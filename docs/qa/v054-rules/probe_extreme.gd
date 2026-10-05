extends SceneTree
const Rules = preload("res://scripts/combat/burn_rules.gd")

func _initialize() -> void:
	for values: Array in [[1.0e-308, 1.0e308], [1.0e-300, 1.0e300]]:
		var fire: float = values[0]
		var faster: float = values[1]
		print("fire=%s faster=%s first_raw=%s final_dps=%s duration=%s result=%s" % [
			fire, faster, fire * 0.3, Rules.raw_fire_dps(fire, 0.3, 0.0, faster),
			Rules.burn_duration(3.0, faster), Rules.from_fire_hit(fire, Rules.PLAYER_POLICY, 0.0, faster)])
	quit(0)
