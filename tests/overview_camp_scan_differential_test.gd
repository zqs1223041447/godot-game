extends "res://tests/exploration_cleanup_hint_test.gd"
## Existing finite query/lineage/settlement flows, with a frozen released scan oracle.
const OLD="res://docs/qa/overview-performance/camp_states_160e059.gd.txt"
var oracle:RefCounted
var compared:=0
var awake_cases:=0
func _initialize()->void:
	if FileAccess.get_sha256(OLD)!="6ce06741ba9e4a3bc200867d556d15bed73b0fdb14b30dda2217378f2ed9e358":quit(1);return
	var source:=FileAccess.get_file_as_string(OLD)
	source=source.replace("func _camp_states()->Array[Dictionary]:","func expected(arena)->Array[Dictionary]:")
	for name:String in ["_world_mode","_map_camps","_map_run","_map_spawn_records","enemies"]:source=source.replace(name,"arena."+name)
	var script:=GDScript.new();script.source_code="extends RefCounted\n"+source
	if script.reload()!=OK:quit(1);return
	oracle=script.new();super._initialize()
func check(value:bool,label:String)->bool:
	var result:=super.check(value,label)
	if oracle!=null and is_instance_valid(arena) and arena._ready_complete:
		var expected:Array=oracle.expected(arena)
		var actual:Array=arena.world_context().camp_states
		compared+=1
		for camp:Dictionary in expected:
			if camp.awake_count>0:awake_cases+=1;break
		super.check(var_to_bytes(actual)==var_to_bytes(expected),"Fresh camp states equal released three-pass oracle: "+label)
	return result
func formal_entry(map_id:String)->bool:
	if not super.formal_entry(map_id):return false
	# Real wake operation gives mixed awake/resident roots before original deaths.
	for index:int in range(0,arena.enemies.size(),2):arena._wake_exploration_enemy(arena.enemies[index])
	return check(true,"Existing wake operation is visible immediately")
func finish_guidance()->void:
	check(compared>30 and awake_cases>0,"Oracle covered finite lifecycle and actual awake roots")
	group_results.camp_differential={"comparisons":compared,"awake_cases":awake_cases,"oracle_sha256":FileAccess.get_sha256(OLD)}
	await super.finish_guidance()
