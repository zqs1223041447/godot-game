class_name MapRunState
extends RefCounted
const Compiler=preload("res://scripts/world/map_compiler.gd")
var profile:Dictionary={}
var admitted:Dictionary={}
var defeated:Dictionary={}
var boss_id:=0
var boss_defeated:=false
var complete:=false
func begin(value:Variant)->bool:
	if not Compiler.profile_reason(value).is_empty():return false
	profile=value.duplicate(true);admitted.clear();defeated.clear();boss_id=0;boss_defeated=false;complete=false
	return true
func clear()->void:
	profile.clear();admitted.clear();defeated.clear();boss_id=0;boss_defeated=false;complete=false
func can_admit()->bool:return not profile.is_empty() and not complete and admitted.size()<int(profile.ordinary_target)
func register_root(enemy:Dictionary,is_boss:bool=false)->bool:
	var id:int=int(enemy.get("id",0))
	if id<=0 or enemy.get("root_id")!=id or int(enemy.get("generation",-1))!=0 or not enemy.get("reward_eligible",false):return false
	if is_boss:
		if not ready_for_boss():return false
		boss_id=id;return true
	if not can_admit() or admitted.has(id):return false
	admitted[id]=true;return true
## Whole camp bookkeeping commits only after every root has been validated.
func register_group(roots: Variant) -> bool:
	if not roots is Array or roots.is_empty() or not can_admit() or admitted.size()+roots.size()>int(profile.ordinary_target): return false
	var ids: Dictionary = {}
	for enemy: Variant in roots:
		if not enemy is Dictionary or not enemy.get("id") is int: return false
		var id: int = enemy.id
		if id<=0 or enemy.get("root_id")!=id or enemy.get("generation")!=0 or not enemy.get("reward_eligible",false) or admitted.has(id) or ids.has(id): return false
		ids[id]=true
	for id: int in ids: admitted[id]=true
	return true
func record_death(enemy:Dictionary)->bool:
	var id:int=int(enemy.get("id",0))
	if id<=0 or enemy.get("root_id")!=id or int(enemy.get("generation",-1))!=0:return false
	if id==boss_id:
		if boss_defeated:return false
		boss_defeated=true;return true
	if not admitted.has(id) or defeated.has(id):return false
	defeated[id]=true;return true
func ready_for_boss()->bool:return not profile.is_empty() and defeated.size()==int(profile.ordinary_target) and boss_id==0
func check_complete(living:int,queued:int)->bool:
	if not complete and boss_defeated and living==0 and queued==0:complete=true;return true
	return false
func snapshot()->Dictionary:return {"admitted":admitted.size(),"ordinary_kills":defeated.size(),"ordinary_target":int(profile.get("ordinary_target",0)),"boss_id":boss_id,"boss_defeated":boss_defeated,"complete":complete}
