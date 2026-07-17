class_name SelectScreen
extends Control

const GameAudio = preload("res://scripts/game_audio.gd")

signal character_selected(index: int)
signal progress_changed

var _characters: Array[Dictionary] = []
var _pending_character_index := -1

@onready var _cards: HBoxContainer = $Margin/VBox/Cards
@onready var _character_confirm_dialog: ConfirmationDialog = $CharacterConfirmDialog

func _ready() -> void:
	_character_confirm_dialog.confirmed.connect(_on_character_confirmed)
	_character_confirm_dialog.canceled.connect(_on_character_selection_canceled)
	_character_confirm_dialog.get_ok_button().text = "選択"
	_character_confirm_dialog.get_cancel_button().text = "キャンセル"

func setup(characters: Array[Dictionary]) -> void:
	_characters = characters
	var show_debug_tools := OS.is_debug_build()
	for index in range(_characters.size()):
		var card := get_card(index)
		var button: Button = card.get_node("InteractionLayer/CardButton")
		button.pressed.connect(_on_character_card_pressed.bind(index))
		var reset_button: Button = card.get_node("InteractionLayer/DebugResetButton")
		reset_button.visible = show_debug_tools
		reset_button.disabled = not show_debug_tools
		if show_debug_tools:
			reset_button.pressed.connect(_on_character_reset_pressed.bind(index))
		var view_original_button: Button = card.get_node("InteractionLayer/ViewOriginalButton")
		view_original_button.button_down.connect(refresh_character_card.bind(index, true))
		view_original_button.button_up.connect(refresh_character_card.bind(index, false))

func show_characters() -> void:
	_pending_character_index = -1
	_character_confirm_dialog.hide()
	visible = true
	refresh_character_cards()

func get_card(index: int) -> Control:
	return _cards.get_node("Card%d" % index)

func refresh_character_cards() -> void:
	for index in range(_characters.size()):
		refresh_character_card(index)

## force_original: 「元の経歴を見る」ボタン押下中に名前・二つ名・立ち絵・プロフィール文を
## すべて初回（オープニング未読時）のものへ一時的に戻す。
func refresh_character_card(index: int, force_original: bool = false) -> void:
	var chara: Dictionary = _characters[index]
	var card := get_card(index)
	var info: VBoxContainer = card.get_node("Margin/VBox/PortraitArea/InfoOverlay/Margin/VBox")
	var name_label: Label = info.get_node("NameLabel")
	var epithet_label: Label = info.get_node("EpithetLabel")
	var profile_body: RichTextLabel = info.get_node("ProfileBody")
	var portrait: TextureRect = card.get_node("Margin/VBox/PortraitArea/Portrait")
	var placeholder: Label = card.get_node("Margin/VBox/PortraitArea/PortraitPlaceholder")
	var view_original_button: Button = card.get_node("InteractionLayer/ViewOriginalButton")
	var opening_seen := bool(chara.get("opening_seen", false))
	view_original_button.visible = opening_seen
	var use_after_opening := opening_seen and not force_original
	name_label.text = str(chara.get("name", "")) if force_original else CharacterDefs.display_name(chara)
	epithet_label.text = str(chara.get("epithet", "")) if force_original else CharacterDefs.display_epithet(chara)
	var opening_state := "済" if opening_seen else "未（開始時に再生）"
	var profile_text := str(chara.get("profile_after_opening", "")) if use_after_opening else ""
	if profile_text == "":
		profile_text = str(chara.get("profile", ""))
	profile_body.text = (
		"%s\n\n"
		+ "レベル: [b]%d[/b] / %d\n"
		+ "累計FINISH: %d\n"
		+ "痛み失敗: %d\n"
		+ "オープニング: %s"
	) % [
		profile_text,
		int(chara["level"]),
		GameRules.MAX_LEVEL,
		int(chara["finish_total"]),
		int(chara["pain_fail_total"]),
		opening_state
	]
	var portrait_path := str(chara.get(
		"portrait_after_opening" if use_after_opening else "portrait",
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
	_fit_profile_overlay.call_deferred(info_overlay)

func _fit_profile_overlay(info_overlay: PanelContainer) -> void:
	if not is_instance_valid(info_overlay):
		return
	info_overlay.offset_top = info_overlay.offset_bottom - info_overlay.get_combined_minimum_size().y

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
	GameAudio.play_se("ui_click")
	character_selected.emit(index)

func _on_character_selection_canceled() -> void:
	_pending_character_index = -1

func _on_character_reset_pressed(index: int) -> void:
	if not OS.is_debug_build() or index < 0 or index >= _characters.size():
		return
	GameAudio.play_se("ui_click")
	var chara: Dictionary = _characters[index]
	chara["level"] = 1
	chara["finish_total"] = 0
	chara["pain_fail_total"] = 0
	chara["opening_seen"] = false
	_characters[index] = chara
	progress_changed.emit()
	refresh_character_card(index)
