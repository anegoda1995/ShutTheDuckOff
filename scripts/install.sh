#!/bin/bash
# Installs ShutTheDuckOff for the current user:
#   - /Applications/ShutTheDuckOff.app, started at login by a LaunchAgent
#   - if VLC is installed, the noduck plugin and "noduck" in VLC's extraintf setting
# Works from a release folder (app next to this script) and from the source tree after `make`.
# Undo everything with uninstall.sh.
set -euo pipefail

ID=io.github.anegoda1995.shuttheduckoff
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="$HOME/Library/Application Support/ShutTheDuckOff"
PLUGINS="$DATA/vlc-plugins"
PLIST="$HOME/Library/LaunchAgents/$ID.plist"
VLCRC="$HOME/Library/Preferences/org.videolan.vlc/vlcrc"

for dir in "$HERE" "$HERE/../build"; do
	if [ -d "$dir/ShutTheDuckOff.app" ]; then SRC="$(cd "$dir" && pwd)"; break; fi
done
if [ -z "${SRC:-}" ]; then echo "ShutTheDuckOff.app not found: run make first."; exit 1; fi
# Check before anything is replaced: stopping here later would leave the app stopped until the next run.
if [ -d /Applications/VLC.app ] && [ -f "$SRC/libnoduck_plugin.dylib" ] && pgrep -xq VLC; then
	echo "Quit VLC first, then run this again."
	exit 1
fi

# The app
launchctl bootout "gui/$(id -u)/$ID" 2>/dev/null || true
rm -rf /Applications/ShutTheDuckOff.app
cp -R "$SRC/ShutTheDuckOff.app" /Applications/
xattr -dr com.apple.quarantine /Applications/ShutTheDuckOff.app 2>/dev/null || true

# VLC plugin (VLC 3.0.x). VLC.app itself is not modified: VLC finds the plugin through VLC_PLUGIN_PATH.
if [ -d /Applications/VLC.app ] && [ -f "$SRC/libnoduck_plugin.dylib" ]; then
	mkdir -p "$PLUGINS"
	cp "$SRC/libnoduck_plugin.dylib" "$PLUGINS/"
	xattr -d com.apple.quarantine "$PLUGINS/libnoduck_plugin.dylib" 2>/dev/null || true
	rm -f "$PLUGINS/plugins.dat"
	# Add noduck to extraintf (Preferences > All > Interface > Control interfaces), keeping anything already there.
	mkdir -p "$(dirname "$VLCRC")"
	[ -f "$VLCRC" ] || printf '[core]\n#extraintf=\n' > "$VLCRC"
	[ -f "$DATA/vlcrc.backup" ] || cp -p "$VLCRC" "$DATA/vlcrc.backup"
	current=$(grep -E '^extraintf=' "$VLCRC" | head -1 | cut -d= -f2- || true)
	case ":$current:" in
		*:noduck:*) ;;
		*)
			new="${current:+$current:}noduck"
			if grep -qE '^extraintf=' "$VLCRC"; then
				sed -i '' "s/^extraintf=.*/extraintf=$new/" "$VLCRC"
			elif grep -qE '^#extraintf=' "$VLCRC"; then
				sed -i '' "s/^#extraintf=.*/extraintf=$new/" "$VLCRC"
			else
				printf '\n[core]\nextraintf=%s\n' "$new" >> "$VLCRC"
			fi
			;;
	esac
	launchctl setenv VLC_PLUGIN_PATH "$PLUGINS"
	echo "VLC plugin installed (restart VLC if it was open before)."
fi

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
