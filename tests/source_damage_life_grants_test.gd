extends SceneTree
const Grants = preload("res://scripts/mechanics/source_monster_grants.gd")
const TreeData = preload("res://scripts/passives/source_tree_data.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const CASES: Array[Dictionary] = [
	{"id":"source_ember_power","node":"13219","index":0,"line":"10% increased Damage",
		"stat":"global_increased","value":0.10,"capacity":false},
	{"id":"source_grove_vitality","node":"52282","index":0,"line":"5% increased maximum Life",
		"stat":"max_health","value":0.05,"capacity":true},
]
var checks := 0
var failures := 0


func _initialize() -> void:
	check(TreeData.ready(), "pinned source available")
	check(Grants.IDS == ["source_gale_stride", "source_ember_power", "source_grove_vitality"],
		"exact ordered three-source admission list")
	check(Grants.ID == "source_gale_stride" and Grants.NODE_ID == "63417" and Grants.STAT_INDEX == 1,
		"v74 constants retain their identity")
	_test_gale_bytes()
	for fixture: Dictionary in CASES:
		_test_current(fixture)
		_test_invalid_typed_grants(fixture)
	_test_cache_independence()
	_test_source_changes()
	_test_gale_bytes()
	print("Source damage/life grants: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_current(fixture: Dictionary) -> void:
	var entry := TreeData.stat_entry(fixture.node, fixture.index)
	var parsed := Runtime.line_effect(entry.raw_line, Runtime.CURRENT_SAVE_VERSION)
	var result := Grants.resolve(fixture.id)
	check(Grants.owns(fixture.id) and result.ok and result.reason.is_empty(), "admitted source resolves: " + fixture.id)
	check(entry.raw_line == fixture.line and parsed.supported and parsed.grants.size() == 1,
		"exact current source line and single current typed grant: " + fixture.id)
	check(parsed.grants == [{"stat":fixture.stat,"mode":"increased","value":fixture.value}],
		"current parser confirms expected source semantics: " + fixture.id)
	var definition: Dictionary = result.definition
	check(definition.typed_grants == parsed.grants and definition.id == fixture.id,
		"raw typed grant and increased mode retained: " + fixture.id)
	check(definition.source_entry == entry and definition.source_refs == [entry]
		and definition.source_line == fixture.line, "exact detached single-entry provenance: " + fixture.id)
	check(definition.source_policy == Runtime._execution_policy(Runtime.CURRENT_SAVE_VERSION)
		and definition.source_save_version == Runtime.CURRENT_SAVE_VERSION
		and definition.policy_version == "source-tree:%s:policy:%d" % [entry.source_version, definition.source_policy],
		"current source execution identity retained: " + fixture.id)
	if fixture.capacity:
		check(result.stats.is_empty() and definition.stats.is_empty(), "Life percent never becomes flat max_health")
		check(result.capacity_increased == {fixture.stat:parsed.grants[0].value}
			and definition.capacity_increased == result.capacity_increased, "Life increased capacity has its own typed channel")
	else:
		check(result.stats == {fixture.stat:parsed.grants[0].value} and definition.stats == result.stats,
			"Damage increase exactly matches the current parser")
		check(not result.has("capacity_increased") and not definition.has("capacity_increased"),
			"Damage has no capacity grants")
	var original := result.duplicate(true)
	result.stats["unexpected"] = 999.0
	result.definition.stats["unexpected"] = 999.0
	result.definition.typed_grants[0].mode = "flat"
	result.definition.typed_grants[0].value = 999.0
	result.definition.source_refs[0].clear()
	result.definition.source_entry.clear()
	if fixture.capacity:
		result.capacity_increased.max_health = 999.0
		result.definition.capacity_increased.max_health = 999.0
	check(var_to_bytes(Grants.resolve(fixture.id)) == var_to_bytes(original),
		"nested result mutation cannot poison cached grant: " + fixture.id)
	var detached := Grants.get_definition(fixture.id)
	detached.typed_grants.clear()
	detached.source_refs.clear()
	detached.stats.clear()
	if fixture.capacity: detached.capacity_increased.clear()
	check(var_to_bytes(Grants.get_definition(fixture.id)) == var_to_bytes(original.definition),
		"public definition is fully detached: " + fixture.id)
	# These original sibling lines are deliberately not part of either admission.
	if fixture.capacity:
		check(TreeData.stat_entry("52282", 1).raw_line == "Transfiguration of Body", "Transfiguration sibling remains ungranted")
	else:
		check(TreeData.stat_entry("13219", 1).raw_line == "14% increased Evasion Rating"
			and TreeData.stat_entry("13219", 2).raw_line == "5% increased maximum Energy Shield",
			"evasion and shield siblings remain ungranted")


func _test_invalid_typed_grants(fixture: Dictionary) -> void:
	var entry := TreeData.stat_entry(fixture.node, fixture.index)
	var parsed := Runtime.line_effect(entry.raw_line, Runtime.CURRENT_SAVE_VERSION)
	for invalid: Variant in [null, [], {}, {"supported":false,"grants":parsed.grants},
			{"supported":1,"grants":parsed.grants}, {"supported":true,"grants":null},
			{"supported":true,"grants":[]}, {"supported":true,"grants":[null]},
			{"supported":true,"grants":[parsed.grants[0], parsed.grants[0]]}]:
		_expect_invalid(fixture.id, entry, invalid, "malformed or multiple effects rejected")
	for change: Dictionary in [{"stat":"damage"}, {"stat":"max_shield"}, {"stat":"evasion_increased"},
			{"stat":"transfiguration_of_body"}, {"stat":"move_speed_increased"}, {"mode":"flat"},
			{"mode":"more"}, {"mode":1}, {"value":-0.01}, {"value":NAN}, {"value":INF},
			{"value":true}, {"value":"0.1"}, {"value":null}, {"condition":"moving"}]:
		var invalid_grant: Dictionary = parsed.grants[0].duplicate(true)
		invalid_grant.merge(change, true)
		_expect_invalid(fixture.id, entry, {"supported":true,"grants":[invalid_grant]}, "non-admitted typed stat/mode/scalar rejected")
	for field: String in entry:
		var invalid_entry := entry.duplicate(true)
		invalid_entry.erase(field)
		_expect_invalid(fixture.id, invalid_entry, parsed, "missing provenance rejected: " + field)
	for change: Dictionary in [{"node_id":"63417"}, {"stat_index":1}, {"stat_index":0.0},
			{"source_hash":"z".repeat(64)}, {"source_commit":"z".repeat(40)}, {"raw_line":false}]:
		var invalid_entry := entry.duplicate(true)
		invalid_entry.merge(change, true)
		_expect_invalid(fixture.id, invalid_entry, parsed, "wrong or malformed source identity rejected")
	var other: Dictionary = CASES[1] if fixture.id == CASES[0].id else CASES[0]
	_expect_invalid(fixture.id, TreeData.stat_entry(other.node, other.index), parsed, "another approved source is not interchangeable")
	for value: Variant in [0, 0.0, 0.25, 2]:
		var grant: Dictionary = parsed.grants[0].duplicate(true)
		grant.value = value
		var compiled := Grants._definition_for(entry, Runtime._execution_policy(Runtime.CURRENT_SAVE_VERSION),
			Runtime.CURRENT_SAVE_VERSION, {"supported":true,"grants":[grant]}, fixture.id)
		check(compiled.ok and compiled.definition.typed_grants == [grant], "valid raw numeric grants preserve their parser values")


func _test_cache_independence() -> void:
	var originals := {}
	var keys := {}
	for id: String in Grants.IDS:
		Grants.resolve(id)
		originals[id] = Grants._cached_definitions[id]
		keys[id] = Grants._cache_keys[id].duplicate()
	for iteration in range(100):
		for id: String in Grants.IDS:
			Grants.resolve(id)
	for id: String in Grants.IDS:
		check(is_same(originals[id], Grants._cached_definitions[id]) and keys[id] == Grants._cache_keys[id],
			"alternating IDs preserve independent cache identity: " + id)
	check(Grants._cached_definitions.size() == 3 and Grants._cache_keys.size() == 3, "cache bounded to three validated static entries")
	for id: String in ["", "source_ember_power.extra", "source_grove", "source_13219", "source_evasion",
			"source_transfiguration_of_body", "ember_power", "grove_vitality"]:
		var rejected := Grants.resolve(id)
		check(not Grants.owns(id) and not rejected.ok and rejected.reason == "Unknown source monster mechanism: " + id
			and rejected.stats.is_empty() and rejected.definition.is_empty(), "exact source IDs only: " + id)
		check(Grants.get_definition(id).is_empty() and Grants._cached_definitions.size() == 3
			and Grants._cache_keys.size() == 3, "unknown IDs never grow or evict valid caches")
	for fixture: Dictionary in CASES:
		var entry := TreeData.stat_entry(fixture.node, fixture.index)
		var policy := Runtime._execution_policy(Runtime.CURRENT_SAVE_VERSION)
		check(Grants._entry_key(entry, policy + 1, Runtime.CURRENT_SAVE_VERSION) != keys[fixture.id],
			"execution policy participates in each key")
		check(Grants._entry_key(entry, policy, Runtime.CURRENT_SAVE_VERSION + 1) != keys[fixture.id],
			"save version participates in each key")
		for field: String in entry:
			var changed := entry.duplicate(true)
			changed[field] = 99 if field == "stat_index" else str(entry[field]) + " changed"
			check(Grants._entry_key(changed, policy, Runtime.CURRENT_SAVE_VERSION) != keys[fixture.id],
				"every source identity/line field participates in key: " + field)


func _test_source_changes() -> void:
	for fixture: Dictionary in CASES:
		var original_stats: Array = TreeData._nodes[fixture.node].stats.duplicate(true)
		var original := Grants.resolve(fixture.id)
		var changed_line := "12% increased maximum Life" if fixture.capacity else "25% increased Damage"
		TreeData._nodes[fixture.node].stats[fixture.index] = changed_line
		var parsed := Runtime.line_effect(changed_line, Runtime.CURRENT_SAVE_VERSION)
		var changed := Grants.resolve(fixture.id)
		check(changed.ok and changed.definition.typed_grants == parsed.grants
			and changed.definition.source_line == changed_line, "changed source line is reparsed, no copied numeric fallback")
		check((changed.capacity_increased if fixture.capacity else changed.stats) == {fixture.stat:parsed.grants[0].value},
			"changed scalar reaches only its intended channel")
		var rejected_lines: Array[String] = ["This is not an executable stat", "14% increased Evasion Rating",
			"5% increased maximum Energy Shield", "Transfiguration of Body", "+5 to maximum Life",
			"10% increased Armour and Evasion Rating", fixture.line + " while moving",
			fixture.line + "\n14% increased Evasion Rating"]
		for line: String in rejected_lines:
			TreeData._nodes[fixture.node].stats = original_stats.duplicate(true)
			Grants.resolve(fixture.id)
			var unaffected := _other_cached_definitions(fixture.id)
			TreeData._nodes[fixture.node].stats[fixture.index] = line
			var rejected := Grants.resolve(fixture.id)
			_assert_failure(fixture.id, rejected, "unsupported, compound, flat or conditional source fails closed")
			for id: String in unaffected:
				check(is_same(unaffected[id], Grants._cached_definitions[id]), "rejection preserves unrelated cache: " + id)
		TreeData._nodes[fixture.node].stats = original_stats.duplicate(true)
		Grants.resolve(fixture.id)
		TreeData._nodes[fixture.node].stats = []
		_assert_failure(fixture.id, Grants.resolve(fixture.id), "missing source entry never reuses valid result")
		TreeData._nodes[fixture.node].stats = original_stats
		check(var_to_bytes(Grants.resolve(fixture.id)) == var_to_bytes(original), "restored source recovers exact original result")
	var original_source: Dictionary = TreeData._data.source.duplicate(true)
	for change: Dictionary in [{"version":"fixture-version"}, {"data_sha256":"a".repeat(64)},
			{"commit":"b".repeat(40)}, {"data_url":"https://example.invalid/source-fixture"}]:
		TreeData._data.source = original_source.duplicate(true)
		TreeData._data.source.merge(change, true)
		for id: String in Grants.IDS:
			var old_key: PackedByteArray = Grants._cache_keys[id].duplicate()
			var old_definition: Dictionary = Grants._cached_definitions[id]
			var result := Grants.resolve(id)
			check(result.ok and old_key != Grants._cache_keys[id]
				and not is_same(old_definition, Grants._cached_definitions[id]), "source metadata change recompiles each admission: " + id)
		check(Grants._cached_definitions.size() == 3 and Grants._cache_keys.size() == 3, "metadata generations do not accumulate cache entries")
	TreeData._data.source = original_source.duplicate(true)
	TreeData._data.source.erase("commit")
	for id: String in Grants.IDS:
		_assert_failure(id, Grants.resolve(id), "missing source metadata cannot yield stale fallback")
	check(Grants._cached_definitions.is_empty() and Grants._cache_keys.is_empty(), "failed source metadata leaves no resolved stale entries")
	TreeData._data.source = original_source
	for id: String in Grants.IDS: check(Grants.resolve(id).ok, "all source entries recover after metadata restored")


func _other_cached_definitions(exclude: String) -> Dictionary:
	var result := {}
	for id: String in Grants.IDS:
		if id == exclude: continue
		Grants.resolve(id)
		result[id] = Grants._cached_definitions[id]
	return result


func _test_gale_bytes() -> void:
	var entry := TreeData.stat_entry("63417", 1)
	var parsed := Runtime.line_effect(entry.raw_line, Runtime.CURRENT_SAVE_VERSION)
	var policy := Runtime._execution_policy(Runtime.CURRENT_SAVE_VERSION)
	# Frozen successful v74 adapter construction from f2427f3. Do not derive this
	# dictionary from the new adapter; compare the entire serialized wire shape.
	var definition := {"id":"source_gale_stride","name":"流岚疾行","stats":{"move_speed_increased":float(parsed.grants[0].value)},
		"source_refs":[entry.duplicate(true)],"source_entry":entry.duplicate(true),
		"source_policy":policy,"source_save_version":Runtime.CURRENT_SAVE_VERSION,"source_line":entry.raw_line,
		"policy_version":"source-tree:%s:policy:%d" % [entry.source_version, policy]}
	var frozen := {"ok":true,"reason":"","stats":definition.stats.duplicate(true),"definition":definition.duplicate(true)}
	check(var_to_bytes(Grants.resolve("source_gale_stride")) == var_to_bytes(frozen), "full Gale resolve bytes match frozen v74 shape")
	check(var_to_bytes(Grants.get_definition("source_gale_stride")) == var_to_bytes(definition), "full Gale definition bytes match frozen v74 shape")


func _expect_invalid(id: String, entry: Dictionary, parsed: Variant, label: String) -> void:
	var result := Grants._definition_for(entry, Runtime._execution_policy(Runtime.CURRENT_SAVE_VERSION), Runtime.CURRENT_SAVE_VERSION, parsed, id)
	check(not result.ok and not result.reason.is_empty() and result.definition.is_empty(), label + ": " + id)


func _assert_failure(id: String, result: Dictionary, label: String) -> void:
	check(not result.ok and not result.reason.is_empty() and result.stats.is_empty() and result.definition.is_empty()
		and not result.has("capacity_increased") and not Grants._cached_definitions.has(id)
		and not Grants._cache_keys.has(id), label + ": " + id)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
