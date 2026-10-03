extends SceneTree
## Same deterministic 100-actor complete-combat fixture in baseline and candidate.
## Every simulation step enters the hash; no timings or diagnostic cache fields do.
const Arena=preload("res://scripts/main.gd")
var arena: Node2D
var serial:=0
var hashes:Array=[]
var digest:=HashingContext.new()
var output:=OS.get_environment("COMBAT_EQUIVALENCE_OUT")
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/workspace/scratch/a51485f153de/v023-profile-users/") or output.is_empty():quit(78);return
	arena=Arena.new();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false)
	for unused:int in 5:await process_frame
	arena.enemies.clear();arena.monster_runtime.reset();arena.telegraphs.reset()
	arena.projectiles.clear();arena.particles.clear();arena.rings.clear();arena.floating_text.clear()
	arena.rng.seed=230023;arena.spawn_timer=1000000;arena.invulnerable=1000000;arena.auto_fire=true
	arena.equip_tornado_example()
	while arena.hud.is_blocking():arena.hud.close_panel()
	fill();digest.start(HashingContext.HASH_SHA256)
	for frame:int in 1200:
		arena.tick(1.0/60.0)
		if arena.group_cooldown_remaining("group_000001")<=0 and arena.mana>=18:arena.cast_group("group_000001")
		if frame%300==299:
			arena._begin_progress_transaction()
			var count:=0
			for enemy:Dictionary in arena.enemies:
				if count>=20:break
				if float(enemy.health)>0:
					arena._damage_enemy(enemy,float(enemy.health)+float(enemy.shield)+1.0,Color.WHITE);count+=1
			arena._end_progress_transaction()
		fill()
		digest.update(var_to_bytes(snapshot()))
		if frame%60==59:
			hashes.append(digest.finish().hex_encode());digest.start(HashingContext.HASH_SHA256)
			await process_frame
	var result:={"ticks":1200,"per_second_complete_state_sha256":hashes,"final_state_sha256":sha(var_to_bytes(snapshot())),"rng_state":str(arena.rng.state),"kills":arena.kills,"rewards":arena.reward_kills,"shots":arena.total_shots,"damage":arena.total_damage,"event_counts":arena.event_counts,"monster_trace":arena.monster_runtime.trace,"inventory_count":arena.state.snapshot().items.size(),"next_monster_id":arena.monster_runtime.next_id,"next_projectile_id":arena.projectile_runtime.next_projectile_id}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("COMBAT_EQUIVALENCE_COMPLETE ",result.final_state_sha256," kills=",arena.kills," reward=",arena.reward_kills)
	arena.queue_free();await process_frame;quit()
func fill()->void:
	var living:=0
	for enemy:Dictionary in arena.enemies:
		if float(enemy.health)>0:living+=1
	for unused:int in range(100-living):
		var point:Vector2=arena.ARENA.position+Vector2(70+(serial%20)*(arena.ARENA.size.x-140)/19.0,50+int((serial%100)/20)*(arena.ARENA.size.y-100)/4.0)
		var species:String=["brood_host","splitter","ember_guard","crawler","skitter","brute"][serial%6]
		var enemy:Dictionary=arena.monster_runtime.create_root(species,1,point,"ordinary","",[],true)
		assert(not enemy.is_empty())
		arena._apply_source_actor_profile(enemy);enemy.spawn=0.0;arena.enemies.append(enemy);serial+=1
func snapshot()->Dictionary:
	return {"enemies":arena.enemies,"projectiles":arena.projectiles,"particles":arena.particles,"text":arena.floating_text,"pickups":arena.pickups,"rings":arena.rings,"cues":arena.visual_cues.cues,
		"rng":arena.rng.state,"build":arena.state.snapshot(),"stats":arena._stats,"position":arena.player_pos,"facing":arena.player_facing,"health":arena.health,"mana":arena.mana,"shield":arena.shield,
		"elapsed":arena.elapsed,"wave":arena.wave,"kills":arena.kills,"rewards":arena.reward_kills,"shots":arena.total_shots,"damage":arena.total_damage,"cooldowns":arena.cooldowns,"groups":arena.group_cooldowns.snapshot(),
		"combat_trace":arena.combat_trace,"damage_trace":arena.damage_trace,"incoming_trace":arena.incoming_damage_trace,"admission_trace":arena.attack_admission_trace,"events":arena.event_counts,
		"lineages":arena.monster_runtime.roots,"queue":arena.monster_runtime.queue,"monster_trace":arena.monster_runtime.trace,"next_monster":arena.monster_runtime.next_id,
		"telegraphs":arena.telegraphs._states,"next_telegraph":arena.telegraphs._next_attack_id,"telegraph_trace":arena.telegraph_trace,
		"next_projectile":arena.projectile_runtime.next_projectile_id,"next_cast":arena.projectile_runtime.next_cast_id,"sequence":arena.projectile_runtime._sequence,
		"attack_timer":arena.attack_timer,"damage_delay":arena.damage_delay,"hurt_flash":arena.hurt_flash,"entropy":arena._player_evasion_entropy}
func sha(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
