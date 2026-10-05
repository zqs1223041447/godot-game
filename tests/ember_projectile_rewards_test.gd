extends SceneTree
## Focused real-main paths left after ember_gameplay_test: carriers and rewards.
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const Catalog=preload("res://scripts/monsters/monster_catalog.gd")
const Lifecycle=preload("res://scripts/monsters/monster_runtime.gd")
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func near(a:float,b:float,label:String)->void:check(absf(a-b)<0.00000001*maxf(1.0,absf(b)),label)
func clean()->void:
	arena.enemies.clear();arena.projectiles.clear();arena.monster_runtime=Lifecycle.new();arena.telegraphs.reset();arena.burn_runtime.reset();arena.burn_trace.clear();arena.damage_trace.clear();arena.combat_trace.clear();arena.event_counts.clear();arena._ember_deaths.clear()
	arena.elapsed=0.0;arena._burn_step_active=false;arena.alive=true;arena.auto_fire=false;arena.demo_mode=false;arena.spawn_timer=1000.0;arena.reward_kills=0;arena.kills=0
	arena._world_mode="normal";arena._geometry.configure("old_garden",arena.ARENA);arena.player_pos=arena.ARENA.get_center();arena.player_facing=Vector2.RIGHT;arena.hud.close_panel();arena.health=10.0;arena.mana=1000.0;arena._stats=arena.state.get_stats()
	for id:String in arena.Data.SKILLS:arena.cooldowns[id]=0.0
func prepare(e:Dictionary)->void:
	e.spawn=0.0;e.health=10000.0;e.max_health=10000.0;e.shield=0.0;e.max_shield=0.0;e.resistances.fire=0.0;e.armour=0.0;e.evasion=0.0;e.speed=0.0;e.attack_timer=1000.0;e.shield_regen=0.0;e.shield_recharge_rate=0.0
func target(offset:Vector2,template:String="brute",rewards:bool=false)->Dictionary:
	var e:Dictionary=arena._spawn_monster(template,arena.player_pos+offset,"ordinary","",[],rewards)
	prepare(e);e.radius=8.0
	return e
func status(e:Dictionary)->Dictionary:return arena.burn_runtime.status_for("monster",int(e.id))
func projectile_step(delta:float)->void:
	arena._burn_step_active=true;arena._burn_step_start=arena.elapsed;arena.elapsed+=delta
	arena._update_projectiles(delta);arena._advance_monster_burns(arena.elapsed);arena._burn_step_active=false
func hits_for(e:Dictionary,role:String)->Array:
	return arena.combat_trace.filter(func(event:Dictionary)->bool:return event.type=="hit" and event.target_id==e.id and event.role==role)
func check_origin(e:Dictionary,role:String,dps:float)->void:
	var s:=status(e);var hits:=hits_for(e,role)
	check(not s.is_empty() and not hits.is_empty(),"Actual %s contact attached a burn"%role)
	if s.is_empty() or hits.is_empty():return
	var hit:Dictionary=hits.back()
	check(s.provenance.ember_generation==0,"Actual %s hit seeds ember generation zero"%role)
	check(s.provenance.projectile_id==hit.projectile_id and s.provenance.cast_id==hit.cast_id and s.provenance.phase==hit.phase,"Burn keeps actual %s hit carrier attribution"%role)
	near(s.raw_dps,dps,"Actual %s burn uses its own frozen fire amount"%role)
	near(s.provenance.ember_expiry,hit.time+3.0+(0.25 if role=="child" else 0.0),"Actual %s hit timestamp owns original three-second deadline"%role)
func test_projectiles()->void:
	clean()
	var parent:=target(Vector2(80,0));var child:=target(Vector2(260,0))
	var blast_survivor:=target(Vector2(370,35));var blast_corpse:=target(Vector2(370,0));blast_corpse.health=45.0
	var neighbor:=target(Vector2(460,0))
	var cast:Dictionary=Compiler.compile_group("tornado",Combat.snapshot({"damage":100.0,"crit_base_chance":0.0},["explode_on_flight_end"]),["ember_proliferation"])
	var mana:float=arena.mana
	check(arena._execute_compiled(cast),"Real main accepts ember tornado with flight-end explosions")
	near(mana-arena.mana,cast.mana,"Real tornado pays compiled mana exactly once")
	check(arena.projectiles.size()==3,"Actual cast emits the unchanged three parent carriers")
	for shot:Dictionary in arena.projectiles:
		check(shot.snapshot.has("burn_policy") and shot.snapshot.has("burn_proliferation") and shot.role=="parent","Emitted parent contains ember policy")
	projectile_step(0.25)
	check_origin(parent,"parent",float(cast.burn_profile.roles.parent.dps))
	check(status(child).is_empty(),"Beyond-parent-range target waits for an actual child")
	projectile_step(0.55)
	check(int(arena.event_counts.get("split",0))==3 and arena.projectiles.size()==9,"Actual range boundaries replace parents with nine children")
	for shot:Dictionary in arena.projectiles:
		check(shot.generation==1 and shot.parent_id>0 and shot.snapshot.has("burn_policy") and shot.snapshot.has("burn_proliferation"),"Actual child carrier inherits ember policy and projectile lineage")
	check_origin(child,"child",float(cast.burn_profile.roles.child.dps))
	check(status(blast_survivor).is_empty() and status(blast_corpse).is_empty(),"Off-path explosion targets have no primary burn")
	projectile_step(0.2)
	check(arena.projectiles.is_empty() and int(arena.event_counts.get("explosion",0))==9,"Nine natural child endings dispatch nine independent explosions")
	var secondary_hits:=0
	for damage:Dictionary in arena.damage_trace:
		if damage.target_id not in [blast_survivor.id,blast_corpse.id]:continue
		check(damage.tags.has("secondary") and not damage.effect_id.is_empty(),"Off-path target was hit by actual independent secondary event")
		near(damage.before_defense_components.fire,90.0,"Secondary keeps unpenalized independent fire budget")
		secondary_hits+=1
	check(secondary_hits>=2 and blast_survivor.health<10000.0 and blast_corpse.health<=0.0,"Actual secondary events both damage a survivor and kill an off-path target")
	check(status(blast_survivor).is_empty() and status(blast_corpse).is_empty(),"Secondary fire never attaches ember burning")
	check(status(neighbor).is_empty() and neighbor.health==10000.0,"Actual secondary kill cannot spread to a nearby untouched target")
	print("EMBER_PROJECTILE_PATH_COMPLETE")
func burn_finish(enemies:Array)->void:
	var cast:Dictionary=Compiler.compile_group("meteor",Combat.snapshot({"damage":1.0,"crit_base_chance":0.0},[]),["ember_proliferation"])
	for e:Dictionary in enemies:
		prepare(e)
		arena._apply_damage_packet(e,cast.packets.direct,cast.snapshot,Color.ORANGE)
		var s:=status(e)
		check(e.health>0.0 and not s.is_empty(),"Real primary leaves a live root or descendant carrying new ember burn")
		if s.is_empty():return
		e.health=float(s.raw_dps)*0.25
	arena._begin_progress_transaction();arena.elapsed+=0.25;arena._advance_monster_burns(arena.elapsed);arena._end_progress_transaction()
	for e:Dictionary in enemies:
		check(e.health<=0.0 and e.death_processed,"Ember DOT routes actual death through existing once-only gate")
func test_rewards()->void:
	clean()
	check(not arena._is_test_profile(),"Reward test uses isolated real normal profile")
	arena.mana=0.0
	check(arena.use_flask("flask_1").ok and arena.use_flask("flask_2").ok,"Real flask use creates headroom in both equipped bottles")
	var charges:Dictionary=arena.flask_runtime.snapshot().charges_by_uid
	var parent:=target(Vector2(80,0),"splitter",true)
	var copied_corpse:Dictionary=parent.duplicate(true);copied_corpse.health=0.0
	var xp:int=arena.state.xp;var roots:int=arena.state.normal_journey().normal_root_kills
	burn_finish([parent])
	check(arena.kills==1 and arena.reward_kills==1,"Only the real splitter root advances reward kills")
	check(arena.state.xp==xp+int(parent.xp_reward) and arena.state.normal_journey().normal_root_kills==roots+1,"Real ember root awards configured XP and one normal root kill")
	var after_flasks:Dictionary=arena.flask_runtime.snapshot()
	for uid:String in charges:check(after_flasks.charges_by_uid[uid]==int(charges[uid])+1,"One ember root grants one charge per equipped flask")
	check(arena.enemies.size()==3 and arena.monster_runtime.queue.is_empty() and arena.monster_runtime.roots[parent.id].reserved==3,"Actual splitter DOT death drains exact original three-child group")
	var after:Dictionary=arena.state.snapshot();var saves:int=arena.state.successful_saves
	arena._finish_enemy_death(parent);arena._finish_enemy_death(copied_corpse)
	check(arena.kills==1 and arena.reward_kills==1 and arena.state.snapshot()==after and arena.flask_runtime.snapshot()==after_flasks,"Original and copied corpse identities cannot replay progression or charges")
	var descendants:Array=arena.enemies.duplicate()
	for e:Dictionary in descendants:
		check(not e.reward_eligible and e.xp_reward==0 and e.root_id==parent.id and e.generation==1 and e.spawn>0.0,"Real descendants retain rewardless lineage and birth protection")
	burn_finish(descendants)
	for e:Dictionary in descendants:arena._finish_enemy_death(e)
	check(arena.kills==4 and arena.reward_kills==1 and arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty(),"Three DOT descendants terminate once without replaying children")
	check(arena.state.snapshot()==after and arena.state.successful_saves==saves and arena.flask_runtime.snapshot()==after_flasks,"Descendant and duplicate deaths change no XP, normal roots, charges or saves")
	print("EMBER_ROOT_REWARDS_COMPLETE")
func test_lineage_budget()->void:
	clean()
	# Valid, acyclic fixture exercises the unchanged six-per-death/twelve-per-root
	# admission through actual DOT deaths; no production constants are changed.
	var templates:Dictionary=Catalog.TEMPLATES.duplicate(true)
	templates.brood_host.death_spawns=[{"template":"splitter","count":6}]
	check(Catalog.validate_templates(templates).is_empty(),"Six-splitter boundary fixture passes actual content validation")
	arena.monster_runtime=Lifecycle.new(templates)
	var parent:=target(Vector2(80,0),"brood_host",true)
	burn_finish([parent])
	check(arena.enemies.size()==6 and arena.monster_runtime.roots[parent.id].reserved==6,"Actual root DOT death admits exactly six children")
	var after:Dictionary=arena.state.snapshot();var charges:Dictionary=arena.flask_runtime.snapshot();var saves:int=arena.state.successful_saves
	var branches:Array=arena.enemies.duplicate()
	burn_finish(branches)
	var rejected:=0
	for event:Dictionary in arena.monster_runtime.trace:
		if event.type=="rejected" and event.reason=="lineage_budget":rejected+=1
	check(rejected==4 and arena.enemies.size()==6 and arena.monster_runtime.roots[parent.id].reserved==12,"DOT siblings preserve twelve-descendant cap: two complete groups admitted, four refused")
	for e:Dictionary in arena.enemies:check(e.generation==2 and not e.reward_eligible,"Budget-admitted grandchildren keep real rewardless lineage")
	burn_finish(arena.enemies.duplicate())
	check(arena.kills==13 and arena.reward_kills==1 and arena.monster_runtime.roots.is_empty() and arena.monster_runtime.queue.is_empty(),"Bounded DOT lineage terminates at original root plus twelve descendants")
	check(arena.state.snapshot()==after and arena.state.successful_saves==saves and arena.flask_runtime.snapshot()==charges,"Budget-admitted or refused descendant branches cannot mint rewards")
	print("EMBER_LINEAGE_BUDGET_COMPLETE")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v047-extra/"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	check(arena.save_build(),"Fresh isolated normal schema29 profile saves")
	test_projectiles();test_rewards();test_lineage_budget()
	print("EMBER_PROJECTILE_REWARDS_COMPLETE checks=%d failures=%d"%[checks,failures])
	arena.queue_free();await process_frame;quit(1 if failures else 0)
