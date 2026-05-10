extends Control

@onready var game_screen: Control = $GameScreen
@onready var summary_label: RichTextLabel = $Overlay/Panel/Margin/VBox/Summary
@onready var toggle_button: Button = $Overlay/Panel/Margin/VBox/ToggleButton

func _ready() -> void:
	toggle_button.pressed.connect(_on_toggle_pressed)
	summary_label.text = (
		"[b]Godot migration direction[/b]\n"
		+ "Layout is no longer stored as generic runtime editor elements.\n"
		+ "Instead, scene nodes carry game meaning directly.\n\n"
		+ "[b]Current mapping[/b]\n"
		+ "- object(role=slime) -> SlimeTarget node\n"
		+ "- object(role=wall) -> WallZone node\n"
		+ "- gauge(name=...) -> NamedGauge node\n"
		+ "- brush config -> Brush node exports\n"
		+ "- screen layout -> game_screen.tscn"
	)

func _on_toggle_pressed() -> void:
	game_screen.visible = not game_screen.visible
	toggle_button.text = "Show Game" if not game_screen.visible else "Hide Game"
