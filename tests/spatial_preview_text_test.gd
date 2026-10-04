extends SceneTree
const Preview=preload("res://scripts/combat/damage_preview.gd")
func _initialize()->void:
	var checks:Array[bool]=[]
	checks.append(Preview.spatial_details({}).is_empty())
	var cast:Dictionary={"recipe":{"speed":960.0},"snapshot":{}}
	var text:String="\n".join(Preview.spatial_details(cast))
	checks.append(text.contains("960.00"))
	checks.append(text.contains("不增加距离上限"))
	cast.recipe={"parent":{"speed":700.0},"child":{"speed":840.0}}
	text="\n".join(Preview.spatial_details(cast))
	checks.append(text.contains("母箭速度 700.00 · 子箭速度 840.00"))
	checks.append(text.contains("返回沿用各自速度"))
	cast.snapshot={"effects":[],"explosion_recipe":{"radius":120.0,"area_multiplier":1.44}}
	checks.append(not "\n".join(Preview.spatial_details(cast)).contains("独立爆炸半径"))
	cast.snapshot.effects=["explode_on_flight_end"]
	text="\n".join(Preview.spatial_details(cast))
	checks.append(text.contains("独立爆炸半径 120.00 · 面积 ×1.4400"))
	checks.append(text.contains("平方根"))
	print("Spatial preview text: %d checks, %d failures"%[checks.size(),checks.count(false)])
	quit(1 if checks.count(false)>0 else 0)
