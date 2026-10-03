class_name ItemTransferPlan
extends RefCounted
## Pure location candidates. The owner validates payloads, skill/passive rules,
## persists one complete build, then commits memory and emits its notification.
const Layout = preload("res://scripts/items/item_location_rules.gd")
const MAX_REVISION: int = 1000000000


static func move(metadata: Variant, locations: Variant, context: Variant, uid: Variant,
		destination: Variant, revision: Variant, expected_revision: Variant) -> Dictionary:
	var rejected: Dictionary = _initial(metadata, locations, context, revision, expected_revision)
	if not rejected.is_empty():
		return rejected
	if not uid is String or not metadata.has(uid):
		return _failure("unknown_item", "物品已变化。")
	if not destination is Dictionary or not destination.get("kind") is String \
			or not Layout._location_shape_error(destination, destination.kind).is_empty():
		return _failure("invalid_destination", "目标位置无效。")
	if destination.kind == "recovery":
		return _failure("recovery_destination_forbidden", "待安置位置只用于迁移，不能作为普通背包。")
	var source: Dictionary = locations[uid]
	if source == destination:
		return _failure("no_change", "")
	var candidate: Dictionary = locations.duplicate(true)
	candidate[uid] = destination.duplicate(true)
	var displaced: String = ""
	var target: String = _target_key(destination)
	if not target.is_empty():
		for other: String in locations:
			if other != uid and _target_key(locations[other]) == target:
				displaced = other
				break
	if not displaced.is_empty():
		if source.kind == "recovery":
			# Recovering an item may not create another hidden pending item.
			var place: Dictionary = _first_bag_space(metadata, candidate, displaced)
			if place.is_empty():
				return _failure("bag_full", "背包没有位置放回原物品。")
			candidate[displaced] = place
		else:
			candidate[displaced] = source.duplicate(true)
	if source.kind == "recovery":
		candidate = compact_recovery(candidate)
	var checked: Dictionary = Layout.validate(metadata, candidate, context)
	if not checked.ok and not displaced.is_empty() and source.kind == "bag" \
			and checked.error_code in ["bag_overlap", "out_of_bounds", "invalid_location"]:
		var place: Dictionary = _first_bag_space(metadata, candidate, displaced)
		if not place.is_empty():
			candidate[displaced] = place
			checked = Layout.validate(metadata, candidate, context)
	if not checked.ok:
		return _failure(checked.error_code, checked.reason)
	return {"ok": true, "error_code": "", "reason": "", "locations": candidate,
		"revision": int(revision) + 1, "moved_uid": uid, "displaced_uid": displaced}


static func arrange(metadata: Variant, locations: Variant, context: Variant,
		revision: Variant, expected_revision: Variant) -> Dictionary:
	var rejected: Dictionary = _initial(metadata, locations, context, revision, expected_revision)
	if not rejected.is_empty():
		return rejected
	var bags: Array[String] = []
	var candidate: Dictionary = locations.duplicate(true)
	for uid: String in candidate:
		if candidate[uid].kind == "bag":
			bags.append(uid)
	bags.sort_custom(func(a: String, b: String) -> bool:
		var a_area: int = int(metadata[a].size[0]) * int(metadata[a].size[1])
		var b_area: int = int(metadata[b].size[0]) * int(metadata[b].size[1])
		return a < b if a_area == b_area else a_area > b_area)
	var occupied: Dictionary = {}
	for uid: String in bags:
		var place: Dictionary = _space_in_cells(metadata[uid].size, occupied)
		if place.is_empty():
			return _failure("cannot_arrange", "当前物品无法按此顺序整理，原位置保持。")
		candidate[uid] = place
		_occupy(occupied, uid, place, metadata[uid].size)
	var checked: Dictionary = Layout.validate(metadata, candidate, context)
	if not checked.ok:
		return _failure(checked.error_code, checked.reason)
	if candidate == locations:
		return _failure("no_change", "")
	return {"ok": true, "error_code": "", "reason": "", "locations": candidate,
		"revision": int(revision) + 1, "moved_uid": "", "displaced_uid": ""}


## The final state owner also uses this after consuming/removing an item. It
## preserves queue order and UID while preventing stale high indices after N shrinks.
static func compact_recovery(locations: Dictionary) -> Dictionary:
	var result: Dictionary = locations.duplicate(true)
	var pending: Array[String] = []
	for uid: String in result:
		if result[uid].kind == "recovery":
			pending.append(uid)
	pending.sort_custom(func(a: String, b: String) -> bool: return int(result[a].index) < int(result[b].index))
	for index: int in range(pending.size()):
		result[pending[index]].index = index
	return result


static func _initial(metadata: Variant, locations: Variant, context: Variant,
		revision: Variant, expected_revision: Variant) -> Dictionary:
	if not revision is int or revision < 0 or revision >= MAX_REVISION \
			or not expected_revision is int or expected_revision != revision:
		return _failure("stale_revision", "物品位置已变化，请重新操作。")
	var checked: Dictionary = Layout.validate(metadata, locations, context)
	return {} if checked.ok else _failure(checked.error_code, checked.reason)


static func _first_bag_space(metadata: Dictionary, locations: Dictionary, moving: String) -> Dictionary:
	var occupied: Dictionary = {}
	for uid: String in locations:
		if uid != moving and locations[uid].kind == "bag":
			_occupy(occupied, uid, locations[uid], metadata[uid].size)
	return _space_in_cells(metadata[moving].size, occupied)


static func _space_in_cells(size: Array, occupied: Dictionary) -> Dictionary:
	for y: int in range(Layout.BAG_ROWS - int(size[1]) + 1):
		for x: int in range(Layout.BAG_COLUMNS - int(size[0]) + 1):
			var fits: bool = true
			for dy: int in range(int(size[1])):
				for dx: int in range(int(size[0])):
					if occupied.has(Vector2i(x + dx, y + dy)):
						fits = false
			if fits:
				return {"kind": "bag", "x": x, "y": y}
	return {}


static func _occupy(occupied: Dictionary, uid: String, location: Dictionary, size: Array) -> void:
	for y: int in range(int(location.y), int(location.y) + int(size[1])):
		for x: int in range(int(location.x), int(location.x) + int(size[0])):
			occupied[Vector2i(x,y)] = uid


static func _target_key(location: Dictionary) -> String:
	match location.kind:
		"equipment": return "equipment:" + str(location.slot_id)
		"passive_socket": return "passive_socket:" + str(location.node_id)
		"skill_main": return "skill_main:" + str(location.group_id)
		"skill_support": return "skill_support:%s:%d" % [location.group_id, location.index]
	return ""


static func _failure(code: String, reason: String) -> Dictionary:
	return {"ok": false, "error_code": code, "reason": reason, "locations": {},
		"revision": -1, "moved_uid": "", "displaced_uid": ""}
