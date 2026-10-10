extends SceneTree
## Exact released generator oracle plus one bounded, final outpost substitution.
const Cases=preload("res://docs/qa/ginkgo-west-storm/capture_baseline.gd")
const State=preload("res://scripts/world/map_camp_state.gd")
const Rules=preload("res://scripts/world/broken_ruins_roster_rules.gd")
const Layout=preload("res://scripts/world/exploration_map_layout.gd")
const Maps=preload("res://scripts/world/map_compiler.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Plan=preload("res://scripts/world/exploration_map_plan.gd")
const Runtime=preload("res://scripts/monsters/monster_runtime.gd")
const ORACLE="res://docs/qa/ruins-corridor-frost/map_camp_state_8740385.gd.txt"
var checks:=0
var failures:=0
var changed:=0
var unchanged:=0
var existing_frost:=0
var no_candidate:=0
var witnesses:Array=[]
var old_script:GDScript
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
	return ok
func compare(profile:Dictionary,seed_value:int,label:String)->void:
	var marks:Dictionary=Layout.layout(profile.id,Layout.WORLD_BOUNDS).landmarks
	var old:RefCounted=old_script.new();var state:=State.new();var replay:=State.new()
	if not old.begin(profile,marks,seed_value,Monsters.CURRENT_ROLL_POLICY).ok or not state.begin(profile,marks,seed_value,Monsters.CURRENT_ROLL_POLICY).ok:
		check(false,"Both generators accept "+label);return
	var expected:Dictionary=old.checkpoint()
	var selected:=-1
	if profile.id=="broken_ruins" and profile.get("normal_map",false) and int(profile.get("journey_tier",0)) in [2,3]:
		var entries:Array=expected.camps[1].entries
		var has_frost:=false
		for index:int in range(4,12):has_frost=has_frost or entries[index].template_id=="frost_guard"
		if has_frost:existing_frost+=1
		else:
			for index:int in range(4,12):
				if entries[index].template_id=="brute" and entries[index].rarity=="normal" and entries[index].mechanisms.is_empty():selected=index;break
			if selected<0:no_candidate+=1
		if selected>=0:
			var original:=str(entries[selected].template_id)
			entries[selected].template_id="frost_guard"
			witnesses.append({"case":label,"ordinal":selected+1,"from":original,"to":"frost_guard"})
	check(var_to_bytes(state.checkpoint())==var_to_bytes(expected),"Entire typed checkpoint equals baseline plus only selected replacement "+label)
	check(replay.begin(profile,marks,seed_value,Monsters.CURRENT_ROLL_POLICY).ok and var_to_bytes(replay.checkpoint())==var_to_bytes(state.checkpoint()),"Exact seed replay "+label)
	if selected>=0:changed+=1
	else:
		unchanged+=1
		check(var_to_bytes(state.checkpoint())==var_to_bytes(old.checkpoint()),"Exact unchanged full checkpoint "+label)
func _initialize()->void:
	if not check(FileAccess.get_sha256(ORACLE)=="5b49600164356fa94fdbb10115d3b07b7d9193aa9212db6d85dbb0a79e86174b","Exact released oracle bytes"):quit(1);return
	old_script=GDScript.new();old_script.source_code=FileAccess.get_file_as_string(ORACLE).replace("class_name MapCampState\n","")
	if not check(old_script.reload()==OK,"Released oracle loads"):quit(1);return
	seed(78941);var expected_rng:=randi();seed(78941)
	for row:Dictionary in Cases.cases():compare(Cases.profile(row),row.seed,row.key)
	for tier:int in [2,3]:
		for special:Array in [[],["storm_patrol"]]:
			var profile:Dictionary=Maps.compile_normal("broken_ruins",tier,["enemy_max_health_120","enemy_shield_from_health_20"],special).profile
			compare(profile,7,"modified/%d/%s"%[tier,str(special)])
	check(randi()==expected_rng,"Full comparison consumes no global RNG")
	check(changed>0 and unchanged>0 and existing_frost>0 and no_candidate>0 and changed+unchanged==265,"Complete bounded batch includes all eligibility boundaries")
	var profile:Dictionary=Maps.compile_normal("broken_ruins",2,[],[]).profile
	var entries:Array[Dictionary]=[]
	for i:int in range(12):entries.append({"template_id":"brute","rarity":"normal","mechanisms":[]})
	check(Rules.corridor_frost_index(profile,"camp_north",entries)==4,"First of eight corridor candidates, not first outpost")
	var before:=var_to_bytes([profile,entries])
	Rules.corridor_frost_index(profile,"camp_north",entries)
	check(var_to_bytes([profile,entries])==before,"Pure helper leaves caller values untouched")
	entries[11].template_id="frost_guard"
	check(Rules.corridor_frost_index(profile,"camp_north",entries)==-1,"Existing last-slot frost prevents stacking")
	entries[11].template_id="brute"
	for i:int in range(4,12):entries[i].rarity="rare"
	check(Rules.corridor_frost_index(profile,"camp_north",entries)==-1,"No rare overwrite or fallback to first outpost")
	for i:int in range(4,12):entries[i].rarity="normal";entries[i].mechanisms=["sentinel"]
	check(Rules.corridor_frost_index(profile,"camp_north",entries)==-1,"No mechanism overwrite")
	for i:int in range(4,12):entries[i].mechanisms=[];entries[i].template_id="brood_host"
	check(Rules.corridor_frost_index(profile,"camp_north",entries)==-1,"No special-template overwrite")
	entries[4].template_id="brute"
	for field:String in ["id","normal_map","journey_tier","wave"]:
		var bad:=profile.duplicate(true);bad.erase(field)
		check(Rules.corridor_frost_index(bad,"camp_north",entries)==-1,"Missing scope field rejects")
	for value:Variant in [true,2.0,"2",1,4]:
		var bad:=profile.duplicate(true);bad.journey_tier=value
		check(Rules.corridor_frost_index(bad,"camp_north",entries)==-1,"Wrong tier type/value rejects")
	check(Rules.corridor_frost_index(profile,"camp_west",entries)==-1 and Rules.corridor_frost_index(profile,"camp_east",entries)==-1,"Other camps excluded")
	var plans:=0
	for tier:int in [1,2,3]:
		for seed_value:int in [0,7,861073]:
			var p:Dictionary=Maps.compile_normal("broken_ruins",tier,[],[]).profile
			var live:=Runtime.new();var cursor:=live.next_id
			var plan:=Plan.plan(p,live,seed_value,Layout.WORLD_BOUNDS)
			if not plan.ok:check(false,"Complete admission "+plan.reason);continue
			plans+=1
			check(plan.roots.size()==37 and plan.run.snapshot().admitted==36 and live.next_id==cursor,"Unchanged root budget and detached ID cursor")
			check(plan.landmarks.outposts[3].id=="camp_north_2" and plan.landmarks.outposts[3].root_ids.size()==8,"Exact corridor membership")
			for i:int in range(37):
				var enemy:Dictionary=plan.roots[i];var record:Dictionary=plan.spawn_records[i]
				check(enemy.root_id==enemy.id and enemy.generation==0 and enemy.reward_eligible and record.actor_id==enemy.id and record.reward_route=="standard","Root identity and reward route")
				check(plan.geometry.is_clear(enemy.pos,enemy.radius),"Unchanged same-body root fits reachable geometry")
	check(plans==9,"All nine full route and spawn admissions finish")
	var report:Dictionary={"checks":checks,"failures":failures,"cases":changed+unchanged,"changed_cases":changed,"unchanged_cases":unchanged,"existing_frost_cases":existing_frost,"no_candidate_cases":no_candidate,"full_plans":plans,"witnesses":witnesses}
	FileAccess.open("res://docs/qa/ruins-corridor-frost/generation-result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("RUINS_CORRIDOR_FROST ",JSON.stringify(report));quit(1 if failures else 0)
