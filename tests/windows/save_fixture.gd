extends RefCounted
## Literal, checked-in historical records; never derived from BuildState._snapshot().
const DIRECTORY: String = "res://tests/windows/save_fixtures/"

static func record(version: int) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "save_v%d.json" % version))
	return value if value is Dictionary else {}


static func bytes(version: int, bom: bool = true, crlf: bool = true) -> PackedByteArray:
	var text: String = FileAccess.get_file_as_string(DIRECTORY + "save_v%d.json" % version)
	text = "\n  " + text.replace("\r\n", "\n").strip_edges() + "\n\n"
	if crlf:
		text = text.replace("\n", "\r\n")
	var result: PackedByteArray = PackedByteArray([239, 187, 191]) if bom else PackedByteArray()
	result.append_array(text.to_utf8_buffer())
	return result


static func equivalent(actual: Variant, expected: Variant) -> bool:
	# JSON parses integral numbers as floats; model rolls/cells are canonical ints.
	# Reparse BOTH independent values, comparing every field without type artifacts.
	return JSON.parse_string(JSON.stringify(actual, "", true, true)) == JSON.parse_string(JSON.stringify(expected, "", true, true))
