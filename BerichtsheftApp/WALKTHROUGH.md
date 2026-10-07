# Walkthrough: Berichtsheft als Vorabversion aufs iPhone

Schritt für Schritt für Freitag daheim — analog zur DezimalApp.
Voraussetzung: Mac mit Xcode 16, iPhone einmal per Kabel gekoppelt
(Entwicklermodus an), gleiches WLAN.

## 1. Code holen

Alles liegt auf `main` — es reicht:

```bash
cd "/Users/timospeth/Library/Mobile Documents/com~apple~CloudDocs/000-Claude/Code/DezimalApp"
git checkout main
git pull origin main
```

Damit ist der Auto-Refresh (Schritt 4) auf der sicheren Seite: Er baut aus
dem Ordner, der gerade ausgecheckt ist. Läge die App nur auf einem
Feature-Branch, würde `BerichtsheftApp/` beim Wechsel auf `main`
verschwinden — der LaunchAgent scheiterte dann still und die App liefe
nach 7 Tagen ab.

## 2. Bauen und installieren

Am einfachsten über Xcode:

1. `BerichtsheftApp/BerichtsheftApp.xcodeproj` öffnen
2. Oben als Ziel dein iPhone wählen
3. ⌘R — fertig. Beim allerersten Mal auf dem iPhone unter
   *Einstellungen → Allgemein → VPN & Geräteverwaltung* dem
   Entwicklerzertifikat vertrauen.

Oder per Kommandozeile (wie bei der DezimalApp):

```bash
xcodebuild -project BerichtsheftApp/BerichtsheftApp.xcodeproj -scheme Berichtsheft \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008120-001E35DC22C3A01E \
  <DerivedData>/Build/Products/Debug-iphoneos/Berichtsheft.app
```

Signier-Fallstrick wie gehabt: meldet der CLI-Build `errSecInternalComponent`,
einmal aus Xcode heraus bauen und den Schlüsselbund-Dialog mit
„Immer erlauben" bestätigen.

## 3. Erststart in der App (2 Minuten)

Die App zeigt beim ersten Start einen Walkthrough. Danach:

1. **Tab „Belege" → „Ordner wählen"** — in iCloud Drive zu
   `01_Jobs/008_Holon` navigieren und *Öffnen*. Die App legt
   `SteuerHotelFahrtkosten/2026` selbst an und merkt sich den Zugriff.
   (Heißt der Ordner bei dir anders: einfach den wählen, den du willst —
   die App hängt die fehlenden Ebenen selbst an.)
2. **Ebenfalls dort: Fahrtstrecke** — die einfachen km
   Weinbergstr. 27 → Elsener Str. 95, Paderborn einmal eintragen
   (aus Apple/Google Maps ablesen).
3. **Tab „Auswertung"** — CW14–33 aus deiner Excel sind schon drin,
   Summen stimmen mit der Excel-Summenzeile überein (27 Nächte,
   1629,49 €, PB 38, HO 25, FT 6, U 7, EZ 20, KiKr 2). Einmal
   **Export** drücken → CSV + JSON liegen im iCloud-Ordner.
4. **Tab „Woche"** — aktuelle CW prüfen; das ⚠︎ neben „Tage" wird zum ✓,
   sobald Mo–Fr alle 5 Tage ein Attribut haben.
5. **Mitteilungen erlauben**, wenn die App nach dem Walkthrough fragt —
   dann erinnert sie dich Mo–Fr um 17:00 Uhr ans Eintragen. Der Schalter
   dazu (an/aus) sitzt im Tab „Belege".

Bei den vorbefüllten Wochen habe ich die Tages-Verteilung (welcher Wochentag
PB/HO/frei war) teils aus dem OneNote übernommen (CW14–19), teils plausibel
verteilt (CW20–33) — die Wochensummen stimmen immer mit der Excel überein.
Feiertage 2026 (Karfreitag, Ostermontag, 1. Mai, Himmelfahrt, Pfingstmontag,
Fronleichnam) sitzen auf den richtigen Tagen. Belege-PDFs musst du einmalig
den Buchungen zuordnen („Beleg (PDF) ablegen" in der jeweiligen Woche) —
dabei werden sie gleich nach Schema `CW17_SleepInn_01.pdf` umbenannt.

## 4. Auto-Refresh: jede Nacht um 4 Uhr

```bash
Tools/refresh-install-berichtsheft.sh   # einmal manuell testen
```

Dann als LaunchAgent `~/Library/LaunchAgents/com.timospeth.berichtsheft.refresh.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.timospeth.berichtsheft.refresh</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string><PFAD-ZUM-REPO>/Tools/refresh-install-berichtsheft.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>4</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
```

`<PFAD-ZUM-REPO>` durch den tatsächlichen Klon-Pfad ersetzen (z. B.
`/Users/timospeth/HOLON-DezimalApp`, mit `pwd` im Repo-Ordner prüfen).

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.timospeth.berichtsheft.refresh.plist 2>/dev/null
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.timospeth.berichtsheft.refresh.plist
```

Das `bootout` vorher ist wichtig — ohne das schlägt `bootstrap` bei einer
schon einmal registrierten Plist gelegentlich mit "Input/output error" fehl.
Status prüfen: `launchctl print gui/$(id -u)/com.timospeth.berichtsheft.refresh`
(zwischen den nächtlichen Läufen ist `state = waiting` normal).

Läuft nachts der Mac gerade im Schlaf, holt macOS den Lauf beim Aufwachen
nach. Das Skript hat keine Mindestabstand-Sperre mehr — jeder Lauf baut und
installiert direkt neu, sobald das iPhone erreichbar ist (sonst wird der
Versuch übersprungen und beim nächsten Mal wiederholt).

Log: `~/Library/Logs/Berichtsheft-refresh.log`. Abschalten:
`launchctl bootout gui/$(id -u)/com.timospeth.berichtsheft.refresh`
