extends SceneTree
## Offline bootstrap probe. Never opens user:// files or sends network requests.


func _initialize() -> void:
	var allowed_root := _canonical(OS.get_environment("GODOT_CERTIFICATE_ROOT"))
	var expected_project := _canonical(OS.get_environment("GODOT_CERTIFICATE_PROJECT"))
	var expected_userdata := _canonical(OS.get_environment("GODOT_CERTIFICATE_USERDATA"))
	var project := _canonical(ProjectSettings.globalize_path("res://"))
	var userdata := _canonical(OS.get_user_data_dir())
	var user_alias := _canonical(ProjectSettings.globalize_path("user://"))
	var isolated := not allowed_root.is_empty() and not expected_project.is_empty() \
		and not expected_userdata.is_empty() and project == expected_project \
		and userdata == expected_userdata and user_alias == expected_userdata \
		and project.begins_with(allowed_root + "/") \
		and userdata.begins_with(allowed_root + "/")
	var mode := OS.get_environment("GODOT_CERTIFICATE_MODE")
	print("CERTIFICATE_PROBE " + JSON.stringify({
		"isolated": isolated,
		"mode": mode,
		"project": project,
		"user_data_dir": userdata,
		"user_alias": user_alias,
		"executable": OS.get_executable_path(),
		"version": Engine.get_version_info(),
		"appdata": OS.get_environment("APPDATA"),
		"certificate_bundle_override": ProjectSettings.get_setting(
			"network/tls/certificate_bundle_override", ""),
	}))
	if not isolated:
		quit(78)
		return
	if mode == "model":
		call_deferred("_read_model")
	else:
		quit(0)


func _read_model() -> void:
	# Dynamic load happens only after the independent userdata guard above.
	var model_script := load("res://scripts/build_state.gd") as GDScript
	if model_script == null or not model_script.can_instantiate():
		quit(79)
		return
	var model: RefCounted = model_script.new()
	var stats: Dictionary = model.get_stats()
	print("CERTIFICATE_MODEL " + JSON.stringify({
		"instantiated": true,
		"stat_count": stats.size(),
		"max_health": stats.get("max_health"),
		"damage": stats.get("damage"),
		"save_methods_called": false,
		"network_requests_sent": false,
	}))
	quit(0 if not stats.is_empty() else 79)


func _canonical(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
