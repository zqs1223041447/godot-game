extends SceneTree
## Bounded developer stress, isolated user:// by tools/validate.sh.
const Model = preload("res://scripts/build_state.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func run() -> void:
	var arena: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.rng.seed = 5050600
	arena.equip_tornado_example()
	arena.hud.close_panel()
	var max_owned: int = 0
	var max_live: int = 0
	for frame: int in range(36000):
		# Immunity and refill isolate capacity/persistence from player survival.
		arena.invulnerable = 1.0
		if frame % 180 == 0:
			arena.mana = arena.get_stats().max_mana
			arena.cast_skill(0)
		arena.tick(1.0 / 60.0)
		if frame % 300 == 0:
			# Complete active encounters via the real one-shot death/reward route.
			for enemy: Dictionary in arena.enemies.duplicate():
				if float(enemy.spawn) <= 0.0:
					arena._damage_enemy(enemy, 10000000.0, Color.WHITE)
			arena._flush_monster_spawns()
		if frame % 600 == 0:
			max_owned = maxi(max_owned, arena.state.equipment_instances.size())
			max_live = maxi(max_live, arena.enemies.size())
			expect(arena.enemies.size() <= arena.MAX_ENEMIES and arena.projectiles.size() <= arena.MAX_PROJECTILES, "Combat capacities stay bounded")
			expect(not arena.state._validate_snapshot(arena.state._snapshot()).is_empty(), "Evolving gear, jewels and layout remain save-valid")
			expect(Model._owned_items_fit(arena.state.inventory, arena.state.jewels.keys(), arena.state.equipment_instances), "All worn and socketed loot retains return capacity")
			# Free two generated items periodically; monotonically new rolls can refill.
			for id: String in arena.state.equipment_instances.keys().slice(0, 2):
				arena.state.discard_equipment(id)
	expect(arena.elapsed >= 599.9 and arena.alive, "Ten simulated minutes reach completion")
	expect(arena.state.next_equipment_id > 20 and arena.reward_kills > 100, "Stress exercised repeated root loot and item identity allocation")
	var saved: Dictionary = arena.state._snapshot()
	expect(arena.state.save_build("user://soak_roundtrip.json") == OK, "Stress snapshot writes")
	var loaded := Model.new()
	expect(loaded.load_build("user://soak_roundtrip.json") and loaded._snapshot() == saved, "Stress snapshot reloads without rerolls")
	print("Equipment soak: %d checks, %d failures; 600 simulated seconds, %d eligible kills, %d issued gear, peak owned %d, peak live %d" % [checks, failures, arena.reward_kills, arena.state.next_equipment_id - 1, max_owned, max_live])
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
