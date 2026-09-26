import AppKit
import Foundation
import MousCore
import SwiftUI

extension UpdateChecker {
    struct Release: Equatable, Sendable {
        var tagName: String
        var displayVersion: String
        var htmlURL: URL
        var dmgURL: URL?

        var openURL: URL { dmgURL ?? htmlURL }
    }

    enum Outcome: Equatable, Sendable {
        case upToDate
        case available(Release)
        case failed
    }

    static func parseRelease(data: Data) -> Release? {
        guard let payload = try? JSONDecoder().decode(LatestPayload.self, from: data) else {
            return nil
        }
        return release(from: payload)
    }

    static func checkLatest(installed: String = installedVersion()) async -> Outcome {
        guard let apiURL = GitHubUpdate.latestAPIURL,
              apiURL.scheme?.lowercased() == "https"
        else {
            return .failed
        }
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = GitHubUpdate.requestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mous/\(installed) (https://github.com/mikhailmits/mous)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        return await withTaskGroup(of: Outcome?.self) { group in
            group.addTask {
                await Self.fetchLatest(request: request, installed: installed)
            }
            group.addTask {
                let nanos = UInt64((GitHubUpdate.requestTimeout + 1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return Task.isCancelled ? nil : .failed
            }
            var outcome: Outcome = .failed
            for await result in group {
                guard let result else { continue }
                outcome = result
                group.cancelAll()
                break
            }
            return outcome
        }
    }

    private static func fetchLatest(request: URLRequest, installed: String) async -> Outcome {
        do {
            let (data, response) = try await GitHubUpdate.session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  Self.isTrustedGitHubURL(response.url),
                  let release = parseRelease(data: data)
            else {
                return .failed
            }
            if isRemoteNewer(installed: installed, remote: release.tagName) {
                return .available(release)
            }
            return .upToDate
        } catch {
            return .failed
        }
    }

    private static func release(from payload: LatestPayload) -> Release? {
        let tag = payload.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return nil }
        guard let htmlURL = httpsURL(payload.htmlURL) ?? GitHubUpdate.releasesPageURL else {
            return nil
        }
        let dmgURL = payload.assets
            .first { $0.name.lowercased().hasSuffix(".dmg") }
            .flatMap { httpsURL($0.browserDownloadURL) }
        return Release(
            tagName: tag,
            displayVersion: normalizedVersion(tag),
            htmlURL: htmlURL,
            dmgURL: dmgURL
        )
    }

    /// Only https GitHub hosts — never follow redirects or assets onto arbitrary download domains.
    static func httpsURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), isTrustedGitHubURL(url) else { return nil }
        return url
    }

    static func isTrustedGitHubURL(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https" else { return false }
        let host = (url.host ?? "").lowercased()
        return host == "github.com"
            || host.hasSuffix(".github.com")
            || host == "githubusercontent.com"
            || host.hasSuffix(".githubusercontent.com")
    }

    private struct LatestPayload: Decodable {
        var tagName: String
        var htmlURL: String
        var assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tagName = try container.decode(String.self, forKey: .tagName)
            htmlURL = try container.decode(String.self, forKey: .htmlURL)
            assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        }
    }

    private struct Asset: Decodable {
        var name: String
        var browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}

private enum GitHubUpdate {
    static let requestTimeout: TimeInterval = 8
    static let latestAPIURL = URL(string: "https://api.github.com/repos/mikhailmits/mous/releases/latest")
    static let releasesPageURL = URL(string: "https://github.com/mikhailmits/mous/releases")
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout
        config.waitsForConnectivity = false
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
}

struct UpdatesSettingsField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var status: Status = .idle
    @State private var release: UpdateChecker.Release?
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 8) {
            Button(action: check) {
                row(title: checkTitle, trailing: checkTrailing)
            }
            .buttonStyle(.plain)
            .disabled(status == .checking)
            .accessibilityLabel(checkTitle)
            .accessibilityIdentifier("Check for updates")
            .accessibilityValue(checkTrailing)
            .accessibilityHint("Looks up the latest Mous release on GitHub.")

            if let release, case .available = status {
                Button {
                    open(release.openURL)
                } label: {
                    row(title: "Update", trailing: release.displayVersion)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Update")
                .accessibilityValue(release.displayVersion)
                .accessibilityHint("Opens the latest disk image, or the GitHub release page.")
                .transition(.opacity)
            }
        }
        .animation(MousMotion.quick(reduceMotion: reduceMotion), value: showsUpdate)
        .animation(MousMotion.quick(reduceMotion: reduceMotion), value: status)
        .onDisappear {
            checkTask?.cancel()
            checkTask = nil
        }
    }

    private var showsUpdate: Bool {
        if case .available = status { return true }
        return false
    }

    private var checkTitle: String {
        switch status {
        case .failed:
            return "Retry"
        default:
            return "Check for updates"
        }
    }

    private var checkTrailing: String {
        switch status {
        case .idle:
            return UpdateChecker.installedVersion()
        case .checking:
            return "Checking…"
        case .upToDate:
            return "✓ Up to date"
        case .available(let version):
            return "\(version) available"
        case .failed:
            return "Couldn’t check"
        }
    }

    private func row(title: String, trailing: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(trailing)
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(trackFill)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var trackFill: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.055))
    }

    private func check() {
        guard status != .checking else { return }
        status = .checking
        let installed = UpdateChecker.installedVersion()
        checkTask?.cancel()
        checkTask = Task { @MainActor in
            let outcome = await UpdateChecker.checkLatest(installed: installed)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .upToDate:
                release = nil
                status = .upToDate
            case .available(let found):
                release = found
                status = .available(found.displayVersion)
            case .failed:
                release = nil
                status = .failed
            }
        }
    }

    private func open(_ url: URL) {
        guard UpdateChecker.isTrustedGitHubURL(url) else { return }
        NSWorkspace.shared.open(url)
    }

    private enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case failed
    }
}
