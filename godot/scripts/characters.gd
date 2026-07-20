class_name CharacterDefs
extends RefCounted

## Character authoring data lives in data/characters/*.tres. This adapter
## preserves the runtime dictionary contract while ProgressStore owns the
## mutable fields (level, totals, and opening_seen).

const CHARACTER_PATHS: Array[String] = [
	"res://data/characters/general.tres",
	"res://data/characters/admiral.tres",
	"res://data/characters/mage.tres"
]

const REQUIRED_KEYS: Array[String] = [
	"id", "name", "epithet", "name_after_opening", "epithet_after_opening",
	"portrait", "portrait_after_opening", "result", "game_background",
	"expressions", "dialogue", "profile", "profile_after_opening", "color",
	"left", "right", "mouth", "level", "finish_total", "pain_fail_total",
	"opening_seen", "opening_pages"
]

static func display_name(chara: Dictionary) -> String:
	return _resolve_after_opening(chara, "name", "name_after_opening")

static func display_epithet(chara: Dictionary) -> String:
	return _resolve_after_opening(chara, "epithet", "epithet_after_opening")

static func _resolve_after_opening(chara: Dictionary, base_key: String, after_key: String) -> String:
	if bool(chara["opening_seen"]):
		var after := str(chara[after_key])
		if after != "":
			return after
	return str(chara[base_key])

static func _validate(chara: Dictionary) -> void:
	var id := str(chara.get("id", "?"))
	for key in REQUIRED_KEYS:
		if not chara.has(key):
			push_error("CharacterDefs: character '%s' is missing required key '%s'" % [id, key])
	for side in ["left", "right"]:
		var target: Dictionary = chara.get(side, {})
		if target.has("breast") and not target.has("breast_root"):
			push_error("CharacterDefs: character '%s' side '%s' has 'breast' but no 'breast_root'" % [id, side])

static func create() -> Array[Dictionary]:
	var characters: Array[Dictionary] = []
	for path in CHARACTER_PATHS:
		var definition := load(path)
		if definition is not CharacterDefinition:
			push_error("CharacterDefs: failed to load CharacterDefinition at %s" % path)
			continue
		var chara := (definition as CharacterDefinition).to_runtime_data()
		_validate(chara)
		characters.append(chara)
	return characters
