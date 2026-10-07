#!/bin/zsh
#
# Hält die Berichtsheft-App auf dem iPhone am Leben — analog zu
# refresh-install.sh der DezimalApp.
#
# Provisioning-Profile eines kostenlosen Personal Teams laufen nach 7 Tagen ab.
# Dieses Skript baut die App neu und installiert sie. Läuft per LaunchAgent
# jede Nacht um 4 Uhr (StartCalendarInterval) — siehe
# BerichtsheftApp/WALKTHROUGH.md für die Plist-Vorlage. Kann jederzeit auch
# manuell aufgerufen werden, es gibt keine Mindestabstand-Sperre mehr.
#

set -uo pipefail

# Repo-Wurzel aus dem Skriptpfad ableiten — funktioniert egal, wo das Repo liegt.
REPO_DIR="${0:A:h:h}"
PROJECT="$REPO_DIR/BerichtsheftApp/BerichtsheftApp.xcodeproj"
SCHEME="Berichtsheft"
DEVICE="00008120-001E35DC22C3A01E"
DERIVED="$HOME/Library/Caches/Berichtsheft-build"
STAMP="$HOME/Library/Caches/Berichtsheft-lastinstall"
LOG="$HOME/Library/Logs/Berichtsheft-refresh.log"

mkdir -p "${LOG:h}" "$DERIVED"

log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S')  $*" >> "$LOG" }

notify() {
    osascript -e "display notification \"$1\" with title \"Berichtsheft\"" >/dev/null 2>&1
}

log "--- Nächtlicher Refresh gestartet"

# --- 1. Ist das iPhone erreichbar? ----------------------------------------
if ! xcrun devicectl device info details --device "$DEVICE" >/dev/null 2>&1; then
    log "iPhone nicht erreichbar — nächster Versuch morgen Nacht"
    exit 0
fi

# --- 2. Bauen -------------------------------------------------------------
BUILD_LOG="$DERIVED/last-build.log"
if ! xcodebuild -project "$PROJECT" \
                -scheme "$SCHEME" \
                -destination 'generic/platform=iOS' \
                -derivedDataPath "$DERIVED" \
                -allowProvisioningUpdates \
                build > "$BUILD_LOG" 2>&1; then
    log "FEHLER beim Bauen:"
    grep -E "error:|errSec|CodeSign failed" "$BUILD_LOG" | sort -u | head -5 >> "$LOG"
    notify "Build fehlgeschlagen — Details in Berichtsheft-refresh.log"
    exit 1
fi

# --- 3. Installieren ------------------------------------------------------
if ! xcrun devicectl device install app \
        --device "$DEVICE" \
        "$DERIVED/Build/Products/Debug-iphoneos/Berichtsheft.app" >> "$BUILD_LOG" 2>&1; then
    log "FEHLER bei der Installation:"
    tail -5 "$BUILD_LOG" >> "$LOG"
    notify "Installation fehlgeschlagen — iPhone erreichbar und entsperrt?"
    exit 1
fi

touch "$STAMP"
log "OK — App neu installiert, wieder 7 Tage gültig"
notify "App erneuert — wieder 7 Tage gültig"
