#!/usr/bin/env bash
# Spin bot: an external proxy between the installed Ion Strikers client and
# the game server. Others see you spinning; your shots land on the nearest
# visible enemy's head. Your own view stays normal.
#
#   tools/spinbot.sh                 start the proxy (API on 8790, ENet on 7790)
#   tools/spinbot.sh --play          also run the game from source through the
#                                    proxy: works on every server, local ones too
#   tools/spinbot.sh --launch        also start the installed app pointed at the
#                                    API proxy: hosted servers only (no --proxy hook)
#   tools/spinbot.sh --spin 360      slower spin (deg/s); --spin 0 keeps real yaw
#   tools/spinbot.sh --no-aim        spin only
#   tools/spinbot.sh --upstream H:P  relay to a known server without the API
#
# Any other option is passed through to game/tools/spin_bot.gd.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="/Applications/Ion Strikers.app/Contents/MacOS/Ion Strikers"
API_PORT=8790
ENET_PORT=7790
LAUNCH=0
PLAY=0
ARGS=()

while [ $# -gt 0 ]; do
	case "$1" in
		--launch) LAUNCH=1; shift ;;
		--play) PLAY=1; shift ;;
		--api-port) API_PORT="$2"; ARGS+=("$1" "$2"); shift 2 ;;
		--enet-port) ENET_PORT="$2"; ARGS+=("$1" "$2"); shift 2 ;;
		*) ARGS+=("$1"); shift ;;
	esac
done

if [ "$PLAY" = 1 ]; then
	godot --path "$ROOT/game" -- --proxy "127.0.0.1:$ENET_PORT" --api-url "http://127.0.0.1:$API_PORT" >/dev/null 2>&1 &
	echo "[spinbot] running the game from source with --proxy 127.0.0.1:$ENET_PORT"
fi

if [ "$LAUNCH" = 1 ]; then
	[ -x "$APP" ] || { echo "not found: $APP" >&2; exit 1; }
	"$APP" -- --api-url "http://127.0.0.1:$API_PORT" >/dev/null 2>&1 &
	echo "[spinbot] launched Ion Strikers with --api-url http://127.0.0.1:$API_PORT"
fi

exec godot --headless --path "$ROOT/game" --script res://tools/spin_bot.gd -- "${ARGS[@]+"${ARGS[@]}"}"
