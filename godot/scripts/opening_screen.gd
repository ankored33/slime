class_name OpeningScreen
extends Control

const GameAudio = preload("res://scripts/game_audio.gd")

signal finished
signal selection_requested

## 文の区切り（。または既存の改行）ごとに1行としてフェードインさせる演出。
## クリック/advance()は「未表示の文を1つ出す」→ 出し切ったら「次のページへ」の順で進む。
const SENTENCE_FADE_DURATION := 0.35
const CURTAIN_OPEN_DURATION := 1.6
const SPLIT_FONT_SIZE := 22
const BLACKOUT_FONT_SIZE := 44

var page_index := 0
var _character: Dictionary = {}
var _pages: Array = []
var _sentences: Array[String] = []
var _revealed_count := 0
var _page_transitioning := false
var _curtain_tween: Tween
var _auto_advance_delay := 0.0
var _auto_advance_delays: Array = []
var _auto_advance_tween: Tween
## curtain ページで「元の経歴を見る」を離したとき戻す先（そのページの本来の portrait キー）。
var _curtain_portrait_key := "result"

@onready var _split: Control = $SplitView
@onready var _portrait: TextureRect = $SplitView/PortraitRect
@onready var _portrait_placeholder: Label = $SplitView/PortraitPlaceholder
@onready var _sentence_list: VBoxContainer = $SplitView/TextPanel/Margin/TextVBox/TextScroll/SentenceList
@onready var _page_label: Label = $SplitView/TextPanel/Margin/TextVBox/Actions/PageLabel
@onready var _next_button: Button = $SplitView/TextPanel/Margin/TextVBox/Actions/OpeningNextButton
@onready var _curtain: Control = $CurtainReveal
@onready var _curtain_image: TextureRect = $CurtainReveal/CharacterImage
@onready var _curtain_left: ColorRect = $CurtainReveal/CurtainLeft
@onready var _curtain_right: ColorRect = $CurtainReveal/CurtainRight
@onready var _curtain_click_hint: Label = $CurtainReveal/ClickHint
@onready var _selection_button: Button = $CurtainReveal/SelectionButton
@onready var _profile_card: PanelContainer = $CurtainReveal/ProfileCard
@onready var _profile_epithet: Label = $CurtainReveal/ProfileCard/Margin/VBox/EpithetLabel
@onready var _profile_name: Label = $CurtainReveal/ProfileCard/Margin/VBox/NameLabel
@onready var _profile_body: RichTextLabel = $CurtainReveal/ProfileCard/Margin/VBox/ProfileBody
@onready var _view_original_button: Button = $CurtainReveal/ViewOriginalButton
@onready var _blackout: Control = $BlackoutView
@onready var _blackout_sentence_list: VBoxContainer = $BlackoutView/BlackoutCenter/SentenceList
@onready var _reform_confirm_dialog: ConfirmationDialog = $ReformConfirmDialog

func _ready() -> void:
	_next_button.pressed.connect(advance)
	_selection_button.pressed.connect(_on_selection_pressed)
	# 「元の経歴を見る」: 選択画面のカードと同じく、押している間だけ本来の名前・
	# 二つ名・プロフィール文・立ち絵に戻す。
	_view_original_button.button_down.connect(_render_profile_card.bind(true))
	_view_original_button.button_up.connect(_render_profile_card.bind(false))
	_reform_confirm_dialog.confirmed.connect(_on_reform_confirmed)
	_reform_confirm_dialog.canceled.connect(_on_reform_canceled)
	_reform_confirm_dialog.get_ok_button().text = "開始"
	_reform_confirm_dialog.get_cancel_button().text = "キャンセル"
	# 暗転ページを含め、画面のどこをクリックしても進める。
	gui_input.connect(_on_gui_input)

## character.opening_pages を表示する、初回の自己紹介オープニング用の入口。
func start(character: Dictionary) -> void:
	_play(character, character["opening_pages"], true)

## 任意のページ列を挟み込みたいとき用の入口（例: 毎回の磨き画面前の一言）。
## opening_pages とは無関係なので、既読フラグ等には触れない。呼び出し側が
## finished シグナルを見て次の画面に進める。
func start_with_pages(character: Dictionary, pages: Array, play_music: bool = false) -> void:
	_play(character, pages, play_music)

func _play(character: Dictionary, pages: Array, play_music: bool) -> void:
	if _curtain_tween != null and _curtain_tween.is_running():
		_curtain_tween.kill()
	if _auto_advance_tween != null and _auto_advance_tween.is_running():
		_auto_advance_tween.kill()
	_character = character
	_pages = pages
	page_index = 0
	_page_transitioning = false
	_auto_advance_delay = 0.0
	_auto_advance_delays.clear()
	_curtain_click_hint.visible = false
	_selection_button.visible = false
	_profile_card.visible = false
	_view_original_button.visible = false
	visible = true
	_render_page()
	if play_music:
		GameAudio.play_bgm("opening_%s" % str(_character["id"]))

## 未表示の文が残っていればそれを1つフェードインさせる。出し切っていれば次のページへ、
## 最終ページなら演出を終える。curtain ページで confirm_text が指定されていれば、
## 出し切った後の最初のクリックは次へ進めず確認ダイアログを挟む。
func advance(automatic: bool = false) -> void:
	if _page_transitioning:
		return
	if _current_auto_advance_delay() > 0.0 and not automatic and DisplayServer.get_name() != "headless":
		return
	if _revealed_count < _sentences.size():
		_reveal_next_sentence()
		return
	var confirm_text := _current_confirm_text()
	if confirm_text != "" and DisplayServer.get_name() != "headless":
		_reform_confirm_dialog.dialog_text = confirm_text
		_reform_confirm_dialog.popup_centered()
		return
	_advance_to_next_page_or_finish()

func _advance_to_next_page_or_finish() -> void:
	if page_index + 1 < _pages.size():
		page_index += 1
		_render_page()
		return
	finished.emit()

func _current_confirm_text() -> String:
	if _pages.is_empty():
		return ""
	return str(_pages[page_index].get("confirm_text", ""))

func _on_reform_confirmed() -> void:
	GameAudio.play_se("ui_click")
	_advance_to_next_page_or_finish()

func _on_reform_canceled() -> void:
	pass

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _curtain.visible and not _curtain_image_contains(event.position):
			return
		advance()

func _get_cursor_shape(position: Vector2) -> Control.CursorShape:
	if _curtain.visible and _curtain_image_contains(position):
		return Control.CURSOR_POINTING_HAND
	return Control.CURSOR_ARROW

## curtain ページはアスペクト比維持で表示するため、キャラ画像の左右に余白ができる。
## その余白（左右パネル）をクリックしても反応しないよう、実際に描画されている
## 画像範囲だけを判定する。
func _curtain_image_contains(pos: Vector2) -> bool:
	var texture := _curtain_image.texture
	if texture == null:
		return false
	var control_size := _curtain_image.size
	var tex_size := texture.get_size()
	var scale := minf(control_size.x / tex_size.x, control_size.y / tex_size.y)
	var drawn_size := tex_size * scale
	var origin := (control_size - drawn_size) * 0.5
	return Rect2(origin, drawn_size).has_point(pos)

func _render_page() -> void:
	if _pages.is_empty():
		_split.visible = false
		_curtain.visible = false
		_blackout.visible = false
		return
	var page: Dictionary = _pages[page_index]
	var style := str(page.get("style", "split"))
	_auto_advance_delay = float(page.get("auto_advance_delay", 0.0))
	var delays_value: Variant = page.get("auto_advance_delays", [])
	_auto_advance_delays = delays_value.duplicate() if delays_value is Array else []
	var is_blackout := style == "blackout"
	var is_curtain := style == "curtain"
	_split.visible = not is_blackout and not is_curtain
	_curtain.visible = is_curtain
	_blackout.visible = is_blackout
	_sentences = _split_sentences(str(page.get("text", "")))
	_revealed_count = 0
	if is_curtain:
		_render_curtain(page)
		return
	_clear_sentences(_current_sentence_list())
	if is_blackout:
		_reveal_next_sentence()
		return
	_page_label.text = "%d / %d" % [page_index + 1, _pages.size()]
	var portrait_key := str(page.get("portrait", "portrait"))
	var image_path := str(_character.get(portrait_key, ""))
	var texture: Texture2D = null
	if image_path != "" and ResourceLoader.exists(image_path):
		texture = load(image_path)
	_portrait.texture = texture
	_portrait_placeholder.visible = texture == null
	_next_button.text = "はじめる ▶" if page_index + 1 >= _pages.size() else "次へ ▼"
	_reveal_next_sentence()

## 全画面のキャラ画を覆う左右の黒幕を、中央の継ぎ目から外側へ開く。
## 開き切ったら入力待ちにし、次のクリックで通常の暗転遷移へつなぐ。
func _render_curtain(page: Dictionary) -> void:
	_curtain_portrait_key = str(page.get("portrait", "result"))
	var half_width := size.x * 0.5
	_curtain_left.position.x = 0.0
	_curtain_right.position.x = half_width
	_curtain_click_hint.visible = false
	_selection_button.visible = false
	_profile_card.visible = false
	_view_original_button.visible = false
	_render_profile_card()
	if DisplayServer.get_name() == "headless":
		_curtain_left.position.x = -half_width
		_curtain_right.position.x = size.x
		_curtain_click_hint.visible = true
		_selection_button.visible = true
		_profile_card.visible = true
		_view_original_button.visible = true
		return
	_page_transitioning = true
	_curtain_tween = create_tween()
	_curtain_tween.set_parallel(true)
	_curtain_tween.tween_property(
		_curtain_left, "position:x", -half_width, CURTAIN_OPEN_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_curtain_tween.tween_property(
		_curtain_right, "position:x", size.x, CURTAIN_OPEN_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_curtain_tween.set_parallel(false)
	_curtain_tween.tween_callback(_finish_curtain_open)

func _finish_curtain_open() -> void:
	_page_transitioning = false
	_curtain_click_hint.visible = true
	_selection_button.visible = true
	_profile_card.visible = true
	_view_original_button.visible = true

func _on_selection_pressed() -> void:
	selection_requested.emit()

## force_original: 「元の経歴を見る」ボタン押下中、名前・二つ名・プロフィール文・立ち絵を
## すべて初回（オープニング未読時）のものへ一時的に戻す（select_screen.gd と同じ挙動）。
func _render_profile_card(force_original: bool = false) -> void:
	_profile_epithet.text = str(_character["epithet"]) if force_original \
		else CharacterDefs.display_epithet(_character)
	_profile_name.text = str(_character["name"]) if force_original \
		else CharacterDefs.display_name(_character)
	_update_curtain_image(force_original)
	var opening_seen := bool(_character["opening_seen"])
	var use_after_opening := opening_seen and not force_original
	var profile_text := str(_character["profile_after_opening"]) if use_after_opening else ""
	if profile_text == "":
		profile_text = str(_character["profile"])
	if not use_after_opening:
		_profile_body.text = profile_text
		return
	_profile_body.text = (
		profile_text
		+ "\n\n矯正進度: [b]%d[/b] / 100"
		+ "\n累計絶頂回数: %d"
		+ "\n苦痛超過による矯正中断回数: %d"
	) % [
		int(_character["level"]),
		int(_character["finish_total"]),
		int(_character["pain_fail_total"])
	]

## force_original: 立ち絵を "portrait"（オープニング前の元絵）に戻す。離せば curtain
## ページ本来の portrait キー（通常 "result"）に戻す。
func _update_curtain_image(force_original: bool) -> void:
	var portrait_key := "portrait" if force_original else _curtain_portrait_key
	var image_path := str(_character.get(portrait_key, ""))
	_curtain_image.texture = load(image_path) if image_path != "" and ResourceLoader.exists(image_path) else null

func _current_sentence_list() -> VBoxContainer:
	return _blackout_sentence_list if _blackout.visible else _sentence_list

func _clear_sentences(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()

## 文を1つ、フェードインさせながら追加表示する（既に出ている文はそのまま残る）。
func _reveal_next_sentence() -> void:
	if _revealed_count >= _sentences.size():
		return
	var sentence := _sentences[_revealed_count]
	_revealed_count += 1
	var is_blackout := _blackout.visible
	var label := Label.new()
	label.text = sentence
	label.autowrap_mode = 3  # TextServer.AUTOWRAP_WORD_SMART
	if is_blackout:
		# CenterContainer は子の最小サイズに合わせて縮めるため、折り返し幅を
		# 明示しないと1文字ずつ縦積みに潰れてしまう。
		label.custom_minimum_size = Vector2(900.0, 0.0)
	else:
		label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if is_blackout else HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_size_override(
		"font_size", BLACKOUT_FONT_SIZE if is_blackout else SPLIT_FONT_SIZE)
	label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_current_sentence_list().add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, SENTENCE_FADE_DURATION)
	_schedule_auto_advance()

func _schedule_auto_advance() -> void:
	var delay := _current_auto_advance_delay()
	if delay <= 0.0 or DisplayServer.get_name() == "headless":
		return
	if _auto_advance_tween != null and _auto_advance_tween.is_running():
		_auto_advance_tween.kill()
	_auto_advance_tween = create_tween()
	_auto_advance_tween.tween_interval(delay)
	_auto_advance_tween.tween_callback(advance.bind(true))

func _current_auto_advance_delay() -> float:
	var delay_index := _revealed_count - 1
	if delay_index >= 0 and delay_index < _auto_advance_delays.size():
		return float(_auto_advance_delays[delay_index])
	return _auto_advance_delay

## 「。」で文を割る。既存の改行（空行含む）も区切りとして扱うので、
## 段落分けや短い演出セリフの改行はそのまま独立した行として表示される。
static func _split_sentences(text: String) -> Array[String]:
	var result: Array[String] = []
	for block in text.split("\n"):
		if block.strip_edges() == "":
			continue
		var start := 0
		for i in range(block.length()):
			if block[i] == "。":
				var sentence := block.substr(start, i - start + 1)
				if sentence.strip_edges() != "":
					result.append(sentence)
				start = i + 1
		var remainder := block.substr(start)
		if remainder.strip_edges() != "":
			result.append(remainder)
	return result
