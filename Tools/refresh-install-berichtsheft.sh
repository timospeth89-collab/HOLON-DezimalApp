#!/bin/zsh
#
# Hält die Berichtsheft-App auf dem iPhone am Leben — analog zu
# refresh-install.sh der DezimalApp.
#
# Provisioning-Profile eines kostenlosen Personal Teams laufen nach 7 Tagen ab.
# Dieses Skript baut die App neu und installiert sie, sobald die letzte
# Installation älter als MAX_AGE ist. LaunchAgent-Vorlage siehe
# BerichtsheftApp/WALKTHROUGH.md.
#
# Manuell erzwingen:  Tools/refresh-install-berichtsheft.sh --force
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
MAX_AGE=$(( 5 * 24 * 60 * 60 ))   # 5 Tage, zwei Tage Puffer vor Ablauf

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

mkdir -p "${LOG:h}" "$DERIVED"

log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S')  $*" >> "$LOG" }

notify() {
    osascript -e "display notification \"$1\" with title \"Berichtsheft\"" >/dev/null 2>&1
}

# --- 1. Ist ein Refresh fällig? -------------------------------------------
age=""
if [[ -f "$STAMP" ]]; then
    age=$(( $(date +%s) - $(stat -f %m "$STAMP") ))
    if (( FORCE == 0 && age < MAX_AGE )); then
        exit 0
    fi
fi

log "--- Refresh fällig (letzte Installation: ${age:-noch nie} s her, force=$FORCE)"

# --- 2. Ist das iPhone erreichbar? ----------------------------------------
if ! xcrun devicectl device info details --device "$DEVICE" >/dev/null 2>&1; then
    log "iPhone nicht erreichbar — nächster Versuch beim nächsten Lauf"
    exit 0
fi

# --- 3. Bauen -------------------------------------------------------------
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

# --- 4. Installieren ------------------------------------------------------
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
