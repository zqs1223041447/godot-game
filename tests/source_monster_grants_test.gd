extends SceneTree
const Grants = preload("res://scripts/mechanics/source_monster_grants.gd")
const TreeData = preload("res://scripts/passives/source_tree_data.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	check(TreeData.ready(), "pinned source available")
	var entry := TreeData.stat_entry("63417", 1)
	var parsed := Runtime.line_effect(entry.raw_line, Runtime.CURRENT_SAVE_VERSION)
	var policy := Runtime._execution_policy(Runtime.CURRENT_SAVE_VERSION)
	check(entry.raw_line == "4% increased Movement Speed", "exact current original source line")
	check(entry.node_id == "63417" and entry.stat_index == 1, "approved single entry identity")
	check(entry.source_version == "3.29.1" and entry.source_hash == TreeData.SOURCE_SHA256,
		"actual source version and hash retained")
	check(entry.source_commit == TreeData._data.source.commit and entry.source_url == TreeData._data.source.data_url,
		"actual pinned source commit and URL retained")
	check(TreeData.stat_entry("63417", 0).raw_line == "15% increased Armour", "other source entry remains separately readable")
	for invalid: Array in [["missing", 1], ["63417", -1], ["63417", 2], ["", 0]]:
		check(TreeData.stat_entry(invalid[0], invalid[1]).is_empty(), "invalid compact source lookup rejected")
	var result := Grants.resolve(Grants.ID)
	check(result.ok and result.reason.is_empty(), "approved source grant resolves")
	check(parsed.supported and parsed.grants.size() == 1 and result.stats == {parsed.grants[0].stat:parsed.grants[0].value},
		"live grant exactly equals current parser with no numeric copy")
	check(result.stats.size() == 1 and result.stats.has("move_speed_increased"), "only movement stat, no armour or ascendancy grants")
	check(result.definition.name == "流岚疾行" and result.definition.id == Grants.ID, "new stable content identity")
	check(result.definition.source_entry == entry and result.definition.source_refs == [entry]
		and result.definition.source_line == entry.raw_line, "precise single-entry provenance retained")
	check(result.definition.source_policy == policy and result.definition.source_save_version == Runtime.CURRENT_SAVE_VERSION,
		"current source execution policy retained")
	_test_detached_outputs(entry, result)
	_test_invalid_results(entry, parsed, policy)
	_test_cache(TreeData.stat_entry("63417", 1), policy)
	_test_compact_boundary()
	print("Source monster grants: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_detached_outputs(entry: Dictionary, result: Dictionary) -> void:
	var original := result.duplicate(true)
	entry.raw_line = "mutated"
	entry.source_hash = "mutated"
	check(TreeData.stat_entry("63417", 1) == original.definition.source_entry, "compact source return is detached")
	result.stats.clear()
	result.definition.stats.clear()
	result.definition.source_entry.clear()
	result.definition.source_refs[0].clear()
	check(Grants.resolve(Grants.ID) == original, "resolve returns cannot mutate validated cache")
	var definition := Grants.get_definition(Grants.ID)
	definition.source_refs.clear()
	definition.stats.move_speed_increased = 999.0
	check(Grants.get_definition(Grants.ID) == original.definition, "definition return is fully detached")
	for id: String in ["", "gale_stride", "source_gale_stride.extra", "source_63417", "source_armour"]:
		var unknown := Grants.resolve(id)
		check(not unknown.ok and not unknown.reason.is_empty() and unknown.stats.is_empty() and unknown.definition.is_empty(),
			"unknown source mechanism fails closed: " + id)
		check(Grants.get_definition(id).is_empty(), "unknown definition absent")


func _test_invalid_results(_entry: Dictionary, parsed: Dictionary, policy: int) -> void:
	var entry := TreeData.stat_entry("63417", 1)
	for fixture: Variant in [null, [], {}, {"supported":false,"grants":[]}, {"supported":1,"grants":parsed.grants},
			{"supported":true,"grants":null}, {"supported":true,"grants":[]},
			{"supported":true,"grants":[parsed.grants[0], parsed.grants[0]]}, {"supported":true,"grants":[null]}]:
		_expect_invalid(entry, policy, fixture, "malformed/unsupported/empty/multiple parser grants rejected")
	for grant: Dictionary in [
			{"stat":"armour_increased","mode":"increased","value":0.04},
			{"stat":"move_speed_increased","mode":"flat","value":0.04},
			{"stat":"move_speed_increased","mode":"increased","value":"0.04"},
			{"stat":"move_speed_increased","mode":"increased","value":true},
			{"stat":"move_speed_increased","mode":"increased","value":-0.01},
			{"stat":"move_speed_increased","mode":"increased","value":NAN},
			{"stat":"move_speed_increased","mode":"increased","value":INF},
			{"stat":"move_speed_increased","mode":"increased","value":0.04,"condition":"moving"}]:
		_expect_invalid(entry, policy, {"supported":true,"grants":[grant]}, "unsupported typed effect/value rejected")
	for field: String in entry:
		var missing := entry.duplicate(true)
		missing.erase(field)
		_expect_invalid(missing, policy, parsed, "missing source identity rejected: " + field)
	for change: Dictionary in [{"node_id":"5819"}, {"stat_index":0}, {"stat_index":1.0},
			{"source_hash":"z".repeat(64)}, {"source_commit":"x".repeat(40)}, {"raw_line":false}]:
		var invalid := entry.duplicate(true)
		invalid.merge(change, true)
		_expect_invalid(invalid, policy, parsed, "unapproved or malformed source identity rejected")
	var zero := {"supported":true,"grants":[{"stat":"move_speed_increased","mode":"increased","value":0.0}]}
	check(Grants._definition_for(entry, policy, Runtime.CURRENT_SAVE_VERSION, zero).ok, "finite zero is valid, not treated as missing")
	check(Grants._definition_for(entry, policy, Runtime.CURRENT_SAVE_VERSION, parsed).ok, "pure fixture checks do not alter production authority")


func _test_cache(entry: Dictionary, policy: int) -> void:
	Grants.resolve(Grants.ID)
	var first: Dictionary = Grants._cached_definitions[Grants.ID]
	var first_key: PackedByteArray = Grants._cache_keys[Grants.ID].duplicate()
	for index in range(100): Grants.resolve(Grants.ID)
	check(is_same(first, Grants._cached_definitions[Grants.ID]) and first_key == Grants._cache_keys[Grants.ID], "unchanged compact identity hits static cache")
	check(Grants._cached_definitions[Grants.ID].id == Grants.ID and Grants._cached_definitions[Grants.ID].stats.size() == 1, "Gale cache entry is one validated definition")
	check(Grants._entry_key(entry, policy + 1, Runtime.CURRENT_SAVE_VERSION) != first_key,
		"execution policy change invalidates cache key")
	check(Grants._entry_key(entry, policy, Runtime.CURRENT_SAVE_VERSION + 1) != first_key,
		"runtime save version change invalidates cache key")
	# Test-local mutation of existing private source caches, restored below. There
	# is deliberately no runtime fixture provider or global injection API.
	var original_source: Dictionary = TreeData._data.source.duplicate(true)
	for field: String in ["version", "data_sha256", "commit"]:
		TreeData._data.source = original_source.duplicate(true)
		TreeData._data.source[field] = "fixture-version" if field == "version" else ("a".repeat(64) if field == "data_sha256" else "b".repeat(40))
		var changed := Grants.resolve(Grants.ID)
		check(changed.ok and Grants._cache_keys[Grants.ID] != first_key and not is_same(first, Grants._cached_definitions[Grants.ID]),
			"actual changed source identity recompiles: " + field)
	TreeData._data.source = original_source
	var original_stats: Array = TreeData._nodes["63417"].stats.duplicate()
	TreeData._nodes["63417"].stats[1] = "8% increased Movement Speed"
	var changed_line := Grants.resolve(Grants.ID)
	var changed_effect := Runtime.line_effect(TreeData._nodes["63417"].stats[1], Runtime.CURRENT_SAVE_VERSION)
	check(changed_line.ok and changed_line.stats.move_speed_increased == changed_effect.grants[0].value
		and Grants._cache_keys[Grants.ID] != first_key, "changed raw source entry recomputes using authoritative parser")
	for rejected_line: String in ["15% increased Armour", "This is not an executable stat", "4% increased Movement Speed\n15% increased Armour"]:
		TreeData._nodes["63417"].stats[1] = rejected_line
		var rejected := Grants.resolve(Grants.ID)
		check(not rejected.ok and not rejected.reason.is_empty() and rejected.stats.is_empty() and rejected.definition.is_empty()
			and not Grants._cached_definitions.has(Grants.ID) and not Grants._cache_keys.has(Grants.ID), "changed invalid entry clears cache with no fallback")
	TreeData._nodes["63417"].stats = original_stats
	TreeData._data.source = original_source.duplicate(true)
	TreeData._data.source.erase("commit")
	check(not Grants.resolve(Grants.ID).ok and not Grants._cached_definitions.has(Grants.ID), "missing metadata rejects and does not reuse stale result")
	TreeData._data.source = original_source
	check(Grants.resolve(Grants.ID).ok and Grants._cache_keys[Grants.ID] == first_key, "restored source resolves original grant again")


func _test_compact_boundary() -> void:
	var entry := TreeData.stat_entry("63417", 1)
	check(entry.size() == 8 and not entry.has("nodes") and not entry.has("stats") and not entry.has("source"),
		"compact entry never returns full node or tree")
	var cached_nodes: Dictionary = TreeData._nodes
	var cached_tree: Dictionary = TreeData._data
	for index in range(100): TreeData.stat_entry("63417", 1)
	check(is_same(cached_nodes, TreeData._nodes) and is_same(cached_tree, TreeData._data), "compact lookup reuses existing source caches")
	var adapter_code := FileAccess.get_file_as_string("res://scripts/mechanics/source_monster_grants.gd")
	check(not adapter_code.contains("Data.node(") and not adapter_code.contains("Data.nodes(")
		and not adapter_code.contains("FileAccess") and not adapter_code.contains("JSON.parse"), "per-resolution adapter has no full-tree read/copy path")
	var data_code := FileAccess.get_file_as_string("res://scripts/passives/source_tree_data.gd")
	var getter := data_code.split("static func stat_entry(")[1].split("static func nodes()")[0]
	check(not getter.contains("node(") and not getter.contains("nodes(") and not getter.contains("FileAccess")
		and not getter.contains("_data.duplicate") and not getter.contains("_nodes.duplicate"), "compact accessor does not duplicate or reload tree")


func _expect_invalid(entry: Dictionary, policy: int, parsed: Variant, label: String) -> void:
	var rejected := Grants._definition_for(entry, policy, Runtime.CURRENT_SAVE_VERSION, parsed)
	check(not rejected.ok and not rejected.reason.is_empty() and rejected.definition.is_empty(), label)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
