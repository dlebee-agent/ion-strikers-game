#!/usr/bin/env bash
# Start Game API + Game Server + client for local development.
# Ctrl+C (or any child exiting) tears the whole stack down.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_URL="${GAME_API_URL:-http://127.0.0.1:8080}"
LISTEN_ADDR="${LISTEN_ADDR:-:8080}"
ENET_PORT="${ENET_PORT:-7777}"
MGMT_PORT="${MGMT_PORT:-9090}"
MAX_LOBBIES="${MAX_LOBBIES:-20}"
JOIN_SECRET="${JOIN_TOKEN_SECRET:-dev-join-secret}"

PIDS=""
CLEANING=0

log() { printf '[dev] %s\n' "$*"; }

die() {
	printf '[dev] error: %s\n' "$*" >&2
	exit 1
}

kill_tree() {
	local sig="$1"
	local pid="$2"
	local child
	for child in $(pgrep -P "$pid" 2>/dev/null || true); do
		kill_tree "$sig" "$child"
	done
	kill "-$sig" "$pid" 2>/dev/null || true
}

cleanup() {
	if [ "$CLEANING" -eq 1 ]; then
		return
	fi
	CLEANING=1
	trap - INT TERM EXIT
	log "tearing down..."
	local pid
	for pid in $PIDS; do
		kill_tree TERM "$pid"
	done
	sleep 0.4
	for pid in $PIDS; do
		kill_tree KILL "$pid"
	done
	# Prefixer awks and anything else still attached to this shell.
	pkill -KILL -P $$ 2>/dev/null || true
	log "stopped"
}

trap cleanup INT TERM EXIT

find_godot() {
	if [ -n "${GODOT:-}" ]; then
		printf '%s\n' "$GODOT"
		return
	fi
	if command -v godot >/dev/null 2>&1; then
		command -v godot
		return
	fi
	local candidate
	for candidate in \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
		if [ -x "$candidate" ]; then
			printf '%s\n' "$candidate"
			return
		fi
	done
	return 1
}

wait_http() {
	local url="$1"
	local tries="${2:-50}"
	local i=0
	while [ "$i" -lt "$tries" ]; do
		if curl -sf "$url" >/dev/null 2>&1; then
			return 0
		fi
		i=$((i + 1))
		sleep 0.2
	done
	return 1
}

wait_tcp() {
	local port="$1"
	local tries="${2:-75}"
	local i=0
	while [ "$i" -lt "$tries" ]; do
		if (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1; then
			return 0
		fi
		i=$((i + 1))
		sleep 0.2
	done
	return 1
}

run_prefixed() {
	local tag="$1"
	shift
	"$@" > >(awk -v t="$tag" '{ print "[" t "] " $0; fflush() }') 2>&1 &
	PIDS="$PIDS $!"
}

alive() {
	kill -0 "$1" 2>/dev/null
}

command -v go >/dev/null 2>&1 || die "go not found on PATH"
command -v curl >/dev/null 2>&1 || die "curl not found on PATH"
GODOT="$(find_godot)" || die "godot not found (set GODOT or install Godot on PATH)"

mkdir -p "$ROOT/.dev"
log "building Game API..."
( cd "$ROOT/api" && go build -o "$ROOT/.dev/gameapi" ./cmd/gameapi )

log "starting Game API on ${LISTEN_ADDR}..."
LISTEN_ADDR="$LISTEN_ADDR" JOIN_TOKEN_SECRET="$JOIN_SECRET" run_prefixed api "$ROOT/.dev/gameapi"
API_PID="${PIDS##* }"
wait_http "$API_URL/health" || die "Game API did not become healthy at $API_URL/health"
alive "$API_PID" || die "Game API exited during startup"
log "Game API is up"

log "starting Game Server (ENet :${ENET_PORT}, mgmt :${MGMT_PORT})..."
run_prefixed server "$GODOT" --path "$ROOT/game" --headless -- \
	--dedicated --dev --register --allow-dynamic-create \
	--api-url "$API_URL" \
	--max-lobbies "$MAX_LOBBIES" \
	--server-id local-dev \
	--public-host 127.0.0.1 \
	--port "$ENET_PORT" \
	--mgmt-port "$MGMT_PORT" \
	--join-secret "$JOIN_SECRET"
SERVER_PID="${PIDS##* }"
wait_tcp "$MGMT_PORT" || die "Game Server management port :${MGMT_PORT} never opened"
alive "$SERVER_PID" || die "Game Server exited during startup"
log "Game Server is up"

log "starting game client..."
run_prefixed game "$GODOT" --path "$ROOT/game" -- --dev --api-url "$API_URL"
CLIENT_PID="${PIDS##* }"
sleep 0.4
alive "$CLIENT_PID" || die "game client exited during startup"
log "stack running — Ctrl+C to stop"

while :; do
	alive "$API_PID" || { log "Game API exited"; exit 0; }
	alive "$SERVER_PID" || { log "Game Server exited"; exit 0; }
	alive "$CLIENT_PID" || { log "game client exited"; exit 0; }
	sleep 0.5
done
