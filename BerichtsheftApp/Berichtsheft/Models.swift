import Foundation

/// Art eines Arbeitstags — entspricht den Zähl-Spalten der Excel
/// (PB Tage, HO Tage, FT, U, EZ, Kind_Krank, Krank).
enum DayKind: String, Codable, CaseIterable, Identifiable {
    case pb        = "PB"
    case ho        = "HO"
    case ft        = "FT"
    case urlaub    = "U"
    case ez        = "EZ"
    case kindKrank = "KiKr"
    case krank     = "Kr"
    case frei      = "frei"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pb:        return "PB (vor Ort)"
        case .ho:        return "Home Office"
        case .ft:        return "Feiertag"
        case .urlaub:    return "Urlaub"
        case .ez:        return "Elternzeit"
        case .kindKrank: return "Kind krank"
        case .krank:     return "Krank"
        case .frei:      return "frei"
        }
    }

    var short: String { rawValue }
}

/// Ein Tag der Woche: Art + was gemacht + wo.
struct DayEntry: Codable, Equatable {
    var kind: DayKind = .frei
    var activity: String = ""
    var location: String = ""

    var isEmpty: Bool { kind == .frei && activity.isEmpty && location.isEmpty }
}

/// Eine (unabhängige) Hotelbuchung innerhalb einer CW.
/// Der Index in der Buchungsliste bestimmt den PDF-Namen:
/// CW17_SleepInn_01.pdf, bei zweiter Buchung _02 usw.
struct Booking: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var hotel: String = ""
    var nights: Int = 2
    var amount: Double = 0
    /// Dateiname des abgelegten Belegs im iCloud-Ordner (falls schon importiert).
    var receiptFile: String = ""
}

/// Eine Kalenderwoche: 7 Tage (Mo–So) + Hotelbuchungen.
struct Week: Codable, Equatable {
    var cw: Int
    var days: [DayEntry] = Array(repeating: DayEntry(), count: 7)
    var bookings: [Booking] = []
    var note: String = ""

    init(cw: Int) { self.cw = cw }

    var nights: Int { bookings.reduce(0) { $0 + $1.nights } }
    var amount: Double { bookings.reduce(0) { $0 + $1.amount } }

    func count(_ kind: DayKind) -> Int {
        days.filter { $0.kind == kind }.count
    }

    /// Hotelspalte wie in der Excel: Hotelname(n), oder Wochen-Art wenn kein Hotel.
    var hotelLabel: String {
        let hotels = bookings.map(\.hotel).filter { !$0.isEmpty }
        if !hotels.isEmpty { return hotels.joined(separator: " + ") }
        // Woche ohne Hotel: dominante Tagesart als Label (wie "HO", "EZ", "Urlaub" in der Excel)
        let workdays = days.prefix(5).map(\.kind).filter { $0 != .frei }
        guard let dominant = Dictionary(grouping: workdays, by: { $0 })
            .max(by: { $0.value.count < $1.value.count })?.key else { return "" }
        switch dominant {
        case .urlaub: return "Urlaub"
        case .ez:     return "EZ"
        case .ho:     return "HO"
        default:      return dominant.short
        }
    }

    var isEmpty: Bool {
        bookings.isEmpty && note.isEmpty && days.allSatisfy(\.isEmpty)
    }
}

/// Alle Wochen eines Jahres.
struct YearData: Codable, Equatable {
    var year: Int
    var weeks: [Week] = []

    init(year: Int) { self.year = year }

    func week(cw: Int) -> Week {
        weeks.first(where: { $0.cw == cw }) ?? Week(cw: cw)
    }

    mutating func update(_ week: Week) {
        if let i = weeks.firstIndex(where: { $0.cw == week.cw }) {
            weeks[i] = week
        } else {
            weeks.append(week)
            weeks.sort { $0.cw < $1.cw }
        }
    }
}

struct AppData: Codable, Equatable {
    var years: [YearData] = []

    func year(_ y: Int) -> YearData {
        years.first(where: { $0.year == y }) ?? YearData(year: y)
    }

    mutating func update(_ yearData: YearData) {
        if let i = years.firstIndex(where: { $0.year == yearData.year }) {
            years[i] = yearData
        } else {
            years.append(yearData)
            years.sort { $0.year < $1.year }
        }
    }
}

// MARK: - Kalenderwochen-Helfer (ISO 8601)

enum CW {
    static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone.current
        return c
    }

    /// Anzahl ISO-Wochen im Jahr (52 oder 53) — Woche des 28. Dezember.
    static func weeksIn(year: Int) -> Int {
        let c = calendar
        let dec28 = c.date(from: DateComponents(year: year, month: 12, day: 28))!
        return c.component(.weekOfYear, from: dec28)
    }

    /// Montag einer Kalenderwoche.
    static func monday(year: Int, cw: Int) -> Date? {
        calendar.date(from: DateComponents(weekday: 2, weekOfYear: cw, yearForWeekOfYear: year))
    }

    /// Datum eines Wochentags (0 = Mo … 6 = So) in einer CW.
    static func date(year: Int, cw: Int, dayIndex: Int) -> Date? {
        guard let mon = monday(year: year, cw: cw) else { return nil }
        return calendar.date(byAdding: .day, value: dayIndex, to: mon)
    }

    static var currentYear: Int {
        calendar.component(.yearForWeekOfYear, from: Date())
    }

    static var currentWeek: Int {
        calendar.component(.weekOfYear, from: Date())
    }

    static let dayNames = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
}
