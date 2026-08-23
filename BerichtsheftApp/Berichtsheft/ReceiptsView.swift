import SwiftUI
import QuickLook
import UniformTypeIdentifiers

/// Tab 3: iCloud-Drive-Ordner für die Finanzamt-Belege.
/// Einmal den Ordner wählen (z. B. 008_Holon) — die App legt
/// SteuerHotelFahrtkosten/2026 selbst an und listet alle Dateien darin.
struct ReceiptsView: View {
    @EnvironmentObject private var store: Store
    @State private var year = CW.currentYear
    @State private var files: [Store.ReceiptInfo] = []
    @State private var showFolderPicker = false
    @State private var previewURL: URL?
    @State private var errorMessage: String?
    @State private var reminderOn = Reminders.isEnabled

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    folderCard
                    reminderCard
                    filesCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Belege")
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
                    Button { refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear { refresh() }
            .onChange(of: year) { _, _ in refresh() }
            .fileImporter(isPresented: $showFolderPicker,
                          allowedContentTypes: [.folder]) { result in
                do {
                    let url = try result.get()
                    try store.setBaseFolder(url)
                    refresh()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .quickLookPreview($previewURL)
            .alert("Fehler", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var yearOptions: [Int] {
        let current = CW.currentYear
        let stored = store.data.years.map(\.year)
        return Array(Set(stored + [current - 1, current, current + 1])).sorted()
    }

    private func refresh() {
        files = store.listReceipts(year: year)
    }

    // MARK: Ordner

    private var folderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("iCloud-Ordner").font(.headline)
            if let name = store.folderName {
                Label {
                    Text("\(name) → \(Store.taxFolderName)/\(String(year))")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "icloud.fill").foregroundStyle(Theme.green)
                }
                Text("Belege, CSV-Export und JSON-Backup landen in diesem Ordner.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Noch kein Ordner gewählt. Wähle in iCloud Drive deinen Ablage-Ordner (z. B. 01_Jobs/008_Holon) — die Unterordner \(Store.taxFolderName)/\(String(year)) legt die App selbst an.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Button {
                showFolderPicker = true
            } label: {
                Label(store.folderName == nil ? "Ordner wählen" : "Ordner ändern",
                      systemImage: "folder.badge.gearshape")
                    .font(.subheadline.bold())
            }
        }
        .card()
    }

    // MARK: Erinnerung

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { reminderOn },
                set: { on in
                    Reminders.setEnabled(on) { granted in
                        reminderOn = granted
                        if on && !granted {
                            errorMessage = "Mitteilungen sind für Berichtsheft deaktiviert. In den iOS-Einstellungen → Berichtsheft → Mitteilungen erlauben und den Schalter erneut setzen."
                        }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Erinnerung").font(.headline)
                    Text("Mo–Fr um 17:00 Uhr: „Kurz eintragen: Was hast du heute gemacht — und wo?“")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .tint(Theme.green)
        }
        .card()
        .onAppear { reminderOn = Reminders.isEnabled }
    }

    // MARK: Dateien

    private var filesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dateien").font(.headline)
                Spacer()
                Text("\(files.count)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            if files.isEmpty {
                Text("Noch keine Dateien. PDFs legst du im Tab „Woche“ direkt bei der Hotelbuchung ab — sie werden automatisch nach Schema 2026-CW17_SleepInn_01.pdf benannt.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }

            ForEach(files) { file in
                fileRow(file)
                if file.id != files.last?.id { Divider().overlay(Theme.cardBorder) }
            }
        }
        .card()
    }

    private func fileRow(_ file: Store.ReceiptInfo) -> some View {
        Button {
            do { previewURL = try store.tempCopyOfReceipt(year: year, name: file.name) }
            catch { errorMessage = error.localizedDescription }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: file.name.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "doc")
                    .foregroundStyle(Theme.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(sizeLabel(file.size)) · \(dateLabel(file.modified))")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        do {
                            try store.deleteReceipt(year: year, name: file.name)
                            refresh()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func sizeLabel(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func dateLabel(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy HH:mm"
        return df.string(from: date)
    }
}
