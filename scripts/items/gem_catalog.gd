class_name GemCatalog
extends RefCounted
## Pure skill/support gem identities and their fixed, non-progressing instance envelope.
## Runtime skill/support behavior remains owned by GameData and SupportRegistry.
const Data = preload("res://scripts/game_data.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const UID_MAX_LENGTH: int = 128
const SKILL_PREFIX: String = "skill:"
const SUPPORT_PREFIX: String = "support:"
const ICON_ROOT: String = "res://assets/ui/grimoire/"


## Return detached metadata for all currently defined active skills and supports.
static func definitions() -> Dictionary:
	var result: Dictionary = {}
	var skill_ids: Array = Data.SKILLS.keys()
	skill_ids.sort()
	for raw_id: Variant in skill_ids:
		if raw_id is String:
			var skill_id: String = raw_id
			result[SKILL_PREFIX + skill_id] = _skill_definition(skill_id)
	var support_ids: Array = Supports.SUPPORTS.keys()
	support_ids.sort()
	for raw_id: Variant in support_ids:
		if raw_id is String:
			var support_id: String = raw_id
			result[SUPPORT_PREFIX + support_id] = _support_definition(support_id)
	return result


## The old canonical schema has a closed gem vocabulary. New definitions do
## not become valid inside a file claiming an older schema after a code update.
static func minimum_save_version(definition_id: String) -> int:
	# Gem additions open independently; schema26 milestone rewards stay frozen.
	if definition_id == "support:inward_pull":
		return 43
	if definition_id == "support:ambush":
		return 42
	if definition_id == "support:shock":
		return 31
	if definition_id == "support:ember_proliferation":
		return 29
	if definition_id == "support:ignite":
		return 28
	if definition_id.begins_with(SKILL_PREFIX) and Data.NEW_SKILL_IDS.has(definition_id.substr(SKILL_PREFIX.length())):
		return Data.NEW_SKILL_SAVE_VERSION
	return 14


## Resolve one exact stable identifier. Bare IDs and unknown IDs are never aliases.
static func definition(id: Variant) -> Dictionary:
	if not id is String:
		return {}
	if id.begins_with(SKILL_PREFIX):
		var skill_id: String = id.substr(SKILL_PREFIX.length())
		if Data.SKILLS.has(skill_id):
			return _skill_definition(skill_id)
	elif id.begins_with(SUPPORT_PREFIX):
		var support_id: String = id.substr(SUPPORT_PREFIX.length())
		if Supports.SUPPORTS.has(support_id):
			return _support_definition(support_id)
	return {}


## Create an independent instance with the only supported payload: level 1, quality 0.
## Invalid UIDs and unknown definition IDs return {} without allocating an alias.
static func create_instance(uid: Variant, definition_id: Variant) -> Dictionary:
	if not _valid_uid(uid):
		return {}
	var resolved: Dictionary = definition(definition_id)
	if resolved.is_empty():
		return {}
	return {
		"uid": uid,
		"kind": resolved.kind,
		"definition_id": resolved.definition_id,
		"payload": {"level": 1, "quality": 0},
	}


## Validate the exact four-field wrapper and exact integer payload. No coercion or defaults.
static func validate_instance(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 4 or not value.has_all(["uid", "kind", "definition_id", "payload"]):
		return false
	if not _valid_uid(value.uid) or not value.kind is String or not value.definition_id is String:
		return false
	var resolved: Dictionary = definition(value.definition_id)
	if resolved.is_empty() or value.kind != resolved.kind:
		return false
	var payload: Variant = value.payload
	if not payload is Dictionary or payload.size() != 2 or not payload.has_all(["level", "quality"]):
		return false
	return payload.level is int and payload.level == 1 and payload.quality is int and payload.quality == 0


## Return detached source metadata for a valid instance; malformed instances return {}.
static func metadata_for_instance(value: Variant) -> Dictionary:
	if not validate_instance(value):
		return {}
	var result: Dictionary = definition(value.definition_id)
	result["uid"] = value.uid
	return result


static func _skill_definition(skill_id: String) -> Dictionary:
	var source: Dictionary = Data.SKILLS[skill_id]
	var capabilities: Array = source.get("capabilities", []).duplicate(true)
	var icon_path: String = ICON_ROOT + skill_id + ".png"
	var icon_texture: Texture2D = ResourceLoader.load(icon_path) as Texture2D
	if icon_texture == null:
		return {}
	return {
		"definition_id": SKILL_PREFIX + skill_id,
		"kind": "skill_gem",
		"name": source.get("name", ""),
		"short_name": source.get("short_name", ""),
		"description": source.get("description", ""),
		"family": "",
		"icon": icon_path,
		"icon_texture": icon_texture,
		"glyph": source.get("icon", ""),
		"size": [1, 1],
		"skill_id": skill_id,
		"support_id": "",
		"capabilities": capabilities,
		"requires": [],
		"skills": [skill_id],
	}


static func _support_definition(support_id: String) -> Dictionary:
	var source: Dictionary = Supports.get_definition(support_id)
	if source.is_empty():
		return {}
	var capabilities: Array = source.get("requires", []).duplicate(true)
	var icon_path: String = ICON_ROOT + support_id + ".png"
	var icon_texture: Texture2D = ResourceLoader.load(icon_path) as Texture2D
	if icon_texture == null:
		return {}
	return {
		"definition_id": SUPPORT_PREFIX + support_id,
		"kind": "support_gem",
		"name": source.get("name", ""),
		"short_name": source.get("name", ""),
		"description": source.get("description", ""),
		"family": source.get("family", ""),
		"icon": icon_path,
		"icon_texture": icon_texture,
		"glyph": "",
		"size": [1, 1],
		"skill_id": "",
		"support_id": support_id,
		"capabilities": capabilities,
		"requires": capabilities.duplicate(true),
		"skills": source.get("skills", []).duplicate(true),
	}


static func _valid_uid(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > UID_MAX_LENGTH or value != value.strip_edges():
		return false
	for byte: int in value.to_utf8_buffer():
		if byte < 32 or byte == 127:
			return false
	return true
