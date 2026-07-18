extends SceneTree

## Headless flow tests for the screen state machine in main.gd.
## Run: godot --headless --path godot -s res://tests/run_flow_tests.gd

var _failures := 0
var _passes := 0
var _done := false
var _completed := false

# 画面遷移をまたいで共有するテストフィクスチャ。
var save_path := "user://slime_save_v2.json"
var had_save := false
var save_backup := ""
var main_scene: PackedScene
var main: Control
var title: Control
var opening: OpeningScreen
var options: OptionsScreen
var frame: Control
var select: SelectScreen
var result: Control
var game: Control

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
	_setup_and_test_opening()
	_test_game_controls_and_zoom()
	_test_brush_assets_and_toolbox()
	_test_candle()
	_test_brush_contact_actions()
	_test_slime_motion_and_finish()
	_test_selection_and_debug_tools()
	_test_pause_persistence_and_layers()
	_restore_save()

	_completed = true
	print("---")
	print("Passed: %d, Failed: %d" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)

func _setup_and_test_opening() -> void:
	had_save = FileAccess.file_exists(save_path)
	if had_save:
		save_backup = FileAccess.get_file_as_string(save_path)

	main_scene = load("res://scenes/main.tscn")
	main = main_scene.instantiate()
	root.add_child(main)

	title = main.get_node("CanvasLayer/TitleScreen")
	opening = main.get_node("CanvasLayer/OpeningScreen")
	options = main.get_node("CanvasLayer/OptionsScreen")
	frame = main.get_node("CanvasLayer/Frame")
	select = main.get_node("CanvasLayer/SelectScreen")
	result = main.get_node("CanvasLayer/Frame/Margin/VBox/ResultScreen")
	game = main.get_node("GameScreen")
	var next_button: Button = main.get_node(
		"CanvasLayer/OpeningScreen/SplitView/TextPanel/Margin/TextVBox/Actions/OpeningNextButton"
	)

	main._characters[0]["opening_seen"] = false
	main._characters[0]["level"] = 1
	main._characters[0]["finish_total"] = 0
	main._characters[1]["opening_seen"] = false

	_check(title.visible and not frame.visible and not game.visible, "boot: title screen only")
	main._on_title_options_pressed()
	_check(options.visible and title.visible, "title options -> overlay on top of title")
	options._on_back_pressed()
	_check(title.visible and not options.visible, "options back -> title screen")

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
	var card0_view_original: Button = main.get_node(
		"CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/InteractionLayer/ViewOriginalButton")
	_check(not card0_view_original.visible,
		"view original: hidden before the opening has been seen")
	var instruction: Label = main.get_node("CanvasLayer/SelectScreen/InstructionOverlay/Label")
	_check_eq(instruction.text, "キャラクターを選択してください。", "select: instruction is overlaid")
	var card0_button: Button = main.get_node("CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/InteractionLayer/CardButton")
	var confirm_dialog: ConfirmationDialog = main.get_node("CanvasLayer/SelectScreen/CharacterConfirmDialog")
	card0_button.emit_signal("pressed")
	_check(confirm_dialog.visible, "select: card click opens confirmation")
	_check_eq(confirm_dialog.dialog_text, "このキャラクターを選択しますか？", "select: confirmation message")
	confirm_dialog.emit_signal("confirmed")
	confirm_dialog.hide()
	_check(opening.visible and not select.visible, "first start -> opening screen")
	_check_eq(opening.page_index, 0, "opening starts at page 0")

	# 各ページは「。」/改行ごとに1文ずつフェード表示され、文を出し切ってから
	# advance() を押すと次のページに進む（opening_screen.gd）。
	var pages: Array = main._characters[0]["opening_pages"]
	for i in range(pages.size() - 1):
		while opening._revealed_count < opening._sentences.size():
			opening.advance()
		opening.advance()
	_check(opening.visible, "opening: still open on last page")
	_check_eq(String(next_button.text), "はじめる ▶", "opening: last page button label")

	while opening._revealed_count < opening._sentences.size():
		opening.advance()
	opening.advance()
	# 初回オープニングの直後も、2回目以降と同じ一言演出を挟んでから磨き画面へ進む。
	_check(opening.visible and not game.visible, "opening end -> day-intro beat before the game screen")
	while opening._revealed_count < opening._sentences.size():
		opening.advance()
	opening.advance()
	_check(game.visible and not opening.visible, "day-intro beat -> game screen")
	_check(bool(main._characters[0]["opening_seen"]), "opening marked as seen")
	var game_background: TextureRect = main.get_node("GameScreen/Playfield/ZoomRoot/CharaImage")
	_check(game_background.texture != null, "game: character background loaded")
	_check(String(game_background.texture.resource_path).ends_with("/general/game_background.png"),
		"game: selected character background is used")

func _test_game_controls_and_zoom() -> void:
	var brush_finger: Brush = main.get_node("GameScreen/Playfield/ZoomRoot/BrushFinger")
	var brush_tongue: Brush = main.get_node("GameScreen/Playfield/ZoomRoot/BrushTongue")
	var brush_fude: Node2D = main.get_node("GameScreen/Playfield/ZoomRoot/BrushFude")
	var brush_rotary: Node2D = main.get_node("GameScreen/Playfield/ZoomRoot/BrushRotary")
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
	var end_day_button: Button = main.get_node("GameScreen/Hud/EndDayButton")
	var end_day_dialog: ConfirmationDialog = main.get_node("GameScreen/EndDayConfirmDialog")
	end_day_button.emit_signal("pressed")
	_check(end_day_dialog.visible, "end day: button opens confirmation")
	_check_eq(end_day_dialog.dialog_text,
		"1日を終えますか？\n（本日のFINISHを確定します）",
		"end day: confirmation message")
	_check(game._menu_paused, "end day: confirmation pauses gameplay")
	end_day_dialog.emit_signal("canceled")
	_check(not end_day_dialog.visible and not game._menu_paused,
		"end day: cancel closes confirmation and resumes gameplay")

	# ホイールズーム: キャラ画像の上だけで効き、上回転で1段階2倍、下回転で等倍へ戻る。
	var zoom_root: Control = main.get_node("GameScreen/Playfield/ZoomRoot")
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	wheel_up.position = Vector2(160.0, 360.0)
	game._input(wheel_up)
	_check_eq(zoom_root.scale, Vector2.ONE, "zoom: wheel over the side panel does nothing")
	wheel_up.position = Vector2(500.0, 300.0)
	game._input(wheel_up)
	_check_eq(zoom_root.scale, Vector2.ONE * game.CHARA_ZOOM,
		"zoom: wheel up over the image zooms in")
	game._input(wheel_up)
	_check_eq(zoom_root.scale, Vector2.ONE * game.CHARA_ZOOM, "zoom: single step only")
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	wheel_down.position = Vector2(500.0, 300.0)
	game._input(wheel_down)
	_check_eq(zoom_root.scale, Vector2.ONE, "zoom: wheel down returns to normal")
	game.reset_day()

func _test_brush_assets_and_toolbox() -> void:
	var brush_finger: Brush = main.get_node("GameScreen/Playfield/ZoomRoot/BrushFinger")
	var brush_tongue: Brush = main.get_node("GameScreen/Playfield/ZoomRoot/BrushTongue")
	var brush_fude: Node2D = main.get_node("GameScreen/Playfield/ZoomRoot/BrushFude")
	var brush_rotary: Node2D = main.get_node("GameScreen/Playfield/ZoomRoot/BrushRotary")

	# ブラシ画像フック: 素材の有無とプレースホルダ表示が対応していること。
	var finger_has_texture := ResourceLoader.exists("res://assets/brushes/finger.png", "Texture2D")
	_check(brush_finger._body.visible == not finger_has_texture,
		"brush: placeholder shown exactly when no texture asset exists")
	_check(ResourceLoader.exists("res://assets/brushes/tongue.png", "Texture2D"),
		"brush: tongue texture asset is imported")
	_check(brush_tongue._base_texture != null and not brush_tongue._body.visible,
		"brush: tongue texture replaces its placeholder")
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

func _test_candle() -> void:
	var left_slime: SlimeTarget = main.get_node("GameScreen/Playfield/ZoomRoot/LeftSlime")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = Vector2(640.0, 360.0)

	# ろうそく固有アクション: 本体では磨けず、保持中の右クリックで滴を作る。
	var brush_candle: Brush = main.get_node("GameScreen/Playfield/ZoomRoot/BrushCandle")
	game._brushes.toggle_from_toolbox("candle")
	_check(brush_candle.visible and game._brushes.held_brush == brush_candle,
		"candle: temporarily unlocked at Lv1 and summoned held")
	var candle_action: Dictionary = game._brushes.handle_input(right_click)
	_check(candle_action.has("wax_origin"), "candle: right click requests a wax drop")
	game._tool_actions.spawn_wax_drop(
		left_slime.position - Vector2(0.0, left_slime.get_hit_radius()))
	game._tool_actions.update_wax_drops(0.05, game._slime_state, game._current_level())
	_check(float(game._slime_state["left"]["polish"]) > 0.0,
		"candle: wax impact adds polish stimulus")
	_check(float(game._slime_state["left"]["pain"]) > 0.0,
		"candle: wax impact adds pain stimulus")
	_check_eq(game._tool_actions.wax_drop_count, 0, "candle: wax drop is consumed on impact")
	var high_level_wax_state := {
		"left": {"polish": 0.0, "pain": 0.0},
		"right": {"polish": 0.0, "pain": 0.0}
	}
	game._tool_actions._apply_wax_impact(high_level_wax_state, "left", GameRules.MAX_LEVEL)
	var high_level_wax_polish := float(high_level_wax_state["left"]["polish"])
	_check(high_level_wax_polish > GameRules.GAUGE_MAX,
		"candle: high-level wax stimulus is not capped by the display gauge")
	var finish_count_before: int = int(game._day_finish_count)
	game._slime_state = high_level_wax_state
	game._check_finish()
	_check(game._day_finish_count - finish_count_before > 1,
		"candle: one high-level wax impact counts multiple finishes")
	_check(not game._fx.finish_active,
		"candle: a high-level multi-finish uses the non-blocking chain effect")
	game.reset_day()

func _test_brush_contact_actions() -> void:
	var brush_finger: Brush = main.get_node("GameScreen/Playfield/ZoomRoot/BrushFinger")
	var left_slime: SlimeTarget = main.get_node("GameScreen/Playfield/ZoomRoot/LeftSlime")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = Vector2(640.0, 360.0)

	# こすり系ブラシの向き: 接触前でも当たり判定付近なら先端側が中心を向く。
	game._brushes.toggle_from_toolbox("finger")
	brush_finger.rotation = 0.0
	brush_finger.position = left_slime.position - Vector2(
		left_slime.get_hit_radius() + brush_finger.get_contact_radius()
			+ game.BRUSH_FACING_RANGE_MARGIN * 0.5,
		0.0
	)
	game._update_brush_facing(1.0)
	_check_near(brush_finger.rotation, PI / 2.0,
		"brush facing: near target rotates local top toward target center")
	brush_finger.position = left_slime.position - Vector2(
		left_slime.get_hit_radius() + brush_finger.get_contact_radius()
			+ game.BRUSH_FACING_RANGE_MARGIN + 20.0,
		0.0
	)
	game._update_brush_facing(1.0)
	_check_near(brush_finger.rotation, 0.0,
		"brush facing: away from target returns upright")
	game.reset_day()

	# 接触判定: 見た目の半径内でも縮小した接触半径の外なら効果は発生しない。
	game._brushes.toggle_from_toolbox("finger")
	brush_finger._rub_speed = 600.0
	brush_finger.position = left_slime.position + Vector2(
		left_slime.get_hit_radius() + brush_finger.get_contact_radius() + 1.0, 0.0)
	game._apply_brush_effects(brush_finger, 1.0)
	_check_eq(float(game._slime_state["left"]["polish"]), 0.0,
		"brush contact: visual overlap outside contact radius has no effect")
	brush_finger.position = left_slime.position + Vector2(
		left_slime.get_hit_radius() + brush_finger.get_contact_radius() - 1.0, 0.0)
	game._apply_brush_effects(brush_finger, 1.0)
	_check(float(game._slime_state["left"]["polish"]) > 0.0,
		"brush contact: inside contact radius applies effect")
	game.reset_day()

	# 歯の固有アクション: 接触中の右クリックだけが一回分の痛みを与える。
	var brush_teeth: Brush = main.get_node("GameScreen/Playfield/ZoomRoot/BrushTeeth")
	game._brushes.toggle_from_toolbox("teeth")
	var teeth_action: Dictionary = game._brushes.handle_input(right_click)
	_check(teeth_action.has("bite_requested"), "teeth: right click requests a bite")
	game._tool_actions.apply_teeth_bite(game._slime_state, game._current_level())
	_check_eq(float(game._slime_state["left"]["pain"]), 0.0,
		"teeth: bite does no damage away from a target")
	brush_teeth.position = left_slime.position + Vector2(
		left_slime.get_hit_radius() + brush_teeth.get_contact_radius(), 0.0)
	game._tool_actions.apply_teeth_bite(game._slime_state, game._current_level())
	_check(float(game._slime_state["left"]["pain"]) > 0.0,
		"teeth: bite damages a target while touching")
	_check_eq(float(game._slime_state["left"]["polish"]), 0.0,
		"teeth: bite has no polish effect")
	game.reset_day()

func _test_slime_motion_and_finish() -> void:
	var left_slime: SlimeTarget = main.get_node("GameScreen/Playfield/ZoomRoot/LeftSlime")
	var brush_finger: Brush = main.get_node("GameScreen/Playfield/ZoomRoot/BrushFinger")
	var end_day_button: Button = main.get_node("GameScreen/Hud/EndDayButton")
	var end_day_dialog: ConfirmationDialog = main.get_node("GameScreen/EndDayConfirmDialog")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = Vector2(640.0, 360.0)

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
	# 差分加算の丸め誤差ぶんだけ許容する（見た目に影響しないサブピクセル）。
	_check(left_slime.position.distance_to(slime_home) < 0.01,
		"push: reset restores the home position")

	# 指の固有アクション: 接触中に右クリックで挟んで固定し、可動範囲まで引っ張れる。
	var playfield: Control = main.get_node("GameScreen/Playfield/ZoomRoot")
	game._brushes.toggle_from_toolbox("finger")
	brush_finger.position = left_slime.position \
		- Vector2(left_slime.get_hit_radius() + brush_finger.get_contact_radius(), 0.0)
	var pinch_action: Dictionary = game._brushes.handle_input(right_click)
	_check(pinch_action.has("pinch_requested"), "finger: right click requests a pinch")
	game._tool_actions.start_pinch()
	_check(game._tool_actions.pinch_slime == left_slime,
		"finger: pinch grabs the touching target")
	var grab_distance: float = brush_finger.position.distance_to(left_slime.position)
	var pull_mouse: Vector2 = playfield.get_global_transform() \
		* (brush_finger.position + Vector2(-200.0, 0.0))
	for i in range(60):
		game._tool_actions.update_pinch(pull_mouse, 1.0 / 60.0)
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
	game._tool_actions.end_pinch()
	brush_finger.position = slime_home + Vector2(500.0, 0.0)
	for i in range(120):
		game._update_slime_squish(1.0 / 60.0)
	_check(left_slime.position.distance_to(slime_home) < 1.0,
		"finger: target springs back home after the pinch ends")
	game.reset_day()

	# 演出ヘルパー: FINISH後は憔悴へ遷移し、失敗演出もリセット可能。
	game._start_finish_fx()
	_check(game._fx.finish_active, "fx: finish effect starts")
	_check(game._finish_label.visible, "fx: finish label is shown")
	for i in range(int(ceil(game.finish_fx_duration * 60.0)) + 1):
		game._fx.update(1.0 / 60.0)
	_check(not game._fx.finish_active and game._fx.exhausted,
		"fx: finish effect transitions to exhausted")
	_check(not game._finish_label.visible, "fx: finish label hides after effect")
	game.reset_day()
	game._start_fail_fx()
	_check(game._fx.fail_active, "fx: fail effect starts")
	game.reset_day()
	_check(not game._fx.fail_active, "fx: reset clears fail effect")

	game._day_finish_count = 4
	end_day_button.emit_signal("pressed")
	_check(game.visible and not result.visible,
		"end day: button does not finish before confirmation")
	end_day_dialog.emit_signal("confirmed")
	_check(result.visible and frame.visible and not game.visible, "day end -> result screen")

func _test_selection_and_debug_tools() -> void:
	var card0_name: Label = main.get_node(
		"CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/Margin/VBox/PortraitArea/InfoOverlay/Margin/VBox/NameLabel")
	var card1_name: Label = main.get_node(
		"CanvasLayer/SelectScreen/Margin/VBox/Cards/Card1/Margin/VBox/PortraitArea/InfoOverlay/Margin/VBox/NameLabel")
	var card0_epithet: Label = main.get_node(
		"CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/Margin/VBox/PortraitArea/InfoOverlay/Margin/VBox/EpithetLabel")
	var card0_portrait: TextureRect = main.get_node(
		"CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/Margin/VBox/PortraitArea/Portrait")
	var card1_portrait: TextureRect = main.get_node(
		"CanvasLayer/SelectScreen/Margin/VBox/Cards/Card1/Margin/VBox/PortraitArea/Portrait")
	var profile_body: RichTextLabel = main.get_node(
		"CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/Margin/VBox/PortraitArea/InfoOverlay/Margin/VBox/ProfileBody")

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

	# 「元の経歴を見る」ボタン: 押している間だけ本名・二つ名・立ち絵・プロフィール文が
	# すべて初回のものに戻る。
	var view_original: Button = main.get_node(
		"CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/InteractionLayer/ViewOriginalButton")
	_check(view_original.visible, "view original: visible once opening is seen")
	view_original.emit_signal("button_down")
	_check(String(card0_portrait.texture.resource_path).ends_with("/general/portrait.png"),
		"view original: portrait reverts to the initial art while held")
	_check(profile_body.text.begins_with(String(main._characters[0]["profile"])),
		"view original: profile text reverts to the initial one while held")
	_check_eq(card0_name.text, String(main._characters[0]["name"]),
		"view original: real name shown while held")
	_check_eq(card0_epithet.text, String(main._characters[0]["epithet"]),
		"view original: real epithet shown while held")
	view_original.emit_signal("button_up")
	_check(String(card0_portrait.texture.resource_path).ends_with("/general/portrait_after_opening.png"),
		"view original: portrait returns to the post-opening art on release")
	_check(profile_body.text.begins_with(String(main._characters[0]["profile_after_opening"])),
		"view original: profile text returns to the post-opening one on release")
	_check_eq(card0_name.text, String(main._characters[0]["name_after_opening"]),
		"view original: name returns to the prisoner record on release")
	_check_eq(card0_epithet.text, String(main._characters[0]["epithet_after_opening"]),
		"view original: epithet returns to the prisoner class on release")

	main._characters[1]["level"] = 5
	main._characters[1]["finish_total"] = 14
	main._characters[1]["pain_fail_total"] = 3
	main._characters[1]["opening_seen"] = true
	select.refresh_character_card(1)
	var admiral_level: Button = main.get_node(
		"CanvasLayer/SelectScreen/Margin/VBox/Cards/Card1/InteractionLayer/DebugLevelButton")
	var level_dialog: ConfirmationDialog = main.get_node(
		"CanvasLayer/SelectScreen/LevelEditDialog")
	_check(admiral_level.visible, "debug level: visible in debug builds")
	admiral_level.emit_signal("pressed")
	_check(level_dialog.visible, "debug level: button opens editor")
	select._level_spin_box.value = 42
	level_dialog.emit_signal("confirmed")
	_check_eq(int(main._characters[1]["level"]), 42, "debug level: applies entered level")
	_check_eq(int(main._characters[1]["finish_total"]), GameRules.required_finish_total(42),
		"debug level: aligns finish total so level persists")
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

	main._on_character_selected(0)
	# 2回目以降の選択では、磨き画面の前に一言だけ暗転演出を挟む（main.gd 参照）。
	_check(opening.visible and not game.visible, "second start shows the day-intro beat, not the full opening")
	while opening._revealed_count < opening._sentences.size():
		opening.advance()
	opening.advance()
	_check(game.visible and not opening.visible, "second start skips the full opening")

func _test_pause_persistence_and_layers() -> void:
	# ESCメニュー: タイトルでは出さず、ゲーム中はオーバーレイでゲージ進行を止める。
	var pause_menu: PauseMenu = main.get_node("CanvasLayer/PauseMenu")
	var esc_event := InputEventKey.new()
	esc_event.keycode = KEY_ESCAPE
	esc_event.pressed = true
	main._unhandled_input(esc_event)
	_check(pause_menu.visible and game.visible, "esc: pause menu overlays the game screen")
	_check(bool(game._menu_paused), "esc: pause menu freezes gauge progress")

	pause_menu._on_options_pressed()
	_check(options.visible and pause_menu.visible and game.visible,
		"pause menu: options overlays on top of the pause menu")
	options._on_back_pressed()
	_check(not options.visible and pause_menu.visible, "pause menu: options back returns to pause menu")

	main._unhandled_input(esc_event)
	_check(not pause_menu.visible, "esc: second press closes the pause menu")
	_check(not bool(game._menu_paused), "esc: closing the pause menu resumes gauge progress")

	main._unhandled_input(esc_event)
	pause_menu._on_title_pressed()
	_check(pause_menu._confirm_dialog.visible, "pause menu: title button asks for confirmation")
	pause_menu._confirm_dialog.emit_signal("canceled")
	_check(game.visible, "pause menu: canceling the title confirmation stays in game")

	pause_menu._on_title_pressed()
	pause_menu._confirm_dialog.emit_signal("confirmed")
	_check(title.visible and not game.visible, "pause menu: confirmed title return leaves the game")
	_check(not bool(game._is_running), "pause menu: returning to title abandons the running day")
	_check(not pause_menu.visible, "pause menu: hidden after returning to title")

	# 「ゲーム終了」は main の実配線を経由すると get_tree().quit() を呼んでしまうため、
	# main に繋がっていない別インスタンスでシグナル配線だけを検証する。
	var pause_menu_probe: PauseMenu = load("res://scenes/pause_menu.tscn").instantiate()
	root.add_child(pause_menu_probe)
	# GDScript のラムダはローカル変数を値でキャプチャするため、書き換え検知には配列を使う。
	var quit_signaled := [false]
	pause_menu_probe.quit_requested.connect(func() -> void: quit_signaled[0] = true)
	pause_menu_probe._on_quit_pressed()
	pause_menu_probe._confirm_dialog.emit_signal("confirmed")
	_check(quit_signaled[0], "pause menu: quit button emits quit_requested after confirmation")
	pause_menu_probe.queue_free()

	main._on_character_selected(0)
	while opening._revealed_count < opening._sentences.size():
		opening.advance()
	opening.advance()
	_check(game.visible and bool(game._is_running) and not bool(game._menu_paused),
		"select after title return: a fresh day starts cleanly")

	# Opening flag survives a reload through the save file.
	var reloaded: Control = main_scene.instantiate()
	root.add_child(reloaded)
	_check(bool(reloaded._characters[0]["opening_seen"]), "opening_seen persisted to save")

	# 胸レイヤー: breast 指定のあるキャラは立ち絵の上に胸スプライトが載り、
	# 乳首画像は等倍表示＋画像サイズ由来の当たり判定になる。無いキャラは載らない。
	var chara_image: Control = game.get_node("Playfield/ZoomRoot/CharaImage")
	var left_target: SlimeTarget = game.get_node("Playfield/ZoomRoot/LeftSlime")
	var live_breast_layers := func() -> Array:
		return chara_image.get_children().filter(
			func(c: Node) -> bool: return c is BreastLayer and not c.is_queued_for_deletion())
	game.setup_species(main._characters[1])
	var admiral_layers: Array = live_breast_layers.call()
	_check(admiral_layers.size() == 1, "breast layer: created for admiral left side")
	_check(left_target.image_native_size, "breast layer: admiral nipple uses native image size")
	_check(absf(left_target.radius - 32.5) < 0.6, "breast layer: hit radius derived from nipple image")
	game.setup_species(main._characters[0])
	var general_layers: Array = live_breast_layers.call()
	_check(general_layers.is_empty(), "breast layer: absent for characters without breast assets")
	_check(not left_target.image_native_size, "breast layer: general target back to circle sizing")

func _restore_save() -> void:
	if had_save:
		var file := FileAccess.open(save_path, FileAccess.WRITE)
		file.store_string(save_backup)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures += 1
		printerr("FAIL: %s" % label)

func _check_eq(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (expected %s, got %s)" % [label, expected, actual])

func _check_near(actual: float, expected: float, label: String) -> void:
	_check(absf(actual - expected) < 0.0001, "%s (expected %f, got %f)" % [label, expected, actual])
