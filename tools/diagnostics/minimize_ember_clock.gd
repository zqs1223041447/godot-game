extends SceneTree
const Runtime=preload("res://scripts/combat/projectile_runtime.gd")
var source:Dictionary
var attempts:=0
var output:String
func _initialize()->void:call_deferred("run")
func anomaly(shots:Array,targets:Array)->Dictionary:
	attempts+=1
	var runtime:=Runtime.new()
	var carriers:Array[Dictionary]=[];carriers.assign(shots.duplicate(true))
	var actors:Array[Dictionary]=[];actors.assign(targets.duplicate(true))
	var events:=runtime.advance(carriers,1.0/60.0,actors,source.checkpoint.player_pos,180)
	var latest:float=-1.0;var previous:Dictionary={};var history:Array=[]
	for event:Dictionary in events:
		if event.type!="hit":continue
		var t:float=event.time
		history.append({"time":t,"sequence":event.sequence,"target_id":event.target_id,"projectile_id":event.projectile_id})
		if t<latest and not is_equal_approx(t,latest):return {"bad":true,"events":history,"previous":previous,"current":event,"latest":latest,"event_count":events.size()}
		latest=maxf(latest,t);previous=event
	return {"bad":false}
func shrink(values:Array,other:Array,shots:bool)->Array:
	var current:=values.duplicate(true);var chunk:int=maxi(1,current.size()/2)
	while true:
		var changed:=false;var start:=0
		while start<current.size():
			var candidate:=current.duplicate(true)
			for i:int in range(mini(chunk,current.size()-start)):candidate.remove_at(start)
			if not candidate.is_empty() and anomaly(candidate,other).bad if shots else not candidate.is_empty() and anomaly(other,candidate).bad:
				current=candidate;changed=true
			else:start+=chunk
		if chunk==1 and not changed:break
		if not changed:chunk=maxi(1,chunk/2)
	return current
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v050-"):quit(78);return
	source=bytes_to_var(FileAccess.get_file_as_bytes(OS.get_environment("CLOCK_CAPTURE")))
	output=OS.get_environment("CLOCK_MINIMAL_OUT")
	var shots:Array=source.checkpoint.projectiles
	var actors:Array=source.enemies
	var original:=anomaly(shots,actors)
	if not original.bad:push_error("Captured Runtime input did not reproduce clock inversion");quit(1);return
	shots=shrink(shots,actors,true);actors=shrink(actors,shots,false);shots=shrink(shots,actors,true)
	var result:=anomaly(shots,actors);assert(result.bad)
	var fixture:Dictionary={"shots":shots,"actors":actors,"player_pos":source.checkpoint.player_pos,"step":1.0/60.0}
	var file:=FileAccess.open(output+".bin",FileAccess.WRITE);file.store_buffer(var_to_bytes(fixture));file.close()
	var report:Dictionary={"attempts":attempts,"shots":shots.size(),"actors":actors.size(),"events":result.events,"latest":result.latest,"bad_offset":result.current.time,"previous_offset":result.previous.time,"neighbor_tie":is_equal_approx(float(result.current.time),float(result.previous.time)),"max_pair_tie":is_equal_approx(float(result.current.time),float(result.latest)),"step":1.0/60.0}
	file=FileAccess.open(output+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close();print(JSON.stringify(report));quit(0)
