class_name CanonicalBuildStore
extends RefCounted
## The canonical tables are the sole owner. All UI views are detached projections.
## A user transaction persists its validated candidate before exposing new memory.
signal changed
const Legacy = preload("res://scripts/build_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/canonical_build_migration.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Transfer = preload("res://scripts/items/item_transfer_plan.gd")
const MAX_SAVE_BYTES := 2097152
var _current: Dictionary = {}
var _io = Legacy.new()
var _path: String = ""
var _disk_bytes := PackedByteArray()
var _disk_expected_exists := false
var _busy := false
var _talent_validator := Callable()
var _socket_ids: Array = []
var last_error: String = ""
var save_attempts := 0
var successful_saves := 0


func _init() -> void:
	_current = Migration.migrate(_io._snapshot())
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


func load_build(path: String) -> bool:
	if _busy: return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		if FileAccess.file_exists(path): return _reject(path, "存档无法读取")
		_path = path
		_disk_expected_exists = false
		_disk_bytes.clear()
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
	if not raw is Dictionary or not Items._whole(raw.get("version"), 1, Rules.VERSION): return _reject(path, "存档属于未知版本")
	var old_version := int(raw.version)
	var candidate: Dictionary = Migration.migrate(raw) if old_version < Rules.VERSION else Rules.decode(raw)
	var reason: String = Rules.reason(candidate, _talent_validator, _socket_ids)
	if not reason.is_empty(): return _reject(path, reason)
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
	_current = candidate
	_path = path
	_disk_bytes = bytes
	_disk_expected_exists = true
	_io._migration_source_bytes.clear()
	for blocked: String in _io._blocked_save_paths.keys():
		if Legacy._save_paths_match(blocked, path): _io._blocked_save_paths.erase(blocked)
	last_error = ""
	changed.emit()
	return true


func save_build(path: String) -> Error:
	if _busy: return ERR_BUSY
	_busy = true
	var error: Error = _persist(_current, path)
	_busy = false
	return error


func move_item(uid: Variant, destination: Variant, expected_revision: Variant, path: String) -> Dictionary:
	if _busy: return _failure("busy", "当前操作尚未结束")
	var planned: Dictionary = Transfer.move(Items.metadata_for_items(_current.items), _current.locations,
		Migration.location_context(_current, _socket_ids), uid, destination, _current.revision, expected_revision)
	if not planned.ok: return planned
	var candidate: Dictionary = _current.duplicate(true)
	candidate.locations = planned.locations
	candidate.revision = planned.revision
	return _commit(candidate, path)


func arrange_items(expected_revision: Variant, path: String) -> Dictionary:
	if _busy: return _failure("busy", "当前操作尚未结束")
	var planned: Dictionary = Transfer.arrange(Items.metadata_for_items(_current.items), _current.locations,
		Migration.location_context(_current, _socket_ids), _current.revision, expected_revision)
	if not planned.ok: return planned
	var candidate: Dictionary = _current.duplicate(true)
	candidate.locations = planned.locations
	candidate.revision = planned.revision
	return _commit(candidate, path)


func _commit(candidate: Dictionary, path: String) -> Dictionary:
	_busy = true
	var reason: String = Rules.reason(candidate, _talent_validator, _socket_ids)
	if not reason.is_empty():
		_busy = false
		return _failure("invalid_candidate", reason)
	var error: Error = _persist(candidate, path)
	if error != OK:
		_busy = false
		return _failure("save_failed", last_error)
	_current = candidate
	# Listeners may read but cannot re-enter a second write during this signal.
	changed.emit()
	_busy = false
	return {"ok": true, "error_code": "", "reason": "", "revision": int(_current.revision)}


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
