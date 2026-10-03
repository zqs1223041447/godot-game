extends SceneTree
## Isolate measured pure work from real sustained-run inventories. No model fix.
const Model = preload("res://scripts/canonical_game_state.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Transfer = preload("res://scripts/items/item_transfer_plan.gd")
const Migration = preload("res://scripts/save/canonical_build_migration.gd")
const RuntimeIcons = preload("res://scripts/visuals/skill_emblem.gd")
var retained_icons: Dictionary = RuntimeIcons.ICONS
var output := OS.get_environment("REWARD_PROFILE_OUT")
var fixture := OS.get_environment("REWARD_PROFILE_FIXTURE")
var report: Array = []

func _initialize()->void: call_deferred("run")

func run()->void:
	var data := OS.get_environment("XDG_DATA_HOME")
	if not data.begins_with("/workspace/scratch/a51485f153de/v023-profile-users/") or output.is_empty() \
			or not fixture.begins_with("/workspace/scratch/a51485f153de/v023-profile-users/"):
		quit(78);return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	var end_state: Dictionary = Rules.decode(raw)
	assert(Rules.reason(end_state).is_empty())
	var reduced := end_state.duplicate(true)
	var uids: Array = reduced.items.keys();uids.sort();uids.reverse()
	for uid: String in uids:
		if reduced.items.size()<=60:break
		if reduced.locations[uid].kind=="bag":reduced.items.erase(uid);reduced.locations.erase(uid)
	assert(Rules.reason(reduced).is_empty())
	var fresh := Model.new().snapshot()
	for source: Dictionary in [fresh,reduced,end_state]:
		var state := Model.new()
		var path := "user://profile-%d.json" % source.items.size()
		FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(source,"\t",true,true))
		assert(state.load_build(path))
		# A genuine XP update makes the last persisted bytes stale, as on a kill.
		state.add_xp(1)
		var stable := state.snapshot()
		var key := var_to_bytes(stable)
		var metadata := Items.metadata_for_items(stable.items)
		assert(metadata.size()==stable.items.size() and not state.crafting_change_already_saved())
		var moving := ""
		for uid: String in stable.locations:
			if stable.locations[uid].kind=="bag":moving=uid
		var context := Migration.paged_location_context(stable,Rules.SourceTree.Data.standard_socket_ids())
		var metrics := {}
		metrics.metadata = timed(func(): return Items.metadata_for_items(stable.items))
		metrics.full_validation = timed(func(): return Rules.reason(stable))
		metrics.first_space_existing_item = timed(func(): return Transfer.first_bag_space_paged(metadata,stable.locations,context,moving))
		metrics.serialize = timed(func(): return JSON.stringify(stable,"\t",true,true))
		metrics.stale_save_receipt = timed(func(): return state.crafting_change_already_saved())
		assert(key==var_to_bytes(stable) and stable==state.snapshot())
		var rng := RandomNumberGenerator.new()
		var award_times: Array[int] = []
		var results: Array[String] = []
		var outcome := PackedByteArray()
		for index: int in range(10):
			state._accept_memory(stable.duplicate(true));rng.seed=230099
			var began := Time.get_ticks_usec()
			var uid: String=state.award_equipment(rng,30,"rare","current")
			award_times.append(Time.get_ticks_usec()-began);results.append(uid)
			var value := var_to_bytes([state.snapshot(),rng.state])
			if index==0:outcome=value
			else:assert(value==outcome)
		metrics.equipment_reward_replay=summary(award_times)
		report.append({"items":stable.items.size(),"retained_runtime_icons":retained_icons.size(),"serialized_bytes":JSON.stringify(stable,"\t",true,true).to_utf8_buffer().size(),
			"metrics_us":metrics,"reward_uid":results[0],"replay_exact":true,"receipt":false,"production_source_unchanged":true})
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("REWARD_PATH_PROFILE_COMPLETE ",report.size())
	quit()

func timed(operation: Callable) -> Dictionary:
	operation.call()
	var times: Array[int]=[]
	for unused: int in range(20):
		var start:=Time.get_ticks_usec();operation.call();times.append(Time.get_ticks_usec()-start)
	return summary(times)

func summary(values: Array[int]) -> Dictionary:
	values.sort();var total:=0.0
	for value: int in values:total+=value
	return {"n":values.size(),"mean":total/values.size(),"p50":values[int(values.size()/2)],"max":values.back()}
