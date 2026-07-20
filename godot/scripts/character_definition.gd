class_name CharacterDefinition
extends Resource

## Immutable authoring data for a character. Runtime progress is deliberately
## produced as a dictionary by to_runtime_data(), then owned by ProgressStore.

@export var id := ""
@export var character_name := ""
@export var epithet := ""
@export var name_after_opening := ""
@export var epithet_after_opening := ""
@export var portrait := ""
@export var portrait_after_opening := ""
@export var portrait_captured := ""
@export var portrait_day_intro := ""
@export var result := ""
@export var game_background := ""
@export var expressions: Dictionary = {}
@export_multiline var profile := ""
@export_multiline var profile_after_opening := ""
@export var color := Color.WHITE
@export var left: Dictionary = {}
@export var right: Dictionary = {}
@export var mouth: Dictionary = {}

func to_runtime_data() -> Dictionary:
	return {
		"id": id,
		"name": character_name,
		"epithet": epithet,
		"name_after_opening": name_after_opening,
		"epithet_after_opening": epithet_after_opening,
		"portrait": portrait,
		"portrait_after_opening": portrait_after_opening,
		"portrait_captured": portrait_captured,
		"portrait_day_intro": portrait_day_intro,
		"result": result,
		"game_background": game_background,
		"expressions": expressions.duplicate(true),
		"dialogue": DialogueLoader.load_dialogue(id),
		"profile": profile,
		"profile_after_opening": profile_after_opening,
		"color": color,
		"left": left.duplicate(true),
		"right": right.duplicate(true),
		"mouth": mouth.duplicate(true),
		"level": 1,
		"finish_total": 0,
		"pain_fail_total": 0,
		"opening_seen": false,
		"opening_pages": OpeningLoader.load_pages(id)
	}
