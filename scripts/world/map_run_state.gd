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
	if not _initial_root_valid(enemy):return false
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
		if not _initial_root_valid(enemy): return false
		var id: int = enemy.id
		if admitted.has(id) or ids.has(id): return false
		ids[id]=true
	for id: int in ids: admitted[id]=true
	return true
## Exploration admits the entire ordinary roster and its living boss together.
## No bookkeeping becomes visible until every identity has been checked.
func register_initial_group(ordinary_roots: Variant, boss: Variant) -> bool:
	if profile.is_empty() or complete or not admitted.is_empty() or not defeated.is_empty() or boss_id != 0 or boss_defeated:
		return false
	if not ordinary_roots is Array or ordinary_roots.size() != int(profile.ordinary_target) or not boss is Dictionary:
		return false
	var ids: Dictionary = {}
	for enemy: Variant in ordinary_roots:
		if not _initial_root_valid(enemy) or ids.has(enemy.id): return false
		ids[enemy.id] = true
	if not _initial_root_valid(boss) or ids.has(boss.id) or boss.get("template_id") != profile.boss_id:
		return false
	admitted = ids
	boss_id = boss.id
	return true

static func _initial_root_valid(enemy: Variant) -> bool:
	return enemy is Dictionary and typeof(enemy.get("id")) == TYPE_INT and enemy.id > 0 \
		and typeof(enemy.get("root_id")) == TYPE_INT and enemy.root_id == enemy.id \
		and typeof(enemy.get("generation")) == TYPE_INT and enemy.generation == 0 \
		and typeof(enemy.get("reward_eligible")) == TYPE_BOOL

## Required completion membership comes from admission, never reward eligibility.
## Optional encounter admission is not implemented. Any unknown actor/request
## fails closed until an explicit optional membership policy is introduced.
func owns_lineage(root_id: Variant) -> bool:
	return typeof(root_id) == TYPE_INT and root_id > 0 and (root_id == boss_id or admitted.has(root_id))

func completion_members(enemies: Array[Dictionary], queue: Array[Dictionary], death_lineages: Dictionary) -> Dictionary:
	var living: Array[Dictionary] = []
	for enemy: Dictionary in enemies:
		if not owns_lineage(enemy.get("root_id")):
			return {"ok": false, "reason": "地图存在未登记怪物，无法确认清图状态"}
		if float(enemy.get("health", 0.0)) > 0.0:
			living.append(enemy)
		else:
			# Actor flags can be stale copies. Only the runtime identity ledger
			# proves legal death settlement before filtering or completion.
			# Main retires lineage ledgers only after filtering settled corpses.
			var processed: Dictionary = death_lineages.get(enemy.root_id, {}).get("processed", {})
			if not processed.has(enemy.get("id")):
				return {"ok": false, "reason": "地图存在尚未结算的死亡，无法确认清图状态"}
	for request: Dictionary in queue:
		if not owns_lineage(request.get("root_id")):
			return {"ok": false, "reason": "地图存在未登记后代，无法确认清图状态"}
	return {"ok": true, "reason": "", "living": living, "pending_count": queue.size()}

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
	if not complete and not profile.is_empty() and boss_defeated and living==0 and queued==0 \
		and admitted.size()==int(profile.ordinary_target) and defeated.size()==int(profile.ordinary_target):
		complete=true;return true
	return false
func snapshot()->Dictionary:return {"admitted":admitted.size(),"ordinary_kills":defeated.size(),"ordinary_target":int(profile.get("ordinary_target",0)),"boss_id":boss_id,"boss_defeated":boss_defeated,"complete":complete}
