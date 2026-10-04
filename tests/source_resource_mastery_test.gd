extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
const OLD_PREFIX=["58833","2151","37690","48423","6204","63976","33479","10490","47251","7388","60398","31875","4397","7938","1031","60388","24362"]
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var model:=Model.new();var candidate:=model.snapshot();candidate.progress.level=119;candidate.progress.xp=0;candidate.talents.allocated=OLD_PREFIX.duplicate();candidate.talents.normal_points=107
	var old:=candidate.duplicate(true);old.version=21
	check(model.Rules.reason_v21(old).is_empty(),"Mastery test prefix is independently legal under frozen21, without a new ordinary cost node")
	model._accept_memory(candidate);var path:="user://cost-mastery.json";check(model.save_build(path)==OK,"Old-compatible prefix persisted through current full validator")
	var base:float=model.get_skill_cast("nova").mana;var points:int=model.talent_points
	check(model.available_passives().has("53188") and model.allocate_passive("53188",12119,model.revision(),path).ok,"Actual mastery choice requires the reached notable group")
	check(model.talent_points==points-1 and is_equal_approx(model.get_stats().mana_cost_efficiency_increased,0.15) and is_equal_approx(model.get_skill_cast("nova").mana,base/1.15),"One mastery effect consumes one point and adds15percent once")
	var injected:=model.snapshot();injected.version=21
	check(not model.Rules.reason_v21(injected).is_empty() and SourceTree.node_effect("53188",12119,21).status!="full" and SourceTree.node_effect("53188",12119,22).status=="full","Old21 rejection is specifically caused by the new mastery vocabulary")
	var bad_path:="user://injected-mastery21.json";var bytes:=JSON.stringify(injected).to_utf8_buffer();FileAccess.open(bad_path,FileAccess.WRITE).store_buffer(bytes)
	var rejected:=Model.new();var before:=rejected.snapshot()
	check(not rejected.load_build(bad_path) and rejected.snapshot()==before and FileAccess.get_file_as_bytes(bad_path)==bytes and not FileAccess.file_exists(bad_path+".v21-backup.json"),"Injected old21 mastery stops before backup or write")
	for id:String in ["45680","25237","10835"]:check(model.allocate_passive(id,0,model.revision(),path).ok,"Second actual notable group connected: "+id)
	before=model.snapshot();var disk:=FileAccess.get_file_as_bytes(path);var cost:float=model.get_skill_cast("nova").mana
	check(not model.allocate_passive("63559",12119,model.revision(),path).ok and model.snapshot()==before and FileAccess.get_file_as_bytes(path)==disk,"Second entrance cannot stack same mastery effect ID")
	check(model.refund_passive("53188",model.revision(),path).ok and model.allocate_passive("63559",12119,model.revision(),path).ok and is_equal_approx(model.get_skill_cast("nova").mana,cost),"Refund then relocate the one effect preserves its amount")
	before=model.snapshot();disk=FileAccess.get_file_as_bytes(path)
	check(not model.refund_passive("10835",model.revision(),path).ok and model.snapshot()==before and FileAccess.get_file_as_bytes(path)==disk,"Cannot orphan the selected mastery by refunding its only reached notable")
	var entrances:=0
	for id:String in SourceTree.Data.standard_ids():
		for option:Dictionary in SourceTree.Data.node(id).mastery_effects:
			if int(option.effect)==12119:entrances+=1
	check(entrances==12,"Catalog has12 entrances to one effect, not12 independent stackable grants")
	print("Source resource mastery: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
