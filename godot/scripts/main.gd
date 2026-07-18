extends Control

const GameAudio = preload("res://scripts/game_audio.gd")
const ProgressStoreScript = preload("res://scripts/progress_store.gd")

# キャラ定義データは characters.gd（CharacterDefs）に分離。テキスト推敲はそちらで。
# ここでは初期値として読み込み、セーブデータ（level 等）で上書きしていく。
var _characters: Array[Dictionary] = CharacterDefs.create()
var _progress_store := ProgressStoreScript.new()

const SCREEN_FADE_DURATION := 0.25

var _selected_index := 0
var _last_result: Dictionary = {}
var _fade_tween: Tween
## _show_day_intro() 中かどうか。同じ OpeningScreen.finished を、初回オープニング
## 終了時（_on_opening_finished 本来の処理）と区別するためのフラグ。
var _showing_day_intro := false

@onready var _frame: Control = $CanvasLayer/Frame
@onready var _screen_title: Label = $CanvasLayer/Frame/Margin/VBox/Header/ScreenTitle
@onready var _screen_subtitle: Label = $CanvasLayer/Frame/Margin/VBox/Header/ScreenSubtitle
@onready var _select_screen: SelectScreen = $CanvasLayer/SelectScreen
@onready var _game_screen: Control = $GameScreen
@onready var _result_screen: Control = $CanvasLayer/Frame/Margin/VBox/ResultScreen
@onready var _result_body: RichTextLabel = $CanvasLayer/Frame/Margin/VBox/ResultScreen/ResultPanel/Margin/ResultBody
@onready var _result_chara_image: TextureRect = $CanvasLayer/ResultCharaImage
@onready var _return_button: Button = $CanvasLayer/Frame/Margin/VBox/ResultScreen/Actions/ReturnButton
@onready var _title_screen: Control = $CanvasLayer/TitleScreen
@onready var _title_start_button: Button = $CanvasLayer/TitleScreen/Center/VBox/TitleStartButton
@onready var _opening_screen: OpeningScreen = $CanvasLayer/OpeningScreen
@onready var _fade_rect: ColorRect = $CanvasLayer/FadeRect
@onready var _title_options_button: Button = $CanvasLayer/TitleScreen/Center/VBox/TitleOptionsButton
@onready var _options_screen: OptionsScreen = $CanvasLayer/OptionsScreen
@onready var _pause_menu: PauseMenu = $CanvasLayer/PauseMenu

func _ready() -> void:
	_return_button.pressed.connect(_on_return_pressed)
	_title_start_button.pressed.connect(_on_title_start_pressed)
	_title_options_button.pressed.connect(_on_title_options_pressed)
	_options_screen.back_requested.connect(_on_options_back_requested)
	_pause_menu.options_requested.connect(_on_pause_options_requested)
	_pause_menu.title_requested.connect(_on_pause_title_confirmed)
	_pause_menu.quit_requested.connect(_on_pause_quit_confirmed)
	_opening_screen.finished.connect(_on_opening_finished)
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
	if not event.is_action_pressed("ui_cancel"):
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
	GameAudio.play_se("ui_click")
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

func _show_title_screen() -> void:
	_hide_all_screens()
	_title_screen.visible = true
	GameAudio.play_bgm("title")

## オプションはどの画面からもその上に被せるオーバーレイなので、他の画面は隠さない。
func _open_options_overlay() -> void:
	_options_screen.show_options()

func _on_title_options_pressed() -> void:
	GameAudio.play_se("ui_click")
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

func _show_result_screen() -> void:
	_hide_all_screens()
	_screen_title.text = "リザルト"
	_screen_subtitle.text = "今日の成果を確認してキャラ選択へ戻ろう。"
	_frame.visible = true
	_result_screen.visible = true
	_render_result()
	GameAudio.play_bgm("select")

func _on_title_start_pressed() -> void:
	GameAudio.play_se("ui_click")
	_transition(_show_select_screen)

func _on_character_selected(index: int) -> void:
	_selected_index = index
	var chara: Dictionary = _characters[_selected_index]
	if not bool(chara.get("opening_seen", false)):
		_transition(_show_opening_screen)
	else:
		_transition(_show_day_intro)

func _begin_day() -> void:
	var chara: Dictionary = _characters[_selected_index]
	_game_screen.setup_species(chara)
	_transition(_show_game_screen)

## 磨き画面に入る直前、毎回（初回の自己紹介オープニングの直後も含む）挟む
## 短い導入演出。宣告のあと、黒い幕が中央から左右へ開いて
## リザルト用のキャラ画像を見せる。
func _show_day_intro() -> void:
	_hide_all_screens()
	_showing_day_intro = true
	var chara: Dictionary = _characters[_selected_index]
	var prisoner_number := str(chara.get("name_after_opening", ""))
	_opening_screen.start_with_pages(chara, [
		{
			"style": "blackout",
			"text": "%s。\n貴様の教導を開始する" % prisoner_number,
			"auto_advance_delay": 0.5
		},
		{
			"style": "curtain",
			"portrait": "result",
			"text": ""
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

func _on_return_pressed() -> void:
	GameAudio.play_se("ui_click")
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
	_transition(_show_result_screen)

func _render_result() -> void:
	var chara: Dictionary = _characters[_selected_index]
	_update_result_chara_image(str(chara.get("result", "")))
	var level_after := int(chara["level"])
	var level_before := int(_last_result.get("level_before", level_after))
	var level_line := "レベル: %d / %d" % [level_after, GameRules.MAX_LEVEL]
	if level_after > level_before:
		GameAudio.play_se("levelup")
		level_line = "レベル: %d → [b][color=#ffd75e]%d[/color][/b] / %d　[color=#ffd75e]LEVEL UP! +%d[/color]" % [
			level_before, level_after, GameRules.MAX_LEVEL, level_after - level_before]
	var failed := bool(_last_result.get("failed_by_pain", false))
	var status_text := "痛みが限界に達した。今日の成果は半減となった。" if failed else "任意終了。成果をすべて持ち帰った。"
	_result_body.text = (
		"[b]%s[/b]\n"
		+ "%s\n\n"
		+ "本日のFINISH: %s\n"
		+ "持ち帰りFINISH: %s\n"
		+ "%s\n"
		+ "累計FINISH: %s\n"
		+ "痛み失敗: %d\n\n"
		+ "成長で伸びるもの:\n"
		+ "- 感度（快感の上がりやすさ）\n"
		+ "- 痛みへの耐性"
	) % [
		str(_last_result.get("species_name", "？？？")),
		status_text,
		NumberFormat.group(int(_last_result.get("day_finish_count", 0))),
		NumberFormat.group(int(_last_result.get("banked_finish_count", 0))),
		level_line,
		NumberFormat.group(int(chara["finish_total"])),
		int(chara["pain_fail_total"])
	]

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
