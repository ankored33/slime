class_name OptionsScreen
extends Control

const GameAudio = preload("res://scripts/game_audio.gd")

signal back_requested

@onready var _back_button: Button = $Center/Panel/Margin/VBox/OptionsBackButton
@onready var _volume_sliders: Dictionary = {
	"bgm": $Center/Panel/Margin/VBox/BgmRow/BgmSlider,
	"se": $Center/Panel/Margin/VBox/SeRow/SeSlider,
	"voice": $Center/Panel/Margin/VBox/VoiceRow/VoiceSlider
}
@onready var _volume_value_labels: Dictionary = {
	"bgm": $Center/Panel/Margin/VBox/BgmRow/BgmValue,
	"se": $Center/Panel/Margin/VBox/SeRow/SeValue,
	"voice": $Center/Panel/Margin/VBox/VoiceRow/VoiceValue
}
@onready var _hearts_slider: HSlider = $Center/Panel/Margin/VBox/HeartsRow/HeartsSlider
@onready var _hearts_value_label: Label = $Center/Panel/Margin/VBox/HeartsRow/HeartsValue

func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	for category: String in _volume_sliders.keys():
		var slider: HSlider = _volume_sliders[category]
		slider.value_changed.connect(_on_volume_changed.bind(category))
	_hearts_slider.value_changed.connect(_on_hearts_opacity_changed)

func show_options() -> void:
	visible = true
	for category: String in _volume_sliders.keys():
		var volume := GameAudio.get_volume(category)
		(_volume_sliders[category] as HSlider).set_value_no_signal(volume)
		_update_volume_value_label(category, volume)
	var opacity := GameSettings.get_heart_opacity()
	_hearts_slider.set_value_no_signal(opacity)
	_hearts_value_label.text = "%d%%" % int(round(opacity * 100.0))

func _on_back_pressed() -> void:
	back_requested.emit()

func _on_volume_changed(value: float, category: String) -> void:
	GameAudio.set_volume(category, value)
	_update_volume_value_label(category, value)

func _update_volume_value_label(category: String, volume: float) -> void:
	(_volume_value_labels[category] as Label).text = "%d%%" % int(round(volume * 100.0))

func _on_hearts_opacity_changed(value: float) -> void:
	GameSettings.set_heart_opacity(value)
	_hearts_value_label.text = "%d%%" % int(round(value * 100.0))
