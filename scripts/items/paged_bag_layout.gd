class_name PagedBagLayout
extends RefCounted
## Pure two-page bag planning and occupancy checks.
## The current save owner still validates the legacy 12x8 location protocol.
## This class proposes page-aware locations without changing items or saving state.

const LegacyLayout = preload("res://scripts/items/item_location_rules.gd")
const PAGE_COUNT: int = 2
const PAGE_COLUMNS: int = 8
const PAGE_ROWS: int = 6
const TOTAL_CELLS: int = PAGE_COUNT * PAGE_COLUMNS * PAGE_ROWS


## Convert a fully valid legacy 12x8 location table into page-aware locations.
## Non-bag targets and pre-existing recovery entries keep their exact values.
static func plan(metadata_by_uid: Variant, legacy_locations: Variant, context: Variant) -> Dictionary:
	var source: Dictionary = LegacyLayout.validate(metadata_by_uid, legacy_locations, context)
	if not source.ok:
		return _failure(source.error_code, source.reason)
	return _repack(metadata_by_uid, legacy_locations, context)


## Repack a page-aware layout after a controller requests organization.
## Items already in recovery stay there; newly unplaceable bag items receive a
## fresh visible recovery index rather than being discarded.
static func arrange(metadata_by_uid: Variant, paged_locations: Variant, context: Variant) -> Dictionary:
	var checked: Dictionary = inspect_layout(metadata_by_uid, paged_locations, context)
	if not checked.ok:
		return _failure(checked.error_code, checked.reason)
	return _repack(metadata_by_uid, paged_locations, context)


## Validate a complete page-aware location map and return detached occupancy data.
static func inspect_layout(metadata_by_uid: Variant, paged_locations: Variant, context: Variant) -> Dictionary:
	var input_error: Dictionary = _metadata_and_location_error(metadata_by_uid, paged_locations)
	if not input_error.is_empty():
		return _failure(input_error.code, input_error.reason)
	var context_error: String = LegacyLayout._context_error(context)
	if not context_error.is_empty():
		return _failure("invalid_context", context_error)

	var uids: Array[String] = _sorted_uids(metadata_by_uid)
	var bag_uids: Array[String] = []
	for uid: String in uids:
		var location: Dictionary = paged_locations[uid]
		if location.get("kind", "") == "bag":
			var bag_error: Dictionary = _paged_bag_location_error(metadata_by_uid[uid], location)
			if not bag_error.is_empty():
				return _failure(bag_error.code, "%s：%s" % [uid, bag_error.reason])
			bag_uids.append(uid)
		else:
			var kind: String = str(location.get("kind", ""))
			var shape_error: String = LegacyLayout._location_shape_error(location, kind)
			if not shape_error.is_empty():
				return _failure("invalid_location", "%s：%s" % [uid, shape_error])
	if bag_uids.size() > TOTAL_CELLS:
		return _failure("bag_full", "两页共 96 格，背包物品数量超过可用格数")

	# Reuse the established validator for item-kind/target rules. Each already-
	# checked page item is projected to a distinct temporary 1x1 legacy cell;
	# the real page footprints are checked separately below.
	var validation_metadata: Dictionary = metadata_by_uid.duplicate(true)
	var validation_locations: Dictionary = {}
	var temporary_cell: int = 0
	for uid: String in uids:
		var location: Dictionary = paged_locations[uid]
		if location.kind == "bag":
			validation_metadata[uid].size = [1, 1]
			validation_locations[uid] = {
				"kind": "bag",
				"x": temporary_cell % LegacyLayout.BAG_COLUMNS,
				"y": int(temporary_cell / LegacyLayout.BAG_COLUMNS),
			}
			temporary_cell += 1
		else:
			validation_locations[uid] = location.duplicate(true)
	var established: Dictionary = LegacyLayout.validate(validation_metadata, validation_locations, context)
	if not established.ok:
		return _failure(established.error_code, established.reason)

	var occupied_cells: Dictionary = {}
	for uid: String in bag_uids:
		var location: Dictionary = paged_locations[uid]
		var size: Array = metadata_by_uid[uid].size
		for y: int in range(location.y, location.y + size[1]):
			for x: int in range(location.x, location.x + size[0]):
				var cell_key: String = _cell_key(location.page, x, y)
				if occupied_cells.has(cell_key):
					return _failure("bag_overlap", "%s 与 %s 的背包占格重叠" % [uid, occupied_cells[cell_key]])
				occupied_cells[cell_key] = uid

	var recovery: Array[Dictionary] = _recovery_entries(paged_locations, "existing_recovery")
	var ordered_locations: Dictionary = {}
	for uid: String in uids:
		ordered_locations[uid] = paged_locations[uid].duplicate(true)
	return _success(ordered_locations, recovery, occupied_cells, established.occupied_targets)


## Find the first row-major position, scanning page 0 before page 1.
## This is a probe only; call check_placement to get a detached occupied map
## with the proposed footprint reserved.
static func find_space(size: Variant, occupied_cells: Variant) -> Dictionary:
	var size_error: String = _size_error(size)
	if not size_error.is_empty():
		return _space_failure("invalid_size", size_error, occupied_cells)
	var occupied_error: String = _occupied_cells_error(occupied_cells)
	if not occupied_error.is_empty():
		return _space_failure("invalid_occupied_cells", occupied_error, {})
	if size[0] > PAGE_COLUMNS or size[1] > PAGE_ROWS:
		return _space_failure("item_exceeds_page", "物品尺寸大于单页 8×6", occupied_cells)
	for page: int in range(PAGE_COUNT):
		for y: int in range(PAGE_ROWS - size[1] + 1):
			for x: int in range(PAGE_COLUMNS - size[0] + 1):
				if _footprint_free(size, page, x, y, occupied_cells):
					return {
						"ok": true, "error_code": "", "reason": "",
						"location": {"kind": "bag", "page": page, "x": x, "y": y},
						"occupied_cells": occupied_cells.duplicate(true),
					}
	return _space_failure("no_space", "两页背包没有可容纳该物品的连续格子", occupied_cells)


## Check one proposed placement and, on success, return a new occupied-cell map.
## The caller's map is never changed, including when the placement is rejected.
static func check_placement(uid: Variant, size: Variant, location: Variant, occupied_cells: Variant) -> Dictionary:
	if not LegacyLayout._stable_id(uid):
		return _placement_failure("invalid_uid", "UID 必须是非空稳定字符串", {}, {})
	var size_error: String = _size_error(size)
	if not size_error.is_empty():
		return _placement_failure("invalid_size", size_error, {}, {})
	var occupied_error: String = _occupied_cells_error(occupied_cells)
	if not occupied_error.is_empty():
		return _placement_failure("invalid_occupied_cells", occupied_error, {}, {})
	var location_error: Dictionary = _paged_bag_location_error({"size": size}, location)
	if not location_error.is_empty():
		return _placement_failure(location_error.code, location_error.reason, {}, occupied_cells)
	for y: int in range(location.y, location.y + size[1]):
		for x: int in range(location.x, location.x + size[0]):
			var cell_key: String = _cell_key(location.page, x, y)
			if occupied_cells.has(cell_key):
				return _placement_failure("bag_overlap", "%s 的占格与 %s 重叠" % [uid, occupied_cells[cell_key]], {}, occupied_cells)
	var candidate: Dictionary = occupied_cells.duplicate(true)
	for y: int in range(location.y, location.y + size[1]):
		for x: int in range(location.x, location.x + size[0]):
			candidate[_cell_key(location.page, x, y)] = uid
	return {
		"ok": true, "error_code": "", "reason": "",
		"location": location.duplicate(true), "occupied_cells": candidate,
	}


static func _repack(metadata_by_uid: Dictionary, source_locations: Dictionary, context: Variant) -> Dictionary:
	var candidate: Dictionary = {}
	var bag_uids: Array[String] = []
	var recovery: Array[Dictionary] = []
	var used_recovery_indices: Dictionary = {}
	for uid: String in _sorted_uids(metadata_by_uid):
		var location: Dictionary = source_locations[uid]
		candidate[uid] = location.duplicate(true)
		if location.kind == "bag":
			bag_uids.append(uid)
		elif location.kind == "recovery":
			used_recovery_indices[location.index] = true
			recovery.append({
				"uid": uid,
				"index": location.index,
				"reason": "preserved_existing_recovery",
			})
	bag_uids.sort_custom(func(a: String, b: String) -> bool:
		var size_a: Array = metadata_by_uid[a].size
		var size_b: Array = metadata_by_uid[b].size
		var area_a: int = size_a[0] * size_a[1]
		var area_b: int = size_b[0] * size_b[1]
		if area_a != area_b:
			return area_a > area_b
		var long_a: int = maxi(size_a[0], size_a[1])
		var long_b: int = maxi(size_b[0], size_b[1])
		if long_a != long_b:
			return long_a > long_b
		if size_a[0] != size_b[0]:
			return size_a[0] > size_b[0]
		return a < b
	)

	var occupied_cells: Dictionary = {}
	for uid: String in bag_uids:
		var size: Array = metadata_by_uid[uid].size
		var placement: Dictionary
		if size[0] > PAGE_COLUMNS or size[1] > PAGE_ROWS:
			placement = {"ok": false, "error_code": "item_exceeds_page"}
		else:
			var found: Dictionary = find_space(size, occupied_cells)
			if found.ok:
				placement = check_placement(uid, size, found.location, occupied_cells)
			else:
				placement = found
		if placement.ok:
			candidate[uid] = placement.location.duplicate(true)
			occupied_cells = placement.occupied_cells
			continue

		var recovery_index: int = _first_free_recovery_index(used_recovery_indices, metadata_by_uid.size())
		if recovery_index < 0:
			return _failure("recovery_capacity", "没有可分配的唯一可见 recovery index")
		used_recovery_indices[recovery_index] = true
		candidate[uid] = {"kind": "recovery", "index": recovery_index}
		var item_reason: String = "item_exceeds_page" if placement.error_code == "item_exceeds_page" else "no_paged_space"
		recovery.append({"uid": uid, "index": recovery_index, "reason": item_reason})

	var checked: Dictionary = inspect_layout(metadata_by_uid, candidate, context)
	if not checked.ok:
		return _failure(checked.error_code, checked.reason)
	recovery.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.index != b.index:
			return a.index < b.index
		return a.uid < b.uid
	)
	return _success(checked.locations, recovery, checked.occupied_cells, checked.occupied_targets)


static func _metadata_and_location_error(metadata_by_uid: Variant, locations: Variant) -> Dictionary:
	if not metadata_by_uid is Dictionary or not locations is Dictionary:
		return {"code": "invalid_input", "reason": "metadata_by_uid 与 locations 必须是对象"}
	for uid: Variant in metadata_by_uid:
		if not LegacyLayout._stable_id(uid):
			return {"code": "invalid_metadata", "reason": "物品 UID 必须是非空稳定字符串"}
		var metadata_error: String = LegacyLayout._metadata_error(metadata_by_uid[uid])
		if not metadata_error.is_empty():
			return {"code": "invalid_metadata", "reason": "%s：%s" % [uid, metadata_error]}
	for uid: Variant in locations:
		if not LegacyLayout._stable_id(uid):
			return {"code": "invalid_location", "reason": "位置表 UID 必须是非空稳定字符串"}
	if metadata_by_uid.size() != locations.size():
		return {"code": "location_set_mismatch", "reason": "每件物品必须且只能有一个位置"}
	for uid: String in metadata_by_uid:
		if not locations.has(uid):
			return {"code": "location_set_mismatch", "reason": "%s 缺少唯一位置" % uid}
		if not locations[uid] is Dictionary or not locations[uid].get("kind", "") is String:
			return {"code": "invalid_location", "reason": "%s 的位置必须含字符串 kind" % uid}
	return {}


static func _paged_bag_location_error(metadata: Variant, location: Variant) -> Dictionary:
	if not LegacyLayout._exact_string_keys(location, ["kind", "page", "x", "y"]):
		return {"code": "invalid_location", "reason": "bag 位置字段必须精确为 kind、page、x、y"}
	if location.kind != "bag":
		return {"code": "invalid_location", "reason": "位置 kind 必须是 bag"}
	if typeof(location.page) != TYPE_INT or typeof(location.x) != TYPE_INT or typeof(location.y) != TYPE_INT:
		return {"code": "invalid_location", "reason": "page、x、y 必须是真正的整数"}
	if location.page < 0 or location.page >= PAGE_COUNT or location.x < 0 or location.x >= PAGE_COLUMNS \
			or location.y < 0 or location.y >= PAGE_ROWS:
		return {"code": "out_of_bounds", "reason": "页码或格子坐标超出两页 8×6 背包范围"}
	var item_error: String = _size_error(metadata.get("size", null))
	if not item_error.is_empty():
		return {"code": "invalid_metadata", "reason": item_error}
	if metadata.size[0] > PAGE_COLUMNS or metadata.size[1] > PAGE_ROWS:
		return {"code": "item_exceeds_page", "reason": "物品尺寸大于单页 8×6，必须进入 recovery"}
	if location.x + metadata.size[0] > PAGE_COLUMNS or location.y + metadata.size[1] > PAGE_ROWS:
		return {"code": "page_boundary", "reason": "多格物品不能越过单页边界"}
	return {}


static func _size_error(size: Variant) -> String:
	if not size is Array or size.size() != 2:
		return "size 必须严格为 [width, height]"
	if typeof(size[0]) != TYPE_INT or typeof(size[1]) != TYPE_INT:
		return "size 的 width、height 必须是真正的整数"
	if size[0] < 1 or size[0] > LegacyLayout.BAG_COLUMNS or size[1] < 1 or size[1] > LegacyLayout.BAG_ROWS:
		return "size 必须在旧背包合法范围 1×1 至 12×8 内"
	return ""


static func _occupied_cells_error(occupied_cells: Variant) -> String:
	if not occupied_cells is Dictionary or occupied_cells.size() > TOTAL_CELLS:
		return "occupied_cells 必须是至多 96 格的对象"
	for key: Variant in occupied_cells:
		if typeof(key) != TYPE_STRING:
			return "占用格键必须是 bag:page:x:y 字符串"
		var parts: PackedStringArray = key.split(":")
		if parts.size() != 4 or parts[0] != "bag" or not parts[1].is_valid_int() \
				or not parts[2].is_valid_int() or not parts[3].is_valid_int():
			return "占用格键必须是 bag:page:x:y 字符串"
		var page: int = int(parts[1])
		var x: int = int(parts[2])
		var y: int = int(parts[3])
		if parts[1] != str(page) or parts[2] != str(x) or parts[3] != str(y) \
				or page < 0 or page >= PAGE_COUNT or x < 0 or x >= PAGE_COLUMNS or y < 0 or y >= PAGE_ROWS:
			return "占用格坐标必须是有效的规范整数"
		if not LegacyLayout._stable_id(occupied_cells[key]):
			return "占用格必须记录稳定 UID"
	return ""


static func _footprint_free(size: Array, page: int, x: int, y: int, occupied_cells: Dictionary) -> bool:
	for dy: int in range(size[1]):
		for dx: int in range(size[0]):
			if occupied_cells.has(_cell_key(page, x + dx, y + dy)):
				return false
	return true


static func _cell_key(page: int, x: int, y: int) -> String:
	return "bag:%d:%d:%d" % [page, x, y]


static func _recovery_entries(locations: Dictionary, reason_code: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for uid: String in locations:
		if locations[uid].get("kind", "") == "recovery":
			entries.append({"uid": uid, "index": locations[uid].index, "reason": reason_code})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.index != b.index:
			return a.index < b.index
		return a.uid < b.uid
	)
	return entries


static func _first_free_recovery_index(used: Dictionary, item_count: int) -> int:
	for index: int in range(item_count):
		if not used.has(index):
			return index
	return -1


static func _sorted_uids(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for uid: Variant in values:
		result.append(str(uid))
	result.sort()
	return result


static func _success(locations: Dictionary, recovery: Array[Dictionary], occupied_cells: Dictionary,
		occupied_targets: Dictionary) -> Dictionary:
	var ordered_locations: Dictionary = {}
	for uid: String in _sorted_uids(locations):
		ordered_locations[uid] = locations[uid].duplicate(true)
	return {
		"ok": true,
		"error_code": "",
		"reason": "",
		"locations": ordered_locations,
		"recovery": recovery.duplicate(true),
		"occupied_cells": occupied_cells.duplicate(true),
		"occupied_targets": occupied_targets.duplicate(true),
	}


static func _failure(code: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"error_code": code,
		"reason": reason,
		"locations": {},
		"recovery": [],
		"occupied_cells": {},
		"occupied_targets": {},
	}


static func _space_failure(code: String, reason: String, occupied_cells: Variant) -> Dictionary:
	var detached: Dictionary = occupied_cells.duplicate(true) if occupied_cells is Dictionary else {}
	return {"ok": false, "error_code": code, "reason": reason, "location": {}, "occupied_cells": detached}


static func _placement_failure(code: String, reason: String, location: Dictionary, occupied_cells: Variant) -> Dictionary:
	var detached: Dictionary = occupied_cells.duplicate(true) if occupied_cells is Dictionary else {}
	return {"ok": false, "error_code": code, "reason": reason,
		"location": location.duplicate(true), "occupied_cells": detached}
