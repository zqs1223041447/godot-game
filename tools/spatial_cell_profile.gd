extends SceneTree
## A/B an existing constructor parameter; shipping DEFAULT_CELL_SIZE is untouched.
const Main = preload("res://scripts/main.gd")
const Spatial = preload("res://scripts/combat/spatial_target_index.gd")
var output := OS.get_environment("SPATIAL_PROFILE_OUT")
var records: Array = []

func _initialize()->void:call_deferred("run")

func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/workspace/scratch/a51485f153de/v023-profile-users/") or output.is_empty():quit(78);return
	for count: int in [100,200,400]:
		var arena=Main.new();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false)
		arena.enemies.clear();arena.monster_runtime.reset();arena.invulnerable=1000000;arena.auto_fire=false;arena.spawn_timer=1000000
		var columns:=ceili(sqrt(count*2.59));var rows:=ceili(float(count)/columns)
		for index:int in range(count):
			var pos:Vector2=arena.ARENA.position+Vector2(70+(index%columns)*(arena.ARENA.size.x-140)/maxi(1,columns-1),50+int(index/columns)*(arena.ARENA.size.y-100)/maxi(1,rows-1))
			var enemy:Dictionary=arena.monster_runtime.create_root(["crawler","skitter","brute"][index%3],1,pos)
			enemy.spawn=0.0;arena.enemies.append(enemy)
		var spread:Array[Dictionary]=arena.enemies.duplicate(true)
		for index:int in range(600):
			arena._update_enemies(1.0/60.0)
			if index%60==0:await process_frame
		var settled:Array[Dictionary]=arena.enemies.duplicate(true)
		for distribution:String in ["spread","settled"]:
			var baseline_hash:=""
			for cell:float in [128.0,64.0]:
				arena.enemies=(spread if distribution=="spread" else settled).duplicate(true)
				arena.enemy_spatial=Spatial.new(cell)
				var times:Array[int]=[];var visits:Array[int]=[]
				for index:int in range(120):
					var began:=Time.get_ticks_usec();arena._update_enemies(1.0/60.0);times.append(Time.get_ticks_usec()-began);visits.append(arena.separation_candidate_visits)
					if index%60==0:await process_frame
				var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(var_to_bytes(arena.enemies));var value:=digest.finish().hex_encode()
				if cell==128.0:baseline_hash=value
				assert(value==baseline_hash,"Cell-size broadphase changed exact sequential enemy state")
				records.append({"count":count,"distribution":distribution,"cell":cell,"cpu_usec":summary(times),"candidate_visits":summary(visits),"enemy_bytes_sha256":value,"exact_state_equal":true})
		arena.queue_free();await process_frame
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(records,"\t",true,true))
	print("SPATIAL_CELL_PROFILE_COMPLETE ",records.size())
	quit()

func summary(values:Array[int])->Dictionary:
	values.sort();var total:=0.0
	for value:int in values:total+=value
	return {"n":values.size(),"mean":total/values.size(),"p50":values[int(values.size()/2)],"max":values.back()}
