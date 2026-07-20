class_name GameDayState
extends RefCounted

## One day's mutable gauge state.  Keeping this outside GameScreen makes the
## gameplay calculations usable without scene nodes and centralizes the
## left/right dictionary contract used by tool actions and debug helpers.

const SIDES: Array[String] = ["left", "right"]

var targets: Dictionary = {}

func _init() -> void:
	reset()

func reset() -> void:
	targets = {
		"left": {"polish": 0.0, "pain": 0.0},
		"right": {"polish": 0.0, "pain": 0.0}
	}

func combined_polish() -> float:
	return value("left", "polish") + value("right", "polish")

func peak_pain() -> float:
	return maxf(value("left", "pain"), value("right", "pain"))

func value(side: String, gauge: String) -> float:
	return float(targets.get(side, {}).get(gauge, 0.0))

func set_value(side: String, gauge: String, amount: float) -> void:
	var state: Dictionary = targets.get(side, {})
	state[gauge] = amount
	targets[side] = state

func reset_polish() -> void:
	for side in SIDES:
		set_value(side, "polish", 0.0)

