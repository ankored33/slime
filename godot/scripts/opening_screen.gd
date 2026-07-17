class_name OpeningScreen
extends Control

const GameAudio = preload("res://scripts/game_audio.gd")

signal finished

var page_index := 0
var _character: Dictionary = {}

@onready var _split: Control = $SplitView
@onready var _portrait: TextureRect = $SplitView/PortraitRect
@onready var _portrait_placeholder: Label = $SplitView/PortraitPlaceholder
@onready var _text: RichTextLabel = $SplitView/TextPanel/Margin/TextVBox/OpeningText
@onready var _page_label: Label = $SplitView/TextPanel/Margin/TextVBox/Actions/PageLabel
@onready var _next_button: Button = $SplitView/TextPanel/Margin/TextVBox/Actions/OpeningNextButton
@onready var _blackout: Control = $BlackoutView
@onready var _blackout_label: Label = $BlackoutView/BlackoutLabel

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

func advance() -> void:
	GameAudio.play_se("ui_click")
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
	if is_blackout:
		_blackout_label.text = str(page.get("text", ""))
		return
	_text.text = str(page.get("text", ""))
	_page_label.text = "%d / %d" % [page_index + 1, pages.size()]
	var portrait_key := str(page.get("portrait", "portrait"))
	var image_path := str(_character.get(portrait_key, ""))
	var texture: Texture2D = null
	if image_path != "" and ResourceLoader.exists(image_path):
		texture = load(image_path)
	_portrait.texture = texture
	_portrait_placeholder.visible = texture == null
	_next_button.text = "はじめる ▶" if page_index + 1 >= pages.size() else "次へ ▼"
