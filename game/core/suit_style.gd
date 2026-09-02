class_name SuitStyle
extends RefCounted

## Suit finishes the player can pick in settings. Every one keeps the team
## readable: the colour is either the body or the glowing seams, never neither.
## This is a client preference, not a lobby lock. Ids are the stored form;
## labels are what the menu shows.

const COLOUR := "colour"
const COLOUR_HOT := "colour_hot"
const DARK := "dark"
const WHITE := "white"
const STYLES: Array[String] = [COLOUR, COLOUR_HOT, DARK, WHITE]
const DEFAULT := COLOUR


static func normalize(style: String) -> String:
	var lower := style.to_lower()
	if lower in STYLES:
		return lower
	return DEFAULT


static func index_of(style: String) -> int:
	return STYLES.find(normalize(style))


static func from_index(idx: int) -> String:
	if idx >= 0 and idx < STYLES.size():
		return STYLES[idx]
	return DEFAULT


## True for the finishes whose body is not the team colour, so the seams have
## to carry it and glow in it.
static func seams_carry_team(style: String) -> bool:
	var s := normalize(style)
	return s == DARK or s == WHITE


static func label_for(style: String) -> String:
	match normalize(style):
		COLOUR_HOT:
			return "Colour · hot seams"
		DARK:
			return "Dark · colour seams"
		WHITE:
			return "White · colour seams"
		_:
			return "Colour · dark seams"


static func blurb_for(style: String) -> String:
	match normalize(style):
		COLOUR_HOT:
			return "Team-colour suit, seams glow white-hot."
		DARK:
			return "Black suit, seams glow in the team colour."
		WHITE:
			return "White suit, seams glow in the team colour."
		_:
			return "Team-colour suit with dark seams."
