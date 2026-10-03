extends SceneTree
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Runtime=preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Renderer=preload("res://scripts/visuals/telegraph_renderer.gd")
const Settings=preload("res://scripts/visuals/visual_settings.gd")
var checks:=0
var failures:=0
func _initialize()->void:
	var shapes:Dictionary={}
	for id:String in Monsters.ELEMENTAL_ENCOUNTERS:
		var enemy:=Monsters.make_enemy(1,id,5,Vector2.ZERO);enemy.spawn=0.0
		var policy:=Monsters.telegraph_policy(enemy);var runtime:=Runtime.new();var started:=runtime.start(enemy,Vector2(40,80),policy.profile)
		check(started.ok,"Real typed profile admitted")
		runtime.advance(policy.profile.windup_seconds*0.65,[enemy])
		var state:=runtime.state_for(1);state.visual_element=Monsters.ELEMENTAL_ENCOUNTERS[id].element
		var before:=var_to_bytes(state)
		for level:int in [0,1,2]:
			var settings:=Settings.new();settings.effects_level=level
			var primitives:=Renderer.primitives([state],settings)
			check(primitives.size()<=8,"Unchanged per-source draw budget")
			var rune:Dictionary={}
			for p:Dictionary in primitives:
				if p.role=="rune_base":rune=p
				if p.role=="danger_boundary":check(p.center==state.center and p.radius==policy.profile.radius,"True collision boundary unchanged")
			check(not rune.is_empty(),"Non-color elemental glyph present at every effects level")
			for point:Vector2 in rune.points:check(point.distance_to(state.center)<policy.profile.radius and point.y<state.center.y-15.0,"Glyph stays within hazard and clear of player center")
			shapes[id]=rune.points
		check(var_to_bytes(state)==before,"Presentation leaves frozen gameplay state unchanged")
	check(shapes.frost_guard!=shapes.storm_skitter,"Cold and lightning readable by different shape, not color alone")
	print("Elemental warning shapes: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
