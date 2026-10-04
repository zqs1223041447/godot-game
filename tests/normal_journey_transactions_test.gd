extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Maps=preload("res://scripts/world/map_compiler.gd")
const Gems=preload("res://scripts/items/gem_catalog.gd")
class FaultModel extends Model:
	var fail_save:=false
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:return ERR_CANT_CREATE if fail_save else super._write_bytes(path,bytes)
var checks:=0
var failures:=0
const PATH="user://build_save.json"
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func observed(model:Model)->Dictionary:
	return {"memory":var_to_bytes(model.snapshot()),"disk":FileAccess.get_file_as_bytes(PATH),"saves":model.successful_saves}
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var model:=FaultModel.new();check(model.save_build(PATH)==OK,"Fresh normal profile saved")
	var changed:=[0];model.changed.connect(func():changed[0]+=1)
	var one:Dictionary=Maps.compile_normal("old_garden",1,[],[]).profile
	var two:=Maps.compile_normal("old_garden",2,["vitality"],[])
	# Use the live catalog rather than inventing an ordinary modifier ID.
	if not two.ok:two=Maps.compile_normal("old_garden",2,[],[])
	check(two.ok,"TierII authoritative profile available")
	var before:=observed(model)
	check(not model.normal_start_map(two.profile,model.revision(),PATH).ok and observed(model)==before,"Locked tier does not deduct or issue run")
	var first:=model.normal_start_map(one,model.revision(),PATH)
	check(first.ok and first.run_id==1 and first.cost==0,"Free starter admitted with persisted run1")
	check(model.normal_journey().next_run_id==2 and model.normal_journey().active_run.run_id==1,"Run ID allocated once")
	check(FileAccess.get_file_as_string(PATH).contains('"active_run"'),"Admission exists on disk before scene entry")
	before=observed(model)
	check(not model.normal_start_map(one,model.revision(),PATH).ok and observed(model)==before,"Active run cannot issue a duplicate")
	check(model.normal_complete_map(1,model.revision(),PATH).ok,"Trusted completion creates pending reward")
	check(model.normal_journey().best_tiers.old_garden==1 and model.normal_journey().best_tiers.broken_ruins==0,"Map unlocks are independent")
	check(model.normal_pending_rewards().pending_map_reward.shards==4 and model.crafting_balance()==0,"Completion creates claim, not a second wallet balance")
	before=observed(model)
	check(not model.normal_complete_map(1,model.revision(),PATH).ok and observed(model)==before,"Same run cannot settle twice")
	check(not model.normal_start_map(two.profile,model.revision(),PATH).ok and observed(model)==before,"Unclaimed map reward prevents another admission")
	var old_revision:=model.revision();var claim:=model.normal_claim_rewards(old_revision,PATH)
	check(claim.ok and claim.claimed_shards==4 and model.crafting_balance()==4,"Map shards are actual inventory currency")
	before=observed(model)
	check(not model.normal_claim_rewards(old_revision,PATH).ok and observed(model)==before,"Duplicate/stale claim is atomic")
	model.fail_save=true;var signals:int=changed[0]
	check(not model.normal_start_map(two.profile,model.revision(),PATH).ok and observed(model)==before and changed[0]==signals,"Failed admission write preserves currency, run ID, memory and notification")
	model.fail_save=false
	var second:=model.normal_start_map(two.profile,model.revision(),PATH)
	check(second.ok and second.run_id==2 and second.cost==4 and model.crafting_balance()==0,"Paid tier uses exact four real shards")
	before=observed(model)
	check(not model.normal_start_map(two.profile,model.revision(),PATH,2).ok and observed(model)==before,"Retry without funds keeps old run and all state")
	check(model.normal_abandon_map(2,model.revision(),PATH).ok and model.crafting_balance()==0,"Abandon gives no refund or completion award")
	before=observed(model)
	check(not model.normal_complete_map(2,model.revision(),PATH).ok and observed(model)==before,"Abandoned run has no claim")
	# Milestones use a persisted count, with one revision for existing XP+counter.
	var revision:=model.revision()
	for i:int in range(60):model.add_normal_root_xp(0)
	var pending:=model.normal_pending_rewards()
	check(pending.pending_gems is int and pending.pending_flasks is int and pending.pending_gems==2 and pending.pending_flasks==1,"Two cross-map gem milestones and one flask milestone accrued")
	check(model.revision()==revision+60 and model.normal_journey().normal_root_kills==60,"One reward-batch revision per legal root")
	check(model.save_build(PATH)==OK,"Existing final reward flush persists cumulative count")
	var snapshot:=model.snapshot();var old_rng:=RandomNumberGenerator.new();old_rng.seed=41;var rng_state:int=old_rng.state
	claim=model.normal_claim_rewards(model.revision(),PATH,false)
	check(claim.ok and claim.claimed_gems==2 and claim.claimed_flasks==1,"All fitting milestones commit once")
	check(model.normal_journey().claimed_gems==2 and model.normal_journey().claimed_flasks==1 and old_rng.state==rng_state,"Claimed ordinals persist without shared RNG")
	var created:Array=[]
	for uid:String in model.snapshot().items:
		if not snapshot.items.has(uid):created.append(model.snapshot().items[uid].definition_id)
	check(created.has(model.Journey.gem_definition(1)) and created.has(model.Journey.gem_definition(2)) and created.has("flask:life"),"Exact frozen milestone definitions materialized")
	# Test stock and normal progress each check the actual opened profile path.
	var test:=Model.new();check(test.save_build("user://town_test_build_save.json")==OK,"Independent test profile created")
	var test_before:=var_to_bytes(test.snapshot())
	check(not test.normal_start_map(one,test.revision(),"user://town_test_build_save.json").ok and not test.normal_claim_rewards(test.revision(),PATH).ok,"Test store cannot invoke normal economy")
	check(not test.add_normal_root_xp(1) and var_to_bytes(test.snapshot())==test_before,"Test store cannot advance normal milestones")
	before=observed(model)
	check(not model.town_claim_offer("currency:calibration_shard",model.revision(),PATH).ok and observed(model)==before,"Normal store cannot claim test currency")
	# Fill actual cells with real UID gems; a full bag keeps all owed rewards.
	var filled:=model.snapshot()
	for uid:String in filled.locations.keys():
		if filled.locations[uid].kind=="bag":filled.locations.erase(uid);filled.items.erase(uid)
	while true:
		var uid:="item_%06d"%int(filled.next_item_serial)
		if not model._place_journey_reward(filled,Gems.create_instance(uid,"support:efficiency")):break
	filled.revision+=1
	check(model._commit(filled,PATH).ok,"Complete240-cell fixture passes full item validation")
	var third:=model.normal_start_map(one,model.revision(),PATH)
	check(third.ok and model.normal_complete_map(third.run_id,model.revision(),PATH).ok,"Free map with full bag preserves pending settlement")
	for i:int in range(30):model.add_normal_root_xp(0)
	check(model.save_build(PATH)==OK,"Full-bag new milestone persists")
	before=observed(model);signals=changed[0]
	check(not model.normal_claim_rewards(model.revision(),PATH).ok and observed(model)==before and changed[0]==signals,"Nothing fits: no UID/ordinal/currency consumption or notification")
	check(model.normal_pending_rewards().pending_gems==1 and not model.normal_pending_rewards().pending_map_reward.is_empty(),"All unplaced awards remain due")
	var remove:=""
	for uid:String in model.snapshot().locations:
		if model.snapshot().locations[uid].kind=="bag":remove=uid;break
	check(model.discard_item(remove,model.revision(),PATH).ok,"One real slot released by permitted gem discard")
	claim=model.normal_claim_rewards(model.revision(),PATH)
	check(claim.ok and claim.claimed_shards==4 and claim.claimed_gems==0,"One freed cell gives priority to entire map credit")
	check(model.normal_pending_rewards().pending_map_reward.is_empty() and model.normal_pending_rewards().pending_gems==1,"Item backlog does not retain map gate")
	var fourth:=model.normal_start_map(one,model.revision(),PATH)
	check(fourth.ok,"Pending gem does not block next map")
	# External disk edits stop a claim/start through the unchanged store receipt.
	check(model.normal_abandon_map(fourth.run_id,model.revision(),PATH).ok,"Test run left normally")
	var disk:=FileAccess.get_file_as_bytes(PATH);var output:=FileAccess.open(PATH,FileAccess.WRITE);output.store_buffer(disk+" ".to_utf8_buffer());output.close()
	var memory:=var_to_bytes(model.snapshot())
	check(not model.normal_start_map(one,model.revision(),PATH).ok and var_to_bytes(model.snapshot())==memory and FileAccess.get_file_as_bytes(PATH)==disk+" ".to_utf8_buffer(),"External bytes are not overwritten by normal admission")
	print("Normal journey transactions: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
