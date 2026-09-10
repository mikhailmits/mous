import Foundation

enum Check {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var failureCount = 0

    static var failures: Int {
        lock.lock(); defer { lock.unlock() }
        return failureCount
    }

    static func equal<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ message: String = "",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        if actual != expected {
            fail("\(actual) != \(expected) \(message)", file: file, line: line)
        }
    }

    static func accuracy(
        _ actual: Double,
        _ expected: Double,
        _ epsilon: Double = 1e-9,
        _ message: String = "",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        if abs(actual - expected) > epsilon {
            fail("\(actual) !~ \(expected) \(message)", file: file, line: line)
        }
    }

    static func `true`(
        _ value: Bool,
        _ message: String = "",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        if !value {
            fail(message.isEmpty ? "expected true" : message, file: file, line: line)
        }
    }

    static func fail(
        _ message: String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        lock.lock()
        failureCount += 1
        lock.unlock()
        fputs("FAIL \(file):\(line) \(message)\n", stderr)
    }
}
