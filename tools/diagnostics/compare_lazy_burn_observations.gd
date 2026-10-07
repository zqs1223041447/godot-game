extends SceneTree
## Read-only v097 comparison of var_to_bytes observations. Run with --script.
## V097_BEFORE and V097_AFTER name input .bin files; V097_COMPARE_OUT is JSON.
## Optional V097_DIFF_STREAM receives every numeric/exact difference as JSONL.
## Only the explicitly listed finite-float leaves may use an error tolerance.

const ABSOLUTE_TOLERANCE: float = 1.0e-10
const RELATIVE_TOLERANCE: float = 1.0e-12
const DETAIL_LIMIT: int = 20

var _frame_array: bool = false
var _diff_stream: FileAccess
var _diff_stream_failed: bool = false
var _diff_stream_rows: int = 0
var _report: Dictionary = {
	"ok": false,
	"exact_input_bytes_equal": false,
	"absolute_tolerance": ABSOLUTE_TOLERANCE,
	"relative_tolerance": RELATIVE_TOLERANCE,
	"tolerance_rule": "abs_error <= max(1e-10, 1e-12 * max(abs(before), abs(after)))",
	"allowed_float_paths": [
		"$.enemies[index].health",
		"$.v095_latest_state.projectile_ids[3][monster_id].health",
		"$.total_damage",
		"$.feedback[1 or 2][bucket].amount",
		"$.feedback[1 or 2][bucket].shield_spent",
		"$.feedback[1 or 2][bucket].health_lost",
	],
	"health_tolerance_requires_same_alive_classification": true,
	"exact_discrete_difference_count": 0,
	"rejected_difference_count": 0,
	"differences": [],
	"numeric": {
		"difference_count": 0,
		"tolerated_count": 0,
		"rejected_count": 0,
		"max_absolute_error": 0.0,
		"max_relative_error": 0.0,
		"max_absolute_path": "",
		"max_relative_path": "",
	},
	"skipped_burn_trace": {
		"array_count": 0,
		"changed_array_count": 0,
		"before_entry_count": 0,
		"after_entry_count": 0,
		"arrays": [],
	},
	"input_errors": [],
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var before_path: String = OS.get_environment("V097_BEFORE")
	var after_path: String = OS.get_environment("V097_AFTER")
	var output_path: String = OS.get_environment("V097_COMPARE_OUT")
	if output_path.is_empty():
		printerr("V097_COMPARE_OUT must name the comparison JSON output")
		quit(1)
		return
	_open_diff_stream(before_path, after_path, output_path)
	var before_bytes: PackedByteArray = _read_input(before_path, "before")
	var after_bytes: PackedByteArray = _read_input(after_path, "after")
	if _report.input_errors.is_empty():
		var before: Variant = bytes_to_var(before_bytes)
		var after: Variant = bytes_to_var(after_bytes)
		_validate_root(before, "before")
		_validate_root(after, "after")
		_report["before"] = {"bytes": before_bytes.size(), "sha256": _sha(before_bytes)}
		_report["after"] = {"bytes": after_bytes.size(), "sha256": _sha(after_bytes)}
		_report.exact_input_bytes_equal = before_bytes == after_bytes
		if _report.input_errors.is_empty():
			_frame_array = typeof(before) == TYPE_ARRAY and typeof(after) == TYPE_ARRAY
			_report["root_kind"] = "frame_array" if _frame_array else "final_observation"
			if _frame_array:
				var frame_exact: Array[bool] = []
				for index: int in range(mini(before.size(), after.size())):
					frame_exact.append(var_to_bytes(before[index]) == var_to_bytes(after[index]))
				_report["per_frame_exact_bytes_equal"] = frame_exact
			_compare(before, after, [])
	_report.rejected_difference_count = int(_report.exact_discrete_difference_count) + int(_report.numeric.rejected_count)
	_close_diff_stream()
	_report.ok = _report.input_errors.is_empty() and _report.rejected_difference_count == 0 and not _diff_stream_failed
	_report["difference_details_truncated"] = int(_report.rejected_difference_count) > _report.differences.size()
	_report.numeric.max_absolute_error = _json_number(float(_report.numeric.max_absolute_error))
	_report.numeric.max_relative_error = _json_number(float(_report.numeric.max_relative_error))
	var output: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		printerr("Cannot write V097_COMPARE_OUT: ", FileAccess.get_open_error())
		quit(1)
		return
	output.store_string(JSON.stringify(_report, "\t", true, true) + "\n")
	output.flush()
	var write_error: Error = output.get_error()
	output.close()
	if write_error != OK:
		printerr("Cannot finish V097_COMPARE_OUT: ", write_error)
		quit(1)
		return
	print("V097_COMPARE ", "PASS" if _report.ok else "FAIL", " exact_discrete=", _report.exact_discrete_difference_count,
		" numeric_tolerated=", _report.numeric.tolerated_count, " numeric_rejected=", _report.numeric.rejected_count,
		" skipped_trace_arrays=", _report.skipped_burn_trace.array_count)
	quit(0 if _report.ok else 1)


func _open_diff_stream(before_path: String, after_path: String, output_path: String) -> void:
	var stream_path: String = OS.get_environment("V097_DIFF_STREAM")
	if stream_path.is_empty():
		return
	for protected_path: String in [before_path, after_path, output_path]:
		if ProjectSettings.globalize_path(stream_path).simplify_path() == ProjectSettings.globalize_path(protected_path).simplify_path():
			_diff_stream_failed = true
			_report["diff_stream_error"] = "V097_DIFF_STREAM must differ from both inputs and the summary output"
			return
	_diff_stream = FileAccess.open(stream_path, FileAccess.WRITE)
	if _diff_stream == null:
		_diff_stream_failed = true
		_report["diff_stream_error"] = "Cannot open V097_DIFF_STREAM (error " + str(FileAccess.get_open_error()) + ")"


func _close_diff_stream() -> void:
	if _diff_stream == null:
		return
	_diff_stream.flush()
	var write_error: Error = _diff_stream.get_error()
	_diff_stream.close()
	_diff_stream = null
	_report["diff_stream_rows"] = _diff_stream_rows
	if write_error != OK:
		_diff_stream_failed = true
		_report["diff_stream_error"] = "Cannot finish V097_DIFF_STREAM (error " + str(write_error) + ")"


func _stream_difference(detail: Dictionary, path: Array) -> void:
	if _diff_stream == null:
		return
	var row: Dictionary = detail.duplicate()
	row["path_components"] = _typed_path_components(path)
	_diff_stream.store_string(JSON.stringify(row, "", true, true) + "\n")
	_diff_stream_rows += 1


func _typed_path_components(path: Array) -> Array:
	var result: Array = []
	for component: Variant in path:
		var entry: Dictionary = {"type": type_string(typeof(component))}
		if typeof(component) == TYPE_STRING or typeof(component) == TYPE_STRING_NAME:
			entry["value"] = str(component)
		elif typeof(component) == TYPE_INT:
			entry["value"] = component
		else:
			entry["sha256"] = _sha(var_to_bytes(component))
		result.append(entry)
	return result


func _read_input(path: String, label: String) -> PackedByteArray:
	if path.is_empty():
		_report.input_errors.append(label + ": input environment variable is empty")
		return PackedByteArray()
	var input: FileAccess = FileAccess.open(path, FileAccess.READ)
	if input == null:
		_report.input_errors.append(label + ": cannot open input (error " + str(FileAccess.get_open_error()) + ")")
		return PackedByteArray()
	var expected_length: int = input.get_length()
	var data: PackedByteArray = input.get_buffer(expected_length)
	input.close()
	if data.is_empty() or data.size() != expected_length:
		_report.input_errors.append(label + ": empty or incomplete input")
	return data


func _validate_root(value: Variant, label: String) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		return
	if typeof(value) != TYPE_ARRAY:
		_report.input_errors.append(label + ": expected a final Dictionary or an Array of frame Dictionaries")
		return
	for index: int in range(value.size()):
		if typeof(value[index]) != TYPE_DICTIONARY:
			_report.input_errors.append(label + ": frame " + str(index) + " is not a Dictionary")
			return


func _compare(before: Variant, after: Variant, path: Array, containers: Array = []) -> void:
	if typeof(before) != typeof(after):
		_discrete(path, "variant_type", before, after)
		return
	if _is_burn_trace(path):
		if typeof(before) == TYPE_ARRAY:
			_skip_trace(before, after, path)
		else:
			_discrete(path, "burn_trace_must_be_array", before, after)
		return
	match typeof(before):
		TYPE_DICTIONARY:
			_compare_dictionary(before, after, path, containers)
		TYPE_ARRAY:
			_compare_array(before, after, path, containers)
		_:
			if var_to_bytes(before) == var_to_bytes(after):
				return
			if typeof(before) == TYPE_FLOAT and _allows_float(path, containers):
				# Nonfinite values, float/int type changes, and signed zero are exact.
				if is_finite(before) and is_finite(after) and not (before == 0.0 and after == 0.0):
					if _is_health_path(path, containers) and (before > 0.0) != (after > 0.0):
						_discrete(path, "health_alive_classification", before, after)
						return
					_compare_float(before, after, path)
					return
			_discrete(path, "exact_typed_bytes", before, after)


func _compare_array(before: Array, after: Array, path: Array, containers: Array) -> void:
	# Empty copies preserve typed-array metadata without comparing their contents.
	var before_empty: Array = before.duplicate()
	var after_empty: Array = after.duplicate()
	before_empty.clear()
	after_empty.clear()
	if var_to_bytes(before_empty) != var_to_bytes(after_empty):
		_discrete(path, "array_type_metadata", before_empty, after_empty)
	if before.size() != after.size():
		_discrete(path, "array_length", before.size(), after.size())
	for index: int in range(mini(before.size(), after.size())):
		_compare(before[index], after[index], path + [index], containers + [TYPE_ARRAY])


func _compare_dictionary(before: Dictionary, after: Dictionary, path: Array, containers: Array) -> void:
	var before_empty: Dictionary = before.duplicate()
	var after_empty: Dictionary = after.duplicate()
	before_empty.clear()
	after_empty.clear()
	if var_to_bytes(before_empty) != var_to_bytes(after_empty):
		_discrete(path, "dictionary_type_metadata", before_empty, after_empty)
	var before_keys: Array = before.keys()
	var after_keys: Array = after.keys()
	if var_to_bytes(before_keys) == var_to_bytes(after_keys):
		for key: Variant in before_keys:
			_compare(before[key], after[key], path + [key], containers + [TYPE_DICTIONARY])
		return
	# Dictionary key identity and insertion order are always exact, even for enemies.
	_discrete(path, "dictionary_key_identity_or_insertion_order", before_keys, after_keys)
	var after_key_bytes: Dictionary = {}
	for key: Variant in after_keys:
		after_key_bytes[var_to_bytes(key).hex_encode()] = key
	for key: Variant in before_keys:
		var signature: String = var_to_bytes(key).hex_encode()
		if after_key_bytes.has(signature):
			_compare(before[key], after[after_key_bytes[signature]], path + [key], containers + [TYPE_DICTIONARY])


func _observation_path(path: Array) -> Array:
	# Strip only the initial frame index; never search for matching nested suffixes.
	if _frame_array and not path.is_empty() and typeof(path[0]) == TYPE_INT:
		return path.slice(1)
	return path


func _string_key(value: Variant, expected: String) -> bool:
	return typeof(value) == TYPE_STRING and value == expected


func _allows_float(path: Array, containers: Array) -> bool:
	if _is_health_path(path, containers):
		return true
	var local: Array = _observation_path(path)
	var local_containers: Array = containers.slice(1) if _frame_array else containers
	if local.size() == 1 and local_containers == [TYPE_DICTIONARY]:
		return _string_key(local[0], "total_damage")
	if local.size() == 4 and local_containers == [TYPE_DICTIONARY, TYPE_ARRAY, TYPE_DICTIONARY, TYPE_DICTIONARY] and _string_key(local[0], "feedback"):
		if typeof(local[1]) != TYPE_INT or (local[1] != 1 and local[1] != 2):
			return false
		return _string_key(local[3], "amount") or _string_key(local[3], "shield_spent") or _string_key(local[3], "health_lost")
	return false


func _is_health_path(path: Array, containers: Array) -> bool:
	var local: Array = _observation_path(path)
	var local_containers: Array = containers.slice(1) if _frame_array else containers
	if local.size() == 3 and local_containers == [TYPE_DICTIONARY, TYPE_ARRAY, TYPE_DICTIONARY]:
		return _string_key(local[0], "enemies") and typeof(local[1]) == TYPE_INT and _string_key(local[2], "health")
	# The observer duplicates Main._projectile_targets, whose integer ID entries
	# alias the same enemy Dictionaries. Admit only this exact mirrored leaf.
	if local.size() == 5 and local_containers == [TYPE_DICTIONARY, TYPE_DICTIONARY, TYPE_ARRAY, TYPE_DICTIONARY, TYPE_DICTIONARY]:
		return _string_key(local[0], "v095_latest_state") and _string_key(local[1], "projectile_ids") \
			and typeof(local[2]) == TYPE_INT and local[2] == 3 and typeof(local[3]) == TYPE_INT \
			and _string_key(local[4], "health")
	return false


func _is_burn_trace(path: Array) -> bool:
	var local: Array = _observation_path(path)
	return local.size() == 1 and _string_key(local[0], "burn_trace")


func _compare_float(before: float, after: float, path: Array) -> void:
	var absolute_error: float = absf(before - after)
	var scale: float = maxf(absf(before), absf(after))
	# Divide first if subtraction overflowed; both original values are finite.
	var relative_error: float = absolute_error / scale if is_finite(absolute_error) else absf(before / scale - after / scale)
	var accepted: bool = absolute_error <= maxf(ABSOLUTE_TOLERANCE, RELATIVE_TOLERANCE * scale)
	var numeric: Dictionary = _report.numeric
	numeric.difference_count += 1
	if numeric.difference_count == 1 or absolute_error > float(numeric.max_absolute_error):
		numeric.max_absolute_error = absolute_error
		numeric.max_absolute_path = _path_text(path)
	if numeric.difference_count == 1 or relative_error > float(numeric.max_relative_error):
		numeric.max_relative_error = relative_error
		numeric.max_relative_path = _path_text(path)
	var detail: Dictionary = {"path": _path_text(path), "category": "numeric", "kind": "numeric_within_tolerance" if accepted else "numeric_outside_tolerance",
		"before": before, "after": after, "absolute_error": _json_number(absolute_error), "relative_error": _json_number(relative_error)}
	_stream_difference(detail, path)
	if accepted:
		numeric.tolerated_count += 1
	else:
		numeric.rejected_count += 1
		_detail(detail)
	# JSON has no Infinity; the readable string preserves an overflowed maximum.
	_report["numeric_max_absolute_error_overflowed"] = not is_finite(float(numeric.max_absolute_error))


func _discrete(path: Array, kind: String, before: Variant, after: Variant) -> void:
	_report.exact_discrete_difference_count += 1
	var detail: Dictionary = {"path": _path_text(path), "category": "exact", "kind": kind, "before": _summary(before), "after": _summary(after)}
	_detail(detail)
	var stream_detail: Dictionary = detail.duplicate()
	if typeof(before) == TYPE_FLOAT and typeof(after) == TYPE_FLOAT and is_finite(before) and is_finite(after):
		var absolute_error: float = absf(before - after)
		var scale: float = maxf(absf(before), absf(after))
		var relative_error: float = 0.0 if scale == 0.0 else (absolute_error / scale if is_finite(absolute_error) else absf(before / scale - after / scale))
		stream_detail["absolute_error"] = _json_number(absolute_error)
		stream_detail["relative_error"] = _json_number(relative_error)
	if kind == "dictionary_key_identity_or_insertion_order":
		stream_detail["before_key_order"] = _typed_path_components(before)
		stream_detail["after_key_order"] = _typed_path_components(after)
	_stream_difference(stream_detail, path)


func _detail(detail: Dictionary) -> void:
	if _report.differences.size() < DETAIL_LIMIT:
		_report.differences.append(detail)


func _skip_trace(before: Array, after: Array, path: Array) -> void:
	var before_bytes: PackedByteArray = var_to_bytes(before)
	var after_bytes: PackedByteArray = var_to_bytes(after)
	var skipped: Dictionary = _report.skipped_burn_trace
	skipped.array_count += 1
	skipped.changed_array_count += int(before_bytes != after_bytes)
	skipped.before_entry_count += before.size()
	skipped.after_entry_count += after.size()
	skipped.arrays.append({"path": _path_text(path), "before_count": before.size(), "after_count": after.size(),
		"before_sha256": _sha(before_bytes), "after_sha256": _sha(after_bytes)})


func _summary(value: Variant) -> Dictionary:
	var bytes: PackedByteArray = var_to_bytes(value)
	var result: Dictionary = {"type": type_string(typeof(value)), "bytes": bytes.size(), "sha256": _sha(bytes)}
	if typeof(value) == TYPE_FLOAT:
		result["value"] = _json_number(value)
	elif typeof(value) == TYPE_INT or typeof(value) == TYPE_BOOL or typeof(value) == TYPE_NIL:
		result["value"] = value
	return result


func _json_number(value: float) -> Variant:
	return value if is_finite(value) else str(value)


func _path_text(path: Array) -> String:
	var result: String = "$"
	for component: Variant in path:
		if typeof(component) == TYPE_INT:
			result += "[" + str(component) + "]"
		elif typeof(component) == TYPE_STRING:
			result += "[" + JSON.stringify(component) + "]"
		else:
			result += "[" + type_string(typeof(component)) + ":sha256=" + _sha(var_to_bytes(component)) + "]"
	return result


func _sha(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
