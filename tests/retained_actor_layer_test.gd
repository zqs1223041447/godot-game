extends SceneTree
## Foot-root lifecycle, shared resource stability and read-only presentation.
const Layer = preload("res://scripts/visuals/retained_actor_layer.gd")
const Factory = preload("res://scripts/monsters/monster_runtime.gd")
const Catalog = preload("res://scripts/monsters/monster_catalog.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
class Fixture extends Node2D:
	var enemies: Array[Dictionary] = []
	var visual_settings = Settings.new()
	var elapsed := 0.0
	var player_pos := Vector2(640, 360)
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host := Fixture.new(); root.add_child(host)
	var layer := Layer.new(); host.add_child(layer)
	var prop := Node2D.new(); prop.name = "IndependentScenery"; prop.position = Vector2(100, 110); layer.add_child(prop)
	var factory := Factory.new()
	for id: String in Catalog.TEMPLATES:
		var enemy := factory.create_root(id, 5, Vector2(100 + host.enemies.size() * 55, 100), "map_boss" if id == "rift_warden" else "ordinary", "", [], false)
		check(not enemy.is_empty(), "Every authored family has a real display fixture")
		host.enemies.append(enemy)
	var initial := var_to_bytes(host.enemies)
	seed(105105); var expected_rng := randi(); seed(105105)
	layer.sync(host)
	var n := host.enemies.size(); var first := layer.diagnostics()
	check(first.actors == n and first.pieces == n * 3 and layer.get_child_count() == n + 1, "One foot root and two retained local parts per identity")
	check(layer.y_sort_enabled and layer.z_index == 0, "WorldDepth sorts roots with a common z")
	var identities := {}
	for actor: Node2D in layer._actors.values():
		identities[int(actor.enemy.id)] = actor.get_instance_id()
		check(actor.position == actor.enemy.pos and actor.rotation == 0.0 and actor.z_index == prop.z_index and not actor.y_sort_enabled, "Actor foot and prop share one atomic y-sort space")
	var before_fallback := {}
	for id: int in layer._actors:
		if layer._actors[id].atlas.is_empty(): before_fallback[id] = layer._actors[id].body.redraw_requests
	for unused: int in range(12): layer.advance(0.1); layer.sync(host)
	for id: int in before_fallback: check(layer._actors[id].body.redraw_requests == before_fallback[id], "Fallback static body is retained while limbs animate")
	check(var_to_bytes(host.enemies) == initial, "Synchronization leaves all authoritative enemy bytes untouched")
	for enemy: Dictionary in host.enemies: enemy.pos += Vector2(0.113, 0.071)
	layer.sync(host)
	for id: int in before_fallback: check(layer._actors[id].body.redraw_requests == before_fallback[id], "Subpixel movement never rebuilds fallback static geometry")
	for enemy: Dictionary in host.enemies: enemy.flash = 0.1
	layer.sync(host)
	for actor: Node2D in layer._actors.values(): check(actor.hurt, "Flash enters the same retained actor")
	var flash_counts := {}
	for id: int in layer._actors: flash_counts[id] = layer._actors[id].body.redraw_requests
	for enemy: Dictionary in host.enemies: enemy.flash = 0.05
	layer.sync(host)
	for id: int in flash_counts: check(layer._actors[id].body.redraw_requests == flash_counts[id], "Positive flash countdown does not rebuild identical tint")
	host.enemies.reverse(); var before := var_to_bytes(host.enemies); layer.sync(host)
	check(var_to_bytes(host.enemies) == before, "Canvas Y sort does not mutate authoritative enemy order")
	for id: int in identities: check(layer._actors[id].get_instance_id() == identities[id], "Input order never replaces a retained root")
	host.enemies.remove_at(0); layer.sync(host)
	check(layer.diagnostics().actors == n - 1 and layer.get_child_count() == n, "Death detaches the whole root and both parts immediately")
	layer.clear()
	check(layer.diagnostics().actors == 0 and layer.get_child_count() == 1 and prop.get_parent() == layer, "Restart clears actors without touching independently managed scenery")
	layer.sync(host); check(layer.diagnostics().actors == n - 1, "Re-entry reconstructs only live identities")
	# 100 entities retain exactly the same bounded roots, parts and textures.
	layer.clear(); host.enemies.clear()
	for i: int in range(100): host.enemies.append(Catalog.make_enemy(i + 1, "crawler", 1, Vector2(100 + (i % 20) * 40, 100 + (i / 20) * 60)))
	layer.sync(host); identities.clear(); var texture_ids := {}
	for id: int in layer._actors:
		var actor: Node2D = layer._actors[id]; identities[id] = [actor.get_instance_id(), actor.body.get_instance_id(), actor.limbs.get_instance_id()]
		if not actor.atlas.is_empty(): texture_ids[actor.atlas.texture.get_instance_id()] = true
	for step: int in range(120):
		for enemy: Dictionary in host.enemies: enemy.pos += Vector2(0.13, 0.02)
		layer.advance(1.0 / 60.0); layer.sync(host)
	check(layer._actors.size() == 100 and layer.get_child_count() == 101 and texture_ids.size() <= 1, "100 monsters use stable bounded nodes and at most one shared atlas")
	for id: int in identities:
		var actor: Node2D = layer._actors[id]
		check(identities[id] == [actor.get_instance_id(), actor.body.get_instance_id(), actor.limbs.get_instance_id()], "Repeated animation preserves all retained instances")
	check(randi() == expected_rng, "Actor admission, sorting and animation consume no RNG")
	host.queue_free(); await process_frame; await process_frame
	print("Retained foot-root lifecycle: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
