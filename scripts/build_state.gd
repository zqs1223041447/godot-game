class_name BuildState
extends RefCounted
## Persistent character configuration. Runtime combat resources live in the arena.

signal changed

const Data = preload("res://scripts/game_data.gd")
const SAVE_VERSION: int = 1
const MAX_LEVEL: int = 1000
const MAX_SAVE_BYTES: int = 65536
const BASE_TALENT_POINTS: int = 5
const EQUIPMENT_SLOTS: Array[String] = ["weapon", "armor", "charm"]
const BASE_STATS: Dictionary = {
	"max_health": 120.0, "max_mana": 100.0, "max_shield": 60.0,
	"damage": 18.0, "attack_speed": 1.7, "move_speed": 240.0,
	"mana_regen": 9.0, "shield_regen": 13.0,
}

var inventory: Array[String] = [
	"ember_wand", "swift_blade", "guardian_robe", "vitality_armor", "azure_charm", "storm_charm",
]
var equipped: Dictionary = {
	"weapon": "ember_wand", "armor": "guardian_robe", "charm": "azure_charm",
}
var talents: Dictionary = {"power": 0, "vitality": 0, "focus": 0, "haste": 0, "aegis": 0}
var skill_slots: Array[String] = ["bolt", "frost", "nova", "dash", "ward"]
var level: int = 1
var xp: int = 0
var talent_points: int = BASE_TALENT_POINTS


func get_stats() -> Dictionary:
	var result: Dictionary = BASE_STATS.duplicate()
	for slot: String in EQUIPMENT_SLOTS:
		var item_id: String = str(equipped.get(slot, ""))
		if Data.ITEMS.has(item_id):
			_add_stats(result, Data.ITEMS[item_id]["stats"], 1)
	for talent_id: String in Data.TALENTS:
		var rank: int = clampi(int(talents.get(talent_id, 0)), 0, int(Data.TALENTS[talent_id]["max_rank"]))
		_add_stats(result, Data.TALENTS[talent_id]["stats"], rank)
	return result


func equip(item_id: String) -> bool:
	if not Data.ITEMS.has(item_id) or not inventory.has(item_id):
		return false
	var slot: String = Data.ITEMS[item_id]["slot"]
	if equipped.get(slot, "") == item_id:
		return false
	equipped[slot] = item_id
	changed.emit()
	return true


func unequip(slot: String) -> bool:
	if not EQUIPMENT_SLOTS.has(slot) or not equipped.has(slot):
		return false
	equipped.erase(slot)
	changed.emit()
	return true


func allocate_talent(talent_id: String) -> bool:
	if not Data.TALENTS.has(talent_id) or talent_points <= 0:
		return false
	var rank: int = int(talents.get(talent_id, 0))
	if rank >= int(Data.TALENTS[talent_id]["max_rank"]):
		return false
	talents[talent_id] = rank + 1
	talent_points -= 1
	changed.emit()
	return true


func refund_talents() -> void:
	var refunded: int = 0
	for talent_id: String in Data.TALENTS:
		refunded += int(talents.get(talent_id, 0))
		talents[talent_id] = 0
	if refunded > 0:
		talent_points += refunded
		changed.emit()


func slot_skill(index: int, skill_id: String) -> bool:
	if index < 0 or index >= skill_slots.size() or not Data.SKILLS.has(skill_id):
		return false
	if skill_slots[index] == skill_id:
		return false
	var previous_index: int = skill_slots.find(skill_id)
	if previous_index >= 0:
		skill_slots[previous_index] = skill_slots[index]
	skill_slots[index] = skill_id
	changed.emit()
	return true


func add_xp(amount: int) -> bool:
	if amount <= 0 or level >= MAX_LEVEL:
		return false
	# Bound additions before arithmetic, including calls from imported progression data.
	xp += mini(amount, 1000000000)
	var leveled: bool = false
	while xp >= xp_required() and level < MAX_LEVEL:
		xp -= xp_required()
		level += 1
		talent_points += 1
		leveled = true
	if level >= MAX_LEVEL:
		xp = 0
	changed.emit()
	return leveled


func xp_required() -> int:
	return 12 + level * 8


func save_build(path: String = "user://build_save.json") -> Error:
	var snapshot: Dictionary = _snapshot()
	if _validate_snapshot(snapshot).is_empty():
		return ERR_INVALID_DATA
	var temporary_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
		return write_error
	# A partial write never overwrites the last successful build save.
	var rename_error: Error = DirAccess.rename_absolute(temporary_path, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary_path)
	return rename_error


func load_build(path: String = "user://build_save.json") -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return false
	var text: String = file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return false
	var candidate: Dictionary = _validate_snapshot(parser.data)
	if candidate.is_empty():
		return false
	# Commit only after every value is validated. JSON never instantiates objects.
	inventory.assign(candidate["inventory"])
	equipped = candidate["equipped"].duplicate()
	talents = candidate["talents"].duplicate()
	skill_slots.assign(candidate["skill_slots"])
	level = int(candidate["level"])
	xp = int(candidate["xp"])
	talent_points = int(candidate["talent_points"])
	changed.emit()
	return true


func _snapshot() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"inventory": inventory.duplicate(), "equipped": equipped.duplicate(),
		"talents": talents.duplicate(), "skill_slots": skill_slots.duplicate(),
		"level": level, "xp": xp, "talent_points": talent_points,
	}


func _validate_snapshot(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var data: Dictionary = value
	if not _is_bounded_int(data.get("version"), SAVE_VERSION, SAVE_VERSION):
		return {}
	if not _is_bounded_int(data.get("level"), 1, MAX_LEVEL):
		return {}
	var loaded_level: int = int(data["level"])
	if not _is_bounded_int(data.get("xp"), 0, 11 + loaded_level * 8):
		return {}
	if not _is_bounded_int(data.get("talent_points"), 0, BASE_TALENT_POINTS + loaded_level - 1):
		return {}
	if not data.get("inventory") is Array or not data.get("skill_slots") is Array:
		return {}
	var loaded_inventory: Array = data["inventory"]
	var loaded_skills: Array = data["skill_slots"]
	if loaded_inventory.size() > Data.ITEMS.size() or loaded_skills.size() != 5:
		return {}
	var seen: Dictionary = {}
	for item_id: Variant in loaded_inventory:
		if not item_id is String or not Data.ITEMS.has(item_id) or seen.has(item_id):
			return {}
		seen[item_id] = true
	seen.clear()
	for skill_id: Variant in loaded_skills:
		if not skill_id is String or not Data.SKILLS.has(skill_id) or seen.has(skill_id):
			return {}
		seen[skill_id] = true
	if not data.get("equipped") is Dictionary or not data.get("talents") is Dictionary:
		return {}
	var loaded_equipped: Dictionary = data["equipped"]
	for slot: Variant in loaded_equipped:
		if not slot is String or not EQUIPMENT_SLOTS.has(slot):
			return {}
		var item_id: Variant = loaded_equipped[slot]
		if not item_id is String or not loaded_inventory.has(item_id):
			return {}
		if Data.ITEMS[item_id]["slot"] != slot:
			return {}
	var loaded_talents: Dictionary = data["talents"]
	var normalized_talents: Dictionary = {}
	var spent_points: int = 0
	for talent_id: Variant in loaded_talents:
		if not talent_id is String or not Data.TALENTS.has(talent_id):
			return {}
		var rank: Variant = loaded_talents[talent_id]
		if not _is_bounded_int(rank, 0, int(Data.TALENTS[talent_id]["max_rank"])):
			return {}
		spent_points += int(rank)
	for talent_id: String in Data.TALENTS:
		normalized_talents[talent_id] = int(loaded_talents.get(talent_id, 0))
	if spent_points + int(data["talent_points"]) != BASE_TALENT_POINTS + loaded_level - 1:
		return {}
	var result: Dictionary = data.duplicate(true)
	result["talents"] = normalized_talents
	return result


static func _is_bounded_int(value: Variant, minimum: int, maximum: int) -> bool:
	# JSON numbers are floats. Reject fractions, booleans, infinity, and coercible text.
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number == floor(number) and number >= minimum and number <= maximum


static func _add_stats(target: Dictionary, modifiers: Dictionary, rank: int) -> void:
	for stat: String in modifiers:
		if target.has(stat):
			target[stat] = float(target[stat]) + float(modifiers[stat]) * rank
