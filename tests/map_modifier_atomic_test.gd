extends SceneTree
const Compiler=preload("res://scripts/encounters/encounter_compiler.gd")
const Admission=preload("res://scripts/encounters/encounter_admission.gd")
const MapCompiler=preload("res://scripts/world/map_compiler.gd")
const MapAdmission=preload("res://scripts/world/map_admission.gd")
const Runtime=preload("res://scripts/monsters/monster_runtime.gd")
const View=preload("res://scripts/visuals/world_view.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	for ids:Array in [["enemy_damage_115"],["enemy_attack_speed_110"],["enemy_shield_from_health_20"],["enemy_armour_80"],["enemy_damage_115","enemy_attack_speed_110"],["enemy_shield_from_health_20","enemy_armour_80"]]:
		var profile:Dictionary=Compiler.compile(ids).profile
		var runtime=Runtime.new();var before:Dictionary=Admission._snapshot(runtime)
		check(not Admission.create_root(runtime,profile,"missing",5,Vector2.ZERO,"ordinary","",[],true).ok and Admission._snapshot(runtime)==before,"Any modifier preserves full factory state on failure")
		var first:Dictionary=Admission.create_root(runtime,profile,"splitter",5,Vector2.ZERO,"ordinary","",[],true)
		check(first.ok,"Actual source admits current modifier")
		first.enemy.health=0.0;runtime.process_death(first.enemy);before=Admission._snapshot(runtime)
		check(Admission.drain(runtime,profile,0,View.WORLD_ARENA).enemies.is_empty() and Admission._snapshot(runtime)==before,"Zero capacity leaves reserved queue/identity unchanged")
		var children:Dictionary=Admission.drain(runtime,profile,1,View.WORLD_ARENA)
		check(children.ok and children.enemies.size()==1 and not children.enemies[0].reward_eligible and children.enemies[0].generation==1,"Partial capacity publishes only one once-modified rewardless child")
		before=Admission._snapshot(runtime);runtime.queue[0].template="missing";var corrupt:Dictionary=Admission._snapshot(runtime)
		check(not Admission.drain(runtime,profile,100,View.WORLD_ARENA).ok and Admission._snapshot(runtime)==corrupt,"Failed remaining child preserves whole queue, never skips bad entry")
	var damage:Dictionary=Compiler.compile(["enemy_damage_115"]).profile
	var invalid=OverflowRuntime.new();var before:Dictionary=Admission._snapshot(invalid)
	check(not Admission.create_root(invalid,damage,"crawler",5,Vector2.ZERO,"ordinary","",[],true).ok and Admission._snapshot(invalid)==before,"Damage overflow after valid creation rolls back all factory state")
	var valid=Runtime.new();var root:Dictionary=valid.create_root("splitter",5,Vector2.ZERO,"ordinary");root.health=0.0;valid.process_death(root)
	var bad_children=OverflowChildren.new();Admission._restore(bad_children,Admission._snapshot(valid));before=Admission._snapshot(bad_children)
	check(not Admission.drain(bad_children,damage,100,View.WORLD_ARENA).ok and Admission._snapshot(bad_children)==before,"Second child overflow rolls back earlier candidate and full identity queue")
	for ids:Array in [["enemy_shield_from_health_20","enemy_armour_80"],["enemy_damage_115","enemy_attack_speed_110"]]:
		var map:Dictionary=MapCompiler.compile("broken_ruins",ids,["elemental_aegis"]).profile
		var runtime=Runtime.new();var admitted:Dictionary=MapAdmission.create_root(runtime,map,"splitter",5,Vector2.ZERO,"ordinary","",[],true)
		admitted.enemy.health=0.0;runtime.process_death(admitted.enemy)
		var children:Dictionary=MapAdmission.drain(runtime,map,100,View.WORLD_ARENA)
		check(children.ok and not children.enemies.is_empty(),"Current ordinary pair and defense special share atomic child boundary")
		for child:Dictionary in children.enemies:
			check(child.encounter_source.profile.modifier_ids==map.normal_ids and child.map_defense_source.modifier_id=="elemental_aegis","Each stage records exactly one complete authoritative profile")
	print("Map modifier atomic: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

class OverflowRuntime extends Runtime:
	func create_root(template_id:String,wave:int,position:Vector2,context:String="ordinary",rarity:String="",mechanisms:Array=[],rewards:bool=true)->Dictionary:
		var enemy:Dictionary=super.create_root(template_id,wave,position,context,rarity,mechanisms,rewards)
		if not enemy.is_empty():enemy.damage=1.7e308
		return enemy
class OverflowChildren extends Runtime:
	func drain(available:int,bounds:Rect2)->Array[Dictionary]:
		var children:Array[Dictionary]=super.drain(available,bounds)
		if children.size()>1:children[1].damage=1.7e308
		return children
