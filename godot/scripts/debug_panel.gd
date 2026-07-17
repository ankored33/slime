class_name DebugPanel
extends PanelContainer

## F1で開閉する開発用チートパネル。game_screen.gd の debug_* フックを呼ぶだけの薄いUI。
## リリースビルドでは game_screen が生成しないため、プレイヤーからは見えない。

const TIME_SCALES: Array[float] = [1.0, 2.0, 4.0]

var _screen: Node
var _info_label: Label

func _init(screen: Node) -> void:
	_screen = screen

func _ready() -> void:
	position = Vector2(340, 16)
	self_modulate = Color(1, 1, 1, 0.94)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_info_label)

	vbox.add_child(_row([
		_button("Lv−", func() -> void: _screen.debug_set_level(_screen.debug_get_level() - 1)),
		_button("Lv＋", func() -> void: _screen.debug_set_level(_screen.debug_get_level() + 1)),
		_button("Lv−100", func() -> void: _screen.debug_set_level(_screen.debug_get_level() - 100)),
		_button("Lv＋100", func() -> void: _screen.debug_set_level(_screen.debug_get_level() + 100)),
		_button("倍速切替", _cycle_time_scale)
	]))
	vbox.add_child(_row([
		_button("左快感+250", func() -> void: _screen.debug_add_gauge("left", "polish", 250.0)),
		_button("左痛み+250", func() -> void: _screen.debug_add_gauge("left", "pain", 250.0)),
		_button("右快感+250", func() -> void: _screen.debug_add_gauge("right", "polish", 250.0)),
		_button("右痛み+250", func() -> void: _screen.debug_add_gauge("right", "pain", 250.0))
	]))
	vbox.add_child(_row([
		_button("ゲージ全リセット", func() -> void: _screen.debug_reset_gauges()),
		_button("FINISH発火", func() -> void: _screen.debug_trigger_finish()),
		_button("失敗発火", func() -> void: _screen.debug_trigger_fail())
	]))
	vbox.add_child(_row([
		_button("表情→次", func() -> void: _screen.debug_cycle_expression()),
		_button("表情:自動", func() -> void: _screen.debug_clear_expression())
	]))

func _process(_delta: float) -> void:
	if not visible:
		return
	var override_id := str(_screen.debug_expression_override())
	_info_label.text = "DEBUG (F1で閉じる)　Lv %d ／ 倍速 x%d ／ 表情 %s" % [
		_screen.debug_get_level(),
		int(Engine.time_scale),
		"自動" if override_id == "" else override_id
	]

func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for button in buttons:
		row.add_child(button)
	return row

func _button(label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(handler)
	return button

func _cycle_time_scale() -> void:
	var index := TIME_SCALES.find(Engine.time_scale)
	Engine.time_scale = TIME_SCALES[(index + 1) % TIME_SCALES.size()]
