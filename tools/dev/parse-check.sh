#!/usr/bin/env bash
# Parse every script in the project and report the ones that will not
# compile.
#
# The headless check tools only load what they themselves use, so a broken
# UI script can sit in a commit that passed all of them: nothing ever opened
# it. This opens all of them.
#
# Godot's own --check-only does the work. Loading a script and testing the
# result is not enough, since a script whose body will not resolve still
# loads and hands back a real resource; reloading one instead reports
# failures for autoloads and anything with a live instance. Neither stands
# in for the parser.
#
#   tools/dev/parse-check.sh          all scripts, 8 at a time
#   JOBS=1 tools/dev/parse-check.sh   one at a time
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GAME="$ROOT/game"
JOBS="${JOBS:-8}"

cd "$GAME" || exit 1

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Checking one script at a time means the autoload singletons are not
# registered, so every reference to one reads as an undeclared identifier.
# Those lines are dropped by name, rather than the whole class of "not
# found" error, so a genuine typo still shows up.
autoloads=$(sed -n '/^\[autoload\]/,/^\[/p' project.godot \
	| sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' \
	| paste -sd '|' -)
[ -n "$autoloads" ] || autoloads='__no_autoloads__'
export PARSE_CHECK_AUTOLOADS="$autoloads"

# The per-file check lives in its own script: passed to xargs inline it
# overruns the length limit BSD xargs allows for an -I replacement, and the
# run silently checks nothing.
cat > "$work/one.sh" <<'ONE'
#!/usr/bin/env bash
out=$(godot --headless --check-only --script "$1" 2>&1)
errs=$(printf '%s' "$out" \
	| grep -iE 'parse error|compile error' \
	| grep -vE "Identifier not found: (${PARSE_CHECK_AUTOLOADS})\$")
if [ -n "$errs" ]; then
	printf 'FAIL %s\n' "$1"
	printf '%s\n' "$errs" | sed 's/^/     /' | head -3
fi
ONE
chmod +x "$work/one.sh"

find . -name '*.gd' -not -path './.godot/*' \
	| sed 's|^\./|res://|' \
	| sort \
	| xargs -P "$JOBS" -n 1 "$work/one.sh" > "$work/report"

checked=$(find . -name '*.gd' -not -path './.godot/*' | wc -l | tr -d ' ')
failed=$(grep -c '^FAIL ' "$work/report" || true)

cat "$work/report"
echo ""
echo "$checked scripts checked"
echo "FAILURES: $failed"
[ "$failed" -eq 0 ]
