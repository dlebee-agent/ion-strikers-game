#!/usr/bin/env bash
# End-to-end check for the spin bot: dedicated server + proxy + a scripted
# client that fires straight up. Passes when the client is credited with hits
# and its own yaw is seen spinning in the snapshots.
#
#   tools/dev/spin-bot-check.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GAME="$ROOT/game"
SERVER_PORT="${SERVER_PORT:-7801}"
PROXY_PORT="${PROXY_PORT:-7802}"
API_PORT="${API_PORT:-8802}"
work="$(mktemp -d)"

cleanup() {
	kill "$server_pid" "$proxy_pid" 2>/dev/null || true
	wait "$server_pid" "$proxy_pid" 2>/dev/null || true
	rm -rf "$work"
}
trap cleanup EXIT

godot --headless --path "$GAME" -- --dedicated --port "$SERVER_PORT" > "$work/server.log" 2>&1 &
server_pid=$!
godot --headless --path "$GAME" --script res://tools/spin_bot.gd -- \
	--enet-port "$PROXY_PORT" --api-port "$API_PORT" \
	> "$work/proxy.log" 2>&1 &
proxy_pid=$!

for _ in $(seq 1 40); do
	grep -q "ENet proxy" "$work/proxy.log" 2>/dev/null && grep -q "listening\|admin password" "$work/server.log" 2>/dev/null && break
	sleep 0.25
done

godot --headless --path "$GAME" --script res://tools/spin_bot_check.gd -- \
	--proxy-port "$PROXY_PORT" --server-port "$SERVER_PORT" \
	2>&1 | grep '^\[check\]'
status=${PIPESTATUS[0]}

echo "--- proxy log"
grep -E '^\[(spinbot|enet|map|aim|hit)\]' "$work/proxy.log" | head -40
exit "$status"
