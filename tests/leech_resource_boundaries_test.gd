extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const PATH=["50986","39725","63649","49806","6580","19711","20010","36704"]
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	var model:=Model.new();var candidate:=model.snapshot();candidate.progress.level=3;candidate.progress.xp=35;candidate.talents.class_id=4;candidate.talents.allocated=PATH.duplicate();candidate.talents.normal_points=0
	check(model.Rules.reason(candidate).is_empty(),"Minimum-level dual-leech build at next-level threshold is legal")
	model._accept_memory(candidate);var path:="user://leech-boundaries.json";check(model.save_build(path)==OK,"Boundary fixture saved")
	arena._replace_build(model,path);arena.restart_run();reset_combat()
	var cast:Dictionary=model.get_basic_cast()
	# A genuine root kill levels the character; mana fills and must clear now.
	var target:=enemy(100000.0,false);hit(target,cast)
	check(not arena.leech_runtime.snapshot().health.expiries.is_empty() and not arena.leech_runtime.snapshot().mana.expiries.is_empty(),"Both resources have pending recovery")
	target=enemy(1.0,true);target.xp_reward=1;hit(target,cast)
	check(model.level==4 and arena.mana==float(arena._stats.max_mana),"Actual root reward level-up fills mana")
	check(arena.leech_runtime.snapshot().mana.expiries.is_empty() and not arena.leech_runtime.snapshot().health.expiries.is_empty(),"Level-up clears full mana but keeps unfilled life")
	# Flask and ordinary regeneration feed their existing consumers first.
	reset_combat();arena.health=float(arena._stats.max_health)-0.01;target=enemy(100000.0,false);cast=model.get_basic_cast();hit(target,cast)
	check(arena.use_flask("flask_1").ok,"Existing life flask starts normally")
	arena._tick(1.0/60.0)
	check(arena.health==float(arena._stats.max_health) and arena.leech_runtime.snapshot().health.expiries.is_empty(),"Life flask reaching full clears pending leech in same tick")
	check(not arena.leech_runtime.snapshot().mana.expiries.is_empty(),"Life flask does not clear mana recovery")
	reset_combat();arena.mana=float(arena._stats.max_mana)-0.001;target=enemy(100000.0,false);hit(target,cast)
	arena._tick(1.0/60.0)
	check(arena.mana==float(arena._stats.max_mana) and arena.leech_runtime.snapshot().mana.expiries.is_empty(),"Native mana regeneration clears full ledger before spending")
	check(not arena.leech_runtime.snapshot().health.expiries.is_empty(),"Mana regeneration leaves life independent")
	# Actual atomic source changes route through the same build-change clamp as gear.
	reset_combat();target=enemy(100000.0,false);hit(target,cast)
	check(model.reset_all_passives(model.revision(),path).ok,"Actual refund transaction succeeds with ongoing instances")
	check(not arena.leech_runtime.is_empty(),"Refund does not retroactively rewrite frozen instance")
	var next:=Model.new();var smaller:float=float(next.get_stats().max_health)
	check(smaller<float(arena._stats.max_health),"Class fixture lowers health capacity")
	arena.health=smaller+0.1
	check(model.select_class(0,model.revision(),path).ok,"Actual source class change commits")
	check(arena.health==smaller and arena.leech_runtime.snapshot().health.expiries.is_empty(),"Build-change lower maximum clamps and clears life immediately")
	check(not arena.leech_runtime.snapshot().mana.expiries.is_empty(),"Build change keeps independent incomplete mana instance")
	# Recovery never goes through build persistence; only explicit transactions did.
	var saves:int=model.successful_saves;var bytes:=var_to_bytes(model.snapshot());arena._advance_leech(0.1)
	check(model.successful_saves==saves and var_to_bytes(model.snapshot())==bytes,"Frozen recovery after source refund remains runtime-only")
	print("Leech resource boundaries: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
func reset_combat()->void:
	arena.enemies.clear();arena.projectiles.clear();arena.pickups.clear();arena.leech_runtime.clear();arena.flask_runtime.clear_effects();arena.damage_trace.clear();arena.monster_runtime=arena.MonsterLifecycle.new()
	arena.alive=true;arena.health=10.0;arena.mana=0.0;arena.shield=0.0;arena.invulnerable=0.0;arena.spawn_timer=10000.0;arena.player_pos=arena.ARENA.get_center();arena._stats=arena.state.get_stats();arena._refresh_leech_caps()
func enemy(life:float,reward:bool)->Dictionary:
	var result:Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(250,0),"ordinary","",[],reward)
	result.spawn=0.0;result.health=life;result.max_health=life;result.shield=0.0;result.armour=0.0;result.evasion=0.0
	return result
func hit(target:Dictionary,cast:Dictionary)->void:
	var packet:Dictionary=arena.Damage.packet({"physical":1000.0},["hit","attack"],"resource_boundary")
	arena._apply_damage_packet(target,packet,cast.snapshot,Color.WHITE)
