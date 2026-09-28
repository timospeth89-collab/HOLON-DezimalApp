# Berichtsheft Web

Eine einzige HTML-Datei (`berichtsheft.html`, ~925 KB, alles eingebettet —
keine Internetverbindung zur Laufzeit nötig) für den Arbeitsrechner: gleiche
Funktionen wie die iPhone-App, aber im Browser. Für Google Chrome oder
Microsoft Edge gebaut — Firefox und Safari unterstützen die dafür nötige
File System Access API nicht.

## Benutzung

1. `berichtsheft.html` per Doppelklick in Chrome öffnen (kein Server nötig).
2. **Ordner wählen** → deinen iCloud-Jahresordner (z. B.
   `SteuerHotelFahrtkosten/2026`) auswählen. Chrome fragt das bei jedem
   Neuöffnen der Seite einmal per Klick ab — das ist eine
   Sicherheitsvorgabe des Browsers, keine Einschränkung dieser App.
3. Liegt dort schon eine `Berichtsheft_<Jahr>.xlsx`, wird sie geladen.
   Sonst: **Leer starten** oder **Alte Excel importieren…**, um deine
   bisherige Tabelle (Spalten CW/Hotel/Nächte/Summe/PB Tage/HO Tage/FT/U/
   EZ/Kind_Krank/Krank) einzulesen.
4. Jede Änderung speichert automatisch (kurze Verzögerung nach dem letzten
   Tastendruck) zurück in `Berichtsheft_<Jahr>.xlsx` im gewählten Ordner —
   dieselbe Datei kannst du auch direkt in Excel/Numbers/LibreOffice öffnen.

## Die vier Tabs

Entsprechen 1:1 den Tabs der iPhone-App (`BerichtsheftApp/`):

- **Woche** — 7 Tage (Art/Tätigkeit/Ort), Hotelbuchungen mit Beleg-Namens-
  Vorschau, Familienheimfahrten, Fahrtage, Prüfsumme (Mo–Fr sollen 5 Tage
  ein Attribut haben).
- **Auswertung** — Jahrestabelle mit Summenzeile, CSV-Export.
- **Steuer** — Entfernungspauschale (Familienheimfahrt + Unterkunft→Arbeit
  je Hotel), Sätze editierbar. Gleiche Annahme wie die iPhone-App: Paderborn
  ist erste Tätigkeitsstätte, Hotelkosten laufen über die doppelte
  Haushaltsführung. **Ohne Gewähr — bitte steuerlich prüfen lassen.**
- **Belege** — gleicht die Buchungen gegen die Dateien im Ordner ab: grün =
  Beleg mit passendem Namen gefunden, gelb = Datei mit anderem/falsch
  geschriebenem Namen gefunden, rot = fehlt. Reine Namensprüfung (CW +
  Hotel + Index, z. B. `2026-CW34_SleepInn_01.pdf`) — der Inhalt der PDF
  wird nicht gelesen.

## Woher die Daten kommen — die Excel als Datenspeicher

Die Arbeitsmappe hat vier Blätter:

| Blatt | Inhalt |
|---|---|
| `<Jahr>` (z. B. `2026`) | Aggregat-Übersicht wie die ursprüngliche Tabelle — **wird bei jedem Speichern neu erzeugt und nie zurückgelesen.** Reine Anzeige. Handeditierst du hier etwas, geht es beim nächsten Speichern verloren. |
| `Tage` | Ein Eintrag je ausgefülltem Tag — Quelle für Tagesart/Tätigkeit/Ort. |
| `Buchungen` | Ein Eintrag je Hotelbuchung — Quelle für Nächte/Betrag/Beleg-Dateiname. |
| `Einstellungen` | Adressen, km-Strecken, Pauschal-Sätze. |

**Alte, einfache Tabelle importieren:** Fehlen `Tage`/`Buchungen`
komplett (z. B. bei deiner ursprünglichen Excel), rekonstruiert die App ein
plausibles Wochenmodell aus den Zählerspalten — die Tagesarten werden dabei
in fester Reihenfolge (PB, HO, FT, U, EZ, KiKr, Kr) auf Mo–Fr verteilt, weil
das alte Format nicht festhält, an welchem Wochentag was war. Nach dem
Import erscheint ein Hinweis-Banner; bitte insbesondere die zuletzt
gebuchten Wochen einmal prüfen.

**Verhältnis zur iPhone-App:** Beide führen unabhängige Datenstände — es
gibt keine automatische Synchronisierung. Sie teilen sich nur denselben
iCloud-**Ordner** für Belege. Wer an beiden Geräten einträgt, sollte sich
für eine Quelle pro Zeitraum entscheiden, oder regelmäßig eine der beiden
Excel-Dateien in die andere App importieren.

## Aufbau

```
src/
  model.js       Datenmodell + ISO-Kalenderwochen + Steuerberechnung
                 (Portierung von BerichtsheftApp/Berichtsheft/Models.swift)
  xlsx-io.js     Excel lesen/schreiben, Import der alten Aggregat-Tabelle
  app.js         Ordnerzugriff (File System Access API), Speichern, UI
  style.css      HOLON-Look, portiert aus Theme.swift
  vendor/
    xlsx.full.min.js   SheetJS 0.18.5 (Apache-2.0), von npm geladen und
                        per SHA-256 sowie Rundlauf-Test gegen eine zweite,
                        unabhängige Bibliothek (Python/openpyxl) geprüft
build.py         Setzt src/* zu berichtsheft.html zusammen
berichtsheft.html  DAS AUSGELIEFERTE ARTEFAKT — einzige Datei, die der
                   Nutzer braucht
test/
  model.test.js    Node-Tests für model.js/xlsx-io.js (Teil der CI)
  browser.test.js  Playwright-Test der echten berichtsheft.html in
                    Chromium — lokal vor jedem Release laufen lassen
                    (nicht automatisch in CI, siehe Datei-Kopfkommentar)
  assertions.js    Testfälle, gemeinsam von model.test.js verwendet
  legacy-sample.xlsx  Beispieldatei im alten Format für den Import-Test
```

## Neu bauen

Nach jeder Änderung an `src/*`:

```bash
python3 build.py
node test/model.test.js          # schnell, Teil der CI
node test/browser.test.js        # gründlicher, braucht Playwright+Chromium
```

## Warum kein CDN, keine externe Bibliothek zur Laufzeit

Die Datei muss auf einem Firmenrechner mit möglicherweise eingeschränktem
Internetzugang funktionieren. Deshalb ist SheetJS komplett eingebettet statt
per `<script src="https://…">` geladen — die Seite braucht nach dem Öffnen
keine Netzwerkverbindung mehr.
