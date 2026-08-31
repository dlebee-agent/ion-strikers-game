#!/usr/bin/env bash
# Gate a release tag against the version declared in project.godot.
#
#   tools/release/check-version.sh game/0.0.1-rc2
#
# Tags are game/<version>, where <version> is MAJOR.MINOR.PATCH with an optional
# pre-release suffix and optional build metadata. Only the numeric core has to
# match application/config/version, because that is the part Apple and Windows
# stamp into bundle metadata; -rc2 and +g9f2fe18 are free to decorate it.
#
# Prints "tag version core" on success so callers can read the parts back.
set -euo pipefail

TAG="${1:-}"
if [ -z "$TAG" ]; then
	echo "usage: check-version.sh <tag>" >&2
	exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

VERSION="${TAG#game/}"
if [ "$VERSION" = "$TAG" ] || [ -z "$VERSION" ]; then
	printf "expected a game/<version> tag, got '%s'\n" "$TAG" >&2
	exit 1
fi

# Deliberately narrow: a bare -rc, an uppercase -RC1 or a stray -wip is a typo,
# not a release. Widen the alternation here if a new channel is ever needed.
if ! printf '%s' "$VERSION" \
	| grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.?[0-9]+)?(\+[0-9A-Za-z.-]+)?$'; then
	cat >&2 <<EOF
'$VERSION' is not an accepted version.

  expected  MAJOR.MINOR.PATCH[-(alpha|beta|rc)N][+BUILD]
  examples  0.0.1   0.0.1-rc2   0.1.0-beta.3   0.0.1-rc2+g9f2fe18
EOF
	exit 1
fi

CORE="${VERSION%%-*}"
CORE="${CORE%%+*}"

DECLARED="$(sed -n 's/^config\/version="\(.*\)"[[:space:]]*$/\1/p' "$ROOT/game/project.godot" | head -1)"
if [ -z "$DECLARED" ]; then
	echo "no config/version in game/project.godot to validate against" >&2
	exit 1
fi

if [ "$CORE" != "$DECLARED" ]; then
	cat >&2 <<EOF
version mismatch: tag says $CORE, project.godot declares $DECLARED

  tag       $TAG
  core      $CORE
  declared  $DECLARED

Bump config/version in game/project.godot to $CORE and commit it, or retag.
EOF
	exit 1
fi

printf '%s %s %s\n' "$TAG" "$VERSION" "$CORE"
