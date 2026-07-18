class_name OpeningScreen
extends Control

const GameAudio = preload("res://scripts/game_audio.gd")

signal finished

## 文の区切り（。または既存の改行）ごとに1行としてフェードインさせる演出。
## クリック/advance()は「未表示の文を1つ出す」→ 出し切ったら「次のページへ」の順で進む。
const SENTENCE_FADE_DURATION := 0.35
const SPLIT_FONT_SIZE := 22
const BLACKOUT_FONT_SIZE := 44

var page_index := 0
var _character: Dictionary = {}
var _sentences: Array[String] = []
var _revealed_count := 0

@onready var _split: Control = $SplitView
@onready var _portrait: TextureRect = $SplitView/PortraitRect
@onready var _portrait_placeholder: Label = $SplitView/PortraitPlaceholder
@onready var _sentence_list: VBoxContainer = $SplitView/TextPanel/Margin/TextVBox/TextScroll/SentenceList
@onready var _page_label: Label = $SplitView/TextPanel/Margin/TextVBox/Actions/PageLabel
@onready var _next_button: Button = $SplitView/TextPanel/Margin/TextVBox/Actions/OpeningNextButton
@onready var _blackout: Control = $BlackoutView
@onready var _blackout_sentence_list: VBoxContainer = $BlackoutView/BlackoutCenter/SentenceList

func _ready() -> void:
	_next_button.pressed.connect(advance)
	# 暗転ページを含め、画面のどこをクリックしても進める。
	gui_input.connect(_on_gui_input)

func start(character: Dictionary) -> void:
	_character = character
	page_index = 0
	visible = true
	_render_page()
	GameAudio.play_bgm("opening_%s" % str(_character.get("id", "")))

## 未表示の文が残っていればそれを1つフェードインさせる。出し切っていれば次のページへ、
## 最終ページなら演出を終える。
func advance() -> void:
	GameAudio.play_se("ui_click")
	if _revealed_count < _sentences.size():
		_reveal_next_sentence()
		return
	var pages: Array = _character.get("opening_pages", [])
	if page_index + 1 < pages.size():
		page_index += 1
		_render_page()
		return
	finished.emit()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		advance()

func _render_page() -> void:
	var pages: Array = _character.get("opening_pages", [])
	if pages.is_empty():
		_split.visible = false
		_blackout.visible = false
		return
	var page: Dictionary = pages[page_index]
	var is_blackout := str(page.get("style", "split")) == "blackout"
	_split.visible = not is_blackout
	_blackout.visible = is_blackout
	_sentences = _split_sentences(str(page.get("text", "")))
	_revealed_count = 0
	_clear_sentences(_current_sentence_list())
	if is_blackout:
		_reveal_next_sentence()
		return
	_page_label.text = "%d / %d" % [page_index + 1, pages.size()]
	var portrait_key := str(page.get("portrait", "portrait"))
	var image_path := str(_character.get(portrait_key, ""))
	var texture: Texture2D = null
	if image_path != "" and ResourceLoader.exists(image_path):
		texture = load(image_path)
	_portrait.texture = texture
	_portrait_placeholder.visible = texture == null
	_next_button.text = "はじめる ▶" if page_index + 1 >= pages.size() else "次へ ▼"
	_reveal_next_sentence()

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
