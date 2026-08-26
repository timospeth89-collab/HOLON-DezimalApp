import SwiftUI

/// Tab 2: Auswertung wie die Excel — eine Zeile pro CW,
/// Spalten CW / Hotel / Nächte / Summe / PB / HO / FT / U / EZ / KiKr / Kr,
/// unten die Jahressumme. Export schreibt CSV + JSON in den iCloud-Ordner.
struct SummaryView: View {
    @EnvironmentObject private var store: Store
    @State private var year = CW.currentYear
    @State private var exportResult: String?

    private var yearData: YearData { store.data.year(year) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statCards
                    table
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Auswertung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Jahr", selection: $year) {
                            ForEach(yearOptions, id: \.self) { Text(String($0)).tag($0) }
                        }
                    } label: {
                        Text(String(year)).font(.headline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        export()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .alert("Export", isPresented: Binding(
                get: { exportResult != nil },
                set: { if !$0 { exportResult = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportResult ?? "")
            }
        }
    }

    private var yearOptions: [Int] {
        let current = CW.currentYear
        let stored = store.data.years.map(\.year)
        return Array(Set(stored + [current - 1, current, current + 1])).sorted()
    }

    private func export() {
        do {
            let files = try store.exportAll(year: year)
            exportResult = "In den iCloud-Ordner geschrieben:\n" + files.joined(separator: "\n")
        } catch {
            exportResult = error.localizedDescription
        }
    }

    // MARK: Jahres-Kacheln

    private var totals: (nights: Int, amount: Double, pb: Int, ho: Int, home: Int, allowance: Double) {
        yearData.weeks.reduce((0, 0.0, 0, 0, 0, 0.0)) { acc, w in
            (acc.0 + w.nights, acc.1 + w.amount, acc.2 + w.count(.pb), acc.3 + w.count(.ho),
             acc.4 + w.homeTrips, acc.5 + store.weekAllowance(w))
        }
    }

    private var statCards: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                statCard("Nächte", "\(totals.nights)")
                statCard("Hotel €", Store.german(totals.amount))
                statCard("Pauschale €", Store.german(totals.allowance))
            }
            HStack(spacing: 10) {
                statCard("PB Tage", "\(totals.pb)")
                statCard("HO Tage", "\(totals.ho)")
                statCard("Heimfahrten", "\(totals.home)")
            }
        }
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.green)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    // MARK: Tabelle

    /// Zähl-Spalten der Tabelle. Bewusst ein Struct statt eines Tupels —
    /// Swift kennt keine KeyPaths auf Tupel-Elemente (`id: \.0`).
    private struct CountColumn: Identifiable {
        let title: String
        let kind: DayKind
        var id: String { title }
    }

    private let countCols: [CountColumn] = [
        .init(title: "PB", kind: .pb), .init(title: "HO", kind: .ho),
        .init(title: "DR", kind: .dienstreise), .init(title: "FT", kind: .ft),
        .init(title: "U", kind: .urlaub),
        .init(title: "EZ", kind: .ez), .init(title: "KiKr", kind: .kindKrank),
        .init(title: "Kr", kind: .krank),
    ]

    private var table: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("CW").gridColumnAlignment(.trailing)
                    Text("✓")
                    Text("Hotel")
                    Text("Nächte").gridColumnAlignment(.trailing)
                    Text("Summe").gridColumnAlignment(.trailing)
                    ForEach(countCols) { col in
                        Text(col.title).gridColumnAlignment(.trailing)
                    }
                    Text("Heim").gridColumnAlignment(.trailing)
                    Text("Tage").gridColumnAlignment(.trailing)
                    Text("€").gridColumnAlignment(.trailing)
                }
                .font(.caption.bold())
                .foregroundStyle(Theme.secondaryText)

                Divider().overlay(Theme.cardBorder)

                ForEach(1...CW.weeksIn(year: year), id: \.self) { cw in
                    let w = yearData.week(cw: cw)
                    GridRow {
                        Text("\(cw)")
                        // Prüfsumme: Mo–Fr müssen 5 Attribute haben
                        if w.isEmpty {
                            Text("")
                        } else {
                            Image(systemName: w.isComplete ? "checkmark" : "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(w.isComplete ? Theme.green : Color(red: 1.0, green: 0.72, blue: 0.3))
                        }
                        Text(w.isEmpty ? "–" : w.hotelLabel)
                            .lineLimit(1)
                            .frame(minWidth: 90, alignment: .leading)
                        Text(w.nights > 0 ? "\(w.nights)" : "")
                        Text(w.amount > 0 ? Store.german(w.amount) : "")
                        ForEach(countCols) { col in
                            let n = w.count(col.kind)
                            Text(n > 0 ? "\(n)" : "")
                                .foregroundStyle(Theme.kindColor(col.kind))
                        }
                        Text(w.homeTrips > 0 ? "\(w.homeTrips)" : "")
                        Text(w.commuteDays > 0 ? "\(w.commuteDays)" : "")
                        Text(store.weekAllowance(w) > 0 ? Store.german(store.weekAllowance(w)) : "")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(w.isEmpty ? Theme.secondaryText.opacity(0.5) : .primary)
                }

                Divider().overlay(Theme.cardBorder)

                GridRow {
                    Text("Σ")
                    Text("")
                    Text("")
                    Text("\(sumNights)")
                    Text(Store.german(sumAmount))
                    ForEach(countCols) { col in
                        Text("\(sumCount(col.kind))")
                    }
                    Text("\(totals.home)")
                    Text("\(sumCommuteDays)")
                    Text(Store.german(totals.allowance))
                }
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(Theme.green)
            }
            .padding(.vertical, 4)
        }
        .card()
    }

    private var sumNights: Int { yearData.weeks.reduce(0) { $0 + $1.nights } }
    private var sumAmount: Double { yearData.weeks.reduce(0) { $0 + $1.amount } }
    private var sumCommuteDays: Int { yearData.weeks.reduce(0) { $0 + $1.commuteDays } }
    private func sumCount(_ kind: DayKind) -> Int {
        yearData.weeks.reduce(0) { $0 + $1.count(kind) }
    }
}
