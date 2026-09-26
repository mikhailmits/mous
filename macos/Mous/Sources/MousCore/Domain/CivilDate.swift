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

    /// UTC midnight for this civil day. Built with an explicit UTC gregorian
    /// calendar so a system timezone cannot shift the day (off-by-one).
    /// `YYYY-MM-DD` for the `mou` CLI. Not locale-dependent.
    public var isoDay: String {
        String(format: "%04d-%02d-%02d", CInt(year), CInt(month), CInt(day))
    }

    public var unixUTCMidnight: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 0,
            minute: 0,
            second: 0
        )
        let date = calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
        return Int(date.timeIntervalSince1970.rounded())
    }

    public static func fromUnixUTCMidnight(_ unix: Int) -> CivilDate {
        let date = Date(timeIntervalSince1970: TimeInterval(unix))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return CivilDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }
}
