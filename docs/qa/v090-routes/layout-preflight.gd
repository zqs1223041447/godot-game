extends SceneTree
const Layout=preload("res://scripts/world/exploration_map_layout.gd")
const Geometry=preload("res://scripts/world/map_geometry.gd")
const Plan=preload("res://scripts/world/exploration_map_plan.gd")
const Runtime=preload("res://scripts/monsters/monster_runtime.gd")
const Compiler=preload("res://scripts/world/map_compiler.gd")
func _initialize()->void:
	var failed:=false
	for map_id:String in ["ginkgo_arcade"]:
		var layout:Dictionary=Layout.layout(map_id,Layout.WORLD_BOUNDS);var geometry=Geometry.new()
		if not bool(layout.get("ok",false)) or not geometry.configure_exploration(map_id,Layout.WORLD_BOUNDS):printerr("BAD_LAYOUT ",map_id);quit(1);return
		for n:int in range(layout.landmarks.route_segments.size()):
			var row:Dictionary=layout.landmarks.route_segments[n]
			var sweep:Dictionary=geometry.sweep(row.from,row.to,float(row.width)*0.5)
			if sweep.hit:printerr("BLOCKED_ROUTE ",map_id," ",n," ",row," ",sweep);failed=true
		for tier:int in [1,2,3]:
			var compiled:Dictionary=Compiler.compile_normal(map_id,tier,[],[])
			var plan:Dictionary=Plan.plan(compiled.profile,Runtime.new(),901,Layout.WORLD_BOUNDS)
			if not plan.ok:printerr("PLAN_FAIL ",map_id," ",tier," ",plan.reason);failed=true
			else:print("READY ",map_id," ",tier," roots=",plan.roots.size()," outposts=",plan.landmarks.outposts.size())
	quit(1 if failed else 0)
