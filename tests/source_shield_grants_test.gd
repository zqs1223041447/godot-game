extends SceneTree
const Grants = preload("res://scripts/mechanics/source_monster_grants.gd")
const TreeData = preload("res://scripts/passives/source_tree_data.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const CAPACITY := "source_aegis_capacity"
const RECOVERY := "source_aegis_recovery"
const OLD_IDS: Array[String] = ["source_gale_stride", "source_ember_power", "source_grove_vitality"]
const FIXTURES: Array[Dictionary] = [
	{"node":"58218","index":0,"line":"8% increased maximum Energy Shield","stat":"max_shield","value":0.08},
	{"node":"21929","index":1,"line":"4% increased maximum Energy Shield","stat":"max_shield","value":0.04},
	{"node":"6949","index":1,"line":"10% increased Energy Shield Recharge Rate","stat":"shield_recharge_rate_increased","value":0.10},
]
var checks := 0
var failures := 0
var frozen_v75: GDScript


func _initialize() -> void:
	check(TreeData.ready(), "pinned source is available")
	check(Grants.IDS == OLD_IDS + [CAPACITY, RECOVERY], "five exact ordered source admissions")
	var source_before := var_to_bytes([TreeData._data, TreeData._nodes])
	_load_frozen_v75()
	_test_old_bytes()
	_test_current()
	_test_detached()
	_test_single_boundary()
	_test_bundle_boundary()
	_test_cache()
	_test_live_changes()
	_test_metadata()
	_test_old_bytes()
	_test_read_only_rng(source_before)
	print("Source shield grants: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _load_frozen_v75() -> void:
	# Exact 76c9cab source captured with read-only git show; strip only the global
	# class registration so it can coexist with the new adapter in this process.
	var source := FileAccess.get_file_as_string("res://docs/qa/v076-source-grants/source_monster_grants.v075.gd.txt")
	check(source.begins_with("class_name SourceMonsterGrants\n"), "frozen v75 source fixture retains its original class header")
	frozen_v75 = GDScript.new()
	frozen_v75.source_code = source.trim_prefix("class_name SourceMonsterGrants\n")
	check(frozen_v75.reload() == OK, "frozen v75 adapter compiles independently")


func _test_old_bytes() -> void:
	for id: String in OLD_IDS:
		check(var_to_bytes(Grants.resolve(id)) == var_to_bytes(frozen_v75.resolve(id)), "entire legacy resolve wire bytes preserved: " + id)
		check(var_to_bytes(Grants.get_definition(id)) == var_to_bytes(frozen_v75.get_definition(id)), "entire legacy definition wire bytes preserved: " + id)


func _entries() -> Array:
	return [TreeData.stat_entry("21929", 1), TreeData.stat_entry("6949", 1)]


func _parsed(entries: Array) -> Array:
	var result: Array = []
	for entry: Dictionary in entries:
		result.append(Runtime.line_effect(entry.raw_line, Runtime.CURRENT_SAVE_VERSION))
	return result


func _compile(entries: Variant, parsed: Variant, id: String = RECOVERY) -> Dictionary:
	return Grants._bundle_definition_for(entries, Runtime._execution_policy(Runtime.CURRENT_SAVE_VERSION), Runtime.CURRENT_SAVE_VERSION, parsed, id)


func _test_current() -> void:
	for fixture: Dictionary in FIXTURES:
		var entry := TreeData.stat_entry(fixture.node, fixture.index)
		var parsed := Runtime.line_effect(entry.raw_line, Runtime.CURRENT_SAVE_VERSION)
		check(entry.raw_line == fixture.line and entry.node_id == fixture.node and entry.stat_index == fixture.index,
			"exact approved compact source entry: " + fixture.node)
		check(parsed.supported and parsed.grants == [{"stat":fixture.stat,"mode":"increased","value":fixture.value}],
			"current player parser is typed numeric authority: " + fixture.node)
		check(entry.source_version == "3.29.1" and entry.source_hash == TreeData.SOURCE_SHA256, "actual pinned source version/hash retained")
	var capacity := Grants.resolve(CAPACITY)
	var entry := TreeData.stat_entry("58218", 0)
	check(capacity.ok and capacity.stats == {} and capacity.capacity_increased == {"max_shield":0.08}, "capacity supplies only increased shield capacity")
	check(capacity.definition.name == "辉壁储盾" and capacity.definition.source_refs == [entry]
		and capacity.definition.source_entry == entry and capacity.definition.source_line == entry.raw_line, "capacity exact single-entry authority")
	check(capacity.definition.typed_grants == Runtime.line_effect(entry.raw_line).grants, "capacity retains current parser grant")
	var recovery := Grants.resolve(RECOVERY)
	var entries := _entries()
	var parsed := _parsed(entries)
	check(recovery.ok and recovery.stats == {"shield_recharge_rate_increased":0.10}
		and recovery.capacity_increased == {"max_shield":0.04}, "Recovery delivers both typed channels atomically")
	var definition: Dictionary = recovery.definition
	check(definition.name == "辉壁复苏" and definition.source_refs == entries and definition.source_entries == entries,
		"Recovery full authority contains both exact compact entries in admitted order")
	check(definition.source_entry == entries[0] and definition.source_entry_scope == "first_entry_only",
		"compatibility first-entry field explicitly does not claim whole-bundle authority")
	check(definition.source_line == entries[0].raw_line + "\n" + entries[1].raw_line
		and definition.typed_grants == parsed[0].grants + parsed[1].grants, "both source lines and raw typed grants retained in known order")
	check(definition.source_policy == Runtime._execution_policy(Runtime.CURRENT_SAVE_VERSION)
		and definition.source_save_version == Runtime.CURRENT_SAVE_VERSION, "bundle shares current runtime execution identity")
	check(definition.stats == recovery.stats and definition.capacity_increased == recovery.capacity_increased,
		"resolved channels exactly match validated definition")
	check(not recovery.stats.has("shield_recharge_start_faster") and not recovery.stats.has("max_shield")
		and not recovery.stats.has("armour_increased"), "no faster start, flat capacity, armour, or node siblings")


func _test_detached() -> void:
	for id: String in [CAPACITY, RECOVERY]:
		var original := Grants.resolve(id)
		var changed := Grants.resolve(id)
		changed.stats["unexpected"] = 9.0
		changed.capacity_increased.clear()
		changed.definition.stats.clear()
		changed.definition.capacity_increased.clear()
		changed.definition.typed_grants[0].value = 9.0
		changed.definition.source_entry.clear()
		for entry: Dictionary in changed.definition.source_refs: entry.clear()
		if id == RECOVERY:
			changed.definition.source_entries[1].clear()
		check(var_to_bytes(Grants.resolve(id)) == var_to_bytes(original), "nested resolve results cannot mutate cache: " + id)
		var definition := Grants.get_definition(id)
		definition.typed_grants.clear()
		definition.source_refs.clear()
		definition.capacity_increased.clear()
		if id == RECOVERY: definition.source_entries.clear()
		check(var_to_bytes(Grants.get_definition(id)) == var_to_bytes(original.definition), "public definition is fully detached: " + id)


func _test_single_boundary() -> void:
	var entry := TreeData.stat_entry("58218", 0)
	var parsed := Runtime.line_effect(entry.raw_line)
	var policy := Runtime._execution_policy(Runtime.CURRENT_SAVE_VERSION)
	for value: Variant in [0, 0.0, 2, 1e308]:
		var effect := parsed.duplicate(true)
		effect.grants[0].value = value
		var result := Grants._definition_for(entry, policy, Runtime.CURRENT_SAVE_VERSION, effect, CAPACITY)
		check(result.ok and result.definition.typed_grants == effect.grants
			and result.definition.capacity_increased == {"max_shield":float(value)}, "finite nonnegative scalar preserved without monster conversion")
	for value: Variant in [-0.01, NAN, INF, -INF, true, "0.08", null]:
		var effect := parsed.duplicate(true)
		effect.grants[0].value = value
		check(not Grants._definition_for(entry, policy, Runtime.CURRENT_SAVE_VERSION, effect, CAPACITY).ok, "invalid capacity scalar rejected")
	for change: Dictionary in [{"stat":"max_health"}, {"mode":"flat"}, {"condition":"moving"}]:
		var effect := parsed.duplicate(true)
		effect.grants[0].merge(change, true)
		check(not Grants._definition_for(entry, policy, Runtime.CURRENT_SAVE_VERSION, effect, CAPACITY).ok, "non-admitted capacity effect rejected")
	check(not Grants._definition_for(_entries()[0], policy, Runtime.CURRENT_SAVE_VERSION, _parsed(_entries())[0], RECOVERY).ok,
		"single-entry helper cannot admit a partial Recovery bundle")


func _test_bundle_boundary() -> void:
	var entries := _entries()
	var parsed := _parsed(entries)
	for malformed: Variant in [null, {}, [], [entries[0]], [entries[0], entries[1], entries[1]], [entries[1], entries[0]], [entries[0], null]]:
		_invalid(_compile(malformed, parsed), "incomplete, reversed, or malformed authority rejects whole bundle")
	for malformed: Variant in [null, {}, [], [parsed[0]], [parsed[0], parsed[1], parsed[1]]]:
		_invalid(_compile(entries, malformed), "exactly two parser results required")
	_invalid(_compile(entries, parsed, CAPACITY), "single-entry ID cannot use bundle helper")
	_invalid(_compile(entries, parsed, "unknown"), "unknown bundle ID rejected")
	for index in range(2):
		for malformed: Variant in [null, [], {}, {"supported":false,"grants":parsed[index].grants},
				{"supported":1,"grants":parsed[index].grants}, {"supported":true,"grants":null},
				{"supported":true,"grants":[]}, {"supported":true,"grants":[null]},
				{"supported":true,"grants":parsed[index].grants + parsed[index].grants}]:
			var changed := parsed.duplicate(true)
			changed[index] = malformed
			_invalid(_compile(entries, changed), "either malformed parser result rejects whole bundle")
		for change: Dictionary in [{"stat":"shield_recharge_start_faster"}, {"stat":"armour_increased"},
				{"stat":"max_health"}, {"mode":"flat"}, {"mode":"more"}, {"mode":1},
				{"value":-0.01}, {"value":NAN}, {"value":INF}, {"value":-INF}, {"value":true},
				{"value":"0.1"}, {"value":null}, {"condition":"moving"}]:
			var changed := parsed.duplicate(true)
			changed[index].grants[0].merge(change, true)
			_invalid(_compile(entries, changed), "either wrong effect or nonfinite scalar rejects both channels")
		for field: String in entries[index]:
			var changed := entries.duplicate(true)
			changed[index].erase(field)
			_invalid(_compile(changed, parsed), "missing metadata from either entry rejects bundle: " + field)
		for change: Dictionary in [{"node_id":"58218"}, {"stat_index":0}, {"stat_index":1.0},
				{"source_hash":"z".repeat(64)}, {"source_commit":"z".repeat(40)}, {"raw_line":false},
				{"source_hash":"a".repeat(64)}, {"source_version":"different-generation"},
				{"source_commit":"b".repeat(40)}, {"source_url":"https://example.invalid/different"}]:
			var changed := entries.duplicate(true)
			changed[index].merge(change, true)
			_invalid(_compile(changed, parsed), "malformed or mixed-generation provenance rejects bundle")
		for value: Variant in [0, 0.0, 2, 1e308]:
			var changed := parsed.duplicate(true)
			changed[index].grants[0].value = value
			var result := _compile(entries, changed)
			check(result.ok and result.definition.typed_grants == changed[0].grants + changed[1].grants,
				"finite zero and large scalar stay unscaled parser grants")


func _warm() -> Dictionary:
	var definitions := {}
	for id: String in Grants.IDS:
		Grants.resolve(id)
		definitions[id] = Grants._cached_definitions[id]
	return definitions


func _test_cache() -> void:
	var original := _warm()
	var keys := Grants._cache_keys.duplicate(true)
	for iteration in range(4):
		for id: String in Grants.IDS: Grants.resolve(id)
	for id: String in Grants.IDS:
		check(is_same(original[id], Grants._cached_definitions[id]) and keys[id] == Grants._cache_keys[id], "alternating cache identity independent: " + id)
	check(Grants._cached_definitions.size() == 5 and Grants._cache_keys.size() == 5, "at most five validated definitions")
	for id: String in ["", "source_aegis", "source_aegis_capacity.extra", "aegis_recovery", "source_6949"]:
		var failed := Grants.resolve(id)
		check(not Grants.owns(id) and not failed.ok and failed.stats.is_empty() and failed.definition.is_empty(), "only exact IDs admitted")
		check(Grants._cached_definitions.size() == 5 and Grants._cache_keys.size() == 5, "unknown IDs do not grow or evict cache")
	var entries := _entries()
	var policy := Runtime._execution_policy(Runtime.CURRENT_SAVE_VERSION)
	check(Grants._bundle_key(entries, policy + 1, Runtime.CURRENT_SAVE_VERSION) != keys[RECOVERY], "policy changes bundle cache identity")
	check(Grants._bundle_key(entries, policy, Runtime.CURRENT_SAVE_VERSION + 1) != keys[RECOVERY], "save version changes bundle cache identity")
	for index in range(2):
		for field: String in entries[index]:
			var changed := entries.duplicate(true)
			changed[index][field] = 99 if field == "stat_index" else str(entries[index][field]) + " changed"
			check(Grants._bundle_key(changed, policy, Runtime.CURRENT_SAVE_VERSION) != keys[RECOVERY], "both compact entries entirely participate in key: " + field)


func _test_live_changes() -> void:
	for fixture: Dictionary in FIXTURES:
		var id := CAPACITY if fixture.node == "58218" else RECOVERY
		var original_stats: Array = TreeData._nodes[fixture.node].stats.duplicate(true)
		var baseline := Grants.resolve(id)
		var line := "12% increased maximum Energy Shield" if fixture.stat == "max_shield" else "25% increased Energy Shield Recharge Rate"
		TreeData._nodes[fixture.node].stats[fixture.index] = line
		var parsed := Runtime.line_effect(line)
		var changed := Grants.resolve(id)
		check(changed.ok and changed.definition.source_line.contains(line), "changed approved source line is reparsed")
		check((changed.capacity_increased if fixture.stat == "max_shield" else changed.stats)[fixture.stat] == parsed.grants[0].value,
			"changed parser scalar reaches only its typed channel")
		var zero_line := "0% increased maximum Energy Shield" if fixture.stat == "max_shield" else "0% increased Energy Shield Recharge Rate"
		TreeData._nodes[fixture.node].stats[fixture.index] = zero_line
		var zero := Grants.resolve(id)
		check(zero.ok and (zero.capacity_increased if fixture.stat == "max_shield" else zero.stats)[fixture.stat] == 0.0, "zero current-source scalar is valid")
		var overflow_line := "9".repeat(400) + ("% increased maximum Energy Shield" if fixture.stat == "max_shield" else "% increased Energy Shield Recharge Rate")
		for rejected_line: String in ["unsupported", "10% increased Armour", "15% faster start of Energy Shield Recharge",
				"+5 to maximum Energy Shield", fixture.line + " while moving", fixture.line + "\n10% increased Damage", overflow_line]:
			TreeData._nodes[fixture.node].stats = original_stats.duplicate(true)
			var unaffected := _warm()
			TreeData._nodes[fixture.node].stats[fixture.index] = rejected_line
			_live_failure(id, Grants.resolve(id), unaffected, "either invalid current source atomically rejects both channels")
		TreeData._nodes[fixture.node].stats = original_stats.duplicate(true)
		var unaffected := _warm()
		TreeData._nodes[fixture.node].stats = []
		_live_failure(id, Grants.resolve(id), unaffected, "missing source never serves a prior complete or partial result")
		TreeData._nodes[fixture.node].stats = original_stats
		check(var_to_bytes(Grants.resolve(id)) == var_to_bytes(baseline), "restored source recovers original complete result")
	# Non-admitted sibling values are deliberately not part of the grant or key.
	for fixture: Dictionary in [{"node":"58218","index":1,"id":CAPACITY}, {"node":"21929","index":0,"id":RECOVERY}, {"node":"6949","index":0,"id":RECOVERY}]:
		var original_line: String = TreeData._nodes[fixture.node].stats[fixture.index]
		var before := Grants.resolve(fixture.id)
		var cache: Dictionary = Grants._cached_definitions[fixture.id]
		TreeData._nodes[fixture.node].stats[fixture.index] = "999% faster start of Energy Shield Recharge"
		check(var_to_bytes(Grants.resolve(fixture.id)) == var_to_bytes(before)
			and is_same(cache, Grants._cached_definitions[fixture.id]), "sibling stats never enter authority or cache identity")
		TreeData._nodes[fixture.node].stats[fixture.index] = original_line


func _test_metadata() -> void:
	var source: Dictionary = TreeData._data.source.duplicate(true)
	for change: Dictionary in [{"version":"fixture-version"}, {"data_sha256":"a".repeat(64)},
			{"commit":"b".repeat(40)}, {"data_url":"https://example.invalid/current-source"}]:
		var old := _warm()
		var keys := Grants._cache_keys.duplicate(true)
		TreeData._data.source = source.duplicate(true)
		TreeData._data.source.merge(change, true)
		for id: String in Grants.IDS:
			check(Grants.resolve(id).ok and keys[id] != Grants._cache_keys[id]
				and not is_same(old[id], Grants._cached_definitions[id]), "actual source metadata invalidates each independent record")
		check(Grants._cached_definitions.size() == 5 and Grants._cache_keys.size() == 5, "metadata generations remain bounded to five cache entries")
	for change: Dictionary in [{"data_sha256":"z".repeat(64)}, {"data_sha256":"a".repeat(63)},
			{"commit":""}, {"version":false}, {"data_url":null}]:
		TreeData._data.source = source.duplicate(true)
		var unaffected := _warm()
		TreeData._data.source.merge(change, true)
		_live_failure(RECOVERY, Grants.resolve(RECOVERY), unaffected, "invalid current metadata evicts only requested Recovery entry")
	TreeData._data.source = source
	_warm()


func _test_read_only_rng(source_before: PackedByteArray) -> void:
	seed(760076)
	var expected := randi()
	seed(760076)
	for id: String in Grants.IDS: Grants.resolve(id)
	check(randi() == expected, "source resolution consumes no global RNG")
	check(var_to_bytes([TreeData._data, TreeData._nodes]) == source_before, "source data and node state are byte-identical after resolution and restored fixtures")
	var code := FileAccess.get_file_as_string("res://scripts/mechanics/source_monster_grants.gd")
	check(not code.contains("Data.node(") and not code.contains("Data.nodes(") and not code.contains("node_effect(")
		and not code.contains("FileAccess") and not code.contains("JSON.parse"), "adapter never allocates nodes or reads/copies the whole tree")
	check(not code.contains("preload(\"res://scripts/passives/source_tree_runtime.gd\")"), "runtime still loads lazily to avoid registry cycle")
	check(not code.contains("3.12") and not code.contains("1.56") and not code.contains("0.4225"), "monster supply amounts do not enter shared source adapter")


func _invalid(result: Dictionary, label: String) -> void:
	check(not result.ok and not result.reason.is_empty() and result.definition.is_empty()
		and not result.has("capacity_increased") and not result.has("stats"), label)


func _live_failure(id: String, result: Dictionary, unaffected: Dictionary, label: String) -> void:
	check(not result.ok and not result.reason.is_empty() and result.stats.is_empty() and result.definition.is_empty()
		and not result.has("capacity_increased") and not Grants._cached_definitions.has(id) and not Grants._cache_keys.has(id), label)
	for other: String in unaffected:
		if other == id: continue
		check(is_same(unaffected[other], Grants._cached_definitions[other]), "failure preserves unrelated cached definition: " + other)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
