extends RefCounted
## No production dependencies or save reads. The runner also checks these paths.

static func normalized(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()


static func evidence() -> Dictionary:
	var sandbox: String = OS.get_environment("GODOT_V014_QA_ROOT")
	var project: String = OS.get_environment("GODOT_V014_QA_PROJECT")
	var userdata: String = OS.get_environment("GODOT_V014_QA_USERDATA")
	var token: String = OS.get_environment("GODOT_V014_QA_TOKEN")
	var directory_name: String = OS.get_environment("GODOT_V014_QA_NAME")
	var actual_project: String = ProjectSettings.globalize_path("res://")
	var actual_userdata: String = OS.get_user_data_dir()
	var user_alias: String = ProjectSettings.globalize_path("user://")
	var ok: bool = OS.get_name() == "Windows" and token.length() == 32
	ok = ok and not sandbox.is_empty() and directory_name.contains(token)
	ok = ok and normalized(actual_project).begins_with(normalized(sandbox) + "/")
	ok = ok and normalized(actual_userdata).begins_with(normalized(sandbox) + "/")
	ok = ok and normalized(actual_project) == normalized(project)
	ok = ok and normalized(actual_userdata) == normalized(userdata)
	ok = ok and normalized(user_alias) == normalized(userdata)
	ok = ok and ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
	ok = ok and ProjectSettings.get_setting("application/config/custom_user_dir_name", "") == directory_name
	return {"ok": ok, "os": OS.get_name(), "sandbox": sandbox, "project": actual_project,
		"user_data_dir": actual_userdata, "user_alias": user_alias, "token": token,
		"directory_name": directory_name}


static func verify() -> bool:
	var result: Dictionary = evidence()
	print("V014_QA_GATE " + JSON.stringify(result))
	if not result.ok:
		printerr("V014_QA_BLOCKED: Actual Windows project/userdata did not match the disposable sandbox.")
	return result.ok
