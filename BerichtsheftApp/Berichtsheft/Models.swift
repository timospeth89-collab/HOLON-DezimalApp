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

    init() {}

    enum CodingKeys: String, CodingKey { case kind, activity, location }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(DayKind.self, forKey: .kind) ?? .frei
        activity = try c.decodeIfPresent(String.self, forKey: .activity) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
    }
}

/// Eine (unabhängige) Hotelbuchung innerhalb einer CW.
/// Der Index in der Buchungsliste bestimmt den PDF-Namen:
/// 2026-CW17_SleepInn_01.pdf, bei zweiter Buchung _02 usw.
struct Booking: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var hotel: String = ""
    var nights: Int = 2
    var amount: Double = 0
    /// Dateiname des abgelegten Belegs im iCloud-Ordner (falls schon importiert).
    var receiptFile: String = ""

    init() {}

    enum CodingKeys: String, CodingKey { case id, hotel, nights, amount, receiptFile }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        hotel = try c.decodeIfPresent(String.self, forKey: .hotel) ?? ""
        nights = try c.decodeIfPresent(Int.self, forKey: .nights) ?? 0
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        receiptFile = try c.decodeIfPresent(String.self, forKey: .receiptFile) ?? ""
    }
}

/// Eine Kalenderwoche: 7 Tage (Mo–So), Hotelbuchungen, Fahrten.
struct Week: Codable, Equatable {
    var cw: Int
    var days: [DayEntry] = Array(repeating: DayEntry(), count: 7)
    var bookings: [Booking] = []
    var note: String = ""
    /// Familienheimfahrten dieser Woche (doppelte Haushaltsführung):
    /// Wohnung am Lebensmittelpunkt <-> Zweitunterkunft, i. d. R. 1 pro Woche.
    var homeTrips: Int = 0
    /// Tage mit Fahrt Zweitunterkunft -> erste Tätigkeitsstätte.
    /// nil = automatisch die PB-Tage der Woche verwenden.
    var commuteDaysOverride: Int?

    init(cw: Int) { self.cw = cw }

    enum CodingKeys: String, CodingKey {
        case cw, days, bookings, note, homeTrips, commuteDaysOverride, trips
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cw = try c.decode(Int.self, forKey: .cw)
        var d = try c.decodeIfPresent([DayEntry].self, forKey: .days) ?? []
        while d.count < 7 { d.append(DayEntry()) }
        days = Array(d.prefix(7))
        bookings = try c.decodeIfPresent([Booking].self, forKey: .bookings) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        commuteDaysOverride = try c.decodeIfPresent(Int.self, forKey: .commuteDaysOverride)
        if let h = try c.decodeIfPresent(Int.self, forKey: .homeTrips) {
            homeTrips = h
        } else if let legacy = try c.decodeIfPresent(Int.self, forKey: .trips) {
            // Altbestand: dort waren 2 = einmal hin und zurück, also 1 Heimfahrt.
            homeTrips = max(0, legacy / 2)
        }
    }

    /// Explizit, weil `trips` nur noch ein Lese-Schlüssel für Altbestände ist
    /// und keine gespeicherte Eigenschaft mehr hat — sonst kann Swift
    /// `encode(to:)` nicht synthetisieren.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cw, forKey: .cw)
        try c.encode(days, forKey: .days)
        try c.encode(bookings, forKey: .bookings)
        try c.encode(note, forKey: .note)
        try c.encode(homeTrips, forKey: .homeTrips)
        try c.encodeIfPresent(commuteDaysOverride, forKey: .commuteDaysOverride)
    }

    var nights: Int { bookings.reduce(0) { $0 + $1.nights } }
    var amount: Double { bookings.reduce(0) { $0 + $1.amount } }

    func count(_ kind: DayKind) -> Int {
        days.filter { $0.kind == kind }.count
    }

    /// Tage mit Fahrt zur ersten Tätigkeitsstätte (Vorgabe: PB-Tage).
    var commuteDays: Int { commuteDaysOverride ?? count(.pb) }

    /// Hotel, auf das sich die Tagesstrecke bezieht (erste Buchung der Woche).
    var primaryHotel: String { bookings.first(where: { !$0.hotel.isEmpty })?.hotel ?? "" }

    /// Prüfsumme: Mo–Fr sollen immer ein Attribut (≠ frei) haben.
    var weekdaysFilled: Int { days.prefix(5).filter { $0.kind != .frei }.count }
    var isComplete: Bool { weekdaysFilled == 5 }

    /// Hotelspalte wie in der Excel: Hotelname(n), oder Wochen-Art wenn kein Hotel.
    var hotelLabel: String {
        let hotels = bookings.map(\.hotel).filter { !$0.isEmpty }
        if !hotels.isEmpty { return hotels.joined(separator: " + ") }
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
        bookings.isEmpty && note.isEmpty && homeTrips == 0
            && commuteDaysOverride == nil && days.allSatisfy(\.isEmpty)
    }
}

/// Einfache Strecke von einem Hotel zur ersten Tätigkeitsstätte.
struct HotelRoute: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var hotel: String = ""
    var km: Double = 0

    init(hotel: String = "", km: Double = 0) { self.hotel = hotel; self.km = km }

    enum CodingKeys: String, CodingKey { case id, hotel, km }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        hotel = try c.decodeIfPresent(String.self, forKey: .hotel) ?? ""
        km = try c.decodeIfPresent(Double.self, forKey: .km) ?? 0
    }
}

/// Eingaben für die steuerliche Auswertung.
/// Annahme laut Nutzer: Paderborn ist die **erste Tätigkeitsstätte**,
/// die Hotelübernachtungen laufen damit über die doppelte Haushaltsführung.
struct TaxSettings: Codable, Equatable {
    var homeAddress: String = "Weinbergstr. 27"
    var workAddress: String = "Elsener Str. 95, 33102 Paderborn"
    /// Einfache Strecke Wohnung <-> erste Tätigkeitsstätte (Familienheimfahrt).
    var kmHomeToWork: Double = 0
    /// Je Hotel die einfache Strecke zur ersten Tätigkeitsstätte.
    var hotelRoutes: [HotelRoute] = []
    /// Entfernungspauschale: Satz für die ersten `thresholdKm` Kilometer …
    var rateFirst: Double = 0.30
    /// … und ab dem Kilometer danach.
    var rateAbove: Double = 0.38
    var thresholdKm: Double = 20

    init() {}

    enum CodingKeys: String, CodingKey {
        case homeAddress, workAddress, kmHomeToWork, hotelRoutes
        case rateFirst, rateAbove, thresholdKm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        homeAddress = try c.decodeIfPresent(String.self, forKey: .homeAddress) ?? "Weinbergstr. 27"
        workAddress = try c.decodeIfPresent(String.self, forKey: .workAddress) ?? "Elsener Str. 95, 33102 Paderborn"
        kmHomeToWork = try c.decodeIfPresent(Double.self, forKey: .kmHomeToWork) ?? 0
        hotelRoutes = try c.decodeIfPresent([HotelRoute].self, forKey: .hotelRoutes) ?? []
        rateFirst = try c.decodeIfPresent(Double.self, forKey: .rateFirst) ?? 0.30
        rateAbove = try c.decodeIfPresent(Double.self, forKey: .rateAbove) ?? 0.38
        thresholdKm = try c.decodeIfPresent(Double.self, forKey: .thresholdKm) ?? 20
    }

    /// Entfernungspauschale für **eine** Fahrt über `distance` km einfacher Strecke.
    func allowance(forDistance distance: Double) -> Double {
        guard distance > 0 else { return 0 }
        let first = min(distance, thresholdKm) * rateFirst
        let above = max(0, distance - thresholdKm) * rateAbove
        return first + above
    }

    func km(forHotel hotel: String) -> Double {
        hotelRoutes.first(where: { $0.hotel.caseInsensitiveCompare(hotel) == .orderedSame })?.km ?? 0
    }
}

/// Alle Wochen eines Jahres.
struct YearData: Codable, Equatable {
    var year: Int
    var weeks: [Week] = []

    init(year: Int) { self.year = year }

    enum CodingKeys: String, CodingKey { case year, weeks }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        year = try c.decode(Int.self, forKey: .year)
        weeks = try c.decodeIfPresent([Week].self, forKey: .weeks) ?? []
    }

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
    var settings: TaxSettings = TaxSettings()

    init() {}

    enum CodingKeys: String, CodingKey { case years, settings }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        years = try c.decodeIfPresent([YearData].self, forKey: .years) ?? []
        settings = try c.decodeIfPresent(TaxSettings.self, forKey: .settings) ?? TaxSettings()
    }

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

    static func weeksIn(year: Int) -> Int {
        let c = calendar
        let dec28 = c.date(from: DateComponents(year: year, month: 12, day: 28))!
        return c.component(.weekOfYear, from: dec28)
    }

    static func monday(year: Int, cw: Int) -> Date? {
        calendar.date(from: DateComponents(weekday: 2, weekOfYear: cw, yearForWeekOfYear: year))
    }

    static func date(year: Int, cw: Int, dayIndex: Int) -> Date? {
        guard let mon = monday(year: year, cw: cw) else { return nil }
        return calendar.date(byAdding: .day, value: dayIndex, to: mon)
    }

    static var currentYear: Int { calendar.component(.yearForWeekOfYear, from: Date()) }
    static var currentWeek: Int { calendar.component(.weekOfYear, from: Date()) }

    static let dayNames = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
}
