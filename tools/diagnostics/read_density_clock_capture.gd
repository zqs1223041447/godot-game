extends SceneTree
func _initialize()->void:
	var input:=OS.get_environment("CLOCK_CAPTURE")
	var value:Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(input))
	var brief:Array=[]
	for e:Dictionary in value.recent_events:
		if float(e.time)>0.00845 and float(e.time)<0.00853:brief.append({"type":e.type,"time":e.time,"sequence":e.sequence,"shot":e.get("projectile_id",0),"target":e.get("target_id",0),"phase":e.get("phase","")})
	print(JSON.stringify({"frame":value.frame,"nearby_events":brief,"checkpoint_actors":value.checkpoint.enemies.size(),"checkpoint_shots":value.checkpoint.projectiles.size(),"clock_min":value.step_start,"first_error":value.event.time},"\t",true,true));quit(0)
