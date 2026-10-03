extends SceneTree
## Actual stationary-target cast geometry, not a claimed sustained-combat DPS test.
const Model=preload("res://scripts/canonical_game_state.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
var arena:Node
var records:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("OFFENSE_BUDGET_OUT")
	if output.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v024-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	var model:=Model.new();var path:="user://budget-%d.json"%Time.get_ticks_usec()
	assert(model.save_build(path)==OK)
	for index:int in 2:
		var id:String=["cleave","shade_bolt"][index]
		var uid:=model.award_gem("skill:"+id)
		assert(model.move_item(uid,{"kind":"skill_main","group_id":"group_%06d"%(index+9)},model.revision(),path).ok)
	arena.state=model;arena._stats=model.get_stats()
	for skill:String in ["cleave","shade_bolt","nova","bolt"]:
		var group:=""
		for row:Dictionary in model.snapshot().skill_groups:
			if model.skill_group(row.id).skill_id==skill:group=row.id;break
		for layout:String in ["single","distant_single","sparse","surrounded"]:
			arena.enemies.clear();arena.projectiles.clear();arena.rings.clear();arena.floating_text.clear();arena.particles.clear()
			arena.group_cooldowns.reset();arena.damage_trace.clear();arena.event_counts.clear();arena.total_damage=0.0;arena.total_shots=0
			arena.mana=arena._stats.max_mana;arena.player_facing=Vector2.RIGHT
			var points:Array[Vector2]=[]
			if layout=="single":points=[Vector2(85,0)]
			elif layout=="distant_single":points=[Vector2(400,0)]
			elif layout=="sparse":points=[Vector2(85,0),Vector2(280,0),Vector2(430,0),Vector2(330,140),Vector2(-250,0)]
			else:
				for radius:float in [70.0,130.0]:
					for step:int in 12:points.append(Vector2.RIGHT.rotated(step*TAU/12)*radius)
			for index:int in points.size():
				var enemy:=Monsters.make_enemy(index+1,"crawler",1,arena.player_pos+points[index]);enemy.health=10000.0;enemy.max_health=10000.0;enemy.spawn=0.0;enemy.armour=0.0;enemy.evasion=0.0;enemy.evasion_entropy=50.0;enemy.shield=0.0
				arena.enemies.append(enemy)
			var recipe:=model.get_group_cast(group)
			var mana_before:float=arena.mana
			assert(arena.cast_group(group))
			for frame:int in 120:arena._update_projectiles(1.0/60.0)
			var hit_targets:=0
			for enemy:Dictionary in arena.enemies:
				if float(enemy.health)<10000.0:hit_targets+=1
			records.append({"skill":skill,"layout":layout,"target_count":points.size(),"hit_targets":hit_targets,"total_actual_damage":arena.total_damage,"mana":mana_before-arena.mana,"cooldown":recipe.cooldown,"initial_projectiles":recipe.initial_count,"base_recipe":recipe.recipe,"events":arena.event_counts.duplicate(true),"retained_projectiles":arena.projectiles.size()})
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"fixture":"one actual cast per stationary arrangement; invulnerability/cooldown/resource sustainability is not inferred","player_stats":model.get_stats(),"records":records},"\t"))
	print("OFFENSE_BUDGET_COMPLETE ",records.size()," real cast/layout records")
	arena.queue_free();await process_frame;quit()
