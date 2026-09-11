import AppKit

enum MousIcons {
    static let variantFileNames = [
        "logo-variant",
        "logo-variant-1",
        "logo-variant-2",
        "logo-variant-3",
        "logo-variant-4",
        "logo-variant-5",
    ]

    static var directory: URL? {
        if let bundled = Bundle.main.resourceURL {
            let probe = bundled.appendingPathComponent("logo-variant-1.png")
            if FileManager.default.isReadableFile(atPath: probe.path) {
                return bundled
            }
        }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let icon = dir.appendingPathComponent("Icon", isDirectory: true)
            let probe = icon.appendingPathComponent("logo-variant-1.png")
            if FileManager.default.isReadableFile(atPath: probe.path) {
                return icon
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    static var appIcon: NSImage? {
        image(named: "AppIcon", extensions: ["icns"])
    }

    static func variantImages() -> [NSImage] {
        variantFileNames.compactMap { image(named: $0, extensions: ["png"]) }
    }

    private static func image(named name: String, extensions: [String]) -> NSImage? {
        guard let directory else { return nil }
        for ext in extensions {
            let url = directory.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.isReadableFile(atPath: url.path),
               let image = NSImage(contentsOf: url)
            {
                return image
            }
        }
        return nil
    }
}
