extends SceneTree
const Maps=preload("res://scripts/world/map_compiler.gd")
const Admission=preload("res://scripts/world/map_admission.gd")
const Runtime=preload("res://scripts/monsters/monster_runtime.gd")
const Encounter=preload("res://scripts/encounters/encounter_admission.gd")
const View=preload("res://scripts/visuals/world_view.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	for ordinary:Array in [[],["enemy_max_health_120"],["enemy_move_speed_110"],["enemy_max_health_120","enemy_move_speed_110"]]:
		var profile:Dictionary=Maps.compile("broken_ruins",ordinary,["elemental_aegis"]).profile
		var runtime=Runtime.new()
		var root:Dictionary=Admission.create_root(runtime,profile,"splitter",5,View.WORLD_ARENA.get_center(),"ordinary","",[],true)
		check(root.ok and root.enemy.map_defense_source.modifier_id=="elemental_aegis","Root admits defense together with ordinary modifiers")
		check(root.enemy.reward_eligible and root.enemy.generation==0,"Root reward and generation unchanged")
		root.enemy.health=0.0;var death:Dictionary=runtime.process_death(root.enemy)
		var children:Dictionary=Admission.drain(runtime,profile,100,View.WORLD_ARENA)
		check(children.ok and children.enemies.size()==death.queued,"All reserved descendants admitted transactionally")
		for child:Dictionary in children.enemies:
			check(child.resistances=={"fire":0.2,"cold":0.2,"lightning":0.2},"Child starts from its own base and receives20 once, not inherited40")
			check(not child.reward_eligible and child.xp_reward==0 and child.root_id==root.enemy.root_id,"Descendant remains zero-reward and same lineage")
		var before:Dictionary=Encounter._snapshot(runtime)
		check(not Admission.create_root(runtime,{},"crawler",5,Vector2.ZERO,"ordinary","",[],true).ok and Encounter._snapshot(runtime)==before,"Invalid profile rejected before identity changes")
		check(not Admission.create_root(runtime,profile,"missing",5,Vector2.ZERO,"ordinary","",[],true).ok and Encounter._snapshot(runtime)==before,"Factory failure restores full identity/lineage state")
		# Valid factory fields but inconsistent resistance simulates a dependency failure.
		var corrupt:=BadDefenseRuntime.new();var corrupt_before:Dictionary=Encounter._snapshot(corrupt)
		check(not Admission.create_root(corrupt,profile,"crawler",5,Vector2.ZERO,"ordinary","",[],true).ok and Encounter._snapshot(corrupt)==corrupt_before,"Post-factory defense rejection rolls back the root atomically")
		var queued=Runtime.new();var boss:Dictionary=queued.create_root("splitter",5,Vector2.ZERO,"ordinary");boss.health=0.0;queued.process_death(boss)
		queued.queue[0].template="missing";before=Encounter._snapshot(queued)
		check(not Admission.drain(queued,profile,100,View.WORLD_ARENA).ok and Encounter._snapshot(queued)==before,"Partial descendant factory failure restores complete queued batch")
		var bad_children:=BadChildDefenseRuntime.new();boss=bad_children.create_root("splitter",5,Vector2.ZERO,"ordinary");boss.health=0.0;bad_children.process_death(boss);before=Encounter._snapshot(bad_children)
		check(not Admission.drain(bad_children,profile,100,View.WORLD_ARENA).ok and Encounter._snapshot(bad_children)==before,"Late child defense rejection restores entire batch including prior valid child")
	print("Map aegis admission: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

class BadDefenseRuntime extends Runtime:
	func create_root(template_id:String,wave:int,position:Vector2,context:String="ordinary",rarity:String="",mechanisms:Array=[],rewards:bool=true)->Dictionary:
		var enemy:Dictionary=super.create_root(template_id,wave,position,context,rarity,mechanisms,rewards)
		if not enemy.is_empty():enemy.resistances.fire=0.99
		return enemy

class BadChildDefenseRuntime extends Runtime:
	func drain(available:int,bounds:Rect2)->Array[Dictionary]:
		var children:Array[Dictionary]=super.drain(available,bounds)
		if children.size()>1:children[1].resistances.fire=0.99
		return children
