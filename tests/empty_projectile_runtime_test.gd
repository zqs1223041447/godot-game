extends SceneTree
const Before=preload("res://docs/qa/v089-empty-projectiles/runtime_before.gd")
const After=preload("res://scripts/combat/projectile_runtime.gd")
const Recipes=preload("res://scripts/combat/combat_data.gd")
var checks:=0
var failures:=0
var callbacks:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func metrics(r:RefCounted)->Array:
	return [r.next_projectile_id,r.next_cast_id,r._sequence,r.last_work_sorts,r.last_work_sort_skips,r.last_work_order_checks,r.last_candidate_visits,r.last_full_scan_visits,r.last_contact_queries,r.last_indexed_queries,r._in_advance,r._index_active]
func cache(r:RefCounted)->PackedByteArray:
	var i=r._target_index
	return var_to_bytes([i._targets,i._cells,i._memberships,i._aliases,i._overflow])
func gate(_shot:Dictionary,_id:int)->bool:callbacks+=1;return true
func terrain(_a:Vector2,_b:Vector2,_r:float)->Dictionary:callbacks+=1;return {"hit":false}
func shot(r:RefCounted,split:bool=false)->Dictionary:
	var spec:Dictionary={"speed":100.0,"range":60.0,"lifetime":2.0,"radius":2.0,"pierce":0,"role":"parent" if split else "child","split":split}
	var snapshot:Dictionary=Recipes.snapshot({"damage":31.0,"attack_added_fire":11.0},["return_on_range","explode_on_flight_end"])
	return r.make_projectile(Vector2.ZERO,Vector2.RIGHT,spec,Recipes.tornado_packet(snapshot,"parent" if split else "child"),snapshot,r.new_cast(),Color.WHITE)
func compare(a:RefCounted,b:RefCounted,sa:Array[Dictionary],sb:Array[Dictionary],delta:float,targets:Array[Dictionary],label:String)->void:
	var t:PackedByteArray=var_to_bytes(targets)
	var ea:Array[Dictionary]=a.advance(sa,delta,targets,Vector2.ZERO,180,gate,terrain)
	var eb:Array[Dictionary]=b.advance(sb,delta,targets,Vector2.ZERO,180,gate,terrain)
	check(var_to_bytes(ea)==var_to_bytes(eb),label+" exact ordered event bytes")
	check(var_to_bytes(sa)==var_to_bytes(sb),label+" exact surviving carriers")
	check(metrics(a)==metrics(b),label+" IDs sequence counters flags")
	check(var_to_bytes(targets)==t,label+" target inputs unchanged")
func run()->void:
	var targets:Array[Dictionary]=[{"id":1,"pos":Vector2(30,0),"radius":5.0,"health":100.0,"spawn":0.0},{"id":2,"pos":Vector2(100,0),"radius":6.0,"health":100.0,"spawn":0.0}]
	for indexed:bool in [true,false]:
		for delta:float in [0.0,-1.0,NAN,INF,1.0/60.0,1000.0]:
			var a=Before.new();var b=After.new();a.use_spatial_index=indexed;b.use_spatial_index=indexed
			a._target_index.rebuild(targets);b._target_index.rebuild(targets)
			var old_cache:PackedByteArray=cache(b)
			for runtime:RefCounted in [a,b]:
				for field:String in ["last_work_sorts","last_work_sort_skips","last_work_order_checks","last_candidate_visits","last_full_scan_visits","last_contact_queries","last_indexed_queries"]:runtime.set(field,17)
				runtime._in_advance=true;runtime._index_active=true
			var sa:Array[Dictionary]=[];var sb:Array[Dictionary]=[];var alias:Array[Dictionary]=sb;var before_callbacks:int=callbacks
			compare(a,b,sa,sb,delta,targets,"empty indexed=%s delta=%s"%[indexed,delta])
			check(callbacks==before_callbacks,"No empty callback dispatch")
			check(is_same(alias,sb) and alias.is_empty(),"Caller array identity remains empty")
			if is_finite(delta) and delta>0.0:
				check(b._target_index._targets.is_empty() and b._target_index._cells.is_empty() and b._target_index._memberships.is_empty() and b._target_index._aliases.is_empty(),"Valid empty releases previous target references")
			else:check(cache(b)==old_cache,"Invalid delta returns before index cleanup")
			check(metrics(b).slice(3,10)==[0,0,0,0,0,0,0] and not b._in_advance and not b._index_active,"Empty always resets diagnostic counters and flags")
	# Existing target dictionaries can move/change radius and their array can be
	# structurally edited while idle; the first new carrier rebuilds completely.
	for indexed:bool in [true,false]:
		var a=Before.new();var b=After.new();a.use_spatial_index=indexed;b.use_spatial_index=indexed
		var sa:Array[Dictionary]=[shot(a)];var sb:Array[Dictionary]=[shot(b)]
		compare(a,b,sa,sb,0.4,targets,"first contact")
		check(sa.is_empty() and sb.is_empty(),"Initial hit consumes both carriers")
		compare(a,b,sa,sb,0.1,targets,"idle after terminal")
		var changed:Array[Dictionary]=targets.duplicate(true);changed.remove_at(0);changed[0].pos=Vector2(25,0);changed[0].radius=9.0;changed.append({"id":77,"pos":Vector2(400,400),"radius":12.0,"health":80.0})
		compare(a,b,sa,sb,0.2,changed,"idle after target structural change")
		sa.append(shot(a));sb.append(shot(b));compare(a,b,sa,sb,0.4,changed,"first new projectile uses current targets")
		check(sa.is_empty() and sb.is_empty(),"Moved target reached on first new projectile frame")
		var test_shot:Dictionary=shot(b)
		check(var_to_bytes(a._contacts(test_shot,Vector2.ZERO,Vector2(100,0),changed))==var_to_bytes(b._contacts(test_shot,Vector2.ZERO,Vector2(100,0),changed)),"External contact helper uses full fallback outside advance")
	for split:bool in [false,true]:
		var a=Before.new();var b=After.new();var sa:Array[Dictionary]=[shot(a,split)];var sb:Array[Dictionary]=[shot(b,split)];var empty:Array[Dictionary]=[]
		for delta:float in [0.7,0.5,1.0,1.0,0.1]:compare(a,b,sa,sb,delta,empty,"return split=%s delta=%s"%[split,delta])
		check(sa.is_empty() and sb.is_empty(),"All natural terminal carriers cleaned exactly once")
	var result:Dictionary={"checks":checks,"failures":failures,"callbacks":callbacks,"scope":"Fixed original runtime event/carrier/ID/counter equivalence; inactive private index clearing intentionally differs"}
	FileAccess.open("res://docs/qa/v089-empty-projectiles/runtime-result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print(JSON.stringify(result));quit(1 if failures else 0)
