extends SceneTree
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const Burn=preload("res://scripts/combat/burn_rules.gd")
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func near(a:float,b:float,label:String)->void:check(absf(a-b)<0.00001*maxf(1.0,absf(b)),label)
func clean()->void:
	arena.enemies.clear();arena.projectiles.clear();arena.monster_runtime.reset();arena.telegraphs.reset();arena.burn_runtime.reset();arena.burn_trace.clear();arena.damage_trace.clear()
	arena.elapsed=0.0;arena._burn_step_active=false;arena._burn_immunity_until=0.0;arena.alive=true;arena.invulnerable=0.0;arena.damage_delay=0.0;arena.auto_fire=false;arena.spawn_timer=1000.0
	arena._world_mode="normal";arena._geometry.configure("old_garden",arena.ARENA);arena._stats=arena.state.get_stats();arena._stats.max_health=10000.0;arena._stats.max_shield=5000.0;arena._stats.life_regen=0.0;arena._stats.shield_recharge_rate=0.0;arena._stats.shield_regen=0.0;arena._stats.fire_resistance=0.0
	arena.health=10000.0;arena.shield=5000.0;arena.mana=1000.0;arena.player_pos=arena.ARENA.get_center();arena.hud.close_panel()
	for id:String in arena.Data.SKILLS:arena.cooldowns[id]=0.0
func target(id:String="brute",distance:float=100.0,rewards:bool=false)->Dictionary:
	var e:Dictionary=arena._spawn_monster(id,arena.player_pos+Vector2(distance,0),"ordinary","",[],rewards)
	e.spawn=0.0;e.max_health=10000.0;e.health=10000.0;e.max_shield=5000.0;e.shield=5000.0;e.armour=10000.0;e.resistances.fire=0.25;e.speed=0.0;e.attack_timer=1000.0;e.shield_regen=0.0;e.shield_recharge_rate=0.0
	return e
func meteor(critical:bool=false)->Dictionary:
	return Compiler.compile_group("meteor",Combat.snapshot({"damage":100.0,"fire_increased":0.5,"global_increased":0.2,"crit_base_chance":1.0 if critical else 0.0,"crit_base_multiplier":2.0},[]),["ignite"])
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	check(arena.save_build(),"Fresh schema28 profile saved")
	clean();var enemy:=target();var cast:=meteor(true);var mana:float=arena.mana
	check(arena._execute_compiled(cast),"Actual supported meteor accepted")
	near(mana-arena.mana,38.4,"Mana120% paid once");near(arena.cooldowns.meteor,8.0,"Cooldown unchanged")
	var statuses:Array=arena.burn_statuses();check(statuses.size()==1,"Actual surviving target attached one burn")
	var dps:float=float(cast.burn_profile.roles.direct.dps)*2.0
	near(statuses[0].raw_dps,dps,"Critical enters frozen fire basis exactly once")
	near(statuses[0].effective_dps,dps*0.75,"Current target fire resistance displayed")
	near(statuses[0].remaining_seconds,3.0,"No instantaneous burn duration consumed")
	var shield:float=enemy.shield;var life:float=enemy.health;var rng:int=arena.rng.state;var critical_state:Dictionary=arena.critical_runtime.checkpoint();var leech:Dictionary=arena.leech_runtime.snapshot();var saves:int=arena.state.successful_saves
	arena.elapsed=0.5;arena._advance_monster_burns(arena.elapsed)
	near(shield-float(enemy.shield),dps*0.5*0.75,"Burn uses half second and current fire resistance once")
	near(enemy.health,life,"Shield absorbs before health");check(arena.rng.state==rng and arena.critical_runtime.checkpoint()==critical_state and arena.leech_runtime.snapshot()==leech,"Tick adds no RNG critical roll or leech")
	check(arena.state.successful_saves==saves,"Nonlethal status tick never persists inventory")
	cast.snapshot.modifiers.append({"mode":"more","value":100.0});arena._stats.fire_increased=100.0;enemy.resistances.fire=0.5
	shield=enemy.shield;arena.elapsed=1.0;arena._advance_monster_burns(arena.elapsed)
	near(shield-float(enemy.shield),dps*0.25,"Offensive changes do not alter existing burn; defense changes do")
	near(arena.burn_statuses()[0].raw_dps,dps,"Live profile retains frozen raw DPS")
	arena.elapsed=4.0;arena._advance_monster_burns(arena.elapsed);check(arena.burn_runtime.is_empty(),"Expiry consumes only remaining duration")
	shield=enemy.shield;arena.elapsed=5.0;arena._advance_monster_burns(arena.elapsed);near(enemy.shield,shield,"Expired burn does not deal extra damage")
	# The admission point within a frame never receives the whole delta.
	clean();enemy=target();cast=meteor();arena._burn_step_active=true;arena._burn_step_start=0.0;arena.elapsed=1.0
	arena._apply_damage_packet(enemy,cast.packets.direct,cast.snapshot,Color.ORANGE,0.0,{"time":0.8,"cast_id":55})
	shield=enemy.shield;arena._advance_monster_burns(1.0);arena._burn_step_active=false
	near(shield-float(enemy.shield),float(cast.burn_profile.roles.direct.dps)*0.2*0.75,"Late event integrates only0.2 remaining seconds")
	# A successful fire hit is required, and secondary effects never inherit.
	clean();enemy=target();enemy.spawn=0.6;cast=meteor();arena._apply_damage_packet(enemy,cast.packets.direct,cast.snapshot,Color.ORANGE)
	check(arena.burn_runtime.is_empty(),"Birth-protected target cannot burn")
	enemy.spawn=0.0;var tornado:Dictionary=Compiler.compile_group("tornado",Combat.snapshot({"damage":30.0,"accuracy":100.0},["explode_on_flight_end"]),["ignite"])
	arena._apply_damage_packet(enemy,tornado.packets.secondary,tornado.snapshot,Color.ORANGE)
	check(arena.burn_runtime.is_empty(),"Secondary packet with supplied primary snapshot still cannot attach")
	# The actual ember action keeps warning geometry and shifts, not adds, raw budget.
	clean();enemy=target("ember_guard",80.0);enemy.attack_timer=0.0;enemy.damage=20.0;enemy.resistances.fire=0.0
	arena._start_enemy_telegraphs();var attack:Dictionary=arena.telegraphs.state_for(enemy.id)
	near(attack.profile.windup_seconds,0.7,"Ember windup unchanged");near(attack.profile.radius,90.0,"Ember danger radius unchanged")
	near(attack.packet.base.physical,14.0,"Physical budget unchanged");near(attack.packet.base.fire,7.0,"Half original fire is immediate")
	var enemy_burn:Dictionary=Burn.from_fire_hit(attack.packet.base.fire,attack.burn_policy)
	near(float(attack.packet.base.physical)+float(attack.packet.base.fire)+enemy_burn.raw_dps*3.0,28.0,"Combined raw budget remains1.4D")
	shield=arena.shield;arena.tick(0.7);enemy.attack_timer=1000.0
	near(shield-arena.shield,21.0,"Actual telegraph applies the reduced immediate packet")
	check(arena.burn_statuses().size()==1 and arena.burn_statuses()[0].target_kind=="player","Same runtime attaches player burn")
	shield=arena.shield;arena.tick(0.5)
	near(shield-arena.shield,enemy_burn.raw_dps*0.18,"Existing0.32hit protection clips actual interval, no deferred debt")
	near(arena.invulnerable,0.0,"Burn does not grant new hit invulnerability")
	arena._damage_enemy(enemy,1000000.0,Color.WHITE);check(arena.burn_statuses().size()==1,"Source death preserves player's already attached burn")
	shield=arena.shield;rng=arena.rng.state;arena.tick(0.5)
	near(shield-arena.shield,enemy_burn.raw_dps*0.5,"Burn continues after source death")
	check(arena.rng.state==rng,"Player burn tick has no hit presentation RNG")
	var frozen:PackedByteArray=var_to_bytes(arena.burn_runtime.statuses());arena.hud.open_panel("inventory");arena._process(0.8)
	check(var_to_bytes(arena.burn_runtime.statuses())==frozen,"Open menu freezes status time");arena.hud.close_panel()
	# Walking out during warning yields neither direct damage nor attachment.
	clean();enemy=target("ember_guard",80.0);enemy.attack_timer=0.0;arena._start_enemy_telegraphs();arena.player_pos+=Vector2(0,200);shield=arena.shield;arena.tick(0.7)
	near(arena.shield,shield,"Avoiding locked circle avoids damage");check(arena.burn_runtime.is_empty(),"Avoided telegraph cannot attach burning")
	# Every actual DOT death goes through the original root/descendant gate once.
	clean();check(arena.enter_normal_town(arena.world_context().revision).ok,"Return to normal town")
	check(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Start real map for status-only finishing blows")
	var layout:Dictionary=arena.world_geometry().landmarks
	for camp:Dictionary in layout.camps:arena.player_pos=camp.trigger_center;arena._update_map_spawning(0.0)
	var weak:Dictionary=Compiler.compile_group("meteor",Combat.snapshot({"damage":1.0},[]),["ignite"])
	var root_before:int=arena.state.normal_journey().normal_root_kills
	arena._begin_progress_transaction()
	for e:Dictionary in arena.enemies.duplicate():
		e.spawn=0.0;e.shield=0.0;e.health=3.5;e.resistances.fire=0.0
		arena._apply_damage_packet(e,weak.packets.direct,weak.snapshot,Color.ORANGE)
		check(e.health>0.0,"Initial hit leaves root for burning kill")
	arena.elapsed+=1.0;arena._advance_monster_burns(arena.elapsed)
	check(arena._map_run.snapshot().ordinary_kills==24 and arena.world_context().boss_phase=="ready","Burning roots unlock boss exactly once")
	arena.player_pos=layout.boss.trigger_center;arena._update_map_spawning(0.0)
	var loops:=0
	while arena.world_context().mode=="map" and loops<10:
		loops+=1
		for e:Dictionary in arena.enemies.duplicate():
			if e.health<=0.0:continue
			e.spawn=0.0;e.shield=0.0;e.health=3.5;e.resistances.fire=0.0
			arena._apply_damage_packet(e,weak.packets.direct,weak.snapshot,Color.ORANGE)
		arena.elapsed+=1.0;arena._advance_monster_burns(arena.elapsed);arena._check_map_complete()
	arena._end_progress_transaction()
	check(loops<10 and arena.world_context().mode=="map_complete","Burn deaths of boss and descendants finish real map")
	check(arena.state.normal_journey().normal_root_kills-root_before==25,"Only24roots plusboss earn progression")
	check(arena.state.normal_pending_rewards().pending_map_reward.shards==4 and arena.burn_runtime.is_empty(),"Completion grants once and clears all transient burning")
	var progress:Dictionary=arena.state.normal_journey();arena._check_map_complete();check(arena.state.normal_journey()==progress,"Completion cannot settle twice")
	check(arena.return_to_town(arena.world_context().revision).ok and arena.burn_runtime.is_empty(),"Return clears statuses")
	print("Ignite actual gameplay: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
