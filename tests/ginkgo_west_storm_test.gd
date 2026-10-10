extends SceneTree
## Frozen pre-change rosters, bounded generation and real geometry admission.
const Capture=preload("res://docs/qa/ginkgo-west-storm/capture_baseline.gd")
const Rules=preload("res://scripts/world/ginkgo_roster_rules.gd")
const State=preload("res://scripts/world/map_camp_state.gd")
const Layout=preload("res://scripts/world/exploration_map_layout.gd")
const Maps=preload("res://scripts/world/map_compiler.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Plan=preload("res://scripts/world/exploration_map_plan.gd")
const Runtime=preload("res://scripts/monsters/monster_runtime.gd")
var checks:=0
var failures:=0
var changed:=0
var preserved:=0
var plans:=0
var witnesses:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _initialize()->void:
	var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/ginkgo-west-storm/baseline.json"))
	check(baseline.baseline=="8ed6961ccc8a87793cbd1ae76c9afe8ae4d9b95a" and baseline.cases.size()==261,"Complete pre-change batch")
	seed(76121);var next_global:=randi();seed(76121)
	for row:Dictionary in baseline.cases:
		var profile:=Capture.profile(row)
		var marks:Dictionary=Layout.layout(row.map_id,Layout.WORLD_BOUNDS).landmarks
		var state:=State.new();var replay:=State.new()
		if not state.begin(profile,marks,int(row.seed),Monsters.CURRENT_ROLL_POLICY).ok:
			check(false,"Admission "+row.key);continue
		check(replay.begin(profile,marks,int(row.seed),Monsters.CURRENT_ROLL_POLICY).ok and var_to_bytes(replay.checkpoint())==var_to_bytes(state.checkpoint()),"Exact seed replay "+row.key)
		var old:Dictionary=bytes_to_var(str(row.slot3).hex_decode())
		var eligible:bool=row.map_id=="ginkgo_arcade" and int(row.tier) in [2,3] and old.template_id=="skitter" and old.rarity=="normal" and old.mechanisms.is_empty()
		for camp:String in State.CAMP_IDS:
			var entries:=state.entries(camp)
			if camp=="camp_west" and eligible:
				var actual:=entries[2].duplicate(true)
				check(actual.template_id=="storm_skitter","Only permitted normal third slot changes")
				actual.template_id="skitter"
				check(var_to_bytes(actual)==var_to_bytes(old),"Position, admission, rarity and mechanisms are exact baseline bytes")
				entries[2]=old;changed+=1
				witnesses.append(row.key)
			check(var_to_bytes(entries).hex_encode().sha256_text()==row.hashes[camp],"Full camp hash matches baseline after allowed slot restoration "+row.key+"/"+camp)
		if not eligible:preserved+=1
	check(changed>0 and preserved>0,"Actual candidate and no-change witnesses")
	check(randi()==next_global,"No global RNG consumption")
	var profile:Dictionary=Maps.compile_normal("ginkgo_arcade",2,[],[]).profile
	var normal:Dictionary={"template_id":"skitter","rarity":"normal","mechanisms":[]}
	var entries:Array[Dictionary]=[normal.duplicate(true),normal.duplicate(true),normal.duplicate(true),normal.duplicate(true)]
	for field:String in ["id","normal_map","journey_tier","wave"]:
		var bad:=profile.duplicate(true);bad.erase(field)
		check(Rules.west_storm_index(bad,"camp_west",entries)==-1,"Missing scope field rejects "+field)
	for bad:Variant in [true,2.0,"2",1,4]:
		var p:=profile.duplicate(true);p.journey_tier=bad
		check(Rules.west_storm_index(p,"camp_west",entries)==-1,"Wrong tier type/value rejects")
	for template:String in ["splitter","brood_host","ember_guard","storm_skitter","frost_guard","chaos_guard"]:
		entries[2].template_id=template
		check(Rules.west_storm_index(profile,"camp_west",entries)==-1,"No fallback on protected "+template)
	entries[2].template_id="skitter"
	for rarity:String in ["magic","rare",""]:
		entries[2].rarity=rarity;check(Rules.west_storm_index(profile,"camp_west",entries)==-1,"No rarity overwrite")
	entries[2].rarity="normal";entries[2].mechanisms=["sentinel"]
	check(Rules.west_storm_index(profile,"camp_west",entries)==-1,"No mechanism overwrite")
	entries[2].mechanisms=[]
	check(Rules.west_storm_index(profile,"camp_north",entries)==-1 and Rules.west_storm_index(profile,"camp_east",entries)==-1,"Other camps excluded")
	check(Rules.west_storm_index(profile,"camp_west",entries)==2,"Only fixed third slot")
	for tier:int in [1,2,3]:
		for seed_value:int in [0,7,861073]:
			var p:Dictionary=Maps.compile_normal("ginkgo_arcade",tier,[],[]).profile
			var live:=Runtime.new();var before:=live.next_id
			var plan:=Plan.plan(p,live,seed_value,Layout.WORLD_BOUNDS)
			if not plan.ok:check(false,"Full plan: "+plan.reason);continue
			plans+=1
			check(plan.roots.size()==37 and plan.spawn_records.size()==37 and plan.run.snapshot().admitted==36,"Full root budget and run ledger")
			check(live.next_id==before,"Detached admission leaves live cursor untouched")
			check(plan.landmarks.outposts[0].id=="camp_west_1" and plan.landmarks.outposts[0].root_ids.size()==4,"First outpost retains four roots")
			for i:int in range(37):
				var enemy:Dictionary=plan.roots[i];var record:Dictionary=plan.spawn_records[i]
				check(record.actor_id==enemy.id and enemy.root_id==enemy.id and enemy.generation==0 and enemy.reward_eligible and record.reward_route=="standard","Stable identity and reward admission")
				check(plan.geometry.is_clear(enemy.pos,enemy.radius),"Actual actor fits unchanged reachable geometry")
			check(plan.spawn_records[2].ordinal==3 and plan.spawn_records[2].outpost_id=="camp_west_1","Selected ordinal resolves authored first outpost")
	check(plans==9,"All nine finite full plans finish")
	var report:Dictionary={"checks":checks,"failures":failures,"cases":baseline.cases.size(),"changed_cases":changed,"unchanged_cases":preserved,"full_plans":plans,"witnesses":witnesses}
	FileAccess.open("res://docs/qa/ginkgo-west-storm/generation-result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("GINKGO_WEST_STORM ",JSON.stringify(report));quit(1 if failures else 0)
