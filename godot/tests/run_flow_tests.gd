extends SceneTree

## Headless flow tests for the screen state machine in main.gd.
##
## Scope（意図的に絞っている）: 主要な画面遷移ルート（起動→選択→OP→磨き→リザルト→保存）、
## 計算・境界値（押し込み/引っ張りの可動域、接触半径、レベル反映）、取り返しのつかない
## 状態変更（FINISH、日終了、タイトルへ戻って日を破棄）、セーブの永続化。
## UI文言の完全一致・素材パス・デバッグ専用UIの表示可否・ホバー演出の詳細は含めない
## （変更のたびに壊れる割に目視の方が早いため）。追加する時はこの基準に沿うこと。
##
## Run: godot --headless --path godot -s res://tests/run_flow_tests.gd

var _failures := 0
var _passes := 0
var _done := false
var _completed := false

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
	_setup()
	_test_boot_select_opening_to_game()
	_test_zoom_and_end_day_dialog()
	_test_toolbox_and_brush_contact()
	_test_candle_wax_finish_counting()
	_test_deep_kiss()
	_test_clip_clamp_and_fall()
	_test_slime_push_pull_and_finish_fx()
	_test_result_to_select_and_debug_level()
	_test_pause_title_return_and_save_persistence()
	_restore_save()

	_completed = true
	print("---")
	print("Passed: %d, Failed: %d" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)

func _setup() -> void:
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
	result = main.get_node("CanvasLayer/Frame/LeftPage/ResultScreen")
	game = main.get_node("GameScreen")

	main._characters[0]["opening_seen"] = false
	main._characters[0]["level"] = 1
	main._characters[0]["finish_total"] = 0
	main._characters[1]["opening_seen"] = false

## 現在表示中のページ群を最後まで送る（文をフェード出し切り→次へ、を繰り返し、
## 最終ページの次のadvance()でfinishedが飛ぶところで止める）。呼び出し側はこれを
## 「1画面ぶんの表示を最後まで送る」単位として、必要な回数だけ呼ぶ
## （例: 初回OPなら1回でOP終了、もう1回で一言演出も送り切る）。
func _drain_opening_pages() -> void:
	while true:
		while opening._revealed_count < opening._sentences.size():
			opening.advance()
		var was_last_page := opening.page_index + 1 >= opening._pages.size()
		opening.advance()
		if was_last_page:
			break

func _test_boot_select_opening_to_game() -> void:
	_check(title.visible and not frame.visible and not game.visible, "boot: title screen only")
	main._on_title_options_pressed()
	_check(options.visible and title.visible, "title options -> overlay on top of title")
	options._on_back_pressed()
	_check(title.visible and not options.visible, "options back -> title screen")

	main._on_title_start_pressed()
	_check(select.visible and not frame.visible and not title.visible, "title start -> select screen")

	var card0_button: Button = main.get_node(
		"CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/InteractionLayer/CardButton")
	card0_button.emit_signal("pressed")
	_check(opening.visible and not select.visible, "first start -> opening screen (no confirm dialog)")

	# 初回オープニング -> 一言演出(day-intro) -> 磨き画面、まで送る。
	_drain_opening_pages()
	_check(opening.visible and not game.visible, "opening end -> day-intro beat before the game screen")
	_drain_opening_pages()
	_check(game.visible and not opening.visible, "day-intro beat -> game screen")
	_check(bool(main._characters[0]["opening_seen"]), "opening marked as seen")
	var game_background: TextureRect = main.get_node("GameScreen/Playfield/ZoomRoot/CharaImage")
	_check(game_background.texture != null, "game: character background loaded")

func _test_zoom_and_end_day_dialog() -> void:
	var end_day_button: Button = main.get_node("GameScreen/Hud/EndDayButton")
	var end_day_dialog: ConfirmationDialog = main.get_node("GameScreen/EndDayConfirmDialog")
	end_day_button.emit_signal("pressed")
	_check(end_day_dialog.visible, "end day: button opens confirmation")
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

func _test_toolbox_and_brush_contact() -> void:
	# rotary/teeth/candle はレベル解禁制になったため、ここと candle テストで使う分だけ
	# 先に全ブラシ解禁しておく（UIの解禁ロジック自体は _test_result_to_select_and_debug_level
	# などとは別に、GameRules 側で単体テスト済み）。
	var max_unlock_level: int = int(GameRules.BRUSH_UNLOCK_LEVELS.values().max())
	game._brushes.apply_unlocks(max_unlock_level)

	var brush_finger: Brush = main.get_node("GameScreen/Playfield/ZoomRoot/BrushFinger")
	var brush_rotary: Node2D = main.get_node("GameScreen/Playfield/ZoomRoot/BrushRotary")
	var brush_teeth: Brush = main.get_node("GameScreen/Playfield/ZoomRoot/BrushTeeth")
	var left_slime: SlimeTarget = main.get_node("GameScreen/Playfield/ZoomRoot/LeftSlime")

	# ツールボックス: ボタンで出し入れでき、回転ブラシは保持中も設置後も回り続ける。
	game._brushes.toggle_from_toolbox("rotary")
	_check(brush_rotary.visible and game._brushes.held_brush == brush_rotary,
		"toolbox: button summons the brush in held state")
	_check(brush_rotary.is_active, "rotating brush: keeps spinning while held")
	game._brushes._set_held_brush(null)
	_check(brush_rotary.is_active, "rotating brush: keeps spinning when placed on the field")
	game._brushes.toggle_from_toolbox("rotary")
	_check(game._brushes.held_brush == brush_rotary, "toolbox: button picks up a placed brush")
	game._brushes.toggle_from_toolbox("rotary")
	_check(not brush_rotary.visible and not brush_rotary.is_active,
		"toolbox: pressing the button while held stows the brush")
	game.reset_day()

	# こすり系ブラシの向き: 当たり判定付近に入ったら先端側が中心を向き、離れると直立に戻る。
	game._brushes.toggle_from_toolbox("finger")
	brush_finger.position = left_slime.position - Vector2(
		left_slime.get_hit_radius() + brush_finger.get_contact_radius()
			+ game.BRUSH_FACING_RANGE_MARGIN * 0.5, 0.0)
	game._update_brush_facing(1.0)
	_check_near(brush_finger.rotation, PI / 2.0,
		"brush facing: near target rotates local top toward target center")
	brush_finger.position = left_slime.position - Vector2(
		left_slime.get_hit_radius() + brush_finger.get_contact_radius()
			+ game.BRUSH_FACING_RANGE_MARGIN + 20.0, 0.0)
	game._update_brush_facing(1.0)
	_check_near(brush_finger.rotation, 0.0, "brush facing: away from target returns upright")
	game.reset_day()

	# 接触判定の境界値: 見た目の半径内でも縮小した接触半径の外なら効果は発生しない。
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
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = Vector2(640.0, 360.0)
	game._brushes.toggle_from_toolbox("teeth")
	game._brushes.handle_input(right_click)
	game._tool_actions.apply_teeth_bite(game._slime_state, game._current_level())
	_check_eq(float(game._slime_state["left"]["pain"]), 0.0,
		"teeth: bite does no damage away from a target")
	brush_teeth.position = left_slime.position + Vector2(
		left_slime.get_hit_radius() + brush_teeth.get_contact_radius(), 0.0)
	game._tool_actions.apply_teeth_bite(game._slime_state, game._current_level())
	_check(float(game._slime_state["left"]["pain"]) > 0.0,
		"teeth: bite damages a target while touching")
	game.reset_day()

func _test_candle_wax_finish_counting() -> void:
	var left_slime: SlimeTarget = main.get_node("GameScreen/Playfield/ZoomRoot/LeftSlime")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = Vector2(640.0, 360.0)

	game._brushes.toggle_from_toolbox("candle")
	var candle_action: Dictionary = game._brushes.handle_input(right_click)
	_check(candle_action.has("wax_origin"), "candle: right click requests a wax drop")
	game._tool_actions.spawn_wax_drop(
		left_slime.position - Vector2(0.0, left_slime.get_hit_radius()))
	game._tool_actions.update_wax_drops(0.05, game._slime_state, game._current_level())
	_check(float(game._slime_state["left"]["polish"]) > 0.0, "candle: wax impact adds polish stimulus")
	_check(float(game._slime_state["left"]["pain"]) > 0.0, "candle: wax impact adds pain stimulus")

	# 回帰防止: 高感度帯の快感はゲージ表示上限で頭打ちにならず、1回のFINISH判定で
	# 複数回分まとめて計上される（保持率撤廃・感度の青天井加速まわりで一度壊れた箇所）。
	# 左右とも刺激しておく（片側だけではFINISH_MIN_SIDE_RATIOのゲートで弾かれるため）。
	var high_level_wax_state := {
		"left": {"polish": 0.0, "pain": 0.0}, "right": {"polish": 0.0, "pain": 0.0}
	}
	game._tool_actions._apply_wax_impact(high_level_wax_state, "left", GameRules.MAX_LEVEL)
	game._tool_actions._apply_wax_impact(high_level_wax_state, "right", GameRules.MAX_LEVEL)
	_check(float(high_level_wax_state["left"]["polish"]) > GameRules.GAUGE_MAX,
		"candle: high-level wax stimulus is not capped by the display gauge")
	var finish_count_before: int = int(game._day_finish_count)
	game._day_state.targets = high_level_wax_state
	game._slime_state = game._day_state.targets
	game._check_finish()
	_check(game._day_finish_count - finish_count_before > 1,
		"candle: one high-level wax impact counts multiple finishes")
	_check(not game._fx.finish_active,
		"candle: a high-level multi-finish uses the non-blocking chain effect")
	game.reset_day()

func _test_deep_kiss() -> void:
	var brush_tongue: Brush = main.get_node("GameScreen/Playfield/ZoomRoot/BrushTongue")
	var mouth_pos: Vector2 = game._mouth_position()
	var mouth_radius: float = game._mouth_radius()
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = Vector2(640.0, 360.0)

	# 舌の右クリックは口づけを要求する（handle_input の返す固有アクションの形）。
	game._brushes.toggle_from_toolbox("tongue")
	var tongue_action: Dictionary = game._brushes.handle_input(right_click)
	_check(tongue_action.has("kiss_requested"), "kiss: tongue's right click requests a kiss")

	# 口から離れた状態で始めようとしても口づけは始まらない。
	brush_tongue.position = mouth_pos + Vector2(500.0, 500.0)
	game._tool_actions.start_kiss(mouth_pos, mouth_radius)
	_check(not game._tool_actions.kiss_active, "kiss: away from the mouth does not start")

	# 口に重ねて始めると、押し続けている間は快感が増え痛みが減る。
	brush_tongue.position = mouth_pos
	game._tool_actions.start_kiss(mouth_pos, mouth_radius)
	_check(game._tool_actions.kiss_active, "kiss: touching the mouth starts it")
	game._slime_state["left"]["pain"] = 100.0
	game._slime_state["right"]["pain"] = 100.0
	var polish_before: float = float(game._slime_state["left"]["polish"])
	game._tool_actions.update_kiss(
		mouth_pos, mouth_radius, game._slime_state, game._current_level(), 1.0)
	_check(float(game._slime_state["left"]["polish"]) > polish_before,
		"kiss: holding it adds polish to the left target")
	_check(float(game._slime_state["right"]["pain"]) < 100.0,
		"kiss: holding it soothes pain on the right target")

	# 口から離れている間は効果が止まるが、口づけモード自体は維持される。
	brush_tongue.position = mouth_pos + Vector2(500.0, 500.0)
	var polish_away: float = float(game._slime_state["left"]["polish"])
	game._tool_actions.update_kiss(
		mouth_pos, mouth_radius, game._slime_state, game._current_level(), 1.0)
	_check(game._tool_actions.kiss_active, "kiss: moving away from the mouth keeps the mode on")
	_check(float(game._slime_state["left"]["polish"]) == polish_away,
		"kiss: no polish is added while away from the mouth")

	# 口に戻ると再び効き、もう一度右クリック（game._input 経由）で切り替え終了する。
	brush_tongue.position = mouth_pos
	game._tool_actions.update_kiss(
		mouth_pos, mouth_radius, game._slime_state, game._current_level(), 1.0)
	_check(float(game._slime_state["left"]["polish"]) > polish_away,
		"kiss: returning to the mouth resumes the effect")
	game._input(right_click)
	_check(not game._tool_actions.kiss_active, "kiss: a second right click toggles it off")

	# 舌を手放すと口づけモードも終わる。
	game._tool_actions.start_kiss(mouth_pos, mouth_radius)
	_check(game._tool_actions.kiss_active, "kiss: touching the mouth restarts it")
	game._brushes.toggle_from_toolbox("tongue")
	game._tool_actions.update_kiss(
		mouth_pos, mouth_radius, game._slime_state, game._current_level(), 1.0)
	_check(not game._tool_actions.kiss_active, "kiss: stowing the tongue ends the mode")
	game.reset_day()

func _test_clip_clamp_and_fall() -> void:
	var left_slime: SlimeTarget = main.get_node("GameScreen/Playfield/ZoomRoot/LeftSlime")
	var brush_clip: Brush = main.get_node("GameScreen/Playfield/ZoomRoot/BrushClip")
	var slime_home: Vector2 = left_slime.position
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = Vector2(640.0, 360.0)

	# 指と同じく、右クリックが開閉トグル。触れていなければ閉じない。
	game._brushes.toggle_from_toolbox("clip")
	brush_clip.position = slime_home + Vector2(500.0, 0.0)
	var away_action: Dictionary = game._brushes.handle_input(right_click)
	_check(away_action.has("pinch_requested"), "clip: right click requests the shared pinch toggle")
	game._tool_actions.toggle_pinch()
	_check(game._tool_actions.pinch_brush == null,
		"clip: right click away from a target does not close it")

	# 接触中の右クリックで閉じ、指と同じつまみ機構で固定される。
	brush_clip.position = left_slime.position \
		- Vector2(left_slime.get_hit_radius() + brush_clip.get_contact_radius(), 0.0)
	game._tool_actions.toggle_pinch()
	_check(brush_clip.is_pinching, "clip: closing switches its visual to the closed state")
	_check(game._tool_actions.pinch_brush == brush_clip, "clip: closing fixes it like the pinch tool")

	# 挟んでいる間は継続的に軽い痛みが蓄積する。
	game._slime_state["left"]["pain"] = 0.0
	game._tool_actions.apply_clip_effects(game._slime_state, game._current_level(), 1.0)
	_check(float(game._slime_state["left"]["pain"]) > 0.0,
		"clip: clamping adds continuous pain while closed")

	# もう一度右クリックすると手を離す。指と違ってその場でバネ復帰はせず、
	# 引っ張りながら垂れ下がって静止する（見た目も消えたりしない）。
	var pain_before_release: float = float(game._slime_state["left"]["pain"])
	game._tool_actions.toggle_pinch()
	_check(game._tool_actions.clip_falling, "clip: a second right click starts the hang-down state")
	for i in range(30):
		game._tool_actions.update_pinch(Vector2.ZERO, 1.0 / 60.0)
		game._tool_actions.apply_clip_effects(game._slime_state, game._current_level(), 1.0 / 60.0)
	_check(game._tool_actions.pinch_brush == brush_clip,
		"clip: it stays fixed in place after being let go (no auto-detach)")
	_check(brush_clip.visible and brush_clip.is_pinching,
		"clip: it stays visible and closed while hanging")
	_check(float(game._slime_state["left"]["pain"]) > pain_before_release,
		"clip: letting go adds a pain spike")
	_check(absf(left_slime.position.distance_to(slime_home) - left_slime.MAX_PULL_DISTANCE) < 4.0,
		"clip: the target settles at (and stays at) its max pull distance")

	# 垂れ下がっている間も継続的に痛みが蓄積し続け、可動範囲を超えて動くこともない。
	var pain_while_hanging: float = float(game._slime_state["left"]["pain"])
	for i in range(30):
		game._tool_actions.update_pinch(Vector2.ZERO, 1.0 / 60.0)
		game._tool_actions.apply_clip_effects(game._slime_state, game._current_level(), 1.0 / 60.0)
	_check(float(game._slime_state["left"]["pain"]) > pain_while_hanging,
		"clip: pain keeps accruing while it hangs, unheld")
	_check(absf(left_slime.position.distance_to(slime_home) - left_slime.MAX_PULL_DISTANCE) < 4.0,
		"clip: it keeps hanging at the max pull distance instead of springing back")
	game.reset_day()

func _test_slime_push_pull_and_finish_fx() -> void:
	var left_slime: SlimeTarget = main.get_node("GameScreen/Playfield/ZoomRoot/LeftSlime")
	var brush_finger: Brush = main.get_node("GameScreen/Playfield/ZoomRoot/BrushFinger")
	var end_day_button: Button = main.get_node("GameScreen/Hud/EndDayButton")
	var end_day_dialog: ConfirmationDialog = main.get_node("GameScreen/EndDayConfirmDialog")

	# 押し込み変位: 接触中は押された方向へ動き、離すとバネで元の位置へ戻る。可動範囲は超えない。
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

	# 指の固有アクション: 右クリックで挟んで引っ張れるが、可動範囲を超えては動かない。
	var playfield: Control = main.get_node("GameScreen/Playfield/ZoomRoot")
	game._brushes.toggle_from_toolbox("finger")
	brush_finger.position = left_slime.position \
		- Vector2(left_slime.get_hit_radius() + brush_finger.get_contact_radius(), 0.0)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = Vector2(640.0, 360.0)
	game._brushes.handle_input(right_click)
	game._tool_actions.start_pinch()
	var pull_mouse: Vector2 = playfield.get_global_transform() \
		* (brush_finger.position + Vector2(-200.0, 0.0))
	for i in range(60):
		game._tool_actions.update_pinch(pull_mouse, 1.0 / 60.0)
	_check(left_slime.position.x < slime_home.x - 10.0, "finger: pulling drags the target along")
	_check(left_slime.position.distance_to(slime_home) <= left_slime.MAX_PULL_DISTANCE + 0.001,
		"finger: pull stops at the max range")
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
	for i in range(int(ceil(game.finish_fx_duration * 60.0)) + 1):
		game._fx.update(1.0 / 60.0)
	_check(not game._fx.finish_active and game._fx.exhausted,
		"fx: finish effect transitions to exhausted")
	game.reset_day()
	game._start_fail_fx()
	_check(game._fx.fail_active, "fx: fail effect starts")
	game.reset_day()
	_check(not game._fx.fail_active, "fx: reset clears fail effect")

	# 日終了（取り返しのつかない状態変更）: 確認を経てリザルト画面へ。
	game._day_finish_count = 4
	end_day_button.emit_signal("pressed")
	_check(game.visible and not result.visible,
		"end day: button does not finish before confirmation")
	end_day_dialog.emit_signal("confirmed")
	_check(result.visible and frame.visible and not game.visible, "day end -> result screen")

func _test_result_to_select_and_debug_level() -> void:
	main._on_return_pressed()
	_check(select.visible and not result.visible, "result return -> select screen")
	var card0_name: Label = main.get_node(
		"CanvasLayer/SelectScreen/Margin/VBox/Cards/Card0/Margin/VBox/PortraitArea/InfoOverlay/Margin/VBox/NameLabel")
	_check(card0_name.text != String(main._characters[0]["name"]),
		"select: display name changes once the opening has been seen")

	# デバッグレベル編集: 入力値がそのままレベルに反映され、finish_totalもそのレベルを
	# 維持できる値に揃う（GameRules.required_finish_totalとの整合性）。
	main._characters[1]["opening_seen"] = true
	select.refresh_character_card(1)
	var admiral_level: Button = main.get_node(
		"CanvasLayer/SelectScreen/Margin/VBox/Cards/Card1/InteractionLayer/DebugLevelButton")
	var level_dialog: ConfirmationDialog = main.get_node("CanvasLayer/SelectScreen/LevelEditDialog")
	admiral_level.emit_signal("pressed")
	_check(level_dialog.visible, "debug level: button opens editor")
	select._level_spin_box.value = 42
	level_dialog.emit_signal("confirmed")
	_check_eq(int(main._characters[1]["level"]), 42, "debug level: applies entered level")
	_check_eq(int(main._characters[1]["finish_total"]), GameRules.required_finish_total(42),
		"debug level: aligns finish total so level persists")

	var admiral_reset: Button = main.get_node(
		"CanvasLayer/SelectScreen/Margin/VBox/Cards/Card1/InteractionLayer/DebugResetButton")
	admiral_reset.emit_signal("pressed")
	_check_eq(int(main._characters[1]["level"]), 1, "debug reset: level")
	_check_eq(int(main._characters[1]["finish_total"]), 0, "debug reset: finish total")
	_check(not bool(main._characters[1]["opening_seen"]), "debug reset: opening state")

	main._on_character_selected(0)
	_check(opening.visible and not game.visible,
		"second start shows the day-intro beat, not the full opening")
	_drain_opening_pages()
	_check(game.visible and not opening.visible, "second start skips the full opening")

func _test_pause_title_return_and_save_persistence() -> void:
	# ESCメニュー: ゲーム中はオーバーレイでゲージ進行を止め、もう一度押すと閉じて再開する。
	var pause_menu: PauseMenu = main.get_node("CanvasLayer/PauseMenu")
	var esc_event := InputEventKey.new()
	esc_event.keycode = KEY_ESCAPE
	esc_event.pressed = true
	main._unhandled_input(esc_event)
	_check(pause_menu.visible and game.visible, "esc: pause menu overlays the game screen")
	_check(bool(game._menu_paused), "esc: pause menu freezes gauge progress")
	main._unhandled_input(esc_event)
	_check(not pause_menu.visible and not bool(game._menu_paused),
		"esc: second press closes the pause menu and resumes gauge progress")

	# タイトルへ戻る（取り返しのつかない状態変更）: キャンセルなら継続、確定なら日を破棄する。
	main._unhandled_input(esc_event)
	pause_menu._on_title_pressed()
	pause_menu._confirm_dialog.emit_signal("canceled")
	_check(game.visible, "pause menu: canceling the title confirmation stays in game")
	pause_menu._on_title_pressed()
	pause_menu._confirm_dialog.emit_signal("confirmed")
	_check(title.visible and not game.visible, "pause menu: confirmed title return leaves the game")
	_check(not bool(game._is_running), "pause menu: returning to title abandons the running day")

	main._on_character_selected(0)
	_drain_opening_pages()
	_check(game.visible and bool(game._is_running) and not bool(game._menu_paused),
		"select after title return: a fresh day starts cleanly")

	# セーブの永続化: opening_seen がファイル経由で新しいインスタンスにも引き継がれる。
	var reloaded: Control = main_scene.instantiate()
	root.add_child(reloaded)
	_check(bool(reloaded._characters[0]["opening_seen"]), "opening_seen persisted to save")
	reloaded.queue_free()

	# 胸レイヤー: breast指定のあるキャラだけ立ち絵の上に生成される（データ駆動の分岐確認）。
	var chara_image: Control = game.get_node("Playfield/ZoomRoot/CharaImage")
	var live_breast_layers := func() -> Array:
		return chara_image.get_children().filter(
			func(c: Node) -> bool: return c is BreastLayer and not c.is_queued_for_deletion())
	game.setup_species(main._characters[1])
	_check(live_breast_layers.call().size() == 1, "breast layer: created for admiral left side")
	game.setup_species(main._characters[0])
	_check(live_breast_layers.call().size() == 2, "breast layer: created for general both sides")
	game.setup_species(main._characters[2])
	_check(live_breast_layers.call().is_empty(), "breast layer: absent for characters without breast assets")

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
