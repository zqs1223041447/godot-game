class_name CanonicalBuildStore
extends RefCounted
## The canonical tables are the sole owner. All UI views are detached projections.
## A user transaction persists its validated candidate before exposing new memory.
signal changed
const Legacy = preload("res://scripts/build_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/canonical_build_migration.gd")
const PagedMigration = preload("res://scripts/save/paged_bag_migration.gd")
const HotkeyMigration = preload("res://scripts/save/reserved_hotkey_migration.gd")
const FlaskMigration = preload("res://scripts/save/flask_item_migration.gd")
const ActiveMigration = preload("res://scripts/save/active_skill_migration.gd")
const CurrencyMigration = preload("res://scripts/save/currency_item_migration.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Currency = preload("res://scripts/items/currency_catalog.gd")
const ItemLocationRules = preload("res://scripts/items/item_location_rules.gd")
const Transfer = preload("res://scripts/items/item_transfer_plan.gd")
const MAX_SAVE_BYTES := 2097152
var _current: Dictionary = {}
var _content_epoch := 0
var _io = Legacy.new()
var _path: String = ""
var _disk_bytes := PackedByteArray()
var _disk_expected_exists := false
var _disk_revision := -1
var _busy := false
var _talent_validator := Callable()
var _socket_ids: Array = []
var last_error: String = ""
var save_attempts := 0
var successful_saves := 0


func _init() -> void:
	_socket_ids = Rules.SourceTree.Data.standard_socket_ids()
	var legacy_default: Dictionary = Migration.migrate(_io._snapshot())
	var paged_default: Dictionary = PagedMigration.migrate_v14(legacy_default, _socket_ids)
	_current = HotkeyMigration.migrate_v18(FlaskMigration.migrate_v17(ActiveMigration.migrate_v16(CurrencyMigration.migrate_v15(paged_default, _socket_ids), _talent_validator, _socket_ids),_talent_validator,_socket_ids),_talent_validator,_socket_ids)
	assert(not _current.is_empty() and Rules.reason(_current).is_empty(), "The built-in canonical fixture must migrate to v19")
	_current.migration_ledger.from_version = 0


func snapshot() -> Dictionary:
	return _current.duplicate(true)


func revision() -> int:
	return int(_current.revision)


func item(uid: String) -> Dictionary:
	return _current.items.get(uid, {}).duplicate(true)


func location(uid: String) -> Dictionary:
	return _current.locations.get(uid, {}).duplicate(true)


func item_definition(uid: String) -> Dictionary:
	return Items.definition_for_instance(_current.items.get(uid, {}))


func skill_group(group_id: String) -> Dictionary:
	return Rules.skill_contents(_current, group_id)


func pending_items() -> Array[String]:
	var result: Array[String] = []
	for uid: String in _current.locations:
		if _current.locations[uid].kind == "recovery": result.append(uid)
	result.sort_custom(func(a: String, b: String) -> bool: return int(_current.locations[a].index) < int(_current.locations[b].index))
	return result


func bag_layout() -> Dictionary:
	return {"pages": ItemLocationRules.CURRENT_BAG_PAGES,"columns":ItemLocationRules.CURRENT_BAG_COLUMNS,"rows":ItemLocationRules.CURRENT_BAG_ROWS}


func load_build(path: String = "user://build_save.json") -> bool:
	if _busy: return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		if FileAccess.file_exists(path): return _reject(path, "存档无法读取")
		_path = path
		_disk_expected_exists = false
		_disk_bytes.clear()
		_disk_revision = -1
		return false
	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return _reject(path, "存档大小超出安全上限")
	var bytes := file.get_buffer(file.get_length())
	file.seek(0)
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK: return _reject(path, "存档格式损坏")
	var raw: Variant = parser.data
	if not raw is Dictionary or not Items._whole(raw.get("version"), 1, Rules.MAX_SERIAL): return _reject(path, "存档属于未知版本")
	var old_version := int(raw.version)
	if old_version > Rules.VERSION: return _reject(path, "存档属于未来版本，已保护原文件")
	var candidate: Dictionary = {}
	if old_version < Rules.VERSION:
		var source_v18:Dictionary={}
		if old_version==Rules.V18_VERSION:
			source_v18=Rules.decode_v18(raw)
		else:
			var source_v17:Dictionary={}
			if old_version==Rules.V17_VERSION:
				source_v17=Rules.decode_v17(raw)
			else:
				var source_v16: Dictionary = {}
				if old_version == Rules.V16_VERSION:
					source_v16 = Rules.decode_v16(raw)
				else:
					var source_v14: Dictionary = {}
					var source_v15: Dictionary = {}
					if old_version == Rules.V14_VERSION:
						source_v14 = Rules.decode_v14(raw)
					elif old_version == Rules.V15_VERSION:
						source_v15 = Rules.decode_v15(raw)
					else:
						var legacy_v14: Dictionary = Migration.migrate(raw)
						source_v14 = Rules.decode_v14(legacy_v14)
					var valid_v15: Dictionary = {}
					if old_version == Rules.V15_VERSION:
						var v15_reason: String = Rules.reason_v15(source_v15, _talent_validator, _socket_ids)
						if not v15_reason.is_empty(): return _reject(path, v15_reason)
						valid_v15 = source_v15
					else:
						var v14_reason: String = Rules.reason_v14(source_v14, _talent_validator, _socket_ids)
						if not v14_reason.is_empty(): return _reject(path, v14_reason)
						valid_v15 = PagedMigration.migrate_v14(source_v14, _socket_ids)
						var migrated_v15_reason: String = Rules.reason_v15(valid_v15, _talent_validator, _socket_ids)
						if not migrated_v15_reason.is_empty(): return _reject(path, migrated_v15_reason)
					source_v16 = CurrencyMigration.migrate_v15(valid_v15, _socket_ids)
				source_v17 = ActiveMigration.migrate_v16(source_v16, _talent_validator, _socket_ids)
			source_v18=FlaskMigration.migrate_v17(source_v17,_talent_validator,_socket_ids)
		candidate=HotkeyMigration.migrate_v18(source_v18,_talent_validator,_socket_ids)
	else:
		candidate = Rules.decode(raw)
	var reason: String = Rules.reason(candidate, _talent_validator, _socket_ids)
	if not reason.is_empty(): return _reject(path, reason)
	var loaded_revision: int = int(candidate.revision)
	# No memory or source overwrite until the original byte backup AND the new
	# candidate commit succeed. A conflict preserves both the old file and state.
	if old_version < Rules.VERSION:
		_io._migration_source_path = path
		_io._migration_source_bytes = bytes
		_io._migration_version = old_version
		var backup_error: Error = _io._backup_legacy_save(path)
		if backup_error != OK: return _reject(path, "原存档备份未完成：%s" % error_string(backup_error))
		var serialized: String = JSON.stringify(candidate, "\t", true, true)
		if serialized.to_utf8_buffer().size() > MAX_SAVE_BYTES: return _reject(path, "迁移后存档过大")
		if FileAccess.get_file_as_bytes(path) != bytes: return _reject(path, "迁移期间原文件被外部修改")
		save_attempts += 1
		var write_error: Error = _write_bytes(path, serialized.to_utf8_buffer())
		if write_error != OK: return _reject(path, "迁移保存失败：%s" % error_string(write_error))
		successful_saves += 1
		bytes = serialized.to_utf8_buffer()
	_accept_memory(candidate)
	_path = path
	_disk_bytes = bytes
	_disk_expected_exists = true
	_disk_revision = loaded_revision
	_io._migration_source_bytes.clear()
	for blocked: String in _io._blocked_save_paths.keys():
		if Legacy._save_paths_match(blocked, path): _io._blocked_save_paths.erase(blocked)
	last_error = ""
	_busy = true
	changed.emit()
	_busy = false
	return true


func save_build(path: String = "user://build_save.json") -> Error:
	if _busy: return ERR_BUSY
	_busy = true
	var error: Error = _persist(_current, path)
	_busy = false
	return error


func can_move_item(uid: Variant, destination: Variant, expected_revision: Variant) -> bool:
	if _busy: return false
	var merge: Dictionary = _currency_merge_plan(uid, destination, expected_revision)
	if merge.handled:
		return merge.ok and Rules.reason(_prepare_candidate(merge.candidate), _talent_validator, _socket_ids).is_empty()
	var planned: Dictionary = Transfer.move_paged(Items.metadata_for_items(_current.items), _current.locations,
		Migration.paged_location_context(_current, _socket_ids), uid, destination, _current.revision, expected_revision)
	if not planned.ok: return false
	var candidate := snapshot()
	candidate.locations = planned.locations
	candidate.revision = planned.revision
	return Rules.reason(_prepare_candidate(candidate), _talent_validator, _socket_ids).is_empty()


func first_bag_position(uid: String) -> Dictionary:
	if not _current.items.has(uid): return {}
	return Transfer.first_bag_space_paged(Items.metadata_for_items(_current.items), _current.locations,
		Migration.paged_location_context(_current, _socket_ids), uid)


func move_item(uid: Variant, destination: Variant, expected_revision: Variant, path: String) -> Dictionary:
	if _busy: return _failure("busy", "当前操作尚未结束")
	var merge: Dictionary = _currency_merge_plan(uid, destination, expected_revision)
	if merge.handled:
		if not merge.ok: return _failure(merge.error_code, merge.reason)
		return _commit(merge.candidate, path)
	var planned: Dictionary = Transfer.move_paged(Items.metadata_for_items(_current.items), _current.locations,
		Migration.paged_location_context(_current, _socket_ids), uid, destination, _current.revision, expected_revision)
	if not planned.ok: return planned
	var candidate: Dictionary = _current.duplicate(true)
	candidate.locations = planned.locations
	candidate.revision = planned.revision
	return _commit(candidate, path)


func _currency_merge_plan(uid: Variant, destination: Variant, expected_revision: Variant) -> Dictionary:
	var result := {"handled": false, "ok": false, "error_code": "", "reason": "", "candidate": {}}
	if not uid is String or not destination is Dictionary or destination.get("kind", "") != "bag" \
			or not _current.items.has(uid) or not Currency.validate_instance(_current.items[uid]):
		return result
	if not ItemLocationRules._current_location_shape_error(destination, "bag").is_empty():
		return result
	var source_location: Dictionary = _current.locations.get(uid, {})
	if source_location.get("kind", "") not in ["bag", "recovery"]:
		return result
	var target_uid := ""
	for other: String in _current.locations:
		if other == uid:
			continue
		var location: Dictionary = _current.locations[other]
		if location.get("kind", "") == "bag" and location.page == destination.page \
				and location.x == destination.x and location.y == destination.y:
			target_uid = other
			break
	if target_uid.is_empty() or not _current.items.has(target_uid) \
			or not Currency.validate_instance(_current.items[target_uid]) \
			or _current.items[target_uid].definition_id != _current.items[uid].definition_id:
		return result
	result.handled = true
	if not expected_revision is int or expected_revision != _current.revision \
			or _current.revision >= Transfer.MAX_REVISION:
		result.error_code = "stale_revision"
		result.reason = "物品位置已变化，请重新操作。"
		return result
	var source_quantity: int = _current.items[uid].payload.quantity
	var target_quantity: int = _current.items[target_uid].payload.quantity
	if source_quantity > Currency.STACK_LIMIT - target_quantity:
		result.error_code = "stack_limit"
		result.reason = "目标碎片堆空间不足，不能部分合并。"
		return result
	var candidate: Dictionary = snapshot()
	candidate.items[target_uid].payload.quantity = target_quantity + source_quantity
	candidate.items.erase(uid)
	candidate.locations.erase(uid)
	candidate.locations = Transfer.compact_recovery(candidate.locations)
	candidate.revision += 1
	var reason: String = Rules.reason(_prepare_candidate(candidate), _talent_validator, _socket_ids)
	if not reason.is_empty():
		result.error_code = "invalid_candidate"
		result.reason = reason
		return result
	result.ok = true
	result.candidate = candidate
	return result


func arrange_items(expected_revision: Variant, path: String) -> Dictionary:
	if _busy: return _failure("busy", "当前操作尚未结束")
	var planned: Dictionary = Transfer.arrange_paged(Items.metadata_for_items(_current.items), _current.locations,
		Migration.paged_location_context(_current, _socket_ids), _current.revision, expected_revision)
	if not planned.ok: return planned
	var candidate: Dictionary = _current.duplicate(true)
	candidate.locations = planned.locations
	candidate.revision = planned.revision
	return _commit(candidate, path)


func _commit(candidate: Dictionary, path: String) -> Dictionary:
	_busy = true
	candidate = _prepare_candidate(candidate)
	var reason: String = Rules.reason(candidate, _talent_validator, _socket_ids)
	if not reason.is_empty():
		_busy = false
		return _failure("invalid_candidate", reason)
	var error: Error = _persist(candidate, path)
	if error != OK:
		_busy = false
		return _failure("save_failed", last_error)
	_accept_memory(candidate)
	# Listeners may read but cannot re-enter a second write during this signal.
	changed.emit()
	_busy = false
	return {"ok": true, "error_code": "", "reason": "", "revision": int(_current.revision)}


func _accept_memory(candidate: Dictionary) -> void:
	_current = candidate
	_content_epoch += 1


func _prepare_candidate(candidate: Dictionary) -> Dictionary:
	return candidate


func _persist(candidate: Dictionary, path: String) -> Error:
	var block: String = _io.save_block_reason(path)
	if not block.is_empty():
		last_error = block
		return ERR_INVALID_DATA
	var reason: String = Rules.reason(candidate, _talent_validator, _socket_ids)
	if not reason.is_empty():
		last_error = reason
		return ERR_INVALID_DATA
	var same_path: bool = Legacy._save_paths_match(path, _path)
	if same_path:
		if FileAccess.file_exists(path) != _disk_expected_exists or (_disk_expected_exists and FileAccess.get_file_as_bytes(path) != _disk_bytes):
			last_error = "存档已被外部修改，请重新读取后再操作"
			return ERR_FILE_ALREADY_IN_USE
	elif FileAccess.file_exists(path):
		last_error = "新保存目标已存在，请先读取该文件"
		return ERR_FILE_ALREADY_IN_USE
	var serialized_revision: int = int(candidate.revision)
	var bytes: PackedByteArray = JSON.stringify(candidate, "\t", true, true).to_utf8_buffer()
	if bytes.size() > MAX_SAVE_BYTES: return ERR_INVALID_DATA
	save_attempts += 1
	var error: Error = _write_bytes(path, bytes)
	if error != OK:
		last_error = "保存失败，物品与材料保持原样：%s" % error_string(error)
		return error
	_path = path
	_disk_bytes = bytes
	_disk_expected_exists = true
	_disk_revision = serialized_revision
	successful_saves += 1
	last_error = ""
	return OK


func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
	return Legacy._atomic_write_bytes(path, bytes)


func _reject(path: String, reason: String) -> bool:
	_io._reject_load(path, reason)
	last_error = _io.last_load_error
	return false


static func _failure(code: String, reason: String) -> Dictionary:
	return {"ok": false, "error_code": code, "reason": reason, "revision": -1}


func _canonical_disk_stamp(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":true,"exists":false}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {"ok":false}
	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return {"ok":false}
	var bytes := file.get_buffer(file.get_length())
	var read_error := file.get_error()
	file.seek(0)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if read_error != OK or parse_error != OK: return {"ok":false}
	var candidate: Dictionary = Rules.decode(parser.data)
	if not Rules.reason(candidate,_talent_validator,_socket_ids).is_empty(): return {"ok":false}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return {"ok":true,"exists":true,"sha256":digest.finish().hex_encode()}
