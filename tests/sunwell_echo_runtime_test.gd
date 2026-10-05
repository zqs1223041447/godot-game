extends SceneTree
## Pure scheduler contract only. Main damage settlement and rendering have separate QA.
const Runtime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Bosses = preload("res://scripts/monsters/map_boss_profiles.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Factory = preload("res://scripts/monsters/monster_runtime.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Admission = preload("res://scripts/world/map_admission.gd")
const Legacy = preload("res://docs/qa/v048-echo/capture_legacy.gd")
const CENTER := Vector2(345.25, 456.5)
const EPSILON := 0.000000001
var checks := 0
var failures := 0


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(is_finite(value) and absf(value - expected) < EPSILON,
		"%s: %.12f expected %.12f" % [label, value, expected])


func _enemy(modifiers: Array = []) -> Dictionary:
	var map: Dictionary = Maps.compile("sunwell_terrace", modifiers, []).profile
	var admitted: Dictionary = Admission.create_root(Factory.new(), map, "rift_warden", map.wave,
		Vector2(111, 222), "map_boss", "", [], true)
	assert(admitted.ok)
	var enemy: Dictionary = admitted.enemy
	enemy.spawn = 0.0
	return enemy


func _start(runtime: RefCounted, enemy: Dictionary, center: Vector2 = CENTER) -> Dictionary:
	var policy: Dictionary = Monsters.telegraph_policy(enemy)
	return runtime.start(enemy, center, policy.profile, policy.visual_pattern)


func _initialize() -> void:
	if OS.get_name() != "Linux" or not OS.get_data_dir().begins_with("/tmp/godot-m1-v048-echo"):
		push_error("Run with isolated Linux XDG storage under /tmp/godot-m1-v048-echo")
		quit(2)
		return
	_test_authority_and_speed()
	_test_exact_phases()
	_test_step_equivalence_and_bounds()
	_test_invalid_inputs()
	_test_cancellation_and_restart()
	_test_copies()
	_test_frozen_legacy()
	print("Sunwell echo runtime: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_authority_and_speed() -> void:
	var definition: Dictionary = Bosses.definition("sunwell_echo")
	_expect(definition.map_id == "sunwell_terrace" and definition.target_rule == "player_at_start", "Map authority freezes the player point")
	_expect(definition.profile == {"radius": 85.0, "windup_seconds": 0.8, "recovery_seconds": 1.9, "damage_multiplier": 0.65}, "Exact reviewed Echo budget")
	_expect(definition.pulse_count == 2 and definition.pulse_interval == 0.8, "Two complete warnings separated by .8 seconds")
	_expect(Bosses.profile_reason(Maps.compile("sunwell_terrace", [], []).profile).is_empty(), "Actual map profile admits Echo")
	for modifiers: Array in [[], ["enemy_damage_115", "enemy_attack_speed_110"]]:
		var enemy := _enemy(modifiers)
		var policy: Dictionary = Monsters.telegraph_policy(enemy)
		_expect(policy.visual_pattern == "sunwell_echo" and policy.target_rule == "player_at_start" and policy.replaces_contact and policy.hold_pursuit_during_action, "Canonical admission reaches the shared telegraph policy")
		_near(policy.profile.recovery_seconds, 1.9 * Monsters.BASE_ATTACK_SPEED / enemy.attack_speed, "Existing attack-speed recovery consumer")
		var admitted_speed: float = enemy.attack_speed
		for speed: float in [admitted_speed, Monsters.BASE_ATTACK_SPEED * 0.5, Monsters.BASE_ATTACK_SPEED, Monsters.BASE_ATTACK_SPEED * 2.0]:
			enemy.attack_speed = speed
			policy = Monsters.telegraph_policy(enemy)
			_near(policy.profile.windup_seconds, 0.8, "Attack speed keeps a complete first and second warning")
			_near(policy.profile.recovery_seconds, 1.9 * Monsters.BASE_ATTACK_SPEED / speed, "Only recovery scales with attack speed")
			var runtime := Runtime.new()
			_expect(_start(runtime, enemy).ok, "Scaled recovery remains legal")
			_expect(runtime.advance(0.799, [enemy]).is_empty(), "No first pulse before .8 under any speed")
			var first := runtime.advance(0.001, [enemy])
			_expect(first.size() == 1 and first[0].pulse_index == 0, "First pulse at .8 under any speed")
			_expect(runtime.advance(0.799, [enemy]).is_empty(), "Second warning remains a full .8 under any speed")
			var second := runtime.advance(0.001, [enemy])
			_expect(second.size() == 1 and second[0].pulse_index == 1, "Second pulse at 1.6 under any speed")
			var contact: Dictionary = Monsters.contact_components(enemy)
			for type: String in contact:
				_near(first[0].packet.base[type], contact[type] * 0.65, "First pulse uses original contact times .65")
				_near(second[0].packet.base[type], contact[type] * 0.65, "Second pulse uses original contact times .65")
				_near(first[0].packet.base[type] + second[0].packet.base[type], contact[type] * 1.3, "Whole action retains contact times 1.3")
			_expect(runtime.advance(policy.profile.recovery_seconds - 0.001, [enemy]).is_empty() and runtime.active_count() == 1, "Recovery lasts its scaled duration")
			_expect(runtime.advance(0.001, [enemy]).is_empty() and runtime.active_count() == 0, "Recovery finishes without another pulse")
	for invalid: Variant in [null, NAN, INF, -INF, -1.0, 0.0, true, "fast"]:
		var enemy := _enemy()
		enemy.attack_speed = invalid
		_expect(Monsters.telegraph_policy(enemy).is_empty(), "Invalid attack speed cannot create a policy")


func _state(runtime: RefCounted, phase: String, index: int, elapsed: float, label: String) -> void:
	var state: Dictionary = runtime.state_for(1)
	_expect(not state.is_empty() and state.phase == phase and state.pulse_index == index, label + " phase/index")
	_near(state.elapsed, elapsed, label + " displayed elapsed")
	_expect(state.center == CENTER and state.profile.radius == 85.0, label + " frozen point/radius")


func _test_exact_phases() -> void:
	var enemy := _enemy()
	# Isolate the authored 1.9 baseline here; native boss mastery speed is covered above.
	enemy.attack_speed = Monsters.BASE_ATTACK_SPEED
	var runtime := Runtime.new()
	var started := _start(runtime, enemy)
	_expect(started.ok and started.attack.attack_id == 1 and runtime.has_timed_sequence_actions(), "Admission creates exactly one timed action")
	_state(runtime, "windup", 0, 0.0, "First warning begins")
	_expect(runtime.advance(0.0, [enemy]).is_empty(), "Zero delta emits nothing")
	_expect(runtime.advance(0.4, [enemy]).is_empty(), "First half warning is harmless")
	_state(runtime, "windup", 0, 0.4, "First warning midpoint")
	enemy.pos += Vector2(100, -100)
	_expect(not _start(runtime, enemy, CENTER + Vector2(400, 400)).ok, "Busy source cannot retarget")
	_expect(runtime.advance(0.399, [enemy]).is_empty(), "First warning does not fire early")
	_state(runtime, "windup", 0, 0.799, "Before first deadline")
	var first := runtime.advance(0.001, [enemy])
	_expect(first.size() == 1 and first[0].pulse_index == 0 and first[0].pulse_count == 2 and first[0].attack_id == 1, "Exactly pulse zero at first deadline")
	_near(first[0].attack_age, 0.8, "First absolute deadline")
	_state(runtime, "windup", 1, 0.0, "Second warning restarts only the display clock")
	_expect(runtime.advance(0.4, [enemy]).is_empty(), "Second half warning is harmless")
	_state(runtime, "windup", 1, 0.4, "Second warning midpoint")
	_expect(runtime.advance(0.399, [enemy]).is_empty(), "Second warning does not fire early")
	_state(runtime, "windup", 1, 0.799, "Before second deadline")
	var second := runtime.advance(0.001, [enemy])
	_expect(second.size() == 1 and second[0].pulse_index == 1 and second[0].attack_id == first[0].attack_id, "Exactly pulse one keeps the same action identity")
	_near(second[0].attack_age, 1.6, "Second absolute deadline")
	_expect(first[0].center == CENTER and second[0].center == CENTER and first[0].radius == 85.0 and second[0].radius == 85.0, "Both pulses remain at the originally supplied player point")
	_expect(Runtime.overlaps(first[0], CENTER + Vector2(100, 0), 15.0) and not Runtime.overlaps(first[0], CENTER + Vector2(100.001, 0), 15.0), "85 radius retains existing inclusive overlap boundary")
	_state(runtime, "recovery", 1, 0.8, "Recovery begins at full second-warning elapsed")
	_expect(runtime.advance(0.0, [enemy]).is_empty(), "Zero delta cannot replay the second pulse")
	_expect(runtime.advance(0.95, [enemy]).is_empty(), "Recovery has no pulses")
	_state(runtime, "recovery", 1, 1.75, "Recovery midpoint")
	_expect(runtime.advance(0.949, [enemy]).is_empty(), "Recovery remains active until its endpoint")
	_state(runtime, "recovery", 1, 2.699, "Before .8 plus recovery display endpoint")
	_expect(runtime.advance(0.001, [enemy]).is_empty() and runtime.active_count() == 0, "3.5 total seconds removes the finished action")
	_expect(runtime.state_for(1).is_empty() and not runtime.has_timed_sequence_actions(), "Completed state is absent")
	_expect(runtime.advance(1.0e308, [enemy]).is_empty(), "Advancing a completed action never repeats pulses")


func _trajectory(steps: Array) -> Array:
	var enemy := _enemy()
	var runtime := Runtime.new()
	_expect(_start(runtime, enemy).ok, "Trajectory starts")
	var elapsed := 0.0
	var events: Array = []
	for delta: float in steps:
		for event: Dictionary in runtime.advance(delta, [enemy]):
			_near(elapsed + event.step_time, event.attack_age, "Step offset reconstructs the absolute deadline")
			_expect(event.step_time >= 0.0 and event.step_time <= delta + EPSILON, "Event belongs to the current step")
			# Only local step offset differs by partition. All remaining event bytes must match.
			event.erase("step_time")
			events.append(event)
		elapsed += delta
	_expect(events.size() == 2 and runtime.active_count() == 0, "Every partition settles at most two pulses and completes")
	_expect(runtime.advance(100.0, [enemy]).is_empty(), "No partition leaves a replayable pulse")
	return events


func _test_step_equivalence_and_bounds() -> void:
	var whole := _trajectory([3.5])
	var frame_steps: Array = []
	for _frame: int in range(210): frame_steps.append(1.0 / 60.0)
	for partition: Array in [[0.0, 0.8, 0.0, 0.8, 1.9], [0.3, 0.5, 0.4, 0.4, 0.7, 1.2], frame_steps, [1.0e308]]:
		_expect(var_to_bytes(_trajectory(partition)) == var_to_bytes(whole), "Whole event bytes match after only step-offset removal")
	var runtime := Runtime.new()
	var sources: Array = []
	for id: int in range(100, 0, -1):
		var enemy := _enemy()
		enemy.id = id
		enemy.root_id = id
		sources.append(enemy)
		_expect(_start(runtime, enemy).ok, "Bounded scheduler admits source %d" % id)
	var overflow := _enemy()
	overflow.id = 101
	overflow.root_id = 101
	_expect(not _start(runtime, overflow).ok and runtime.active_count() == 100, "Capacity cannot evict an existing sequence")
	var events := runtime.advance(50.0, sources)
	_expect(events.size() == 200 and runtime.active_count() == 0, "100 bounded actions emit exactly 200 events")
	for index: int in range(events.size()):
		_expect(events[index].source_id == index % 100 + 1 and events[index].pulse_index == index / 100, "Events order by deadline then source identity")
	_expect(runtime.advance(50.0, sources).is_empty(), "No event repeats after the bounded burst")


func _reject(enemy: Variant, overrides: Variant, pattern: Variant, label: String, point: Vector2 = CENTER) -> void:
	var runtime := Runtime.new()
	_expect(not runtime.start(enemy, point, overrides, pattern).ok and runtime.active_count() == 0, label)
	_expect(_start(runtime, _enemy()).attack.attack_id == 1, label + " preserves the first action identity")


func _test_invalid_inputs() -> void:
	var good := _enemy()
	var profile: Dictionary = Monsters.telegraph_policy(good).profile
	for bad: Variant in [null, true, [], 2, {}]: _reject(bad, profile, "sunwell_echo", "Malformed source rejects")
	for row: Array in [["root_id", 2], ["root_id", 1.0], ["generation", 1], ["generation", 0.0], ["template_id", "crawler"], ["rarity", "rare"], ["map_boss_attack_id", "garden_slam"], ["map_boss_attack_id", "unknown"], ["health", 0.0], ["spawn", 0.1], ["death_processed", true]]:
		var bad := good.duplicate(true)
		bad[row[0]] = row[1]
		_reject(bad, profile, "sunwell_echo", "Forged boss authority rejects: " + row[0])
	var unattached := good.duplicate(true)
	unattached.erase("map_boss_attack_id")
	_reject(unattached, profile, "sunwell_echo", "Unattached root cannot request Echo")
	for field: String in ["id", "health", "spawn", "damage"]:
		for invalid: Variant in [null, true, "1", NAN, INF, -INF, -1.0]:
			var bad := good.duplicate(true)
			bad[field] = invalid
			_reject(bad, profile, "sunwell_echo", "Invalid numeric source field: " + field)
	for invalid: Variant in [null, [], {}, {"physical": 0.5}, {"fire": -1.0}, {"cold": NAN}, {"unknown": 1.0}, {"physical": true}]:
		var bad := good.duplicate(true)
		bad.contact_weights = invalid
		_reject(bad, profile, "sunwell_echo", "Invalid contact components reject")
	for pattern: Variant in [null, true, 2, [], "unknown", "garden_slam", "ember_burn"]:
		_reject(good, profile, pattern, "Wrong visual authority rejects")
	for overrides: Variant in [null, [], true, {}, {"pulse_count": 3}, {"radius": 85.0}, {"windup_seconds": 0.8}]:
		_reject(good, overrides, "sunwell_echo", "Missing or unknown Echo override rejects")
	for field: String in ["radius", "windup_seconds", "damage_multiplier", "recovery_seconds"]:
		for invalid: Variant in [null, true, "1", NAN, INF, -1.0]:
			var overrides := profile.duplicate(true)
			overrides[field] = invalid
			_reject(good, overrides, "sunwell_echo", "Malformed override rejects: " + field)
	for field: String in ["radius", "windup_seconds", "damage_multiplier"]:
		var overrides := profile.duplicate(true)
		overrides[field] += 0.001
		_reject(good, overrides, "sunwell_echo", "Valid but unauthorized Echo budget rejects: " + field)
	for point: Vector2 in [Vector2(INF, 0), Vector2(0, NAN)]: _reject(good, profile, "sunwell_echo", "Nonfinite center rejects", point)
	for invalid: float in [0.0, -1.0, NAN, INF, -INF]:
		var runtime := Runtime.new()
		_start(runtime, good)
		runtime.advance(0.8, [good])
		var before := var_to_bytes(runtime.state_for(1))
		_expect(runtime.advance(invalid, [good]).is_empty() and var_to_bytes(runtime.state_for(1)) == before, "Invalid delta freezes the second warning")
	var oversized: Array = []
	for id: int in range(101):
		var source := good.duplicate(true)
		source.id = id + 1
		oversized.append(source)
	for invalid: Variant in [null, {}, true, [null], [{}], [good, good], oversized]:
		var runtime := Runtime.new()
		_start(runtime, good)
		runtime.advance(0.8, [good])
		_expect(runtime.advance(50.0, invalid).is_empty() and runtime.active_count() == 0, "Malformed source universe cancels pending echo")


func _test_cancellation_and_restart() -> void:
	for elapsed: float in [0.4, 0.8, 1.2, 1.6]:
		for mode: String in ["death", "birth", "processed", "removed", "cancel", "reset"]:
			var enemy := _enemy()
			var runtime := Runtime.new()
			var first_id: int = _start(runtime, enemy).attack.attack_id
			runtime.advance(elapsed, [enemy])
			var live: Array = [enemy]
			match mode:
				"death": enemy.health = 0.0
				"birth": enemy.spawn = 0.1
				"processed": enemy.death_processed = true
				"removed": live.clear()
				"cancel": _expect(runtime.cancel(enemy.id), "Explicit cancel removes the sequence")
				"reset": runtime.reset()
			_expect(runtime.advance(0.0, live).is_empty() and runtime.active_count() == 0, "Cancellation runs even at zero delta: %s at %.1f" % [mode, elapsed])
			_expect(runtime.advance(100.0, [_enemy()]).is_empty(), "Restored source never revives a cancelled second pulse")
			enemy = _enemy()
			var restarted := _start(runtime, enemy, CENTER + Vector2(10, 10))
			_expect(restarted.ok and restarted.attack.attack_id > first_id and restarted.attack.pulse_index == 0 and restarted.attack.elapsed == 0.0, "Restart starts a new identity with a full first warning")
			_expect(runtime.advance(0.799, [enemy]).is_empty(), "Restart cannot inherit old elapsed time")
			var events := runtime.advance(0.801, [enemy])
			_expect(events.size() == 2 and events[0].attack_id == restarted.attack.attack_id and events[1].attack_id == restarted.attack.attack_id, "Restart emits only its own two pulses")
			_expect(events[0].center == CENTER + Vector2(10, 10) and events[1].center == events[0].center, "Only explicit restart can choose a new point")
	for field: String in ["health", "spawn", "death_processed"]:
		var enemy := _enemy()
		var runtime := Runtime.new()
		_start(runtime, enemy)
		runtime.advance(0.8, [enemy])
		enemy[field] = "invalid"
		_expect(runtime.advance(50.0, [enemy]).is_empty() and runtime.active_count() == 0, "Malformed liveness cancels before the second pulse")


func _test_copies() -> void:
	var enemy := _enemy()
	# A valid mixed packet makes nested component copying observable for both pulses.
	enemy.contact_weights = {"physical": 0.5, "fire": 0.3, "cold": 0.2}
	var profile: Dictionary = Monsters.telegraph_policy(enemy).profile
	var original_recovery: float = profile.recovery_seconds
	var input_bytes := var_to_bytes([enemy, profile])
	var definition := Bosses.definition("sunwell_echo")
	definition.profile.radius = 1.0
	definition.pulse_count = 99
	_expect(Bosses.definition("sunwell_echo").profile.radius == 85.0 and Bosses.definition("sunwell_echo").pulse_count == 2, "Definition accessor is detached")
	var runtime := Runtime.new()
	seed(48048)
	var expected_random := randi()
	seed(48048)
	var started := runtime.start(enemy, CENTER, profile, "sunwell_echo")
	var original := var_to_bytes(runtime.state_for(1))
	started.attack.center = Vector2.ZERO
	started.attack.profile.radius = 1.0
	started.attack.packet.base.fire = 999.0
	started.attack.pulses_emitted = 99
	_expect(var_to_bytes(runtime.state_for(1)) == original, "Start result cannot alter retained action")
	var exposed := runtime.state_for(1)
	exposed.profile.windup_seconds = 0.01
	exposed.packet.tags.clear()
	exposed.center = Vector2.ZERO
	_expect(var_to_bytes(runtime.state_for(1)) == original, "state_for deeply copies profile, tags and point")
	var first := runtime.advance(0.8, [enemy])
	_expect(var_to_bytes([enemy, profile]) == input_bytes, "Start and advance preserve caller inputs")
	_expect(not first[0].has("burn_policy") and first[0].packet.base.size() == 3, "Echo retains typed hit components without an unrelated burn policy")
	var mixed_contact: Dictionary = Monsters.contact_components(enemy)
	for type: String in mixed_contact:
		_near(first[0].packet.base[type], mixed_contact[type] * 0.65, "Mixed contact component retains its exact per-pulse budget")
	var saved_event := var_to_bytes(first[0])
	var expected_base: Dictionary = first[0].packet.base.duplicate(true)
	first[0].profile.radius = 1.0
	first[0].packet.base.fire = 999.0
	first[0].packet.tags.clear()
	first[0].center = Vector2.ZERO
	first[0].pulse_index = 99
	var saved_state := var_to_bytes(runtime.state_for(1))
	profile.radius = 1.0
	profile.damage_multiplier = 0.0
	enemy.pos = Vector2(999, 999)
	enemy.damage = 99999.0
	enemy.attack_speed *= 20.0
	enemy.contact_weights.clear()
	enemy.contact_weights.lightning = 1.0
	_expect(var_to_bytes(runtime.state_for(1)) == saved_state, "Later input mutations cannot alter the pending sequence")
	var second := runtime.advance(0.8, [enemy])
	_expect(second.size() == 1 and second[0].packet.base == expected_base and second[0].profile.radius == 85.0 and second[0].center == CENTER and second[0].packet.tags == ["attack", "area", "hit"], "Second pulse remains an independent frozen copy")
	_expect(second[0].pulse_index == 1 and bytes_to_var(saved_event).pulse_index == 0, "Returned first pulse never aliases the second pulse")
	_near(runtime.state_for(1).profile.recovery_seconds, original_recovery, "Mid-action speed change cannot shorten frozen recovery")
	_expect(randi() == expected_random, "Pure scheduling consumes no global RNG")
	var retained := var_to_bytes(second[0])
	runtime.reset()
	_expect(var_to_bytes(second[0]) == retained, "Reset does not mutate events already returned")


func _test_frozen_legacy() -> void:
	var path := "res://docs/qa/v048-echo/legacy-v047.bin"
	_expect(FileAccess.file_exists(path), "Released v47 oracle exists")
	if not FileAccess.file_exists(path): return
	var frozen := FileAccess.get_file_as_bytes(path)
	var current := Legacy.records()
	var prior: Array = bytes_to_var(frozen)
	_expect(prior.size() == 6 and current.size() == 6, "Default and two old bosses include timed and untimed trajectories")
	_expect(var_to_bytes(current) == frozen, "All six complete legacy raw trajectories match released v47 bytes")
	for index: int in range(mini(prior.size(), current.size())):
		_expect(var_to_bytes(current[index]) == var_to_bytes(prior[index]), "Unfiltered start/state/event bytes match: %s timed=%s" % [current[index].kind, current[index].timed])
