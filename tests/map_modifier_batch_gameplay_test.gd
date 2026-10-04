extends SceneTree
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Encounter=preload("res://scripts/encounters/encounter_admission.gd")
var arena:Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func begin(ids:Array,special:Array=[])->void:
	if arena.world_context().mode=="map":arena.return_to_town(arena.world_context().revision)
	check(arena.craft_map("old_garden",ids,special,arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Real map config accepted")
	arena.enemies.clear();arena.monster_runtime.reset();arena.projectiles.clear();arena.damage_trace.clear();arena.incoming_damage_trace.clear();arena.telegraphs.reset();arena.telegraph_trace.clear()
	arena.invulnerable=0.0;arena.health=arena._stats.max_health;arena.shield=arena._stats.max_shield;arena._player_evasion_entropy=50.0;arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
func make(template:String,offset:Vector2)->Dictionary:
	var actor:Dictionary=arena._spawn_monster(template,arena.player_pos+offset,"ordinary","",[],false)
	actor.spawn=0.0;actor.attack_timer=0.0
	return actor
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	check(arena.enter_town_test(arena.world_context().revision).ok,"Enter isolated test profile")
	var original:Dictionary=arena.state.snapshot()
	# Actual contact consumes modified damage and rate; compare raw incoming
	# components because the player's armour is intentionally hit-size dependent.
	var contact:Array=[]
	for ids:Array in [[],["enemy_damage_115","enemy_attack_speed_110"]]:
		begin(ids);var enemy:=make("crawler",Vector2(12,0));arena._update_enemies(0.001)
		check(arena.incoming_damage_trace.size()==1,"Real contact attack reaches shared defense exactly once")
		contact.append({"amount":arena.incoming_damage_trace.back().raw_components.physical,"timer":enemy.attack_timer})
	check(is_equal_approx(contact[1].amount,contact[0].amount*1.15),"Fierce affects actual contact raw damage by15percent")
	check(is_equal_approx(contact[1].timer,contact[0].timer/1.1),"Rapid affects actual contact interval by inverse1.1")
	# Three real warning attacks: windup unchanged, recovery faster, raw packet15%.
	for template:String in ["ember_guard","frost_guard","storm_skitter"]:
		var records:Array=[]
		for ids:Array in [[],["enemy_damage_115","enemy_attack_speed_110"]]:
			begin(ids);var enemy:=make(template,Vector2(60,0));arena._start_enemy_telegraphs()
			var attack:Dictionary=arena.telegraphs.state_for(enemy.id)
			check(not attack.is_empty(),"Real warning admitted for "+template)
			records.append(attack.duplicate(true))
			arena._advance_enemy_telegraphs(float(attack.profile.windup_seconds)-0.001)
			check(arena.incoming_damage_trace.is_empty(),"Faster attack rate cannot resolve before full warning")
			arena._advance_enemy_telegraphs(0.001)
			check(arena.incoming_damage_trace.size()==1 and arena.telegraph_trace.back().applied,"Real unchanged warning deadline resolves through player defense")
		check(records[0].profile.windup_seconds==records[1].profile.windup_seconds,"Warning readable duration remains exact")
		check(is_equal_approx(records[1].profile.recovery_seconds,records[0].profile.recovery_seconds/1.1),"Only warning recovery speeds up")
		for type:String in records[0].packet.base:check(is_equal_approx(records[1].packet.base[type],records[0].packet.base[type]*1.15),"Each source telegraph component increases15percent")
	# Shield baseline must not include Strong's multiplier, including descendants.
	begin(["enemy_max_health_120","enemy_shield_from_health_20"])
	var guarded:=make("crawler",Vector2(70,0));var base:Dictionary=Monsters.make_enemy(1,"crawler",arena.wave,Vector2.ZERO,"ordinary")
	var expected:float=base.max_health*0.2
	check(is_equal_approx(guarded.max_health,base.max_health*1.2) and is_equal_approx(guarded.max_shield,expected) and is_equal_approx(guarded.shield,expected),"Actual spawned shield uses pre-Strong life")
	var hp:float=guarded.health
	arena._apply_damage_packet(guarded,Damage.packet({"chaos":expected+5.0},["hit"],"shield_test"),{"modifiers":[]},Color.WHITE,0.0)
	check(guarded.shield==0.0 and is_equal_approx(hp-guarded.health,5.0),"Real shield consumes chaos before health; no invented chaos bypass")
	var parent:=make("splitter",Vector2(60,30));parent.health=0.0;var death:Dictionary=arena.monster_runtime.process_death(parent);arena._flush_monster_spawns()
	var children:=0
	for child:Dictionary in arena.enemies:
		if child.generation==0:continue
		children+=1;var canonical:Dictionary=Monsters.make_enemy(1,child.template_id,arena.wave,Vector2.ZERO,"death_child")
		check(is_equal_approx(child.max_shield,canonical.max_shield+canonical.max_health*0.2) and is_equal_approx(child.max_health,canonical.max_health*1.2),"Each child applies fixed health/shield rules once from its own base")
		check(not child.reward_eligible and child.xp_reward==0,"Buffed descendant still gives zero root reward")
	check(children==death.queued,"All reserved descendants arrive")
	# Armour + aegis demonstrates physical hit-size behavior and typed separation.
	begin(["enemy_armour_80"],["elemental_aegis"])
	var enemy:=make("ember_guard",Vector2(70,0));enemy.max_health=10000.0;enemy.health=10000.0
	check(enemy.armour==80.0 and is_equal_approx(enemy.resistances.fire,0.45),"Ordinary armour composes with shared elemental special")
	for amount:float in [10.0,100.0]:
		arena.damage_trace.clear();var packet:Dictionary=Damage.packet({"physical":amount,"fire":amount,"chaos":amount},["hit"],"armour_test")
		arena._apply_damage_packet(enemy,packet,{"modifiers":[]},Color.WHITE,0.0)
		var actual:Dictionary=arena.damage_trace.back();var expected_physical:float=amount*(1.0-minf(0.9,80.0/(80.0+5.0*amount)))
		check(is_equal_approx(actual.components.physical,expected_physical),"Actual armour depends on physical hit size")
		check(is_equal_approx(actual.components.fire,amount*0.55) and actual.components.chaos==amount,"Armour does not reduce fire or chaos; fire still uses actual45percent")
	# Combining shield and armour admits through ordinary and map defense stages.
	begin(["enemy_armour_80","enemy_shield_from_health_20"],["elemental_aegis"])
	enemy=make("brute",Vector2(70,0));check(enemy.armour==80 and enemy.max_shield>0 and enemy.resistances.cold==0.2,"Both ordinary defense fields and special reach a real actor")
	var random_before:int=arena.rng.state;var identity_before:Dictionary=Encounter._snapshot(arena.monster_runtime)
	var draft:Dictionary=arena.map_draft()
	check(not arena.craft_map("old_garden",["enemy_damage_115","enemy_attack_speed_110","enemy_armour_80"],[],draft.revision).ok and arena.rng.state==random_before and Encounter._snapshot(arena.monster_runtime)==identity_before,"Third ordinary clause cannot mutate active map or consume identity/RNG")
	check(arena.return_to_town(arena.world_context().revision).ok and arena.state.snapshot()==original,"All challenges remain run-only and leave persistent build untouched")
	print("Map modifier gameplay: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
