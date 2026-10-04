extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Data=preload("res://scripts/game_data.gd")
const Rules=preload("res://scripts/combat/leech_rules.gd")
const Preview=preload("res://scripts/combat/damage_preview.gd")
const Card=preload("res://scripts/ui/unified_item_presentation.gd")
const Sheet=preload("res://scripts/ui/canonical_character_panel.gd")
const DUAL=["50986","39725","63649","49806","6580","19711","20010","36704"]
const PHYSICAL=["50986","47389","42911","40867","476","24865","6741","14056","34400","24914","61262","37800"]
var checks:=0
var failures:=0
var arena:Node

func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func near(actual:float,expected:float,label:String)->void:check(absf(actual-expected)<=maxf(0.00000001,absf(expected)*0.000000001),label+" got %s expected %s"%[actual,expected])
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var plain:=Model.new();var raw:=plain.get_combat_snapshot()
	var baseline:Array=bytes_to_var(FileAccess.get_file_as_bytes("res://tests/fixtures/v040_leech/zero-leech-v39.bin"))
	for entry:Dictionary in baseline:
		var cast:Dictionary=Compiler.compile_basic(raw) if entry.skill=="$basic" else Compiler.compile_group(entry.skill,raw,entry.supports)
		check(var_to_bytes(cast)==var_to_bytes(entry.compiled),"Frozen v39 zero-leech recipe exact: "+entry.skill+str(entry.supports))
	check(not raw.has("leech_modifiers"),"No zero-leech snapshot field added")
	var model:=Model.new();var candidate:=model.snapshot()
	candidate.progress.level=119;candidate.progress.xp=0;candidate.talents.class_id=4;candidate.talents.allocated=DUAL.slice(0,-1);candidate.talents.normal_points=124-candidate.talents.allocated.size()
	check(model.Rules.reason(candidate).is_empty(),"Real connected source path before dual leech")
	model._accept_memory(candidate);var path:="user://leech-build.json";check(model.save_build(path)==OK,"Source fixture persists")
	check(model.available_passives().has("36704") and model.allocate_passive("36704",0,model.revision(),path).ok,"Actual dual leech source node allocates atomically")
	var profile:=model.get_leech_profile()
	near(profile.health.attack_fraction,0.004,"Source life fraction preserved")
	near(profile.mana.attack_fraction,0.004,"Source mana fraction preserved")
	near(profile.health.instance_rate,model.get_stats().max_health*0.02,"Authoritative life instance rate")
	var sheet:=Sheet.leech_stat_values(profile)
	check(sheet.health_leech_instance==profile.health.instance_rate and sheet.mana_leech_cap==profile.mana.total_rate_cap,"C sheet consumes actual model profile")
	var uid:String=model.award_gem("skill:cleave")
	check(model.move_item(uid,{"kind":"skill_main","group_id":"group_000009"},model.revision(),path).ok,"Real cleave UID occupies actual skill group")
	var frozen:=model.get_group_cast("group_000009")
	var view:=Card.view(model,uid)
	check(Preview.leech_lines(frozen).size()==2 and "\n".join(view.preview_lines).contains("生命偷取：攻击 0.40%") and "\n".join(view.preview_lines).contains("法力偷取：攻击 0.40%"),"Actual compiler reaches K unified card")
	for id:String in Data.SKILLS:
		var cast:Dictionary=Compiler.compile_group(id,model.get_combat_snapshot(),[])
		check(cast.ok and cast.has("leech")== (id in ["tornado","cleave"]),"Actual active skill eligibility: "+id)
	check(model.get_basic_cast().has("leech"),"Basic attack uses same leech consumer")
	var frozen_bytes:=var_to_bytes(frozen)
	for node:String in ["54872","1382","9171","39530"]:
		check(model.available_passives().has(node) and model.allocate_passive(node,0,model.revision(),path).ok,"Reachable source speed/cap node "+node)
	var later:=model.get_leech_profile()
	check(later.health.attack_fraction>profile.health.attack_fraction and later.mana.attack_fraction>profile.mana.attack_fraction,"Real life and mana notable increase fractions")
	check(later.health.total_rate_cap>profile.health.total_rate_cap and later.mana.total_rate_cap>profile.mana.total_rate_cap,"Real total cap sources both consumed")
	check(later.mana.instance_rate>profile.mana.instance_rate and later.health.instance_rate>profile.health.instance_rate,"Real instance rate sources both consumed")
	check(var_to_bytes(frozen)==frozen_bytes,"Existing cast unchanged by later allocations")
	var loaded:=Model.new();check(loaded.load_build(path) and loaded.snapshot()==model.snapshot() and loaded.get_leech_profile()==later,"Saved schema25 allocation/profile restores")
	# Start the actual main scene and use the authoritative source build.
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	arena.build_save_path=path;arena.state._accept_memory(model.snapshot());arena._on_build_changed()
	clean()
	var actual:Dictionary=arena.state.get_group_cast("group_000009")
	var before_state:=var_to_bytes(arena.state.snapshot());var saves:int=arena.state.successful_saves
	var target:=enemy(Vector2(60,0));target.health=3.0;target.shield=7.0;target.armour=100.0
	var packet:Dictionary=arena.Damage.packet({"physical":60.0,"cold":40.0},["hit","attack"],"controlled_mixed")
	var before_health:float=arena.health;var before_mana:float=arena.mana
	arena._apply_damage_packet(target,packet,actual.snapshot,Color.WHITE)
	var observed:Dictionary=arena.damage_trace.back()
	near(observed.shield_spent+observed.health_lost,10.0,"Actual damage bounded to enemy shield+life")
	near(observed.leech.health,10.0*later.health.attack_fraction,"Actual overkill excluded from life budget")
	near(observed.leech.mana,10.0*later.mana.attack_fraction,"Actual overkill excluded from mana budget")
	check(arena.health==before_health and arena.mana==before_mana,"Hit admission has no instant recovery")
	var ledger:=var_to_bytes(arena.leech_runtime.snapshot());arena._apply_damage_packet(target,packet,actual.snapshot,Color.WHITE)
	check(var_to_bytes(arena.leech_runtime.snapshot())==ledger,"Dead target cannot duplicate recovery")
	arena._tick(0.5)
	near(arena.health-before_health,observed.leech.health,"Main tick recovers bounded life budget")
	near(arena.mana-before_mana,observed.leech.mana,"Main tick recovers bounded mana budget")
	check(var_to_bytes(arena.state.snapshot())==before_state and arena.state.successful_saves==saves,"Leech advances do not persist or change build revision")
	# A real cast, rather than direct hit helpers, creates the same source profile.
	clean();target=enemy(Vector2(60,0));target.health=100000.0
	check(arena.cast_group("group_000009") and arena.damage_trace.size()==1,"Real active gem cast delivers melee hit")
	check(arena.damage_trace.back().has("leech") and not arena.leech_runtime.is_empty(),"Real cast starts non-instant dual recovery")
	var debt:Dictionary=arena.group_cooldowns.snapshot();ledger=var_to_bytes(arena.leech_runtime.snapshot());var old_rng:int=arena.rng.state
	check(not arena.cast_group("group_000009") and ledger==var_to_bytes(arena.leech_runtime.snapshot()) and old_rng==arena.rng.state and debt==arena.group_cooldowns.snapshot(),"Cooldown failure cannot add recovery or change RNG/debt")
	# Fullness from pickups clears one resource immediately, before later spending.
	arena.health=float(arena._stats.max_health)-1.0;arena.mana=0.0
	arena.pickups.clear();arena.pickups.append({"pos":arena.player_pos,"life":3.0});arena._update_pickups(0.0)
	check(arena.leech_runtime.snapshot().health.expiries.is_empty() and not arena.leech_runtime.snapshot().mana.expiries.is_empty(),"Pickup full health clears only health ledger immediately")
	arena.health-=1.0;before_health=arena.health;arena._advance_leech(0.02)
	check(arena.health==before_health,"Damage after a full pickup cannot revive stored life leech")
	# Same final damage/loot RNG with leech on and off; actual recovery stays separate.
	var observations:Array=[]
	for enabled:bool in [false,true]:
		clean();target=enemy(Vector2(60,0));arena.rng.seed=4080
		var snapshot:Dictionary=actual.snapshot.duplicate(true)
		if not enabled:snapshot.erase("leech")
		arena._apply_damage_packet(target,actual.packets.direct,snapshot,Color.WHITE)
		var hit:Dictionary=arena.damage_trace.back().duplicate(true);hit.erase("leech")
		observations.append({"target":target.duplicate(true),"hit":hit,"rng":arena.rng.state})
	check(var_to_bytes(observations[0])==var_to_bytes(observations[1]),"Leech does not change hit, enemy state, particles or original RNG")
	await projectile_and_lifecycle(actual)
	print("Leech compile/gameplay: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)

func clean()->void:
	arena.enemies.clear();arena.projectiles.clear();arena.pickups.clear();arena.damage_trace.clear();arena.combat_trace.clear();arena.attack_admission_trace.clear();arena.event_counts.clear()
	arena.monster_runtime=arena.MonsterLifecycle.new();arena.projectile_runtime=arena.Projectiles.new();arena.leech_runtime.clear();arena.group_cooldowns.reset()
	arena.player_pos=arena.ARENA.get_center();arena.player_facing=Vector2.RIGHT;arena.alive=true;arena.health=10.0;arena.mana=80.0;arena.shield=0.0;arena.invulnerable=0.0;arena.spawn_timer=10000.0
	arena._stats.life_regen=0.0;arena._stats.mana_regen=0.0;arena.attack_timer=0.0
	for id:String in arena.cooldowns:arena.cooldowns[id]=0.0

func enemy(offset:Vector2)->Dictionary:
	var target:Dictionary=arena._spawn_monster("crawler",arena.player_pos+offset,"ordinary","",[],false)
	target.spawn=0.0;target.health=100000.0;target.max_health=100000.0;target.shield=0.0;target.max_shield=0.0;target.evasion=0.0;target.armour=0.0
	return target

func projectile_and_lifecycle(actual:Dictionary)->void:
	clean();arena.equip_tornado_example()
	while arena.hud.is_blocking():arena.hud.close_panel()
	var cast:Dictionary=arena.state.get_skill_cast("tornado");arena.mana=float(arena._stats.max_mana)-1.0
	check(arena._execute_compiled(cast),"Actual equipment tornado admitted")
	var saved:Dictionary=cast.leech.duplicate(true)
	for shot:Dictionary in arena.projectiles:check(shot.snapshot.leech==saved,"Parent inherits one frozen profile")
	arena._update_projectiles(0.4)
	for shot:Dictionary in arena.projectiles:check(shot.generation==1 and shot.snapshot.leech==saved,"Children inherit without reapplying leech values")
	arena._update_projectiles(0.6)
	for shot:Dictionary in arena.projectiles:check(shot.state=="returning" and shot.snapshot.leech==saved,"Returning projectiles retain profile")
	var previous:Dictionary=arena.state.snapshot();var candidate:Dictionary=previous.duplicate(true)
	candidate.talents.allocated=DUAL.duplicate();candidate.talents.normal_points=124-DUAL.size()
	check(arena.state.Rules.reason(candidate).is_empty(),"Replacement source build valid")
	arena.state._accept_memory(candidate);arena._on_build_changed()
	check(arena.state.get_skill_cast("tornado").leech!=saved,"Next cast uses changed build")
	for shot:Dictionary in arena.projectiles:check(shot.snapshot.leech==saved,"Active carrier unaffected by source refund")
	arena.state._accept_memory(previous);arena._on_build_changed()
	clean();var target:=enemy(Vector2(200,25));var origin:Vector2=arena.player_pos+Vector2(200,0)
	var shot:Dictionary=arena.projectile_runtime.make_projectile(origin,Vector2.RIGHT,{"speed":10.0,"range":500.0,"lifetime":0.01,"pierce":-1,"radius":1.0},cast.packets.parent,cast.snapshot,arena.projectile_runtime.new_cast(),Color.WHITE)
	arena.projectiles.append(shot);arena._update_projectiles(0.02)
	check(int(arena.event_counts.get("explosion",0))==1 and not arena.damage_trace.is_empty(),"Actual natural-end explosion delivers damage")
	check(arena.leech_runtime.is_empty() and not arena.damage_trace.back().has("leech"),"Independent non-attack explosion cannot borrow parent leech")
	clean();target=enemy(Vector2(60,0));arena._apply_damage_packet(target,actual.packets.direct,actual.snapshot,Color.WHITE)
	var before:=var_to_bytes(arena.leech_runtime.snapshot());arena.hud.open_panel("inventory");arena._process(0.5)
	check(before==var_to_bytes(arena.leech_runtime.snapshot()),"Paused menu freezes leech clock")
	arena.hud.close_panel();arena.hit_player_components({"chaos":1000000.0})
	check(not arena.alive and arena.leech_runtime.is_empty(),"Player death clears recovery without resurrection")
	arena.restart_run();check(arena.leech_runtime.is_empty(),"Restart has no old recovery")
	# The profile switch and return paths reuse the existing restart lifecycle.
	# Legacy equipment convenience calls save to NORMAL_BUILD_PATH. Rebind through
	# a real load rather than bypassing that store's external-write protection.
	var normal:=Model.new();check(normal.load_build(arena.NORMAL_BUILD_PATH),"Reload actual normal profile after equipment operations")
	arena._replace_build(normal,arena.NORMAL_BUILD_PATH);arena.restart_run();clean()
	target=enemy(Vector2(60,0));var normal_cast:Dictionary=arena.state.get_basic_cast()
	arena._apply_damage_packet(target,normal_cast.packets.projectile,normal_cast.snapshot,Color.WHITE)
	check(not arena.leech_runtime.is_empty(),"Real profile has pending recovery before switching")
	var entered:Dictionary=arena.enter_town_test(arena.world_context().revision)
	check(entered.ok,"Optional test-town profile opens normally: "+str(entered.get("reason","")))
	check(arena.leech_runtime.is_empty(),"Profile switch keeps recovery runtime-only")
	check(arena.start_map(arena.map_draft().revision).ok,"Actual finite map starts")
	clean();target=enemy(Vector2(60,0));normal_cast=arena.state.get_basic_cast()
	arena._apply_damage_packet(target,normal_cast.packets.projectile,normal_cast.snapshot,Color.WHITE)
	check(not arena.leech_runtime.is_empty(),"Map combat creates pending recovery")
	check(arena.return_to_town(arena.world_context().revision).ok and arena.leech_runtime.is_empty(),"Confirmed return to town clears both resources")
	check(arena.leave_town_test(arena.world_context().revision).ok and arena.leech_runtime.is_empty(),"Normal profile restored without runtime ledger")
