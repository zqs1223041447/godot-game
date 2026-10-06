class_name SourceMonsterGrants
extends RefCounted
## Explicit source-stat admission, not node/ascendancy allocation. Runtime parsing
## is the only numeric authority; unsupported or changed effects fail closed.
const Data = preload("res://scripts/passives/source_tree_data.gd")
const ID := "source_gale_stride"
const NODE_ID := "63417"
const STAT_INDEX := 1
const RECOVERY_ID := "source_aegis_recovery"
const IDS: Array[String] = [ID, "source_ember_power", "source_grove_vitality", "source_aegis_capacity", RECOVERY_ID]
# Admit exact typed source entries, never whole nodes or their sibling effects.
# Values are deliberately absent: the current source parser supplies them.
const _ADMISSIONS: Dictionary = {
	ID: {"node_id":NODE_ID,"stat_index":STAT_INDEX,"name":"流岚疾行",
		"stat":"move_speed_increased","mode":"increased","capacity":false},
	"source_ember_power": {"node_id":"13219","stat_index":0,"name":"烬火威力",
		"stat":"global_increased","mode":"increased","capacity":false},
	"source_grove_vitality": {"node_id":"52282","stat_index":0,"name":"苍林生机",
		"stat":"max_health","mode":"increased","capacity":true},
	"source_aegis_capacity": {"node_id":"58218","stat_index":0,"name":"辉壁储盾",
		"stat":"max_shield","mode":"increased","capacity":true},
	RECOVERY_ID: {"name":"辉壁复苏","entries":[
		{"node_id":"21929","stat_index":1,"stat":"max_shield","mode":"increased","capacity":true},
		{"node_id":"6949","stat_index":1,"stat":"shield_recharge_rate_increased","mode":"increased","capacity":false},
	]},
}
# Runtime depends on the registry through jewels. Load it only after that class
# graph has initialized, rather than introducing a registry preload cycle.
static var _runtime: Script
static var _cache_keys: Dictionary = {}
static var _cached_definitions: Dictionary = {}


static func owns(id: String) -> bool:
	return _ADMISSIONS.has(id)


static func get_definition(id: String) -> Dictionary:
	return resolve(id).definition


static func resolve(id: String) -> Dictionary:
	if not owns(id): return _failure("Unknown source monster mechanism: " + id, id)
	if id == RECOVERY_ID: return _resolve_bundle(id)
	var admission: Dictionary = _ADMISSIONS[id]
	var entry := Data.stat_entry(admission.node_id, admission.stat_index)
	var invalid := _entry_error(entry, id)
	if not invalid.is_empty(): return _failure(invalid, id)
	if _runtime == null:
		_runtime = load("res://scripts/passives/source_tree_runtime.gd")
	if _runtime == null: return _failure("Source tree runtime unavailable", id)
	var save_version: int = _runtime.CURRENT_SAVE_VERSION
	var policy: int = _runtime._execution_policy(save_version)
	var key := _entry_key(entry, policy, save_version)
	if key != _cache_keys.get(id, PackedByteArray()) or not _cached_definitions.has(id):
		var parsed: Variant = _runtime.line_effect(entry.raw_line, save_version)
		var compiled := _definition_for(entry, policy, save_version, parsed, id)
		if not compiled.ok: return _failure(compiled.reason, id)
		# At most one validated definition per exact admission (five total). Alternating
		# IDs reuse independent entries; failures and scaled actors are not cached.
		_cache_keys[id] = key
		_cached_definitions[id] = compiled.definition.duplicate(true)
	var definition: Dictionary = _cached_definitions[id]
	var result := {"ok":true,"reason":"","stats":definition.stats.duplicate(true),
		"definition":definition.duplicate(true)}
	if definition.has("capacity_increased"):
		result.capacity_increased = definition.capacity_increased.duplicate(true)
	return result


static func _entry_key(entry: Dictionary, policy: int, save_version: int) -> PackedByteArray:
	# Compact entry includes actual version/hash/commit, node/index and raw line.
	return var_to_bytes([entry, policy, save_version])


static func _entry_error(entry: Dictionary, id: String = ID) -> String:
	if not owns(id): return "Unknown source monster mechanism: " + id
	var admission: Dictionary = _ADMISSIONS[id]
	if admission.has("entries"): return "Source monster bundle requires all approved entries"
	return _single_entry_error(entry, admission)


static func _single_entry_error(entry: Dictionary, admission: Dictionary) -> String:
	if entry.is_empty(): return "Source monster stat entry unavailable"
	if not entry.get("node_id") is String or entry.node_id != admission.node_id or not entry.get("stat_index") is int or entry.stat_index != admission.stat_index:
		return "Source monster stat entry is not the approved node/index"
	for field: String in ["raw_line", "node_name", "source_version", "source_hash", "source_commit", "source_url"]:
		if not entry.get(field) is String or entry[field].is_empty():
			return "Source monster stat entry missing identity: " + field
	if entry.source_hash.length() != 64 or not entry.source_hash.is_valid_hex_number(false) \
			or entry.source_commit.length() != 40 or not entry.source_commit.is_valid_hex_number(false):
		return "Source monster stat entry has invalid source hash/commit"
	return ""


## Pure boundary validation. Tests can supply malformed parser results here;
## production resolution always obtains both entry and effect from source APIs.
static func _definition_for(entry: Dictionary, policy: int, save_version: int, parsed: Variant, id: String = ID) -> Dictionary:
	var invalid := _entry_error(entry, id)
	if not invalid.is_empty(): return {"ok":false,"reason":invalid,"definition":{}}
	if not parsed is Dictionary or not parsed.get("supported") is bool or not parsed.supported:
		return {"ok":false,"reason":"Source monster stat entry is unsupported","definition":{}}
	var grants: Variant = parsed.get("grants")
	if not grants is Array or grants.size() != 1:
		return {"ok":false,"reason":"Source monster stat entry must produce exactly one typed grant","definition":{}}
	var grant: Variant = grants[0]
	var admission: Dictionary = _ADMISSIONS[id]
	if not grant is Dictionary or grant.size() != 3 or not grant.get("stat") is String or not grant.get("mode") is String \
			or grant.stat != admission.stat or grant.mode != admission.mode:
		var reason := "Source monster stat entry effect does not match movement-speed increase" if id == ID else "Source monster stat entry effect does not match the approved stat/mode"
		return {"ok":false,"reason":reason,"definition":{}}
	var value: Variant = grant.get("value")
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
		var reason := "Source monster movement-speed increase must be finite and nonnegative" if id == ID else "Source monster increase must be finite and nonnegative"
		return {"ok":false,"reason":reason,"definition":{}}
	var stats: Dictionary = {} if admission.capacity else {admission.stat:float(value)}
	var definition := {"id":id,"name":admission.name,"stats":stats,
		"source_refs":[entry.duplicate(true)],"source_entry":entry.duplicate(true),
		"source_policy":policy,"source_save_version":save_version,"source_line":entry.raw_line,
		"policy_version":"source-tree:%s:policy:%d" % [entry.source_version, policy]}
	# Preserve the v74 Gale wire shape, including absence of empty new fields.
	if id != ID:
		definition.typed_grants = grants.duplicate(true)
	if admission.capacity:
		definition.capacity_increased = {admission.stat:float(value)}
	return {"ok":true,"reason":"","definition":definition}


static func _resolve_bundle(id: String) -> Dictionary:
	var entries: Array = []
	for admission: Dictionary in _ADMISSIONS[id].entries:
		entries.append(Data.stat_entry(admission.node_id, admission.stat_index))
	var invalid := _bundle_entries_error(entries, id)
	if not invalid.is_empty(): return _failure(invalid, id)
	if _runtime == null:
		_runtime = load("res://scripts/passives/source_tree_runtime.gd")
	if _runtime == null: return _failure("Source tree runtime unavailable", id)
	var save_version: int = _runtime.CURRENT_SAVE_VERSION
	var policy: int = _runtime._execution_policy(save_version)
	var key := _bundle_key(entries, policy, save_version)
	if key != _cache_keys.get(id, PackedByteArray()) or not _cached_definitions.has(id):
		var parsed: Array = []
		for entry: Dictionary in entries:
			parsed.append(_runtime.line_effect(entry.raw_line, save_version))
		var compiled := _bundle_definition_for(entries, policy, save_version, parsed, id)
		if not compiled.ok: return _failure(compiled.reason, id)
		# Commit both validated grants together. No partial result enters the cache.
		_cache_keys[id] = key
		_cached_definitions[id] = compiled.definition.duplicate(true)
	var definition: Dictionary = _cached_definitions[id]
	return {"ok":true,"reason":"","stats":definition.stats.duplicate(true),
		"definition":definition.duplicate(true),"capacity_increased":definition.capacity_increased.duplicate(true)}


static func _bundle_key(entries: Array, policy: int, save_version: int) -> PackedByteArray:
	# Both compact entries include their actual source identities and raw lines.
	return var_to_bytes([entries, policy, save_version])


static func _bundle_entries_error(entries: Variant, id: String = RECOVERY_ID) -> String:
	if not owns(id): return "Unknown source monster mechanism: " + id
	var admission: Dictionary = _ADMISSIONS[id]
	if not admission.has("entries") or not entries is Array or entries.size() != admission.entries.size():
		return "Source monster bundle requires all approved entries"
	for index in range(entries.size()):
		if not entries[index] is Dictionary: return "Source monster bundle entry is malformed"
		var invalid := _single_entry_error(entries[index], admission.entries[index])
		if not invalid.is_empty(): return invalid
		for field: String in ["source_version", "source_hash", "source_commit", "source_url"]:
			if entries[index][field] != entries[0][field]:
				return "Source monster bundle entries must share one source identity"
	return ""


## Pure atomic boundary for fixture validation. Production always parses both
## current compact entries through the same player runtime and execution policy.
static func _bundle_definition_for(entries: Variant, policy: int, save_version: int, parsed: Variant, id: String = RECOVERY_ID) -> Dictionary:
	var invalid := _bundle_entries_error(entries, id)
	if not invalid.is_empty(): return {"ok":false,"reason":invalid,"definition":{}}
	if not parsed is Array or parsed.size() != entries.size():
		return {"ok":false,"reason":"Source monster bundle requires every parsed entry","definition":{}}
	var admission: Dictionary = _ADMISSIONS[id]
	var stats := {}
	var capacity_increased := {}
	var typed_grants: Array = []
	var lines: PackedStringArray = []
	for index in range(entries.size()):
		var effect: Variant = parsed[index]
		if not effect is Dictionary or not effect.get("supported") is bool or not effect.supported:
			return {"ok":false,"reason":"Source monster bundle entry is unsupported","definition":{}}
		var grants: Variant = effect.get("grants")
		if not grants is Array or grants.size() != 1:
			return {"ok":false,"reason":"Source monster bundle entry must produce exactly one typed grant","definition":{}}
		var grant: Variant = grants[0]
		var expected: Dictionary = admission.entries[index]
		if not grant is Dictionary or grant.size() != 3 or not grant.get("stat") is String or not grant.get("mode") is String \
				or grant.stat != expected.stat or grant.mode != expected.mode:
			return {"ok":false,"reason":"Source monster bundle entry effect does not match the approved stat/mode","definition":{}}
		var value: Variant = grant.get("value")
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
			return {"ok":false,"reason":"Source monster bundle increase must be finite and nonnegative","definition":{}}
		if expected.capacity: capacity_increased[expected.stat] = float(value)
		else: stats[expected.stat] = float(value)
		typed_grants.append(grant.duplicate(true))
		lines.append(entries[index].raw_line)
	var definition := {"id":id,"name":admission.name,"stats":stats,
		"source_refs":entries.duplicate(true),"source_entry":entries[0].duplicate(true),
		"source_policy":policy,"source_save_version":save_version,"source_line":"\n".join(lines),
		"policy_version":"source-tree:%s:policy:%d" % [entries[0].source_version, policy],
		"typed_grants":typed_grants,"capacity_increased":capacity_increased,
		"source_entries":entries.duplicate(true),"source_entry_scope":"first_entry_only"}
	return {"ok":true,"reason":"","definition":definition}


static func _failure(reason: String, id: String = "") -> Dictionary:
	# A rejected current source must never leave a prior valid value as fallback.
	# A failure for one admission must not evict unrelated validated entries.
	_cache_keys.erase(id)
	_cached_definitions.erase(id)
	return {"ok":false,"reason":reason,"stats":{},"definition":{}}
