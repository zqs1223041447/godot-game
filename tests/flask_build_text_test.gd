extends SceneTree
const Presentation=preload("res://scripts/ui/unified_item_presentation.gd")
func _initialize()->void:
	var checks:Array[bool]=[]
	checks.append(Presentation.flask_preview_lines({"ok":false}).is_empty())
	var profile:Dictionary={"ok":true,"duration":3.0,"recovery_total":52.5,"resource":"health","charges_per_root":1.25}
	var lines:Array[String]=Presentation.flask_preview_lines(profile)
	checks.append(lines.size()==2)
	checks.append(lines[0]=="当前构筑：3.00 秒内回复 52.50 生命")
	checks.append(lines[1].contains("1.25 充能（小数累计）"))
	profile.resource="mana"
	checks.append(Presentation.flask_preview_lines(profile)[0].ends_with("魔力"))
	print("Flask build text: %d checks, %d failures"%[checks.size(),checks.count(false)])
	quit(1 if checks.count(false)>0 else 0)
