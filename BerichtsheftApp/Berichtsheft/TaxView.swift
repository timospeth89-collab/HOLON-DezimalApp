import SwiftUI

/// Tab 3: steuerliche Auswertung + die Eingaben, von denen sie abhängt.
///
/// Annahme: Paderborn ist die **erste Tätigkeitsstätte**. Damit gilt für
/// beide Fahrtarten die Entfernungspauschale auf die einfache Strecke,
/// und die Hotelkosten laufen über die doppelte Haushaltsführung.
struct TaxView: View {
    @EnvironmentObject private var store: Store
    @State private var year = CW.currentYear

    private var summary: Store.TaxSummary { store.taxSummary(year: year) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    resultCard
                    routeCard
                    hotelCard
                    rateCard
                    disclaimerCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Steuer")
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
            }
            .onAppear { ensureHotelRoutes() }
        }
    }

    private var yearOptions: [Int] {
        let current = CW.currentYear
        let stored = store.data.years.map(\.year)
        return Array(Set(stored + [current - 1, current, current + 1])).sorted()
    }

    // MARK: Ergebnis

    private var resultCard: some View {
        let s = summary
        return VStack(alignment: .leading, spacing: 10) {
            Text("Zusammenfassung \(String(year))").font(.headline)

            row("Übernachtung Zweitunterkunft",
                detail: "\(s.nights) Nächte",
                value: Store.german(s.lodging))
            Divider().overlay(Theme.cardBorder)
            row("Familienheimfahrten",
                detail: "\(s.homeTrips) × \(Store.german(store.data.settings.kmHomeToWork)) km",
                value: Store.german(s.homeAllowance))
            Divider().overlay(Theme.cardBorder)
            row("Unterkunft → Arbeit",
                detail: "\(s.commuteDays) Tage",
                value: Store.german(s.commuteAllowance))
            Divider().overlay(Theme.cardBorder)
            row("Entfernungspauschale gesamt",
                detail: "",
                value: Store.german(s.totalAllowance),
                bold: true)

            if !s.hotelsWithoutRoute.isEmpty {
                Label("Ohne Strecke: \(s.hotelsWithoutRoute.joined(separator: ", ")) — unten eintragen, sonst fehlen diese Fahrten.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.3))
            }
        }
        .card()
    }

    private func row(_ title: String, detail: String, value: String, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(bold ? .subheadline.bold() : .subheadline)
                if !detail.isEmpty {
                    Text(detail).font(.caption2).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            Text("\(value) €")
                .font(.system(.subheadline, design: .monospaced).weight(bold ? .bold : .regular))
                .foregroundStyle(bold ? Theme.green : .primary)
        }
    }

    // MARK: Strecke Wohnung → Arbeit

    private var routeCard: some View {
        let settings = store.settingsBinding
        return VStack(alignment: .leading, spacing: 8) {
            Text("Familienheimfahrt").font(.headline)
            field("Von", text: settings.homeAddress, placeholder: "Weinbergstr. 27, 63936 Schneeberg")
            field("Nach", text: settings.workAddress, placeholder: "Elsener Str. 95, Paderborn")
            HStack {
                Text("km").font(.caption).foregroundStyle(Theme.secondaryText).frame(width: 38, alignment: .leading)
                TextField("0", value: settings.kmHomeToWork, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .frame(width: 84)
                    .textFieldStyle(.roundedBorder)
                Text("einfache Strecke").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Text("Eine Heimfahrt pro Woche ist bei doppelter Haushaltsführung ansetzbar — gerechnet wird die einfache Strecke.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(Theme.secondaryText).frame(width: 38, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.subheadline)
                .textFieldStyle(.plain)
        }
    }

    // MARK: Strecken je Hotel

    private var hotelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hotel → Arbeit").font(.headline)
            Text("Tagesstrecke je Unterkunft, einfache Strecke. Die App nimmt für jede Woche das Hotel der ersten Buchung.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)

            ForEach(store.data.settings.hotelRoutes) { route in
                if let i = store.data.settings.hotelRoutes.firstIndex(where: { $0.id == route.id }) {
                    hotelRow(index: i)
                    if route.id != store.data.settings.hotelRoutes.last?.id {
                        Divider().overlay(Theme.cardBorder)
                    }
                }
            }

            Button {
                store.data.settings.hotelRoutes.append(HotelRoute())
                store.save()
            } label: {
                Label("Hotel hinzufügen", systemImage: "plus.circle.fill")
                    .font(.subheadline.bold())
            }
        }
        .card()
    }

    private func hotelRow(index: Int) -> some View {
        let routes = store.settingsBinding.hotelRoutes
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Hotel", text: routes[index].hotel)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                TextField("0", value: routes[index].km, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                Text("km").font(.caption).foregroundStyle(Theme.secondaryText)
                Button(role: .destructive) {
                    store.data.settings.hotelRoutes.remove(at: index)
                    store.save()
                } label: {
                    Image(systemName: "trash").font(.caption)
                }
            }
            TextField("Adresse (Gedächtnisstütze fürs km-Ablesen in Maps)",
                      text: routes[index].address)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .textFieldStyle(.plain)
        }
    }

    /// Vom Nutzer nachgereichte Adressen der 2026 gebuchten Hotels — nur zur
    /// Anzeige, damit die Beleg-PDFs nicht erneut durchsucht werden müssen.
    /// Kilometer bleiben Handarbeit: Kartendienste sind aus dieser Umgebung
    /// heraus nicht erreichbar, die Zahl muss der Nutzer selbst ablesen.
    private static let knownAddresses: [String: String] = [
        "B&B": "Bahnhofstraße 31, 33102 Paderborn",
        "InterCity": "Bahnhofstraße 29, 33102 Paderborn",
        "SleepInn": "Marienloher Str. 50, 33104 Paderborn",
        "MotelLutz": "An d. Talle 78a, 33102 Paderborn",
    ]

    /// Für jedes bekannte Hotel eine Zeile anlegen, damit nichts vergessen wird.
    private func ensureHotelRoutes() {
        var changed = false
        for hotel in store.knownHotels(year: year) {
            let exists = store.data.settings.hotelRoutes.contains {
                $0.hotel.caseInsensitiveCompare(hotel) == .orderedSame
            }
            if !exists {
                let address = Self.knownAddresses.first {
                    $0.key.caseInsensitiveCompare(hotel) == .orderedSame
                }?.value ?? ""
                store.data.settings.hotelRoutes.append(HotelRoute(hotel: hotel, address: address))
                changed = true
            }
        }
        if changed { store.save() }
    }

    // MARK: Sätze

    private var rateCard: some View {
        let settings = store.settingsBinding
        return VStack(alignment: .leading, spacing: 8) {
            Text("Entfernungspauschale").font(.headline)
            HStack {
                Text("bis").font(.caption).foregroundStyle(Theme.secondaryText)
                TextField("20", value: settings.thresholdKm, format: .number.precision(.fractionLength(0...0)))
                    .keyboardType(.decimalPad).frame(width: 52).textFieldStyle(.roundedBorder)
                Text("km:").font(.caption).foregroundStyle(Theme.secondaryText)
                TextField("0,30", value: settings.rateFirst, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad).frame(width: 64).textFieldStyle(.roundedBorder)
                Text("€/km").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            HStack {
                Text("darüber:").font(.caption).foregroundStyle(Theme.secondaryText)
                TextField("0,38", value: settings.rateAbove, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad).frame(width: 64).textFieldStyle(.roundedBorder)
                Text("€/km").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Text("Voreingestellt sind 0,30 € bis 20 km und 0,38 € darüber. Bitte für das jeweilige Jahr gegenprüfen und hier anpassen.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Ohne Gewähr", systemImage: "info.circle")
                .font(.subheadline.bold())
            Text("""
            Die App rechnet nach der Annahme: Paderborn ist erste Tätigkeitsstätte, \
            die Hotelübernachtungen laufen über die doppelte Haushaltsführung. \
            Dort gelten eigene Regeln — Höchstbetrag für die Unterkunft, \
            Verpflegungspauschale nur in den ersten drei Monaten, Nachweis des \
            eigenen Hausstands. Ob und ab wann das bei dir greift, gehört einmal \
            von deinem Steuerberater bestätigt. Das hier ist keine Steuerberatung.
            """)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }
}
