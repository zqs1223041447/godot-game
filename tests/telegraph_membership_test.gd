extends SceneTree
## Boolean-query equivalence against the unchanged copied-snapshot API.
const Runtime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func enemy(id: int, pattern: String = "") -> Dictionary:
	var result := {"id": id, "root_id": id, "generation": 0, "template_id": "ember_guard",
		"rarity": "normal", "health": 100.0, "spawn": 0.0, "death_processed": false,
		"damage": 20.0, "attack_speed": Monsters.BASE_ATTACK_SPEED,
		"pos": Vector2.ZERO, "contact_weights": {"physical": 0.5, "fire": 0.5}}
	if not pattern.is_empty():
		result.template_id = "rift_warden"
		result.rarity = "boss"
		result.map_boss_attack_id = pattern
	return result

func start(runtime: RefCounted, actor: Dictionary) -> void:
	var policy: Dictionary = Monsters.telegraph_policy(actor)
	check(runtime.start(actor, Vector2(100, 100), policy.profile, policy.get("visual_pattern", "")).ok, "Admission")

func compare(runtime: RefCounted, label: String) -> void:
	var before := var_to_bytes([runtime._states, runtime._next_attack_id])
	for id: int in range(-1, 103):
		check(runtime.has_state(id) == not runtime.state_for(id).is_empty(), label + ": predicate")
	check(before == var_to_bytes([runtime._states, runtime._next_attack_id]), label + ": read-only")

func _initialize() -> void:
	for pattern: String in ["", "sunwell_echo", "ginkgo_shelter_slam", "ruins_garden_slam"]:
		var runtime := Runtime.new()
		var actor := enemy(1, pattern)
		compare(runtime, "empty")
		start(runtime, actor)
		compare(runtime, "windup")
		# Exercise partial freezing, first/second warnings, recovery and expiry.
		for delta: float in [0.5, 0.4, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 10.0]:
			runtime.advance(delta, [actor], true, {1: delta / 2.0} if delta == 0.5 else {})
			compare(runtime, "advance " + str(delta))
		check(not runtime.has_state(1), "Expiry removes state")
		start(runtime, actor)
		runtime.cancel(1)
		compare(runtime, "explicit cancellation")
		start(runtime, actor)
		runtime.advance(0.0, [])
		compare(runtime, "source removed")
		start(runtime, actor)
		actor.health = 0.0
		runtime.advance(0.0, [actor])
		compare(runtime, "dead source")
		actor.health = 100.0
		start(runtime, actor)
		runtime.reset()
		compare(runtime, "reset")
	var crowd := Runtime.new()
	for id: int in range(1, 101): start(crowd, enemy(id))
	compare(crowd, "100 active sources")
	if "--bench" in OS.get_cmdline_user_args(): benchmark(crowd, "100 active")
	for id: int in range(1, 101, 2): crowd.cancel(id)
	compare(crowd, "50 active / 50 inactive")
	if "--bench" in OS.get_cmdline_user_args():
		benchmark(crowd, "mixed")
		crowd.reset()
		benchmark(crowd, "empty")
	print("Telegraph membership: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func sample(runtime: RefCounted, membership: bool) -> Dictionary:
	var total := 0
	var begin := Time.get_ticks_usec()
	for repeat: int in range(100):
		for id: int in range(1, 101):
			if runtime.has_state(id) if membership else not runtime.state_for(id).is_empty(): total += 1
	return {"us": Time.get_ticks_usec() - begin, "hits": total}

func benchmark(runtime: RefCounted, label: String) -> void:
	var before := var_to_bytes([runtime._states, runtime._next_attack_id])
	# Warm both paths, alternate pair order, and report raw samples without a timing gate.
	sample(runtime, false); sample(runtime, true)
	var old_samples: Array[int] = []
	var new_samples: Array[int] = []
	for pair: int in range(6):
		var old: Dictionary
		var new: Dictionary
		if pair % 2 == 0:
			old = sample(runtime, false); new = sample(runtime, true)
		else:
			new = sample(runtime, true); old = sample(runtime, false)
		check(old.hits == new.hits, "Benchmark predicates agree")
		old_samples.append(old.us); new_samples.append(new.us)
	check(before == var_to_bytes([runtime._states, runtime._next_attack_id]), "Benchmark is read-only")
	print("Query benchmark %s (10000 queries/sample), snapshot_us=%s membership_us=%s" % [label, old_samples, new_samples])
