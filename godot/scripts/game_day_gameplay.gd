class_name GameDayGameplay
extends RefCounted

## Node-independent daily gameplay calculations. GameScreen remains the
## coordinator for scene effects, while this class owns gauge mutations and
## touch-derived state.

const PAIN_GAIN_SCALE := 0.35

func brush_effect_rates(brush: Brush, level: int) -> Dictionary:
	var rub := brush.get_action_multiplier()
	return {
		"polish": brush.get_effective_polish_gain() * GameRules.polish_bonus(level) * rub,
		"pain": brush.get_effective_pain_gain() * GameRules.pain_resist(level) * rub * PAIN_GAIN_SCALE,
		"soothe": brush.get_effective_soothe_gain() * rub
	}

func is_brush_touching(brush: Brush, slime: SlimeTarget) -> bool:
	return brush.position.distance_to(slime.position) \
		<= brush.get_contact_radius() + slime.get_hit_radius()

func apply_brush_effects(
		brush: Brush, slimes: Array[SlimeTarget], state: GameDayState,
		level: int, delta: float) -> float:
	var rates := brush_effect_rates(brush, level)
	var polish_added := 0.0
	for slime in slimes:
		if not is_brush_touching(brush, slime):
			continue
		var side := String(slime.side)
		var polish_gain := float(rates["polish"]) * delta
		state.set_value(side, "polish", maxf(0.0, state.value(side, "polish") + polish_gain))
		var pain := clampf(state.value(side, "pain") + float(rates["pain"]) * delta,
			0.0, GameRules.PAIN_CAP)
		state.set_value(side, "pain", clampf(pain - float(rates["soothe"]) * delta,
			0.0, GameRules.PAIN_CAP))
		polish_added += polish_gain
	return polish_added

func apply_passive_changes(state: GameDayState, touched_sides: Dictionary, delta: float) -> void:
	for side in GameDayState.SIDES:
		if bool(touched_sides.get(side, false)):
			continue
		state.set_value(side, "pain", maxf(0.0,
			state.value(side, "pain") - GameRules.PAIN_RECOVERY_PER_SEC * delta))
		state.set_value(side, "polish", maxf(0.0,
			state.value(side, "polish") - GameRules.POLISH_DECAY_PER_SEC * delta))

func touch_info(brushes: Dictionary, slimes: Array[SlimeTarget], level: int) -> Dictionary:
	var touching := false
	var touched_sides := {}
	var polish_rate := 0.0
	var pain_rate := 0.0
	for brush: Brush in brushes.values():
		if not brush.visible or not brush.is_effective():
			continue
		var rates := brush_effect_rates(brush, level)
		for slime in slimes:
			if is_brush_touching(brush, slime):
				touching = true
				touched_sides[String(slime.side)] = true
				polish_rate += float(rates["polish"])
				pain_rate += float(rates["pain"]) - float(rates["soothe"])
	return {
		"touching": touching,
		"touched_sides": touched_sides,
		"polish_rate": polish_rate,
		"pain_rate": pain_rate
	}

func finish_count(state: GameDayState, threshold: float) -> int:
	var count := GameRules.finish_count(
		state.value("left", "polish"), state.value("right", "polish"), threshold)
	if count > 0:
		state.reset_polish()
	return count

func has_failed(state: GameDayState) -> bool:
	return state.peak_pain() >= GameRules.PAIN_LIMIT
