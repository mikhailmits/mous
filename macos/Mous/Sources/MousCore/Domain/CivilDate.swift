import Foundation

public struct CivilDate: Equatable, Hashable, Sendable, Comparable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static func localToday(
        timeZone: TimeZone = .current,
        now: Date = Date()
    ) -> CivilDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return CivilDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    public static func localMonthStart(
        timeZone: TimeZone = .current,
        now: Date = Date()
    ) -> CivilDate {
        let today = localToday(timeZone: timeZone, now: now)
        return CivilDate(year: today.year, month: today.month, day: 1)
    }

    public var unixUTCMidnight: Int {
        var parts = DateComponents()
        parts.calendar = Calendar(identifier: .gregorian)
        parts.timeZone = TimeZone(secondsFromGMT: 0)
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 0
        parts.minute = 0
        parts.second = 0
        let date = parts.date ?? Date(timeIntervalSince1970: 0)
        return Int(date.timeIntervalSince1970)
    }

    public static func fromUnixUTCMidnight(_ unix: Int) -> CivilDate {
        let date = Date(timeIntervalSince1970: TimeInterval(unix))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return CivilDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }
}
