import SwiftUI

/// One motion language for the popup. Reduce Motion stays a short fade.
enum MousMotion {
    static func spring(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .spring(duration: 0.55, bounce: 0)
    }

    static func fade(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .easeInOut(duration: 0.4)
    }

    static func quick(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .easeInOut(duration: 0.4)
    }

    /// Amount ticks and commit roll — slightly longer than `quick`.
    static func tick(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .easeInOut(duration: 0.45)
    }
}
