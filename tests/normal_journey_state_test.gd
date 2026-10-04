extends SceneTree
const Journey=preload("res://scripts/world/normal_journey_state.gd")
const Maps=preload("res://scripts/world/map_compiler.gd")
const Gems=preload("res://scripts/items/gem_catalog.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func rejected(journey:Dictionary,label:String)->void:
	check(not Journey.reason(journey).is_empty() and Journey.decode(journey).is_empty(),label)
func fail_unchanged(journey:Dictionary,operation:String,argument:Variant)->void:
	var bytes:=var_to_bytes(journey)
	var result:Dictionary=Journey.new().call(operation,journey,argument)
	check(not result.ok and result.journey.is_empty() and not result.reason.is_empty() and var_to_bytes(journey)==bytes,"Failed %s preserves caller and returns no candidate"%operation)
func _initialize()->void:
	var empty:=Journey.empty();check(Journey.reason(empty).is_empty() and Journey.decode(empty)==empty,"Empty journey is complete and valid")
	var detached:=Journey.empty();detached.best_tiers.old_garden=3
	check(empty.best_tiers.old_garden==0,"Empty journeys do not share nested containers")
	var decoded:=Journey.decode(JSON.parse_string(JSON.stringify(empty)))
	check(decoded==empty and decoded.next_run_id is int and decoded.best_tiers.old_garden is int,"JSON finite integral values become real integers")
	for field:String in ["normal_root_kills","next_run_id","claimed_gems","claimed_flasks"]:
		for invalid:Variant in [true,false,-1,0.5,"1",null,INF,NAN,1000000001]:
			var bad:=empty.duplicate(true);bad[field]=invalid;rejected(bad,"Reject malformed numeric "+field)
	var bad:=empty.duplicate(true);bad.next_run_id=0;rejected(bad,"Serial starts at one")
	bad=empty.duplicate(true);bad.normal_root_kills=60;bad.claimed_gems=2;bad.claimed_flasks=1
	check(Journey.reason(bad).is_empty(),"Milestone counters allow exact earned rewards")
	bad.claimed_gems=3;rejected(bad,"Cannot claim unearned gems")
	bad.claimed_gems=2;bad.claimed_flasks=2;rejected(bad,"Cannot claim unearned flasks")
	bad=empty.duplicate(true);bad.runtime_rng=4;rejected(bad,"No transient fields")
	bad=empty.duplicate(true);bad.erase("claimed_gems");rejected(bad,"All fields mandatory")
	bad=empty.duplicate(true);bad.best_tiers={"old_garden":0};rejected(bad,"Both map records mandatory")
	bad=empty.duplicate(true);bad.best_tiers.old_garden=4;rejected(bad,"Best tiers capped at three")
	bad=empty.duplicate(true);bad.best_tiers.old_garden=1.0
	check(not Journey.reason(bad).is_empty() and Journey.decode(bad).best_tiers.old_garden==1,"Pure reason does not coerce floats")
	for id:String in Journey.MAP_IDS:
		var first:Dictionary=Maps.compile_normal(id,1,[],[]).profile
		var source_bytes:=var_to_bytes(empty);var started:=Journey.start(empty,first)
		check(started.ok and started.run_id==1 and started.cost==0 and started.journey.next_run_id==2 and var_to_bytes(empty)==source_bytes,"Start tier1 on "+id+" without touching input")
		check(Journey.reason(started.journey).is_empty() and Journey.decode(JSON.parse_string(JSON.stringify(started.journey)))==started.journey,"Active run roundtrips canonically")
		fail_unchanged(empty,"start",Maps.compile_normal(id,2,[],[]).profile)
		fail_unchanged(started.journey,"start",first)
		for wrong:Variant in [0,2,1.0,true,"1"]:
			fail_unchanged(started.journey,"complete",wrong);fail_unchanged(started.journey,"abandon",wrong)
		var ended:=Journey.complete(started.journey,1)
		check(ended.ok and ended.reward==4 and ended.journey.best_tiers[id]==1 and ended.journey.active_run.is_empty() and ended.journey.pending_map_reward.shards==4,"Completion unlocks next tier and records reward once")
		check(Journey.reason(ended.journey).is_empty() and Journey.decode(JSON.parse_string(JSON.stringify(ended.journey)))==ended.journey,"Pending reward roundtrips")
		fail_unchanged(ended.journey,"start",first);fail_unchanged(ended.journey,"complete",1);fail_unchanged(ended.journey,"abandon",1)
		var abandoned:=Journey.abandon(started.journey,1)
		check(abandoned.ok and abandoned.journey.active_run.is_empty() and abandoned.journey.best_tiers==empty.best_tiers and abandoned.journey.next_run_id==2 and abandoned.journey.pending_map_reward.is_empty(),"Abandon clears only active run; no unlock or refund")
		var progress:Dictionary=ended.journey.duplicate(true);progress.pending_map_reward={}
		for tier:int in [2,3]:
			var profile:Dictionary=Maps.compile_normal(id,tier,["enemy_move_speed_110","enemy_armour_80"],["frost_patrol"]).profile
			started=Journey.start(progress,profile)
			check(started.ok and started.cost==(tier-1)*4 and started.journey.active_run.fee_paid==started.cost,"Tier cost recorded canonically")
			ended=Journey.complete(started.journey,started.run_id)
			check(ended.ok and ended.reward==tier*4+4 and ended.journey.best_tiers[id]==tier and Journey.reason(ended.journey).is_empty(),"Canonical full modifier reward and best tier")
			progress=ended.journey.duplicate(true);progress.pending_map_reward={}
		var replay:=Journey.start(progress,first);var replayed:=Journey.complete(replay.journey,replay.run_id)
		check(replayed.journey.best_tiers[id]==3 and replayed.reward==4,"Replaying lower tiers never reduces best tier")
	var first:Dictionary=Maps.compile_normal("old_garden",1,[],[]).profile
	fail_unchanged(empty,"start",Maps.compile("old_garden",[],[]).profile)
	var forged:=first.duplicate(true);forged.fee=9;fail_unchanged(empty,"start",forged)
	forged=first.duplicate(true);forged.normal_map=1;fail_unchanged(empty,"start",forged)
	bad=empty.duplicate(true);bad.next_run_id=Journey.MAX_SERIAL;fail_unchanged(bad,"start",first)
	bad.next_run_id=Journey.MAX_SERIAL-1;var last:=Journey.start(bad,first)
	check(last.ok and last.run_id==Journey.MAX_SERIAL-1 and last.journey.next_run_id==Journey.MAX_SERIAL,"Last available serial is accepted once")
	var active:Dictionary=Journey.start(empty,first).journey
	for change:String in ["run_zero","run_future","tier_locked","map_unknown","fee","duplicate","unsorted","unknown","non_string","low_special","extra","both"]:
		bad=active.duplicate(true)
		match change:
			"run_zero":bad.active_run.run_id=0
			"run_future":bad.active_run.run_id=2
			"tier_locked":bad.active_run.tier=2
			"map_unknown":bad.active_run.map_id="unknown"
			"fee":bad.active_run.fee_paid=4
			"duplicate":bad.active_run.normal_ids=["enemy_armour_80","enemy_armour_80"]
			"unsorted":bad.active_run.normal_ids=["enemy_move_speed_110","enemy_armour_80"]
			"unknown":bad.active_run.normal_ids=["unknown"]
			"non_string":bad.active_run.normal_ids=[1]
			"low_special":bad.active_run.special_ids=["frost_patrol"]
			"extra":bad.active_run.wave=1
			"both":bad.pending_map_reward={"run_id":1,"map_id":"old_garden","tier":1,"shards":4}
		rejected(bad,"Invalid active run "+change)
	var pending:Dictionary=Journey.complete(active,1).journey
	for change:String in ["serial","map","tier","reward_low","reward_high","extra","float"]:
		bad=pending.duplicate(true)
		match change:
			"serial":bad.pending_map_reward.run_id=2
			"map":bad.pending_map_reward.map_id="unknown"
			"tier":bad.pending_map_reward.tier=2
			"reward_low":bad.pending_map_reward.shards=3
			"reward_high":bad.pending_map_reward.shards=9
			"extra":bad.pending_map_reward.normal_ids=[]
			"float":bad.pending_map_reward.shards=4.5
		rejected(bad,"Invalid pending reward "+change)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v041_journey/manifest.json"))
	check(Journey.GEM_DEFINITIONS==manifest.gem_definitions and Journey.GEM_DEFINITIONS.size()==26,"Frozen reward vocabulary matches actual released26 definitions")
	for definition:String in Journey.GEM_DEFINITIONS:check(not Gems.definition(definition).is_empty(),"Frozen reward is a real gem: "+definition)
	seed(34983);var expected_rand:=randi();seed(34983)
	for ordinal:int in range(1,101):
		var rng:=RandomNumberGenerator.new();rng.seed=0x47454D31 ^ ordinal
		check(Journey.gem_definition(ordinal)==Journey.GEM_DEFINITIONS[rng.randi_range(0,25)] and Journey.gem_definition(ordinal)==Journey.gem_definition(ordinal),"Stable independent gem ordinal"+str(ordinal))
		check(Journey.flask_definition(ordinal)==("flask:life" if ordinal%2 else "flask:mana"),"Alternating flask ordinal"+str(ordinal))
	check(randi()==expected_rand,"Reward identity helpers never consume shared RNG")
	check(Journey.gem_definition(0)=="" and Journey.gem_definition(-1)=="" and Journey.gem_definition(33333334)=="" and Journey.flask_definition(0)=="" and Journey.flask_definition(16666667)=="","Invalid reward ordinals rejected")
	print("Normal journey state: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
