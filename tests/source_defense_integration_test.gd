extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Attack=preload("res://scripts/combat/attack_hit_rules.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	check(Attack.chance(100,0)==1.0 and Attack.chance(0,100)==0.05,"zero evasion and zero accuracy limits")
	check(Attack.chance(100,1000)<Attack.chance(200,1000),"accuracy increases real hit chance")
	check(Attack.chance(100,1000)>Attack.chance(100,2000),"evasion reduces real hit chance")
	check(not Attack.resolve(NAN,10).ok and not Attack.resolve(10,10,100).ok,"invalid entropy/ratings rejected")
	for accuracy:float in [0.0,10.0,100.0,1000.0]:
		for evasion:float in [0.0,10.0,1000.0,10000.0]:
			var entropy:=50.0
			var hits:=0
			for index:int in range(1000):
				var result:=Attack.resolve(accuracy,evasion,entropy)
				check(result.ok and result.entropy>=0 and result.entropy<100,"bounded entropy")
				entropy=result.entropy
				if result.hit:hits+=1
			check(hits==int(Attack.chance(accuracy,evasion)*1000.0),"1000 attacks match exact rounded probability")
	var source_stats:={"armour":500.0,"fire_resistance":0.5,"cold_resistance":0.25,"lightning_resistance":1.0}
	var mixed:=Defense.incoming_source_hit({"physical":100.0,"fire":100.0,"cold":100.0,"lightning":100.0,"chaos":100.0},source_stats,200.0,200.0)
	check(mixed.ok and mixed.components=={"physical":50.0,"fire":50.0,"cold":75.0,"lightning":25.0,"chaos":100.0},"typed resistance/armour affect only intended components")
	check(mixed.shield_spent==200.0 and mixed.health_lost==100.0,"mitigation then shield then life")
	var big:=Defense.incoming_source_hit({"physical":1000.0},source_stats,0.0,2000.0)
	check(big.ok and is_equal_approx(big.damage_total,1000.0*10.0/11.0),"armour protection falls against bigger hit")
	check(Defense.incoming_source_hit({"physical":100.0},source_stats,200.0,200.0,"monster").components.physical==50.0,"same actual defense formula for both actors")
	var arena:Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.hud.close_panel()
	arena.enemies.clear()
	arena.projectiles.clear()
	arena.auto_fire=false
	arena.state=Model.new()
	arena._stats=arena.state.get_stats()
	var enemy:Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(30,0),"ordinary","normal",[],false)
	if enemy.is_empty():enemy=arena._spawn_monster("crawler",arena.player_pos+Vector2(30,0),"ordinary","",[],false)
	check(not enemy.is_empty(),"actual catalog target admitted")
	if enemy.is_empty():arena.queue_free();quit(1);return
	var agile:Dictionary=arena._spawn_monster("skitter",arena.player_pos+Vector2(150,100),"ordinary","",[],false)
	check(agile.get("evasion",0.0)==320.0 and agile.get("accuracy",0.0)==100.0,"natural agile template has actual authored ratings")
	check(Attack.chance(140,agile.evasion)==0.96 and Attack.chance(160,agile.evasion)==1.0,"ten dexterity improves chance against a real naturally obtainable species")
	enemy.spawn=0.0
	enemy.health=10000.0
	enemy.max_health=10000.0
	enemy.evasion=100000.0
	enemy.armour=500.0
	enemy.evasion_entropy=0.0
	var packet:=Damage.packet({"physical":100.0},["hit","attack","projectile"],"basic")
	var snapshot:Dictionary=arena.state.get_combat_snapshot()
	snapshot.modifiers=[]
	snapshot.effects=[]
	var before_rng:int=arena.rng.state
	var before_health:float=enemy.health
	arena._apply_damage_packet(enemy,packet,snapshot,Color.WHITE)
	check(enemy.health==before_health and not arena.attack_admission_trace[-1].hit,"actual attack misses evading enemy")
	check(arena.rng.state==before_rng,"accuracy gate consumes no global reward/presentation RNG")
	var spell:=Damage.packet({"physical":100.0},["hit","spell"],"nova")
	arena._apply_damage_packet(enemy,spell,snapshot,Color.WHITE)
	check(enemy.health==before_health-50.0,"spell bypasses evasion but physical still meets armour")
	# Projectile evasion is before pierce consumption; it does not repeatedly
	# retry a collider in the same flight phase or produce on-hit slow/knockback.
	enemy.evasion_entropy=0.0
	var shot:Dictionary=arena.projectile_runtime.make_projectile(arena.player_pos,Vector2.RIGHT,{"speed":100.0,"range":1000.0,"lifetime":10.0,"pierce":0},packet,snapshot,1,Color.WHITE)
	arena.projectiles.append(shot)
	arena._update_projectiles(0.5)
	check(arena.projectiles.size()==1 and shot.pierce==0 and shot.hit_ids.is_empty(),"evaded projectile survives without spending pierce")
	check(arena.event_counts.get("evaded",0)==1 and shot.hit_ledger.size()==1,"one evasion event and encounter ledger entry")
	before_health=enemy.health
	arena._update_projectiles(0.1)
	check(enemy.health==before_health and arena.event_counts.get("evaded",0)==1,"same phase cannot reroll an overlap")
	arena._stats.armour=500.0
	arena._stats.cold_resistance=0.5
	arena._stats.evasion=100000.0
	arena._player_evasion_entropy=0.0
	arena.health=200.0
	arena.shield=0.0
	arena.invulnerable=0.0
	check(not arena.hit_player_components({"physical":100.0},int(enemy.id),["hit","attack","melee"]) and arena.health==200.0,"enemy melee uses same evasion gate")
	check(arena.hit_player_components({"physical":100.0,"cold":100.0},int(enemy.id),["hit","spell"]) and arena.health==100.0,"real player settlement applies armour and cold resistance after spell admission")
	arena._stats.life_regen=10.0
	arena.invulnerable=2.0
	arena.enemies.clear()
	arena.projectiles.clear()
	arena.spawn_timer=1000.0
	arena._tick(0.1)
	check(is_equal_approx(arena.health,101.0),"life regeneration is an actual simulation consumer")
	print("Source defense integration: %d checks, %d failures"%[checks,failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
