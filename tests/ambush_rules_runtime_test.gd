extends SceneTree
## Pure carrier boundaries, isolated from actor/UI/save state and RNG.
const Rules = preload("res://scripts/combat/ambush_support_rules.gd")
const Runtime = preload("res://scripts/combat/player_trap_runtime.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Critical = preload("res://scripts/combat/critical_strike_runtime.gd")
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(660066)
	var expected: Array = [randi(), randi(), randi()]
	seed(660066)
	_case(_boundaries, "arming, expiry, monotonically increasing clock")
	_case(_capacity, "shared quota, read-only preflight, atomic refusal")
	_case(_ownership, "placement snapshots and ownership transfer")
	_case(_criticals, "placement-time critical result validation")
	_case(_malformed, "malformed inputs fail without mutation")
	_case(_bounded, "bounded pure-data storage and reset")
	_expect([randi(), randi(), randi()] == expected, "All carrier operations preserve global RNG")
	print("Ambush rules/runtime: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _case(callback: Callable, label: String) -> void:
	completed = false
	callback.call()
	_expect(completed, "Case completed without script errors: " + label)


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


func _cast(skill: String = "nova", critical_chance: float = 0.0) -> Dictionary:
	var stats: Dictionary = {"damage": 100.0, "global_increased": 0.25, "spell_added_cold": 7.0}
	if critical_chance > 0.0:
		stats.crit_base_chance = critical_chance
		stats.crit_base_multiplier = 2.25
	var cast: Dictionary = Compiler.compile_group(skill, Combat.snapshot(stats, []), ["ambush"])
	_expect(cast.ok, "Fixture compiles: " + skill)
	return cast


func _place(runtime: RefCounted, at: float, cast: Dictionary, cast_id: int = 1) -> Dictionary:
	return runtime.place(at, Vector2(10, 20), cast, cast.snapshot, cast_id)


func _bytes(runtime: RefCounted) -> PackedByteArray:
	return var_to_bytes([runtime.get("_entries"), runtime.get("_clock"), runtime.get("_next_id")])


func _adjacent(value: float, direction: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	bytes.encode_u64(0, bytes.decode_u64(0) + direction)
	return bytes.decode_double(0)


func _boundaries() -> void:
	var runtime := Runtime.new()
	var cast := _cast()
	_expect(runtime.is_empty() and runtime.ready(0).ready.is_empty(), "Empty runtime emits no candidate")
	_expect(_place(runtime, 0, cast).id == 1, "First placement owns identity one")
	_expect(runtime.statuses(0)[0] == {"id": 1, "position": Vector2(10, 20), "skill_id": "nova", "armed": false,
		"remaining_seconds": 12.0, "arming_remaining_seconds": 0.35}, "Exact minimal initial presentation")
	var before: PackedByteArray = _bytes(runtime)
	_expect(runtime.statuses(12).is_empty() and _bytes(runtime) == before, "Expired presentation read does not advance or prune")
	_expect(not runtime.take(1, _adjacent(0.35, -1)).ok and _bytes(runtime) == before, "ULP-before arming consumption rejects atomically")
	_expect(runtime.ready(_adjacent(0.35, -1)).ready.is_empty(), "No early trigger through floating tolerance")
	var ready: Dictionary = runtime.ready(0.35)
	_expect(ready.ok and ready.ready == [{"id": 1, "position": Vector2(10, 20), "trigger_radius": 70.0}], "Exact arming emits minimal identity-ordered row")
	var taken: Dictionary = runtime.take(1, 0.35)
	_expect(taken.ok and taken.entry.armed_at == 0.35 and taken.entry.expires_at == 12.0, "Exact arming consumes frozen entry")
	_expect(runtime.is_empty() and not runtime.take(1, 0.35).ok, "Exactly once consumption")
	_expect(_place(runtime, 1.0, cast).id == 2, "Later placement does not reuse consumed identity")
	_expect(runtime.ready(_adjacent(13.0, -1)).ready.size() == 1, "ULP-before expiry remains available")
	before = _bytes(runtime)
	_expect(not runtime.take(2, 13.0).ok and _bytes(runtime) == before, "Exact expiry can never emit a hit")
	_expect(runtime.ready(13.0).ready.is_empty() and runtime.is_empty(), "Exact expiry prunes without explosion")
	before = _bytes(runtime)
	_expect(not runtime.ready(12.0).ok and not runtime.can_place(12.0, Vector2.ZERO, cast).ok, "Clock rejects backwards observations and placements")
	_expect(_bytes(runtime) == before and runtime.statuses(12).is_empty(), "Invalid clock operations cannot mutate")
	_expect(runtime.ready(1.0e300).ok, "Huge finite advancement safely drains empty storage")
	_expect(not runtime.can_place(1.0e300, Vector2.ZERO, cast).ok, "Unrepresentable arming deadlines reject")
	completed = true


func _capacity() -> void:
	var runtime := Runtime.new()
	var nova := _cast()
	var meteor := _cast("meteor")
	for index: int in range(3):
		_expect(_place(runtime, 0, nova if index != 1 else meteor, 10 + index).id == index + 1, "Both skill kinds share one serial and quota")
	var before := _bytes(runtime)
	var denied: Dictionary = runtime.can_place(0, Vector2.ZERO, meteor)
	_expect(not denied.ok and denied.error_code == "capacity", "Quota refusal has presentation-safe capacity code")
	_expect(not _place(runtime, 0, meteor, 90).ok and _bytes(runtime) == before, "Full quota rejects without consuming serial, clock or storage")
	_expect(runtime.can_place(12, Vector2.ZERO, meteor).ok and _bytes(runtime) == before, "Read-only quota ignores exact-expired entries")
	_expect(not _place(runtime, 12, meteor, 0).ok and _bytes(runtime) == before, "Invalid late placement does not prune expired entries")
	_expect(_place(runtime, 12, meteor, 99).id == 4 and runtime.active_count() == 1, "Accepted exact-expiry placement atomically frees old quota")
	_expect(runtime.statuses(12)[0].skill_id == "meteor", "One new unarmed meteor remains")
	completed = true


func _ownership() -> void:
	var runtime := Runtime.new()
	var cast := _cast()
	var packet_before: PackedByteArray = var_to_bytes(cast.packets.direct)
	var snapshot_before: PackedByteArray = var_to_bytes(cast.snapshot)
	_expect(_place(runtime, 0, cast).ok and _place(runtime, 0, cast, 2).ok, "Two independent frozen carriers")
	cast.recipe.radius = 1.0
	cast.snapshot.modifiers[0].value = 999.0
	cast.packets.direct.base.clear()
	cast.snapshot.compiled_packets.clear()
	var statuses: Array = runtime.statuses(0)
	statuses[0].position = Vector2(-99, -99)
	statuses.clear()
	var candidates: Dictionary = runtime.ready(0.35)
	candidates.ready[0].id = 777
	candidates.ready[0].position = Vector2.ZERO
	var taken: Dictionary = runtime.take(1, 0.35)
	_expect(taken.ok and taken.entry.radius == 155.0 and taken.entry.slow == 0.6, "Placement geometry and nova slow survive caller mutation")
	_expect(var_to_bytes(taken.entry.packet) == packet_before and var_to_bytes(taken.entry.snapshot) == snapshot_before, "Deep snapshot isolates nested source mutation")
	_expect(taken.entry.position == Vector2(10, 20) and taken.entry.cast_id == 1, "Projection mutation cannot alter frozen provenance")
	taken.entry.packet.base.clear()
	taken.entry.snapshot.modifiers.clear()
	var second: Dictionary = runtime.take(2, 0.35)
	_expect(var_to_bytes(second.entry.packet) == packet_before and var_to_bytes(second.entry.snapshot) == snapshot_before, "Owned consumption of first trap cannot mutate another")
	completed = true


func _criticals() -> void:
	for chance: float in [0.0, 0.4, 1.0]:
		var cast := _cast("meteor", chance)
		var runtime := Runtime.new()
		var critical := Critical.new()
		critical.reset(660)
		var checkpoint := critical.checkpoint()
		_expect(runtime.can_place(0, Vector2.ZERO, cast).ok and critical.checkpoint() == checkpoint, "Preflight consumes no private critical state")
		var frozen: Dictionary = critical.freeze(cast.snapshot)
		_expect(frozen.ok and runtime.place(0, Vector2.ZERO, cast, frozen.snapshot, 1).ok, "Exact Critical.freeze result is accepted for every chance")
		var entry: Dictionary = runtime.take(1, 0.35).entry
		_expect(entry.snapshot == frozen.snapshot and entry.slow == 0.0, "Critical outcome remains the placement result until trigger")
		if chance > 0.0:
			var before := _bytes(runtime)
			_expect(not runtime.place(0.35, Vector2.ZERO, cast, cast.snapshot, 2).ok and _bytes(runtime) == before, "Unrolled positive-chance snapshot rejects atomically")
			var forged: Dictionary = frozen.snapshot.duplicate(true)
			forged.critical_roll.multiplier = 77.0
			_expect(not runtime.place(0.35, Vector2.ZERO, cast, forged, 2).ok, "Forged critical strength rejects")
	completed = true


func _malformed() -> void:
	var runtime := Runtime.new()
	var cast := _cast()
	_expect(_place(runtime, 0, cast).ok, "Malformed-input fixture")
	var before := _bytes(runtime)
	for invalid: Variant in [null, true, false, "0", &"0", [], {}, NAN, INF, -INF, -1.0]:
		_expect(not runtime.can_place(invalid, Vector2.ZERO, cast).ok, "Bad preflight time rejected")
		_expect(not runtime.ready(invalid).ok and not runtime.take(1, invalid).ok and runtime.statuses(invalid).is_empty(), "Bad observation time rejected")
		_expect(_bytes(runtime) == before, "Malformed time leaves exact state unchanged")
	for invalid: Variant in [null, true, 1, Vector2(INF, 0), Vector2(0, NAN), Vector3.ZERO, {}]:
		_expect(not runtime.can_place(0, invalid, cast).ok and _bytes(runtime) == before, "Bad position rejected atomically")
	for invalid: Variant in [null, true, false, "1", &"1", 1.0, [], {}, -1, 0]:
		_expect(not runtime.place(0, Vector2.ZERO, cast, cast.snapshot, invalid).ok and not runtime.take(invalid, 0).ok, "Cast and trap IDs require positive integers")
		_expect(_bytes(runtime) == before, "Malformed identity leaves exact state unchanged")
	for invalid: Variant in [null, true, "cast", [], {}, {"ok": true}]:
		_expect(not runtime.can_place(0, Vector2.ZERO, invalid).ok and _bytes(runtime) == before, "Malformed compiled envelope rejected atomically")
	var edits: Array = [["ok", 1], ["skill_id", "cleave"], ["mana", -1.0], ["cooldown", 0], ["initial_count", 1], ["trap_profile", {}], ["packets", {}], ["snapshot", {}], ["recipe", {"radius": 501.0}], ["support_ids", []]]
	for edit: Array in edits:
		var bad: Dictionary = cast.duplicate(true)
		bad[edit[0]] = edit[1]
		_expect(not runtime.can_place(0, Vector2.ZERO, bad).ok and _bytes(runtime) == before, "Malformed compiled field rejected: " + str(edit[0]))
	for field: String in Rules.POLICY:
		for invalid: Variant in [true, null, "1", NAN, INF, -1, 0.0]:
			var bad: Dictionary = cast.duplicate(true)
			bad.trap_profile[field] = invalid
			_expect(not runtime.can_place(0, Vector2.ZERO, bad).ok and _bytes(runtime) == before, "Malformed fixed policy rejected: " + field)
	var bad: Dictionary = cast.duplicate(true)
	bad.packets.direct.tags.append("trap")
	_expect(not runtime.can_place(0, Vector2.ZERO, bad).ok, "Trap damage tag is not introduced")
	bad = cast.duplicate(true)
	bad.snapshot.modifiers.append(bad.snapshot.modifiers.back().duplicate(true))
	_expect(not runtime.can_place(0, Vector2.ZERO, bad).ok, "Duplicate Ambush damage factor rejected")
	for links: Array in [["ambush", "unknown"], ["ambush", "efficiency", "efficiency"], ["ambush", "ignite"], ["ambush", "volley"]]:
		bad = cast.duplicate(true)
		bad.support_ids = links
		_expect(not runtime.can_place(0, Vector2.ZERO, bad).ok, "Forged support admission rejected")
	bad = cast.duplicate(true)
	bad.snapshot.modifiers[0].all_tags = ["trap"]
	_expect(not runtime.can_place(0, Vector2.ZERO, bad).ok, "Unimplemented trap-stat damage scope rejected")
	var foreign: Dictionary = cast.snapshot.duplicate(true)
	foreign.modifiers[0].value += 1.0
	_expect(not runtime.place(0, Vector2.ZERO, cast, foreign, 4).ok and _bytes(runtime) == before, "Foreign frozen snapshot rejected atomically")
	completed = true


func _bounded() -> void:
	var runtime := Runtime.new()
	var cast := _cast()
	var before := _bytes(runtime)
	for extra: Variant in [RefCounted.new(), func(): pass, "x".repeat(4097)]:
		var bad: Dictionary = cast.duplicate(true)
		bad.snapshot.extra = extra
		_expect(not runtime.can_place(0, Vector2.ZERO, bad).ok and _bytes(runtime) == before, "References and excessive strings cannot enter retained storage")
	var bad: Dictionary = cast.duplicate(true)
	var cycle: Dictionary = {}
	cycle["self"] = cycle
	bad.snapshot.extra = cycle
	_expect(not runtime.can_place(0, Vector2.ZERO, bad).ok and _bytes(runtime) == before, "Cyclic input is rejected by bounded traversal")
	cycle.clear()
	bad = cast.duplicate(true)
	var many: Array = []
	many.resize(Runtime.MAX_DATA_VALUES + 1)
	bad.snapshot.extra = many
	_expect(not runtime.can_place(0, Vector2.ZERO, bad).ok, "Aggregate storage budget rejects oversized arrays")
	bad = cast.duplicate(true)
	bad.snapshot[&"optional_data"] = {&"name": &"literal"}
	_expect(runtime.can_place(0, Vector2.ZERO, bad).ok and runtime.place(0, Vector2.ZERO, bad, bad.snapshot, 1).ok, "Production StringName keys and inert values remain valid pure data")
	runtime.reset()
	_expect(runtime.is_empty() and _place(runtime, 0, cast).id == 1, "Lifecycle reset clears carriers, clock and serial")
	runtime.reset()
	runtime.set("_next_id", Runtime.MAX_ID)
	before = _bytes(runtime)
	_expect(not _place(runtime, 0, cast).ok and _bytes(runtime) == before, "Identity exhaustion rejects without overflow")
	completed = true
