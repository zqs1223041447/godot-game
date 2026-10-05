extends SceneTree
## Read already-recorded Variant streams; never instantiate main or simulate.
func _initialize() -> void:
	var reports: Array = []
	for path: String in OS.get_cmdline_user_args():
		var observations: Array = bytes_to_var(FileAccess.get_file_as_bytes(path))
		var unique: Dictionary = {}
		var active_frames := 0
		var max_active := 0
		var hit_frames := 0
		for frame: Array in observations:
			if not frame[14].is_empty(): active_frames += 1
			max_active = maxi(max_active, frame[14].size())
			if not frame[9].is_empty(): hit_frames += 1
			for segment: Dictionary in frame[16]:
				if float(segment.to_time) > float(segment.from_time) and float(segment.raw_amount) > 0.0 and float(segment.settlement.health_lost) > 0.0:
					unique[var_to_bytes(segment).hex_encode()] = segment
		var health_lost := 0.0
		for segment: Dictionary in unique.values(): health_lost += float(segment.settlement.health_lost)
		reports.append({"path": path, "frames": observations.size(), "active_burn_frames": active_frames,
			"max_active_burns": max_active, "frames_with_combat_trace": hit_frames,
			"unique_positive_width_health_loss_segments": unique.size(), "observed_burn_health_lost": health_lost})
	print(JSON.stringify(reports))
	quit()
