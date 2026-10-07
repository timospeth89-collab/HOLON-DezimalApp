import SwiftUI
import UIKit

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
    /// Walkthrough beim ersten Start; über „?“ in der Woche wieder aufrufbar.
    @AppStorage("walkthroughSeen") private var walkthroughSeen = false
    @State private var showWalkthrough = false

    var body: some View {
        TabView {
            WeekView()
                .tabItem { Label("Woche", systemImage: "calendar") }
            SummaryView()
                .tabItem { Label("Auswertung", systemImage: "tablecells") }
            TaxView()
                .tabItem { Label("Steuer", systemImage: "eurosign.circle") }
            ReceiptsView()
                .tabItem { Label("Belege", systemImage: "folder") }
        }
        .toolbar {
            // .decimalPad/.numberPad haben keine Return-Taste -- ohne diese
            // Leiste bleibt die Tastatur bei den km-/€-Feldern offen und
            // blockiert den Rest der App.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onAppear {
            if !walkthroughSeen { showWalkthrough = true }
            Reminders.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWalkthrough)) { _ in
            showWalkthrough = true
        }
        .sheet(isPresented: $showWalkthrough, onDismiss: {
            walkthroughSeen = true
            // Nach dem ersten Walkthrough einmal nach Mitteilungen fragen
            // und die Mo–Fr-17-Uhr-Erinnerung aktivieren.
            Reminders.promptOnceIfNeeded()
        }) {
            WalkthroughView(isPresented: $showWalkthrough)
        }
    }
}

extension Notification.Name {
    static let showWalkthrough = Notification.Name("berichtsheft.showWalkthrough")
}
