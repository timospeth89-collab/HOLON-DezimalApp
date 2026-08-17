import Foundation
import UserNotifications

/// Lokale Erinnerung: Mo–Fr um 17:00 Uhr „Berichtsheft ausfüllen".
/// Fünf wiederholende Kalender-Trigger, keine Server nötig.
enum Reminders {
    private static let enabledKey = "berichtsheft.reminderEnabled"
    private static let promptedKey = "berichtsheft.reminderPrompted"
    private static let identifiers = (2...6).map { "berichtsheft.reminder.\($0)" }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Schaltet die Erinnerung um; fragt bei Bedarf die Mitteilungs-Erlaubnis ab.
    /// `completion` liefert den tatsächlichen Zustand (false, wenn iOS ablehnt).
    static func setEnabled(_ on: Bool, completion: @escaping (Bool) -> Void) {
        UserDefaults.standard.set(true, forKey: promptedKey)
        guard on else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            cancel()
            completion(false)
            return
        }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    UserDefaults.standard.set(granted, forKey: enabledKey)
                    if granted { schedule() } else { cancel() }
                    completion(granted)
                }
            }
    }

    /// Nach dem ersten Walkthrough einmalig aktivieren (fragt die Erlaubnis ab).
    static func promptOnceIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: promptedKey) else { return }
        setEnabled(true) { _ in }
    }

    /// Beim App-Start: Trigger neu setzen, falls aktiviert und erlaubt.
    static func refresh() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async { schedule() }
        }
    }

    private static func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        let content = UNMutableNotificationContent()
        content.title = "Berichtsheft"
        content.body = "Kurz eintragen: Was hast du heute gemacht — und wo?"
        content.sound = .default

        // DateComponents.weekday: 1 = So, 2 = Mo … 6 = Fr
        for weekday in 2...6 {
            var comps = DateComponents()
            comps.weekday = weekday
            comps.hour = 17
            comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: "berichtsheft.reminder.\(weekday)",
                                             content: content, trigger: trigger))
        }
    }

    private static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
