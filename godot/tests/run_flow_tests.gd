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
		"CanvasLayer/OpeningScreen/SplitView/TextPanel/Margin/TextVBox/Actions/OpeningNextButton"
	)

	main._characters[0]["opening_seen"] = false
	main._characters[0]["level"] = 1
	main._characters[0]["finish_total"] = 0
	main._characters[1]["opening_seen"] = false

	_check(title.visible and not frame.visible and not game.visible, "boot: title screen only")

	main._on_title_start_pressed()
	_check(select.visible and not frame.visible and not title.visible, "title start -> select screen")

	var card0_name: Label = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/Margin/VBox/PortraitArea/InfoOverlay/Margin/VBox/NameLabel")
	var card1_name: Label = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card1/Margin/VBox/PortraitArea/InfoOverlay/Margin/VBox/NameLabel")
	_check(card0_name.text != "？？？" and card1_name.text != "？？？", "select: both cards populated")
	var card0_portrait: TextureRect = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/Margin/VBox/PortraitArea/Portrait")
	var card1_portrait: TextureRect = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card1/Margin/VBox/PortraitArea/Portrait")
	_check(card0_portrait.texture != null, "select: general portrait loaded")
	_check(card1_portrait.texture != null, "select: admiral portrait loaded")
	_check(String(card0_portrait.texture.resource_path).ends_with("/general/portrait.png"),
		"select: general uses initial portrait before opening")
	var profile_body: RichTextLabel = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/Margin/VBox/PortraitArea/InfoOverlay/Margin/VBox/ProfileBody")
	_check(profile_body.fit_content, "select: profile overlay shrinks to its content")
	var instruction: Label = main.get_node("CanvasLayer/SelectScreen/InstructionOverlay/Label")
	_check_eq(instruction.text, "キャラクターを選択してください。", "select: instruction is overlaid")
	var card0_info: PanelContainer = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/Margin/VBox/PortraitArea/InfoOverlay")
	_check(absf(card0_info.anchor_left - (2.0 / 3.0)) < 0.001,
		"select: profile overlay uses the right third")
	var card0_button: Button = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/InteractionLayer/CardButton")
	var card1_button: Button = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card1/InteractionLayer/CardButton")
	_check(card0_button.anchor_right == 1.0 and card0_button.anchor_bottom == 1.0,
		"select: general card is fully clickable")
	_check(card1_button.anchor_right == 1.0 and card1_button.anchor_bottom == 1.0,
		"select: admiral card is fully clickable")
	var confirm_dialog: ConfirmationDialog = main.get_node("CanvasLayer/SelectScreen/CharacterConfirmDialog")
	card0_button.emit_signal("pressed")
	_check(confirm_dialog.visible, "select: card click opens confirmation")
	_check_eq(confirm_dialog.dialog_text, "このキャラクターを選択しますか？", "select: confirmation message")
	confirm_dialog.emit_signal("confirmed")
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
	var game_background: TextureRect = main.get_node("GameScreen/Playfield/CharaImage")
	_check(game_background.texture != null, "game: character background loaded")
	_check(String(game_background.texture.resource_path).ends_with("/general/game_background.png"),
		"game: selected character background is used")
	_check(absf(game_background.position.x + game_background.size.x * 0.5 - 640.0) < 0.1,
		"game: character background is horizontally centered")
	_check(absf(game_background.position.y) < 0.1 and absf(game_background.size.y - 720.0) < 0.1,
		"game: character background fills the screen height")

	var brush_finger: Node2D = main.get_node("GameScreen/Playfield/BrushFinger")
	var brush_fude: Node2D = main.get_node("GameScreen/Playfield/BrushFude")
	var brush_rotary: Node2D = main.get_node("GameScreen/Playfield/BrushRotary")
	_check(brush_finger.visible, "Lv1: finger brush available")
	_check(not brush_fude.visible, "Lv1: fude brush locked")
	_check(not brush_rotary.visible, "Lv1: rotating brush locked")
	_check(bool(brush_rotary.is_rotating), "rotating brush: scene marks it as rotating")

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
	_check(String(card0_portrait.texture.resource_path).ends_with("/general/portrait_after_opening.png"),
		"select: general portrait changes after opening")

	main._characters[1]["level"] = 5
	main._characters[1]["finish_total"] = 14
	main._characters[1]["pain_fail_total"] = 3
	main._characters[1]["opening_seen"] = true
	main._refresh_character_card(1)
	var admiral_reset: Button = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card1/InteractionLayer/DebugResetButton")
	_check_eq(admiral_reset.visible, OS.is_debug_build(), "debug reset: visibility follows debug build")
	if OS.is_debug_build():
		admiral_reset.emit_signal("pressed")
		_check_eq(int(main._characters[1]["level"]), 1, "debug reset: level")
		_check_eq(int(main._characters[1]["finish_total"]), 0, "debug reset: finish total")
		_check_eq(int(main._characters[1]["pain_fail_total"]), 0, "debug reset: pain failures")
		_check(not bool(main._characters[1]["opening_seen"]), "debug reset: opening state")
		_check(String(card1_portrait.texture.resource_path).ends_with("/admiral/portrait.png"),
			"debug reset: portrait returns to initial state")
	else:
		_check(admiral_reset.disabled, "debug reset: disabled outside debug builds")

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
