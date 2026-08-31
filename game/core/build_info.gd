class_name BuildInfo
extends RefCounted

## Release identity: what the console reports and what a dedicated server tells
## the Game API it is running.
##
## `application/config/version` in project.godot is the source of truth for the
## numeric version, and the exporters read it straight out of there for bundle
## metadata. Apple and Windows only accept digits and dots in those fields, so a
## tag's pre-release part cannot live there — BUILD carries the full tag version
## instead, and tools/release/stamp-build-info.sh rewrites it during a release.
## Untagged builds keep the placeholder and report themselves as a dev build.

const BUILD := "dev"


static func is_release() -> bool:
	return BUILD != "dev"


## Numeric MAJOR.MINOR.PATCH, matching what the exporters stamp into bundles.
static func core() -> String:
	var declared := str(ProjectSettings.get_setting("application/config/version", ""))
	return declared if not declared.is_empty() else "0.0.0"


## Full release identity, including any pre-release suffix.
static func version() -> String:
	if is_release():
		return BUILD
	return "%s-dev" % core()


static func godot_version() -> String:
	var v := Engine.get_version_info()
	return "%s.%s.%s.%s" % [v["major"], v["minor"], v["patch"], v["status"]]
