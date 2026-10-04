extends SceneTree
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Runtime=preload("res://scripts/combat/telegraphed_area_runtime.gd")
var arena:Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func begin(map_id:String,modifiers:Array=[])->void:
	if arena.world_context().mode in ["map","map_complete"]:arena.return_to_town(arena.world_context().revision)
	check(arena.craft_map(map_id,modifiers,[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Actual town craft/start opens "+map_id)
	arena.auto_fire=false;arena.set_process(false);arena.hud.set_process(false)
	while arena.hud.is_blocking():arena.hud.close_panel()
func kill(enemy:Dictionary)->void:
	enemy.spawn=0.0
	var settlement:=Defense.incoming_hit({"physical":100000.0},{},enemy.shield,enemy.health,"monster")
	arena._apply_enemy_settlement(enemy,settlement,Color.WHITE)
func natural_boss()->Dictionary:
	var loops:=0
	while arena._map_run.boss_id==0 and loops<40:
		loops+=1;arena.spawn_timer=0.0;arena._begin_progress_transaction();arena._update_map_spawning(0.0)
		for enemy:Dictionary in arena.enemies.duplicate():
			if enemy.id!=arena._map_run.boss_id and enemy.health>0.0:kill(enemy)
		arena._end_progress_transaction()
	check(arena.world_context().ordinary_kills==arena.world_context().ordinary_target,"Real ordinary admissions and once-only deaths reach finite target")
	for enemy:Dictionary in arena.enemies:
		if enemy.id==arena._map_run.boss_id:return enemy
	return {}
func prepare(enemy:Dictionary,boss_position:Vector2,player_position:Vector2)->void:
	arena.telegraphs.reset();arena.telegraph_trace.clear();arena.incoming_damage_trace.clear();arena.attack_admission_trace.clear()
	enemy.pos=boss_position;enemy.spawn=0.0;enemy.attack_timer=0.0;enemy.knockback=Vector2.ZERO
	arena.player_pos=player_position;arena.health=arena._stats.max_health;arena.shield=5.0;arena.invulnerable=0.0;arena._player_evasion_entropy=99.0
func start(enemy:Dictionary)->Dictionary:
	var rng_before:int=arena.rng.state;arena._start_enemy_telegraphs();var attack:Dictionary=arena.telegraphs.state_for(enemy.id)
	check(not attack.is_empty() and arena.rng.state==rng_before,"Actual start freezes map policy without consuming gameplay RNG")
	return attack
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	while arena.hud.is_blocking():arena.hud.close_panel()
	var normal:Dictionary=arena.state.snapshot();check(arena.enter_town_test(arena.world_context().revision).ok,"Real optional entry uses isolated test profile")
	var base_attacks:Dictionary={}
	for map_id:String in ["old_garden","broken_ruins"]:
		begin(map_id);var enemy:=natural_boss();check(not enemy.is_empty() and enemy.map_boss_attack_id==arena._map_run.profile.boss_attack_id,"Finite map really admits its own boss policy")
		var boss_position:=Vector2(450,350);var player_position:=boss_position+Vector2(100,0) if map_id=="old_garden" else boss_position+Vector2(0,300)
		prepare(enemy,boss_position,player_position);var attack:=start(enemy);base_attacks[map_id]=attack.duplicate(true)
		check(attack.center==(boss_position if map_id=="old_garden" else player_position) and arena.telegraph_visual_states()[0].visual_pattern==enemy.map_boss_attack_id,"Real visual snapshot uses correct fixed circle and pattern")
		var expected:=Defense.incoming_source_hit(attack.packet.base,arena._stats,arena.shield,arena.health,"player")
		arena._advance_enemy_telegraphs(attack.profile.windup_seconds-0.001);check(arena.incoming_damage_trace.is_empty(),"Actual map attack waits its full readable windup")
		arena._advance_enemy_telegraphs(0.001)
		check(arena.incoming_damage_trace.size()==1 and arena.telegraph_trace.back().applied and is_equal_approx(arena.shield,expected.remaining_shield) and is_equal_approx(arena.health,expected.remaining_health) and expected.shield_spent==5.0,"Map hit uses shared defence and shield before health")
		prepare(enemy,boss_position,player_position);attack=start(enemy);arena.player_pos=attack.center+Vector2(attack.profile.radius+arena.PLAYER_RADIUS+0.1,0)
		arena._advance_enemy_telegraphs(attack.profile.windup_seconds)
		check(arena.telegraph_trace.back().center==attack.center and not arena.telegraph_trace.back().inside and arena.incoming_damage_trace.is_empty(),"Walking out avoids fixed mark; settlement never follows player")
		prepare(enemy,boss_position,boss_position+Vector2(12,0));attack=start(enemy);var resources:Vector2=Vector2(arena.health,arena.shield);arena._update_enemies(0.05)
		check(arena.incoming_damage_trace.is_empty() and Vector2(arena.health,arena.shield)==resources and enemy.pos==boss_position,"During map action even direct body overlap cannot add contact damage or pursuit")
		prepare(enemy,boss_position,player_position);var stats:Dictionary=arena._stats.duplicate(true);arena._stats.evasion=100000.0;arena._player_evasion_entropy=0.0;attack=start(enemy)
		arena._advance_enemy_telegraphs(attack.profile.windup_seconds)
		check(arena.telegraph_trace.back().inside and not arena.telegraph_trace.back().applied and arena.incoming_damage_trace.is_empty(),"Existing attack evasion can reject an otherwise-overlapping map hit")
		arena._stats=stats
		if map_id=="broken_ruins":
			var wall:Rect2=arena.world_geometry().walls[0];var left:=Vector2(wall.position.x-15.0,wall.get_center().y);var right:=Vector2(wall.end.x+15.0,wall.get_center().y)
			prepare(enemy,Vector2(wall.position.x-90.0,wall.get_center().y),left);attack=start(enemy);arena.player_pos=right
			check(Runtime.overlaps({"shape":"circle","center":attack.center,"radius":attack.profile.radius},right,arena.PLAYER_RADIUS) and not arena._terrain_visible(attack.center,right),"Opposite-wall fixture overlaps geometrically but wall blocks circle-center sight")
			arena._advance_enemy_telegraphs(attack.profile.windup_seconds);check(not arena.telegraph_trace.back().inside and arena.incoming_damage_trace.is_empty(),"Wall between locked center and player blocks actual hit")
			prepare(enemy,Vector2(wall.end.x+40.0,wall.get_center().y),left);arena._start_enemy_telegraphs();check(arena.telegraphs.active_count()==0,"Wall between source and player prevents starting mark")
		prepare(enemy,boss_position,player_position);attack=start(enemy);var events_before:int=int(arena.event_counts.get("enemy_telegraph_resolved",0));var reward_before:int=arena.reward_kills
		arena._begin_progress_transaction();kill(enemy);arena._end_progress_transaction();arena._advance_enemy_telegraphs(5.0)
		check(arena.telegraphs.active_count()==0 and int(arena.event_counts.get("enemy_telegraph_resolved",0))==events_before and arena.reward_kills==reward_before+1,"Actual boss death cancels warning and rewards once")
		arena._flush_monster_spawns();var children:Array=arena.enemies.filter(func(row:Dictionary)->bool:return row.root_id==enemy.id and row.generation>0 and row.health>0)
		check(children.size()==4,"Actual map boss death creates the existing four children")
		arena._begin_progress_transaction()
		for child:Dictionary in children:check(not child.has("map_boss_attack_id"),"Actual child has no boss-only policy");kill(child)
		arena._end_progress_transaction();arena._flush_monster_spawns();arena._check_map_complete()
		check(arena.world_context().mode=="map_complete" and arena.reward_kills==reward_before+1,"Map completes only after descendants clear without extra rewards")
		check(arena.return_to_town(arena.world_context().revision).ok and arena.telegraphs.active_count()==0,"Real return preserves progress and removes all map actions")
		begin(map_id,["enemy_damage_115","enemy_attack_speed_110"])
		enemy=arena._spawn_monster("rift_warden",boss_position,"map_boss");prepare(enemy,boss_position,player_position);attack=start(enemy)
		var base:Dictionary=base_attacks[map_id]
		check(is_equal_approx(attack.packet.base.physical,base.packet.base.physical*1.15) and is_equal_approx(attack.profile.recovery_seconds,base.profile.recovery_seconds/1.1) and attack.profile.windup_seconds==base.profile.windup_seconds,"Actual fierce/rapid map uses modified damage/recovery while preserving full warning")
		check(arena.return_to_town(arena.world_context().revision).ok,"Player may return while a boss warning is pending")
		arena._advance_enemy_telegraphs(5.0);check(arena.telegraphs.active_count()==0 and arena.world_context().mode=="town","Pending attack cannot leak after town transition")
	check(arena.leave_town_test(arena.world_context().revision).ok and arena.state.snapshot()==normal,"Normal profile remains byte-equivalent through all test maps")
	arena.enemies.clear();arena.monster_runtime.reset();var ordinary:Dictionary=arena._spawn_monster("rift_warden",arena.player_pos+Vector2(12,0),"level_boss")
	prepare(ordinary,ordinary.pos,arena.player_pos);arena._start_enemy_telegraphs();check(not ordinary.has("map_boss_attack_id") and arena.telegraphs.active_count()==0,"Normal wave boss retains old contact role")
	arena._update_enemies(0.001);check(arena.incoming_damage_trace.size()==1,"Normal wave boss still reaches real contact settlement")
	print("Map boss gameplay: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
