extends SceneTree
## Independent deterministic contract tests for projectile rules and typed damage.
## Run with isolated XDG directories, as in tools/validate.sh.

const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_damage()
	_test_snapshot()
	_test_recipe_snapshot()
	_test_tornado_lineage()
	_test_return_and_expiry()
	_test_flight_end_precedence()
	_test_contacts()
	_test_time_partition()
	_test_cancellation()
	_test_capacity()
	print("Combat pipeline: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String, tolerance: float = 0.0001) -> void:
	_expect(absf(value - expected) <= tolerance, "%s (actual %.6f, expected %.6f)" % [label, value, expected])


func _events(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in events:
		if event.type == type:
			result.append(event)
	return result


func _effect_id() -> String:
	return "explode_on_flight_end"


func _snapshot(returning: bool = true, exploding: bool = true) -> Dictionary:
	var effects: Array = []
	if returning:
		effects.append("return_on_range")
	if exploding:
		effects.append(_effect_id())
	return Recipes.snapshot({"damage": 100.0}, effects)


func _shot(runtime: RefCounted, snapshot: Dictionary, overrides: Dictionary = {}, origin: Vector2 = Vector2.ZERO) -> Dictionary:
	var spec: Dictionary = {"speed": 100.0, "range": 100.0, "lifetime": 3.0,
		"radius": 0.0, "pierce": -1, "role": "child", "split": false}
	spec.merge(overrides, true)
	return runtime.make_projectile(origin, Vector2.RIGHT, spec,
		Recipes.tornado_packet(snapshot, "child"), snapshot, runtime.new_cast(), Color.WHITE)


func _target(id: int, x: float, y: float = 0.0, radius: float = 0.0) -> Dictionary:
	return {"id": id, "pos": Vector2(x, y), "radius": radius, "health": 10000.0, "spawn": 0.0}


func _test_damage() -> void:
	var stats: Dictionary = {"damage": 100.0, "global_increased": 0.2,
		"projectile_increased": 0.5, "elemental_increased": 0.3}
	var modifiers: Array[Dictionary] = Recipes.modifiers(stats)
	var arrow: Dictionary = Damage.packet({"physical": 100.0, "fire": 100.0}, ["hit", "projectile"], "tornado")
	var blast: Dictionary = Damage.packet({"physical": 100.0, "fire": 100.0}, ["hit", "area", "explosion"], "tornado")
	var result: Dictionary = Damage.resolve(arrow, modifiers)
	_near(result.total, 370.0, "All applicable increased modifiers add")
	_near(result.components.physical, 170.0, "Elemental increase excludes physical")
	_near(result.components.fire, 200.0, "Elemental increase applies to fire")
	_near(Damage.resolve(blast, modifiers).total, 270.0, "Projectile increase excludes explosion")
	modifiers.append({"id": "more_a", "mode": "more", "value": 0.1})
	modifiers.append({"id": "more_b", "mode": "more", "value": 0.2})
	_near(Damage.resolve(arrow, modifiers).total, 488.4, "Independent more factors multiply on arrow")
	_near(Damage.resolve(blast, modifiers).total, 356.4, "Independent more factors multiply on explosion")
	var typed: Dictionary = Damage.packet({"physical": 10.0, "fire": 10.0, "cold": 10.0, "lightning": 10.0, "chaos": 10.0}, [], "tornado")
	var elemental: Array[Dictionary] = Recipes.modifiers({"elemental_increased": 1.0})
	var all_types: Dictionary = Damage.resolve(typed, elemental)
	_near(all_types.total, 80.0, "Only three elemental components receive elemental increase")
	_near(all_types.components.chaos, 10.0, "Chaos is not elemental")
	_near(Damage.resolve(arrow, [], {"physical": 0.25, "fire": 0.5}).total, 125.0, "Defender mitigates each type separately")
	_near(Damage.resolve(arrow, [], {"physical": 0.5, "fire": 0.5}).total, 100.0, "Current defender data changes later resolution")
	var area_only: Array[Dictionary] = Recipes.modifiers({"area_increased": 1.0})
	_near(Damage.resolve(arrow, area_only).total, 200.0, "Area modifier excludes arrow")
	_near(Damage.resolve(blast, area_only).total, 400.0, "Area modifier includes explosion")
	var skill_only: Array = [{"id": "other_skill", "mode": "increased", "value": 2.0, "skills": ["frost"]}]
	_near(Damage.resolve(arrow, skill_only).total, 200.0, "Skill-filtered modifier does not leak")
	var snapshot: Dictionary = Recipes.snapshot(stats, [])
	var explosion: Dictionary = Recipes.tornado_packet(snapshot, "explosion")
	_expect(not explosion.tags.has("projectile") and explosion.tags.has("explosion"), "Explosion constructs its own delivery tags")
	_near(Damage.resolve(explosion, snapshot.modifiers).total, 135.0, "Explosion raw coefficient excludes resolved arrow scaling")
	_near(Damage.resolve(Recipes.tornado_packet(snapshot, "child"), snapshot.modifiers).total, 127.4, "Child raw coefficient preserves physical/fire mix")


func _test_snapshot() -> void:
	var stats: Dictionary = {"damage": 100.0, "global_increased": 0.2, "projectile_count": 2}
	var effects: Array = ["return_on_range", _effect_id()]
	var snapshot: Dictionary = Recipes.snapshot(stats, effects)
	stats.damage = 900.0
	stats.global_increased = 9.0
	effects.clear()
	_near(snapshot.base_damage, 100.0, "Snapshot keeps cast-time base damage")
	_expect(snapshot.effects.size() == 2 and snapshot.projectile_count == 2, "Snapshot keeps cast-time effect grants and count")
	var runtime = Runtime.new()
	var shot: Dictionary = _shot(runtime, snapshot)
	snapshot.base_damage = 999.0
	snapshot.modifiers[0].value = 99.0
	snapshot.effects.clear()
	_near(shot.snapshot.base_damage, 100.0, "Projectile owns detached nested snapshot")
	_near(shot.snapshot.modifiers[0].value, 0.2, "Nested modifiers do not alias caller data")
	_expect(shot.snapshot.effects.size() == 2, "Projectile effects do not alias caller array")


func _test_recipe_snapshot() -> void:
	var runtime = Runtime.new()
	var snapshot: Dictionary = _snapshot()
	# Distinct pre-cast values prove descendants use the snapshot, not catalog defaults.
	snapshot.tornado_recipe.child.speed = 123.0
	snapshot.tornado_recipe.child.range = 60.0
	snapshot.tornado_recipe.child.lifetime = 1.25
	snapshot.tornado_recipe.child.coefficient = 0.45
	snapshot.explosion_recipe.coefficient = 0.8
	snapshot.explosion_recipe.radius = 42.0
	var original: Dictionary = snapshot.duplicate(true)
	var shots: Array[Dictionary] = []
	_expect(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, snapshot, 100, 1) == 1, "Custom recipe is captured by a cast")
	snapshot.tornado_recipe.child_count = 1
	snapshot.tornado_recipe.child.speed = 999.0
	snapshot.tornado_recipe.child.range = 999.0
	snapshot.tornado_recipe.child.lifetime = 99.0
	snapshot.tornado_recipe.child.coefficient = 9.0
	snapshot.explosion_recipe.coefficient = 9.0
	snapshot.explosion_recipe.radius = 900.0
	var events: Array[Dictionary] = runtime.advance(shots, 0.4, [], Vector2.ZERO, 100)
	_expect(shots.size() == 3 and _events(events, "spawned").size() == 3, "Post-cast input mutation cannot change child count")
	for child: Dictionary in shots:
		_near(child.speed, 123.0, "Child preserves cast-time speed recipe")
		_near(child.range, 60.0, "Child preserves cast-time range recipe")
		_near(child.lifetime, 1.25, "Child preserves cast-time lifetime recipe")
		_near(child.damage, 45.0, "Child preserves cast-time raw damage coefficient")
		_expect(child.snapshot == original, "Descendant keeps deep-detached complete cast snapshot")
	events = runtime.advance(shots, 2.0, [], Vector2.ZERO, 100)
	var blasts: Array[Dictionary] = _events(events, "explosion")
	_expect(shots.is_empty() and blasts.size() == 3, "Frozen lifetime and effect recipe expire all three children")
	for blast: Dictionary in blasts:
		_near(blast.radius, 42.0, "Explosion preserves cast-time radius")
		_near(blast.payload.base.fire, 80.0, "Explosion preserves cast-time coefficient independently of arrow")
	var independent: Dictionary = _snapshot()
	_near(independent.tornado_recipe.child.speed, Recipes.TORNADO.child.speed, "Mutating one snapshot does not mutate catalog or new snapshots")
	_near(independent.explosion_recipe.radius, Recipes.TORNADO.explosion.radius, "Explosion recipe is detached from catalog")


func _test_tornado_lineage() -> void:
	for count: int in [1, 3, 9]:
		var runtime = Runtime.new()
		var shots: Array[Dictionary] = []
		var snapshot: Dictionary = _snapshot()
		_expect(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, snapshot, 100, count) == count, "Requested parent count %d" % count)
		var mothers: Array[Dictionary] = shots.duplicate()
		var events: Array[Dictionary] = runtime.advance(shots, 0.5, [], Vector2.ZERO, 100)
		_expect(_events(events, "split").size() == count, "Each of %d mothers splits exactly once" % count)
		_expect(shots.size() == count * 3, "Each mother produces exactly three children")
		_expect(_events(events, "explosion").is_empty(), "Split-consumed mothers do not explode")
		var ids: Dictionary = {}
		var per_parent: Dictionary = {}
		var lineage_valid: bool = true
		for mother: Dictionary in mothers:
			lineage_valid = lineage_valid and not mother.active and mother.end_reason == "split_consumed"
		for child: Dictionary in shots:
			ids[child.id] = true
			per_parent[child.parent_id] = int(per_parent.get(child.parent_id, 0)) + 1
			lineage_valid = lineage_valid and child.role == "child" and child.generation == 1 and child.root_id == child.parent_id
			lineage_valid = lineage_valid and child.cast_id == mothers[0].cast_id and child.snapshot == snapshot
			_near(child.age, 0.5 - 150.0 / 420.0, "Child advances only residual time after split")
			_near(child.lifetime, 1.7, "Child receives its own full lifetime")
		_expect(ids.size() == count * 3 and per_parent.size() == count and lineage_valid, "Unique IDs and correct parent/root/cast lineage")
		for value: int in per_parent.values():
			_expect(value == 3, "Exactly three children per parent ID")
		if shots.size() < 2:
			continue
		var first: Dictionary = shots[0]
		var second: Dictionary = shots[1]
		_near(Vector2(first.velocity).normalized().dot(Vector2(second.velocity).normalized()), -0.5, "Children separated radially by 120 degrees")
		first.hit_ledger["outbound:999"] = true
		_expect(not second.hit_ledger.has("outbound:999"), "Sibling hit ledgers are independent")


func _test_return_and_expiry() -> void:
	var runtime = Runtime.new()
	var shot: Dictionary = _shot(runtime, _snapshot())
	var shots: Array[Dictionary] = [shot]
	var start_events: Array[Dictionary] = runtime.advance(shots, 1.0, [], Vector2.ZERO, 100)
	_expect(_events(start_events, "return_started").size() == 1 and shot.state == "returning", "Range starts exactly one return")
	_near(shot.pos.x, 100.0, "Return starts at exact range point")
	_near(shot.age, 1.0, "Return does not reset age")
	_near(shot.life, 2.0, "Return preserves remaining lifetime")
	var fixed_velocity: Vector2 = shot.velocity
	var middle: Array[Dictionary] = runtime.advance(shots, 1.0, [], Vector2(0, 500), 100)
	_expect(shot.velocity == fixed_velocity, "Player movement after return does not cause homing")
	_near(shot.pos.x, 0.0, "Return reaches original center without stopping")
	_expect(shot.active and _events(middle, "return_started").is_empty(), "Center passage is nonterminal and does not retrigger return")
	var final_events: Array[Dictionary] = runtime.advance(shots, 1.0, [], Vector2(500, 500), 100)
	_near(shot.pos.x, -100.0, "Return travels past player until original lifetime")
	_expect(shots.is_empty() and shot.end_reason == "lifetime_expired", "Lifetime terminates returning projectile")
	_expect(_events(final_events, "explosion").size() == 1, "Expiry dispatches one explosion")
	_expect(_events(runtime.advance(shots, 10.0, [], Vector2.ZERO, 100), "explosion").is_empty(), "Expired projectile cannot explode again")
	var aimed: Dictionary = _shot(runtime, _snapshot())
	var aimed_shots: Array[Dictionary] = [aimed]
	runtime.advance(aimed_shots, 1.0, [], Vector2(25, 25), 100)
	_expect(Vector2(aimed.velocity).is_equal_approx(Vector2(-75, 25).normalized() * 100.0), "Return samples current center at transition")
	var coincident: Dictionary = _shot(runtime, _snapshot())
	var coincident_shots: Array[Dictionary] = [coincident]
	runtime.advance(coincident_shots, 1.0, [], Vector2(100, 0), 100)
	_expect(Vector2(coincident.velocity).is_equal_approx(Vector2(-100, 0)), "Coincident return center reverses current direction safely")
	var far: Dictionary = _shot(runtime, _snapshot(), {}, Vector2(5000, 5000))
	var far_shots: Array[Dictionary] = [far]
	var far_events: Array[Dictionary] = runtime.advance(far_shots, 3.0, [], Vector2(5000, 5000), 100)
	_expect(_events(far_events, "explosion").size() == 1, "Off-arena position does not cancel valid lifetime explosion")


func _test_flight_end_precedence() -> void:
	var runtime = Runtime.new()
	var no_return: Dictionary = _shot(runtime, _snapshot(false, true))
	var shots: Array[Dictionary] = [no_return]
	var events: Array[Dictionary] = runtime.advance(shots, 2.0, [], Vector2.ZERO, 100)
	_expect(no_return.end_reason == "range_consumed" and _events(events, "explosion").size() == 1, "Without return, natural range end explodes")
	var returning: Dictionary = _shot(runtime, _snapshot())
	shots = [returning]
	events = runtime.advance(shots, 1.5, [], Vector2.ZERO, 100)
	_expect(_events(events, "return_started").size() == 1 and _events(events, "explosion").is_empty(), "Return intercepts range end before explosion")
	var early: Dictionary = _shot(runtime, _snapshot(), {"lifetime": 0.5})
	shots = [early]
	events = runtime.advance(shots, 2.0, [], Vector2.ZERO, 100)
	_near(early.pos.x, 50.0, "Expiry clips motion before range")
	_expect(_events(events, "return_started").is_empty() and _events(events, "explosion").size() == 1, "Early expiry has no return and exactly one explosion")
	var instant: Dictionary = _shot(runtime, _snapshot(), {"lifetime": 0.0})
	shots = [instant]
	var origin_targets: Array[Dictionary] = [_target(1, 0.0)]
	events = runtime.advance(shots, 0.1, origin_targets, Vector2.ZERO, 100)
	_expect(_events(events, "hit").is_empty(), "Zero-lifetime projectile has no active interval for contact")
	_expect(shots.is_empty() and _events(events, "explosion").size() == 1, "Zero lifetime terminates once without moving")
	for split: bool in [false, true]:
		var tied: Dictionary = _shot(runtime, _snapshot(), {"lifetime": 1.0, "split": split, "role": "parent" if split else "child"})
		shots = [tied]
		var targets: Array[Dictionary] = [_target(1, 100.0)]
		events = runtime.advance(shots, 2.0, targets, Vector2.ZERO, 100)
		_expect(tied.end_reason == "lifetime_expired", "Lifetime wins exact range tie, split=%s" % split)
		_expect(_events(events, "split").is_empty() and _events(events, "return_started").is_empty(), "Exact lifetime tie prevents split and return")
		_expect(_events(events, "hit").is_empty(), "Contact exactly on lifetime deadline is excluded")
		_expect(_events(events, "explosion").size() == 1, "Exact tie emits exactly one natural-end explosion")
	var boundary: Dictionary = _shot(runtime, _snapshot())
	shots = [boundary]
	var boundary_targets: Array[Dictionary] = [_target(2, 100.0)]
	events = runtime.advance(shots, 1.0, boundary_targets, Vector2.ZERO, 100)
	var hits: Array[Dictionary] = _events(events, "hit")
	_expect(hits.size() == 1 and hits[0].phase == "outbound", "Earlier range endpoint contact belongs to outbound phase")
	var returns: Array[Dictionary] = _events(events, "return_started")
	_expect(not hits.is_empty() and not returns.is_empty() and events.find(hits[0]) < events.find(returns[0]), "Range endpoint hit precedes return transition")


func _test_contacts() -> void:
	var runtime = Runtime.new()
	var shot: Dictionary = _shot(runtime, _snapshot(), {"pierce": 0})
	var shots: Array[Dictionary] = [shot]
	var targets: Array[Dictionary] = [_target(9, 80.0), _target(2, 20.0), _target(5, 50.0)]
	var events: Array[Dictionary] = runtime.advance(shots, 1.0, targets, Vector2.ZERO, 100)
	var hits: Array[Dictionary] = _events(events, "hit")
	_expect(hits.size() == 1 and hits[0].target_id == 2, "Travel-order contact wins despite reverse enemy order")
	_near(shot.pos.x, 20.0, "Impact consumption clips projectile at first contact")
	_expect(shot.end_reason == "hit_consumed" and _events(events, "explosion").is_empty(), "Impact consumption never triggers natural-end explosion")
	shot = _shot(runtime, _snapshot(), {"range": 1000.0, "lifetime": 0.5})
	shots = [shot]
	targets = [_target(1, 49.0), _target(2, 50.0), _target(3, 51.0)]
	events = runtime.advance(shots, 2.0, targets, Vector2.ZERO, 100)
	hits = _events(events, "hit")
	_expect(hits.size() == 1 and hits[0].target_id == 1, "No contact at or after expiry endpoint")
	shot = _shot(runtime, _snapshot())
	shots = [shot]
	targets = [_target(1, 50.0, 0.0, 5.0)]
	events = runtime.advance(shots, 3.0, targets, Vector2.ZERO, 100)
	hits = _events(events, "hit")
	_expect(hits.size() == 2 and hits[0].phase == "outbound" and hits[1].phase == "returning", "One target can be hit once on each leg")
	shot = _shot(runtime, _snapshot(), {"range": 1000.0})
	shots = [shot]
	targets = [_target(7, 20.0), _target(3, 20.0)]
	events = runtime.advance(shots, 0.5, targets, Vector2.ZERO, 100)
	hits = _events(events, "hit")
	_expect(hits.size() == 2 and hits[0].target_id == 3 and hits[1].target_id == 7, "Exact contact ties use stable target ID")
	var left: Dictionary = _shot(runtime, _snapshot())
	var right: Dictionary = _shot(runtime, _snapshot())
	shots = [left, right]
	targets = [_target(1, 50.0)]
	events = runtime.advance(shots, 3.0, targets, Vector2.ZERO, 100)
	_expect(_events(events, "hit").size() == 4, "Overlapping projectiles independently hit both legs")
	_expect(_events(events, "explosion").size() == 2, "Overlapping projectiles independently explode")
	var blasts: Array[Dictionary] = _events(events, "explosion")
	_expect(blasts.size() == 2 and blasts[0].effect_id != blasts[1].effect_id, "Independent explosions have unique effect identities")
	var dead: Dictionary = _target(1, 20.0)
	dead.health = 0.0
	var spawning: Dictionary = _target(2, 30.0)
	spawning.spawn = 1.0
	shot = _shot(runtime, _snapshot())
	shots = [shot]
	targets = [dead, spawning]
	_expect(_events(runtime.advance(shots, 0.5, targets, Vector2.ZERO, 100), "hit").is_empty(), "Dead and spawning targets are excluded")
	var late: Dictionary = _shot(runtime, _snapshot(), {}, Vector2(-50, 0))
	var early: Dictionary = _shot(runtime, _snapshot())
	shots = [late, early]
	targets = [_target(1, 20.0)]
	hits = _events(runtime.advance(shots, 0.8, targets, Vector2.ZERO, 100), "hit")
	_expect(hits.size() == 2 and hits[0].projectile_id == early.id and hits[1].projectile_id == late.id, "Cross-projectile events sort by actual impact time")


func _simulate(step: float, tornado: bool) -> Dictionary:
	var runtime = Runtime.new()
	var shots: Array[Dictionary] = []
	if tornado:
		runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, _snapshot(), 100, 2)
	else:
		shots.append(_shot(runtime, _snapshot()))
	var time: float = 0.0
	var all_events: Array[Dictionary] = []
	var targets: Array[Dictionary] = [_target(1, 50.0, 0.0, 5.0), _target(2, -50.0, 0.0, 5.0)]
	while time < 3.4 - 0.000001:
		var delta: float = minf(step, 3.4 - time)
		var events: Array[Dictionary] = runtime.advance(shots, delta, targets, Vector2.ZERO, 100)
		for event: Dictionary in events:
			event.time = float(event.time) + time
			all_events.append(event)
		time += delta
	return {"events": all_events, "shots": shots}


func _test_time_partition() -> void:
	for tornado: bool in [false, true]:
		var large: Dictionary = _simulate(3.4, tornado)
		for step: float in [0.17, 0.02, 0.007]:
			var small: Dictionary = _simulate(step, tornado)
			for type: String in ["split", "spawned", "return_started", "hit", "explosion", "terminated"]:
				var a: Array[Dictionary] = _events(large.events, type)
				var b: Array[Dictionary] = _events(small.events, type)
				_expect(a.size() == b.size(), "%s count invariant to timestep %.3f, tornado=%s" % [type, step, tornado])
				var ordered: bool = true
				for index: int in range(mini(a.size(), b.size())):
					ordered = ordered and a[index].projectile_id == b[index].projectile_id
					ordered = ordered and absf(float(a[index].time) - float(b[index].time)) < 0.0001
					ordered = ordered and Vector2(a[index].pos).distance_to(Vector2(b[index].pos)) < 0.001
					if type == "hit":
						ordered = ordered and a[index].target_id == b[index].target_id and a[index].phase == b[index].phase
				_expect(ordered, "%s IDs, timestamps, positions invariant to timestep %.3f, tornado=%s" % [type, step, tornado])
			_expect(large.shots.is_empty() and small.shots.is_empty(), "All simulated shots end by bounded lifetime")


func _test_cancellation() -> void:
	for reason: String in ["run_reset", "owner_death", "safety_cancelled"]:
		var runtime = Runtime.new()
		var shots: Array[Dictionary] = [_shot(runtime, _snapshot()), _shot(runtime, _snapshot())]
		var events: Array[Dictionary] = runtime.cancel_all(shots, reason)
		_expect(shots.is_empty() and _events(events, "terminated").size() == 2, "Cancellation removes every projectile: " + reason)
		_expect(_events(events, "explosion").is_empty() and _events(events, "split").is_empty(), "Cancellation suppresses gameplay effects: " + reason)
		_expect(runtime.cancel_all(shots, reason).is_empty(), "Repeated cancellation is idempotent")
	var runtime = Runtime.new()
	var shot: Dictionary = _shot(runtime, _snapshot())
	var shots: Array[Dictionary] = [shot]
	for delta: float in [0.0, -1.0, INF, NAN]:
		_expect(runtime.advance(shots, delta, [], Vector2.ZERO, 100).is_empty(), "Invalid or empty time step emits nothing")
		_near(shot.age, 0.0, "Invalid time step does not advance state")


func _test_capacity() -> void:
	var runtime = Runtime.new()
	var shots: Array[Dictionary] = []
	_expect(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, _snapshot(), 2, 3) == 0 and shots.is_empty(), "Over-budget parent volley is rejected atomically")
	_expect(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, _snapshot(), 3, 3) == 3, "Exact-capacity parent volley is admitted")
	var rejected: Dictionary = _shot(runtime, _snapshot(), {"split": true, "role": "parent", "range": 50.0})
	shots = [rejected]
	var events: Array[Dictionary] = runtime.advance(shots, 0.6, [], Vector2.ZERO, 2)
	_expect(_events(events, "spawned").is_empty() and _events(events, "spawn_rejected").size() == 1, "Three-child split is rejected atomically when only two fit")
	_expect(_events(events, "explosion").is_empty() and not rejected.active, "Rejected split cancels without explosion")
	var too_deep: Dictionary = _shot(runtime, _snapshot(), {"split": true, "role": "parent", "range": 50.0})
	too_deep.generation = 1
	shots = [too_deep]
	events = runtime.advance(shots, 0.6, [], Vector2.ZERO, 100)
	_expect(_events(events, "spawned").is_empty() and _events(events, "spawn_rejected").size() == 1, "Generation limit prevents recursive splitting")
	_expect(_events(events, "explosion").is_empty() and not too_deep.active, "Generation-limit cancellation has no explosion")
	for mother_first: bool in [true, false]:
		runtime = Runtime.new()
		var mother: Dictionary = _shot(runtime, _snapshot(), {"split": true, "role": "parent", "range": 50.0})
		var expires_first: Dictionary = _shot(runtime, _snapshot(false, false), {"range": 1000.0, "lifetime": 0.1})
		shots.assign([mother, expires_first] if mother_first else [expires_first, mother])
		events = runtime.advance(shots, 0.6, [], Vector2.ZERO, 3)
		_expect(_events(events, "spawned").size() == 3 and _events(events, "spawn_rejected").is_empty(), "Earlier expiry frees capacity independent of array order, mother_first=%s" % mother_first)
	for expires_first_in_array: bool in [true, false]:
		runtime = Runtime.new()
		var mother: Dictionary = _shot(runtime, _snapshot(), {"split": true, "role": "parent", "range": 10.0})
		var expires_later: Dictionary = _shot(runtime, _snapshot(false, false), {"range": 1000.0, "lifetime": 0.5})
		shots.assign([expires_later, mother] if expires_first_in_array else [mother, expires_later])
		events = runtime.advance(shots, 0.6, [], Vector2.ZERO, 3)
		_expect(_events(events, "spawned").is_empty() and _events(events, "spawn_rejected").size() == 1, "Future expiry cannot free capacity early, expires_first_in_array=%s" % expires_first_in_array)
