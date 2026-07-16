extends Control

const GameAudio = preload("res://scripts/game_audio.gd")

const SAVE_PATH := "user://slime_save_v2.json"

# キャラ定義。名前・オープニングは仮素材で、本素材が来たら差し替える。
# left / right は磨きターゲット2点の配置。
# expressions は表情id → 画像パス。空のままなら既定パス
# res://assets/chara/<id>/<表情id>.png を探す（無ければ表情名ラベルで代替表示）。
# 表情id一覧: idle_a〜idle_d（ブラシ無し）, touch_a〜touch_d（ブラシ当て）,
# climax（絶頂）, despair（絶望）, exhausted（憔悴）。詳細は expression_rules.gd。
var _characters: Array[Dictionary] = [
	{
		"id": "general",
		"name": "アリスティア",
		"epithet": "《眩耀たる漆黒》",
		"portrait": "res://assets/chara/general/portrait.png",
		"portrait_after_opening": "res://assets/chara/general/portrait_after_opening.png",
		"game_background": "res://assets/chara/general/game_background.png",
		"expressions": {},
		"profile": "虜囚番号Ｎ１０５６４　帝国の一般虜囚。\n性別：女　年齢：21　捕縛日：帝国暦2025年8月\n収監場所：帝国矯罰院\n\n膂力　S　　技巧　SS　　魔力　S\n策略　B　　戦略　A\n\nネブラレア王国最強の将軍。その剣は帝国にとって敗北を運ぶ魔剣であり、彼女自身が帝国を穿つ最強の矛であった。",
		"color": Color(1.0, 0.71, 0.78, 0.92),
		# 磨きターゲット = 立ち絵に重ねる乳首部分の小画像＋当たり判定。
		# 座標は 800x800 素材の画面換算: screen_x = 280 + src_x*0.9, screen_y = src_y*0.9
		# （640x720 枠・cover 表示・左右40pxクロップ前提。素材を差し替えたら要再計測）
		"left": {
			"position": Vector2(377.0, 592.0),
			"radius": 40.0,
			"image": ""
		},
		"right": {
			"position": Vector2(748.0, 416.0),
			"radius": 40.0,
			"image": ""
		},
		"level": 1,
		"finish_total": 0,
		"pain_fail_total": 0,
		"opening_seen": false,
		"opening_pages": [
			{
				"style": "split",
				"portrait": "portrait",
				"text": "ネブラレア王国最強の将軍、金色の髪を靡かせる《眩耀たる漆黒》アリスティア。\n彼女は我らが帝国にとって悪夢そのものだった。その剣技はもはや人智を超越しており、一振りで百の兵を薙ぎ払い、魔法を込めた一閃は堅牢なる城壁すらも砕いた。赤い瞳は戦場のあらゆる動きを見抜き、いかなる英雄の攻撃をも紙一重で躱す。彼女の前に立つ者は、勇猛なる帝国兵であろうと歴戦の将であろうと等しく塵となった。彼女の剣は我々にとって敗北を運ぶ魔剣であり、彼女自身が帝国を穿つ最強の矛なのだと、幾度となく身をもって知らされた。"
			},
			{
				"style": "blackout",
				"text": "だが捕らえた。\n帝国の7つの軍団が\nついに降伏したのだ。"
			},
			{
				"style": "split",
				"portrait": "portrait_after_opening",
				"text": "彼女の手首に嵌められた枷から伸びる重々しい鎖は、頑丈な柱に繋がれている。拘束された両手は吊り上げられ、漆黒の鎧を剥ぎ取られた無防備な身体は、屈辱的な姿勢を強いられている。かつて魔剣を握り、数多の帝国兵を切り裂いたその指先は、今や固く握りしめられ、震えていた。その赤き瞳の輝きは失せ、ただ屈辱と怒りの炎が燻るのみだった。透き通る肌から真珠のような汗が流れ落ちる。最強の矛は今、完全にその力を奪われ、晒し者にされている。\n\n……今日から、彼女の「世話」はお前の役目だ。"
			}
		]
	},
	{
		"id": "admiral",
		"name": "チチカ・エルマ",
		"epithet": "《緋色の方程式》",
		"portrait": "res://assets/chara/admiral/portrait.png",
		"portrait_after_opening": "res://assets/chara/admiral/portrait_after_opening.png",
		"game_background": "res://assets/chara/admiral/game_background.png",
		"expressions": {},
		"profile": "虜囚番号Ｃ３９３１２　帝国の一般虜囚。\n性別：女　年齢：155　捕縛日：帝国暦2025年8月\n収監場所：帝国矯罰院\n\n膂力　C　　技巧　C　　魔力　B\n策略　S　　戦略　SSS\n\nザコチック条約機構軍を統べる総督。その軍略は完璧であり、帝国の敗北は彼女がペンを走らせたその瞬間に約束されていた。",
		"color": Color(0.47, 0.9, 0.78, 0.92),
		"left": {
			"position": Vector2(341.0, 455.0),
			"radius": 40.0,
			"image": ""
		},
		"right": {
			"position": Vector2(618.0, 360.0),
			"radius": 40.0,
			"image": ""
		},
		"level": 1,
		"finish_total": 0,
		"pain_fail_total": 0,
		"opening_seen": false,
		"opening_pages": [
			{
				"style": "split",
				"portrait": "portrait",
				"text": "ザコチック条約機構軍を統べる総督、飄々と軍幕を巡る《緋色の方程式》チチカ・エルマ。\n彼女は戦場を支配する絶対的な知性そのものだった。その風貌からは想像もつかない速度で千の策を脳裏に渦巻かせ、戦況を未来予知のごとく読み解く。我々の大軍はわずかな手勢に翻弄され、難攻不落と信じていた要塞は一夜にして陥落した。帝国全土から選りすぐられた最高の軍師たちでさえ、掌の上で踊らされた。その軍略は完璧であり、我が軍の敗北は彼女がペンを走らせたその瞬間に約束されていた。我々が受けた幾多の屈辱は、彼女という盤上の支配者によってもたらされた。"
			},
			{
				"style": "blackout",
				"text": "だが捕らえた。"
			},
			{
				"style": "split",
				"portrait": "portrait_after_opening",
				"text": "彼女の身体を拘束するのは、分厚い鉄枷だった。彼女が築き上げた不敗の歴史は、自身の敗北によって終わりを告げた。かつて机上に地図を広げ、無数の部隊を動かしたその小さな腕は、今はただ冷たく鋭い金属の感触に耐えている。軍服は引き裂かれ、白い肌には幾つもの痛々しい傷が見えた。かつて無尽蔵とも思える知性と希望とをたたえていた瞳にはもはや光はなく、ただ屈辱と絶望に歪んでいる。いかな神算鬼謀を宿す頭脳も、この無慈悲な状況を覆すことはできない。\n\n……鉄格子の向こうで、彼女はお前を睨みつけている。"
			}
		]
	}
]

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

func _ready() -> void:
	_return_button.pressed.connect(_on_return_pressed)
	_title_start_button.pressed.connect(_on_title_start_pressed)
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

func _show_title_screen() -> void:
	_hide_all_screens()
	_title_screen.visible = true
	GameAudio.play_bgm("title")

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
