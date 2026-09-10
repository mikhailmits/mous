import Foundation

public enum APIError: Error, Equatable, Sendable {
    case transport
    case timeout
    case undecodable
    case server(status: Int, code: String, detail: String)
    case missingMainAccount

    public var userMessage: String {
        switch self {
        case .transport, .timeout, .undecodable:
            return "Can't reach mous"
        case .server:
            return "Couldn't save — Return to retry"
        case .missingMainAccount:
            return "Can't load totals"
        }
    }

    /// Connection failed; keep retrying. Server/validation errors are not this.
    public var isUnreachable: Bool {
        switch self {
        case .transport, .timeout:
            return true
        case .undecodable, .server, .missingMainAccount:
            return false
        }
    }
}
