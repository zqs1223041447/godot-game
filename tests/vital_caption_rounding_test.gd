extends SceneTree

func _initialize() -> void:
	var hud = load("res://scripts/game_hud.gd").new()
	var bar := ProgressBar.new()
	var label := Label.new()
	hud._bars["shield"] = bar
	hud._bar_values["shield"] = label
	var failures := 0
	for entry: Array in [[91.8,91.8,"92 / 92"],[91.3,91.8,"92 / 92"],[0.0,91.8,"0 / 92"],[0.0,0.0,"0 / 0"],[100.0,100.0,"100 / 100"]]:
		hud._set_vital("shield",entry[0],entry[1])
		if label.text != entry[2]:
			failures += 1
			push_error("Vital caption mismatch: "+label.text)
	print("Vital caption rounding: 5 checks, %d failures" % failures)
	bar.free()
	label.free()
	hud.free()
	quit(1 if failures else 0)
