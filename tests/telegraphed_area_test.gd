extends SceneTree

const Runtime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Profiles = preload("res://scripts/monsters/telegraph_profiles.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_profiles()
	_test_timing()
	_test_event_order()
	_test_cancellation_and_birth()
	_test_invalid_inputs()
	_test_copies_and_rng()
	_test_shared_damage_path()
	_test_capacity_and_soak()
	print("Telegraphed area: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.0000001, label)


func _enemy(id: int = 1) -> Dictionary:
	return {"id": id, "health": 100.0, "shield": 10.0, "spawn": 0.0,
		"damage": 20.0, "contact_weights": {"physical": 0.5, "fire": 0.5},
		"pos": Vector2.ZERO, "extra": {"untouched": [1, 2, 3]}}


func _test_profiles() -> void:
	var info: Dictionary = Profiles.metadata()
	_expect(info.ok and info.origin == "original" and info.source_refs.is_empty(), "Original metadata has no invented external source")
	_expect(info.status == "standalone_not_integrated" and not info.automatic_repeat, "Metadata states standalone scope and explicit restart")
	_expect(info.profile == {"windup_seconds": 0.7, "recovery_seconds": 1.2, "radius": 90.0, "damage_multiplier": 1.4}, "Default timing, radius and multiplier match the requested contract")
	_expect(info.max_active == Runtime.MAX_ACTIVE and info.max_sources_per_advance == 100, "Metadata and runtime share capacity authority")
	var overrides: Dictionary = {"radius": 123.0, "damage_multiplier": 2.0, "windup_seconds": 0.5, "recovery_seconds": 0.9}
	_expect(Profiles.metadata(overrides).profile == Profiles.resolve(overrides).profile, "Configured metadata and execution share profile resolution")
	info.defaults.radius = 1.0
	info.limits.radius.maximum = 1.0
	info.profile.radius = 1.0
	info.states.clear()
	_expect(Profiles.metadata().defaults.radius == 90.0 and Profiles.metadata().limits.radius.maximum == 4096.0, "Metadata nested values are detached")
	_expect(Profiles.metadata().states == ["windup", "recovery"], "Metadata arrays are detached")
	for invalid: Variant in [null, [], true, "profile", {"unknown": 1}, {1: 1}]:
		_expect(not Profiles.resolve(invalid).ok and not Profiles.metadata(invalid).ok, "Malformed profile is rejected")
	for key: String in Profiles.DEFAULTS:
		for invalid: Variant in [null, {}, [], true, "1", NAN, INF, -INF, -1.0]:
			_expect(not Profiles.resolve({key: invalid}).ok, "Invalid profile scalar rejects: " + key)
		_expect(not Profiles.resolve({key: float(Profiles.LIMITS[key].maximum) + 1.0}).ok, "Profile upper bound rejects: " + key)
		for edge: String in ["minimum", "maximum"]:
			_expect(Profiles.resolve({key: Profiles.LIMITS[key][edge]}).ok, "Profile accepts documented bound: " + key + "/" + edge)
	_expect(not Profiles.resolve({"windup_seconds": 0.0}).ok and not Profiles.resolve({"recovery_seconds": 0.0}).ok, "Zero-duration loops cannot be authored")


func _test_timing() -> void:
	var enemy: Dictionary = _enemy()
	var runtime = Runtime.new()
	_expect(runtime.start(enemy, Vector2(200, 100)).ok, "Eligible source begins windup")
	_expect(runtime.advance(0.69, [enemy]).is_empty(), "No event before windup deadline")
	_expect(runtime.state_for(1).phase == "windup", "Windup remains visible before deadline")
	var events: Array[Dictionary] = runtime.advance(0.01, [enemy])
	_expect(events.size() == 1, "Deadline emits exactly one event")
	if events.size() != 1:
		return
	var reference: Dictionary = events[0]
	_expect(reference.center == Vector2(200, 100) and reference.radius == 90.0, "Event locks the original circle")
	_expect(reference.type == "circle_attack" and reference.shape == "circle", "Event has explicit attack and shape semantics")
	_expect(reference.packet.base == {"physical": 14.0, "fire": 14.0}, "Each contact component is scaled once by 1.4")
	_expect(reference.packet.tags == ["attack", "area", "hit"], "Packet has its own delivery tags")
	_expect(runtime.state_for(1).phase == "recovery", "Attack enters recovery after emission")
	_expect(not runtime.start(enemy, Vector2.ZERO).ok, "Recovery prevents re-admission")
	_expect(runtime.advance(1.199, [enemy]).is_empty() and runtime.active_count() == 1, "Recovery lasts its full interval without repeated events")
	_expect(runtime.advance(0.001, [enemy]).is_empty() and runtime.active_count() == 0, "Recovery finishes exactly after 1.2 seconds")
	_expect(runtime.advance(100.0, [enemy]).is_empty(), "Idle source never auto-restarts")
	var partitions: Array = [
		[1.9], [0.7, 1.2], [0.2, 0.3, 0.2, 0.6, 0.6],
		[0.69999, 0.00001, 1.2], [0.75, 1.15], [1000.0], [1.0e300],
	]
	var small_steps: Array = []
	for index: int in range(190):
		small_steps.append(0.01)
	partitions.append(small_steps)
	for steps: Array in partitions:
		var candidate = Runtime.new()
		candidate.start(enemy, Vector2(200, 100))
		var emitted: Array[Dictionary] = []
		for delta: float in steps:
			emitted.append_array(candidate.advance(delta, [enemy]))
		_expect(emitted == [reference], "Delta partitions and huge steps produce the identical single attack")
		_expect(candidate.active_count() == 0, "Delta remainder completes recovery without retained state")
		_expect(candidate.advance(5.0, [enemy]).is_empty(), "Completed attack never replays")
	var carried = Runtime.new()
	carried.start(enemy, Vector2.ZERO)
	_expect(carried.advance(0.8, [enemy]).size() == 1, "Crossing step emits once")
	_near(carried.state_for(1).elapsed, 0.8, "Crossing step retains 0.1 seconds of recovery")
	carried.advance(1.1, [enemy])
	_expect(carried.active_count() == 0, "Recovery does not lose the crossing remainder")


func _test_event_order() -> void:
	var a: Dictionary = _enemy(9)
	var b: Dictionary = _enemy(2)
	for split: bool in [false, true]:
		var runtime = Runtime.new()
		runtime.start(a, Vector2.ZERO, {"windup_seconds": 0.8})
		runtime.start(b, Vector2.ZERO, {"windup_seconds": 0.2})
		var events: Array[Dictionary] = []
		if split:
			events.append_array(runtime.advance(0.5, [b, a]))
			events.append_array(runtime.advance(1.5, [a, b]))
		else:
			events = runtime.advance(2.0, [a, b])
		_expect(events.size() == 2, "Mixed deadlines emit two attacks")
		if events.size() == 2:
			_expect(events[0].source_id == 2 and events[1].source_id == 9, "Event order follows deadline, independent of source-array order")
	var tied = Runtime.new()
	tied.start(a, Vector2.ZERO)
	tied.start(b, Vector2.ZERO)
	var events: Array[Dictionary] = tied.advance(0.7, [a, b])
	_expect(events.size() == 2 and events[0].source_id == 2 and events[1].source_id == 9, "Equal deadlines use ascending source identity")


func _test_cancellation_and_birth() -> void:
	for delta: float in [0.0, -1.0, NAN, INF, 0.7, 1000.0]:
		for cause: String in ["dead", "missing", "birth", "processed"]:
			var enemy: Dictionary = _enemy()
			var runtime = Runtime.new()
			runtime.start(enemy, Vector2.ZERO)
			runtime.advance(0.5, [enemy])
			var live: Array = [enemy]
			match cause:
				"dead": enemy.health = 0.0
				"missing": live.clear()
				"birth": enemy.spawn = 0.1
				"processed": enemy.death_processed = true
			_expect(runtime.advance(delta, live).is_empty() and runtime.active_count() == 0, "Cancellation precedes timing: " + cause)
	var enemy: Dictionary = Monsters.make_enemy(1, "ember_guard", 3, Vector2.ZERO)
	var runtime = Runtime.new()
	_expect(enemy.spawn > 0.0 and not runtime.start(enemy, Vector2.ZERO).ok, "Real catalog birth protection rejects attack admission")
	_expect(runtime.advance(100.0, [enemy]).is_empty() and enemy.spawn > 0.0, "Runtime never consumes caller birth protection")
	enemy.spawn = 0.0
	var first: Dictionary = runtime.start(enemy, Vector2.ZERO)
	_expect(first.ok, "Source can start after caller ends birth protection")
	runtime.reset()
	_expect(runtime.advance(10.0, [enemy]).is_empty(), "Reset cancels unfinished attack")
	var second: Dictionary = runtime.start(enemy, Vector2.ZERO)
	_expect(second.ok and second.attack.attack_id > first.attack.attack_id, "Attack identity is not reused across reset")
	_expect(runtime.cancel(1) and not runtime.cancel(1), "Explicit cancellation is idempotent")
	_expect(runtime.advance(10.0, [enemy]).is_empty(), "Explicit cancellation never emits a terminal hit")
	runtime.start(enemy, Vector2.ZERO)
	runtime.advance(0.7, [enemy])
	enemy.health = 0.0
	_expect(runtime.advance(0.0, [enemy]).is_empty() and runtime.active_count() == 0, "Death also frees recovery state")


func _test_invalid_inputs() -> void:
	var runtime = Runtime.new()
	for invalid: Variant in [null, [], true, 2, {}]:
		_expect(not runtime.start(invalid, Vector2.ZERO).ok, "Invalid source object rejects")
	for field: String in ["id", "health", "spawn", "damage"]:
		for invalid: Variant in [null, {}, [], true, "1", NAN, INF, -INF, -1.0]:
			var source: Dictionary = _enemy()
			source[field] = invalid
			_expect(not runtime.start(source, Vector2.ZERO).ok and runtime.active_count() == 0, "Invalid source field rejects atomically: " + field)
	for invalid: Variant in [null, [], {"fire": -1.0}, {"fire": NAN}, {"fire": INF}, {"fire": true}, {"fire": "1"}, {"other": 1.0}, {1: 1.0}, {}, {"fire": 0.5}]:
		var enemy: Dictionary = _enemy()
		enemy.contact_weights = invalid
		_expect(not runtime.start(enemy, Vector2.ZERO).ok, "Invalid component weights reject before catalog access")
	var overflowing: Dictionary = _enemy()
	overflowing.damage = 1.0e308
	_expect(not runtime.start(overflowing, Vector2.ZERO, {"damage_multiplier": 100.0}).ok, "Scaled overflow rejects")
	_expect(not runtime.start(_enemy(), Vector2(INF, 0)).ok and not runtime.start(_enemy(), Vector2(0, NAN)).ok, "Nonfinite target center rejects")
	_expect(not runtime.start(_enemy(), Vector2.ZERO, {"radius": -1}).ok, "Invalid profile does not admit an attack")
	var enemy: Dictionary = _enemy()
	runtime.start(enemy, Vector2.ZERO)
	for invalid: float in [0.0, -1.0, NAN, INF, -INF]:
		var before: Dictionary = runtime.state_for(1)
		_expect(runtime.advance(invalid, [enemy]).is_empty() and runtime.state_for(1) == before, "Invalid delta does not advance a living source")
	var too_many: Array = []
	for index: int in range(101):
		too_many.append(_enemy(index + 1))
	for invalid: Variant in [null, {}, true, [null], [{}], [enemy, enemy], too_many]:
		runtime.reset()
		runtime.start(enemy, Vector2.ZERO)
		_expect(runtime.advance(10.0, invalid).is_empty() and runtime.active_count() == 0, "Invalid or oversized source universe fails closed")
	for field: String in ["health", "spawn", "death_processed"]:
		runtime.start(enemy, Vector2.ZERO)
		var invalid: Dictionary = enemy.duplicate(true)
		invalid[field] = "invalid"
		_expect(runtime.advance(10.0, [invalid]).is_empty() and runtime.active_count() == 0, "Malformed liveness cancels source: " + field)


func _test_copies_and_rng() -> void:
	var enemy: Dictionary = _enemy()
	var original: Dictionary = enemy.duplicate(true)
	var overrides: Dictionary = {"radius": 123.0, "damage_multiplier": 2.0}
	var overrides_before: Dictionary = overrides.duplicate(true)
	var sources: Array = [enemy]
	var runtime = Runtime.new()
	seed(123456)
	var expected_random: int = randi()
	seed(123456)
	var started: Dictionary = runtime.start(enemy, Vector2(20, 30), overrides)
	started.attack.profile.radius = 1.0
	started.attack.packet.base.fire = 999.0
	_expect(runtime.state_for(1).profile.radius == 123.0, "Start result is a copied snapshot")
	var events: Array[Dictionary] = runtime.advance(0.7, sources)
	_expect(randi() == expected_random, "Start and advance consume no global RNG")
	_expect(enemy == original and sources == [original] and overrides == overrides_before, "Start and advance preserve all caller inputs")
	if events.size() != 1:
		_expect(false, "Copy test receives one event")
		return
	events[0].packet.base.fire = 999.0
	events[0].packet.tags.clear()
	events[0].profile.radius = 1.0
	var state: Dictionary = runtime.state_for(1)
	_expect(state.packet.base.fire == 20.0 and state.packet.tags == ["attack", "area", "hit"] and state.profile.radius == 123.0, "Event nested data cannot mutate retained recovery state")
	state.packet.base.physical = 999.0
	_expect(runtime.state_for(1).packet.base.physical == 20.0, "State accessor is detached")
	runtime.reset()
	runtime.start(enemy, Vector2(20, 30), overrides)
	overrides.radius = 1.0
	overrides.damage_multiplier = 0.0
	enemy.damage = 1000.0
	enemy.contact_weights.fire = 0.0
	enemy.contact_weights.physical = 1.0
	enemy.pos = Vector2(999, 999)
	var frozen: Array[Dictionary] = runtime.advance(0.7, [enemy])
	_expect(frozen.size() == 1, "Source stat changes do not cancel a living attack")
	if frozen.size() == 1:
		_expect(frozen[0].center == Vector2(20, 30) and frozen[0].radius == 123.0, "Center and radius are frozen at start")
		_expect(frozen[0].packet.base == {"physical": 20.0, "fire": 20.0}, "Contact components and multiplier are frozen at start")


func _test_shared_damage_path() -> void:
	var enemy: Dictionary = _enemy()
	var runtime = Runtime.new()
	runtime.start(enemy, Vector2.ZERO)
	var events: Array[Dictionary] = runtime.advance(0.7, [enemy])
	if events.size() != 1:
		_expect(false, "Damage adapter receives one event")
		return
	var hit: Dictionary = Defense.incoming_hit(events[0].packet.base, {"fire_resistance": 0.25}, 10.0, 100.0, "player")
	_expect(hit.ok, "Event enters the existing shared defense path")
	_near(hit.damage_total, 24.5, "Only fire is reduced: 14 physical + 10.5 fire")
	_near(hit.remaining_shield, 0.0, "Existing defense settles shield first")
	_near(hit.remaining_health, 85.5, "Existing defense settles remaining health loss")
	var resolved: Dictionary = Damage.resolve(events[0].packet, [], {"fire": 0.25})
	var settled: Dictionary = Defense.settle_resolved(resolved, 10.0, 100.0)
	_expect(settled.ok and settled.remaining_health == hit.remaining_health, "Explicit resolver/settlement path agrees without double mitigation")
	_expect(enemy.health == 100.0 and enemy.shield == 10.0, "Runtime and defense preview never mutate source resources")
	for template: String in ["crawler", "brute", "ember_guard"]:
		var actual: Dictionary = Monsters.make_enemy(2, template, 3, Vector2.ZERO)
		actual.spawn = 0.0
		runtime.reset()
		_expect(runtime.start(actual, Vector2.ZERO).ok, "Real catalog source accepted: " + template)
		var emitted: Array[Dictionary] = runtime.advance(0.7, [actual])
		var contact: Dictionary = Monsters.contact_components(actual)
		_expect(emitted.size() == 1, "Real catalog source emits once: " + template)
		if emitted.size() == 1:
			for type: String in contact:
				_near(emitted[0].packet.base[type], float(contact[type]) * 1.4, "Catalog and runtime share contact-base authority: " + template + "/" + type)


func _test_capacity_and_soak() -> void:
	var sources: Array[Dictionary] = []
	for index: int in range(100):
		sources.append(_enemy(index + 1))
	var original: Array[Dictionary] = sources.duplicate(true)
	var runtime = Runtime.new()
	var completed: int = 0
	for cycle: int in range(100):
		var all_started: bool = true
		for enemy: Dictionary in sources:
			all_started = runtime.start(enemy, Vector2(enemy.id, cycle)).ok and all_started
		_expect(all_started and runtime.active_count() == 100, "One hundred concurrent attacks are admitted")
		_expect(not runtime.start(_enemy(101), Vector2.ZERO).ok and runtime.active_count() == 100, "Capacity pressure rejects without eviction")
		var events: Array[Dictionary] = runtime.advance(0.7, sources)
		_expect(events.size() == 100 and runtime.active_count() == 100, "One hundred events retain only recovery states")
		var seen: Dictionary = {}
		for event: Dictionary in events:
			seen[event.source_id] = true
		_expect(seen.size() == 100, "Every active source emits once")
		completed += events.size()
		_expect(runtime.advance(1.2, sources).is_empty() and runtime.active_count() == 0, "All recovery states are reclaimed after every cycle")
	_expect(completed == 10000 and sources == original, "Ten thousand attacks retain bounded state and leave inputs unchanged")
	var independent: Array = []
	for index: int in range(100):
		var instance = Runtime.new()
		instance.start(sources[index], Vector2.ZERO)
		independent.append(instance)
	var count: int = 0
	for index: int in range(100):
		count += independent[index].advance(1000.0, [sources[index]]).size()
		_expect(independent[index].active_count() == 0, "Independent runtime instance reclaims its attack")
	_expect(count == 100, "One hundred runtime instances do not share mutable state")
