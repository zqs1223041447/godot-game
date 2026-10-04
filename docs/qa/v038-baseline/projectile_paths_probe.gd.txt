extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Runtime=preload("res://scripts/combat/projectile_runtime.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Monsters=preload("res://scripts/monsters/monster_runtime.gd")
func digest(v:Variant)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(var_to_bytes(v));return h.finish().hex_encode()
func _initialize()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v038-projectile"):quit(78);return
	var model:=Model.new();var cast:Dictionary=Compiler.compile_group("bolt",model.get_combat_snapshot(),["pierce"])
	assert(cast.ok)
	var rows:Array=[]
	for layout:String in ["spread","dense"]:
		var factory:=Monsters.new();var targets:Array[Dictionary]=[]
		for i:int in range(100):
			var pos:=Vector2(80+(i%10)*100,80+int(i/10)*50) if layout=="spread" else Vector2(540+(i%10)*14,260+int(i/10)*14)
			var enemy:Dictionary=factory.create_root("crawler",1,pos,"ordinary","normal",[],false);enemy.spawn=0.0;targets.append(enemy)
		for amount:int in [30,180]:
			var records:Array=[];var expected:=""
			for repetition:int in range(20):
				var runtime:=Runtime.new();var shots:Array[Dictionary]=[]
				var spawn_t:=Time.get_ticks_usec()
				for j:int in range(amount):
					var origin:=Vector2(60+(j%10)*100,70+int(j%100/10)*50) if layout=="spread" else Vector2(530+(j%10)*13,250+int(j%100/10)*13)
					shots.append(runtime.make_projectile(origin,Vector2.RIGHT,cast.recipe,cast.packets.projectile,cast.snapshot,runtime.new_cast(),Color.WHITE))
				var spawn_us:=Time.get_ticks_usec()-spawn_t
				var tick_t:=Time.get_ticks_usec();var events:Array[Dictionary]=runtime.advance(shots,1.0/60.0,targets,Vector2(500,300),180);var tick_us:=Time.get_ticks_usec()-tick_t
				var outcome:=digest([shots,events,runtime.next_projectile_id,runtime.next_cast_id])
				if repetition==0:expected=outcome
				assert(expected==outcome)
				records.append({"spawn_us":spawn_us,"advance_us":tick_us,"contact_queries":runtime.last_contact_queries,"candidate_visits":runtime.last_candidate_visits,"full_scan_visits":runtime.last_full_scan_visits,"sorts":runtime.last_work_sorts,"sort_skips":runtime.last_work_sort_skips,"events":events.size(),"survivors":shots.size()})
			rows.append({"layout":layout,"shots":amount,"targets":100,"same_replay_hash":expected,"records":records})
	var result={"source":"f074c2614540f0842964ced961b3430871adce57","scope":"20 identical fixed one-tick repeats per spread/dense100 targets x30/180 carriers. Actual bolt+pierce compiled recipe; max180 shipping bound. Direct carrier stress fixture, not mana-funded single cast, no reward/settlement. Construction outside advance timing; same full events+carrier replay digest.","samples":rows}
	FileAccess.open("/workspace/scratch/a51485f153de/v038-diagnostics/projectile-paths.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print("Projectile diagnostic complete");quit()
