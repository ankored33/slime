extends Control

const GameAudio = preload("res://scripts/game_audio.gd")
const ProgressStoreScript = preload("res://scripts/progress_store.gd")

# キャラ定義データは characters.gd（CharacterDefs）に分離。テキスト推敲はそちらで。
# ここでは初期値として読み込み、セーブデータ（level 等）で上書きしていく。
var _characters: Array[Dictionary] = CharacterDefs.create()
var _progress_store := ProgressStoreScript.new()

const SCREEN_FADE_DURATION := 0.25
## 一日を終える時だけの幕閉じ演出（日次導入のカーテン開き=opening_screen.gd の
## CURTAIN_OPEN_DURATION の逆再生がベースだが、こちらは少し速める）。
const DAY_END_CURTAIN_DURATION := 1.0
## 幕が閉じ切ったあと、覆われた状態からリザルト画面へフェードインする長さ。
const DAY_END_RESULT_FADE_DURATION := 0.4
## リザルト本文のタイプライター演出の速度（1秒あたりの文字数）。
const RESULT_TYPE_CHARS_PER_SEC := 25.0
## タイプ演出後にキャラ画像をフェードインする長さ。
const RESULT_IMAGE_FADE_DURATION := 0.3
## リザルト画面に入ってからタイプ演出が始まるまでの間。
const RESULT_TYPE_START_DELAY := 1.0

var _selected_index := 0
var _last_result: Dictionary = {}
var _fade_tween: Tween
var _day_end_curtain_tween: Tween
var _result_type_tween: Tween
## _show_day_intro() 中かどうか。同じ OpeningScreen.finished を、初回オープニング
## 終了時（_on_opening_finished 本来の処理）と区別するためのフラグ。
var _showing_day_intro := false

@onready var _frame: Control = $CanvasLayer/Frame
@onready var _date_label: Label = $CanvasLayer/Frame/LeftPage/DateLabel
@onready var _select_screen: SelectScreen = $CanvasLayer/SelectScreen
@onready var _game_screen: Control = $GameScreen
@onready var _result_screen: Control = $CanvasLayer/Frame/LeftPage/ResultScreen
@onready var _result_body: RichTextLabel = $CanvasLayer/Frame/LeftPage/ResultScreen/ResultBody
@onready var _result_chara_image: TextureRect = $CanvasLayer/Frame/ResultCharaImage
@onready var _return_button: Button = $CanvasLayer/Frame/LeftPage/ResultScreen/Actions/ReturnButton
@onready var _title_screen: Control = $CanvasLayer/TitleScreen
@onready var _title_start_button: Button = $CanvasLayer/TitleScreen/Center/VBox/TitleStartButton
@onready var _opening_screen: OpeningScreen = $CanvasLayer/OpeningScreen
@onready var _fade_rect: ColorRect = $CanvasLayer/FadeRect
@onready var _day_end_curtain: Control = $CanvasLayer/DayEndCurtain
@onready var _day_end_curtain_left: ColorRect = $CanvasLayer/DayEndCurtain/CurtainLeft
@onready var _day_end_curtain_right: ColorRect = $CanvasLayer/DayEndCurtain/CurtainRight
@onready var _title_options_button: Button = $CanvasLayer/TitleScreen/Center/VBox/TitleOptionsButton
@onready var _options_screen: OptionsScreen = $CanvasLayer/OptionsScreen
@onready var _pause_menu: PauseMenu = $CanvasLayer/PauseMenu
@onready var _tutorial_overlay: Control = $CanvasLayer/TutorialOverlay
@onready var _tutorial_body: Label = $CanvasLayer/TutorialOverlay/Center/VBox/Body
@onready var _tutorial_button: Button = $CanvasLayer/TutorialOverlay/Center/VBox/ButtonRow/AcknowledgeButton

func _ready() -> void:
	_return_button.pressed.connect(_on_return_pressed)
	_result_body.gui_input.connect(_on_result_body_gui_input)
	_tutorial_body.text = TutorialText.BODY
	_tutorial_button.pressed.connect(_on_tutorial_acknowledged)
	_title_start_button.pressed.connect(_on_title_start_pressed)
	_title_options_button.pressed.connect(_on_title_options_pressed)
	_options_screen.back_requested.connect(_on_options_back_requested)
	_pause_menu.options_requested.connect(_on_pause_options_requested)
	_pause_menu.title_requested.connect(_on_pause_title_confirmed)
	_pause_menu.quit_requested.connect(_on_pause_quit_confirmed)
	_opening_screen.finished.connect(_on_opening_finished)
	_opening_screen.selection_requested.connect(_on_opening_selection_requested)
	_game_screen.day_finished.connect(_on_day_finished)
	_select_screen.character_selected.connect(_on_character_selected)
	_select_screen.progress_changed.connect(_save_progress)
	_select_screen.setup(_characters)
	_progress_store.load_into(_characters)
	_show_title_screen()
	# 起動時はタイトルへフェードインで入る。
	if DisplayServer.get_name() != "headless":
		_fade_rect.visible = true
		_fade_rect.color.a = 1.0
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		_fade_tween = create_tween()
		_fade_tween.tween_property(_fade_rect, "color:a", 0.0, SCREEN_FADE_DURATION * 2)
		_fade_tween.tween_callback(_on_fade_finished)

## ESCメニュー: タイトル画面では出さない。オプションが開いていれば先にそれを閉じる。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _is_result_typing():
		_complete_result_typing()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _tutorial_overlay.visible:
		return
	if _options_screen.visible:
		_on_options_back_requested()
		get_viewport().set_input_as_handled()
		return
	if _title_screen.visible:
		return
	_toggle_pause_menu()
	get_viewport().set_input_as_handled()

func _toggle_pause_menu() -> void:
	if _pause_menu.visible:
		_close_pause_menu()
	else:
		_open_pause_menu()

func _open_pause_menu() -> void:
	_pause_menu.open()
	_game_screen.pause_for_menu()

func _close_pause_menu() -> void:
	_pause_menu.close()
	_game_screen.resume_from_menu()

func _on_pause_title_confirmed() -> void:
	_pause_menu.close()
	_game_screen.abandon_day()
	_transition(_show_title_screen)

func _on_pause_quit_confirmed() -> void:
	get_tree().quit()

## 暗転フェードを挟んで画面を切り替える。switcher は _show_*_screen 系の Callable。
## ヘッドレス（テスト）実行時は即時切替。フェード中の再要求は無視する。
func _transition(switcher: Callable) -> void:
	if DisplayServer.get_name() == "headless":
		switcher.call()
		return
	if _fade_tween != null and _fade_tween.is_running():
		return
	_fade_rect.visible = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_rect, "color:a", 1.0, SCREEN_FADE_DURATION)
	_fade_tween.tween_callback(switcher)
	_fade_tween.tween_property(_fade_rect, "color:a", 0.0, SCREEN_FADE_DURATION)
	_fade_tween.tween_callback(_on_fade_finished)

func _on_fade_finished() -> void:
	_fade_rect.visible = false
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

## 一日を終える時だけの画面切り替え。日次導入のカーテン開き（opening_screen.gd の
## _render_curtain）の逆再生: 左右から幕を閉じて画面を覆い隠し、覆われている間に
## switcher でリザルト画面へ切り替えてから幕をフェードアウトして見せる。
func _transition_with_curtain_close(switcher: Callable) -> void:
	if DisplayServer.get_name() == "headless":
		switcher.call()
		return
	if _day_end_curtain_tween != null and _day_end_curtain_tween.is_running():
		return
	var half_width := _day_end_curtain.size.x * 0.5
	_day_end_curtain.visible = true
	_day_end_curtain.modulate.a = 1.0
	_day_end_curtain_left.position.x = -half_width
	_day_end_curtain_right.position.x = _day_end_curtain.size.x
	_day_end_curtain_tween = create_tween()
	_day_end_curtain_tween.set_parallel(true)
	_day_end_curtain_tween.tween_property(
		_day_end_curtain_left, "position:x", 0.0, DAY_END_CURTAIN_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_day_end_curtain_tween.tween_property(
		_day_end_curtain_right, "position:x", half_width, DAY_END_CURTAIN_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_day_end_curtain_tween.set_parallel(false)
	_day_end_curtain_tween.tween_callback(switcher)
	_day_end_curtain_tween.tween_property(
		_day_end_curtain, "modulate:a", 0.0, DAY_END_RESULT_FADE_DURATION
	)
	_day_end_curtain_tween.tween_callback(_on_day_end_curtain_finished)

func _on_day_end_curtain_finished() -> void:
	_day_end_curtain.visible = false

func _hide_all_screens() -> void:
	_frame.visible = false
	_select_screen.visible = false
	_game_screen.visible = false
	_result_screen.visible = false
	_result_chara_image.visible = false
	_title_screen.visible = false
	_opening_screen.visible = false
	_options_screen.visible = false
	_pause_menu.visible = false
	_tutorial_overlay.visible = false

func _show_title_screen() -> void:
	_hide_all_screens()
	_title_screen.visible = true
	GameAudio.play_bgm("title")

## オプションはどの画面からもその上に被せるオーバーレイなので、他の画面は隠さない。
func _open_options_overlay() -> void:
	_options_screen.show_options()

func _on_title_options_pressed() -> void:
	_open_options_overlay()

func _on_options_back_requested() -> void:
	_options_screen.visible = false

func _on_pause_options_requested() -> void:
	_open_options_overlay()

func _show_select_screen() -> void:
	_hide_all_screens()
	_select_screen.show_characters()
	GameAudio.play_bgm("select")

func _show_opening_screen() -> void:
	_hide_all_screens()
	_opening_screen.start(_characters[_selected_index])

func _show_game_screen() -> void:
	# Hide the side frame entirely; the play screen has its own HUD.
	_hide_all_screens()
	_game_screen.visible = true
	# 磨き画面のBGMは3曲からランダム。
	GameAudio.play_bgm("game_%s" % (["a", "b", "c"] as Array[String]).pick_random())
	_maybe_show_tutorial()

## 初回だけ、磨き画面の上にチュートリアル訓示を被せる。閉じるまでゲームは停止。
func _maybe_show_tutorial() -> void:
	if _progress_store.tutorial_seen or DisplayServer.get_name() == "headless":
		return
	_tutorial_overlay.visible = true
	_game_screen.pause_for_menu()

func _on_tutorial_acknowledged() -> void:
	GameAudio.play_se("ui_click")
	_tutorial_overlay.visible = false
	_game_screen.resume_from_menu()
	_progress_store.tutorial_seen = true
	_save_progress()

func _show_result_screen() -> void:
	_hide_all_screens()
	_frame.visible = true
	_result_screen.visible = true
	_render_result()
	GameAudio.play_bgm("select")

func _on_title_start_pressed() -> void:
	_transition(_show_select_screen)

func _on_character_selected(index: int) -> void:
	_selected_index = index
	var chara: Dictionary = _characters[_selected_index]
	if not bool(chara["opening_seen"]):
		_transition(_show_opening_screen)
	else:
		_transition(_show_day_intro)

func _begin_day() -> void:
	var chara: Dictionary = _characters[_selected_index]
	_game_screen.setup_species(chara)
	_transition(_show_game_screen)

## 磨き画面に入る直前、毎回（初回の自己紹介オープニングの直後も含む）挟む
## 短い導入演出。黒い幕が中央から左右へ開いてリザルト用のキャラ画像を見せ、
## クリック待ちのあと矯導確認ダイアログを挟んで、宣告してから磨き画面へ進む。
func _show_day_intro() -> void:
	_hide_all_screens()
	_showing_day_intro = true
	var chara: Dictionary = _characters[_selected_index]
	var prisoner_number := str(chara["name_after_opening"])
	# 幕開きで見せる立ち絵は portrait_day_intro 優先、無いキャラは result で代用。
	var intro_portrait_key := "portrait_day_intro" \
		if str(chara.get("portrait_day_intro", "")) != "" else "result"
	_opening_screen.start_with_pages(chara, [
		{
			"style": "curtain",
			"portrait": intro_portrait_key,
			"text": "",
			"confirm_text": "%sを矯導しますか？" % prisoner_number
		},
		{
			"style": "blackout",
			"text": "%s。\nこれより貴様の矯導を開始する。" % prisoner_number,
			"auto_advance_delays": [1.0, 2.0]
		}
	])

func _on_opening_finished() -> void:
	if _showing_day_intro:
		_showing_day_intro = false
		_begin_day()
		return
	# 初回の自己紹介オープニングが終わった直後。既読フラグを立ててから、
	# この一言演出（_show_day_intro）を挟んでから磨き画面へ進む。
	var chara: Dictionary = _characters[_selected_index]
	chara["opening_seen"] = true
	_characters[_selected_index] = chara
	_save_progress()
	_show_day_intro()

func _on_opening_selection_requested() -> void:
	_showing_day_intro = false
	_transition(_show_select_screen)

func _on_return_pressed() -> void:
	_transition(_show_select_screen)

func _on_day_finished(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	var chara: Dictionary = _characters[_selected_index]
	chara["finish_total"] = int(chara["finish_total"]) + int(result.get("banked_finish_count", 0))
	if bool(result.get("failed_by_pain", false)):
		chara["pain_fail_total"] = int(chara["pain_fail_total"]) + 1
	_last_result["level_before"] = int(chara["level"])
	chara["level"] = GameRules.level_for_finish_total(int(chara["finish_total"]))
	_characters[_selected_index] = chara
	_save_progress()
	_transition_with_curtain_close(_show_result_screen)

func _render_result() -> void:
	var chara: Dictionary = _characters[_selected_index]
	_update_result_chara_image(str(chara["result"]))
	var today := Time.get_date_dict_from_system()
	_date_label.text = "帝国暦%d年%d月%d日" % [int(today["year"]), int(today["month"]), int(today["day"])]
	var level_after := int(chara["level"])
	var level_before := int(_last_result.get("level_before", level_after))
	var level_line := "レベル: %d / %d" % [level_after, GameRules.MAX_LEVEL]
	if level_after > level_before:
		GameAudio.play_se("levelup")
		level_line = "レベル: %d → [b][color=#ffd75e]%d[/color][/b] / %d　[color=#ffd75e]LEVEL UP! +%d[/color]" % [
			level_before, level_after, GameRules.MAX_LEVEL, level_after - level_before]
	var failed := bool(_last_result.get("failed_by_pain", false))
	var status_line := "痛みが限界に達した。今日の成果は半減となった。\n" if failed else ""
	var tool_lines := _format_finish_by_tool(_last_result.get("finish_count_by_tool", {}))
	_result_body.text = (
		"[b]%s[/b]\n"
		+ "%s\n"
		+ "%s\n"
		+ "本日の絶頂回数: %s\n"
		+ "%s"
		+ "累計絶頂回数: %s\n"
		+ "痛み失敗: %d"
	) % [
		str(_last_result.get("species_name", "？？？")),
		level_line,
		status_line,
		NumberFormat.group(int(_last_result.get("day_finish_count", 0))),
		tool_lines,
		NumberFormat.group(int(chara["finish_total"])),
		int(chara["pain_fail_total"])
	]
	_start_result_typing()

## リザルト画面の登場演出。日付→本文の順に1文字ずつタイプし、終わったら
## キャラ画像を短くフェードインして、最後に戻るボタンを出す。クリックで全表示に飛ばせる。
func _start_result_typing() -> void:
	if _result_type_tween:
		_result_type_tween.kill()
	_return_button.visible = false
	_result_chara_image.modulate.a = 0.0
	if DisplayServer.get_name() == "headless":
		_complete_result_typing()
		return
	_date_label.visible_characters = 0
	_result_body.visible_characters = 0
	var date_total := _date_label.get_total_character_count()
	var body_total := _result_body.get_total_character_count()
	_result_type_tween = create_tween()
	_result_type_tween.tween_interval(RESULT_TYPE_START_DELAY)
	_result_type_tween.tween_property(
		_date_label, "visible_characters", date_total, date_total / RESULT_TYPE_CHARS_PER_SEC)
	_result_type_tween.tween_property(
		_result_body, "visible_characters", body_total, body_total / RESULT_TYPE_CHARS_PER_SEC)
	_result_type_tween.tween_property(
		_result_chara_image, "modulate:a", 1.0, RESULT_IMAGE_FADE_DURATION)
	_result_type_tween.tween_callback(func() -> void: _return_button.visible = true)

func _is_result_typing() -> bool:
	return _result_screen.visible and _result_type_tween != null and _result_type_tween.is_running()

func _complete_result_typing() -> void:
	if _result_type_tween:
		_result_type_tween.kill()
	_date_label.visible_characters = -1
	_result_body.visible_characters = -1
	_result_chara_image.modulate.a = 1.0
	_return_button.visible = true

func _on_result_body_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _is_result_typing():
		_complete_result_typing()
		get_viewport().set_input_as_handled()

## { ツール表示名: FINISH数 } を件数の多い順に "- 指: 12\n" 形式へ整形する。空なら空文字。
func _format_finish_by_tool(by_tool: Dictionary) -> String:
	if by_tool.is_empty():
		return ""
	var tool_names := by_tool.keys()
	tool_names.sort_custom(func(a, b): return int(by_tool[a]) > int(by_tool[b]))
	var lines := "内訳:\n"
	for tool_name in tool_names:
		lines += "- %s: %s\n" % [tool_name, NumberFormat.group(int(by_tool[tool_name]))]
	return lines + "\n"

## キャラ定義の result 画像があればリザルト画面右に表示する。無ければ隠す。
func _update_result_chara_image(path: String) -> void:
	if ResourceLoader.exists(path):
		var texture := load(path)
		if texture is Texture2D:
			_result_chara_image.texture = texture
			_result_chara_image.visible = true
			return
	_result_chara_image.visible = false

func _save_progress() -> void:
	_progress_store.save(_characters)
