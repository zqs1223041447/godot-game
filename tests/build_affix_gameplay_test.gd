extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Gear=preload("res://scripts/items/equipment_catalog.gd")
const Items=preload("res://scripts/items/unified_item_catalog.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Preview=preload("res://scripts/combat/damage_preview.gd")
const Card=preload("res://scripts/ui/unified_item_presentation.gd")
const DUAL=["50986","39725","63649","49806","6580","19711","20010","36704"]
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func near(a:float,b:float,label:String)->void:check(is_equal_approx(a,b),label+": "+str(a)+" expected "+str(b))
func gear(base:String,uid:String)->Dictionary:
	var affixes:Array=[]
	for id:String in Gear.BuildAffixes.AFFIX_IDS:affixes.append({"id":id,"tier":3,"value":Gear.affix_definition(id).tiers[2].max})
	return {"id":uid,"base_id":base,"item_level":16,"rarity":"rare","affixes":affixes}
func target()->Dictionary:
	var result:Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(60,0),"ordinary","",[],false)
	result.spawn=0.0;result.health=100000.0;result.max_health=result.health;result.shield=0.0;result.max_shield=0.0;result.armour=0.0;result.evasion=0.0;result.resistances={}
	return result
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	check(arena.save_build(),"Initial legitimate normal save")
	check(arena.leave_normal_town(arena.world_context().revision).ok,"Real practice entry for accepted combat")
	var model:RefCounted=arena.state;var baseline:Dictionary=model.get_basic_cast();var uids:Array[String]=[]
	for spec:Array in [["wayglass_token","amulet"],["nine_slot_etched_ring","ring_1"],["nine_slot_etched_ring","ring_2"],["nine_slot_threaded_gloves","gloves"]]:
		var uid:String="gear_%06d"%int(model.snapshot().next_item_serial);uids.append(uid)
		check(model._admit_reward_item(Items.wrap_equipment(gear(spec[0],uid))),"New actual equipment UID enters bag")
		check(model.move_item(uid,{"kind":"equipment","slot_id":spec[1]},model.revision(),arena.NORMAL_BUILD_PATH).ok,"Real slot atomically equips new affixes: "+str(spec[1]))
	var profile:Dictionary=model.get_leech_profile();var actual:Dictionary=model.get_basic_cast()
	near(profile.health.attack_fraction,0.024,"Four equipped life prefixes add")
	near(profile.mana.attack_fraction,0.014,"Four equipped mana prefixes add")
	near(actual.critical.primary.chance,0.13,"Four equipped chance suffixes scale5% base")
	near(actual.critical.primary.multiplier,2.1,"Four equipped multiplier suffixes add60points")
	for id:String in model.Data.SKILLS:
		var cast:Dictionary=Compiler.compile_group(id,model.get_combat_snapshot(),[])
		check(cast.ok and cast.has("leech")== (id in ["tornado","cleave"]),"Actual leech attack-only scope "+id)
		if id not in ["dash","ward"]:near(cast.critical.primary.chance,0.13,"Global crit also reaches actual spell "+id)
	var main_uid:String=model.award_gem("skill:cleave");check(not main_uid.is_empty(),"Real cleave gem acquired")
	check(model.move_item(main_uid,{"kind":"skill_main","group_id":"group_000009"},model.revision(),arena.NORMAL_BUILD_PATH).ok,"Real active gem installed")
	var cast:Dictionary=model.get_group_cast("group_000009");var card:Dictionary=Card.view(model,main_uid)
	check("\n".join(card.preview_lines).contains("2.40%") and "\n".join(card.preview_lines).contains("1.40%") and "\n".join(card.preview_lines).contains("13.0%"),"Actual model/compiled equipment reaches K card")
	var before:Dictionary=model.snapshot();var loaded:=Model.new();check(loaded.load_build(arena.NORMAL_BUILD_PATH) and loaded.snapshot()==before and loaded.get_leech_profile()==profile,"Equipped four-family full save roundtrip")
	arena.enemies.clear();arena.projectiles.clear();arena.damage_trace.clear();arena.leech_runtime.clear();arena.group_cooldowns.reset();arena.player_facing=Vector2.RIGHT;arena.health=10.0;arena.mana=60.0
	var enemy:=target();var original_target:=enemy.duplicate(true);var chosen_seed:=0
	for i:int in range(1,200):
		var rng:=RandomNumberGenerator.new();rng.seed=i
		if float(rng.randi())/4294967296.0<0.13:chosen_seed=i;break
	check(chosen_seed>0,"Deterministic critical fixture found without touching loot RNG")
	arena.critical_runtime._rng.seed=chosen_seed
	var loot_before:int=arena.rng.state;var saves:int=model.successful_saves
	check(arena.cast_group("group_000009") and arena.damage_trace.size()==1,"Actual accepted melee cast hits")
	var hit:Dictionary=arena.damage_trace.back();check(hit.critical.critical,"Equipped crit profile drives real result")
	near(hit.critical.multiplier,2.1,"Real hit uses equipped multiplier")
	var expected:Dictionary=arena.Damage.resolve(cast.packets.direct,cast.snapshot.modifiers,{},2.1)
	near(hit.total,expected.total,"Real final damage follows same compiled packet")
	var applied:float=hit.shield_spent+hit.health_lost
	near(hit.leech.health,minf(applied*0.024,cast.leech.health.instance_amount_cap),"Life budget comes from actual equipped hit")
	near(hit.leech.mana,minf(applied*0.014,cast.leech.mana.instance_amount_cap),"Mana budget comes from actual equipped hit")
	var loot_after:int=arena.rng.state
	check(model.successful_saves==saves,"Crit/leech do not write save")
	var life_before:float=arena.health;var mana_before:float=arena.mana;arena._advance_leech(0.5)
	near(arena.health-life_before,minf(hit.leech.health,cast.leech.health.instance_rate*0.5),"Life recovered at frozen per-instance rate")
	near(arena.mana-mana_before,minf(hit.leech.mana,cast.leech.mana.instance_rate*0.5),"Mana recovered at frozen per-instance rate")
	# Existing hit effects use the shared stream. Compare the identical accepted
	# cast with new profiles disabled, not an incorrect claim that casting draws none.
	arena.enemies.clear();arena.enemies.append(original_target);arena.damage_trace.clear();arena.leech_runtime.clear();arena.rng.state=loot_before
	var control:Dictionary=cast.duplicate(true);control.snapshot.erase("leech");control.erase("leech");control.snapshot.critical.primary.chance=0.0;control.critical.primary.chance=0.0
	check(arena._execute_compiled(control) and arena.rng.state==loot_after,"Enabled critical/leech leaves existing accepted-cast shared RNG advancement identical")
	# Freeze a live projectile before changing the equipped build.
	arena.enemies.clear();arena.projectiles.clear();arena.group_cooldowns.reset();arena.mana=float(arena._stats.max_mana)
	var tornado:Dictionary=model.get_skill_cast("tornado");check(arena._execute_compiled(tornado) and not arena.projectiles.is_empty(),"Actual tornado carrier created")
	var shot:Dictionary=arena.projectiles[0];var frozen:=var_to_bytes(shot.snapshot)
	for uid:String in uids:
		var position:Dictionary=model.first_bag_position(uid);check(not position.is_empty() and model.move_item(uid,position,model.revision(),arena.NORMAL_BUILD_PATH).ok,"Actual unequip preserves UID and changes next cast")
	near(model.get_basic_cast().critical.primary.chance,baseline.critical.primary.chance,"Unequip restores base critical chance")
	check(not model.get_basic_cast().has("leech") and var_to_bytes(shot.snapshot)==frozen,"Old projectile keeps frozen equipment profile, next cast has no leech")
	# A real passive source combines with equipped gear, rather than replacing it.
	var candidate:Dictionary=model.snapshot();candidate.progress.level=3;candidate.progress.xp=0;candidate.talents.class_id=4;candidate.talents.allocated=DUAL.duplicate();candidate.talents.normal_points=0;candidate.revision+=1
	check(model._commit(candidate,arena.NORMAL_BUILD_PATH).ok,"Real supported source path fixture persists")
	check(model.move_item(uids[0],{"kind":"equipment","slot_id":"amulet"},model.revision(),arena.NORMAL_BUILD_PATH).ok,"One item reapplied through actual command")
	near(model.get_leech_profile().health.attack_fraction,0.010,"Source0.4% plus item0.6% life")
	near(model.get_leech_profile().mana.attack_fraction,0.0075,"Source0.4% plus item0.35% mana")
	# One natural weighted acquisition witness through the authoritative model API.
	var witness_seed:=0
	for i:int in range(1,300):
		var rng:=RandomNumberGenerator.new();rng.seed=i
		var rolled:=Gear.generate_loot_profile(rng,"gear_000123",16,"rare",Gear.CANONICAL_LOOT_PROFILE_ID)
		for affix:Dictionary in rolled.affixes:
			if Gear.BuildAffixes.AFFIX_IDS.has(affix.id):witness_seed=i
		if witness_seed>0:break
	var rng:=RandomNumberGenerator.new();rng.seed=witness_seed
	var new_uid:String=model.award_equipment(rng,16,"rare")
	check(not new_uid.is_empty() and model.item(new_uid).payload.affixes.any(func(a:Dictionary)->bool:return Gear.BuildAffixes.AFFIX_IDS.has(a.id)),"Current model natural loot dispatcher can actually award new family")
	check(model.save_build(arena.NORMAL_BUILD_PATH)==OK,"Actual awarded item saves with journey intact")
	print("Build affix gameplay: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
