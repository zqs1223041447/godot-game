extends SceneTree
## Verify effects are emitted only for accepted real gameplay events.
var arena: Node
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	call_deferred("run")
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: "+message)
func kinds(kind: String) -> Array:
	return arena.visual_cues.cues.filter(func(cue:Dictionary)->bool:return cue.kind==kind)
func fresh() -> void:
	arena.enemies.clear()
	arena.projectiles.clear()
	arena.rings.clear()
	arena.particles.clear()
	arena.visual_cues.reset()
	arena.hud.close_panel()
	arena.mana=float(arena.get_stats().max_mana)
	for id: String in arena.cooldowns:
		arena.cooldowns[id]=0.0
func slot(skill: String) -> void:
	fresh()
	arena.state.slot_skill(0,skill)
func target(pos: Vector2) -> Dictionary:
	var enemy: Dictionary=arena._spawn_enemy(pos,0)
	enemy.spawn=0.0
	enemy.health=10000.0
	enemy.max_health=10000.0
	enemy.shield=0.0
	return enemy
func run() -> void:
	arena=load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.demo_mode=true
	await process_frame
	slot("bolt")
	arena.mana=0
	expect(not arena.cast_skill(0) and arena.visual_cues.cues.is_empty(),"no cue for insufficient mana")
	arena.mana=100
	arena.cooldowns.bolt=1
	expect(not arena.cast_skill(0) and arena.visual_cues.cues.is_empty(),"no cue for cooldown rejection")
	arena.cooldowns.bolt=0
	arena.hud.open_panel("inventory")
	expect(not arena.cast_skill(0) and arena.visual_cues.cues.is_empty(),"no cue for modal-blocked cast")
	arena.hud.close_panel()
	expect(arena.cast_skill(0) and kinds("cast").size()==1,"one cue for an admitted volley")
	expect(kinds("cast")[0].skill=="bolt","admitted cue carries real skill identity")
	slot("tornado")
	for i: int in range(arena.MAX_PROJECTILES):
		arena.projectiles.append({})
	expect(not arena.cast_skill(0) and arena.visual_cues.cues.is_empty(),"no cue when full tornado volley cannot enter")
	arena.projectiles.clear()
	for skill: String in ["tornado","frost"]:
		slot(skill)
		expect(arena.cast_skill(0) and kinds("cast").size()==1 and kinds("cast")[0].skill==skill,"unique accepted cast "+skill)
	slot("nova")
	var enemy: Dictionary=target(arena.player_pos+Vector2(70,0))
	var before: float=enemy.health
	expect(arena.cast_skill(0) and kinds("nova").size()==1 and enemy.health<before,"nova cue accompanies real area damage")
	expect(kinds("nova")[0].radius==155.0 and not kinds("impact").is_empty(),"nova boundary and hit feedback match area")
	slot("meteor")
	enemy=target(arena.player_pos+Vector2(90,0))
	expect(arena.cast_skill(0) and kinds("meteor").size()==1,"meteor accepted cue")
	expect(kinds("meteor")[0].origin==enemy.pos and kinds("meteor")[0].radius==110.0,"meteor uses actual target and radius")
	slot("chain")
	for offset: Vector2 in [Vector2(70,0),Vector2(160,50),Vector2(200,-35)]:
		target(arena.player_pos+offset)
	expect(arena.cast_skill(0) and kinds("chain").size()==3,"one visible low-mode beam per actual chain target")
	var linked: Dictionary={}
	for cue: Dictionary in kinds("chain"):
		linked[cue.target_id]=true
		expect(cue.origin!=cue.destination,"chain path has distinct endpoints")
	expect(linked.size()==3,"chain cues preserve unique actual target identities")
	slot("dash")
	var start: Vector2=arena.player_pos
	expect(arena.cast_skill(0) and kinds("dash").size()==1,"dash accepted cue")
	expect(kinds("dash")[0].origin==start and kinds("dash")[0].destination==arena.player_pos,"dash uses actual clamped movement endpoints")
	slot("ward")
	arena.shield=0
	expect(arena.cast_skill(0) and arena.shield>0 and kinds("ward").size()==1,"ward cue matches shield restoration")
	fresh()
	arena.invulnerable=0
	arena.shield=0
	arena.hit_player(5)
	expect(kinds("hurt").size()==1 and not kinds("hurt")[0].shielded,"life damage has player hurt brackets")
	arena.hit_player(5)
	expect(kinds("hurt").size()==1,"rejected immune hit has no feedback")
	arena.invulnerable=0
	arena.shield=10
	arena.hit_player(5)
	expect(kinds("hurt").size()==2 and kinds("hurt").back().shielded,"fully shielded player hit uses alternate cue")
	fresh()
	enemy=target(Vector2(500,340))
	enemy.shield=30
	arena._damage_enemy(enemy,10,Color.CYAN)
	expect(kinds("impact").size()==1 and kinds("impact")[0].shielded,"enemy shield hit is a hex cue")
	enemy.shield=0
	arena._damage_enemy(enemy,10,Color.CYAN)
	expect(kinds("impact").size()==2 and not kinds("impact").back().shielded,"enemy life hit is a star cue")
	enemy.health=1
	arena._damage_enemy(enemy,5,Color.CYAN)
	expect(kinds("death").size()==1,"confirmed death emits one cue")
	arena._damage_enemy(enemy,5,Color.CYAN)
	expect(kinds("death").size()==1,"repeat corpse damage does not emit death again")
	slot("tornado")
	for item_id: String in ["prism_bow","return_mantle","detonation_charm"]:
		arena.state.equip(item_id)
	arena.cast_skill(0)
	for i: int in range(38):
		arena._update_projectiles(0.01)
		arena._update_effects(0.01)
	expect(kinds("split").size()==5,"five admitted parent splits emit five cues")
	for i: int in range(65):
		arena._update_projectiles(0.01)
		arena._update_effects(0.01)
	expect(kinds("return").size()==15,"fifteen actual child returns emit cues")
	for i: int in range(110):
		arena._update_projectiles(0.01)
		arena._update_effects(0.01)
	expect(kinds("explosion").size()==15,"natural-end explosions carry fifteen cues")
	for cue: Dictionary in kinds("explosion"):
		expect(cue.radius==76.0,"visual boundary uses actual explosion radius")
	var rng_state: int=arena.rng.state
	arena.visual_cues.emit_cue("meteor",Vector2.ZERO,{"radius":110})
	arena.visual_cues.advance(0.01)
	expect(arena.rng.state==rng_state,"presentation does not consume gameplay RNG")
	arena._update_effects(1.0)
	expect(arena.visual_cues.cues.is_empty(),"simulation effect tick expires cue pool")
	arena.visual_cues.emit_cue("chain",Vector2.ZERO)
	arena.restart_run()
	expect(arena.visual_cues.cues.is_empty(),"restart cancels all transient visual cues")
	print("combat_cues_integration_test: %d checks, %d failures"%[checks,failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
