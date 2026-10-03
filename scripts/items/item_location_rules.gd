class_name ItemLocationRules
extends RefCounted
## Pure validator for resolved item metadata and their one authoritative location.
## It never moves items, resolves payloads, persists state or consumes randomness.

const BAG_COLUMNS: int = 12
const BAG_ROWS: int = 8
const PAGED_BAG_COLUMNS: int = 8
const PAGED_BAG_ROWS: int = 6
const PAGED_BAG_PAGES: int = 2
const MAX_ITEM_ID_LENGTH: int = 128
const MAX_SUPPORT_INDEX: int = 4
const ITEM_KINDS: Array[String] = ["equipment", "jewel", "skill_gem", "support_gem", "currency"]
const EQUIPMENT_CATEGORIES: Array[String] = [
	"weapon", "body_armour", "amulet", "ring", "boots", "belt", "gloves", "helmet",
]
const EQUIPMENT_SLOTS: Dictionary = {
	"weapon": "weapon",
	"body_armour": "body_armour",
	"amulet": "amulet",
	"ring_1": "ring",
	"ring_2": "ring",
	"boots": "boots",
	"belt": "belt",
	"gloves": "gloves",
	"helmet": "helmet",
}
const CONTEXT_FIELDS: Array[String] = [
	"columns", "rows", "equipment_slots", "skill_group_ids", "passive_socket_ids", "allow_recovery",
]


static func validate(metadata_by_uid: Variant, locations: Variant, context: Variant) -> Dictionary:
	var context_error: String = _context_error(context)
	return _validate(metadata_by_uid, locations, context, false, context_error)


## v15 adds a second, explicit layout contract. The legacy validate/context
## above remains frozen at 12×8 for v14 decoding and fixtures.
static func validate_paged(metadata_by_uid: Variant, locations: Variant, context: Variant) -> Dictionary:
	var context_error: String = _paged_context_error(context)
	return _validate(metadata_by_uid, locations, context, true, context_error)


static func _validate(metadata_by_uid: Variant, locations: Variant, context: Variant,
		paged: bool, context_error: String) -> Dictionary:
	if not context_error.is_empty():
		return _failure("invalid_context", context_error)
	if not metadata_by_uid is Dictionary or not locations is Dictionary:
		return _failure("invalid_input", "metadata_by_uid 与 locations 必须是对象")

	var uids: Array = metadata_by_uid.keys()
	for uid: Variant in uids:
		if not _stable_id(uid):
			return _failure("invalid_metadata", "物品 UID 必须是非空稳定字符串")
		var item_error: String = _metadata_error(metadata_by_uid[uid])
		if not item_error.is_empty():
			return _failure("invalid_metadata", "%s：%s" % [uid, item_error])
	for uid: Variant in locations.keys():
		if not _stable_id(uid):
			return _failure("invalid_location", "位置表 UID 必须是非空稳定字符串")
	if metadata_by_uid.size() != locations.size():
		return _failure("location_set_mismatch", "每件物品必须且只能有一个位置")
	for uid: String in uids:
		if not locations.has(uid):
			return _failure("location_set_mismatch", "%s 缺少唯一位置" % uid)

	# Canonical order makes the successful occupied maps independent of input dictionary order.
	uids.sort()
	var occupied_cells: Dictionary = {}
	var occupied_targets: Dictionary = {}
	var equipment_slots: Dictionary = context.equipment_slots
	var skill_group_ids: Array = context.skill_group_ids
	var passive_socket_ids: Array = context.passive_socket_ids
	for uid: String in uids:
		var item: Dictionary = metadata_by_uid[uid]
		var location: Variant = locations[uid]
		if not location is Dictionary:
			return _failure("invalid_location", "%s 的位置必须是对象" % uid)
		if not location.has("kind") or typeof(location.kind) != TYPE_STRING:
			return _failure("invalid_location", "%s 的位置缺少字符串 kind" % uid)
		var kind: String = location.kind
		var target_error: String = _paged_location_shape_error(location, kind) if paged else _location_shape_error(location, kind)
		if not target_error.is_empty():
			return _failure("invalid_location", "%s：%s" % [uid, target_error])

		match kind:
			"bag":
				var x: int = location.x
				var y: int = location.y
				var page: int = location.page if paged else 0
				var width: int = item.size[0]
				var height: int = item.size[1]
				var columns: int = PAGED_BAG_COLUMNS if paged else BAG_COLUMNS
				var rows: int = PAGED_BAG_ROWS if paged else BAG_ROWS
				if x < 0 or y < 0 or x + width > columns or y + height > rows:
					var bounds_message: String = ("%s 超出双页 8×6 背包边界" % uid) if paged else ("%s 超出 12×8 背包边界" % uid)
					return _failure("out_of_bounds", bounds_message)
				for cell_y: int in range(y, y + height):
					for cell_x: int in range(x, x + width):
						var cell_key: String = "bag:%d:%d:%d" % [page, cell_x, cell_y] if paged else "bag:%d:%d" % [cell_x, cell_y]
						if occupied_cells.has(cell_key):
							return _failure("bag_overlap", "%s 与 %s 的背包占格重叠" % [uid, occupied_cells[cell_key]])
						occupied_cells[cell_key] = uid
			"equipment":
				if item.kind != "equipment":
					return _failure("kind_mismatch", "%s 只有 equipment 可穿戴" % uid)
				var slot_id: String = location.slot_id
				if not equipment_slots.has(slot_id) or equipment_slots[slot_id] != item.category:
					return _failure("target_mismatch", "%s 的装备类别与目标槽不匹配" % uid)
				var equipment_key: String = "equipment:%s" % slot_id
				if occupied_targets.has(equipment_key):
					return _failure("duplicate_target", "%s 已被 %s 占用" % [equipment_key, occupied_targets[equipment_key]])
				occupied_targets[equipment_key] = uid
			"passive_socket":
				if item.kind != "jewel":
					return _failure("kind_mismatch", "%s 只有 jewel 可镶入珠宝孔" % uid)
				var node_id: String = location.node_id
				if not passive_socket_ids.has(node_id):
					return _failure("target_mismatch", "珠宝孔 %s 不在调用方许可集合中" % node_id)
				var socket_key: String = "passive_socket:%s" % node_id
				if occupied_targets.has(socket_key):
					return _failure("duplicate_target", "%s 已被 %s 占用" % [socket_key, occupied_targets[socket_key]])
				occupied_targets[socket_key] = uid
			"skill_main":
				if item.kind != "skill_gem":
					return _failure("kind_mismatch", "%s 只有 skill_gem 可放入技能主槽" % uid)
				var group_id: String = location.group_id
				if not skill_group_ids.has(group_id):
					return _failure("target_mismatch", "技能行 %s 不在调用方许可集合中" % group_id)
				var main_key: String = "skill_main:%s" % group_id
				if occupied_targets.has(main_key):
					return _failure("duplicate_target", "%s 已被 %s 占用" % [main_key, occupied_targets[main_key]])
				occupied_targets[main_key] = uid
			"skill_support":
				if item.kind != "support_gem":
					return _failure("kind_mismatch", "%s 只有 support_gem 可放入辅助槽" % uid)
				var support_group_id: String = location.group_id
				if not skill_group_ids.has(support_group_id):
					return _failure("target_mismatch", "技能行 %s 不在调用方许可集合中" % support_group_id)
				var support_key: String = "skill_support:%s:%d" % [support_group_id, location.index]
				if occupied_targets.has(support_key):
					return _failure("duplicate_target", "%s 已被 %s 占用" % [support_key, occupied_targets[support_key]])
				occupied_targets[support_key] = uid
			"recovery":
				if not context.allow_recovery:
					return _failure("recovery_disabled", "普通移动不允许使用迁移暂存位置")
				if location.index >= metadata_by_uid.size():
					return _failure("invalid_location", "recovery index 必须小于物品总数")
				var recovery_key: String = "recovery:%d" % location.index
				if occupied_targets.has(recovery_key):
					return _failure("duplicate_target", "%s 已被 %s 占用" % [recovery_key, occupied_targets[recovery_key]])
				occupied_targets[recovery_key] = uid
			_:
				return _failure("invalid_location", "未知位置 kind：%s" % kind)

	return {
		"ok": true,
		"error_code": "",
		"reason": "",
		"occupied_cells": occupied_cells,
		"occupied_targets": occupied_targets,
	}


static func _context_error(value: Variant) -> String:
	if not _exact_string_keys(value, CONTEXT_FIELDS):
		return "context 必须严格包含六个协议字段"
	if typeof(value.columns) != TYPE_INT or value.columns != BAG_COLUMNS or typeof(value.rows) != TYPE_INT or value.rows != BAG_ROWS:
		return "背包尺寸必须是 12 列、8 行的整数"
	if typeof(value.allow_recovery) != TYPE_BOOL:
		return "allow_recovery 必须是布尔值"
	if not _exact_dictionary_keys(value.equipment_slots, EQUIPMENT_SLOTS.keys()):
		return "equipment_slots 必须精确包含九个装备目标"
	for slot_id: String in EQUIPMENT_SLOTS:
		var category: Variant = value.equipment_slots[slot_id]
		if typeof(category) != TYPE_STRING or category != EQUIPMENT_SLOTS[slot_id]:
			return "装备目标 %s 的类别配置无效" % slot_id
	if not _unique_id_array(value.skill_group_ids):
		return "skill_group_ids 必须是唯一稳定字符串数组"
	if not _unique_id_array(value.passive_socket_ids):
		return "passive_socket_ids 必须是唯一稳定字符串数组"
	return ""


static func _paged_context_error(value: Variant) -> String:
	var paged_fields: Array[String] = ["columns", "rows", "pages", "equipment_slots", "skill_group_ids", "passive_socket_ids", "allow_recovery"]
	if not _exact_string_keys(value, paged_fields):
		return "paged context 必须严格包含七个协议字段"
	if typeof(value.columns) != TYPE_INT or value.columns != PAGED_BAG_COLUMNS \
			or typeof(value.rows) != TYPE_INT or value.rows != PAGED_BAG_ROWS \
			or typeof(value.pages) != TYPE_INT or value.pages != PAGED_BAG_PAGES:
		return "双页背包尺寸必须是两页 8 列、6 行的整数"
	if typeof(value.allow_recovery) != TYPE_BOOL:
		return "allow_recovery 必须是布尔值"
	if not _exact_dictionary_keys(value.equipment_slots, EQUIPMENT_SLOTS.keys()):
		return "equipment_slots 必须精确包含九个装备目标"
	for slot_id: String in EQUIPMENT_SLOTS:
		var category: Variant = value.equipment_slots[slot_id]
		if typeof(category) != TYPE_STRING or category != EQUIPMENT_SLOTS[slot_id]:
			return "装备目标 %s 的类别配置无效" % slot_id
	if not _unique_id_array(value.skill_group_ids):
		return "skill_group_ids 必须是唯一稳定字符串数组"
	if not _unique_id_array(value.passive_socket_ids):
		return "passive_socket_ids 必须是唯一稳定字符串数组"
	return ""


static func _metadata_error(value: Variant) -> String:
	if not _exact_string_keys(value, ["kind", "category", "size"]):
		return "metadata 必须严格包含 kind、category、size"
	if typeof(value.kind) != TYPE_STRING or not ITEM_KINDS.has(value.kind):
		return "kind 不受支持"
	if typeof(value.category) != TYPE_STRING:
		return "category 必须是字符串"
	if value.kind == "equipment":
		if not EQUIPMENT_CATEGORIES.has(value.category):
			return "equipment 的 category 不受支持"
	elif value.category != "":
		return "非 equipment 的 category 必须为空字符串"
	if not value.size is Array or value.size.size() != 2:
		return "size 必须是 [width, height]"
	if typeof(value.size[0]) != TYPE_INT or typeof(value.size[1]) != TYPE_INT:
		return "size 必须使用真正的整数"
	if value.size[0] < 1 or value.size[0] > BAG_COLUMNS or value.size[1] < 1 or value.size[1] > BAG_ROWS:
		return "size 必须在 1×1 至 12×8 范围内"
	if value.kind == "currency" and value.size != [1, 1]:
		return "currency 必须占用 1×1 格子"
	return ""


static func _location_shape_error(value: Dictionary, kind: String) -> String:
	var expected: Array[String]
	match kind:
		"bag": expected = ["kind", "x", "y"]
		"equipment": expected = ["kind", "slot_id"]
		"passive_socket": expected = ["kind", "node_id"]
		"skill_main": expected = ["kind", "group_id"]
		"skill_support": expected = ["kind", "group_id", "index"]
		"recovery": expected = ["kind", "index"]
		_:
			return "位置 kind 不受支持"
	if not _exact_string_keys(value, expected):
		return "%s 位置字段必须精确为 %s" % [kind, ", ".join(expected)]
	match kind:
		"bag":
			if typeof(value.x) != TYPE_INT or typeof(value.y) != TYPE_INT:
				return "背包坐标必须使用真正的整数"
			if value.x < 0 or value.x >= BAG_COLUMNS or value.y < 0 or value.y >= BAG_ROWS:
				return "背包坐标超出 12×8 范围"
		"equipment":
			if not _stable_id(value.slot_id): return "slot_id 必须是稳定字符串"
		"passive_socket":
			if not _stable_id(value.node_id): return "node_id 必须是稳定字符串"
		"skill_main":
			if not _stable_id(value.group_id): return "group_id 必须是稳定字符串"
		"skill_support":
			if not _stable_id(value.group_id): return "group_id 必须是稳定字符串"
			if typeof(value.index) != TYPE_INT or value.index < 0 or value.index > MAX_SUPPORT_INDEX:
				return "辅助 index 必须是 0..4 的真正整数"
		"recovery":
			if typeof(value.index) != TYPE_INT or value.index < 0:
				return "recovery index 必须是非负真正整数"
	return ""


static func _paged_location_shape_error(value: Dictionary, kind: String) -> String:
	if kind != "bag":
		return _location_shape_error(value, kind)
	if not _exact_string_keys(value, ["kind", "page", "x", "y"]):
		return "bag 位置字段必须精确为 kind、page、x、y"
	for field: String in ["page", "x", "y"]:
		if typeof(value[field]) != TYPE_INT:
			return "背包页码和坐标必须使用真正的整数"
	if value.page < 0 or value.page >= PAGED_BAG_PAGES:
		return "背包页码超出 0..1 范围"
	if value.x < 0 or value.x >= PAGED_BAG_COLUMNS or value.y < 0 or value.y >= PAGED_BAG_ROWS:
		return "背包坐标超出双页 8×6 范围"
	return ""


static func _unique_id_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for item_id: Variant in value:
		if not _stable_id(item_id) or seen.has(item_id):
			return false
		seen[item_id] = true
	return true


static func _exact_dictionary_keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or not expected.has(key):
			return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true


static func _exact_string_keys(value: Variant, expected: Array) -> bool:
	return _exact_dictionary_keys(value, expected)


static func _stable_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > MAX_ITEM_ID_LENGTH:
		return false
	if value != value.strip_edges():
		return false
	for character: int in value.to_utf8_buffer():
		if character < 32 or character == 127:
			return false
	return true


static func _failure(error_code: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"error_code": error_code,
		"reason": reason,
		"occupied_cells": {},
		"occupied_targets": {},
	}
