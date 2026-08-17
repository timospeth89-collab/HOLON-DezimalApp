import SwiftUI

/// Geführter Einstieg beim ersten Start (über „?" in der Woche jederzeit
/// wieder aufrufbar): erklärt die drei Tabs und die Erst-Einrichtung.
struct WalkthroughView: View {
    @Binding var isPresented: Bool
    @State private var page = 0

    private let pages: [(icon: String, title: String, text: String)] = [
        ("book.closed.fill",
         "Berichtsheft",
         "Deine Wochen-/Hotelabrechnung: OneNote-Liste und Excel in einer App — Belege fürs Finanzamt inklusive.\n\nCW14–33 aus deiner bisherigen Excel sind schon vorbefüllt."),
        ("calendar",
         "Woche erfassen",
         "Pro Kalenderwoche 7 Tage: Art (PB vor Ort, HO, Feiertag, Urlaub, EZ, Kind krank, Krank), Tätigkeit und Ort.\n\nDas ✓/⚠︎ oben zeigt die Prüfsumme: Mo–Fr sollen immer 5 Tage ein Attribut haben.\n\n„Ausfüllen" setzt Mo–Fr auf einen Schlag."),
        ("bed.double.fill",
         "Hotel + Beleg",
         "Buchungen mit Nächten und Betrag eintragen — mehrere pro Woche möglich.\n\n„Beleg (PDF) ablegen" holt die Rechnung aus Dateien/iCloud und benennt sie automatisch:\n\nCW17_SleepInn_01.pdf\n\nzweite Buchung → _02, dritte → _03."),
        ("car.fill",
         "Fahrten",
         "Pro Woche die einfachen Fahrten zählen (2 = hin + zurück).\n\nDie Strecke Weinbergstr. 27 ↔ Elsener Str. 95 trägst du einmal im Tab „Belege" ein — km stehen dann in Auswertung und Export."),
        ("icloud.fill",
         "Einrichten (einmalig)",
         "1. Tab „Belege" → „Ordner wählen" → in iCloud Drive deinen Ordner 01_Jobs/008_Holon wählen. Die App legt SteuerHotelFahrtkosten/2026 selbst an.\n\n2. Darunter die einfache km-Strecke eintragen.\n\n3. Tab „Auswertung" → Export schreibt CSV (öffnet in Excel) + JSON-Backup in den Ordner."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 24) {
                        Image(systemName: pages[i].icon)
                            .font(.system(size: 56))
                            .foregroundStyle(Theme.green)
                        Text(pages[i].title)
                            .font(.title2.bold())
                        Text(pages[i].text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        Spacer().frame(height: 20)
                    }
                    .tag(i)
                    .padding(.top, 40)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    isPresented = false
                }
            } label: {
                Text(page < pages.count - 1 ? "Weiter" : "Los geht's")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Theme.green))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .interactiveDismissDisabled(false)
    }
}
