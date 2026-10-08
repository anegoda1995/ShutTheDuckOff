#!/bin/bash
# Is ShutTheDuckOff installed and running, what did it do last, and is VLC immune?
ID=io.github.anegoda1995.shuttheduckoff
PLUGINS="$HOME/Library/Application Support/ShutTheDuckOff/vlc-plugins"
VLCRC="$HOME/Library/Preferences/org.videolan.vlc/vlcrc"

row() { printf '  %-24s %s\n' "$1" "$2"; }

row "app" "$([ -d /Applications/ShutTheDuckOff.app ] && echo installed || echo "not installed")"
pid=$(pgrep -f /Applications/ShutTheDuckOff.app/Contents/MacOS/ShutTheDuckOff | head -1)
row "running" "$([ -n "$pid" ] && echo "yes (pid $pid)" || echo no)"
if [ -n "$pid" ]; then
	last=$(/usr/bin/log show --last 1d --style compact --predicate "subsystem == '$ID' AND processID == $pid" 2>/dev/null \
		| grep -E 'protecting|cannot' | tail -1 | sed -E 's/^[0-9-]+ ([0-9:.]+) .*\] /\1 /')
	row "last action" "${last:-waiting for a call}"
fi
row "VLC plugin" "$([ -f "$PLUGINS/libnoduck_plugin.dylib" ] && echo installed || echo "not installed")"
row "VLC extraintf" "$(grep -E '^#?extraintf=' "$VLCRC" 2>/dev/null | head -1)"

vlc=$(pgrep -x VLC | head -1)
if [ -z "$vlc" ]; then
	row "VLC" "not running"
elif /usr/bin/log show --last 1d --style compact --predicate "subsystem == '$ID' AND processID == $vlc" 2>/dev/null | grep -q 'noduck: active'; then
	row "VLC (pid $vlc)" "immune (noduck active)"
else
	row "VLC (pid $vlc)" "not immune: restart VLC"
fi
