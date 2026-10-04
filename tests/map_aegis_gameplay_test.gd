extends SceneTree
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
const Encounter=preload("res://scripts/encounters/encounter_admission.gd")
var arena:Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func begin(special:Array,ordinary:Array=[])->void:
	if arena.world_context().mode=="map":arena.return_to_town(arena.world_context().revision)
	check(arena.craft_map("broken_ruins",ordinary,special,arena.map_draft().revision).ok,"Select current map through authority")
	arena.rng.seed=303003;arena.monster_runtime.next_id=0
	check(arena.start_map(arena.map_draft().revision).ok,"Start authoritative current profile")
	while arena.hud.is_blocking():arena.hud.close_panel()
func clean_enemy(template:String="brute")->Dictionary:
	arena.enemies.clear();arena.monster_runtime.reset();arena.projectiles.clear();arena.damage_trace.clear();arena.combat_trace.clear()
	arena.player_pos=arena.ARENA.get_center();arena.player_facing=Vector2.RIGHT
	var enemy:Dictionary=arena._spawn_monster(template,arena.player_pos+Vector2(70,0),"ordinary","",[],false)
	enemy.spawn=0.0;enemy.max_health=10000.0;enemy.health=10000.0;enemy.shield=0.0;enemy.max_shield=0.0;enemy.evasion_rating=0.0
	return enemy
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	check(arena.enter_town_test(arena.world_context().revision).ok,"Enter existing test mode")
	var base_build:Dictionary=arena.state.snapshot()
	# Match all natural admissions using the exact same seed/identity start.
	for ordinary:Array in [[],["enemy_max_health_120","enemy_move_speed_110"]]:
		var cases:Array=[]
		for special:Array in [[],["elemental_aegis"]]:
			begin(special,ordinary)
			while arena._map_run.can_admit():
				if arena._spawn_enemy().is_empty():check(false,"Natural root failed");break
			cases.append({"enemies":arena.enemies.duplicate(true),"random":arena.rng.state,"roots":arena.monster_runtime.roots.duplicate(true)})
		check(cases[0].random==cases[1].random and cases[0].roots==cases[1].roots and cases[0].enemies.size()==36,"Natural seed, identities, lineage and finite admissions unchanged")
		var ash:=0
		for index:int in range(36):
			var before:Dictionary=cases[0].enemies[index];var after:Dictionary=cases[1].enemies[index]
			for field:String in before:
				if field not in ["defense_stats","resistances"]:check(before[field]==after[field],"Natural admission non-defense field unchanged: "+field)
			check(after.map_defense_source.modifier_id=="elemental_aegis","Every admitted root has one source marker")
			if before.template_id=="ember_guard":
				ash+=1;check(is_equal_approx(after.resistances.fire,0.45),"Natural ash admission preserves base25 then adds20")
		check(ash>0,"Actual ash fixed admission present")
	# Actual skill execution/projectile delivery, including mixed tornado packets.
	for id:String in ["cleave","shade_bolt","meteor","nova","chain","bolt","frost","tornado"]:
		var amounts:Array=[]
		for special:Array in [[],["elemental_aegis"]]:
			begin(special);var target:=clean_enemy();arena.cooldowns[id]=0.0;arena.mana=arena._stats.max_mana
			var cast:Dictionary=Compiler.compile_skill(id,arena.state.get_combat_snapshot(),[])
			var starting_mana:float=arena.mana
			check(arena._execute_compiled(cast),"Actual skill admitted: "+id)
			arena._update_projectiles(0.8)
			var components:Dictionary={}
			for record:Dictionary in arena.damage_trace:
				for type:String in record.components:components[type]=float(components.get(type,0.0))+float(record.components[type])
			amounts.append(components)
			check(not components.is_empty() and is_equal_approx(starting_mana-arena.mana,float(cast.mana)) and is_equal_approx(float(arena.cooldowns[id]),float(cast.cooldown)),"Damage delivered with unchanged mana/cooldown: "+id)
		for type:String in amounts[0]:
			var multiplier:=0.8 if type in ["fire","cold","lightning"] else 1.0
			check(is_equal_approx(float(amounts[1].get(type,0)),float(amounts[0][type])*multiplier),"Actual "+id+" component "+type+" settles only its matching resistance")
	begin(["elemental_aegis"])
	var target:=clean_enemy("ember_guard");target.shield=50.0;target.max_shield=50.0
	var before_health:float=target.health
	arena._apply_damage_packet(target,Damage.packet({"physical":100.0,"fire":100.0,"cold":100.0,"lightning":100.0,"chaos":100.0},["hit"],"mixed_hit"),arena.state.get_combat_snapshot(),Color.WHITE,0.0)
	var hit:Dictionary=arena.damage_trace.back()
	check(is_equal_approx(hit.components.fire,55.0) and is_equal_approx(hit.components.cold,80.0) and is_equal_approx(hit.components.lightning,80.0) and hit.components.physical==100.0 and hit.components.chaos==100.0,"Mixed main settlement uses45fire/20cold/20lightning and unchanged physical/chaos")
	check(target.shield==0.0 and is_equal_approx(before_health-target.health,365.0) and hit.shield_spent==50.0,"Effective mitigation precedes shield then life")
	# Late descendant application uses the same rule once and remains rewardless.
	var parent:=clean_enemy("splitter");parent.health=0.0;var death:Dictionary=arena.monster_runtime.process_death(parent);arena._flush_monster_spawns()
	check(arena.enemies.size()==death.queued,"Real child queue drains full reserved count")
	for child:Dictionary in arena.enemies:check(child.resistances=={"fire":0.2,"cold":0.2,"lightning":0.2} and not child.reward_eligible and child.xp_reward==0,"Main child admission gets20once and no new reward")
	var rng_before:int=arena.rng.state;var runtime_before:Dictionary=Encounter._snapshot(arena.monster_runtime)
	var valid:Dictionary=arena._map_run.profile;arena._map_run.profile=valid.duplicate(true);arena._map_run.profile.special_ids=["unknown"]
	check(arena._spawn_enemy().is_empty() and arena.rng.state==rng_before and Encounter._snapshot(arena.monster_runtime)==runtime_before,"Invalid active map rejected before RNG/identity")
	arena._map_run.profile=valid
	check(arena.return_to_town(arena.world_context().revision).ok and arena.state.snapshot()==base_build,"Testing the modifier adds no persistent fields or build mutation")
	print("Map aegis gameplay: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
