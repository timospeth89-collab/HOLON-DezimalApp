import SwiftUI

@main
struct BerichtsheftApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.green)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            WeekView()
                .tabItem { Label("Woche", systemImage: "calendar") }
            SummaryView()
                .tabItem { Label("Auswertung", systemImage: "tablecells") }
            ReceiptsView()
                .tabItem { Label("Belege", systemImage: "folder") }
        }
    }
}
