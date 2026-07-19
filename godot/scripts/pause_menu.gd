class_name PauseMenu
extends Control

const GameAudio = preload("res://scripts/game_audio.gd")

signal options_requested
signal title_requested
signal quit_requested

@onready var _options_button: Button = $Center/Panel/Margin/VBox/OptionsButton
@onready var _title_button: Button = $Center/Panel/Margin/VBox/TitleButton
@onready var _quit_button: Button = $Center/Panel/Margin/VBox/QuitButton
@onready var _confirm_dialog: ConfirmationDialog = $ConfirmDialog

var _pending_action := ""

func _ready() -> void:
	_options_button.pressed.connect(_on_options_pressed)
	_title_button.pressed.connect(_on_title_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_confirm_dialog.confirmed.connect(_on_confirm_dialog_confirmed)
	_confirm_dialog.canceled.connect(_on_confirm_dialog_canceled)
	_confirm_dialog.get_ok_button().text = "はい"
	_confirm_dialog.get_cancel_button().text = "キャンセル"

func open() -> void:
	visible = true

func close() -> void:
	visible = false
	_pending_action = ""
	_confirm_dialog.hide()

func _on_options_pressed() -> void:
	options_requested.emit()

func _on_title_pressed() -> void:
	_pending_action = "title"
	_confirm_dialog.dialog_text = "タイトルに戻りますか？\n（今日の進行状況は失われます）"
	_confirm_dialog.popup_centered()

func _on_quit_pressed() -> void:
	_pending_action = "quit"
	_confirm_dialog.dialog_text = "ゲームを終了しますか？"
	_confirm_dialog.popup_centered()

func _on_confirm_dialog_confirmed() -> void:
	var action := _pending_action
	_pending_action = ""
	GameAudio.play_se("ui_click")
	if action == "title":
		title_requested.emit()
	elif action == "quit":
		quit_requested.emit()

func _on_confirm_dialog_canceled() -> void:
	_pending_action = ""
