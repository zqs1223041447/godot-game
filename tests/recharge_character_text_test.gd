extends SceneTree
const Sheet=preload("res://scripts/ui/canonical_character_panel.gd")
class Model extends RefCounted:
	signal changed
	var level:=1
	var xp:=0
	var talent_points:=0
	var rate:=18.0
	var delay:=2.5
	func get_stats()->Dictionary:return {"shield_recharge_rate":rate,"shield_recharge_delay":delay,"shield_regen":10.0}
func _initialize()->void:
	var model=Model.new()
	var panel=Sheet.new()
	panel.setup(model)
	var checks:Array[bool]=[]
	checks.append(panel.find_child("Value_shield_recharge_rate",true,false).text=="18.00")
	checks.append(panel.find_child("Value_shield_recharge_delay",true,false).text=="2.50")
	checks.append(panel.find_child("CharacterStat_shield_recharge_delay",true,false).tooltip_text.contains("下一次有效损伤"))
	checks.append(panel.find_child("CharacterStat_shield_recharge_delay",true,false).tooltip_text.contains("已经开始的等待"))
	model.rate=24.0
	model.delay=2.0
	model.changed.emit()
	panel.refresh()
	checks.append(panel.find_child("Value_shield_recharge_rate",true,false).text=="24.00")
	checks.append(panel.find_child("Value_shield_recharge_delay",true,false).text=="2.00")
	panel.free()
	print("Recharge character text: %d checks, %d failures"%[checks.size(),checks.count(false)])
	quit(1 if checks.count(false)>0 else 0)
