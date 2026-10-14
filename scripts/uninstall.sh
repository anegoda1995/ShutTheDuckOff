#!/bin/bash
# Removes everything install.sh added, the app's settings and its permission.
set -euo pipefail

ID=io.github.anegoda1995.shuttheduckoff
PLIST="$HOME/Library/LaunchAgents/$ID.plist"

# On SIGTERM the app stops protecting; even if it were killed, macOS gives every app its sound back.
launchctl bootout "gui/$(id -u)/$ID" 2>/dev/null || true
rm -f "$PLIST"
rm -rf /Applications/ShutTheDuckOff.app
defaults delete "$ID" 2>/dev/null || true
tccutil reset AudioCapture "$ID" >/dev/null 2>&1 || true
echo "Uninstalled."
