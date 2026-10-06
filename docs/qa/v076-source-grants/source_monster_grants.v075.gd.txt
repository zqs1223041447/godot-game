class_name SourceMonsterGrants
extends RefCounted
## Explicit source-stat admission, not node/ascendancy allocation. Runtime parsing
## is the only numeric authority; unsupported or changed effects fail closed.
const Data = preload("res://scripts/passives/source_tree_data.gd")
const ID := "source_gale_stride"
const NODE_ID := "63417"
const STAT_INDEX := 1
const IDS: Array[String] = [ID, "source_ember_power", "source_grove_vitality"]
# Admit a single typed source line, never a whole node or its sibling effects.
# Values are deliberately absent: the current source parser supplies them.
const _ADMISSIONS: Dictionary = {
	ID: {"node_id":NODE_ID,"stat_index":STAT_INDEX,"name":"流岚疾行",
		"stat":"move_speed_increased","mode":"increased","capacity":false},
	"source_ember_power": {"node_id":"13219","stat_index":0,"name":"烬火威力",
		"stat":"global_increased","mode":"increased","capacity":false},
	"source_grove_vitality": {"node_id":"52282","stat_index":0,"name":"苍林生机",
		"stat":"max_health","mode":"increased","capacity":true},
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
		# At most one validated entry per exact admission (three total). Alternating
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
	if entry.is_empty(): return "Source monster stat entry unavailable"
	var admission: Dictionary = _ADMISSIONS[id]
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


static func _failure(reason: String, id: String = "") -> Dictionary:
	# A rejected current source must never leave a prior valid value as fallback.
	# A failure for one admission must not evict unrelated validated entries.
	_cache_keys.erase(id)
	_cached_definitions.erase(id)
	return {"ok":false,"reason":reason,"stats":{},"definition":{}}
