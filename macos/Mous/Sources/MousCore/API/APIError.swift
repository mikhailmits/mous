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
        case .server(let status, _, _):
            // Conflict, validation, and timeout are not a safe automatic retry.
            // A timed-out POST may already have been saved.
            if status == 408 || status == 409 || status == 422 {
                return "Couldn't save"
            }
            return "Couldn't save — Return to retry"
        case .missingMainAccount:
            return "Can't load totals"
        }
    }

    /// Connection failed; keep retrying. 409/422/5xx `.server` and decode errors are not this.
    public var isUnreachable: Bool {
        switch self {
        case .transport, .timeout:
            return true
        case .undecodable, .server, .missingMainAccount:
            return false
        }
    }
}
