extends SceneTree
const Layout=preload("res://scripts/world/exploration_map_layout.gd")
const Plan=preload("res://scripts/world/exploration_map_plan.gd")
const Previous=preload("res://docs/qa/v090-routes/baseline_plan.gd")
const Geometry=preload("res://scripts/world/map_geometry.gd")
const Runtime=preload("res://scripts/monsters/monster_runtime.gd")
const Maps=preload("res://scripts/world/map_compiler.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
var checks:=0
var failures:=0
var reports:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func normal_actor(actor:Dictionary)->Dictionary:
	var value:Dictionary=actor.duplicate(true);value.erase("pos");value.erase("map_outpost_id");return value
func normalize_record(record:Dictionary)->Dictionary:
	var value:Dictionary=record.duplicate(true);value.erase("position");value.erase("outpost_id");return value
func graph(landmarks:Dictionary,geometry:RefCounted)->void:
	var edges:Dictionary={}
	for segment:Dictionary in landmarks.route_segments:
		if not edges.has(segment.from):edges[segment.from]=[]
		if not edges.has(segment.to):edges[segment.to]=[]
		edges[segment.from].append(segment.to);edges[segment.to].append(segment.from)
		check(not geometry.sweep(segment.from,segment.to,36.0).hit,"Whole 72-unit route width is clear")
		var steps:int=maxi(1,ceili(segment.from.distance_to(segment.to)/25.0))
		for i:int in range(steps+1):check(geometry.is_clear(segment.from.lerp(segment.to,float(i)/steps),36.0),"Complete painted strip stays inside real walkable area")
	var reached:Dictionary={landmarks.entry:true};var queue:Array[Vector2]=[landmarks.entry]
	while not queue.is_empty():
		var current:Vector2=queue.pop_front()
		for neighbor:Vector2 in edges.get(current,[]):
			if not reached.has(neighbor):reached[neighbor]=true;queue.append(neighbor)
	check(reached.has(landmarks.boss.center),"Connected route reaches boss without defeating outposts")
	for outpost:Dictionary in landmarks.outposts:
		check(reached.has(outpost.center),"Every outpost center belongs to connected authored route graph")
		check(geometry.is_clear(outpost.sign_position,15.0),"Outpost sign placement is physically clear")
	check(landmarks.route_segments.size()>=edges.size(),"At least one closed route choice remains")
func run()->void:
	for map_id:String in ["old_garden","broken_ruins","sunwell_terrace","ginkgo_arcade"]:
		var layout:Dictionary=Layout.layout(map_id,Layout.WORLD_BOUNDS);var geo=Geometry.new();geo.configure_exploration(map_id,Layout.WORLD_BOUNDS)
		check(layout.ok and layout.landmarks.outposts.size()==6,"Six authored outposts: "+map_id)
		graph(layout.landmarks,geo)
		var sizes:Array[int]=[]
		for outpost:Dictionary in layout.landmarks.outposts:sizes.append(int(outpost.root_count))
		check(sizes==([3,5,3,5,3,5] if map_id=="old_garden" else [4,8,4,8,4,8]),"Smaller approach pack and denser resident pack preserve total")
		for tier:int in [1,2,3]:
			var plain:Dictionary=Maps.compile_normal(map_id,tier,[],[])
			var special:Array=[]
			if plain.profile.wave>=4:special=["elemental_aegis"]
			var compiled:Dictionary=Maps.compile_normal(map_id,tier,["enemy_max_health_120","enemy_shield_from_health_20"],special)
			for seed_value:int in [90001,90002,90003]:
				var runtime=Runtime.new();var old_runtime=Runtime.new();var rng:=RandomNumberGenerator.new();rng.seed=seed_value
				var rng_before:int=rng.state
				var current:Dictionary=Plan.plan(compiled.profile,runtime,seed_value,Layout.WORLD_BOUNDS)
				var old:Dictionary=Previous.plan(compiled.profile,old_runtime,seed_value,Layout.WORLD_BOUNDS)
				check(bool(current.get("ok",false)) and bool(old.get("ok",false)),"Both full plans generate "+map_id+"/"+str(tier))
				if not bool(current.get("ok",false)) or not bool(old.get("ok",false)):continue
				check(runtime.next_id==0 and runtime.roots.is_empty() and rng.state==rng_before,"Pure complete planning leaves live runtime and unrelated RNG untouched")
				check(current.roots.size()==old.roots.size() and current.run.snapshot()==old.run.snapshot(),"All original roots/boss and run counters preserved")
				check(var_to_bytes(current.runtime_checkpoint)==var_to_bytes(old.runtime_checkpoint),"IDs lineage and producer trace bytes preserved")
				check(var_to_bytes(current.run.profile)==var_to_bytes(old.run.profile),"Map profile fees rewards and mechanics unchanged")
				var ids:Dictionary={};var count:=0
				for outpost:Dictionary in current.landmarks.outposts:
					check(outpost.root_ids.size()==outpost.root_count,"Every resident mapped once to exact outpost count")
					for id:int in outpost.root_ids:check(not ids.has(id),"Outpost identity never duplicated");ids[id]=outpost.id;count+=1
				check(count==int(compiled.profile.ordinary_target),"All ordinary roots have one outpost and boss remains independent")
				for i:int in range(current.roots.size()):
					var actor:Dictionary=current.roots[i];var before:Dictionary=old.roots[i]
					check(var_to_bytes(normal_actor(actor))==var_to_bytes(normal_actor(before)),"All actor combat/reward fields and spawn key preserved except position/new display identity")
					check(var_to_bytes(normalize_record(current.spawn_records[i]))==var_to_bytes(normalize_record(old.spawn_records[i])),"Source record identity/ordinal/reward route preserved")
					check(geo.is_clear(actor.pos,actor.radius) and actor.pos.distance_to(current.landmarks.entry)>=850.0,"Actual radius safe and outside entry auto-acquisition")
					for j:int in range(i):check(actor.pos.distance_to(current.roots[j].pos)>=float(actor.radius)+float(current.roots[j].radius),"Full-map bodies do not overlap")
				check(not Plan.plan(compiled.profile,runtime,seed_value,Layout.WORLD_BOUNDS,current.roots.size()-1).ok,"Capacity rejects complete roster before mutation")
				check(not Plan.plan(compiled.profile,runtime,seed_value,Layout.WORLD_BOUNDS,100,Monsters.CURRENT_ROLL_POLICY,{"season":"unimplemented"}).ok,"Future seasonal options remain unavailable")
				reports.append({"map":map_id,"tier":tier,"seed":seed_value,"roots":current.roots.size(),"outposts":6,"same_roster":true})
	var result:Dictionary={"checks":checks,"failures":failures,"plans":reports};FileAccess.open("res://docs/qa/v090-routes/layout-result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print("ROUTE_LAYOUT ",checks," checks ",failures," failures");quit(1 if failures else 0)
