#!/bin/bash
# thinking-orb.sh — Start/Stop des Thinking-Orb-Overlays.
# Start: ./thinking-orb.sh      Stop: ./thinking-orb.sh stop
set -euo pipefail
BIN="$HOME/.hermes/thinking-orb/app/Thinking Orb.app/Contents/MacOS/thinking-orb-app"
if [ "${1:-}" = "stop" ]; then
  pkill -x thinking-orb-app && echo "stopped" || echo "not running"
  exit 0
fi
if pgrep -x thinking-orb-app >/dev/null; then
  echo "already running"
  exit 0
fi
[ -x "$BIN" ] || { echo "binary missing — erst ./native/build-app.sh ausführen" >&2; exit 1; }
"$BIN" >/dev/null 2>&1 &
echo "thinking-orb started"
