extends RefCounted
## This guard has no production dependency and never opens a save file.

static func _normalized(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()


static func _inside(path: String, parent: String) -> bool:
	return not parent.is_empty() and _normalized(path).begins_with(_normalized(parent) + "/")


static func evidence() -> Dictionary:
	var sandbox: String = OS.get_environment("GODOT_SAVE_QA_ROOT")
	var expected_project: String = OS.get_environment("GODOT_SAVE_QA_PROJECT")
	var expected_userdata: String = OS.get_environment("GODOT_SAVE_QA_USERDATA")
	var token: String = OS.get_environment("GODOT_SAVE_QA_TOKEN")
	var actual_project: String = ProjectSettings.globalize_path("res://")
	var actual_userdata: String = OS.get_user_data_dir()
	var user_alias: String = ProjectSettings.globalize_path("user://")
	var ok: bool = OS.get_name() == "Windows" and token.length() == 32
	ok = ok and _inside(actual_project, sandbox) and _inside(actual_userdata, sandbox)
	ok = ok and _normalized(actual_project) == _normalized(expected_project)
	ok = ok and _normalized(actual_userdata) == _normalized(expected_userdata)
	ok = ok and _normalized(user_alias) == _normalized(actual_userdata)
	ok = ok and ProjectSettings.get_setting("application/config/name", "") == "Windows Save QA " + token
	ok = ok and ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
	ok = ok and ProjectSettings.get_setting("application/config/custom_user_dir_name", "") == "存档 沙箱 " + token
	return {"ok": ok, "os": OS.get_name(), "sandbox": sandbox, "project": actual_project,
		"user_data_dir": actual_userdata, "user_alias": user_alias, "token": token}


static func verify() -> bool:
	var result: Dictionary = evidence()
	print("SAVE_QA_GATE " + JSON.stringify(result))
	if not result.ok:
		printerr("SAVE_QA_BLOCKED: Actual project/userdata did not match the disposable Windows sandbox.")
	return result.ok
