extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
const Registry=preload("res://scripts/mechanics/mechanic_registry.gd")
const Sheet=preload("res://scripts/ui/canonical_character_panel.gd")
const RATE_PATH=["58833","2151","37690","48423","6204","63976","33479","10490","22473","3452"]
const DELAY_PATH=["58833","2151","37690","48423","6204","63976","33479","10490","47251","7388","60398","46340","34478","5591","23690"]
var arena:Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	for nodes:Array in [RATE_PATH,DELAY_PATH]:player_scenario(nodes)
	enemy_scenario()
	print("Source recharge gameplay: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
func player_scenario(nodes:Array)->void:
	var model:=Model.new();var setup:=model.snapshot();setup.progress.level=119;setup.progress.xp=0;setup.talents.allocated=nodes.slice(0,-1);setup.talents.normal_points=123-(setup.talents.allocated.size()-1)
	check(model.Rules.reason(setup).is_empty(),"High-level test-only connected prefix validates")
	model._accept_memory(setup);var path:="user://recharge-"+str(nodes.back())+".json";check(model.save_build(path)==OK,"Prefix saved before real allocation")
	var before:=model.get_stats();check(model.allocate_passive(nodes.back(),0,model.revision(),path).ok,"Actual allocation spends one point on a full recharge node")
	var stats:=model.get_stats();var profile:=Defense.recharge_profile(stats)
	check(stats.shield_recharge_rate==profile.rate and stats.shield_recharge_delay==profile.delay and stats.shield_regen==before.shield_regen,"Current derived values share the calculator and retain flat baseline")
	check(stats.shield_recharge_rate>before.shield_recharge_rate,"Source rate grant affects actual derived recovery")
	if nodes==DELAY_PATH:check(stats.shield_recharge_delay<before.shield_recharge_delay,"Source faster-start grant reduces real next-hit wait")
	var panel:=Sheet.new();panel.setup(model)
	check(panel.find_child("Value_shield_recharge_rate",true,false).text=="%.2f"%stats.shield_recharge_rate and panel.find_child("Value_shield_recharge_delay",true,false).text=="%.2f"%stats.shield_recharge_delay,"Root C sheet renders actual model values")
	panel.free()
	if arena.state.changed.is_connected(arena._on_build_changed):arena.state.changed.disconnect(arena._on_build_changed)
	arena.state=model;arena.build_save_path=path;model.changed.connect(arena._on_build_changed);arena._stats=stats
	arena.enemies.clear();arena.projectiles.clear();arena.monster_runtime.reset();arena.spawn_timer=10000.0;arena.boss_wave_pending=0;arena.alive=true;arena.elapsed=0.0;arena.wave=1
	arena.health=stats.max_health;arena.mana=stats.max_mana;arena.shield=stats.max_shield;arena.invulnerable=0.0;arena.damage_delay=0.0
	check(arena.hit_player_components({"physical":10.0}) and arena.health==stats.max_health and arena.damage_delay==profile.delay,"Real shield-only effective hit starts configured delay")
	var after_hit:float=arena.shield;var delay:float=arena.damage_delay
	arena.invulnerable=0.0;check(not arena.hit_player_components({"physical":0.0}) and arena.damage_delay==delay and arena.shield==after_hit,"Zero damage cannot restart recharge")
	arena._stats.evasion=1e9;arena._player_evasion_entropy=0.0
	check(not arena.hit_player_components({"physical":10.0},0,["attack"]) and arena.damage_delay==delay and arena.shield==after_hit,"Evaded attack cannot restart recharge")
	arena._stats=stats;arena._tick(delay*0.5)
	check(is_equal_approx(arena.damage_delay,delay*0.5) and arena.shield==after_hit,"No early recovery inside waiting interval")
	var waiting:float=arena.damage_delay
	check(model.refund_passive(nodes.back(),model.revision(),path).ok,"Actual refund updates derived rate via model signal")
	check(arena.damage_delay==waiting and arena._stats.shield_recharge_rate==before.shield_recharge_rate,"Ongoing wait stays fixed while future rate updates immediately")
	var after_refund:float=arena.shield
	arena._tick(waiting+0.2)
	check(arena.damage_delay==0.0 and is_equal_approx(arena.shield,minf(arena._stats.max_shield,after_refund+before.shield_recharge_rate*0.2)),"Crossing wait threshold only restores the remaining delta")
	arena.invulnerable=0.0
	check(arena.hit_player_components({"physical":1.0}) and arena.damage_delay==before.shield_recharge_delay,"Subsequent effective hit uses changed delay configuration")
	# Same total time split at the threshold gives the same real shield result.
	arena.shield=0.0;arena.damage_delay=before.shield_recharge_delay;arena._tick(before.shield_recharge_delay+0.25);var whole:float=arena.shield
	arena.shield=0.0;arena.damage_delay=before.shield_recharge_delay;arena._tick(before.shield_recharge_delay-0.1);arena._tick(0.35)
	check(is_equal_approx(arena.shield,whole),"Subdivided main ticks match one-step recharge gain")
	arena.shield=arena._stats.max_shield-0.1;arena.damage_delay=0.0;arena._tick(1.0)
	check(arena.shield==arena._stats.max_shield,"Recovery clamps to actual shield maximum")
	arena.shield=0.0;arena.damage_delay=2.0;arena.mana=arena._stats.max_mana;arena.cooldowns.ward=0.0
	check(arena._execute_compiled(model.get_skill_cast("ward")) and arena.damage_delay==0.0 and is_equal_approx(arena.shield,arena._stats.max_shield*0.75),"Ward retains independent immediate75percent restoration and wait reset")
	var loaded:=Model.new();check(loaded.load_build(path) and loaded.snapshot()==model.snapshot() and loaded.get_stats()==model.get_stats(),"Runtime timers never become new persistent fields")
func enemy_scenario()->void:
	# An isolated content bundle exercises the real shared registry and monster
	# factory. No new natural monster mechanic or shipped values are introduced.
	var original:Dictionary=Registry._definitions["aegis_recovery"].duplicate(true);var original_revision:int=Registry._revision
	Registry._definitions["aegis_recovery"].stats["shield_recharge_rate_increased"]=0.5
	Registry._definitions["aegis_recovery"].stats["shield_recharge_start_faster"]=0.5;Registry._revision+=1
	check(Registry.is_supported("aegis_recovery","player") and Registry.is_supported("aegis_recovery","monster"),"Both actors admit the same complete recharge bundle")
	arena.enemies.clear();arena.telegraphs.reset();arena.monster_runtime.reset();arena.alive=true;arena.player_pos=arena.ARENA.get_center()
	var enemy:Dictionary=arena._spawn_monster("brute",arena.ARENA.position+Vector2(80,80),"ordinary","magic",["aegis_recovery"],false)
	check(not enemy.is_empty(),"Real monster admission consumes shared complete bundle")
	if enemy.is_empty():Registry._definitions["aegis_recovery"]=original;Registry._revision=original_revision;return
	var profile:=Defense.recharge_profile(enemy.mechanism_stats,"monster")
	check(enemy.shield_recharge_rate==profile.rate and enemy.shield_recharge_delay==profile.delay,"Factory stores shared final rate/delay without a second interpretation")
	enemy.spawn=0.0;enemy.speed=0.0;enemy.attack_timer=100.0;enemy.evasion=0.0
	var health:float=enemy.health
	arena._apply_damage_packet(enemy,Damage.packet({"physical":1.0},["hit","spell"],"recharge_probe"),arena.state.get_combat_snapshot(),Color.WHITE,0.0)
	check(enemy.health==health and enemy.damage_delay==profile.delay,"Real enemy shield hit starts configured wait")
	var shield:float=enemy.shield;arena._update_enemies(profile.delay-0.1)
	check(enemy.shield==shield and is_equal_approx(enemy.damage_delay,0.1),"Enemy waits for the full threshold")
	var before:float=enemy.damage_delay
	arena._apply_damage_packet(enemy,Damage.packet({"physical":0.0},["hit","spell"],"zero"),arena.state.get_combat_snapshot(),Color.WHITE,0.0)
	check(enemy.damage_delay==before,"Enemy zero damage does not reset wait")
	enemy.evasion=1e9;enemy.evasion_entropy=0.0
	arena._apply_damage_packet(enemy,Damage.packet({"physical":1.0},["hit","attack"],"miss"),arena.state.get_combat_snapshot(),Color.WHITE,0.0)
	check(enemy.damage_delay==before and enemy.shield==shield,"Enemy evade preserves wait and resource")
	arena._update_enemies(0.2)
	check(enemy.damage_delay==0.0 and is_equal_approx(enemy.shield,minf(enemy.max_shield,shield+profile.rate*0.1)),"Enemy also uses only post-threshold delta")
	Registry._definitions["aegis_recovery"]=original;Registry._revision=original_revision
