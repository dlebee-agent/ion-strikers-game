#!/usr/bin/env bash
# Launch the Ion Strikers dedicated server from a release archive.
#
# Every argument is forwarded, so anything boot.gd parses works:
#
#   ./run-server.sh --port 7777 --mgmt-port 9090 \
#       --register --allow-dynamic-create --api-url https://api.example.com \
#       --public-host game.example.com --server-id eu-west-1 \
#       --join-secret "$JOIN_TOKEN_SECRET"
#
# Without --register the server runs standalone and prints a generated admin
# password on startup.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

BIN="$HERE/ion-strikers-server.x86_64"
if [ ! -x "$BIN" ]; then
	# The macOS archive ships an .app bundle whose inner binary is named by the
	# engine, so glob for it rather than hardcoding a name.
	BIN="$(/usr/bin/find "$HERE" -maxdepth 4 -type f -path '*/Contents/MacOS/*' -perm -u+x -print -quit)"
fi

if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
	printf 'run-server: no server binary found next to %s\n' "$HERE" >&2
	exit 1
fi

exec "$BIN" --headless -- --dedicated "$@"
