@tool
class_name NamedGauge
extends ProgressBar

@export var gauge_id := "":
	set(value):
		gauge_id = value
		_refresh_label()

@export var caption := "":
	set(value):
		caption = value
		_refresh_label()

@onready var _caption_label: Label = $Caption

func _ready() -> void:
	add_to_group("named_gauges")
	show_percentage = false
	_refresh_label()

func set_gauge_value(current: float, maximum: float = GameRules.GAUGE_MAX) -> void:
	max_value = max(1.0, maximum)
	value = clamp(current, 0.0, max_value)
	_refresh_label()

func _refresh_label() -> void:
	if not is_node_ready():
		return
	var title := caption if caption != "" else gauge_id
	_caption_label.text = "%s  %d / %d" % [title, int(round(value)), int(round(max_value))]
