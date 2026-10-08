#!/bin/bash
# Removes everything install.sh added and takes "noduck" out of VLC's extraintf setting again.
set -euo pipefail

ID=io.github.anegoda1995.shuttheduckoff
DATA="$HOME/Library/Application Support/ShutTheDuckOff"
PLIST="$HOME/Library/LaunchAgents/$ID.plist"
VLCRC="$HOME/Library/Preferences/org.videolan.vlc/vlcrc"

if pgrep -xq VLC; then echo "Quit VLC first, then run this again."; exit 1; fi

# On SIGTERM the app stops protecting; even if it were killed, macOS gives every app its sound back.
launchctl bootout "gui/$(id -u)/$ID" 2>/dev/null || true
rm -f "$PLIST"
rm -rf /Applications/ShutTheDuckOff.app
defaults delete "$ID" 2>/dev/null || true
tccutil reset AudioCapture "$ID" >/dev/null 2>&1 || true
launchctl unsetenv VLC_PLUGIN_PATH

if [ -f "$VLCRC" ]; then
	current=$(grep -E '^extraintf=' "$VLCRC" | head -1 | cut -d= -f2- || true)
	rest=$(printf '%s' "$current" | tr ':' '\n' | grep -vx noduck | paste -sd: - || true)
	if [ -n "$rest" ]; then
		sed -i '' "s/^extraintf=.*/extraintf=$rest/" "$VLCRC"
	else
		sed -i '' "s/^extraintf=.*/#extraintf=/" "$VLCRC"
	fi
fi

rm -rf "$DATA"
echo "Uninstalled."
