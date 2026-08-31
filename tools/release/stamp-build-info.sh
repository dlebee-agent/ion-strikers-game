#!/usr/bin/env bash
# Rewrite BuildInfo.BUILD with the version being released.
#
#   tools/release/stamp-build-info.sh 0.0.1-rc2
#
# application/config/version in project.godot stays the numeric source of truth
# that the exporters read for bundle metadata. This carries the full tag version,
# pre-release suffix and all, so a dedicated server reports exactly which build
# it is running rather than just its numeric version.
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
	echo "usage: stamp-build-info.sh <version>" >&2
	exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FILE="$ROOT/game/core/build_info.gd"

if ! grep -q '^const BUILD := ' "$FILE"; then
	printf 'stamp-build-info: no BUILD constant found in %s\n' "$FILE" >&2
	exit 1
fi

# Write via a temp file rather than sed -i, whose syntax differs between the
# GNU and BSD builds this runs on.
TMP="$(mktemp)"
sed -e "s|^const BUILD := .*|const BUILD := \"${VERSION}\"|" "$FILE" > "$TMP"
mv "$TMP" "$FILE"

grep -n '^const BUILD := ' "$FILE"
