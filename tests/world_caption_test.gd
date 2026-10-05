extends SceneTree
const HUD = preload("res://scripts/game_hud.gd")
func _initialize() -> void:
	var cases := [
		[{"mode":"map","map_name":"晴泉台地"},"晴泉台地"],
		[{"mode":"map_complete","map_name":"断垣试炼"},"断垣试炼"],
		[{"mode":"town","test_mode":false},"正式城镇"],
		[{"mode":"town","test_mode":true},"测试城镇"],
		[{"mode":"normal"},"灰烬庭院"]]
	for row: Array in cases:
		if HUD.world_caption(row[0]) != row[1]:
			push_error("World caption mismatch")
			quit(1)
			return
	print("World caption: 5 checks, 0 failures")
	quit(0)
