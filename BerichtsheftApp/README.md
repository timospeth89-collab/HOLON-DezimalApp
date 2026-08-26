# Berichtsheft

iPhone-App (SwiftUI) für die Wochen-/Hotelabrechnung: ersetzt die OneNote-Liste
und die Excel `Berichtsheft - Tabelle.xlsx` und legt die Hotel-Belege fürs
Finanzamt sauber benannt in iCloud Drive ab. Look angelehnt an HOLON
(dunkles UI, Holon-Grün `#29EB9F`, gleiches App-Icon-Logo wie die DezimalApp).

## Die drei Tabs

### 1. Woche
Pro Kalenderwoche 7 Tage (Mo–So), je Tag:

- **Art** — entspricht den Zähl-Spalten der Excel:
  `PB` (vor Ort), `HO` (Home Office), `FT` (Feiertag), `U` (Urlaub),
  `EZ` (Elternzeit), `KiKr` (Kind krank), `Kr` (Krank), `frei`
- **Tätigkeit** — Freitext wie im OneNote (z. B. „V103 OpenLoop Test")
- **Ort** — Freitext

Menü „Ausfüllen" setzt Mo–Fr auf einmal (PB-Woche, HO-Woche, Urlaub, EZ).

**Prüfsumme:** Mo–Fr sollen immer 5 Tage ein Attribut haben. Neben „Tage"
zeigt ein ✓ (5/5) bzw. ⚠︎ (z. B. 3/5) den Stand; in der Auswertung markiert
eine ✓/⚠︎-Spalte jede Woche, im CSV-Export steht `Tage erfasst`.

**Fahrten:** Paderborn ist die erste Tätigkeitsstätte, also gilt die
Entfernungspauschale auf die **einfache** Strecke. Pro Woche werden zwei
Dinge erfasst: die **Familienheimfahrt** (Wohnung ↔ Paderborn, i. d. R. 1×,
beim Anlegen der ersten Buchung vorgeschlagen) und die **Tagesfahrten**
Unterkunft → Arbeit, deren Anzahl automatisch den PB-Tagen entspricht und
pro Woche übersteuerbar ist. Die Strecken stehen im Tab „Steuer“: einmal
die Heimfahrt, und je Hotel die Tagesstrecke — die Unterkunft wechselt ja.

Dazu die **Hotelbuchungen** der Woche: Hotel, Nächte, Betrag. Mehrere
unabhängige Buchungen pro CW sind möglich — die Position in der Liste ist der
Index im Dateinamen. Über „Beleg (PDF) ablegen" wählst du die Rechnung aus
Dateien/iCloud, sie wird **automatisch umbenannt** nach dem Schema

```
<Jahr>-CW<KW>_<Hotel>_<Index>.pdf   z. B. 2026-CW17_SleepInn_01.pdf
```

Sonderzeichen im Hotelnamen werden ersetzt (`B&B` → `BaB`, Umlaute → ae/oe/ue).
Das Jahr steht vorn, damit die Datei auch außerhalb des Jahresordners
eindeutig ist und chronologisch sortiert.

### 2. Auswertung
Jahrestabelle exakt wie die Excel: eine Zeile pro CW mit
`CW | Hotel | Nächte | Summe | PB | HO | FT | U | EZ | KiKr | Kr` und
Summenzeile, oben Jahres-Kacheln (Nächte, Hotel-€, PB-/HO-Tage).

**Export** schreibt in den iCloud-Jahresordner (Fallback-Lösung):

- `Berichtsheft_<Jahr>.csv` — Auswertung, Spalten wie die Excel
  (Semikolon + Dezimalkomma, öffnet direkt im deutschen Excel)
- `Berichtsheft_<Jahr>_Tage.csv` — alle Tageseinträge (Datum, Art, Tätigkeit, Ort)
- `Berichtsheft_<Jahr>_Steuer.csv` — Zusammenfassung fürs Finanzamt
- `Berichtsheft_<Jahr>.json` — komplettes Datenbackup

### Erinnerung

Mo–Fr um 17:00 Uhr meldet sich die App per Mitteilung („Kurz eintragen: Was
hast du heute gemacht — und wo?"). Nach dem ersten Walkthrough fragt sie
einmal nach der Mitteilungs-Erlaubnis; der Schalter dazu sitzt im Tab
„Belege". Rein lokale Notifications (fünf wiederholende Kalender-Trigger),
kein Server nötig.

### 3. Steuer

Jahres-Zusammenfassung zum Abtippen in die Steuersoftware: Übernachtungskosten
der Zweitunterkunft, Familienheimfahrten und Fahrten Unterkunft → erste
Tätigkeitsstätte, jeweils mit Entfernungspauschale. Darunter die Eingaben,
von denen das abhängt — Heimfahrt-Strecke, Strecke je Hotel und die Sätze
(voreingestellt 0,30 € bis 20 km, 0,38 € darüber; im Zweifel fürs jeweilige
Jahr prüfen und anpassen).

Die App rechnet nach der Annahme: Paderborn ist erste Tätigkeitsstätte, die
Hotelkosten laufen über die **doppelte Haushaltsführung**. Dort gelten eigene
Regeln (Höchstbetrag Unterkunft, Verpflegungspauschale nur in den ersten drei
Monaten, Nachweis des eigenen Hausstands). Ob und ab wann das greift, gehört
steuerlich bestätigt — die App ist ein Werkzeug, keine Steuerberatung.

### 4. Belege
Hier wählst du **einmalig** den iCloud-Drive-Ordner (z. B.
`01_Jobs/008_Holon`). Die App legt darunter selbst
`SteuerHotelFahrtkosten/<Jahr>` an und merkt sich den Zugriff dauerhaft
(Security-Scoped Bookmark). Wählst du direkt `SteuerHotelFahrtkosten` oder
schon den Jahresordner, wird nichts doppelt angelegt. Der Tab listet alle
Dateien im Jahresordner; Tippen öffnet die Vorschau, ⋯ löscht.

> Warum Ordner wählen statt eigener iCloud-Container? Mit dem kostenlosen
> Personal Team gibt es keine iCloud-Entitlements. Der Dateien-Dialog
> funktioniert ohne — und die Belege liegen so in *deinem* sichtbaren
> iCloud-Drive-Ordner, den du dem Finanzamt direkt geben kannst.

## Daten

Gespeichert wird lokal als JSON (Application Support), unabhängig vom
iCloud-Ordner — die App funktioniert also auch offline/ohne gewählten Ordner;
nur Beleg-Ablage und Export brauchen ihn.

Beim allerersten Start werden die 2026-Daten aus der bisherigen Excel
(CW14–33, `Seed2026.json` im Bundle) vorbefüllt — die Wochensummen stimmen
mit der Excel-Summenzeile überein. Beim ersten Start zeigt die App außerdem
einen Walkthrough (über „?" im Tab „Woche" jederzeit wieder aufrufbar).

Installation als Vorabversion: siehe [WALKTHROUGH.md](WALKTHROUGH.md).

## Aufbau

- `Berichtsheft/Models.swift` — Wochen/Tage/Buchungen/Fahrten + ISO-KW-Helfer
- `Berichtsheft/Store.swift` — Persistenz, iCloud-Ordner, PDF-Import, CSV-Export, Seed
- `Berichtsheft/WeekView.swift` — Wocheneingabe (Tage, Buchungen, Fahrten, Prüfsumme)
- `Berichtsheft/TaxView.swift` — Steuer-Auswertung, Strecken, Sätze
- `Berichtsheft/SummaryView.swift` — Excel-Auswertung inkl. km und ✓/⚠︎
- `Berichtsheft/ReceiptsView.swift` — Ordner, Erinnerung, Belegliste
- `Berichtsheft/WalkthroughView.swift` — Onboarding
- `Berichtsheft/Theme.swift` — HOLON-Look
- `Berichtsheft/Seed2026.json` — Vorbefüllung CW14–33 aus der Excel

## Bauen

Wie die DezimalApp: Deployment Target iOS 17, Bundle-ID
`com.timospeth.Berichtsheft`, Team `WAZT637B2E` (Personal Team, automatisches
Signing, 7-Tage-Ablauf — siehe Haupt-README).

```bash
xcodebuild -project BerichtsheftApp/BerichtsheftApp.xcodeproj -scheme Berichtsheft -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

Aufs iPhone: `BerichtsheftApp.xcodeproj` öffnen, Gerät wählen, ⌘R — oder
analog zur DezimalApp per `xcodebuild … -allowProvisioningUpdates` und
`devicectl device install app`.
