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

    func week(year: Int, cw: Int) -> Week {
        data.year(year).week(cw: cw)
    }

    func update(year: Int, week: Week) {
        var yearData = data.year(year)
        yearData.update(week)
        data.update(yearData)
        save()
    }

    func binding(year: Int, cw: Int) -> Binding<Week> {
        Binding(
            get: { self.week(year: year, cw: cw) },
            set: { self.update(year: year, week: $0) }
        )
    }

    var settingsBinding: Binding<RouteSettings> {
        Binding(
            get: { self.data.settings },
            set: { self.data.settings = $0; self.save() }
        )
    }

    /// Kilometer einer Woche: Fahrten × einfache Strecke.
    func kilometers(_ week: Week) -> Double {
        Double(week.trips) * data.settings.kmOneWay
    }

    /// Alle bisher verwendeten Hotelnamen (für Vorschläge).
    func knownHotels(year: Int) -> [String] {
        var seen = [String]()
        for w in data.year(year).weeks {
            for b in w.bookings where !b.hotel.isEmpty && !seen.contains(b.hotel) {
                seen.append(b.hotel)
            }
        }
        return seen.isEmpty ? ["B&B", "InterCity", "SleepInn", "MotelLutz"] : seen
    }

    // MARK: - iCloud-Ordner (Security-Scoped Bookmark)

    /// Vom Nutzer im Dateien-Dialog gewählten Ordner merken.
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

    /// Führt `work` mit Zugriff auf den Jahresordner aus und legt fehlende
    /// Unterordner an: gewählt "008_Holon" → 008_Holon/SteuerHotelFahrtkosten/2026,
    /// gewählt "SteuerHotelFahrtkosten" → …/2026, gewählt "2026" → direkt.
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

    /// Dateiname nach Nomenklatur: CW17_SleepInn_01.pdf
    /// (Index = Position der Buchung in der Woche, 01/02/03 …)
    static func receiptName(cw: Int, hotel: String, index: Int) -> String {
        String(format: "CW%d_%@_%02d.pdf", cw, fileToken(hotel), index)
    }

    /// Hotelname → Dateinamens-Baustein: "B&B" → "BaB", Umlaute ausgeschrieben,
    /// alles andere Nicht-Alphanumerische entfernt.
    static func fileToken(_ s: String) -> String {
        var t = s
        for (k, v) in [("&", "a"), ("ä", "ae"), ("ö", "oe"), ("ü", "ue"),
                       ("Ä", "Ae"), ("Ö", "Oe"), ("Ü", "Ue"), ("ß", "ss")] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        t = t.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return t.isEmpty ? "Hotel" : t
    }

    /// Kopiert ein gewähltes PDF in den Jahresordner unter dem Nomenklatur-Namen.
    /// Gibt den Dateinamen zurück.
    func importReceipt(from source: URL, year: Int, cw: Int, hotel: String, index: Int) throws -> String {
        let name = Store.receiptName(cw: cw, hotel: hotel, index: index)
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

    /// Alle Dateien im Jahresordner (PDF zuerst, dann Rest), alphabetisch.
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

    /// Kopiert einen Beleg in einen temporären Ordner (für Vorschau/Teilen).
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

    // MARK: - Export (CSV-Fallback wie die Excel + JSON-Backup)

    /// Schreibt Berichtsheft_<Jahr>.csv (Auswertung wie die Excel),
    /// Berichtsheft_<Jahr>_Tage.csv (alle Tageseinträge) und
    /// Berichtsheft_<Jahr>.json (komplettes Backup) in den Jahresordner.
    /// Gibt die Namen der geschriebenen Dateien zurück.
    func exportAll(year: Int) throws -> [String] {
        let summary = summaryCSV(year: year)
        let daysCSV = daysCSV(year: year)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = (try? encoder.encode(data.year(year))) ?? Data()

        return try withYearFolder(year: year) { dir -> [String] in
            let files = [
                ("Berichtsheft_\(year).csv", Data(summary.utf8)),
                ("Berichtsheft_\(year)_Tage.csv", Data(daysCSV.utf8)),
                ("Berichtsheft_\(year).json", json),
            ]
            for (name, raw) in files {
                try raw.write(to: dir.appendingPathComponent(name), options: .atomic)
            }
            return files.map { $0.0 }
        }
    }

    /// Auswertung, Spalten wie die Excel plus Fahrten/km/Prüfsumme;
    /// Semikolon + Dezimalkomma, damit deutsches Excel die Datei direkt öffnet.
    func summaryCSV(year: Int) -> String {
        var lines = ["CW;Hotel;Nächte;Summe;PB Tage;HO Tage;FT;U;EZ;Kind_Krank;Krank;Fahrten;km;Tage erfasst"]
        let yearData = data.year(year)
        var tot = (nights: 0, amount: 0.0, pb: 0, ho: 0, ft: 0, u: 0, ez: 0, kk: 0, kr: 0,
                   trips: 0, km: 0.0)

        for cw in 1...CW.weeksIn(year: year) {
            let w = yearData.week(cw: cw)
            if w.isEmpty {
                lines.append("\(cw);;;;;;;;;;;;;")
                continue
            }
            let pb = w.count(.pb), ho = w.count(.ho), ft = w.count(.ft)
            let u = w.count(.urlaub), ez = w.count(.ez)
            let kk = w.count(.kindKrank), kr = w.count(.krank)
            let km = kilometers(w)
            let check = w.isComplete ? "5/5" : "\(w.weekdaysFilled)/5 !"
            lines.append("\(cw);\(w.hotelLabel);\(w.nights);\(Store.german(w.amount));\(pb);\(ho);\(ft);\(u);\(ez);\(kk);\(kr);\(w.trips);\(Store.german(km));\(check)")
            tot = (tot.nights + w.nights, tot.amount + w.amount, tot.pb + pb, tot.ho + ho,
                   tot.ft + ft, tot.u + u, tot.ez + ez, tot.kk + kk, tot.kr + kr,
                   tot.trips + w.trips, tot.km + km)
        }
        lines.append("Summe;;\(tot.nights);\(Store.german(tot.amount));\(tot.pb);\(tot.ho);\(tot.ft);\(tot.u);\(tot.ez);\(tot.kk);\(tot.kr);\(tot.trips);\(Store.german(tot.km));")
        lines.append("")
        lines.append("Fahrtstrecke;\(Store.csvEscape(data.settings.from)) -> \(Store.csvEscape(data.settings.to));einfach;\(Store.german(data.settings.kmOneWay)) km")
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
