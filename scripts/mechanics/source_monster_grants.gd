class_name SourceMonsterGrants
extends RefCounted
## Explicit source-stat admission, not node/ascendancy allocation. Runtime parsing
## is the only numeric authority; unsupported or changed effects fail closed.
const Data = preload("res://scripts/passives/source_tree_data.gd")
const ID := "source_gale_stride"
const NODE_ID := "63417"
const STAT_INDEX := 1
# Runtime depends on the registry through jewels. Load it only after that class
# graph has initialized, rather than introducing a registry preload cycle.
static var _runtime: Script
static var _cache_key := PackedByteArray()
static var _cached_definition: Dictionary = {}


static func get_definition(id: String) -> Dictionary:
	return resolve(id).definition


static func resolve(id: String) -> Dictionary:
	if id != ID: return _failure("Unknown source monster mechanism: " + id)
	var entry := Data.stat_entry(NODE_ID, STAT_INDEX)
	var invalid := _entry_error(entry)
	if not invalid.is_empty(): return _failure(invalid)
	if _runtime == null:
		_runtime = load("res://scripts/passives/source_tree_runtime.gd")
	if _runtime == null: return _failure("Source tree runtime unavailable")
	var save_version: int = _runtime.CURRENT_SAVE_VERSION
	var policy: int = _runtime._execution_policy(save_version)
	var key := _entry_key(entry, policy, save_version)
	if key != _cache_key or _cached_definition.is_empty():
		var parsed: Variant = _runtime.line_effect(entry.raw_line, save_version)
		var compiled := _definition_for(entry, policy, save_version, parsed)
		if not compiled.ok: return _failure(compiled.reason)
		# Exactly one validated static entry. Never cache failures or scaled actors.
		_cache_key = key
		_cached_definition = compiled.definition.duplicate(true)
	return {"ok":true,"reason":"","stats":_cached_definition.stats.duplicate(true),
		"definition":_cached_definition.duplicate(true)}


static func _entry_key(entry: Dictionary, policy: int, save_version: int) -> PackedByteArray:
	# Compact entry includes actual version/hash/commit, node/index and raw line.
	return var_to_bytes([entry, policy, save_version])


static func _entry_error(entry: Dictionary) -> String:
	if entry.is_empty(): return "Source monster stat entry unavailable"
	if not entry.get("node_id") is String or entry.node_id != NODE_ID or not entry.get("stat_index") is int or entry.stat_index != STAT_INDEX:
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
static func _definition_for(entry: Dictionary, policy: int, save_version: int, parsed: Variant) -> Dictionary:
	var invalid := _entry_error(entry)
	if not invalid.is_empty(): return {"ok":false,"reason":invalid,"definition":{}}
	if not parsed is Dictionary or not parsed.get("supported") is bool or not parsed.supported:
		return {"ok":false,"reason":"Source monster stat entry is unsupported","definition":{}}
	var grants: Variant = parsed.get("grants")
	if not grants is Array or grants.size() != 1:
		return {"ok":false,"reason":"Source monster stat entry must produce exactly one typed grant","definition":{}}
	var grant: Variant = grants[0]
	if not grant is Dictionary or grant.size() != 3 or not grant.get("stat") is String or not grant.get("mode") is String \
			or grant.stat != "move_speed_increased" or grant.mode != "increased":
		return {"ok":false,"reason":"Source monster stat entry effect does not match movement-speed increase","definition":{}}
	var value: Variant = grant.get("value")
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
		return {"ok":false,"reason":"Source monster movement-speed increase must be finite and nonnegative","definition":{}}
	var definition := {"id":ID,"name":"流岚疾行","stats":{"move_speed_increased":float(value)},
		"source_refs":[entry.duplicate(true)],"source_entry":entry.duplicate(true),
		"source_policy":policy,"source_save_version":save_version,"source_line":entry.raw_line,
		"policy_version":"source-tree:%s:policy:%d" % [entry.source_version, policy]}
	return {"ok":true,"reason":"","definition":definition}


static func _failure(reason: String) -> Dictionary:
	# A rejected current source must never leave a prior valid value as fallback.
	_cache_key = PackedByteArray()
	_cached_definition = {}
	return {"ok":false,"reason":reason,"stats":{},"definition":{}}
