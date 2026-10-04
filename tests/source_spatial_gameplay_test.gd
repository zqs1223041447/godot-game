extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const Runtime=preload("res://scripts/combat/projectile_runtime.gd")
const Geometry=preload("res://scripts/world/map_geometry.gd")
const View=preload("res://scripts/visuals/world_view.gd")
const PATHS={
	"area_size_increased":["58833","2151","5560"],
	"melee_area_size_increased":["58833","48828","33508","36881","35503","19144","28330","46578","30733","49178","43374","22703","14056","11700"],
	"projectile_speed_increased":["58833","48828","33508","36881","35503","19144","16167","10829","238","11497","5408","56589","23471","5237","30679","11678","44306"],
	"spell_area_size_increased":["58833","2151","37690","48423","6204","63976","33479","10490","22473","14211","42731","37078","14182","13322","60090","46092","51923","48778","37671","27415","32710","51801"]}
var checks:=0
var failures:=0
var arena:Node
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func count(events:Array,type:String)->int:
	var found:=0
	for event:Dictionary in events:if event.type==type:found+=1
	return found
func fixture(path:Array)->Dictionary:
	var model:=Model.new()
	model.award_gem("skill:cleave");model.award_gem("skill:shade_bolt")
	var candidate:=model.snapshot()
	# Isolated high-level fixture exposes the real connected path, not a grant in production.
	candidate.progress.level=119;candidate.progress.xp=0;candidate.talents.allocated=path.duplicate();candidate.talents.normal_points=123-(path.size()-1)
	for uid:String in candidate.items:
		if candidate.items[uid].definition_id=="skill:cleave":candidate.locations[uid]={"kind":"skill_main","group_id":"group_000009"}
		elif candidate.items[uid].definition_id=="skill:shade_bolt":candidate.locations[uid]={"kind":"skill_main","group_id":"group_000010"}
	return candidate
func clean()->void:
	arena.enemies.clear();arena.projectiles.clear();arena.damage_trace.clear();arena.combat_trace.clear();arena.event_counts.clear();arena.monster_runtime.reset();arena.projectile_runtime=Runtime.new()
	arena.player_pos=arena.ARENA.get_center();arena.player_facing=Vector2.RIGHT;arena.alive=true;arena.attack_timer=0.0;arena.mana=10000.0
	for id:String in arena.cooldowns:arena.cooldowns[id]=0.0
func enemy(position:Vector2)->Dictionary:
	var result:Dictionary=arena._spawn_monster("crawler",position,"ordinary","",[],false)
	result.spawn=0.0;result.radius=1.0;result.health=10000.0;result.max_health=10000.0;result.evasion=0.0;result.shield=0.0;result.max_shield=0.0
	return result
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	# Actual model transactions on all four source paths, including current save reload.
	for stat:String in PATHS:
		var nodes:Array=PATHS[stat];var prefix:Array=nodes.slice(0,nodes.size()-1);var model:=Model.new();var candidate:=fixture(prefix)
		check(Rules.reason(candidate).is_empty(),"Connected pre-node fixture validates: "+stat)
		model._accept_memory(candidate);var path:="user://path-"+stat+".json"
		check(model.save_build(path)==OK,"Validated source path persisted")
		var before:Dictionary=model.get_stats();var prior_basic:=model.get_basic_cast();var previous_revision:=model.revision()
		check(model.available_passives().has(nodes.back()) and model.allocate_passive(nodes.back(),0,model.revision(),path).ok,"Real allocation entry admits new full source node")
		var grant:=0.0
		for value:Dictionary in SourceTree.node_effect(nodes.back()).grants:if value.stat==stat:grant+=float(value.value)
		check(is_equal_approx(model.get_stats()[stat]-before[stat],grant) and model.revision()==previous_revision+1,"Actual stat consumer sums source value once")
		var actual:Dictionary=model.snapshot();var reloaded:=Model.new()
		check(reloaded.load_build(path) and reloaded.snapshot()==actual and reloaded.get_stats()==model.get_stats(),"Current save retains UID/path/stat projection")
		if stat=="projectile_speed_increased":check(model.get_basic_cast().recipe.speed>prior_basic.recipe.speed,"Basic cast cache invalidated by source allocation")
		var borrowed:=model.get_basic_cast();borrowed.recipe.speed=1.0
		check(model.get_basic_cast().recipe.speed!=1.0,"Cached basic cast is detached from caller mutation")
		check(model.refund_passive(nodes.back(),model.revision(),path).ok and model.get_stats()==before and model.get_basic_cast()==prior_basic,"Refund restores prior stats and exact cached cast projection")
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	var boosted:=fixture(PATHS.area_size_increased);var plain:=fixture(["58833","2151"])
	# Real direct-area hit boundaries and current spell/melee scopes.
	for id:String in ["nova","meteor","cleave"]:
		var casts:Array=[]
		for candidate:Dictionary in [plain,boosted]:
			arena.state._accept_memory(candidate);casts.append(arena.state.get_skill_cast(id))
		check(casts[0].ok and casts[1].ok and casts[1].recipe.radius>casts[0].recipe.radius,"Real slotted gem receives source AoE: "+id)
		var midpoint:float=(casts[0].recipe.radius+casts[1].recipe.radius)*0.5
		var results:Array=[]
		for compiled:Dictionary in casts:
			clean();var origin:Vector2=arena.player_pos
			if id=="meteor":origin+=Vector2(30,0);enemy(origin)
			var inside:=enemy(origin+Vector2(midpoint,0));var outside:=enemy(origin+Vector2(casts[1].recipe.radius+2.0,0));var start_mana:float=arena.mana
			check(arena._execute_compiled(compiled),"Main executes the actual compiled area skill")
			results.append(inside.health<10000.0)
			check(outside.health==10000.0 and is_equal_approx(start_mana-arena.mana,compiled.mana) and is_equal_approx(arena.cooldowns[id],compiled.cooldown),"Outer boundary/mana/cooldown remain exact")
		check(results==[false,true],"New annulus changes real hit admission, not just display: "+id)
	# Actual spawned scalar projectiles keep cast speed despite a source refund.
	var speed_build:=fixture(PATHS.projectile_speed_increased);var no_speed:=fixture(PATHS.projectile_speed_increased.slice(0,-1))
	for id:String in ["bolt","frost","shade_bolt"]:
		clean();arena.state._accept_memory(speed_build);var cast:Dictionary=arena.state.get_skill_cast(id);enemy(arena.player_pos+Vector2(600,0))
		check(arena._execute_compiled(cast),"Main spawns final source-speed projectile: "+id)
		var carrier:Dictionary=arena.projectiles[0];var start:Vector2=carrier.pos;var frozen:Dictionary=carrier.snapshot.duplicate(true)
		arena.state._accept_memory(no_speed);arena._update_projectiles(0.05)
		check(is_equal_approx(carrier.pos.distance_to(start),float(cast.recipe.speed)*0.05) and carrier.snapshot==frozen and carrier.speed==cast.recipe.speed,"Active carrier keeps original speed/snapshot after allocation state changes")
		check(carrier.range==650.0 and carrier.lifetime==1.7,"Main scalar carrier range/lifetime caps unchanged")
	clean();arena.state._accept_memory(speed_build);arena._stats=arena.state.get_stats();arena.auto_fire=true;enemy(arena.player_pos+Vector2(600,0));arena._update_auto_attack()
	check(arena.projectiles.size()==1 and arena.projectiles[0].speed==arena.state.get_basic_cast().recipe.speed and arena.projectiles[0].speed>640.0,"Real automatic basic attack consumes cached source speed")
	# Carrier descendants, returning flight and independent explosion use one frozen recipe.
	var raw:=Combat.snapshot({"damage":20.0,"projectile_speed_increased":0.5,"area_size_increased":0.44},["return_on_range","explode_on_flight_end"])
	var cast:=Compiler.compile_skill("tornado",raw,[]);var runtime:=Runtime.new();var shots:Array[Dictionary]=[]
	check(runtime.spawn_tornado(shots,Vector2.ZERO,Vector2.RIGHT,cast.snapshot,180,1)==1,"One real parent admitted")
	var parent:Dictionary=shots[0];var events:=runtime.advance(shots,0.25,[],Vector2.ZERO,180)
	check(parent.end_reason=="split_consumed" and count(events,"split")==1 and shots.size()==3,"Faster parent reaches same range and splits once")
	for child:Dictionary in shots:check(child.speed==390.0 and child.recipe.child.speed==390.0 and child.snapshot.explosion_recipe.radius==cast.snapshot.explosion_recipe.radius,"Children inherit final speed/area once")
	var children:=shots.duplicate(false);events=runtime.advance(shots,0.5,[],Vector2.ZERO,180)
	check(count(events,"return_started")==3 and count(events,"explosion")==0,"Returning starts at unchanged child range before lifetime")
	for child:Dictionary in shots:check(child.state=="returning" and is_equal_approx(child.velocity.length(),390.0),"Return keeps frozen child speed")
	events=runtime.advance(shots,2.0,[],Vector2.ZERO,180)
	check(shots.is_empty() and count(events,"explosion")==3 and count(events,"lifetime_expired")==3,"Natural lifetimes emit one terminal explosion per child")
	for event:Dictionary in events:if event.type=="explosion":check(is_equal_approx(event.radius,91.2),"Actual terminal event uses scaled explosion radius")
	# Same final recipes preserve the lifetime/range/solid-wall precedence.
	var geometry:=Geometry.new();geometry.configure("broken_ruins",View.WORLD_ARENA);var wall:Rect2=geometry.snapshot().walls[0]
	for speed_source:float in [-0.1,0.5]:
		var compiled:=Compiler.compile_basic(Combat.snapshot({"damage":20.0,"projectile_speed_increased":speed_source,"area_size_increased":0.44},["return_on_range","explode_on_flight_end"]))
		for lifespan:float in [0.5,1.7]:
			runtime=Runtime.new();var speed:float=compiled.recipe.speed;var radius:=5.5;var origin:=Vector2(wall.position.x-radius-speed*0.5,wall.get_center().y)
			var carrier:=runtime.make_projectile(origin,Vector2.RIGHT,{"speed":speed,"range":speed*0.5,"lifetime":lifespan,"radius":radius,"pierce":-1},compiled.packets.projectile,compiled.snapshot,runtime.new_cast(),Color.WHITE)
			shots=[carrier];events=runtime.advance(shots,2.0,[],origin,180,Callable(),geometry.sweep)
			check(carrier.end_reason==("lifetime_expired" if lifespan==0.5 else "terrain_collision") and count(events,"return_started")==0 and count(events,"explosion")==int(lifespan==0.5),"Compiled fast/slow carrier preserves lifetime then wall then range ordering")
	# Independent explosion annulus in actual main settlement, with frozen compiled payload.
	clean();var blast_cast:=Compiler.compile_basic(raw);var end:Vector2=arena.player_pos+Vector2(100,0)
	var target:=enemy(end+Vector2(0,85));var outside:=enemy(end+Vector2(0,94))
	var blast_shot:Dictionary=arena.projectile_runtime.make_projectile(end,Vector2.RIGHT,{"speed":blast_cast.recipe.speed,"range":650.0,"lifetime":0.1},blast_cast.packets.projectile,blast_cast.snapshot,arena.projectile_runtime.new_cast(),Color.WHITE)
	blast_shot.age=0.1;arena.projectiles.append(blast_shot);arena._update_projectiles(0.01)
	check(target.health<10000.0 and outside.health==10000.0 and int(arena.event_counts.get("explosion",0))==1,"Main explosion damages newly covered annulus once and respects outer boundary")
	print("Source spatial gameplay: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
