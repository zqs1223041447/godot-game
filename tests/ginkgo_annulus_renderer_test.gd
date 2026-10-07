extends SceneTree
const Renderer = preload("res://scripts/visuals/telegraph_renderer.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var base := {"source_id":1,"center":Vector2(420,350),"phase":"windup","elapsed":0.5,"visual_pattern":"ginkgo_shelter_slam","pulse_index":1,"pulse_count":2,"shape":"annulus","inner_radius":130.0,"profile":{"radius":240.0,"windup_seconds":1.0,"recovery_seconds":1.9}}
	var original := var_to_bytes(base)
	for effects in range(3):
		var settings := Settings.new()
		settings.effects_level = effects
		var primitives := Renderer.primitives([base], settings)
		expect(primitives.size() <= Renderer.MAX_PRIMITIVES_PER_SOURCE, "Bounded annulus primitives")
		var inner := 0
		var outer := 0
		var fills := 0
		for primitive: Dictionary in primitives:
			if primitive.kind == "annulus":
				fills += 1
				expect(primitive.inner_radius == 130.0 and primitive.radius == 240.0 and primitive.center == base.center, "Tint retains exact safe hole")
			elif primitive.kind == "circle":
				expect(not primitive.filled, "Never tint safe center as filled disk")
				if primitive.role == "danger_inner_boundary":
					inner += 1
					expect(primitive.radius == 130.0, "True inner boundary")
				elif primitive.role == "danger_boundary":
					outer += 1
					expect(primitive.radius == 240.0, "True outer boundary")
			elif primitive.kind == "polyline":
				expect(primitive.points.size() <= Renderer.MAX_POLYLINE_POINTS, "Bounded rune")
				for point: Vector2 in primitive.points:
					var distance := point.distance_to(base.center)
					expect(distance > 132.0 and distance < 238.0, "Rune stays in dangerous band")
		expect(fills == 1 and inner == 2 and outer == 2, "Both boundaries retained at every effects level")
	expect(var_to_bytes(base) == original, "Snapshot unchanged")
	var first := base.duplicate(true)
	first.shape = "circle"
	first.inner_radius = 0.0
	first.pulse_index = 0
	first.profile.radius = 130.0
	first.profile.windup_seconds = 1.4
	var first_primitives := Renderer.primitives([first])
	expect(first_primitives[0].kind == "circle" and first_primitives[0].filled and first_primitives[0].radius == 130.0, "First stage remains filled inner disk")
	for invalid in [-1.0,0.0,240.0,250.0,NAN]:
		var bad := base.duplicate(true)
		bad.inner_radius = invalid
		expect(Renderer.primitives([bad]).is_empty(), "Invalid inner radius rejected")
	var recovery := base.duplicate(true)
	recovery.phase = "recovery"
	recovery.elapsed = 1.1
	expect(not Renderer.primitives([recovery]).is_empty(), "Second-stage recovery renders hole")
	recovery.elapsed = 2.9
	expect(Renderer.primitives([recovery]).is_empty(), "Expired recovery omitted")
	print("Ginkgo annulus renderer: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
