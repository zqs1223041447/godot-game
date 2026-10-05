extends SceneTree
## Read retained evidence only; no main scene, simulation, import or save write.
func _initialize() -> void:
	var prefix: String = OS.get_environment("MANA_GUARD_INSPECT_PREFIX")
	if prefix.is_empty(): quit(78); return
	var result: Dictionary = {}
	for side: String in ["old", "new"]:
		var archive: PackedByteArray = FileAccess.get_file_as_bytes(prefix + "-legacy-" + side + ".bin.gz")
		var raw := archive.decompress_dynamic(20000000, FileAccess.COMPRESSION_GZIP)
		var frames: Array = bytes_to_var(raw)
		var seen: Dictionary = {}; var player := 0.0; var monster := 0.0
		for frame: Dictionary in frames:
			for segment: Dictionary in frame.burn_trace:
				var identity := var_to_bytes([segment.target_kind, segment.target_id, segment.from_time, segment.to_time, segment.raw_dps, segment.get("provenance", {})])
				if seen.has(identity): continue
				seen[identity] = true
				if segment.target_kind == "player": player += float(segment.settlement.health_lost)
				else: monster += float(segment.settlement.health_lost)
		result[side] = {"frames": frames.size(), "unique_burn_segments": seen.size(), "player_burn_actual_life_loss": player, "monster_burn_actual_life_loss": monster}
	result["equal"] = result.old == result.new
	result["source"] = "Read retained observation archives only; no simulation rerun"
	FileAccess.open(prefix + "-burn-deduplicated.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t", true, true))
	print(JSON.stringify(result))
	quit(0 if result.equal and result.old.player_burn_actual_life_loss > 0.0 and result.old.monster_burn_actual_life_loss > 0.0 else 1)
