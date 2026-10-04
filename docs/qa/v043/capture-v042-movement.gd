extends SceneTree
const Geometry=preload("res://scripts/world/map_geometry.gd")
const View=preload("res://scripts/visuals/world_view.gd")
func _initialize()->void:
	var output:=OS.get_environment("V043_MOVE_BASELINE")
	if output.is_empty():quit(78);return
	var records:Array=[];var rng:=RandomNumberGenerator.new();rng.seed=43042
	for id:String in ["normal","old_garden","broken_ruins"]:
		var geometry:=Geometry.new();assert(geometry.configure(id,View.WORLD_ARENA))
		for radius:float in [14.0,22.0,27.5]:
			for i:int in range(40):
				var start:Vector2=View.WORLD_ARENA.position+Vector2(rng.randf()*View.WORLD_ARENA.size.x,rng.randf()*View.WORLD_ARENA.size.y)
				start=geometry.legal_point(start,radius)
				var desired:=start+Vector2(rng.randf_range(-500,500),rng.randf_range(-250,250))
				records.append({"map_id":id,"radius":radius,"start":start,"desired":desired,"result":geometry.move(start,desired,radius)})
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_buffer(var_to_bytes(records));file.close();print("Frozen v42 movement baseline: ",records.size()," cases");quit()
