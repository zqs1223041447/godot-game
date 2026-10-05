extends SceneTree
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const Model=preload("res://scripts/canonical_game_state.gd")
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func near(a:float,b:float,label:String)->void:check(absf(a-b)<0.00000001*maxf(1.0,absf(b)),label)
func clean()->void:
	arena.enemies.clear();arena.projectiles.clear();arena.monster_runtime.reset();arena.telegraphs.reset();arena.burn_runtime.reset();arena.burn_trace.clear();arena.damage_trace.clear();arena._ember_deaths.clear()
	arena.feedback_runtime.reset();arena.leech_runtime.clear();arena.rng.seed=8084;arena.elapsed=0.0;arena._burn_step_active=false;arena.alive=true;arena.invulnerable=0.0;arena.auto_fire=false;arena.spawn_timer=1000.0
	arena._world_mode="normal";arena._geometry.configure("old_garden",arena.ARENA);arena.player_pos=arena.ARENA.get_center();arena.hud.close_panel();arena.health=10000.0;arena.shield=5000.0;arena.mana=1000.0
func target(offset:Vector2,rewards:bool=false)->Dictionary:
	var e:Dictionary=arena._spawn_monster("brute",arena.player_pos+offset,"ordinary","",[],rewards)
	e.spawn=0.0;e.health=10000.0;e.max_health=10000.0;e.shield=0.0;e.max_shield=0.0;e.resistances.fire=0.0;e.armour=0.0;e.speed=0.0;e.attack_timer=1000.0;e.shield_regen=0.0;e.shield_recharge_rate=0.0
	return e
func cast(support:String="ember_proliferation",amount:float=10.0)->Dictionary:
	return Compiler.compile_group("meteor",Combat.snapshot({"damage":amount,"crit_base_chance":0.0,"crit_base_multiplier":1.5},[]),[support])
func attach(e:Dictionary,c:Dictionary)->Dictionary:
	arena._apply_damage_packet(e,c.packets.direct,c.snapshot,Color.ORANGE)
	return arena.burn_runtime.status_for("monster",int(e.id))
func status(e:Dictionary)->Dictionary:return arena.burn_runtime.status_for("monster",int(e.id))
func time_advance(at:float)->void:arena.elapsed=at;arena._advance_monster_burns(at)
func temporal(divisions:int)->Dictionary:
	clean()
	# The future recipient has the smaller ID, exposing old per-target ordering.
	var recipient:=target(Vector2(180,0));var source:=target(Vector2(80,0))
	var c:=cast();var s:=attach(source,c);var dps:float=s.raw_dps
	source.health=dps*0.4
	check(arena.burn_runtime.apply("monster",recipient.id,0,0.1,3.0,0.0).ok,"Old recipient burn admitted")
	for i:int in range(divisions):time_advance(float(i+1)/float(divisions))
	var result:Dictionary={"recipient_health":recipient.health,"source_health":source.health,"status":status(recipient),"rng":arena.rng.state,"kills":arena.kills}
	near(float(recipient.health),10000.0-0.1*0.4-dps*0.6,"Only exact post-death remainder burns recipient")
	near(float(result.status.provenance.ember_expiry),3.0,"Original absolute expiry survives partition")
	return result
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	check(arena.save_build(),"Fresh29 saved")
	var model:RefCounted=arena.state
	var offer:Dictionary={}
	for row:Dictionary in arena.normal_gem_offers():
		if row.definition_id=="support:ember_proliferation":offer=row
	check(not offer.is_empty() and offer.cost==4,"Actual merchant lists new gem for4")
	for item:Dictionary in model.snapshot().items.values():check(item.definition_id!="support:ember_proliferation","No new gem gifted")
	var candidate:Dictionary=model.snapshot();check(model._set_bag_currency_balance(candidate,4).ok,"Fixture physical currency")
	candidate.revision+=1;check(model._commit(candidate,arena.NORMAL_BUILD_PATH).ok,"Currency fixture persisted atomically")
	var quote:Dictionary=arena.normal_gem_trade_quote("buy","support:ember_proliferation",model.revision())
	check(quote.ok and quote.cost.calibration_shard==4,"Real unique purchase quote")
	var purchase:Dictionary=arena.execute_normal_gem_trade(quote.handle,"support:ember_proliferation")
	check(purchase.ok and model.crafting_balance()==0,"Real transaction deducts4")
	check(not arena.execute_normal_gem_trade(quote.handle,"support:ember_proliferation").ok,"Same quote cannot spend twice")
	var group_id:=""
	for g:Dictionary in model.snapshot().skill_groups:
		if model.skill_group(g.id).skill_id=="meteor":group_id=g.id
	check(model.move_item(purchase.uid,{"kind":"skill_support","group_id":group_id,"index":0},model.revision(),arena.NORMAL_BUILD_PATH).ok,"Bought UID slots into actual group")
	var real_cast:Dictionary=model.get_group_cast(group_id)
	check(real_cast.ok and real_cast.burn_profile.proliferation.enabled,"Actual group compiler enables propagation")
	var loaded:=Model.new();check(loaded.load_build(arena.NORMAL_BUILD_PATH) and loaded.snapshot()==model.snapshot(),"Actual equipped schema29 reload")
	check(loaded.get_group_cast(group_id)==real_cast,"Saved group compile identical")
	clean();var source:=target(Vector2(80,0));var recipient:=target(Vector2(500,0));var third:=target(Vector2(600,0))
	var mana:float=arena.mana;check(arena.cast_group(group_id),"Real purchased group casts")
	near(mana-arena.mana,real_cast.mana,"Mana is paid once")
	check(arena.group_cooldowns.remaining(group_id,model.skill_group(group_id).main_uid)>0.0,"Existing cooldown debt starts")
	recipient.pos=arena.player_pos+Vector2(190,0);third.pos=arena.player_pos+Vector2(300,0)
	var original:=status(source);check(not original.is_empty() and original.provenance.ember_generation==0,"Actual source has direct lineage")
	check(status(recipient).is_empty(),"Recipient outside spell begins without burn")
	arena.elapsed=0.25;arena._damage_enemy(source,1000000.0,Color.WHITE)
	var inherited:=status(recipient)
	check(not inherited.is_empty() and inherited.provenance.ember_generation==1,"Death creates one-hop receiver")
	near(inherited.raw_dps,original.raw_dps,"Inherited DPS frozen")
	near(inherited.provenance.ember_expiry,original.provenance.ember_expiry,"Inherited absolute deadline frozen")
	near(inherited.remaining,2.75,"No duration reset")
	near(recipient.health,10000.0,"Transfer creates no instantaneous damage")
	var rng:int=arena.rng.state;var critical:Dictionary=arena.critical_runtime.checkpoint();var leech:Dictionary=arena.leech_runtime.snapshot();var saves:int=model.successful_saves
	recipient.shield=1000.0;recipient.resistances.fire=0.5;time_advance(0.75)
	near(1000.0-float(recipient.shield),float(original.raw_dps)*0.25,"Transfer uses receiver resistance and shield first")
	check(arena.rng.state==rng and arena.critical_runtime.checkpoint()==critical and arena.leech_runtime.snapshot()==leech and model.successful_saves==saves,"Nonlethal inherited DOT has no RNG crit leech or writes")
	arena._damage_enemy(recipient,1000000.0,Color.WHITE);check(status(third).is_empty(),"Inherited burn cannot chain to third target")
	var after:Dictionary=model.snapshot();arena._finish_enemy_death(source);check(model.snapshot()==after and arena._ember_deaths.is_empty(),"Duplicate death has no extra transaction or queue")
	# Large and small time partitions must produce the same remaining burn.
	var one:=temporal(1);var split:=temporal(60)
	near(one.recipient_health,split.recipient_health,"One interval and60pieces agree on actual life")
	near(one.status.remaining,split.status.remaining,"Partition independent remaining duration")
	check(one.rng==split.rng,"Partition does not introduce RNG")
	# Two same-cut sources die before any recipient is selected.
	clean();var a:=target(Vector2(0,0));var b:=target(Vector2(1,0));var c:=cast();var sa:=attach(a,c);attach(b,c)
	a.health=float(sa.raw_dps)*0.5;b.health=float(sa.raw_dps)*0.5
	var crowd:Array[Dictionary]=[]
	for i:int in range(10):crowd.append(target(Vector2(10+i*5,0)))
	time_advance(0.5)
	check(a.health<=0.0 and b.health<=0.0,"Both exact-cut sources dead")
	for i:int in range(crowd.size()):check(not status(crowd[i]).is_empty() if i<8 else status(crowd[i]).is_empty(),"Nearest8 only; dead sources consume no slot")
	check(arena._ember_deaths.is_empty(),"All same-cut transfers drained")
	# Actual walls and birth protection gate transfer, while same-side valid target receives.
	clean();arena._geometry.configure("broken_ruins",arena.ARENA)
	var wall:Rect2=arena._geometry.snapshot().walls[0]
	source=target(Vector2.ZERO);recipient=target(Vector2.ZERO);third=target(Vector2.ZERO)
	source.pos=wall.position+Vector2(-20,100);recipient.pos=wall.position+Vector2(76,100);third.pos=source.pos+Vector2(-40,0)
	var newborn:=target(Vector2.ZERO);newborn.pos=source.pos+Vector2(0,20);newborn.spawn=0.5
	attach(source,cast());arena._damage_enemy(source,1000000.0,Color.WHITE)
	check(status(recipient).is_empty() and status(newborn).is_empty() and not status(third).is_empty(),"Real geometry LOS and birth protection")
	# Superseding source attribution follows the winning burn, not historical seed.
	clean();source=target(Vector2(80,0));recipient=target(Vector2(180,0));attach(source,cast());attach(source,cast("ignite"))
	check(not status(source).provenance.has("ember_generation"),"Stronger ordinary ignite replaces lineage")
	arena._damage_enemy(source,1000000.0,Color.WHITE);check(status(recipient).is_empty(),"Overwritten source cannot propagate")
	clean();source=target(Vector2(80,0));recipient=target(Vector2(180,0));source.health=1.0;attach(source,cast())
	check(status(recipient).is_empty(),"Instant lethal hit never formed burn")
	clean();source=target(Vector2(80,0));recipient=target(Vector2(180,0));sa=attach(source,cast());source.health=float(sa.raw_dps)*3.0;time_advance(3.0)
	check(source.health<=0.0 and status(recipient).is_empty(),"Death exactly at expiry has no remaining flame")
	# Cross-target historical near-equal projectile times stay monotonic.
	clean();source=target(Vector2(80,0));recipient=target(Vector2(180,0));c=cast();arena._burn_step_active=true;arena._burn_step_start=1000000.0;arena.elapsed=1000001.0
	arena._apply_damage_packet(source,c.packets.direct,c.snapshot,Color.ORANGE,0.0,{"time":0.5000001})
	arena._apply_damage_packet(recipient,c.packets.direct,c.snapshot,Color.ORANGE,0.0,{"time":0.5})
	near(status(source).last_time,status(recipient).last_time,"Cross-target tie uses relative offsets even after long uptime")
	arena._burn_step_active=false
	arena._finish_player_death() # Alive player is unchanged; explicit death then clears all.
	arena.health=0.0;arena._finish_player_death();check(arena.burn_runtime.is_empty() and arena._ember_deaths.is_empty(),"Player death cancels all transient flame")
	print("EMBER_GAMEPLAY_COMPLETE checks=%d failures=%d"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
