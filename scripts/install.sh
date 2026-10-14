#!/bin/bash
# Installs ShutTheDuckOff for the current user: /Applications/ShutTheDuckOff.app, started at login by a LaunchAgent.
# Works from a release folder (app next to this script) and from the source tree after `make`.
# Undo everything with uninstall.sh.
set -euo pipefail

ID=io.github.anegoda1995.shuttheduckoff
HERE="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/$ID.plist"

for dir in "$HERE" "$HERE/../build"; do
	if [ -d "$dir/ShutTheDuckOff.app" ]; then SRC="$(cd "$dir" && pwd)"; break; fi
done
if [ -z "${SRC:-}" ]; then echo "ShutTheDuckOff.app not found: run make first."; exit 1; fi

# The app
launchctl bootout "gui/$(id -u)/$ID" 2>/dev/null || true
rm -rf /Applications/ShutTheDuckOff.app
cp -R "$SRC/ShutTheDuckOff.app" /Applications/
xattr -dr com.apple.quarantine /Applications/ShutTheDuckOff.app 2>/dev/null || true

# Start at login
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$ID</string>
	<key>AssociatedBundleIdentifiers</key>
	<string>$ID</string>
	<key>ProgramArguments</key>
	<array>
		<string>/Applications/ShutTheDuckOff.app/Contents/MacOS/ShutTheDuckOff</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Installed. macOS now asks for \"System Audio Recording\": allow it for ShutTheDuckOff."
