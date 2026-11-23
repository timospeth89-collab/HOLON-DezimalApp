#!/bin/zsh
#
# Hält die Berichtsheft-App auf dem iPhone am Leben — analog zu
# refresh-install.sh der DezimalApp.
#
# Provisioning-Profile eines kostenlosen Personal Teams laufen nach 7 Tagen ab.
# Dieses Skript holt den neuesten Stand von GitHub (main), baut die App neu und
# installiert sie per WLAN aufs iPhone. Läuft per LaunchAgent jede Nacht um
# 4 Uhr — Einrichtung: Tools/install-nightly-refresh.sh. Kann jederzeit auch
# manuell aufgerufen werden, es gibt keine Mindestabstand-Sperre.
#

set -uo pipefail

# launchd startet mit minimalem PATH; Homebrew-Pfade zur Sicherheit ergänzen.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"

# Repo-Wurzel aus dem Skriptpfad ableiten — funktioniert egal, wo das Repo liegt.
REPO_DIR="${0:A:h:h}"
PROJECT="$REPO_DIR/BerichtsheftApp/BerichtsheftApp.xcodeproj"
SCHEME="Berichtsheft"
DEVICE="00008120-001E35DC22C3A01E"
DERIVED="$HOME/Library/Caches/Berichtsheft-build"
STAMP="$HOME/Library/Caches/Berichtsheft-lastinstall"
LOG="$HOME/Library/Logs/Berichtsheft-refresh.log"
RETRIES=5          # Versuche, das iPhone im WLAN zu erreichen
RETRY_WAIT=60      # Sekunden zwischen den Versuchen

mkdir -p "${LOG:h}" "$DERIVED"

log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S')  $*" >> "$LOG"; }

notify() {
    osascript -e "display notification \"$1\" with title \"Berichtsheft\"" >/dev/null 2>&1
}

# Bei jedem Fehlschlag: warnen, sobald die letzte erfolgreiche Installation
# 5 Tage oder älter ist (Ablauf nach 7 Tagen).
warn_if_stale() {
    [[ -f "$STAMP" ]] || return 0
    local days=$(( ( $(date +%s) - $(stat -f %m "$STAMP") ) / 86400 ))
    (( days >= 5 )) && notify "Letzte erfolgreiche Installation vor $days Tagen — App läuft bald ab"
    return 0
}

log "--- Nächtlicher Refresh gestartet"

# --- 1. Neuesten Stand holen (best effort) ---------------------------------
if git -C "$REPO_DIR" pull --ff-only origin main >> "$LOG" 2>&1; then
    log "git pull OK, Stand $(git -C "$REPO_DIR" rev-parse --short HEAD)"
else
    log "git pull fehlgeschlagen — baue mit dem vorhandenen Stand"
fi

# --- 2. Ist das iPhone erreichbar? ----------------------------------------
reachable=0
for attempt in $(seq 1 $RETRIES); do
    if xcrun devicectl device info details --device "$DEVICE" >/dev/null 2>&1; then
        reachable=1
        break
    fi
    log "iPhone nicht erreichbar (Versuch $attempt/$RETRIES)"
    (( attempt < RETRIES )) && sleep $RETRY_WAIT
done
if (( reachable == 0 )); then
    log "iPhone nach $RETRIES Versuchen nicht erreichbar — nächster Versuch morgen Nacht"
    warn_if_stale
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
    warn_if_stale
    exit 1
fi

# --- 4. Installieren ------------------------------------------------------
if ! xcrun devicectl device install app \
        --device "$DEVICE" \
        "$DERIVED/Build/Products/Debug-iphoneos/Berichtsheft.app" >> "$BUILD_LOG" 2>&1; then
    log "FEHLER bei der Installation:"
    tail -5 "$BUILD_LOG" >> "$LOG"
    notify "Installation fehlgeschlagen — iPhone erreichbar und entsperrt?"
    warn_if_stale
    exit 1
fi

touch "$STAMP"
log "OK — App neu installiert, wieder 7 Tage gültig"
notify "App erneuert — wieder 7 Tage gültig"
