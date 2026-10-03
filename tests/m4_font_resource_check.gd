extends SceneTree
func _initialize() -> void:
	var font := load("res://assets/fonts/arena_sans.otf") as FontFile
	font.allow_system_fallback = false
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fonts/coverage_manifest.json"))
	var all_chars: String = manifest.baseline.characters + manifest.generation.added_since_baseline
	var seen := {}
	var missing := []
	for index: int in range(all_chars.length()):
		var codepoint := all_chars.unicode_at(index)
		if seen.has(codepoint): continue
		seen[codepoint] = true
		if not font.has_char(codepoint): missing.append(codepoint)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(font.data)
	var actual := digest.finish().hex_encode()
	var matched: bool = actual == str(manifest.generation.font_sha256)
	print(JSON.stringify({"mapped_checks":seen.size(),"missing":missing,"source_data_hash_matches":matched,"sha256":actual,"system_fallback":font.allow_system_fallback}))
	quit(0 if missing.is_empty() and matched else 1)
