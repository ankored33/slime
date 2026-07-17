extends SceneTree

## Headless flow tests for the screen state machine in main.gd.
## Run: godot --headless --path godot -s res://tests/run_flow_tests.gd

var _failures := 0
var _passes := 0
var _done := false
var _completed := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run_tests()
	# スクリプトエラーで _run_tests が途中中断すると quit が呼ばれず exit 0 で
	# 成功扱いになってしまうため、完走フラグで検出して確実に落とす。
	if not _completed:
		printerr("FAIL: flow tests aborted before completion (script error above)")
		quit(1)
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
	var card0_epithet: Label = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/Margin/VBox/PortraitArea/InfoOverlay/Margin/VBox/EpithetLabel")
	_check_eq(card0_name.text, String(main._characters[0]["name"]),
		"select: real name before opening")
	_check_eq(card0_epithet.text, String(main._characters[0]["epithet"]),
		"select: epithet shown before opening")
	var card0_portrait: TextureRect = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/Margin/VBox/PortraitArea/Portrait")
	var card1_portrait: TextureRect = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card1/Margin/VBox/PortraitArea/Portrait")
	_check(card0_portrait.texture != null, "select: general portrait loaded")
	_check(card1_portrait.texture != null, "select: admiral portrait loaded")
	_check(String(card0_portrait.texture.resource_path).ends_with("/general/portrait.png"),
		"select: general uses initial portrait before opening")
	var profile_body: RichTextLabel = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/Margin/VBox/PortraitArea/InfoOverlay/Margin/VBox/ProfileBody")
	_check(profile_body.text.begins_with(String(main._characters[0]["profile"])),
		"select: profile shows pre-opening text")
	var instruction: Label = main.get_node("CanvasLayer/SelectScreen/InstructionOverlay/Label")
	_check_eq(instruction.text, "キャラクターを選択してください。", "select: instruction is overlaid")
	var card0_button: Button = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/InteractionLayer/CardButton")
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

	var brush_finger: Node2D = main.get_node("GameScreen/Playfield/BrushFinger")
	var brush_fude: Node2D = main.get_node("GameScreen/Playfield/BrushFude")
	var brush_rotary: Node2D = main.get_node("GameScreen/Playfield/BrushRotary")
	_check(not brush_finger.visible and not brush_rotary.visible,
		"toolbox: brushes start stowed")
	var finger_button: Button = game._brushes.get_tool_button("finger")
	var rotary_button: Button = game._brushes.get_tool_button("rotary")
	_check(finger_button != null and finger_button.visible, "Lv1: finger tool button available")
	_check(rotary_button != null and rotary_button.visible,
		"Lv1: rotating brush tool button temporarily available")
	_check(bool(brush_rotary.is_rotating), "rotating brush: scene marks it as rotating")
	var brush_name_label: Label = main.get_node("GameScreen/Hud/BrushNameLabel")
	_check_eq(brush_name_label.text, "指", "brush HUD: finger is the default display")

	# ブラシ画像フック: 素材の有無とプレースホルダ表示が対応していること。
	var finger_has_texture := ResourceLoader.exists("res://assets/brushes/finger.png", "Texture2D")
	_check(brush_finger._body.visible == not finger_has_texture,
		"brush: placeholder shown exactly when no texture asset exists")
	var brush_texture := ImageTexture.create_from_image(
		Image.create(128, 128, false, Image.FORMAT_RGBA8))
	brush_fude._apply_texture(brush_texture)
	_check(not brush_fude._body.visible, "brush: placeholder hidden when texture applied")

	# ツールボックス: ボタンで出し入れし、押した道具は保持状態で出現する。
	game._brushes.toggle_from_toolbox("rotary")
	_check(brush_rotary.visible and game._brushes.held_brush == brush_rotary,
		"toolbox: button summons the brush in held state")
	_check(brush_rotary.is_active, "rotating brush: keeps spinning while held")
	brush_rotary.position = Vector2(900.0, 400.0)
	game._brushes._set_held_brush(null)
	_check(brush_rotary.is_active, "rotating brush: keeps spinning when placed on the field")
	game._brushes.toggle_from_toolbox("rotary")
	_check(game._brushes.held_brush == brush_rotary, "toolbox: button picks up a placed brush")
	game._brushes.toggle_from_toolbox("rotary")
	_check(not brush_rotary.visible and not brush_rotary.is_active,
		"toolbox: pressing the button while held stows the brush")
	game._brushes.toggle_from_toolbox("rotary")
	brush_rotary.position = Vector2(1100.0, 300.0)
	game._brushes._set_held_brush(null)
	_check(not brush_rotary.visible, "toolbox: releasing over the box stows the brush")
	game.reset_day()

	# ろうそく固有アクション: 本体では磨けず、保持中の右クリックで滴を作る。
	var brush_candle: Brush = main.get_node("GameScreen/Playfield/BrushCandle")
	game._brushes.toggle_from_toolbox("candle")
	_check(brush_candle.visible and game._brushes.held_brush == brush_candle,
		"candle: temporarily unlocked at Lv1 and summoned held")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = Vector2(640.0, 360.0)
	var candle_action: Dictionary = game._brushes.handle_input(right_click)
	_check(candle_action.has("wax_origin"), "candle: right click requests a wax drop")
	var left_slime: SlimeTarget = main.get_node("GameScreen/Playfield/LeftSlime")
	game._spawn_wax_drop(left_slime.position - Vector2(0.0, left_slime.get_hit_radius()))
	game._update_wax_drops(0.05)
	_check(float(game._slime_state["left"]["polish"]) > 0.0,
		"candle: wax impact adds polish stimulus")
	_check(float(game._slime_state["left"]["pain"]) > 0.0,
		"candle: wax impact adds pain stimulus")
	_check_eq(game._wax_drops.size(), 0, "candle: wax drop is consumed on impact")
	game.reset_day()

	# 歯の固有アクション: 接触中の右クリックだけが一回分の痛みを与える。
	var brush_teeth: Brush = main.get_node("GameScreen/Playfield/BrushTeeth")
	game._brushes.toggle_from_toolbox("teeth")
	var teeth_action: Dictionary = game._brushes.handle_input(right_click)
	_check(teeth_action.has("bite_requested"), "teeth: right click requests a bite")
	game._apply_teeth_bite()
	_check_eq(float(game._slime_state["left"]["pain"]), 0.0,
		"teeth: bite does no damage away from a target")
	brush_teeth.position = left_slime.position + Vector2(
		left_slime.get_hit_radius() + brush_teeth.hit_radius, 0.0)
	game._apply_teeth_bite()
	_check(float(game._slime_state["left"]["pain"]) > 0.0,
		"teeth: bite damages a target while touching")
	_check_eq(float(game._slime_state["left"]["polish"]), 0.0,
		"teeth: bite has no polish effect")
	game.reset_day()

	# 押し込み変位: 接触中は押された方向へ少し動き、離すとバネで元の位置へ戻る。
	var slime_home: Vector2 = left_slime.position
	game._brushes.toggle_from_toolbox("finger")
	brush_finger.position = left_slime.position - Vector2(left_slime.radius, 0.0)
	for i in range(30):
		game._update_slime_squish(1.0 / 60.0)
	_check(left_slime.position.x > slime_home.x + 1.0,
		"push: slime is displaced away from a pressing brush")
	_check(left_slime.position.distance_to(slime_home) <= left_slime.MAX_PUSH_DISTANCE + 0.001,
		"push: displacement stays within the max range")
	brush_finger.position = slime_home + Vector2(500.0, 0.0)
	for i in range(120):
		game._update_slime_squish(1.0 / 60.0)
	_check(left_slime.position.distance_to(slime_home) < 1.0,
		"push: slime springs back home after release")
	game.reset_day()
	_check_eq(left_slime.position, slime_home, "push: reset restores the home position")

	# 指の固有アクション: 接触中に右クリックで挟んで固定し、可動範囲まで引っ張れる。
	var playfield: Control = main.get_node("GameScreen/Playfield")
	game._brushes.toggle_from_toolbox("finger")
	brush_finger.position = left_slime.position \
		- Vector2(left_slime.get_hit_radius() + brush_finger.hit_radius, 0.0)
	var pinch_action: Dictionary = game._brushes.handle_input(right_click)
	_check(pinch_action.has("pinch_requested"), "finger: right click requests a pinch")
	game._start_pinch()
	_check(game._pinch_slime == left_slime, "finger: pinch grabs the touching target")
	var grab_distance: float = brush_finger.position.distance_to(left_slime.position)
	var pull_mouse: Vector2 = playfield.get_global_transform() \
		* (brush_finger.position + Vector2(-200.0, 0.0))
	for i in range(60):
		game._update_pinch(pull_mouse, 1.0 / 60.0)
	_check(left_slime.position.x < slime_home.x - 10.0,
		"finger: pulling drags the target along")
	_check(left_slime.position.distance_to(slime_home) <= left_slime.MAX_PULL_DISTANCE + 0.001,
		"finger: pull stops at the max range")
	_check(absf(brush_finger.position.distance_to(left_slime.position) - grab_distance) < 0.5,
		"finger: pinched finger stays attached to the target")
	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	right_release.position = Vector2(640.0, 360.0)
	var release_action: Dictionary = game._brushes.handle_input(right_release)
	_check(release_action.has("pinch_released"), "finger: releasing right click lets go")
	game._end_pinch()
	brush_finger.position = slime_home + Vector2(500.0, 0.0)
	for i in range(120):
		game._update_slime_squish(1.0 / 60.0)
	_check(left_slime.position.distance_to(slime_home) < 1.0,
		"finger: target springs back home after the pinch ends")
	game.reset_day()

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
	_check(profile_body.text.begins_with(String(main._characters[0]["profile_after_opening"])),
		"select: profile switches after opening")
	_check_eq(card0_name.text, String(main._characters[0]["name_after_opening"]),
		"select: prisoner number replaces name after opening")
	_check_eq(card0_epithet.text, String(main._characters[0]["epithet_after_opening"]),
		"select: epithet becomes prisoner class after opening")

	main._characters[1]["level"] = 5
	main._characters[1]["finish_total"] = 14
	main._characters[1]["pain_fail_total"] = 3
	main._characters[1]["opening_seen"] = true
	main._refresh_character_card(1)
	var admiral_reset: Button = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card1/InteractionLayer/DebugResetButton")
	# headless テストは常にデバッグビルドで走る。リリース時の非表示はここでは検証できない。
	_check(admiral_reset.visible, "debug reset: visible in debug builds")
	_check_eq(card1_name.text, String(main._characters[1]["name_after_opening"]),
		"select: admiral card shows prisoner number when opening seen")
	admiral_reset.emit_signal("pressed")
	_check_eq(card1_name.text, String(main._characters[1]["name"]), "debug reset: real name restored")
	_check_eq(int(main._characters[1]["level"]), 1, "debug reset: level")
	_check_eq(int(main._characters[1]["finish_total"]), 0, "debug reset: finish total")
	_check_eq(int(main._characters[1]["pain_fail_total"]), 0, "debug reset: pain failures")
	_check(not bool(main._characters[1]["opening_seen"]), "debug reset: opening state")
	_check(String(card1_portrait.texture.resource_path).ends_with("/admiral/portrait.png"),
		"debug reset: portrait returns to initial state")

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

	_completed = true
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
