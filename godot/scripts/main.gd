extends Control

const MAX_LEVEL := 8
const LEVEL_STEP := 3
const SAVE_PATH := "user://slime_save_v1.json"

var _species_list: Array[Dictionary] = [
	{
		"id": "mint",
		"name": "Mint Slime",
		"color": Color(0.45, 1.0, 0.8, 0.92),
		"left": {
			"position": Vector2(552.5, 480.0),
			"radius": 110.0,
			"image": ""
		},
		"right": {
			"position": Vector2(753.5, 477.0),
			"radius": 110.0,
			"image": ""
		},
		"level": 1,
		"finish_total": 0,
		"pain_fail_total": 0
	},
	{
		"id": "peach",
		"name": "Peach Slime",
		"color": Color(1.0, 0.71, 0.78, 0.92),
		"left": {
			"position": Vector2(540.0, 485.0),
			"radius": 124.0,
			"image": ""
		},
		"right": {
			"position": Vector2(766.0, 482.0),
			"radius": 124.0,
			"image": ""
		},
		"level": 1,
		"finish_total": 0,
		"pain_fail_total": 0
	},
	{
		"id": "azure",
		"name": "Azure Slime",
		"color": Color(0.47, 0.73, 1.0, 0.92),
		"left": {
			"position": Vector2(560.0, 474.0),
			"radius": 98.0,
			"image": ""
		},
		"right": {
			"position": Vector2(746.0, 471.0),
			"radius": 98.0,
			"image": ""
		},
		"level": 1,
		"finish_total": 0,
		"pain_fail_total": 0
	}
]

var _selected_species_index := 0
var _last_result: Dictionary = {}

@onready var _screen_title: Label = $CanvasLayer/Frame/Margin/VBox/Header/ScreenTitle
@onready var _screen_subtitle: Label = $CanvasLayer/Frame/Margin/VBox/Header/ScreenSubtitle
@onready var _select_screen: Control = $CanvasLayer/Frame/Margin/VBox/SelectScreen
@onready var _game_screen: Control = $GameScreen
@onready var _result_screen: Control = $CanvasLayer/Frame/Margin/VBox/ResultScreen
@onready var _species_list_ui: ItemList = $CanvasLayer/Frame/Margin/VBox/SelectScreen/HBox/SpeciesList
@onready var _species_detail: RichTextLabel = $CanvasLayer/Frame/Margin/VBox/SelectScreen/HBox/DetailPanel/Margin/SpeciesDetail
@onready var _start_button: Button = $CanvasLayer/Frame/Margin/VBox/SelectScreen/Actions/StartButton
@onready var _result_body: RichTextLabel = $CanvasLayer/Frame/Margin/VBox/ResultScreen/ResultPanel/Margin/ResultBody
@onready var _return_button: Button = $CanvasLayer/Frame/Margin/VBox/ResultScreen/Actions/ReturnButton

func _ready() -> void:
	_species_list_ui.item_selected.connect(_on_species_selected)
	_start_button.pressed.connect(_on_start_pressed)
	_return_button.pressed.connect(_on_return_pressed)
	_game_screen.day_finished.connect(_on_day_finished)
	_load_progress()
	_refresh_species_list()
	_show_select_screen()

func _refresh_species_list() -> void:
	_species_list_ui.clear()
	for species: Dictionary in _species_list:
		_species_list_ui.add_item("%s  Lv.%d" % [species["name"], species["level"]])
	_species_list_ui.select(_selected_species_index)
	_refresh_species_detail()

func _refresh_species_detail() -> void:
	var species: Dictionary = _species_list[_selected_species_index]
	var left_cfg: Dictionary = species.get("left", {})
	var left_radius := float(left_cfg.get("radius", 100.0))
	_species_detail.text = (
		"[b]%s[/b]\n"
		+ "Level: %d / %d\n"
		+ "Total Finish: %d\n"
		+ "Pain Failures: %d\n"
		+ "Hitbox Radius: %d\n\n"
		+ "Growth:\n"
		+ "- Higher polish gain\n"
		+ "- Better pain tolerance\n"
		+ "- More retained polish after FINISH"
	) % [
		species["name"],
		species["level"],
		MAX_LEVEL,
		species["finish_total"],
		species["pain_fail_total"],
		int(round(left_radius))
	]

func _show_select_screen() -> void:
	_screen_title.text = "Slime Select"
	_screen_subtitle.text = "Choose a species pair to condition for the day."
	_select_screen.visible = true
	_game_screen.visible = false
	_result_screen.visible = false
	_refresh_species_list()

func _show_game_screen() -> void:
	_screen_title.text = "Conditioning"
	_screen_subtitle.text = "Drag brushes, toggle them on, and cash out before pain reaches 100%."
	_select_screen.visible = false
	_game_screen.visible = true
	_result_screen.visible = false

func _show_result_screen() -> void:
	_screen_title.text = "Result"
	_screen_subtitle.text = "Review the day and return to species selection."
	_select_screen.visible = false
	_game_screen.visible = false
	_result_screen.visible = true
	_render_result()

func _on_species_selected(index: int) -> void:
	_selected_species_index = index
	_refresh_species_detail()

func _on_start_pressed() -> void:
	var species: Dictionary = _species_list[_selected_species_index]
	_game_screen.setup_species(species)
	_show_game_screen()

func _on_return_pressed() -> void:
	_show_select_screen()

func _on_day_finished(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	var species: Dictionary = _species_list[_selected_species_index]
	species["finish_total"] = int(species["finish_total"]) + int(result.get("banked_finish_count", 0))
	if bool(result.get("failed_by_pain", false)):
		species["pain_fail_total"] = int(species["pain_fail_total"]) + 1
	species["level"] = min(MAX_LEVEL, 1 + int(species["finish_total"]) / LEVEL_STEP)
	_species_list[_selected_species_index] = species
	_save_progress()
	_show_result_screen()

func _render_result() -> void:
	var species: Dictionary = _species_list[_selected_species_index]
	var failed := bool(_last_result.get("failed_by_pain", false))
	var status_text := "Pain limit reached. The day's finish was halved." if failed else "Voluntary cash-out. All finish secured."
	_result_body.text = (
		"[b]%s[/b]\n"
		+ "%s\n\n"
		+ "Today Finish: %d\n"
		+ "Banked Finish: %d\n"
		+ "Species Level: %d / %d\n"
		+ "Total Finish: %d\n"
		+ "Pain Failures: %d\n\n"
		+ "Unlocked growth focus:\n"
		+ "- Better polish gain\n"
		+ "- Better pain tolerance\n"
		+ "- Better post-FINISH retention"
	) % [
		str(_last_result.get("species_name", "Slime")),
		status_text,
		int(_last_result.get("day_finish_count", 0)),
		int(_last_result.get("banked_finish_count", 0)),
		int(species["level"]),
		MAX_LEVEL,
		int(species["finish_total"]),
		int(species["pain_fail_total"])
	]

func _save_progress() -> void:
	var payload := {
		"version": 1,
		"species": []
	}
	for species: Dictionary in _species_list:
		payload["species"].append({
			"id": str(species.get("id", "")),
			"level": int(species.get("level", 1)),
			"finish_total": int(species.get("finish_total", 0)),
			"pain_fail_total": int(species.get("pain_fail_total", 0))
		})
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to save progress to %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(payload))
	file.close()

func _load_progress() -> void:
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
	var loaded_species: Array = parsed.get("species", [])
	var by_id: Dictionary = {}
	for entry in loaded_species:
		if typeof(entry) == TYPE_DICTIONARY:
			by_id[str(entry.get("id", ""))] = entry
	for index in range(_species_list.size()):
		var species: Dictionary = _species_list[index]
		var sid := str(species.get("id", ""))
		if not by_id.has(sid):
			continue
		var saved: Dictionary = by_id[sid]
		species["finish_total"] = max(0, int(saved.get("finish_total", 0)))
		species["pain_fail_total"] = max(0, int(saved.get("pain_fail_total", 0)))
		var derived_level := 1 + int(species["finish_total"]) / LEVEL_STEP
		var saved_level := int(saved.get("level", derived_level))
		species["level"] = min(MAX_LEVEL, max(1, max(saved_level, derived_level)))
		_species_list[index] = species
