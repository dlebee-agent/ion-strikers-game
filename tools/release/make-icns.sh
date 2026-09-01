#!/usr/bin/env bash
# Build a macOS .icns from a square PNG (1024×1024 recommended).
# Usage: tools/release/make-icns.sh path/to/icon.png path/to/output.icns
set -euo pipefail

PNG="${1:?png path required}"
OUT="${2:?icns output path required}"

if [ ! -f "$PNG" ]; then
	printf 'make-icns: %s not found\n' "$PNG" >&2
	exit 1
fi

SET="$(mktemp -d)/icon.iconset"
mkdir -p "$SET"

sips -z 16 16 "$PNG" --out "$SET/icon_16x16.png" >/dev/null
sips -z 32 32 "$PNG" --out "$SET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$PNG" --out "$SET/icon_32x32.png" >/dev/null
sips -z 64 64 "$PNG" --out "$SET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$PNG" --out "$SET/icon_128x128.png" >/dev/null
sips -z 256 256 "$PNG" --out "$SET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$PNG" --out "$SET/icon_256x256.png" >/dev/null
sips -z 512 512 "$PNG" --out "$SET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$PNG" --out "$SET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$PNG" --out "$SET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$SET" -o "$OUT"
printf 'make-icns: wrote %s\n' "$OUT"
