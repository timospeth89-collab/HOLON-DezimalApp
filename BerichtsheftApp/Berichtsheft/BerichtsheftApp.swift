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
    /// Walkthrough beim ersten Start; über „?" in der Woche wieder aufrufbar.
    @AppStorage("walkthroughSeen") private var walkthroughSeen = false
    @State private var showWalkthrough = false

    var body: some View {
        TabView {
            WeekView()
                .tabItem { Label("Woche", systemImage: "calendar") }
            SummaryView()
                .tabItem { Label("Auswertung", systemImage: "tablecells") }
            ReceiptsView()
                .tabItem { Label("Belege", systemImage: "folder") }
        }
        .onAppear {
            if !walkthroughSeen { showWalkthrough = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWalkthrough)) { _ in
            showWalkthrough = true
        }
        .sheet(isPresented: $showWalkthrough, onDismiss: { walkthroughSeen = true }) {
            WalkthroughView(isPresented: $showWalkthrough)
        }
    }
}

extension Notification.Name {
    static let showWalkthrough = Notification.Name("berichtsheft.showWalkthrough")
}
