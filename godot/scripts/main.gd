extends Control

const GameAudio = preload("res://scripts/game_audio.gd")
const ProgressStoreScript = preload("res://scripts/progress_store.gd")
const ResultScreenScript = preload("res://scripts/result_screen.gd")

# キャラ定義データは characters.gd（CharacterDefs）に分離。テキスト推敲はそちらで。
# ここでは初期値として読み込み、セーブデータ（level 等）で上書きしていく。
var _characters: Array[Dictionary] = CharacterDefs.create()
var _progress_store := ProgressStoreScript.new()
var _result_screen_ctrl := ResultScreenScript.new()

const SCREEN_FADE_DURATION := 0.25
## 一日を終える時だけの幕閉じ演出（日次導入のカーテン開き=opening_screen.gd の
## CURTAIN_OPEN_DURATION の逆再生がベースだが、こちらは少し速める）。
const DAY_END_CURTAIN_DURATION := 1.0
## 幕が閉じ切ったあと、覆われた状態からリザルト画面へフェードインする長さ。
const DAY_END_RESULT_FADE_DURATION := 0.4

var _selected_index := 0
var _last_result: Dictionary = {}
var _fade_tween: Tween
var _day_end_curtain_tween: Tween
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
	_result_screen_ctrl.setup(_result_screen, _date_label, _result_body, _result_chara_image, _return_button)
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
	if event is InputEventMouseButton and event.pressed and _result_screen_ctrl.is_typing():
		_result_screen_ctrl.complete_typing()
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
	_result_screen_ctrl.render(_characters[_selected_index], _last_result)
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
## クリック待ちのあと矯正確認ダイアログを挟んで、宣告してから磨き画面へ進む。
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
			"confirm_text": "%sを矯正しますか？" % prisoner_number
		},
		{
			"style": "blackout",
			"text": "%s。\nこれより貴様の矯正を開始する。" % prisoner_number,
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

func _save_progress() -> void:
	_progress_store.save(_characters)
