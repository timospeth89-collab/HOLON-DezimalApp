import Foundation
import SwiftUI

/// Zentrale Datenhaltung:
/// - JSON lokal in Application Support (funktioniert immer, auch ohne iCloud-Ordner)
/// - gewählter iCloud-Drive-Ordner als Security-Scoped Bookmark
/// - Belege (PDF) + CSV-Export + JSON-Backup landen im Jahresordner
final class Store: ObservableObject {
    @Published var data: AppData = AppData()
    /// Anzeigename des gewählten iCloud-Ordners, nil = noch keiner gewählt.
    @Published var folderName: String?

    private static let bookmarkKey = "berichtsheft.folderBookmark"
    static let taxFolderName = "SteuerHotelFahrtkosten"

    init() {
        load()
        importSeedIfNeeded()
        folderName = resolveBaseFolder()?.lastPathComponent
    }

    /// Beim allerersten Start die 2026-Daten aus der bisherigen Excel
    /// (Berichtsheft - Tabelle.xlsx, CW14–33) vorbefüllen.
    private func importSeedIfNeeded() {
        let flag = "berichtsheft.seedImported"
        guard !UserDefaults.standard.bool(forKey: flag), data.years.isEmpty,
              let url = Bundle.main.url(forResource: "Seed2026", withExtension: "json"),
              let raw = try? Data(contentsOf: url),
              let seed = try? JSONDecoder().decode(YearData.self, from: raw) else { return }
        data.update(seed)
        UserDefaults.standard.set(true, forKey: flag)
        save()
    }

    // MARK: - Lokale Persistenz

    private var localFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Berichtsheft", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }

    private func load() {
        guard let raw = try? Data(contentsOf: localFile),
              let decoded = try? JSONDecoder().decode(AppData.self, from: raw) else { return }
        data = decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? encoder.encode(data) else { return }
        try? raw.write(to: localFile, options: .atomic)
    }

    // MARK: - Wochen lesen/schreiben

    func week(year: Int, cw: Int) -> Week { data.year(year).week(cw: cw) }

    func update(year: Int, week: Week) {
        var yearData = data.year(year)
        yearData.update(week)
        data.update(yearData)
        save()
    }

    func binding(year: Int, cw: Int) -> Binding<Week> {
        Binding(get: { self.week(year: year, cw: cw) },
                set: { self.update(year: year, week: $0) })
    }

    var settingsBinding: Binding<TaxSettings> {
        Binding(get: { self.data.settings },
                set: { self.data.settings = $0; self.save() })
    }

    /// Alle bisher verwendeten Hotelnamen (für Vorschläge und Streckenpflege).
    func knownHotels(year: Int) -> [String] {
        var seen = [String]()
        for w in data.year(year).weeks {
            for b in w.bookings where !b.hotel.isEmpty && !seen.contains(b.hotel) {
                seen.append(b.hotel)
            }
        }
        return seen.isEmpty ? ["B&B", "InterCity", "SleepInn", "MotelLutz"] : seen
    }

    // MARK: - Steuerliche Berechnung
    //
    // Annahme (vom Nutzer bestätigt): Paderborn ist die erste Tätigkeitsstätte.
    // Damit gilt für beide Fahrtarten die Entfernungspauschale auf die
    // **einfache** Strecke, und die Hotelkosten laufen über die doppelte
    // Haushaltsführung — nicht als Reisekosten.

    /// Einfache Strecke Zweitunterkunft -> Arbeit für diese Woche.
    func commuteKm(_ week: Week) -> Double {
        data.settings.km(forHotel: week.primaryHotel)
    }

    /// Entfernungspauschale der Woche für die Fahrten Unterkunft -> Arbeit.
    func commuteAllowance(_ week: Week) -> Double {
        Double(week.commuteDays) * data.settings.allowance(forDistance: commuteKm(week))
    }

    /// Entfernungspauschale der Woche für die Familienheimfahrten.
    func homeAllowance(_ week: Week) -> Double {
        Double(week.homeTrips) * data.settings.allowance(forDistance: data.settings.kmHomeToWork)
    }

    func weekAllowance(_ week: Week) -> Double {
        commuteAllowance(week) + homeAllowance(week)
    }

    struct TaxSummary {
        var nights = 0
        var lodging = 0.0
        var homeTrips = 0
        var homeKm = 0.0
        var homeAllowance = 0.0
        var commuteDays = 0
        var commuteKm = 0.0
        var commuteAllowance = 0.0
        /// Hotels, für die noch keine Strecke hinterlegt ist.
        var hotelsWithoutRoute: [String] = []

        var totalAllowance: Double { homeAllowance + commuteAllowance }
    }

    func taxSummary(year: Int) -> TaxSummary {
        var s = TaxSummary()
        let settings = data.settings
        for w in data.year(year).weeks where !w.isEmpty {
            s.nights += w.nights
            s.lodging += w.amount
            s.homeTrips += w.homeTrips
            s.homeKm += Double(w.homeTrips) * settings.kmHomeToWork
            s.homeAllowance += homeAllowance(w)

            let days = w.commuteDays
            let km = commuteKm(w)
            s.commuteDays += days
            s.commuteKm += Double(days) * km
            s.commuteAllowance += commuteAllowance(w)

            let hotel = w.primaryHotel
            if days > 0, !hotel.isEmpty, km == 0, !s.hotelsWithoutRoute.contains(hotel) {
                s.hotelsWithoutRoute.append(hotel)
            }
        }
        return s
    }

    // MARK: - iCloud-Ordner (Security-Scoped Bookmark)

    func setBaseFolder(_ url: URL) throws {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: Store.bookmarkKey)
        folderName = url.lastPathComponent
    }

    private func resolveBaseFolder() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: Store.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Store.bookmarkKey)
        }
        return url
    }

    @discardableResult
    func withYearFolder<T>(year: Int, _ work: (URL) throws -> T) throws -> T {
        guard let base = resolveBaseFolder() else { throw StoreError.noFolder }
        let ok = base.startAccessingSecurityScopedResource()
        defer { if ok { base.stopAccessingSecurityScopedResource() } }

        var dir = base
        let name = base.lastPathComponent
        if name != "\(year)" {
            if name != Store.taxFolderName {
                dir = dir.appendingPathComponent(Store.taxFolderName, isDirectory: true)
            }
            dir = dir.appendingPathComponent("\(year)", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try work(dir)
    }

    // MARK: - Belege (PDF)

    /// Dateiname nach Nomenklatur: 2026-CW17_SleepInn_01.pdf
    /// Jahr zuerst, damit die Datei auch außerhalb des Jahresordners
    /// eindeutig ist und chronologisch sortiert.
    static func receiptName(year: Int, cw: Int, hotel: String, index: Int) -> String {
        String(format: "%d-CW%02d_%@_%02d.pdf", year, cw, fileToken(hotel), index)
    }

    /// Hotelname -> Dateinamens-Baustein: "B&B" -> "BaB", Umlaute ausgeschrieben.
    static func fileToken(_ s: String) -> String {
        var t = s
        for (k, v) in [("&", "a"), ("ä", "ae"), ("ö", "oe"), ("ü", "ue"),
                       ("Ä", "Ae"), ("Ö", "Oe"), ("Ü", "Ue"), ("ß", "ss")] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        t = t.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return t.isEmpty ? "Hotel" : t
    }

    func importReceipt(from source: URL, year: Int, cw: Int, hotel: String, index: Int) throws -> String {
        let name = Store.receiptName(year: year, cw: cw, hotel: hotel, index: index)
        let ok = source.startAccessingSecurityScopedResource()
        defer { if ok { source.stopAccessingSecurityScopedResource() } }
        try withYearFolder(year: year) { dir in
            let dest = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
        }
        return name
    }

    struct ReceiptInfo: Identifiable {
        var id: String { name }
        let name: String
        let size: Int
        let modified: Date
    }

    func listReceipts(year: Int) -> [ReceiptInfo] {
        (try? withYearFolder(year: year) { dir -> [ReceiptInfo] in
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []
            return urls
                .filter { !$0.hasDirectoryPath }
                .map { url in
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    return ReceiptInfo(name: url.lastPathComponent,
                                       size: values?.fileSize ?? 0,
                                       modified: values?.contentModificationDate ?? .distantPast)
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }) ?? []
    }

    func deleteReceipt(year: Int, name: String) throws {
        try withYearFolder(year: year) { dir in
            try FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    func tempCopyOfReceipt(year: Int, name: String) throws -> URL {
        try withYearFolder(year: year) { dir in
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: tmp.path) {
                try FileManager.default.removeItem(at: tmp)
            }
            try FileManager.default.copyItem(at: dir.appendingPathComponent(name), to: tmp)
            return tmp
        }
    }

    // MARK: - Export

    func exportAll(year: Int) throws -> [String] {
        let summary = summaryCSV(year: year)
        let daysText = daysCSV(year: year)
        let taxText = taxCSV(year: year)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = (try? encoder.encode(data.year(year))) ?? Data()

        return try withYearFolder(year: year) { dir -> [String] in
            let files = [
                ("Berichtsheft_\(year).csv", Data(summary.utf8)),
                ("Berichtsheft_\(year)_Tage.csv", Data(daysText.utf8)),
                ("Berichtsheft_\(year)_Steuer.csv", Data(taxText.utf8)),
                ("Berichtsheft_\(year).json", json),
            ]
            for (name, raw) in files {
                try raw.write(to: dir.appendingPathComponent(name), options: .atomic)
            }
            return files.map { $0.0 }
        }
    }

    /// Auswertung, Spalten wie die Excel plus Fahrten und Prüfsumme.
    func summaryCSV(year: Int) -> String {
        var lines = ["CW;Hotel;Nächte;Summe;PB Tage;HO Tage;FT;U;EZ;Kind_Krank;Krank;Heimfahrten;Fahrtage;km einfach;Pauschale;Tage erfasst"]
        let yearData = data.year(year)
        var tot = (nights: 0, amount: 0.0, pb: 0, ho: 0, ft: 0, u: 0, ez: 0, kk: 0, kr: 0,
                   home: 0, days: 0, allow: 0.0)

        for cw in 1...CW.weeksIn(year: year) {
            let w = yearData.week(cw: cw)
            if w.isEmpty {
                lines.append("\(cw);;;;;;;;;;;;;;;")
                continue
            }
            let pb = w.count(.pb), ho = w.count(.ho), ft = w.count(.ft)
            let u = w.count(.urlaub), ez = w.count(.ez)
            let kk = w.count(.kindKrank), kr = w.count(.krank)
            let allow = weekAllowance(w)
            let check = w.isComplete ? "5/5" : "\(w.weekdaysFilled)/5 !"
            lines.append("\(cw);\(w.hotelLabel);\(w.nights);\(Store.german(w.amount));\(pb);\(ho);\(ft);\(u);\(ez);\(kk);\(kr);\(w.homeTrips);\(w.commuteDays);\(Store.german(commuteKm(w)));\(Store.german(allow));\(check)")
            tot = (tot.nights + w.nights, tot.amount + w.amount, tot.pb + pb, tot.ho + ho,
                   tot.ft + ft, tot.u + u, tot.ez + ez, tot.kk + kk, tot.kr + kr,
                   tot.home + w.homeTrips, tot.days + w.commuteDays, tot.allow + allow)
        }
        lines.append("Summe;;\(tot.nights);\(Store.german(tot.amount));\(tot.pb);\(tot.ho);\(tot.ft);\(tot.u);\(tot.ez);\(tot.kk);\(tot.kr);\(tot.home);\(tot.days);;\(Store.german(tot.allow));")
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Alle Tageseinträge als zweite Tabelle (Berichtsheft-Detail).
    func daysCSV(year: Int) -> String {
        var lines = ["CW;Datum;Tag;Art;Tätigkeit;Ort"]
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy"
        for w in data.year(year).weeks where !w.isEmpty {
            for (i, day) in w.days.enumerated() where !day.isEmpty {
                let date = CW.date(year: year, cw: w.cw, dayIndex: i).map(df.string(from:)) ?? ""
                lines.append("\(w.cw);\(date);\(CW.dayNames[i]);\(day.kind.short);\(Store.csvEscape(day.activity));\(Store.csvEscape(day.location))")
            }
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Zusammenfassung fürs Finanzamt / zum Abtippen in die Steuersoftware.
    func taxCSV(year: Int) -> String {
        let s = taxSummary(year: year)
        let set = data.settings
        var lines = ["Position;Menge;Einheit;Betrag EUR"]
        lines.append("Übernachtungskosten (Zweitunterkunft);\(s.nights);Nächte;\(Store.german(s.lodging))")
        lines.append("Familienheimfahrten;\(s.homeTrips);Fahrten;\(Store.german(s.homeAllowance))")
        lines.append("  davon einfache Strecke;\(Store.german(set.kmHomeToWork));km;")
        lines.append("Fahrten Unterkunft -> erste Tätigkeitsstätte;\(s.commuteDays);Tage;\(Store.german(s.commuteAllowance))")
        lines.append("Entfernungspauschale gesamt;;;\(Store.german(s.totalAllowance))")
        lines.append("")
        lines.append("Annahme;erste Tätigkeitsstätte = \(Store.csvEscape(set.workAddress)); doppelte Haushaltsführung;")
        lines.append("Sätze;\(Store.german(set.rateFirst)) EUR/km bis \(Store.german(set.thresholdKm)) km;\(Store.german(set.rateAbove)) EUR/km darüber;")
        lines.append("Hinweis;Ohne Gewähr - steuerliche Einordnung bitte pruefen lassen;;")
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    static func german(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func csvEscape(_ s: String) -> String {
        if s.contains(";") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    enum StoreError: LocalizedError {
        case noFolder
        var errorDescription: String? {
            switch self {
            case .noFolder:
                return "Kein iCloud-Ordner gewählt. Im Tab „Belege“ zuerst den Ordner auswählen."
            }
        }
    }
}
