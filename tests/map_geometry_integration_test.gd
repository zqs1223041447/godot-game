extends SceneTree
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
var arena:Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func enemy(template:String,point:Vector2)->Dictionary:
	var value:Dictionary=arena._spawn_monster(template,point,"map_boss" if template=="rift_warden" else "demo","",[],false)
	value.spawn=0.0;value.attack_timer=0.0
	return value
func clear_fight()->void:
	arena.enemies.clear();arena.projectiles.clear();arena.monster_runtime.reset();arena.telegraphs.reset();arena.combat_trace.clear();arena.damage_trace.clear();arena.invulnerable=0.0;arena.health=arena._stats.max_health;arena.mana=arena._stats.max_mana;arena.alive=true
	while arena.hud.is_blocking():arena.hud.close_panel()
func cast(id:String)->bool:
	arena.mana=arena._stats.max_mana;arena.cooldowns[id]=0.0
	return arena._execute_compiled(Compiler.compile_skill(id,arena.state.get_combat_snapshot(),[]))
func drawing_matches(geometry:Dictionary)->bool:
	var drawing:Dictionary=arena.static_environment.world_geometry().duplicate(true)
	# Presentation coverage is the only permitted extra; all physics fields match.
	var covered:Variant=drawing.get("dimensional_wall_indices",[])
	if not covered is Array:return false
	var unique:Dictionary={}
	for index:Variant in covered:
		if not index is int or index<0 or index>=geometry.walls.size() or unique.has(index):return false
		unique[index]=true
	drawing.erase("dimensional_wall_indices")
	return drawing==geometry
func kill(source:Dictionary)->void:
	source.spawn=0.0
	var settled:Dictionary=Defense.incoming_hit({"physical":100000.0},{},source.shield,source.health,"monster")
	arena._apply_enemy_settlement(source,settled,Color.WHITE)
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	check(arena.world_context().mode=="town" and arena.world_geometry().walls.is_empty(),"Fresh profile starts in safe town")
	check(arena.leave_normal_town(arena.world_context().revision).ok,"Public practice entry establishes normal geometry")
	check(arena.world_geometry().id=="normal" and arena.world_geometry().walls.is_empty(),"Normal starts without terrain blockers")
	var normal_snapshot:Dictionary=arena.state.snapshot()
	check(arena.enter_town_test(arena.world_context().revision).ok,"Enter existing safe profile flow")
	check(arena.world_geometry().id=="town" and drawing_matches(arena.world_geometry()),"Town shares current geometry snapshot with retained background")
	check(arena.craft_map("broken_ruins",[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Actual device launches ruins geometry")
	var geometry:Dictionary=arena.world_geometry();var wall:Rect2=geometry.walls[0]
	check(drawing_matches(geometry) and arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS),"Static drawing and player birth use same layout")
	for source:Dictionary in arena.enemies:check(arena._geometry.is_clear(source.pos,source.radius),"Initial roots born outside walls")
	clear_fight();arena.player_pos=Vector2(wall.position.x-50,wall.get_center().y);arena.player_facing=Vector2.RIGHT
	Input.action_press("move_right");arena._move_player(0.5);Input.action_release("move_right")
	check(arena.player_pos.x<wall.position.x-arena.PLAYER_RADIUS and arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS),"Actual walking cannot cross wall")
	arena.player_pos=Vector2(wall.position.x-50,wall.get_center().y);arena.player_facing=Vector2.RIGHT
	check(cast("dash") and arena.player_pos.x<wall.position.x-arena.PLAYER_RADIUS,"Actual admitted dash clips against same footprint")
	check(arena.invulnerable==0.6,"Dash keeps its existing invulnerability consumer")
	clear_fight();arena.player_pos=Vector2(wall.position.x-18,wall.get_center().y)
	for id:String in ["cleave","nova","meteor","chain"]:
		clear_fight();arena.player_pos=Vector2(wall.position.x-18,wall.get_center().y);arena.player_facing=Vector2.RIGHT
		var hidden:=enemy("crawler",Vector2(wall.end.x+18,wall.get_center().y));var health:float=hidden.health
		check(arena._nearest_enemy(arena.player_pos).is_empty(),"Auto target cannot acquire enemy behind wall")
		check(cast(id) and hidden.health==health,"Actual "+id+" hit cannot pass through wall")
		hidden.pos=arena.player_pos+Vector2(-70,0);health=hidden.health
		check(cast(id) and hidden.health<health,"Actual "+id+" still hits a visible enemy")
	# The full projectile event consumer must respect the same blocker query.
	for id:String in ["bolt","frost","shade_bolt","tornado"]:
		clear_fight();arena.player_pos=Vector2(wall.position.x-40,wall.get_center().y);arena.player_facing=Vector2.RIGHT
		var hidden:=enemy("brute",Vector2(wall.end.x+35,wall.get_center().y));var health:float=hidden.health
		check(cast(id),"Real projectile skill admitted beside wall")
		arena._update_projectiles(0.8)
		check(hidden.health==health and int(arena.event_counts.get("terrain_hit",0))>0,"Actual "+id+" wall events reach main without hidden damage")
	clear_fight();arena.player_pos=Vector2(wall.position.x-18,wall.get_center().y)
	var source:=enemy("frost_guard",Vector2(wall.end.x+28,wall.get_center().y))
	arena._start_enemy_telegraphs()
	check(arena.telegraphs.state_for(source.id).is_empty(),"Enemy cannot start a locked attack across solid wall")
	# Start legally, then move to the other side during its unchanged warning.
	var center:=Vector2(wall.position.x-20,wall.get_center().y);source.pos=center+Vector2(-35,0);arena.player_pos=center
	arena._start_enemy_telegraphs();check(not arena.telegraphs.state_for(source.id).is_empty(),"Visible enemy warning still starts")
	arena.player_pos=Vector2(wall.end.x+16,wall.get_center().y);var health_before:float=arena.health;var shield_before:float=arena.shield
	arena._advance_enemy_telegraphs(2.0)
	check(arena.health==health_before and arena.shield==shield_before and not arena.telegraph_trace.back().applied,"Moving behind wall during warning prevents ground hit through wall")
	clear_fight();arena.player_pos=Vector2(wall.position.x-100,wall.get_center().y)
	var mover:=enemy("brute",Vector2(wall.position.x-30,wall.get_center().y));mover.knockback=Vector2(1500,0)
	arena._update_enemies(0.2)
	check(arena._geometry.is_clear(mover.pos,mover.radius) and mover.pos.x<wall.position.x,"Real knockback and separation cannot push a body through wall")
	clear_fight();arena.player_pos=Vector2(wall.end.x+100,wall.get_center().y)
	mover=enemy("brute",Vector2(wall.position.x-100,wall.get_center().y))
	var crossed_end:=false
	check(is_equal_approx(float(mover.speed),50.0),"Wave-five brute keeps its native 50-unit speed")
	# Independent authored-layout bound: 1260 high + 100 wide + two 100-unit
	# approaches, with 200 units for the unchanged body/corner clearance.
	var budget_seconds:float=(wall.size.y+wall.size.x+400.0)/50.0
	var legal_path:=true;var speed_preserved:=true;var walked:=0.0
	for step:int in range(ceili(budget_seconds*60.0)):
		var previous:Vector2=mover.pos
		arena._update_enemies(1.0/60.0)
		var distance:float=previous.distance_to(mover.pos);walked+=distance
		legal_path=legal_path and arena._geometry.is_clear(mover.pos,mover.radius) and not arena._geometry.sweep(previous,mover.pos,mover.radius).hit
		speed_preserved=speed_preserved and distance<=50.0/60.0+0.001 and is_equal_approx(float(mover.speed),50.0)
		if mover.pos.y<wall.position.y-mover.radius or mover.pos.y>wall.end.y+mover.radius:crossed_end=true
		if Vector2(mover.pos).distance_to(arena.player_pos)<60.0:break
	check(legal_path,"Every pursuit step preserves the real collision footprint")
	check(speed_preserved and walked<=budget_seconds*50.0+0.01,"Pursuit does not teleport, accelerate or enlarge its independent distance budget")
	check(crossed_end and Vector2(mover.pos).distance_to(arena.player_pos)<60.0,"Actual monster walks around the wall instead of stalling")
	clear_fight()
	for template:String in ["crawler","skitter","brute","rift_warden"]:
		var born:=enemy(template,wall.get_center())
		check(arena._geometry.is_clear(born.pos,born.radius),"Forced root birth projected legally without changing radius")
	# Restore the actual admitted roster instead of registering a synthetic corpse.
	arena.restart_run()
	var parent:Dictionary={}
	for candidate:Dictionary in arena.enemies:
		if not candidate.get("death_spawns",[]).is_empty():parent=candidate;break
	check(not parent.is_empty(),"Public restart provides a real admitted splitting root")
	if not parent.is_empty():
		parent.pos=arena._geometry.legal_point(Vector2(wall.position.x-14,wall.get_center().y),parent.radius)
		var expected_children:=0
		for request:Dictionary in parent.death_spawns:expected_children+=int(request.count)
		var reward_before:int=arena.reward_kills
		kill(parent)
		check(arena.monster_runtime.roots[parent.id].processed.has(parent.id),"Real damage settlement records the once-only root death")
		check(arena.monster_runtime.queue.size()==expected_children and expected_children>0,"Real root death reserves its full descendant count")
		check(arena.reward_kills==reward_before+1,"Eligible root rewards exactly once")
		arena._flush_monster_spawns()
		var children:Array=arena.enemies.filter(func(row:Dictionary)->bool:return row.root_id==parent.id and row.generation>0)
		check(children.size()==expected_children and not arena.enemies.has(parent),"Real death children retain reserved count and retire the settled corpse")
		for child:Dictionary in children:
			check(arena._geometry.is_clear(child.pos,child.radius) and not child.reward_eligible and child.xp_reward==0,"Every child is legal with zero descendant reward")
			kill(child)
		check(arena.reward_kills==reward_before+1,"Actual descendant settlements award no additional rewards")
		arena._finish_enemy_death(parent)
		check(arena.reward_kills==reward_before+1,"Duplicate root settlement cannot award twice")
	check(arena.return_to_town(arena.world_context().revision).ok and arena.world_geometry().walls.is_empty(),"Return clears blockers before safe town resumes")
	check(arena.leave_town_test(arena.world_context().revision).ok and arena.state.snapshot()==normal_snapshot,"Geometry/profile changes preserve original normal build")
	print("Map geometry integration: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
