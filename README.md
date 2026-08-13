# DezimalApp

iPhone-App (SwiftUI), die die Rechnung aus `Software_VSM_Transitions_3_4_Lmo.xlsx` nachbildet:
Dezimalwert eingeben → 4-stelliger Hex-BitMask-Wert.

## Logik

| Excel | Bedeutung | App |
|---|---|---|
| `C21` | Eingabewert, z. B. `53759` | Eingabefeld |
| `B21:B36` | `=IF(BITAND($C21;2^i)=0;0;1)`, i = 0…15 | Bit-Tabelle, Spalte `set` |
| `N7` | `=DEC2HEX(SUMPRODUCT((1-B21:B36)*2^(ROW(B21:B36)-ROW(B21)));4)` | großes Hex-Ergebnis |
| `O7` | gleiches Ergebnis per Python | aufklappbares Skript zum Kopieren |

`N7` invertiert alle 16 Bits und setzt sie wieder zu einer Zahl zusammen — das ist
das 16-Bit-Einerkomplement. Die App rechnet das nativ in Swift (`BitMask.mask(for:)`),
das Python-Skript wird zusätzlich mit dem eingegebenen Wert angezeigt.

Beispiele aus dem Sheet (verifiziert):

- `53759` → `D1FF` → **`2E00`**
- `54271` → `D3FF` → **`2C00`**

## Aufbau

- `DezimalApp/BitMask.swift` — Rechenlogik + Signalnamen aus `A21:A36`
- `DezimalApp/ContentView.swift` — UI
- `DezimalApp/DezimalAppApp.swift` — App-Entry

## Icon

`DezimalApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png` ist das Holon-Logo von
`holon-mover.com/static/images/app-icon.png` (1024×1024), Alphakanal entfernt —
iOS akzeptiert bei App-Icons keinen. Der Akzentton der App (`AccentColor`) ist das
Holon-Grün `#29EB9F` aus demselben Bild.

## Bauen

Deployment Target iOS 17, Bundle-ID `com.timospeth.DezimalApp`, Team `WAZT637B2E`
(Personal Team, automatisches Signing).

Simulator:

```bash
xcodebuild -project DezimalApp.xcodeproj -scheme DezimalApp -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

Auf dem iPhone (angeschlossen, entsperrt, Entwicklermodus an):

```bash
xcodebuild -project DezimalApp.xcodeproj -scheme DezimalApp -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

```bash
xcrun devicectl device install app --device 00008120-001E35DC22C3A01E <Pfad>/DezimalApp.app
```

Oder einfach `DezimalApp.xcodeproj` öffnen, Gerät wählen und ⌘R.

### Fallstricke

- Signiert der Kommandozeilen-Build mit `errSecInternalComponent`, fehlt `codesign`
  die Freigabe für den privaten Schlüssel — einmal aus Xcode heraus bauen und den
  Schlüsselbund-Dialog mit „Immer erlauben" bestätigen.
- Mit dem kostenlosen Personal Team läuft die App **7 Tage** auf dem Gerät,
  danach neu installieren — das erledigt die Automatik unten.

## Automatische Erneuerung

`Tools/refresh-install.sh` baut und installiert die App neu, sobald die letzte
Installation älter als 5 Tage ist. Der LaunchAgent
`~/Library/LaunchAgents/com.timospeth.dezimalapp.refresh.plist` ruft es alle
6 Stunden auf; ist nichts fällig, beendet es sich sofort. Erfolg und Fehler landen
in `~/Library/Logs/DezimalApp-refresh.log`, bei Fehlern kommt zusätzlich eine
Mitteilung.

Die Installation läuft über WLAN. Ab Xcode 15 (CoreDevice) genügt dafür, dass das
iPhone einmal per Kabel gekoppelt wurde — den früheren Haken *Connect via network*
gibt es nicht mehr. Prüfen:

```bash
xcrun devicectl list devices
```

Steht dort `transportType: localNetwork`, ist das Gerät kabellos erreichbar.

Zum Zeitpunkt des Laufs müssen Mac und iPhone im selben Netz sein, der Mac wach und
angemeldet, das iPhone entsperrt. Klappt es nicht, versucht es der nächste Lauf
6 Stunden später erneut — bei 5 Tagen Schwelle und 7 Tagen Ablauf bleiben rund
acht Versuche Puffer.

```bash
# sofort erzwingen
Tools/refresh-install.sh --force
```

```bash
# Automatik abschalten
launchctl bootout gui/$(id -u)/com.timospeth.dezimalapp.refresh
```
