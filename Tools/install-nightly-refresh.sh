#!/bin/zsh
#
# Einmalig ausführen: richtet den nächtlichen 4-Uhr-Refresh als LaunchAgent ein
# (schreibt die Plist mit dem echten Repo-Pfad, registriert sie neu und zeigt
# den Status). Danach muss nichts mehr von Hand gemacht werden.
#
#   zsh Tools/install-nightly-refresh.sh
#

set -euo pipefail

REPO_DIR="${0:A:h:h}"
SCRIPT="$REPO_DIR/Tools/refresh-install-berichtsheft.sh"
LABEL="com.timospeth.berichtsheft.refresh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LAUNCHD_LOG="$HOME/Library/Logs/Berichtsheft-launchd.log"

if [[ ! -f "$SCRIPT" ]]; then
    print -u2 "Skript nicht gefunden: $SCRIPT"
    exit 1
fi
chmod +x "$SCRIPT"

if [[ "$REPO_DIR" == *"Mobile Documents"* ]]; then
    print "HINWEIS: Das Repo liegt in iCloud Drive ($REPO_DIR)."
    print "  Ein Git-Repo in iCloud kann beschädigt werden, und Hintergrundjobs"
    print "  dürfen dort teils nicht lesen. Empfohlen: außerhalb von iCloud klonen,"
    print "  z. B.  git clone git@github.com:timospeth89-collab/HOLON-DezimalApp.git ~/Developer/HOLON-DezimalApp"
    print "  und dort dieses Skript erneut ausführen."
    print ""
fi

mkdir -p "${PLIST:h}" "${LAUNCHD_LOG:h}"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>$SCRIPT</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>4</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$LAUNCHD_LOG</string>
    <key>StandardErrorPath</key>
    <string>$LAUNCHD_LOG</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST"

# bootout vorher: sonst scheitert bootstrap bei bereits registrierter Plist
# gelegentlich mit "Input/output error".
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

print "Registriert. Status:"
launchctl print "gui/$(id -u)/$LABEL" | grep -E "state =|path =|program =" || true

print ""
print "Fertig: Berichtsheft wird jede Nacht um 4:00 Uhr aktualisiert."
print "Logs:  ~/Library/Logs/Berichtsheft-refresh.log  und  $LAUNCHD_LOG"
print ""
print "Damit der Mac um 4 Uhr wach ist (einmalig, braucht dein Passwort):"
print "  sudo pmset repeat wakeorpoweron MTWRFSU 03:55:00"
print "Und im iPhone/Xcode: Fenster > Devices and Simulators > iPhone >"
print "  'Connect via network' aktivieren; iPhone nachts im WLAN und am Ladekabel."
