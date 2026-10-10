extends "res://tests/cleave_inward_test.gd"
## Bounded supplement: reuse the paid owned fixture and actual map entry.
var boundary_samples: Array = []
func compile_checks() -> void: pass
func sector_case(_links: Array) -> bool: return true

func movement_case() -> bool:
	if not super.movement_case() or not link(["inward_pull"]): return false
	park();arena.player_pos=arena.ARENA.position+Vector2(600,1600)
	var enemy: Dictionary=arena.enemies[0]
	prep_actor(enemy,arena.player_pos);enemy.speed=0.0;enemy.knockback=Vector2(30,40)
	arena.player_facing=Vector2.UP
	ready_cast()
	check(arena.cast_group(group_id) and arena.damage_trace.size()==1,"Coincident target remains an actual admitted cleave hit")
	vector_near(enemy.knockback,Vector2.ZERO,"Zero distance replaces previous impulse with finite zero")
	vector_near(arena.player_facing,Vector2.UP,"Coincident target preserves previous facing")
	var start: Vector2=enemy.pos
	arena._update_enemies(0.1)
	vector_near(enemy.pos,start,"No impulse motion or NaN at zero distance")
	if not link([]):return false
	arena.player_facing=Vector2.ZERO;ready_cast()
	check(arena.cast_group(group_id) and arena.damage_trace.size()==1,"Plain cleave also hits coincident body")
	vector_near(arena.player_facing,Vector2.RIGHT,"Missing previous facing uses finite right fallback")
	if not link(["inward_pull"]):return false
	prep_actor(enemy,arena.player_pos+Vector2(70,0));enemy.speed=0.0
	ready_cast();check(arena.cast_group(group_id),"First repeated-hit cast")
	arena._update_enemies(0.1)
	vector_near(enemy.knockback,Vector2(-138,0),"First hit decays before subsequent hit")
	# Deliberately reset only the cooldown to isolate repeated successful hit semantics.
	arena.group_cooldowns.reset();arena.damage_trace.clear()
	check(arena.cast_group(group_id) and arena.damage_trace.size()==1,"Second admitted cast hits once")
	vector_near(enemy.knockback,Vector2(-190,0),"Repeated hit replaces, never adds to residual impulse")
	start=enemy.pos;arena._update_enemies(0.1)
	vector_near(enemy.pos,start+Vector2(-19,0),"Replacement impulse moves original amount")
	arena.player_pos=Vector2(enemy.pos)+Vector2(25,0)
	arena.group_cooldowns.reset();check(arena.cast_group(group_id),"Third cast uses new actual origin")
	vector_near(enemy.knockback,Vector2(190,0),"Changed origin reverses residual impulse without stacking")
	for unused: int in range(12): arena._update_enemies(1.0/30.0)
	vector_near(enemy.knockback,Vector2.ZERO,"Finite decay fully removes repeated-hit impulse")
	check(enemy.pos.is_finite() and arena._geometry.is_clear(enemy.pos,enemy.radius),"Decayed target remains finite and inside map")
	return failures==0

func route_to_entry(start: Vector2, radius: float) -> bool:
	var current:=start
	var goal: Vector2=arena.world_geometry().landmarks.entry
	for unused: int in range(160):
		if current.distance_to(goal)<0.05:return true
		var direction: Vector2=arena._geometry.direction(current,goal,radius,70.0)
		var next: Vector2=arena._geometry.move(current,current+direction*70.0,radius)
		if not arena._geometry.is_clear(next,radius) or current.distance_to(next)<0.0001:return false
		current=next
	return false

func wall_case() -> bool:
	if not super.wall_case():return false
	var enemy: Dictionary=arena.enemies[0]
	var initial_ids: Array=ids()
	var ledger: Dictionary=arena._map_run.snapshot()
	var records: Array=arena.map_spawn_records()
	for wall: Rect2 in arena.world_geometry().walls:
		for normal: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			for radius: float in [10.0,28.0]:
				park()
				var edge: Vector2=wall.get_center()+normal*(wall.size.x/2.0 if normal.x!=0.0 else wall.size.y/2.0)
				arena.player_pos=edge+normal*16.0
				prep_actor(enemy,edge+normal*(radius+32.0),radius);enemy.speed=0.0
				check(arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS) and arena._geometry.is_clear(enemy.pos,radius),"Wall-face initial bodies legal")
				ready_cast();check(arena.cast_group(group_id) and arena.damage_trace.size()==1,"Wall-face real cast has exactly one hit")
				vector_near(enemy.knockback,-normal*190.0,"Wall-face impulse points toward cast origin")
				var start: Vector2=enemy.pos
				for unused: int in range(4):
					arena._update_enemies(0.1)
					check(arena._geometry.is_clear(enemy.pos,radius) and (Vector2(enemy.pos)-edge).dot(normal)>=radius-0.001,"Every step stays on original wall side with full body clear")
				check(route_to_entry(enemy.pos,radius),"Moved body retains a finite path to original entry")
				boundary_samples.append({"wall":wall,"normal":normal,"radius":radius,"start":start,"end":enemy.pos})
	# Existing boundary clamp also handles impulse overshooting the player's origin.
	for normal: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		park()
		var edge: Vector2=arena.ARENA.get_center()+normal*(arena.ARENA.size.x/2.0 if normal.x!=0.0 else arena.ARENA.size.y/2.0)
		arena.player_pos=edge-normal*16.0
		prep_actor(enemy,edge-normal*40.0);enemy.speed=0.0
		ready_cast();check(arena.cast_group(group_id),"Arena-edge actual cast")
		arena._update_enemies(0.4)
		check(arena._geometry.is_clear(enemy.pos,enemy.radius) and route_to_entry(enemy.pos,enemy.radius),"Overshoot clamp stays within map and reachable")
	check(ids()==initial_ids and arena._map_run.snapshot()==ledger and arena.map_spawn_records()==records,"Displacement preserves all actor IDs, finite objective ledger and root records")
	# Controlled settlements exercise the real completion ledger after displacement.
	var roots: int=arena.reward_kills
	for unused: int in range(8):
		arena._begin_progress_transaction()
		for target: Dictionary in arena.enemies.duplicate():
			if float(target.health)>0.0: kill(target)
		arena._end_progress_transaction()
		arena._flush_monster_spawns()
		if arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty():break
	arena._check_map_complete()
	check(arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty() and arena._map_run.complete and arena.world_context().mode=="map_complete","Map objectives remain completable after pulls; all descendants drain")
	check(arena.reward_kills-roots==records.size(),"Each original root rewards once despite repeated pulls")
	impulse_samples=boundary_samples
	return failures==0
