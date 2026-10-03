extends SceneTree
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Profiles=preload("res://scripts/monsters/telegraph_profiles.gd")
const Model=preload("res://scripts/canonical_game_state.gd")
const TreeRules=preload("res://scripts/passives/source_tree_runtime.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Renderer=preload("res://scripts/visuals/telegraph_renderer.gd")
const EncounterCompiler=preload("res://scripts/encounters/encounter_compiler.gd")
const Settings=preload("res://scripts/visuals/visual_settings.gd")
var arena:Node
var checks:=0
var failures:=0
var found:={"frost_guard":0,"storm_skitter":0}
var evidence:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func near(a:float,b:float,label:String)->void:check(is_equal_approx(a,b),label+" %.9f / %.9f"%[a,b])
func run()->void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated+"/"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	test_policy()
	test_natural_rolls()
	for id:String in Monsters.ELEMENTAL_ENCOUNTERS:
		await test_node_and_attack(id)
		test_cancel_boundaries(id)
	test_rewards()
	check(found.frost_guard>0 and found.storm_skitter>0,"Both variants really arise through natural main admission")
	print("ELEMENTAL_ENCOUNTER_RECORDS "+JSON.stringify(evidence))
	print("Elemental encounters: %d checks, %d failures, natural substitutions %s"%[checks,failures,str(found)])
	arena.queue_free();await process_frame;quit(1 if failures else 0)
func test_policy()->void:
	check(Monsters.validate_templates(Monsters.TEMPLATES).is_empty(),"New templates satisfy shared mechanism/rarity/death rules")
	for id:String in Monsters.ELEMENTAL_ENCOUNTERS:
		var p:Dictionary=Monsters.ELEMENTAL_ENCOUNTERS[id]
		for rarity:String in Monsters.ORDINARY_RARITIES:
			var mechanisms:Array=[] if rarity=="normal" else ["gale_stride"] if rarity=="magic" else ["ember_power","aegis_capacity"]
			for wave:int in [4,5,10]:
				var old:Dictionary=Monsters.make_enemy(1,p.source_template,wave,Vector2.ZERO,"ordinary",rarity,mechanisms)
				var new:Dictionary=Monsters.make_enemy(1,id,wave,Vector2.ZERO,"ordinary",rarity,mechanisms)
				for key:String in old:
					if key not in ["template_id","name","contact_weights"]:check(new[key]==old[key],"Replacement retains source tier/species/stat/reward field "+key)
				var policy:=Monsters.telegraph_policy(new)
				near(policy.profile.windup_seconds,Profiles.ELEMENTAL[id].windup_seconds,"Shared attack speed never shortens warning")
				new.attack_speed*=2.0
				near(Monsters.telegraph_policy(new).profile.recovery_seconds,policy.profile.recovery_seconds*0.5,"Shared attack speed changes recovery exactly once")
				near(Monsters.telegraph_policy(new).profile.windup_seconds,policy.profile.windup_seconds,"Warning still fixed after haste")
		var original:Dictionary=Monsters.make_enemy(77,id,5,Vector2.ZERO,"ordinary","magic",["gale_stride"])
		var challenge:Dictionary=EncounterCompiler.compile(["enemy_max_health_120","enemy_move_speed_110"])
		var applied:Dictionary=EncounterCompiler.apply_to_enemy(original,challenge.profile)
		check(applied.ok,"Existing challenge compiler accepts elemental templates")
		near(applied.enemy.max_health,original.max_health*1.2,"Existing maximum-health modifier exactly once")
		near(applied.enemy.speed,original.speed*1.1,"Existing move modifier exactly once")
		check(applied.enemy.damage==original.damage and applied.enemy.contact_weights==original.contact_weights and Monsters.telegraph_policy(applied.enemy)==Monsters.telegraph_policy(original),"Challenge modifiers cannot invent elemental damage/timing changes")
		check(Monsters.elemental_template_for_roll(int(p.minimum_wave)-1,int(p.admission_remainder),{"template":p.source_template,"rarity":"normal"}).is_empty(),"Not before declared wave")
		for invalid:String in ["splitter","brood_host","rift_warden","ember_guard"]:
			check(Monsters.elemental_template_for_roll(99,int(p.admission_remainder),{"template":invalid,"rarity":"rare"}).is_empty(),"No replacement of existing special/boss/fire template")
	for n:int in range(1,65):check(Monsters.encounter_for_admission(5,n)==("ember_guard" if n%8==0 else ""),"Existing fire cadence remains exact")
func test_natural_rolls()->void:
	arena.demo_mode=false
	for wave:int in [3,4,5,8]:
		for index:int in range(64):
			arena.enemies.clear();arena.monster_runtime.reset();arena.wave=wave
			var ordinal:int=4 if index%2==0 else 6
			arena.ordinary_admissions=ordinal-1
			arena.rng.seed=250000+wave*1000+index
			var oracle:=RandomNumberGenerator.new();oracle.state=arena.rng.state
			var roll:=Monsters.ordinary_roll(oracle,wave)
			var expected_id:=Monsters.elemental_template_for_roll(wave,ordinal,roll)
			var side:=oracle.randi_range(0,3)
			if side<2:oracle.randf_range(arena.ARENA.position.y+36.0,arena.ARENA.end.y-40.0)
			else:oracle.randf_range(arena.ARENA.position.x+43.0,arena.ARENA.end.x-43.0)
			var actual:Dictionary=arena._spawn_enemy()
			check(not actual.is_empty(),"Actual natural admission succeeds")
			if actual.is_empty():continue
			check(actual.template_id==(roll.template if expected_id.is_empty() else expected_id),"Actual main uses the original roll then restricted replacement")
			check(arena.rng.state==oracle.state,"Variant selection consumes no extra RNG")
			check(arena.ordinary_admissions==ordinal,"Only successful ordinary admission advances ordinal")
			var original:=Monsters.make_enemy(actual.id,roll.template,wave,actual.pos,"ordinary",roll.rarity,roll.mechanisms)
			for key:String in ["kind","rarity","mechanism_ids","mechanism_stats","health","max_health","damage","speed","attack_speed","xp_reward","reward_eligible","death_spawns","equipment_pool"]:
				check(actual[key]==original[key],"Actual admission preserves original "+key)
			if not expected_id.is_empty():found[expected_id]+=1
	arena.demo_mode=true
func path_to(stat:String)->Array[String]:
	var start:String=TreeRules.Data.start_for_class(0)
	var queue:Array[String]=[start];var parents:Dictionary={start:""};var head:=0
	while head<queue.size():
		var id:String=queue[head];head+=1
		var effect:Dictionary=TreeRules.node_effect(id)
		if effect.status=="full" and effect.grants.size()==1 and effect.grants[0].stat==stat:
			var path:Array[String]=[]
			while not id.is_empty():path.push_front(id);id=parents[id]
			return path
		for neighbor:String in TreeRules.Data.adjacency(id):
			if parents.has(neighbor):continue
			var node:Dictionary=TreeRules.Data.node(neighbor)
			if node.type in ["start","mastery","proxy"] or node.source.get("isBlighted",false) or TreeRules.node_effect(neighbor).status!="full":continue
			parents[neighbor]=id;queue.append(neighbor)
	return []
func fresh_enemy(id:String)->Dictionary:
	arena.enemies.clear();arena.telegraphs.reset();arena.telegraph_trace.clear();arena.incoming_damage_trace.clear();arena.attack_admission_trace.clear()
	arena.alive=true;arena.health=1000.0;arena.shield=5.0;arena.invulnerable=0.0;arena._player_evasion_entropy=99.0
	arena.player_pos=arena.ARENA.get_center();arena.demo_mode=true;arena.wave=int(Monsters.ELEMENTAL_ENCOUNTERS[id].minimum_wave)
	var enemy:Dictionary=arena._spawn_monster(id,arena.player_pos+Vector2(100,0),"demo","normal",[],false)
	enemy.spawn=0.0;enemy.attack_timer=0.0
	return enemy
func test_node_and_attack(id:String)->void:
	var element:String=Monsters.ELEMENTAL_ENCOUNTERS[id].element
	var stat:=element+"_resistance";var path_nodes:=path_to(stat)
	check(not path_nodes.is_empty(),"A currently fully executable source path reaches "+stat)
	if path_nodes.is_empty():return
	var model:=Model.new();var candidate:=model.snapshot();candidate.progress.level=100;candidate.talents.normal_points=104
	model._accept_memory(candidate);var path:="user://elemental-"+id+".json"
	check(model.save_build(path)==OK,"Isolated earned-budget fixture saved")
	for node:String in path_nodes.slice(1,-1):check(model.allocate_passive(node,0,model.revision(),path).ok,"Actual valid connected path allocation "+node)
	var before:=model.get_stats();check(model.allocate_passive(path_nodes.back(),0,model.revision(),path).ok,"Actual final resistance node allocated")
	var after:=model.get_stats();check(after[stat]>before[stat],"Real source node changes typed resistance")
	var totals:Array[float]=[]
	for stats:Dictionary in [before,after]:
		arena.state=model;arena._stats=stats
		var enemy:=fresh_enemy(id);var policy:=Monsters.telegraph_policy(enemy)
		var rng_before:int=arena.rng.state
		arena._start_enemy_telegraphs();check(arena.telegraphs.active_count()==1,"Actual main begins warning")
		var visual:Array=arena.telegraph_visual_states();check(visual[0].visual_element==element,"Visual identity comes from frozen actual element")
		var original_position:Vector2=enemy.pos
		arena._update_enemies(float(policy.profile.windup_seconds)-0.001)
		check(arena.incoming_damage_trace.is_empty() and enemy.pos==original_position,"Full warning harmless and pursuit held")
		arena._advance_enemy_telegraphs(0.001)
		check(arena.incoming_damage_trace.size()==1,"Exactly one actual elemental damage event")
		if arena.incoming_damage_trace.is_empty():continue
		var hit:Dictionary=arena.incoming_damage_trace.back();var raw:float=enemy.damage*policy.profile.damage_multiplier
		check(hit.raw_components.size()==1 and hit.raw_components.has(element),"No hidden physical/status component")
		near(hit.damage_total,raw*(1.0-clampf(float(stats[stat]),0.0,0.75)),"Current matching resistance changes actual incoming hit")
		near(hit.shield_spent,minf(5.0,hit.damage_total),"Shield settles before life")
		near(hit.health_lost,maxf(0.0,hit.damage_total-5.0),"Only excess damage reaches life")
		check(arena.rng.state==rng_before,"Attack/timing/defense use no global RNG")
		totals.append(hit.damage_total)
		arena._advance_enemy_telegraphs(20.0);check(arena.incoming_damage_trace.size()==1,"Recovery never replays or adds contact")
	if totals.size()==2:check(totals[1]<totals[0],"Real allocated source node reduces real natural-template attack")
	var other:String="lightning" if element=="cold" else "cold"
	near(Defense.incoming_source_hit({other:100.0},before,0.0,1000.0).damage_total,Defense.incoming_source_hit({other:100.0},after,0.0,1000.0).damage_total,"Nonmatching element does not benefit from this node")
	var reopened:=Model.new();check(reopened.load_build(path) and reopened.snapshot()==model.snapshot(),"Resistance path and all items survive exact save roundtrip")
	evidence.append({"template":id,"element":element,"path":path_nodes,"before_resistance":before[stat],"after_resistance":after[stat],"actual_damage":totals})
	await process_frame
func test_cancel_boundaries(id:String)->void:
	for delta:float in [0.0,0.001]:
		var enemy:=fresh_enemy(id);var policy:=Monsters.telegraph_policy(enemy);arena._start_enemy_telegraphs()
		var center:Vector2=arena.player_pos
		arena.player_pos+=Vector2(float(policy.profile.radius)+arena.PLAYER_RADIUS+delta,0)
		arena._advance_enemy_telegraphs(policy.profile.windup_seconds)
		check(arena.telegraph_trace.size()==1 and arena.telegraph_trace[0].inside==(delta==0.0),"Exact circle/body edge and movement outside")
		check(arena.telegraph_trace[0].center==center,"Warning target remains locked")
	for reason:String in ["dead","removed","birth","processed"]:
		var enemy:=fresh_enemy(id);var policy:=Monsters.telegraph_policy(enemy);arena._start_enemy_telegraphs()
		match reason:
			"dead":enemy.health=0.0
			"removed":arena.enemies.clear()
			"birth":enemy.spawn=0.1
			"processed":enemy.death_processed=true
		arena._advance_enemy_telegraphs(policy.profile.windup_seconds)
		check(arena.telegraphs.active_count()==0 and arena.incoming_damage_trace.is_empty(),"Attack cancelled on "+reason)
	var enemy:=fresh_enemy(id);var policy:=Monsters.telegraph_policy(enemy)
	arena._stats=arena._stats.duplicate(true);arena._stats.evasion=100000.0;arena._player_evasion_entropy=0.0
	arena._start_enemy_telegraphs();arena._advance_enemy_telegraphs(policy.profile.windup_seconds)
	check(arena.incoming_damage_trace.is_empty() and arena.attack_admission_trace.size()==1 and not arena.attack_admission_trace[0].hit,"Actual elemental attack can be evaded through shared attack admission")
	enemy=fresh_enemy(id);enemy.spawn=0.1;arena._start_enemy_telegraphs();check(arena.telegraphs.active_count()==0,"Birth protection blocks admission")
	enemy.spawn=0;arena._start_enemy_telegraphs();enemy.damage=9999.0;enemy.contact_weights={"chaos":1.0}
	check(arena.telegraph_visual_states()[0].visual_element==Monsters.ELEMENTAL_ENCOUNTERS[id].element,"Live mutation cannot recolor frozen warning")
	var state:Dictionary=arena.telegraph_visual_states()[0];state.elapsed=0.2
	var settings:=Settings.new();settings.effects_level=0
	var primitives:=Renderer.primitives([state],settings);var boundary:=0
	for primitive:Dictionary in primitives:
		if primitive.role=="danger_boundary":boundary+=1;near(primitive.radius,policy.profile.radius,"Low mode real boundary matches damage radius")
	check(boundary==2 and primitives.size()<=Renderer.MAX_PRIMITIVES_PER_SOURCE,"Low effects keeps exact boundary under old primitive cap")

func test_rewards()->void:
	var model:=Model.new();check(model.save_build()==OK,"Create isolated main save for reward transaction")
	arena.state=model;model.changed.connect(arena._on_build_changed);arena._stats=model.get_stats()
	for id:String in Monsters.ELEMENTAL_ENCOUNTERS:
		arena.enemies.clear();arena.monster_runtime.reset();arena.demo_mode=false;arena.reward_kills=0
		var enemy:Dictionary=arena._spawn_monster(id,arena.player_pos+Vector2(100,0),"ordinary","normal",[],true)
		enemy.spawn=0.0
		var before:=model.snapshot();var saves:int=model.successful_saves
		arena._begin_progress_transaction();arena._damage_enemy(enemy,enemy.health+1.0,Color.WHITE);arena._end_progress_transaction()
		var after:=model.snapshot()
		check(arena.reward_kills==1 and enemy.death_processed,"One real root death gives one eligible kill")
		check(after.items==before.items and after.locations==before.locations,"No extra guaranteed item or currency reward")
		check(after.progress.xp==before.progress.xp+int(enemy.xp_reward),"Original same-species XP delivered exactly once")
		check(model.successful_saves==saves+1,"Reward transaction saves once")
		var random_state:int=arena.rng.state
		arena._damage_enemy(enemy,1.0,Color.WHITE)
		check(model.snapshot()==after and arena.rng.state==random_state,"Repeated corpse event cannot replay rewards or draws")
		check(arena.monster_runtime.queue.is_empty(),"Elemental variants add no death descendants")
	var reloaded:=Model.new();check(reloaded.load_build() and reloaded.snapshot()==model.snapshot(),"Real XP and all instances reload byte-equivalently")
	model.changed.disconnect(arena._on_build_changed)
