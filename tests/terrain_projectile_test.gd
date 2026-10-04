extends SceneTree
const Runtime=preload("res://scripts/combat/projectile_runtime.gd")
const Recipes=preload("res://scripts/combat/combat_data.gd")
const Geometry=preload("res://scripts/world/map_geometry.gd")
const View=preload("res://scripts/visuals/world_view.gd")
var geometry=Geometry.new()
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func shot(runtime:RefCounted,origin:Vector2,changes:Dictionary={})->Dictionary:
	var spec:Dictionary={"speed":200.0,"range":1000.0,"lifetime":10.0,"radius":6.0,"pierce":-1,"role":"child","split":false};spec.merge(changes,true)
	var snapshot:Dictionary=Recipes.snapshot({"damage":100.0},["return_on_range","explode_on_flight_end"])
	return runtime.make_projectile(origin,Vector2.RIGHT,spec,Recipes.tornado_packet(snapshot,"parent" if spec.split else "child"),snapshot,runtime.new_cast(),Color.WHITE)
func count(events:Array,type:String)->int:
	var result:=0
	for event:Dictionary in events:if event.type==type:result+=1
	return result
func _initialize()->void:
	geometry.configure("broken_ruins",View.WORLD_ARENA)
	var wall:Rect2=geometry.snapshot().walls[0];var start:=Vector2(wall.position.x-106,wall.get_center().y)
	var targets:Array[Dictionary]=[{"id":1,"pos":start+Vector2(40,0),"radius":8.0,"health":100.0,"spawn":0.0},{"id":2,"pos":start+Vector2(200,0),"radius":8.0,"health":100.0,"spawn":0.0}]
	for role:String in ["parent","child"]:
		for pierce:int in [-1,0,3]:
			var runtime=Runtime.new();var carrier:=shot(runtime,start,{"role":role,"split":role=="parent","pierce":pierce})
			var shots:Array[Dictionary]=[carrier]
			var events:Array[Dictionary]=runtime.advance(shots,2.0,targets,Vector2(wall.end.x+80,start.y),180,Callable(),geometry.sweep)
			check(count(events,"hit")==1,"Only target before the wall receives contact")
			check(count(events,"explosion")==0 and count(events,"split")==0 and count(events,"return_started")==0,"Wall does not trigger natural end effects")
			check(shots.is_empty() and carrier.end_reason==("hit_consumed" if pierce==0 else "terrain_collision"),"Pierce cannot bypass solid terrain")
			check(carrier.pos.x<=wall.position.x-6+0.001,"Parent/child footprint stops before wall")
	var runtime=Runtime.new();var returning:=shot(runtime,start);returning.state="returning";returning.return_center=Vector2(wall.end.x+10,start.y)
	var returning_shots:Array[Dictionary]=[returning]
	var returning_events:Array[Dictionary]=runtime.advance(returning_shots,2.0,[],returning.return_center,180,Callable(),geometry.sweep)
	check(returning.end_reason=="terrain_collision" and count(returning_events,"explosion")==0,"Returning shot remains blocked even with owner beyond wall")
	runtime=Runtime.new();var embedded:=shot(runtime,wall.get_center());var embedded_shots:Array[Dictionary]=[embedded]
	var embedded_targets:Array[Dictionary]=[{"id":9,"pos":wall.get_center(),"radius":8.0,"health":100.0,"spawn":0.0}]
	var embedded_events:Array[Dictionary]=runtime.advance(embedded_shots,0.1,embedded_targets,start,180,Callable(),geometry.sweep)
	check(count(embedded_events,"hit")==0 and embedded.end_reason=="terrain_collision","Carrier originating inside wall cannot damage an overlapping target before t0 collision")
	# A wall/range tie consumes the wall, but the historical lifetime ceiling still wins.
	for lifespan:float in [10.0,0.5]:
		runtime=Runtime.new();var carrier:=shot(runtime,start,{"range":100.0,"lifetime":lifespan,"split":true,"role":"parent"});var shots:Array[Dictionary]=[carrier]
		var events:Array[Dictionary]=runtime.advance(shots,1.0,[],start,180,Callable(),geometry.sweep)
		check(count(events,"split")==0 and count(events,"return_started")==0,"Wall at range prevents range callbacks")
		check(carrier.end_reason==("lifetime_expired" if lifespan==0.5 else "terrain_collision"),"Lifetime deadline precedence remains exact")
		check(count(events,"explosion")==int(lifespan==0.5),"Only a genuine same-time lifetime end gets expiry effect")
	# Time subdivision and cached work ordering cannot change the actual wall event.
	var a=Runtime.new();var b=Runtime.new();b.use_cached_work_order=false
	var sa:Array[Dictionary]=[shot(a,start)];var sb:Array[Dictionary]=[shot(b,start)];var original_a:Dictionary=sa[0];var original_b:Dictionary=sb[0]
	var ea:Array[Dictionary]=a.advance(sa,0.8,targets,start,180,Callable(),geometry.sweep)
	var eb:Array[Dictionary]=[]
	for tick:int in range(8):eb.append_array(b.advance(sb,0.1,targets,start,180,Callable(),geometry.sweep))
	check(original_a.end_reason==original_b.end_reason and original_a.pos.is_equal_approx(original_b.pos),"Subdivided sweep yields the same collision position/reason")
	check(count(ea,"hit")==count(eb,"hit") and count(ea,"terrain_hit")==count(eb,"terrain_hit"),"Subdivision preserves unique pre-wall hits and one collision")
	geometry.configure("old_garden",View.WORLD_ARENA)
	a=Runtime.new();b=Runtime.new();sa=[shot(a,start,{"range":100.0})];sb=sa.duplicate(true);b.next_projectile_id=a.next_projectile_id;b.next_cast_id=a.next_cast_id
	ea=a.advance(sa,2.5,targets,start,180);eb=b.advance(sb,2.5,targets,start,180,Callable(),geometry.sweep)
	check(ea==eb and sa==sb,"Explicit empty wall query exactly equals legacy runtime")
	print("Terrain projectiles: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
