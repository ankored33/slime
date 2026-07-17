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

func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	for category: String in _volume_sliders.keys():
		var slider: HSlider = _volume_sliders[category]
		slider.value_changed.connect(_on_volume_changed.bind(category))

func show_options() -> void:
	visible = true
	for category: String in _volume_sliders.keys():
		var volume := GameAudio.get_volume(category)
		(_volume_sliders[category] as HSlider).set_value_no_signal(volume)
		_update_volume_value_label(category, volume)

func _on_back_pressed() -> void:
	GameAudio.play_se("ui_click")
	back_requested.emit()

func _on_volume_changed(value: float, category: String) -> void:
	GameAudio.set_volume(category, value)
	_update_volume_value_label(category, value)

func _update_volume_value_label(category: String, volume: float) -> void:
	(_volume_value_labels[category] as Label).text = "%d%%" % int(round(volume * 100.0))
