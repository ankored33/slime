extends Control

const GameAudio = preload("res://scripts/game_audio.gd")

const SAVE_PATH := "user://slime_save_v2.json"

# キャラ定義データは characters.gd（CharacterDefs）に分離。テキスト推敲はそちらで。
# ここでは初期値として読み込み、セーブデータ（level 等）で上書きしていく。
var _characters: Array[Dictionary] = CharacterDefs.create()

const SCREEN_FADE_DURATION := 0.25

var _selected_index := 0
var _last_result: Dictionary = {}
var _opening_page := 0
var _pending_character_index := -1
var _fade_tween: Tween

@onready var _frame: Control = $CanvasLayer/Frame
@onready var _screen_title: Label = $CanvasLayer/Frame/Margin/VBox/Header/ScreenTitle
@onready var _screen_subtitle: Label = $CanvasLayer/Frame/Margin/VBox/Header/ScreenSubtitle
@onready var _select_screen: Control = $CanvasLayer/SelectScreen
@onready var _character_confirm_dialog: ConfirmationDialog = $CanvasLayer/SelectScreen/CharacterConfirmDialog
@onready var _game_screen: Control = $GameScreen
@onready var _result_screen: Control = $CanvasLayer/Frame/Margin/VBox/ResultScreen
@onready var _result_body: RichTextLabel = $CanvasLayer/Frame/Margin/VBox/ResultScreen/ResultPanel/Margin/ResultBody
@onready var _return_button: Button = $CanvasLayer/Frame/Margin/VBox/ResultScreen/Actions/ReturnButton
@onready var _title_screen: Control = $CanvasLayer/TitleScreen
@onready var _title_start_button: Button = $CanvasLayer/TitleScreen/Center/VBox/TitleStartButton
@onready var _opening_screen: Control = $CanvasLayer/OpeningScreen
@onready var _opening_split: Control = $CanvasLayer/OpeningScreen/SplitView
@onready var _opening_portrait: TextureRect = $CanvasLayer/OpeningScreen/SplitView/PortraitRect
@onready var _opening_portrait_placeholder: Label = $CanvasLayer/OpeningScreen/SplitView/PortraitPlaceholder
@onready var _opening_text: RichTextLabel = $CanvasLayer/OpeningScreen/SplitView/TextPanel/Margin/TextVBox/OpeningText
@onready var _opening_page_label: Label = $CanvasLayer/OpeningScreen/SplitView/TextPanel/Margin/TextVBox/Actions/PageLabel
@onready var _opening_next_button: Button = $CanvasLayer/OpeningScreen/SplitView/TextPanel/Margin/TextVBox/Actions/OpeningNextButton
@onready var _opening_blackout: Control = $CanvasLayer/OpeningScreen/BlackoutView
@onready var _opening_blackout_label: Label = $CanvasLayer/OpeningScreen/BlackoutView/BlackoutLabel
@onready var _fade_rect: ColorRect = $CanvasLayer/FadeRect
@onready var _title_options_button: Button = $CanvasLayer/TitleScreen/Center/VBox/TitleOptionsButton
@onready var _options_screen: Control = $CanvasLayer/OptionsScreen
@onready var _options_back_button: Button = $CanvasLayer/OptionsScreen/Center/Panel/Margin/VBox/OptionsBackButton
@onready var _volume_sliders: Dictionary = {
	"bgm": $CanvasLayer/OptionsScreen/Center/Panel/Margin/VBox/BgmRow/BgmSlider,
	"se": $CanvasLayer/OptionsScreen/Center/Panel/Margin/VBox/SeRow/SeSlider,
	"voice": $CanvasLayer/OptionsScreen/Center/Panel/Margin/VBox/VoiceRow/VoiceSlider
}
@onready var _volume_value_labels: Dictionary = {
	"bgm": $CanvasLayer/OptionsScreen/Center/Panel/Margin/VBox/BgmRow/BgmValue,
	"se": $CanvasLayer/OptionsScreen/Center/Panel/Margin/VBox/SeRow/SeValue,
	"voice": $CanvasLayer/OptionsScreen/Center/Panel/Margin/VBox/VoiceRow/VoiceValue
}

func _ready() -> void:
	_return_button.pressed.connect(_on_return_pressed)
	_title_start_button.pressed.connect(_on_title_start_pressed)
	_title_options_button.pressed.connect(_on_title_options_pressed)
	_options_back_button.pressed.connect(_on_options_back_pressed)
	for category: String in _volume_sliders.keys():
		var slider: HSlider = _volume_sliders[category]
		slider.value_changed.connect(_on_volume_changed.bind(category))
	_opening_next_button.pressed.connect(_on_opening_next_pressed)
	# 画面のどこをクリックしてもページが進む（暗転ページはこれが唯一の進行手段）。
	_opening_screen.gui_input.connect(_on_opening_gui_input)
	_game_screen.day_finished.connect(_on_day_finished)
	_character_confirm_dialog.confirmed.connect(_on_character_confirmed)
	_character_confirm_dialog.canceled.connect(_on_character_selection_canceled)
	_character_confirm_dialog.get_ok_button().text = "選択"
	_character_confirm_dialog.get_cancel_button().text = "キャンセル"
	for index in range(_characters.size()):
		var card := _get_card(index)
		var button: Button = card.get_node("InteractionLayer/CardButton")
		button.pressed.connect(_on_character_card_pressed.bind(index))
		var reset_button: Button = card.get_node("InteractionLayer/DebugResetButton")
		reset_button.pressed.connect(_on_character_reset_pressed.bind(index))
	_load_progress()
	_show_title_screen()
	# 起動時はタイトルへフェードインで入る。
	if DisplayServer.get_name() != "headless":
		_fade_rect.visible = true
		_fade_rect.color.a = 1.0
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		_fade_tween = create_tween()
		_fade_tween.tween_property(_fade_rect, "color:a", 0.0, SCREEN_FADE_DURATION * 2)
		_fade_tween.tween_callback(_on_fade_finished)

func _get_card(index: int) -> Control:
	return _select_screen.get_node("Margin/VBox/Cards/Card%d" % index)

func _refresh_character_cards() -> void:
	for index in range(_characters.size()):
		_refresh_character_card(index)

func _refresh_character_card(index: int) -> void:
	var chara: Dictionary = _characters[index]
	var card := _get_card(index)
	var info: VBoxContainer = card.get_node("Margin/VBox/PortraitArea/InfoOverlay/Margin/VBox")
	var name_label: Label = info.get_node("NameLabel")
	var epithet_label: Label = info.get_node("EpithetLabel")
	var profile_body: RichTextLabel = info.get_node("ProfileBody")
	var portrait: TextureRect = card.get_node("Margin/VBox/PortraitArea/Portrait")
	var placeholder: Label = card.get_node("Margin/VBox/PortraitArea/PortraitPlaceholder")
	name_label.text = str(chara["name"])
	epithet_label.text = str(chara.get("epithet", ""))
	var opening_state := "済" if bool(chara.get("opening_seen", false)) else "未（開始時に再生）"
	profile_body.text = (
		"%s\n\n"
		+ "レベル: [b]%d[/b] / %d\n"
		+ "累計FINISH: %d\n"
		+ "痛み失敗: %d\n"
		+ "オープニング: %s"
	) % [
		str(chara.get("profile", "")),
		int(chara["level"]),
		GameRules.MAX_LEVEL,
		int(chara["finish_total"]),
		int(chara["pain_fail_total"]),
		opening_state
	]
	var portrait_path := str(chara.get(
		"portrait_after_opening" if bool(chara.get("opening_seen", false)) else "portrait",
		""
	))
	if portrait_path == "":
		portrait_path = str(chara.get("portrait", ""))
	var texture: Texture2D = null
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		texture = load(portrait_path)
	portrait.texture = texture
	placeholder.visible = texture == null
	var info_overlay := info.get_parent().get_parent() as PanelContainer
	call_deferred("_fit_profile_overlay", info_overlay)

func _fit_profile_overlay(info_overlay: PanelContainer) -> void:
	if not is_instance_valid(info_overlay):
		return
	info_overlay.offset_top = info_overlay.offset_bottom - info_overlay.get_combined_minimum_size().y

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
	_title_screen.visible = false
	_opening_screen.visible = false
	_options_screen.visible = false

func _show_title_screen() -> void:
	_hide_all_screens()
	_title_screen.visible = true
	GameAudio.play_bgm("title")

func _show_options_screen() -> void:
	_hide_all_screens()
	_options_screen.visible = true
	# 現在値をスライダーへ反映（set_value_no_signal で保存の連鎖を避ける）。
	for category: String in _volume_sliders.keys():
		var volume := GameAudio.get_volume(category)
		(_volume_sliders[category] as HSlider).set_value_no_signal(volume)
		_update_volume_value_label(category, volume)

func _on_title_options_pressed() -> void:
	GameAudio.play_se("ui_click")
	_transition(_show_options_screen)

func _on_options_back_pressed() -> void:
	GameAudio.play_se("ui_click")
	_transition(_show_title_screen)

func _on_volume_changed(value: float, category: String) -> void:
	GameAudio.set_volume(category, value)
	_update_volume_value_label(category, value)

func _update_volume_value_label(category: String, volume: float) -> void:
	(_volume_value_labels[category] as Label).text = "%d%%" % int(round(volume * 100.0))

func _show_select_screen() -> void:
	_hide_all_screens()
	_pending_character_index = -1
	_character_confirm_dialog.hide()
	_select_screen.visible = true
	_refresh_character_cards()
	GameAudio.play_bgm("select")

func _show_opening_screen() -> void:
	_hide_all_screens()
	_opening_screen.visible = true
	_render_opening_page()
	GameAudio.play_bgm("opening_%s" % str(_characters[_selected_index].get("id", "")))

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

func _on_character_card_pressed(index: int) -> void:
	if index < 0 or index >= _characters.size():
		return
	GameAudio.play_se("ui_click")
	_pending_character_index = index
	_character_confirm_dialog.popup_centered()

func _on_character_confirmed() -> void:
	if _pending_character_index < 0:
		return
	var index := _pending_character_index
	_pending_character_index = -1
	_on_character_start_pressed(index)

func _on_character_selection_canceled() -> void:
	_pending_character_index = -1

func _on_character_reset_pressed(index: int) -> void:
	if index < 0 or index >= _characters.size():
		return
	GameAudio.play_se("ui_click")
	var chara: Dictionary = _characters[index]
	chara["level"] = 1
	chara["finish_total"] = 0
	chara["pain_fail_total"] = 0
	chara["opening_seen"] = false
	_characters[index] = chara
	_save_progress()
	_refresh_character_card(index)

func _on_character_start_pressed(index: int) -> void:
	GameAudio.play_se("ui_click")
	_selected_index = index
	var chara: Dictionary = _characters[_selected_index]
	if not bool(chara.get("opening_seen", false)):
		_opening_page = 0
		_transition(_show_opening_screen)
	else:
		_begin_day()

func _begin_day() -> void:
	var chara: Dictionary = _characters[_selected_index]
	_game_screen.setup_species(chara)
	_transition(_show_game_screen)

func _on_opening_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_opening_next_pressed()

func _on_opening_next_pressed() -> void:
	GameAudio.play_se("ui_click")
	var chara: Dictionary = _characters[_selected_index]
	var pages: Array = chara.get("opening_pages", [])
	if _opening_page + 1 < pages.size():
		_opening_page += 1
		_render_opening_page()
		return
	chara["opening_seen"] = true
	_characters[_selected_index] = chara
	_save_progress()
	_begin_day()

func _render_opening_page() -> void:
	var chara: Dictionary = _characters[_selected_index]
	var pages: Array = chara.get("opening_pages", [])
	if pages.is_empty():
		_opening_split.visible = false
		_opening_blackout.visible = false
		return
	var page: Dictionary = pages[_opening_page]
	var is_blackout := str(page.get("style", "split")) == "blackout"
	_opening_split.visible = not is_blackout
	_opening_blackout.visible = is_blackout
	if is_blackout:
		_opening_blackout_label.text = str(page.get("text", ""))
		return
	_opening_text.text = str(page.get("text", ""))
	_opening_page_label.text = "%d / %d" % [_opening_page + 1, pages.size()]
	# 左半分にはキャラ選択と同じ立ち絵を出す。page["portrait"] はキャラ定義のキー名。
	var portrait_key := str(page.get("portrait", "portrait"))
	var image_path := str(chara.get(portrait_key, ""))
	var texture: Texture2D = null
	if image_path != "" and ResourceLoader.exists(image_path):
		texture = load(image_path)
	_opening_portrait.texture = texture
	_opening_portrait_placeholder.visible = texture == null
	var is_last := _opening_page + 1 >= pages.size()
	_opening_next_button.text = "はじめる ▶" if is_last else "次へ ▼"

func _on_return_pressed() -> void:
	GameAudio.play_se("ui_click")
	_transition(_show_select_screen)

func _on_day_finished(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	var chara: Dictionary = _characters[_selected_index]
	chara["finish_total"] = int(chara["finish_total"]) + int(result.get("banked_finish_count", 0))
	if bool(result.get("failed_by_pain", false)):
		chara["pain_fail_total"] = int(chara["pain_fail_total"]) + 1
	chara["level"] = GameRules.level_for_finish_total(int(chara["finish_total"]))
	_characters[_selected_index] = chara
	_save_progress()
	_transition(_show_result_screen)

func _render_result() -> void:
	var chara: Dictionary = _characters[_selected_index]
	var failed := bool(_last_result.get("failed_by_pain", false))
	var status_text := "痛みが限界に達した。今日の成果は半減となった。" if failed else "任意終了。成果をすべて持ち帰った。"
	_result_body.text = (
		"[b]%s[/b]\n"
		+ "%s\n\n"
		+ "本日のFINISH: %d\n"
		+ "持ち帰りFINISH: %d\n"
		+ "レベル: %d / %d\n"
		+ "累計FINISH: %d\n"
		+ "痛み失敗: %d\n\n"
		+ "成長で伸びるもの:\n"
		+ "- 感度（快感の上がりやすさ）\n"
		+ "- FINISHに必要な快感量が減る\n"
		+ "- 痛みへの耐性\n"
		+ "- FINISH後に残る快感量"
	) % [
		str(_last_result.get("species_name", "？？？")),
		status_text,
		int(_last_result.get("day_finish_count", 0)),
		int(_last_result.get("banked_finish_count", 0)),
		int(chara["level"]),
		GameRules.MAX_LEVEL,
		int(chara["finish_total"]),
		int(chara["pain_fail_total"])
	]

func _save_progress() -> void:
	var payload := {
		"version": 2,
		"characters": []
	}
	for chara: Dictionary in _characters:
		payload["characters"].append({
			"id": str(chara.get("id", "")),
			"level": int(chara.get("level", 1)),
			"finish_total": int(chara.get("finish_total", 0)),
			"pain_fail_total": int(chara.get("pain_fail_total", 0)),
			"opening_seen": bool(chara.get("opening_seen", false))
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
	var loaded: Array = parsed.get("characters", [])
	var by_id: Dictionary = {}
	for entry in loaded:
		if typeof(entry) == TYPE_DICTIONARY:
			by_id[str(entry.get("id", ""))] = entry
	for index in range(_characters.size()):
		var chara: Dictionary = _characters[index]
		var cid := str(chara.get("id", ""))
		if not by_id.has(cid):
			continue
		var saved: Dictionary = by_id[cid]
		chara["finish_total"] = max(0, int(saved.get("finish_total", 0)))
		chara["pain_fail_total"] = max(0, int(saved.get("pain_fail_total", 0)))
		chara["opening_seen"] = bool(saved.get("opening_seen", false))
		var saved_level := int(saved.get("level", 1))
		chara["level"] = GameRules.level_for_finish_total(int(chara["finish_total"]), saved_level)
		_characters[index] = chara
