extends SceneTree
## Real scene cast admission, support scope and frozen projectile lineage.
## Run each suite with its own disposable XDG roots, never against a player's save.
const Model = preload("res://scripts/build_state.gd")
const Data = preload("res://scripts/game_data.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")
const FRESH_PATH: String = "user://skill_support_integration_fresh.json"

class CountingState extends "res://scripts/build_state.gd":
	var compile_calls: int = 0
	func get_skill_cast(skill_id: String) -> Dictionary:
		compile_calls += 1
		return super.get_skill_cast(skill_id)

var arena: Node
var checks: int = 0
var failures: int = 0
var _finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fresh = Model.new()
	_expect(fresh.save_build() == OK and fresh.save_build(FRESH_PATH) == OK, "Scene fixtures save only inside disposable user directory")
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = CountingState.new()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	_case(_test_cast_counts_and_costs, "supported real cast counts and exact costs")
	_case(_test_capacity, "whole-volley capacity admission")
	_case(_test_insufficient_mana, "insufficient mana and exact-cost admission")
	_case(_test_invalid_runtime_links, "corrupt runtime links fail before payment")
	_case(_test_concurrent_skills, "swapped independent skills in flight together")
	_case(_test_damage_scope, "real skill hits and support scope algebra")
	_case(_test_frozen_lineage, "children, return, explosions and live mitigation")
	_case(_test_cancelled_lineage, "death and reset cancellation")
	_case(_test_bounded_parents, "bounded parent count and child-budget refusal")
	print("Skill support integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	_finished = false
	test.call()
	_expect(_finished, "Scene case completes without a script exception: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.0001, "%s (actual %.7f, expected %.7f)" % [label, value, expected])


func _reset() -> void:
	_expect(arena.state.load_build(FRESH_PATH), "Known fixture reload preserves the scene's live signal connections")
	arena.restart_run()
	arena.auto_fire = false
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.spawn_timer = 99999.0
	arena.player_pos = Vector2(500, 300)
	arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 606001


func _bare() -> void:
	for slot: String in Model.EQUIPMENT_SLOTS:
		arena.state.unequip(slot)


func _prepare(skill: String, supports: Array, bow: bool = false) -> void:
	_reset()
	_bare()
	if bow:
		arena.state.equip("prism_bow")
	arena.state.slot_skill(0, skill)
	arena.state.set_skill_supports(skill, supports)
	arena.mana = 100.0
	arena.cooldowns[skill] = 0.0
	arena.state.compile_calls = 0


func _cast(index: int = 0) -> bool:
	arena.state.compile_calls = 0
	var accepted: bool = arena.cast_skill(index)
	_expect(arena.state.compile_calls == 1, "Main compiles exactly once for one cast admission decision")
	return accepted


func _test_cast_counts_and_costs() -> void:
	var base_counts: Dictionary = {"tornado": 3, "bolt": 3, "frost": 5}
	var support_sets: Array = [[], ["volley"], ["focus"], ["volley", "focus"], ["focus", "volley"]]
	for skill: String in base_counts:
		for links: Array in support_sets:
			for bow: bool in [false, true]:
				_prepare(skill, links, bow)
				var count: int = int(base_counts[skill]) + (2 if links.has("volley") else 0) + (2 if bow and skill == "tornado" else 0)
				var cost: float = float(Data.SKILLS[skill].mana) * (1.3 if links.has("volley") else 1.0) * (1.2 if links.has("focus") else 1.0)
				_expect(_cast(), "Actual cast succeeds: %s / %s / bow=%s" % [skill, str(links), str(bow)])
				_expect(arena.projectiles.size() == count and arena.total_shots == count, "Real emission equals compiled count, including skill-specific bow scope")
				_near(arena.mana, 100.0 - cost, "Real cast charges multiplied mana once without display rounding")
				_near(arena.cooldowns[skill], Data.SKILLS[skill].cooldown, "Real cast starts unchanged skill cooldown once")
				var cast_ids: Dictionary = {}
				for shot: Dictionary in arena.projectiles:
					cast_ids[shot.cast_id] = true
					_expect(shot.skill_id == skill and shot.snapshot == arena.projectiles[0].snapshot, "Every emitted carrier owns the same skill-scoped frozen cast")
				_expect(cast_ids.size() == 1, "All initial carriers share one cast identity")
				if skill == "tornado":
					arena._update_projectiles(0.5)
					_expect(arena.projectiles.size() == count * 3 and arena.event_counts.get("split", 0) == count, "Every supported tornado parent still creates exactly three children")
					_expect(arena.event_counts.get("explosion", 0) == 0, "Splitting supported parents never creates a natural-end explosion")
	_finished = true


func _fill(count: int) -> void:
	var snapshot: Dictionary = arena.state.get_combat_snapshot()
	for index: int in range(count):
		arena.projectiles.append(arena.projectile_runtime.make_projectile(Vector2(500, 300), Vector2.RIGHT,
			{"speed": 1.0, "range": 1000.0, "lifetime": 10.0, "radius": 0.0},
			Damage.packet({"physical": 1.0}, ["hit", "attack", "projectile"], "basic"), snapshot,
			arena.projectile_runtime.new_cast(), Color.WHITE))


func _admission_state() -> Dictionary:
	return {"shots": arena.projectiles.duplicate(true), "total": arena.total_shots, "mana": arena.mana,
		"cooldowns": arena.cooldowns.duplicate(true), "next_cast": arena.projectile_runtime.next_cast_id,
		"next_projectile": arena.projectile_runtime.next_projectile_id, "events": arena.event_counts.duplicate(true),
		"damage": arena.total_damage, "kills": arena.kills, "rewards": arena.reward_kills,
		"cues": arena.visual_cues.cues.duplicate(true), "next_cue": arena.visual_cues.next_id,
		"particles": arena.particles.duplicate(true), "rng": arena.rng.state}


func _test_capacity() -> void:
	var specs: Dictionary = {"tornado": [7, 28.08], "bolt": [5, 10.92], "frost": [7, 24.96]}
	for skill: String in specs:
		var count: int = specs[skill][0]
		for free: int in [0, count - 1, count]:
			_prepare(skill, ["volley", "focus"], true)
			_fill(arena.MAX_PROJECTILES - free)
			var before: Dictionary = _admission_state()
			var accepted: bool = _cast()
			if free < count:
				_expect(not accepted and _admission_state() == before, "%s with %d free slots rejects without payment, cooldown, ID allocation, partial emission or events" % [skill, free])
			else:
				_expect(accepted and arena.projectiles.size() == arena.MAX_PROJECTILES and arena.total_shots == count, "Exact remaining capacity admits the whole supported volley: " + skill)
				_near(arena.mana, 100.0 - float(specs[skill][1]), "Exact-capacity cast charges the supported cost: " + skill)
				_expect(arena.projectiles.slice(0, int(before.shots.size())) == before.shots, "Successful boundary cast preserves every existing carrier")
	_finished = true


func _test_insufficient_mana() -> void:
	var costs: Dictionary = {"tornado": 28.08, "bolt": 10.92, "frost": 24.96}
	for skill: String in costs:
		for balance: float in [0.0, float(costs[skill]) - 0.001]:
			_prepare(skill, ["volley", "focus"])
			arena.mana = balance
			var before: Dictionary = _admission_state()
			_expect(not _cast() and _admission_state() == before, "Insufficient supported mana rejects without any combat mutation: " + skill)
		_prepare(skill, ["volley", "focus"])
		# Use the exact compiler float, rather than introducing an unrelated literal ULP.
		arena.mana = arena.state.get_skill_cast(skill).mana
		_expect(_cast(), "Exactly compiled mana admits the cast: " + skill)
		_near(arena.mana, 0.0, "Exact-cost cast leaves zero mana without negative residue: " + skill)
		var before: Dictionary = _admission_state()
		_expect(not _cast() and _admission_state() == before, "Cooldown rejection cannot replay the supported cast: " + skill)
	_finished = true


func _test_invalid_runtime_links() -> void:
	for skill: String in ["tornado", "bolt", "frost"]:
		for malformed: Variant in [["unknown"], ["focus", "focus"], ["volley", "focus", "volley"], "focus", [null]]:
			_prepare(skill, [])
			# Model transactions never create these; the executor must still fail closed.
			arena.state.skill_supports[skill] = malformed
			var before: Dictionary = _admission_state()
			_expect(not _cast() and _admission_state() == before, "Corrupt live support data cannot emit, charge, advance IDs/RNG or spawn cast cues: " + skill)
	_finished = true


func _test_concurrent_skills() -> void:
	_prepare("bolt", ["focus"])
	arena.state.set_skill_supports("frost", ["volley"])
	_expect(arena.state.slot_skill(0, "frost") and arena.state.skill_slots[1] == "bolt", "Two linked skills swap actual hotbar slots")
	var target: Dictionary = _target()
	_expect(_cast(0) and _cast(1), "Both swapped linked skills can be cast independently into one scene")
	_expect(arena.projectiles.size() == 10, "Concurrent frost volley and focused bolt emit seven plus three carriers")
	_near(arena.mana, 100.0 - 16.0 * 1.3 - 7.0 * 1.2, "Concurrent casts charge each skill's own linked cost")
	arena._update_projectiles(0.25)
	_expect(arena.damage_trace.size() == 2, "Center target receives one hit from each independent frozen cast")
	var hits: Dictionary = {}
	for record: Dictionary in arena.damage_trace:
		hits[record.skill_id] = record.total
	_near(float(hits.get("bolt", -1.0)), 18.0 * 1.6 * 1.25, "Swapped bolt retains its own focus without frost's penalty")
	_near(float(hits.get("frost", -1.0)), 18.0 * 0.85 * 0.8, "Swapped frost retains its own volley without bolt's bonus")
	_near(100000.0 - float(target.health), 18.0 * (1.6 * 1.25 + 0.85 * 0.8), "One target accounts for exactly the sum of independent linked hits")
	_finished = true


func _target(position: Vector2 = Vector2(600, 300)) -> Dictionary:
	var target: Dictionary = arena._spawn_monster("crawler", position, "ordinary", "normal", [])
	target.spawn = 0.0
	target.radius = 0.0
	target.health = 100000.0
	target.max_health = 100000.0
	target.shield = 0.0
	target.resistances = {}
	target.speed = 0.0
	return target


func _test_damage_scope() -> void:
	var coefficients: Dictionary = {"tornado": 1.0, "bolt": 1.6, "frost": 0.85}
	for skill: String in coefficients:
		for links: Array in [["volley"], ["focus"], ["volley", "focus"]]:
			_prepare(skill, links)
			var target: Dictionary = _target()
			_expect(_cast(), "Supported damage fixture casts actual skill: " + skill)
			arena._update_projectiles(0.25)
			var factor: float = (0.8 if links.has("volley") else 1.0) * (1.25 if links.has("focus") else 1.0)
			_expect(arena.damage_trace.size() == 1, "Narrow center target receives exactly one supported initial hit: " + skill)
			_near(100000.0 - float(target.health), 18.0 * float(coefficients[skill]) * factor, "Real hit uses multiplicative more/less factors: " + skill + str(links))
	# An independently linked skill cannot change another real skill or basic attack.
	for skill: String in ["bolt", "frost", "meteor", "nova", "chain", "basic"]:
		_prepare("tornado", ["focus"])
		var target: Dictionary = _target()
		if skill == "basic":
			arena.auto_fire = true
			arena.attack_timer = 0.0
			arena._update_auto_attack()
			arena._update_projectiles(0.25)
		else:
			arena.state.slot_skill(0, skill)
			_expect(_cast(), "Unlinked real skill remains usable: " + skill)
			if skill in ["bolt", "frost"]:
				arena._update_projectiles(0.25)
		var coefficient: float = {"bolt": 1.6, "frost": 0.85, "meteor": 4.3, "nova": 2.7, "chain": 2.2, "basic": 1.0}[skill]
		_near(100000.0 - float(target.health), 18.0 * coefficient, "Linked tornado support never leaks into real unlinked skill: " + skill)
	# Test the modifier scopes without relying on a UI label or a matched damage total alone.
	var state = Model.new()
	state.equipped.clear()
	var increases: Array = Combat.modifiers({"global_increased": 0.2, "projectile_increased": 0.5, "elemental_increased": 0.3})
	var arrow: Dictionary = Damage.packet({"physical": 100.0, "fire": 100.0}, ["hit", "projectile"], "tornado")
	var explosion: Dictionary = Damage.packet({"physical": 100.0, "fire": 100.0}, ["hit", "area", "secondary", "explosion"], "tornado")
	for links: Array in [[], ["volley"], ["focus"], ["volley", "focus"], ["focus", "volley"]]:
		state.set_skill_supports("tornado", links)
		var cast: Dictionary = state.get_skill_cast("tornado")
		var modifiers: Array = increases.duplicate(true)
		modifiers.append_array(cast.snapshot.modifiers)
		var factor: float = (0.8 if links.has("volley") else 1.0) * (1.25 if links.has("focus") else 1.0)
		_near(Damage.resolve(arrow, modifiers).total, 370.0 * factor, "Independent scope fixture follows 370 to 296 to 370, in either support order")
		_near(Damage.resolve(explosion, modifiers).total, 270.0, "Secondary explosion excludes both projectile support factors")
		for other: String in ["basic", "bolt", "frost"]:
			var unrelated: Dictionary = arrow.duplicate(true)
			unrelated.skill_id = other
			_near(Damage.resolve(unrelated, modifiers).total, 370.0, "Same projectile-hit tags are insufficient without the linked skill ID: " + other)
		var no_hit: Dictionary = arrow.duplicate(true)
		no_hit.tags = ["projectile"]
		_near(Damage.resolve(no_hit, modifiers).total, 370.0, "Linked projectile payload still requires the hit tag")
	_finished = true


func _install_weapon() -> String:
	var id: String = "gear_%06d" % arena.state.next_equipment_id
	var instance: Dictionary = {"id": id, "base_id": "cinder_reed", "rarity": "magic", "item_level": 1,
		"affixes": [{"id": "farweave", "tier": 1, "value": 7}, {"id": "coalglow", "tier": 1, "value": 8}]}
	_expect(Catalog.validate_instance(instance), "Frozen-flight source uses valid existing projectile and fire affixes")
	arena.state.equipment_instances[id] = instance
	arena.state.inventory.append(id)
	arena.state.next_equipment_id += 1
	arena.state._sync_backpack()
	_expect(arena.state.equip(id), "Rolled source enters the actual equipment/stat change path")
	return id


func _test_frozen_lineage() -> void:
	_prepare("tornado", ["focus"])
	var gear_id: String = _install_weapon()
	arena.state.equip("return_mantle")
	arena.state.equip("detonation_charm")
	var compiled: Dictionary = arena.state.get_skill_cast("tornado")
	var frozen: Dictionary = compiled.snapshot.duplicate(true)
	_expect(_cast(), "Frozen-lineage fixture emits real supported tornado parents")
	arena.state.remove_skill_support("tornado", "focus")
	arena.state.add_skill_support("tornado", "volley")
	for slot: String in Model.EQUIPMENT_SLOTS:
		arena.state.unequip(slot)
	_expect(arena.state.discard_equipment(gear_id), "Generated source is discarded while its original cast is still flying")
	_expect(arena.state.get_combat_snapshot().effects.is_empty() and arena.state.get_skill_supports("tornado") == ["volley"], "Live build now has a different support and no original effect grants")
	arena._update_projectiles(0.5)
	_expect(arena.projectiles.size() == 9 and arena.event_counts.get("split", 0) == 3, "Old three-parent cast creates nine children despite current volley assignment")
	var center: Dictionary = {}
	for child: Dictionary in arena.projectiles:
		_expect(child.snapshot == frozen and child.generation == 1 and child.recipe.child_count == 3, "Every child inherits detached old support, affix and effect snapshot")
		_near(child.damage, 21.0 * 0.7 * (0.6 * 1.27 + 0.4 * 1.65) * 1.25, "Child retains original focus and existing affix arithmetic")
		if absf(float(child.velocity.y)) < 0.001 and child.velocity.x > 0.0:
			center = child
	_expect(not center.is_empty(), "Fixture finds the actual center outward child")
	if center.is_empty():
		return
	var target: Dictionary = _target(Vector2(center.pos) + Vector2.RIGHT * 30.0)
	arena._update_projectiles(0.05)
	_near(target.health, 100000.0, "Target remains untouched before resistance changes in flight")
	target.resistances = {"physical": 0.25, "fire": 0.5}
	arena._update_projectiles(0.15)
	var expected_hit: float = 21.0 * 0.7 * (0.6 * 1.27 * 0.75 + 0.4 * 1.65 * 0.5) * 1.25
	_expect(arena.damage_trace.size() == 1, "Old supported child delivers one actual outbound hit")
	_near(100000.0 - float(target.health), expected_hit, "Frozen offensive numbers combine with current target mitigation at impact")
	arena._update_projectiles(0.4)
	_expect(arena.event_counts.get("return_started", 0) == 9, "All nine old children retain return after effect source removal")
	for child: Dictionary in arena.projectiles:
		_expect(child.snapshot == frozen and child.state == "returning", "Returning leg keeps exactly the old snapshot")
	arena._update_projectiles(0.6)
	var returned: int = 0
	for record: Dictionary in arena.damage_trace:
		if record.phase == "returning":
			returned += 1
			_near(record.total, expected_hit, "Actual returning hit retains old support after unlink and gear discard")
	_expect(returned == 1, "Center child may hit the same enemy exactly once on the return leg")
	# Place target at the center child's true expiry endpoint; its expiry cannot itself hit.
	target.pos = Vector2(center.pos) + Vector2(center.velocity) * (float(center.lifetime) - float(center.age))
	target.resistances.fire = 0.75
	arena.damage_trace.clear()
	arena._update_projectiles(1.0)
	_expect(arena.projectiles.is_empty() and arena.event_counts.get("explosion", 0) == 9, "Old children end naturally with one explosion each and no support-induced recursion")
	var blasts: int = 0
	for record: Dictionary in arena.damage_trace:
		if record.tags.has("explosion"):
			blasts += 1
			_near(record.total, 21.0 * 0.9 * 1.58 * 0.25, "Actual explosion retains old fire/global gear, reads live mitigation and excludes focus")
			_expect(not record.tags.has("projectile") and record.tags.has("secondary"), "Actual explosion preserves secondary delivery identity")
	_expect(blasts >= 1, "Expiry endpoint target receives at least the center child's actual explosion")
	var events: Dictionary = arena.event_counts.duplicate(true)
	arena._update_projectiles(3.0)
	_expect(arena.event_counts == events, "Finished supported lineage cannot replay returns, splits or explosions")
	arena.enemies.clear()
	arena.cooldowns.tornado = 0.0
	arena.mana = 100.0
	_expect(_cast() and arena.projectiles.size() == 5, "Next cast uses new volley count after the old lineage finishes")
	_near(arena.projectiles[0].damage, 18.0 * 0.8, "Next cast uses new volley penalty without discarded gear or old focus")
	_finished = true


func _test_cancelled_lineage() -> void:
	for reason: String in ["owner_death", "run_reset"]:
		_prepare("tornado", ["volley", "focus"], true)
		arena.state.equip("return_mantle")
		arena.state.equip("detonation_charm")
		_expect(_cast(), "Cancellation starts a real fully supported seven-parent cast")
		arena._update_projectiles(0.5)
		var old: Array = arena.projectiles.duplicate()
		var build: Dictionary = arena.state._snapshot()
		var target: Dictionary = _target(Vector2(500, 300))
		if reason == "owner_death":
			arena.invulnerable = 0.0
			arena.shield = 0.0
			arena.health = 1.0
			arena.hit_player(2.0)
		else:
			arena.restart_run()
		for child: Dictionary in old:
			_expect(not child.active and child.end_reason == reason, "Every frozen supported child terminates with the explicit cancellation reason")
		arena._update_projectiles(5.0)
		_expect(arena.projectiles.is_empty() and arena.event_counts.get("explosion", 0) == 0 and arena.event_counts.get("return_started", 0) == 0, "Cancellation cannot synthesize supported returns or explosions")
		_expect(arena.reward_kills == 0 and arena.kills == 0 and arena.state._snapshot() == build, "Cancellation awards no XP, jewels, equipment or kill progress")
		_near(target.health, 100000.0, "Cancelled lineage cannot damage a nearby enemy")
	_finished = true


func _test_bounded_parents() -> void:
	var runtime = Runtime.new()
	var snapshot: Dictionary = Combat.snapshot({"damage": 18.0, "projectile_count": 1000.0}, ["return_on_range", "explode_on_flight_end"])
	var compiled: Dictionary = Compiler.compile_skill("tornado", snapshot, ["volley", "focus"])
	_expect(compiled.ok and compiled.initial_count == 9, "Compiler clamps even large equipment-plus-support initial count to nine")
	var shots: Array[Dictionary] = []
	_expect(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, compiled.snapshot, 180, compiled.initial_count) == 9 and shots.size() == 9, "Runtime honors the bounded compiled parent request")
	var events: Array[Dictionary] = runtime.advance(shots, 0.5, [], Vector2.ZERO, 180)
	_expect(shots.size() == 27 and _event_count(events, "split") == 9 and _event_count(events, "spawned") == 27, "Maximum supported parent cast remains exactly nine times three children")
	events = runtime.advance(shots, 3.0, [], Vector2.ZERO, 180)
	_expect(shots.is_empty() and _event_count(events, "explosion") == 27 and _event_count(events, "split") == 0, "Maximum lineage terminates after one bounded child generation")
	shots.clear()
	_expect(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, compiled.snapshot, 180, 10000) == 9, "Runtime independently clamps an oversized requested count")
	# One admitted parent cannot emit even a partial child group when only two slots exist.
	runtime.cancel_all(shots)
	runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, compiled.snapshot, 2, 1)
	events = runtime.advance(shots, 0.5, [], Vector2.ZERO, 2)
	_expect(shots.is_empty() and _event_count(events, "spawn_rejected") == 1 and _event_count(events, "spawned") == 0, "Insufficient descendant capacity rejects the entire three-child group")
	_expect(_event_count(events, "explosion") == 0 and _event_count(events, "flight_ended") == 0, "Budget-cancelled supported parent is never a natural damaging end")
	_finished = true


func _event_count(events: Array[Dictionary], type: String) -> int:
	var count: int = 0
	for event: Dictionary in events:
		if event.type == type:
			count += 1
	return count
