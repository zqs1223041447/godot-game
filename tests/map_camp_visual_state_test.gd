extends SceneTree
const Layer = preload("res://scripts/visuals/static_arena_layer.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var layer := Layer.new()
	root.add_child(layer)
	var geometry := {"walls": [], "landmarks": {"entry":Vector2(920,670), "camps":[{"id":"a","center":Vector2(290,170),"trigger_center":Vector2(290,590),"trigger_radius":64.0,"root_count":8}], "boss":{"center":Vector2(920,355),"trigger_center":Vector2(920,670),"trigger_radius":64.0}}}
	var before := var_to_bytes(geometry)
	layer.configure(Rect2(0,0,1840,711), null)
	layer.set_geometry(geometry)
	layer.set_encounter_state([{"id":"a","state":"dormant","roots_defeated":0}], "sealed")
	await process_frame
	await process_frame
	var signs: Node2D = layer._camp_signs
	expect(layer.world_geometry() == geometry, "Visual layer uses supplied absolute geometry")
	expect(var_to_bytes(geometry) == before, "Visual preparation does not mutate geometry")
	expect(signs._states == {"a":"dormant"} and signs._boss == "sealed", "Sealed state is copied without gameplay inference")
	var ground_count: int = layer.draw_count
	expect(ground_count > 0 and signs.draw_count > 0, "Initial canvas draw occurred before redraw comparisons")
	layer.set_encounter_state([{"id":"a","state":"active","roots_defeated":0}], "sealed")
	await process_frame
	await process_frame
	expect(layer.draw_count == ground_count, "Camp activation never redraws whole arena")
	var signs_count: int = signs.draw_count
	layer.set_encounter_state([{"id":"a","state":"active","roots_defeated":1}], "sealed")
	await process_frame
	await process_frame
	expect(signs.draw_count == signs_count, "Per-kill progress never redraws unchanged flags")
	layer.set_encounter_state([{"id":"a","state":"cleared","roots_defeated":8}], "ready")
	expect(signs._states.a == "cleared" and signs._boss == "ready", "Final states come only from backend fields")
	layer.set_geometry({"walls":[]})
	expect(signs._landmarks.is_empty(), "Town or arena removes map landmarks")
	layer.queue_free()
	await process_frame
	print("Map camp visuals: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
