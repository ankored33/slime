class_name ProgressStore
extends RefCounted

const SAVE_PATH := "user://slime_save_v2.json"

## 初回チュートリアルの既読フラグ（キャラ横断のグローバル状態）。
var tutorial_seen := false

func save(characters: Array[Dictionary]) -> void:
	var payload := {
		"version": 2,
		"tutorial_seen": tutorial_seen,
		"characters": []
	}
	for chara in characters:
		payload["characters"].append({
			"id": str(chara["id"]),
			"level": int(chara["level"]),
			"finish_total": int(chara["finish_total"]),
			"pain_fail_total": int(chara["pain_fail_total"]),
			"opening_seen": bool(chara["opening_seen"])
		})
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to save progress to %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(payload))
	file.close()

func load_into(characters: Array[Dictionary]) -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Failed to open save file: %s" % SAVE_PATH)
		return
	var raw := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save format is invalid; ignoring save file.")
		return
	tutorial_seen = bool(parsed.get("tutorial_seen", false))
	var loaded: Array = parsed.get("characters", [])
	var by_id: Dictionary = {}
	for entry in loaded:
		if typeof(entry) == TYPE_DICTIONARY:
			by_id[str(entry.get("id", ""))] = entry
	for index in range(characters.size()):
		var chara: Dictionary = characters[index]
		var character_id := str(chara["id"])
		if not by_id.has(character_id):
			continue
		var saved: Dictionary = by_id[character_id]
		chara["finish_total"] = max(0, int(saved.get("finish_total", 0)))
		chara["pain_fail_total"] = max(0, int(saved.get("pain_fail_total", 0)))
		chara["opening_seen"] = bool(saved.get("opening_seen", false))
		var saved_level := int(saved.get("level", 1))
		chara["level"] = GameRules.level_for_finish_total(
			int(chara["finish_total"]), saved_level)
		characters[index] = chara
