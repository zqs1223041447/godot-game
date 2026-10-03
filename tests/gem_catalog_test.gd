extends SceneTree
## GemCatalog is a pure definition/instance boundary; no inventory or save state is created.
const Catalog = preload("res://scripts/items/gem_catalog.gd")
const Data = preload("res://scripts/game_data.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Emblem = preload("res://scripts/visuals/skill_emblem.gd")
const ICON_ROOT: String = "res://assets/ui/grimoire/"
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_all_source_definitions()
	_check_instance_schema()
	_check_rejections()
	_check_copy_isolation_and_determinism()
	_check_rng_unchanged()
	print("Gem catalog: 8 skills, 16 supports; %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_all_source_definitions() -> void:
	var catalog: Dictionary = Catalog.definitions()
	_expect(Data.SKILLS.size() == 8, "Source catalog contains exactly eight skills")
	_expect(Supports.SUPPORTS.size() == 16, "SupportRegistry contains exactly sixteen supports")
	_expect(Emblem.ICONS.size() == 24, "SkillEmblem contains exactly twenty-four original icon mappings")
	_expect(catalog.size() == 24, "Gem catalog exposes exactly twenty-four definitions")
	for skill_id: String in Data.SKILLS:
		var id: String = "skill:" + skill_id
		var source: Dictionary = Data.SKILLS[skill_id]
		var definition: Dictionary = Catalog.definition(id)
		_expect(catalog.has(id) and definition == catalog[id], "Skill definition is indexed by its stable ID: " + id)
		_expect(definition.kind == "skill_gem" and definition.definition_id == id, "Skill uses the exact gem kind and definition ID: " + id)
		_expect(definition.skill_id == skill_id and definition.support_id == "", "Skill metadata names only its source skill: " + id)
		_expect(definition.name == source.name and definition.short_name == source.short_name and definition.description == source.description, "Skill text is reused from GameData: " + id)
		_expect(definition.capabilities == source.capabilities and definition.requires.is_empty(), "Skill capability labels are copied exactly: " + id)
		_expect(definition.glyph == source.icon, "Skill glyph is retained from its source definition: " + id)
		_expect(definition.icon == ICON_ROOT + skill_id + ".png", "Skill uses the runtime emblem path: " + id)
		var skill_texture: Variant = ResourceLoader.load(definition.icon)
		_expect(skill_texture is Texture2D and definition.icon_texture is Texture2D, "Skill icon loads as a Texture2D: " + id)
		_expect(Emblem.ICONS.has(skill_id) and skill_texture == Emblem.ICONS[skill_id] and definition.icon_texture == Emblem.ICONS[skill_id], "Skill icon matches the actual SkillEmblem mapping: " + id)
		_expect(definition.size == [1, 1], "Skill gem footprint is one by one: " + id)
	for support_id: String in Supports.SUPPORTS:
		var id: String = "support:" + support_id
		var source: Dictionary = Supports.get_definition(support_id)
		var definition: Dictionary = Catalog.definition(id)
		_expect(catalog.has(id) and definition == catalog[id], "Support definition is indexed by its stable ID: " + id)
		_expect(definition.kind == "support_gem" and definition.definition_id == id, "Support uses the exact gem kind and definition ID: " + id)
		_expect(definition.skill_id == "" and definition.support_id == support_id, "Support metadata names only its source support: " + id)
		_expect(definition.name == source.name and definition.description == source.description, "Support text is reused from SupportRegistry: " + id)
		_expect(definition.family == source.get("family", ""), "Support family label is retained exactly: " + id)
		_expect(definition.skills == source.get("skills", []) and definition.capabilities == source.requires and definition.requires == source.requires, "Support skill and capability labels are reused exactly: " + id)
		_expect(definition.icon == ICON_ROOT + support_id + ".png", "Support uses the runtime emblem path: " + id)
		var support_texture: Variant = ResourceLoader.load(definition.icon)
		_expect(support_texture is Texture2D and definition.icon_texture is Texture2D, "Support icon loads as a Texture2D: " + id)
		_expect(Emblem.ICONS.has(support_id) and support_texture == Emblem.ICONS[support_id] and definition.icon_texture == Emblem.ICONS[support_id], "Support icon matches the actual SkillEmblem mapping: " + id)
		_expect(definition.size == [1, 1], "Support gem footprint is one by one: " + id)
	_expect(Catalog.definition("bolt").is_empty() and Catalog.definition("volley").is_empty(), "Bare source IDs are not aliases")
	_expect(Catalog.definition("skill:unknown").is_empty() and Catalog.definition("support:unknown").is_empty(), "Unknown namespaced IDs are rejected")
	_expect(Catalog.definition(1).is_empty(), "Non-string definition IDs are rejected")


func _check_instance_schema() -> void:
	for id: String in Catalog.definitions():
		var instance: Dictionary = Catalog.create_instance("qa:" + id, id)
		_expect(instance.size() == 4 and instance.has_all(["uid", "kind", "definition_id", "payload"]), "Created instance has exactly four wrapper fields: " + id)
		_expect(instance.uid == "qa:" + id and instance.kind == Catalog.definition(id).kind and instance.definition_id == id, "Created instance preserves UID, kind and exact definition ID: " + id)
		_expect(instance.payload == {"level": 1, "quality": 0}, "Created instance payload is fixed at level 1 and quality 0: " + id)
		_expect(Catalog.validate_instance(instance), "Created instance validates: " + id)
		var metadata: Dictionary = Catalog.metadata_for_instance(instance)
		_expect(metadata.uid == instance.uid and metadata.definition_id == id and metadata.size == [1, 1], "Instance metadata resolves without changing identity or footprint: " + id)
		if id.begins_with("skill:"):
			_expect(metadata.skill_id == id.trim_prefix("skill:") and metadata.support_id == "", "Instance metadata returns source skill ID: " + id)
		else:
			_expect(metadata.skill_id == "" and metadata.support_id == id.trim_prefix("support:"), "Instance metadata returns source support ID: " + id)


func _check_rejections() -> void:
	var valid: Dictionary = Catalog.create_instance("qa:bolt", "skill:bolt")
	_expect(Catalog.create_instance("", "skill:bolt").is_empty(), "Empty UID is rejected")
	_expect(Catalog.create_instance("  \t", "skill:bolt").is_empty(), "Whitespace-only UID is rejected")
	_expect(Catalog.create_instance(42, "skill:bolt").is_empty(), "Non-string UID is rejected")
	_expect(Catalog.validate_instance(Catalog.create_instance("x", "skill:bolt")), "One-character UID is accepted")
	_expect(Catalog.validate_instance(Catalog.create_instance("x".repeat(128), "skill:bolt")), "128-character UID is accepted")
	_expect(Catalog.create_instance("x".repeat(129), "skill:bolt").is_empty(), "UID longer than 128 characters is rejected")
	_expect(Catalog.create_instance(" leading", "skill:bolt").is_empty(), "UID with leading trim whitespace is rejected")
	_expect(Catalog.create_instance("trailing ", "skill:bolt").is_empty(), "UID with trailing trim whitespace is rejected")
	_expect(Catalog.create_instance("inner\ttab", "skill:bolt").is_empty(), "UID with an embedded control byte below 32 is rejected")
	_expect(Catalog.create_instance("line\nfeed", "skill:bolt").is_empty(), "UID with an embedded line feed is rejected")
	_expect(Catalog.create_instance("delete" + String.chr(127), "skill:bolt").is_empty(), "UID with DEL byte 127 is rejected")
	_expect(Catalog.validate_instance(Catalog.create_instance("gem:宝石-01", "skill:bolt")), "Trim-stable non-ASCII UID is accepted")
	_expect(Catalog.create_instance("qa:unknown", "bolt").is_empty(), "Unknown aliased ID cannot be instantiated")
	_expect(Catalog.create_instance("qa:unknown", "support:unknown").is_empty(), "Unknown namespaced ID cannot be instantiated")
	_expect(not Catalog.validate_instance(null), "Null instance is rejected")
	_expect(not Catalog.validate_instance([]), "Non-dictionary instance is rejected")
	var missing: Dictionary = valid.duplicate(true)
	missing.erase("kind")
	_expect(not Catalog.validate_instance(missing), "Missing wrapper fields are rejected")
	var extra: Dictionary = valid.duplicate(true)
	extra["extra"] = true
	_expect(not Catalog.validate_instance(extra), "Extra wrapper fields are rejected")
	var bad_uid: Dictionary = valid.duplicate(true)
	bad_uid.uid = 7
	_expect(not Catalog.validate_instance(bad_uid), "Wrong UID type is rejected")
	var control_uid: Dictionary = valid.duplicate(true)
	control_uid.uid = "bad\ruid"
	_expect(not Catalog.validate_instance(control_uid), "Instance validation rejects embedded UID controls")
	var bad_kind: Dictionary = valid.duplicate(true)
	bad_kind.kind = "support_gem"
	_expect(not Catalog.validate_instance(bad_kind), "Mismatched kind is rejected")
	var bad_id: Dictionary = valid.duplicate(true)
	bad_id.definition_id = "bolt"
	_expect(not Catalog.validate_instance(bad_id), "Bare definition ID alias is rejected")
	var missing_payload: Dictionary = valid.duplicate(true)
	missing_payload.erase("payload")
	_expect(not Catalog.validate_instance(missing_payload), "Missing payload is rejected")
	var extra_payload: Dictionary = valid.duplicate(true)
	extra_payload.payload["extra"] = 1
	_expect(not Catalog.validate_instance(extra_payload), "Extra payload fields are rejected")
	var float_level: Dictionary = valid.duplicate(true)
	float_level.payload.level = 1.0
	_expect(not Catalog.validate_instance(float_level), "Floating-point level is rejected")
	var float_quality: Dictionary = valid.duplicate(true)
	float_quality.payload.quality = 0.0
	_expect(not Catalog.validate_instance(float_quality), "Floating-point quality is rejected")
	var bool_level: Dictionary = valid.duplicate(true)
	bool_level.payload.level = true
	_expect(not Catalog.validate_instance(bool_level), "Boolean level is rejected")
	var bool_quality: Dictionary = valid.duplicate(true)
	bool_quality.payload.quality = false
	_expect(not Catalog.validate_instance(bool_quality), "Boolean quality is rejected")
	var wrong_level: Dictionary = valid.duplicate(true)
	wrong_level.payload.level = 2
	_expect(not Catalog.validate_instance(wrong_level), "Unsupported level is rejected")
	var wrong_quality: Dictionary = valid.duplicate(true)
	wrong_quality.payload.quality = 1
	_expect(not Catalog.validate_instance(wrong_quality), "Unsupported quality is rejected")
	var string_payload: Dictionary = valid.duplicate(true)
	string_payload.payload.level = "1"
	_expect(not Catalog.validate_instance(string_payload), "String level is rejected")
	var malformed_payload: Dictionary = valid.duplicate(true)
	malformed_payload.payload = []
	_expect(not Catalog.validate_instance(malformed_payload), "Non-dictionary payload is rejected")
	var json_value: Variant = JSON.parse_string(JSON.stringify(valid))
	_expect(json_value is Dictionary and json_value.payload.level == 1.0 and json_value.payload.quality == 0.0, "JSON preserves the numeric payload values")
	_expect(not Catalog.validate_instance(json_value), "Strict validation rejects JSON-decoded floating-point payload types")
	_expect(Catalog.metadata_for_instance(extra).is_empty(), "Invalid instances have no metadata fallback")


func _check_copy_isolation_and_determinism() -> void:
	var first: Dictionary = Catalog.create_instance("same-definition-a", "support:focus")
	var second: Dictionary = Catalog.create_instance("same-definition-b", "support:focus")
	_expect(Catalog.validate_instance(first) and Catalog.validate_instance(second), "Distinct UIDs may independently use the same definition")
	first.payload.level = 2
	_expect(second.payload == {"level": 1, "quality": 0}, "Mutating one instance cannot mutate another")
	var definition_copy: Dictionary = Catalog.definition("skill:bolt")
	definition_copy.capabilities.clear()
	definition_copy.skills.clear()
	_expect(Catalog.definition("skill:bolt").capabilities == Data.SKILLS.bolt.capabilities, "Definition results are deeply detached from source capability arrays")
	var all_copy: Dictionary = Catalog.definitions()
	all_copy["support:focus"].skills.clear()
	_expect(Catalog.definition("support:focus").skills == Supports.get_definition("focus").get("skills", []), "Definitions map is detached from support sources")
	_expect(Catalog.definitions() == Catalog.definitions(), "Definition enumeration is deterministic")
	_expect(Catalog.create_instance("stable-uid", "skill:bolt") == Catalog.create_instance("stable-uid", "skill:bolt"), "Instance creation is deterministic for the same inputs")
	var metadata: Dictionary = Catalog.metadata_for_instance(second)
	metadata.capabilities.clear()
	_expect(Catalog.metadata_for_instance(second).capabilities == Supports.get_definition("focus").requires, "Instance metadata is deeply detached")


func _check_rng_unchanged() -> void:
	seed(740219)
	var expected: int = randi()
	seed(740219)
	Catalog.definitions()
	Catalog.definition("skill:bolt")
	Catalog.definition("support:focus")
	Catalog.create_instance("rng-check", "skill:bolt")
	Catalog.validate_instance(Catalog.create_instance("rng-check", "support:focus"))
	Catalog.metadata_for_instance(Catalog.create_instance("rng-check", "support:focus"))
	var observed: int = randi()
	_expect(observed == expected, "Catalog API calls do not consume global RNG state")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("GemCatalog: " + message)
