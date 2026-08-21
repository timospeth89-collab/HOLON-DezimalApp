import SwiftUI
import UniformTypeIdentifiers

/// Tab 1: eine Kalenderwoche erfassen — 7 Tage (Art, Tätigkeit, Ort)
/// plus Hotelbuchungen mit Beleg-Ablage.
struct WeekView: View {
    @EnvironmentObject private var store: Store
    @State private var year = CW.currentYear
    @State private var cw = CW.currentWeek

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    weekPicker
                    WeekEditor(week: store.binding(year: year, cw: cw), year: year, cw: cw)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Berichtsheft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        NotificationCenter.default.post(name: .showWalkthrough, object: nil)
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Jahr", selection: $year) {
                            ForEach(yearOptions, id: \.self) { Text(String($0)).tag($0) }
                        }
                    } label: {
                        Text(String(year)).font(.headline)
                    }
                }
            }
        }
        .onChange(of: year) { _, newYear in
            cw = min(cw, CW.weeksIn(year: newYear))
        }
    }

    private var yearOptions: [Int] {
        let current = CW.currentYear
        let stored = store.data.years.map(\.year)
        return Array(Set(stored + [current - 1, current, current + 1])).sorted()
    }

    private var weekPicker: some View {
        HStack {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left").font(.title3.bold())
            }
            Spacer()
            VStack(spacing: 2) {
                Menu {
                    Picker("CW", selection: $cw) {
                        ForEach(1...CW.weeksIn(year: year), id: \.self) { Text("CW \($0)").tag($0) }
                    }
                } label: {
                    Text("CW \(cw)")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.green)
                }
                Text(rangeLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button { step(1) } label: {
                Image(systemName: "chevron.right").font(.title3.bold())
            }
        }
        .card()
    }

    private func step(_ delta: Int) {
        let next = cw + delta
        if next < 1 {
            year -= 1
            cw = CW.weeksIn(year: year)
        } else if next > CW.weeksIn(year: year) {
            year += 1
            cw = 1
        } else {
            cw = next
        }
    }

    private var rangeLabel: String {
        let df = DateFormatter()
        df.dateFormat = "dd.MM."
        let dfYear = DateFormatter()
        dfYear.dateFormat = "dd.MM.yyyy"
        guard let mon = CW.date(year: year, cw: cw, dayIndex: 0),
              let sun = CW.date(year: year, cw: cw, dayIndex: 6) else { return "" }
        return "\(df.string(from: mon)) – \(dfYear.string(from: sun))"
    }
}

struct WeekEditor: View {
    @Binding var week: Week
    let year: Int
    let cw: Int
    @EnvironmentObject private var store: Store

    @State private var importBookingID: UUID?
    @State private var showPDFImporter = false
    @State private var errorMessage: String?

    private func dayBinding(_ i: Int) -> Binding<DayEntry> {
        Binding(get: { week.days[i] }, set: { week.days[i] = $0 })
    }

    private func bookingBinding(_ index: Int) -> Binding<Booking> {
        Binding(get: { week.bookings[index] }, set: { week.bookings[index] = $0 })
    }

    var body: some View {
        VStack(spacing: 14) {
            daysCard
            bookingsCard
            tripsCard
            noteCard
        }
        .fileImporter(isPresented: $showPDFImporter,
                      allowedContentTypes: [.pdf],
                      allowsMultipleSelection: false) { result in
            handlePDFImport(result)
        }
        .alert("Fehler", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Tage

    private var daysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tage").font(.headline)
                checksumBadge
                Spacer()
                Menu {
                    Button("Mo–Fr vor Ort (PB)") { fill(.pb) }
                    Button("Mo–Fr Home Office") { fill(.ho) }
                    Button("Mo–Fr Urlaub") { fill(.urlaub) }
                    Button("Mo–Fr Elternzeit") { fill(.ez) }
                    Button("Woche leeren", role: .destructive) { clearDays() }
                } label: {
                    Label("Ausfüllen", systemImage: "wand.and.stars")
                        .font(.subheadline)
                }
            }
            ForEach(0..<7, id: \.self) { i in
                dayRow(i)
                if i < 6 { Divider().overlay(Theme.cardBorder) }
            }
        }
        .card()
    }

    private func dayRow(_ i: Int) -> some View {
        let day = dayBinding(i)
        return HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 1) {
                Text(CW.dayNames[i])
                    .font(.subheadline.bold())
                Text(dayLabel(i))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(width: 42)

            Menu {
                Picker("Art", selection: day.kind) {
                    ForEach(DayKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
            } label: {
                KindBadge(kind: week.days[i].kind)
            }

            VStack(spacing: 6) {
                TextField("Tätigkeit (z. B. V103 OpenLoop Test)", text: day.activity)
                    .font(.subheadline)
                TextField("Ort", text: day.location)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .textFieldStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    /// Prüfsumme: Mo–Fr sollen immer ein Attribut haben (5/5).
    private var checksumBadge: some View {
        Label("\(week.weekdaysFilled)/5",
              systemImage: week.isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.caption.bold())
            .foregroundStyle(week.isComplete ? Theme.green : Color(red: 1.0, green: 0.72, blue: 0.3))
    }

    private func dayLabel(_ i: Int) -> String {
        guard let date = CW.date(year: year, cw: cw, dayIndex: i) else { return "" }
        let df = DateFormatter()
        df.dateFormat = "dd.MM."
        return df.string(from: date)
    }

    private func fill(_ kind: DayKind) {
        for i in 0..<5 { week.days[i].kind = kind }
    }

    private func clearDays() {
        week.days = Array(repeating: DayEntry(), count: 7)
    }

    // MARK: Buchungen

    private var bookingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hotel / Buchungen").font(.headline)
                Spacer()
                if week.nights > 0 {
                    Text("\(week.nights) Nächte · \(Store.german(week.amount)) €")
                        .font(.caption)
                        .foregroundStyle(Theme.green)
                }
            }

            if week.bookings.isEmpty {
                Text("Keine Buchung diese Woche (HO / Urlaub / EZ).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }

            // Identität über Booking.id (nicht über den Index), damit Löschen
            // mitten in der Liste keine veraltete Zeile stehen lässt.
            ForEach(week.bookings) { booking in
                if let index = week.bookings.firstIndex(where: { $0.id == booking.id }) {
                    bookingRow(index: index)
                    if booking.id != week.bookings.last?.id {
                        Divider().overlay(Theme.cardBorder)
                    }
                }
            }

            Button {
                week.bookings.append(Booking())
                // Hotelwoche heißt normalerweise: einmal hin, einmal zurück.
                if week.trips == 0 { week.trips = 2 }
            } label: {
                Label("Buchung hinzufügen", systemImage: "plus.circle.fill")
                    .font(.subheadline.bold())
            }
        }
        .card()
    }

    // MARK: Fahrten

    private var tripsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fahrten").font(.headline)
                Spacer()
                if week.trips > 0 {
                    Text(store.data.settings.kmOneWay > 0
                         ? "\(Store.german(store.kilometers(week))) km"
                         : "km-Strecke in „Belege“ eintragen")
                        .font(.caption)
                        .foregroundStyle(store.data.settings.kmOneWay > 0
                                         ? Theme.green
                                         : Color(red: 1.0, green: 0.72, blue: 0.3))
                }
            }
            Stepper(value: $week.trips, in: 0...14) {
                Text("\(week.trips) einfache Fahrten")
                    .font(.subheadline)
            }
            Text("\(store.data.settings.from) ↔ \(store.data.settings.to) · 2 = einmal hin und zurück")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }

    private func bookingRow(index: Int) -> some View {
        let binding = bookingBinding(index)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: "%02d", index + 1))
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(Theme.green)

                TextField("Hotel", text: binding.hotel)
                    .font(.subheadline.bold())
                    .textFieldStyle(.plain)

                Menu {
                    ForEach(store.knownHotels(year: year), id: \.self) { hotel in
                        Button(hotel) { week.bookings[index].hotel = hotel }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }

                Button(role: .destructive) {
                    week.bookings.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                }
            }

            HStack(spacing: 14) {
                Stepper(value: binding.nights, in: 0...7) {
                    Text("\(week.bookings[index].nights) Nächte").font(.subheadline)
                }
                .fixedSize()

                Spacer()

                TextField("0,00", value: binding.amount, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                Text("€").foregroundStyle(Theme.secondaryText)
            }

            Button {
                importBookingID = week.bookings[index].id
                showPDFImporter = true
            } label: {
                if week.bookings[index].receiptFile.isEmpty {
                    Label("Beleg (PDF) ablegen → \(Store.receiptName(cw: cw, hotel: week.bookings[index].hotel, index: index + 1))",
                          systemImage: "doc.badge.plus")
                        .font(.caption)
                } else {
                    Label(week.bookings[index].receiptFile, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.green)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func handlePDFImport(_ result: Result<[URL], Error>) {
        defer { importBookingID = nil }
        do {
            guard let source = try result.get().first,
                  let bookingID = importBookingID,
                  let index = week.bookings.firstIndex(where: { $0.id == bookingID }) else { return }
            let name = try store.importReceipt(from: source, year: year, cw: cw,
                                               hotel: week.bookings[index].hotel, index: index + 1)
            week.bookings[index].receiptFile = name
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Notiz

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notiz").font(.headline)
            TextField("z. B. Priv. Fahrt ElsenerBarker", text: $week.note, axis: .vertical)
                .lineLimit(1...4)
                .font(.subheadline)
                .textFieldStyle(.plain)
        }
        .card()
    }
}
