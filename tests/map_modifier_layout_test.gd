extends SceneTree
const Controls=preload("res://scripts/ui/encounter_controls.gd")
const Catalog=preload("res://scripts/encounters/encounter_catalog.gd")
var failures:=0
var checks:=0
func check(value:bool)->void:
	checks+=1
	if not value: failures+=1
func _initialize()->void: call_deferred("run")
func run()->void:
	for scale:float in [1.0,1.35]:
		var scroll:=ScrollContainer.new()
		scroll.size=Vector2(520,380)
		scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		root.add_child(scroll)
		var panel=Controls.new()
		panel.font_scale=scale
		panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		scroll.add_child(panel)
		panel.set_context(["enemy_armour_80","enemy_shield_from_health_20"])
		await process_frame
		await process_frame
		for id:String in Catalog.get_ids():
			var option:Control=panel.find_child("EncounterOption_"+id,true,false)
			check(option.size.x>0 and option.get_global_rect().end.x<=scroll.get_global_rect().end.x)
		var confirm:Control=panel.find_child("EncounterConfirm",true,false)
		scroll.ensure_control_visible(confirm)
		await process_frame
		check(confirm.get_global_rect().position.y>=scroll.get_global_rect().position.y)
		check(confirm.get_global_rect().end.y<=scroll.get_global_rect().end.y+1)
		scroll.queue_free()
		await process_frame
	print("Map modifier scroll layout: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
