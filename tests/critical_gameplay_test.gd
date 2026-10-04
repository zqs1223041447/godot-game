extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const CriticalRuntime=preload("res://scripts/combat/critical_strike_runtime.gd")
const Projectiles=preload("res://scripts/combat/projectile_runtime.gd")
const Presentation=preload("res://scripts/ui/unified_item_presentation.gd")
const PATHS=[
	[6,"crit_chance_increased",["44683","38129","11334","15549","20546","35894"]],
	[6,"crit_multiplier_add",["44683","38129","11334","15549","20546","35894","35283","28754"]],
	[3,"spell_crit_chance_increased",["54447","57226","21678","32210","8948","38176","11551","19635","44723"]],
	[3,"spell_crit_multiplier_add",["54447","57226","21678","32210","8948","38176","11551","19635","44723","16790","53493"]],
	[4,"melee_crit_chance_increased",["50986","47389","42911","40867","476","24865","6741","14056","34400","24914","38664"]],
	[4,"melee_crit_multiplier_add",["50986","47389","42911","40867","476","24865","6741","14056","34400","24914","38664","56460"]],
	[2,"projectile_attack_crit_chance_increased",["50459","39821","52904","444","61306","60942","32555","22266","14804"]],
	[2,"projectile_attack_crit_multiplier_add",["50459","39821","52904","444","61306","60942","32555","22266","14804","12794"]]]
var checks:=0
var failures:=0
var arena:Node
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func observe()->Dictionary:
	return {"mana":arena.mana,"shots":arena.projectiles.duplicate(true),"ids":[arena.projectile_runtime.next_projectile_id,arena.projectile_runtime.next_cast_id],"rng":arena.rng.state,"critical":arena.critical_runtime.checkpoint(),"debts":arena.group_cooldowns.snapshot(),"state":arena.state.snapshot(),"saves":arena.state.successful_saves}
func clean()->void:
	arena.enemies.clear();arena.projectiles.clear();arena.damage_trace.clear();arena.combat_trace.clear();arena.attack_admission_trace.clear();arena.event_counts.clear();arena.monster_runtime=arena.MonsterLifecycle.new();arena.projectile_runtime=Projectiles.new()
	arena.group_cooldowns.reset();arena.player_pos=arena.ARENA.get_center();arena.player_facing=Vector2.RIGHT;arena.alive=true;arena.attack_timer=0.0;arena.mana=10000.0
	for id:String in arena.cooldowns:arena.cooldowns[id]=0.0
func enemy(at:Vector2)->Dictionary:
	var e:Dictionary=arena._spawn_monster("crawler",at,"ordinary","",[],false)
	e.spawn=0.0;e.radius=8.0;e.health=100000000.0;e.max_health=e.health;e.shield=0.0;e.max_shield=0.0;e.armour=0.0;e.evasion=0.0
	return e
func winning_seed(snapshot:Dictionary)->int:
	var rt:=CriticalRuntime.new()
	for seed_value:int in range(10000):
		rt.reset(seed_value)
		if rt.freeze(snapshot).snapshot.get("critical_roll",{}).get("critical",false):return seed_value
	return -1
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	for row:Array in PATHS:
		var model:=Model.new();var candidate:=model.snapshot();var nodes:Array=row[2];var prefix:Array=nodes.slice(0,-1)
		candidate.progress.level=119;candidate.progress.xp=0;candidate.talents.class_id=row[0];candidate.talents.allocated=prefix;candidate.talents.normal_points=124-prefix.size()
		check(model.Rules.reason(candidate).is_empty(),"Actual connected pre-node build validates: "+row[1])
		model._accept_memory(candidate);var path:String="user://critical-"+row[1]+".json"
		check(model.save_build(path)==OK,"Connected source fixture saved atomically")
		var before:Dictionary=model.get_stats();var previous:Dictionary=model.get_skill_cast("tornado");var old_spell:Dictionary=model.get_skill_cast("nova")
		check(model.available_passives().has(nodes.back()) and model.allocate_passive(nodes.back(),0,model.revision(),path).ok,"Real available-node transaction admits complete critical node")
		var grant:=0.0
		for g:Dictionary in model.SourceTree.node_effect(nodes.back()).grants:if g.stat==row[1]:grant+=float(g.value)
		check(is_equal_approx(model.get_stats()[row[1]]-before[row[1]],grant),"Real source value enters authoritative stat exactly once")
		var now:Dictionary=model.get_skill_cast("tornado");var spell:Dictionary=model.get_skill_cast("nova")
		if str(row[1]).begins_with("spell_"):check(now.critical==previous.critical and spell.critical!=old_spell.critical,"Spell investment changes spell and not attack")
		elif str(row[1]).begins_with("projectile_attack_"):check(now.critical!=previous.critical and spell.critical==old_spell.critical,"Projectile-attack investment excludes spell")
		elif str(row[1]).begins_with("melee_"):check(now.critical==previous.critical and spell.critical==old_spell.critical,"Melee investment excludes ranged attack and spell")
		else:check(now.critical!=previous.critical and spell.critical!=old_spell.critical,"Global critical investment reaches attack and spell")
		var loaded:=Model.new();check(loaded.load_build(path) and loaded.snapshot()==model.snapshot() and loaded.get_skill_cast("tornado")==now,"Saved source allocation and compiled profile reload exactly")
		check(model.refund_passive(nodes.back(),model.revision(),path).ok and model.get_stats()==before and model.get_skill_cast("tornado")==previous,"Refund restores exact earlier profile")
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	var model:Model=arena.state;var path:="user://critical-live.json";arena.build_save_path=path
	for id:String in ["cleave","shade_bolt"]:
		var uid:String=model.award_gem("skill:"+id)
		check(not uid.is_empty() and model.move_item(uid,{"kind":"skill_main","group_id":"group_000009" if id=="cleave" else "group_000010"},model.revision(),path).ok,"Real new skill gem equipped into existing UID row")
	var support_uid:String=model.award_gem("support:efficiency")
	for group:Dictionary in model.snapshot().skill_groups:
		clean();check(model.move_item(support_uid,{"kind":"skill_support","group_id":group.id,"index":0},model.revision(),path).ok,"Real support remains compatible with critical casting")
		var compiled:Dictionary=model.get_group_cast(group.id);var id:String=compiled.skill_id
		var seed_value:=winning_seed(compiled.snapshot) if compiled.has("critical") else 19
		check(seed_value>=0,"Actual canonical profile has a reachable deterministic critical result")
		arena.critical_runtime.reset(seed_value);enemy(arena.player_pos+Vector2(60,0));enemy(arena.player_pos+Vector2(80,12));enemy(arena.player_pos+Vector2(100,-12))
		arena.mana=compiled.mana-0.000001;var before:=observe()
		check(not arena.cast_group(group.id) and observe()==before,"Insufficient mana rejects before critical/loot RNG, UID, debt or payment: "+id)
		if compiled.initial_count>0:
			arena.projectiles.resize(arena.MAX_PROJECTILES)
			for i:int in range(arena.MAX_PROJECTILES):arena.projectiles[i]={}
			arena.mana=10000.0;before=observe();check(not arena.cast_group(group.id) and observe()==before,"Full carrier budget rejects without a critical draw")
			arena.projectiles.clear()
		arena.mana=compiled.mana;var saved:=model.snapshot();var saves:int=model.successful_saves
		check(arena.cast_group(group.id) and is_zero_approx(arena.mana),"Real group cast pays final exact mana: "+id)
		check(model.snapshot()==saved and model.successful_saves==saves and is_equal_approx(arena.group_cooldown_remaining(group.id),compiled.cooldown),"Critical cast keeps runtime-only payment and existing UID cooldown debt")
		if id in ["dash","ward"]:check(arena.critical_runtime.draws==0 and arena.critical_runtime.events==0,"Utility does not roll critical")
		else:
			if compiled.initial_count>0:arena._update_projectiles(0.25)
			check(not arena.damage_trace.is_empty() and arena.critical_runtime.draws==1 and arena.critical_runtime.events==1,"One actual cast roll drives its initial hits: "+id)
			for record:Dictionary in arena.damage_trace:check(record.critical.critical and record.critical.multiplier==compiled.critical.primary.multiplier,"Every admitted target inherits the single cast result")
			var content:Dictionary=model.skill_group(group.id);var view:=Presentation.view(model,content.main_uid)
			check("\n".join(view.preview_lines).contains("暴击几率 5.0%") or "\n".join(view.preview_lines).contains("暴击几率 5%"),"Real K card shows exact compiled baseline probability")
		arena.mana=10000.0;before=observe();check(not arena.cast_group(group.id) and observe()==before,"Cooldown refusal does not reroll critical")
	# Old raw/zero profiles preserve source RNG, event and hit arithmetic paths.
	clean();var raw:=Combat.snapshot({"damage":20.0},[]);var plain:=Compiler.compile_skill("nova",raw,[])
	var raw_zero:=raw.duplicate(true);raw_zero.critical_modifiers={"base_chance":0.0,"base_multiplier":1.5};var zero:=Compiler.compile_skill("nova",raw_zero,[])
	var runs:Array=[]
	for compiled:Dictionary in [plain,zero]:
		clean();arena.rng.seed=513;enemy(arena.player_pos+Vector2(60,0));arena.critical_runtime.reset(89)
		check(arena._execute_compiled(compiled),"Legacy/zero direct cast admitted")
		runs.append([arena.damage_trace.duplicate(true),arena.rng.state,arena.critical_runtime.checkpoint(),arena.enemies.duplicate(true)])
	check(runs[0]==runs[1],"Explicit zero and missing critical preserve full hit/target/loot RNG observations")
	# Enabling critical uses no values from the shared loot/particle generator.
	var shared_states:Array=[]
	var actual_nova:Dictionary=model.get_skill_cast("nova")
	var no_critical:Dictionary=actual_nova.duplicate(true);no_critical.snapshot.erase("critical");no_critical.erase("critical")
	for compiled:Dictionary in [no_critical,actual_nova]:
		clean();arena.rng.seed=9781;enemy(arena.player_pos+Vector2(60,0));arena.critical_runtime.reset(winning_seed(actual_nova.snapshot))
		check(arena._execute_compiled(compiled),"No-death matched load admitted")
		shared_states.append(arena.rng.state)
	check(shared_states[0]==shared_states[1],"Actual enabled critical never consumes shared loot/particle RNG in matched no-death load")
	clean();var corrupt:Dictionary=model.get_skill_cast("tornado").duplicate(true);corrupt.snapshot.compiled_packets.erase("parent")
	var refused_before:=observe();check(not arena._execute_compiled(corrupt) and observe()==refused_before,"Late tornado failure restores critical stream together with mana/debt/IDs")
	var invalid:Dictionary=model.get_skill_cast("nova").duplicate(true);invalid.snapshot.critical.primary.chance=true
	refused_before=observe();check(not arena._execute_compiled(invalid) and observe()==refused_before,"Malformed critical profile rejects atomically before casting")
	# Basic automatic entry uses the same snapshot while remaining free.
	clean();enemy(arena.player_pos+Vector2(60,0));var basic:=model.get_basic_cast();arena.critical_runtime.reset(winning_seed(basic.snapshot));arena.auto_fire=true;var mana_before:float=arena.mana
	arena._update_auto_attack();arena._update_projectiles(0.2);arena.auto_fire=false
	check(arena.mana==mana_before and arena.critical_runtime.draws==1 and not arena.damage_trace.is_empty() and arena.damage_trace[0].critical.critical,"Ordinary attack entry is free and uses shared critical consumer")
	# Evasion remains authoritative; a critical cast cannot turn a miss into a hit.
	clean();var evasive:=enemy(arena.player_pos+Vector2(60,0));evasive.evasion=100000000.0;evasive.evasion_entropy=0.0
	var melee:=model.get_skill_cast("cleave");arena.critical_runtime.reset(winning_seed(melee.snapshot))
	check(arena._execute_compiled(melee) and arena.damage_trace.is_empty() and not arena.attack_admission_trace.back().hit,"Rolled critical still misses a failed attack admission")
	# Mother/child/return inheritance and fresh per-event secondary rolls are checked below.
	await projectile_cases(model)
	print("Critical gameplay: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
func projectile_cases(model:Model)->void:
	clean();arena.equip_tornado_example()
	while arena.hud.is_blocking():arena.hud.close_panel()
	var compiled:Dictionary=model.get_skill_cast("tornado");var frozen:=var_to_bytes(compiled)
	arena.critical_runtime.reset(winning_seed(compiled.snapshot));check(arena._execute_compiled(compiled),"Actual equipment return/explosion tornado admitted")
	var cast_roll:Dictionary=arena.projectiles[0].snapshot.critical_roll.duplicate(true)
	for shot:Dictionary in arena.projectiles:check(shot.snapshot.critical_roll==cast_roll,"Every parent inherits primary roll")
	arena._update_projectiles(0.4)
	check(arena.projectiles.size()==int(compiled.initial_count)*3 and arena.critical_runtime.events==1,"Splitting retains one roll and exact child count")
	for shot:Dictionary in arena.projectiles:check(shot.snapshot.critical_roll==cast_roll and shot.generation==1,"Child inherits original roll without reapplying chance/multiplier")
	arena._update_projectiles(0.6)
	check(arena.critical_runtime.events==1,"Beginning return creates no secondary roll")
	for shot:Dictionary in arena.projectiles:check(shot.snapshot.critical_roll==cast_roll and shot.state=="returning","Return preserves original critical snapshot")
	# Changing current stat projection cannot alter existing carriers.
	var current:=model.snapshot();var modified:=current.duplicate(true);modified.talents.class_id=6;modified.progress.level=119;modified.progress.xp=0;modified.talents.allocated=PATHS[1][2].duplicate();modified.talents.normal_points=124-modified.talents.allocated.size()
	check(model.Rules.reason(modified).is_empty(),"Current build change fixture is legal")
	model._accept_memory(modified)
	check(model.get_skill_cast("tornado").critical!=compiled.critical and var_to_bytes(compiled)==frozen,"New source build changes next cast but not prior compiled object")
	for shot:Dictionary in arena.projectiles:check(shot.snapshot.critical==compiled.critical and shot.snapshot.critical_roll==cast_roll,"Flying carrier keeps frozen old profile/result after build change")
	model._accept_memory(current)
	# Use a genuine natural-end event with two targets and predict its independent draw.
	clean();var rt:CriticalRuntime=arena.critical_runtime;rt.reset(57)
	var snapshot:Dictionary=compiled.snapshot.duplicate(true);snapshot.critical.primary={"chance":1.0,"multiplier":2.0};snapshot.critical.secondary={"chance":0.5,"multiplier":1.7}
	var primary:Dictionary=rt.freeze(snapshot).snapshot;var next_state:Dictionary=rt.checkpoint();var expected:Dictionary=rt.freeze(primary,"secondary").snapshot.critical_roll;rt.restore(next_state)
	var origin:Vector2=arena.player_pos+Vector2(200,0);enemy(origin+Vector2(0,25));enemy(origin+Vector2(0,-25))
	var shot:Dictionary=arena.projectile_runtime.make_projectile(origin,Vector2.RIGHT,{"speed":10.0,"range":500.0,"lifetime":0.01,"pierce":-1,"radius":1.0},compiled.packets.parent,primary,arena.projectile_runtime.new_cast(),Color.WHITE)
	arena.projectiles.append(shot);arena._update_projectiles(0.02)
	check(int(arena.event_counts.get("explosion",0))==1 and rt.events==2 and rt.draws==1 and arena.damage_trace.size()==2,"One actual natural-end explosion rolls independently once across two targets")
	for record:Dictionary in arena.damage_trace:check(record.critical==expected and record.tags.has("secondary"),"Secondary targets share independent result and tag scope")
	var after:Dictionary=rt.checkpoint();arena._update_projectiles(0.1);check(rt.checkpoint()==after,"Completed projectile cannot reroll the same explosion")
	# Cancellation does not dispatch natural-end effects or consume the crit stream.
	arena.projectiles.append(arena.projectile_runtime.make_projectile(origin,Vector2.RIGHT,{"speed":10.0,"range":500.0,"lifetime":0.1},compiled.packets.parent,primary,arena.projectile_runtime.new_cast(),Color.WHITE))
	arena.projectile_runtime.cancel_all(arena.projectiles,"owner_death");arena._update_projectiles(0.2)
	check(rt.checkpoint()==after,"Owner cancellation consumes no secondary draw")

	# Hit consumption and terrain collision are not natural expiry events.
	clean();var target:=enemy(arena.player_pos+Vector2(25,0));rt.reset(57);primary=rt.freeze(snapshot).snapshot;after=rt.checkpoint()
	arena.projectiles.append(arena.projectile_runtime.make_projectile(arena.player_pos,Vector2.RIGHT,{"speed":200.0,"range":500.0,"lifetime":1.0,"pierce":0,"radius":1.0},compiled.packets.parent,primary,arena.projectile_runtime.new_cast(),Color.WHITE))
	arena._update_projectiles(0.3)
	check(arena.projectiles.is_empty() and target.health<100000000.0 and not arena.event_counts.has("explosion") and rt.checkpoint()==after,"Consumed hit emits no independent explosion or critical roll")
	clean();arena._geometry.configure("broken_ruins",arena.ARENA)
	var wall:Rect2=arena._geometry.snapshot().walls[0];origin=wall.position+Vector2(-30,80);rt.reset(57);primary=rt.freeze(snapshot).snapshot;after=rt.checkpoint()
	arena.projectiles.append(arena.projectile_runtime.make_projectile(origin,Vector2.RIGHT,{"speed":200.0,"range":500.0,"lifetime":1.0,"pierce":-1,"radius":1.0},compiled.packets.parent,primary,arena.projectile_runtime.new_cast(),Color.WHITE))
	arena._update_projectiles(0.3)
	check(arena.projectiles.is_empty() and int(arena.event_counts.get("terrain_hit",0))==1 and not arena.event_counts.has("explosion") and rt.checkpoint()==after,"Actual map wall consumes projectile without secondary draw")
	arena._geometry.configure("normal",arena.ARENA)
