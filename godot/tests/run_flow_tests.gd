extends SceneTree

## Headless flow tests for the screen state machine in main.gd.
## Run: godot --headless --path godot -s res://tests/run_flow_tests.gd

var _failures := 0
var _passes := 0
var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run_tests()
	return true

func _run_tests() -> void:
	var save_path: String = "user://slime_save_v2.json"
	var had_save := FileAccess.file_exists(save_path)
	var save_backup := ""
	if had_save:
		save_backup = FileAccess.get_file_as_string(save_path)

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate()
	root.add_child(main)

	var title: Control = main.get_node("CanvasLayer/TitleScreen")
	var opening: Control = main.get_node("CanvasLayer/OpeningScreen")
	var frame: Control = main.get_node("CanvasLayer/Frame")
	var select: Control = main.get_node("CanvasLayer/SelectScreen")
	var result: Control = main.get_node("CanvasLayer/Frame/Margin/VBox/ResultScreen")
	var game: Control = main.get_node("GameScreen")
	var next_button: Button = main.get_node(
		"CanvasLayer/OpeningScreen/Margin/VBox/TextPanel/Margin/TextVBox/Actions/OpeningNextButton"
	)

	main._characters[0]["opening_seen"] = false
	main._characters[0]["level"] = 1
	main._characters[0]["finish_total"] = 0

	_check(title.visible and not frame.visible and not game.visible, "boot: title screen only")

	main._on_title_start_pressed()
	_check(select.visible and not frame.visible and not title.visible, "title start -> select screen")

	var card0_name: Label = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/Margin/VBox/NameLabel")
	var card1_name: Label = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card1/Margin/VBox/NameLabel")
	_check(card0_name.text != "？？？" and card1_name.text != "？？？", "select: both cards populated")

	main._on_character_start_pressed(0)
	_check(opening.visible and not select.visible, "first start -> opening screen")
	_check_eq(main._opening_page, 0, "opening starts at page 0")

	var pages: Array = main._characters[0]["opening_pages"]
	for i in range(pages.size() - 1):
		main._on_opening_next_pressed()
	_check(opening.visible, "opening: still open on last page")
	_check_eq(String(next_button.text), "はじめる ▶", "opening: last page button label")

	main._on_opening_next_pressed()
	_check(game.visible and not opening.visible, "opening end -> game screen")
	_check(bool(main._characters[0]["opening_seen"]), "opening marked as seen")

	var brush_a: Node2D = main.get_node("GameScreen/Playfield/BrushA")
	var brush_d: Node2D = main.get_node("GameScreen/Playfield/BrushD")
	var brush_e: Node2D = main.get_node("GameScreen/Playfield/BrushE")
	_check(brush_a.visible, "Lv1: soft brush available")
	_check(not brush_d.visible, "Lv1: fine-point brush locked")
	_check(not brush_e.visible, "Lv1: rotating brush locked")
	_check(bool(brush_e.is_rotating), "rotating brush: scene marks it as rotating")

	main._on_day_finished({
		"species_id": "general",
		"species_name": "test",
		"day_finish_count": 4,
		"banked_finish_count": 4,
		"failed_by_pain": false
	})
	_check(result.visible and frame.visible and not game.visible, "day end -> result screen")

	main._on_return_pressed()
	_check(select.visible and not result.visible, "result return -> select screen")

	main._on_character_start_pressed(0)
	_check(game.visible and not opening.visible, "second start skips opening")

	# Opening flag survives a reload through the save file.
	var reloaded: Control = main_scene.instantiate()
	root.add_child(reloaded)
	_check(bool(reloaded._characters[0]["opening_seen"]), "opening_seen persisted to save")

	if had_save:
		var file := FileAccess.open(save_path, FileAccess.WRITE)
		file.store_string(save_backup)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	print("---")
	print("Passed: %d, Failed: %d" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures += 1
		printerr("FAIL: %s" % label)

func _check_eq(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (expected %s, got %s)" % [label, expected, actual])
