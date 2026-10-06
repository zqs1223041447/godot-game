extends RefCounted
## JSON is the sole numeric authority. PoE percentages are either explicitly
## projected against a fixed reference or retain native additive damage semantics.
## This adapter never imports source layout, art, conditional or unimplemented rules.
const PATH: String = "res://data/passive_balance.json"
const VALID_STATS: Array[String] = ["damage", "max_health", "max_mana", "max_shield", "attack_speed", "move_speed", "mana_regen", "shield_regen", "global_increased", "projectile_increased", "elemental_increased", "area_increased"]
const REQUIRED_IDS: Array[String] = ["ember_power", "ember_fervor", "ember_mastery", "grove_vitality", "grove_guard", "grove_mastery", "tide_capacity", "tide_flow", "tide_mastery", "gale_alacrity", "gale_stride", "gale_mastery", "aegis_capacity", "aegis_recovery", "aegis_mastery", "prism_vigor", "prism_reserve", "prism_recovery", "prism_mastery", "poe_global_damage", "poe_projectile_damage", "poe_elemental_damage", "poe_area_damage"]
static var _loaded: bool = false
static var _config: Dictionary = {}
static var _errors: Array[String] = []

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		_errors.append("Passive balance config is missing: " + PATH)
		push_error(_errors[0])
		return
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(PATH)) != OK:
		_errors.append("Passive balance JSON failed to parse")
		push_error(_errors[0])
		return
	if not parser.data is Dictionary:
		_errors.append("Passive balance root must be an object")
		push_error(_errors[0])
		return
	_errors = validate_config(parser.data)
	if not _errors.is_empty():
		push_error("Passive balance rejected: " + "; ".join(_errors))
		return
	_config = parser.data.duplicate(true)

static func definitions() -> Dictionary:
	_ensure_loaded()
	return _config.get("definitions", {}).duplicate(true)

static func node_override(node_id: String) -> String:
	_ensure_loaded()
	return str(_config.get("node_overrides", {}).get(node_id, ""))

static func node_overrides() -> Dictionary:
	_ensure_loaded()
	return _config.get("node_overrides", {}).duplicate(true)

static func policy_version() -> String:
	_ensure_loaded()
	return str(_config.get("balance_revision", "invalid"))

static func player_caps() -> Dictionary:
	_ensure_loaded()
	return _config.get("player_passive_caps", {}).duplicate(true)

static func validation_errors() -> Array[String]:
	_ensure_loaded()
	return _errors.duplicate()

static func source_manifest() -> Dictionary:
	_ensure_loaded()
	return _config.get("source", {}).duplicate(true)

static func cap_player_passives(stats: Dictionary) -> Dictionary:
	_ensure_loaded()
	if not _errors.is_empty():
		return {}
	var caps: Dictionary = _config.player_passive_caps
	var result: Dictionary = {}
	for key: Variant in stats:
		if not key is String or not caps.has(key) or not _is_amount(stats[key]):
			push_error("Unsupported or invalid player passive contribution: " + str(key))
			return {}
		result[key] = minf(float(stats[key]), float(caps[key]))
	return result

static func validate_config(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if config.get("schema_version", 0) != 1 or str(config.get("balance_revision", "")).is_empty():
		errors.append("Unsupported schema or missing balance revision")
	if config.get("policy_version", "") != config.get("balance_revision", ""):
		errors.append("Policy version and calibration revision differ")
	if not config.get("definitions") is Dictionary or not config.get("player_passive_caps") is Dictionary or not config.get("node_overrides") is Dictionary:
		errors.append("Definitions, caps and overrides must be objects")
		return errors
	var source: Variant = config.get("source")
	if not source is Dictionary or str(source.get("commit", "")).length() != 40 or str(source.get("data_sha256", "")).length() != 64:
		errors.append("Source must have fixed commit and SHA-256")
	var defs: Dictionary = config.definitions
	for id: String in REQUIRED_IDS:
		if not defs.has(id):
			errors.append("Missing mechanism: " + id)
	for key: Variant in defs:
		if not key is String or not defs[key] is Dictionary:
			errors.append("Mechanism identity/entry invalid")
			continue
		var entry: Dictionary = defs[key]
		if str(entry.get("name", "")).is_empty() or not entry.get("stats") is Dictionary or not entry.get("source_refs") is Array:
			errors.append("Mechanism fields invalid: " + str(key))
			continue
		if entry.stats.is_empty() or entry.source_refs.is_empty():
			errors.append("Empty stats or unproven source: " + str(key))
		var derived: Dictionary = {}
		for ref: Variant in entry.source_refs:
			if not ref is Dictionary:
				errors.append("Source reference is not an object: " + str(key))
				continue
			var stat: String = str(ref.get("target_stat", ""))
			if not VALID_STATS.has(stat) or not _is_amount(ref.get("source_value")) or not _is_amount(ref.get("scale")) or ref.get("source_mode", "") not in ["increased", "flat"]:
				errors.append("Unsupported source transform: " + str(key))
				continue
			var base: Variant = ref.get("reference_base")
			if base != null and not _is_amount(base):
				errors.append("Invalid reference base: " + str(key))
				continue
			if base == null and (not stat.ends_with("_increased") or ref.get("adaptation", "") != "native_additive_increased"):
				errors.append("Native increase transform contract invalid: " + str(key))
			if base != null and (stat.ends_with("_increased") or ref.get("adaptation", "") != "fixed_reference_flat_projection"):
				errors.append("Fixed-reference transform contract invalid: " + str(key))
			if str(ref.get("modifier_id", "")).is_empty() or not ref.get("source_node") is Dictionary:
				errors.append("Source modifier identity missing: " + str(key))
			var source_unit: float = 0.01 if ref.source_mode == "increased" else 1.0
			if ref.source_mode == "flat" and (base == null or not is_equal_approx(float(base), 1.0)):
				errors.append("Flat source requires unit reference base: " + str(key))
			derived[stat] = float(derived.get(stat, 0.0)) + float(ref.source_value) * source_unit * float(ref.scale) * (1.0 if base == null else float(base))
		if derived.size() != entry.stats.size():
			errors.append("Source and runtime stat keys differ: " + str(key))
		for stat: Variant in entry.stats:
			if not stat is String or not VALID_STATS.has(stat) or not _is_amount(entry.stats[stat]):
				errors.append("Invalid runtime stat: " + str(key))
			elif not derived.has(stat) or not is_equal_approx(float(derived.get(stat, -1.0)), float(entry.stats[stat])):
				errors.append("Runtime value does not match source calibration: " + str(key) + "/" + str(stat))
	for stat: String in VALID_STATS:
		if not config.player_passive_caps.has(stat) or not _is_amount(config.player_passive_caps.get(stat)):
			errors.append("Missing/invalid passive cap: " + stat)
	for stat: Variant in config.player_passive_caps:
		if not VALID_STATS.has(str(stat)):
			errors.append("Unknown passive cap: " + str(stat))
	for node: Variant in config.node_overrides:
		if not node is String or not _valid_small_node(str(node)) or not defs.has(str(config.node_overrides[node])):
			errors.append("Unknown node override mechanism: " + str(node))
	return errors

static func _is_amount(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0

static func _valid_small_node(id: String) -> bool:
	var parts: PackedStringArray = id.split("_")
	if parts.size() != 3 or parts[0] not in ["ember", "grove", "tide", "gale", "aegis", "prism"] or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return false
	var ring: int = int(parts[1])
	var index: int = int(parts[2])
	if ring < 3 or ring > 6 or index < 0 or index >= [1, 2, 4, 6, 8, 9][ring - 1]:
		return false
	return id == "%s_%d_%d" % [parts[0], ring, index] and Vector2i(ring, index) not in [Vector2i(3, 0), Vector2i(5, 3), Vector2i(3, 2), Vector2i(4, 3), Vector2i(5, 6), Vector2i(6, 4)]
