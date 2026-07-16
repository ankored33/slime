extends Control

const SAVE_PATH := "user://slime_save_v2.json"

# キャラ定義。名前・オープニングは仮素材で、本素材が来たら差し替える。
# left / right は磨きターゲット2点の配置。
var _characters: Array[Dictionary] = [
	{
		"id": "general",
		"name": "女将軍（仮名）",
		"epithet": "無敵と呼ばれた女将軍",
		"portrait": "",
		"profile": "（プロフィール仮テキスト）\n所属・経歴・気性などをここに差し込む。",
		"color": Color(1.0, 0.71, 0.78, 0.92),
		"left": {
			"position": Vector2(552.5, 480.0),
			"radius": 110.0,
			"image": ""
		},
		"right": {
			"position": Vector2(753.5, 477.0),
			"radius": 110.0,
			"image": ""
		},
		"level": 1,
		"finish_total": 0,
		"pain_fail_total": 0,
		"opening_seen": false,
		"opening_pages": [
			{
				"image": "",
				"text": "（仮テキスト 1/3）\n戦場で無敵を誇った女将軍は、ついに捕らえられ、この牢に繋がれた。"
			},
			{
				"image": "",
				"text": "（仮テキスト 2/3）\nここに本編のオープニングテキストを差し込む。"
			},
			{
				"image": "",
				"text": "（仮テキスト 3/3）\n……今日から、彼女の「世話」はお前の役目だ。"
			}
		]
	},
	{
		"id": "admiral",
		"name": "エルフ提督（仮名）",
		"epithet": "無敗を誇った女エルフ提督",
		"portrait": "",
		"profile": "（プロフィール仮テキスト）\n所属・経歴・気性などをここに差し込む。",
		"color": Color(0.47, 0.9, 0.78, 0.92),
		"left": {
			"position": Vector2(560.0, 474.0),
			"radius": 98.0,
			"image": ""
		},
		"right": {
			"position": Vector2(746.0, 471.0),
			"radius": 98.0,
			"image": ""
		},
		"level": 1,
		"finish_total": 0,
		"pain_fail_total": 0,
		"opening_seen": false,
		"opening_pages": [
			{
				"image": "",
				"text": "（仮テキスト 1/3）\n海で無敗を誇った女エルフ提督も、陸に上げられればただの捕虜だった。"
			},
			{
				"image": "",
				"text": "（仮テキスト 2/3）\nここに本編のオープニングテキストを差し込む。"
			},
			{
				"image": "",
				"text": "（仮テキスト 3/3）\n……鉄格子の向こうで、彼女はお前を睨みつけている。"
			}
		]
	}
]

var _selected_index := 0
var _last_result: Dictionary = {}
var _opening_page := 0

@onready var _frame: Control = $CanvasLayer/Frame
@onready var _screen_title: Label = $CanvasLayer/Frame/Margin/VBox/Header/ScreenTitle
@onready var _screen_subtitle: Label = $CanvasLayer/Frame/Margin/VBox/Header/ScreenSubtitle
@onready var _select_screen: Control = $CanvasLayer/SelectScreen
@onready var _game_screen: Control = $GameScreen
@onready var _result_screen: Control = $CanvasLayer/Frame/Margin/VBox/ResultScreen
@onready var _result_body: RichTextLabel = $CanvasLayer/Frame/Margin/VBox/ResultScreen/ResultPanel/Margin/ResultBody
@onready var _return_button: Button = $CanvasLayer/Frame/Margin/VBox/ResultScreen/Actions/ReturnButton
@onready var _title_screen: Control = $CanvasLayer/TitleScreen
@onready var _title_start_button: Button = $CanvasLayer/TitleScreen/Center/VBox/TitleStartButton
@onready var _opening_screen: Control = $CanvasLayer/OpeningScreen
@onready var _opening_image: TextureRect = $CanvasLayer/OpeningScreen/Margin/VBox/ImageArea/OpeningImage
@onready var _opening_image_placeholder: Label = $CanvasLayer/OpeningScreen/Margin/VBox/ImageArea/ImagePlaceholder
@onready var _opening_text: RichTextLabel = $CanvasLayer/OpeningScreen/Margin/VBox/TextPanel/Margin/TextVBox/OpeningText
@onready var _opening_page_label: Label = $CanvasLayer/OpeningScreen/Margin/VBox/TextPanel/Margin/TextVBox/Actions/PageLabel
@onready var _opening_next_button: Button = $CanvasLayer/OpeningScreen/Margin/VBox/TextPanel/Margin/TextVBox/Actions/OpeningNextButton

func _ready() -> void:
	_return_button.pressed.connect(_on_return_pressed)
	_title_start_button.pressed.connect(_on_title_start_pressed)
	_opening_next_button.pressed.connect(_on_opening_next_pressed)
	_game_screen.day_finished.connect(_on_day_finished)
	for index in range(_characters.size()):
		var card := _get_card(index)
		var button: Button = card.get_node("Margin/VBox/StartButton")
		button.pressed.connect(_on_character_start_pressed.bind(index))
	_load_progress()
	_show_title_screen()

func _get_card(index: int) -> Control:
	return _select_screen.get_node("Margin/VBox/Cards/Card%d" % index)

func _refresh_character_cards() -> void:
	for index in range(_characters.size()):
		_refresh_character_card(index)

func _refresh_character_card(index: int) -> void:
	var chara: Dictionary = _characters[index]
	var card := _get_card(index)
	var name_label: Label = card.get_node("Margin/VBox/NameLabel")
	var epithet_label: Label = card.get_node("Margin/VBox/EpithetLabel")
	var profile_body: RichTextLabel = card.get_node("Margin/VBox/ProfileBody")
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
	var portrait_path := str(chara.get("portrait", ""))
	var texture: Texture2D = null
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		texture = load(portrait_path)
	portrait.texture = texture
	placeholder.visible = texture == null

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

func _show_select_screen() -> void:
	_hide_all_screens()
	_select_screen.visible = true
	_refresh_character_cards()

func _show_opening_screen() -> void:
	_hide_all_screens()
	_opening_screen.visible = true
	_render_opening_page()

func _show_game_screen() -> void:
	# Hide the side frame entirely; the play screen has its own HUD.
	_hide_all_screens()
	_game_screen.visible = true

func _show_result_screen() -> void:
	_hide_all_screens()
	_screen_title.text = "リザルト"
	_screen_subtitle.text = "今日の成果を確認してキャラ選択へ戻ろう。"
	_frame.visible = true
	_result_screen.visible = true
	_render_result()

func _on_title_start_pressed() -> void:
	_show_select_screen()

func _on_character_start_pressed(index: int) -> void:
	_selected_index = index
	var chara: Dictionary = _characters[_selected_index]
	if not bool(chara.get("opening_seen", false)):
		_opening_page = 0
		_show_opening_screen()
	else:
		_begin_day()

func _begin_day() -> void:
	var chara: Dictionary = _characters[_selected_index]
	_game_screen.setup_species(chara)
	_show_game_screen()

func _on_opening_next_pressed() -> void:
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
		_opening_text.text = ""
		_opening_page_label.text = "0 / 0"
		return
	var page: Dictionary = pages[_opening_page]
	_opening_text.text = str(page.get("text", ""))
	_opening_page_label.text = "%d / %d" % [_opening_page + 1, pages.size()]
	var image_path := str(page.get("image", ""))
	var texture: Texture2D = null
	if image_path != "" and ResourceLoader.exists(image_path):
		texture = load(image_path)
	_opening_image.texture = texture
	_opening_image_placeholder.visible = texture == null
	var is_last := _opening_page + 1 >= pages.size()
	_opening_next_button.text = "はじめる ▶" if is_last else "次へ ▼"

func _on_return_pressed() -> void:
	_show_select_screen()

func _on_day_finished(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	var chara: Dictionary = _characters[_selected_index]
	chara["finish_total"] = int(chara["finish_total"]) + int(result.get("banked_finish_count", 0))
	if bool(result.get("failed_by_pain", false)):
		chara["pain_fail_total"] = int(chara["pain_fail_total"]) + 1
	chara["level"] = GameRules.level_for_finish_total(int(chara["finish_total"]))
	_characters[_selected_index] = chara
	_save_progress()
	_show_result_screen()

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
		+ "- 快感の上がりやすさ\n"
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
