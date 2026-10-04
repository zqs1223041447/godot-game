extends SceneTree
## Short exact-observable comparison against the frozen f074c26 reward chain.
## Generate the oracle only by running this script with --path at that checkout.
const Model = preload("res://scripts/canonical_game_state.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Arena = preload("res://scripts/main.gd")
const GOLDEN = "res://docs/qa/v038-rewards/baseline-equivalence.json"
var checks := 0
var failures := 0
var rows: Array = []

class ObservedState extends "res://scripts/canonical_game_state.gd":
	var fail_write := false
	var admitted: Array = []
	func _admit_reward_item(wrapped: Dictionary) -> bool:
		var accepted := super._admit_reward_item(wrapped)
		admitted.append([wrapped.uid, accepted, revision()])
		return accepted
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_write else super._write_bytes(path, bytes)

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func fingerprint(value: Variant) -> String:
	return var_to_bytes(value).hex_encode().sha256_text()

func state_record(state: ObservedState, rng: RandomNumberGenerator) -> Dictionary:
	var current := state.snapshot()
	return {"typed_state_sha256": fingerprint(current), "state": JSON.stringify(current,"\t",true,true),
		"uid_order": current.items.keys(), "rng": str(rng.state), "admissions": state.admitted.duplicate(true)}

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v038-rewards-"):
		quit(78)
		return
	for batch: int in [1,8,20]:
		for repetition: int in range(3):
			await death_batch(batch,repetition,0,false)
	# Cross item reward boundaries with actual root deaths, flask charge grants,
	# and one failed batch save followed by the existing explicit retry.
	await death_batch(20,0,118,false)
	await death_batch(20,0,58,true)
	test_rejections()
	var serialized := JSON.stringify(rows,"\t",true,true)
	var output := OS.get_environment("REWARD_V38_RECORD_OUT")
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		check(file != null,"Can write comparison record")
		if file != null:
			file.store_string(serialized)
			file.close()
	if OS.get_environment("REWARD_V38_BASELINE") != "1":
		check(FileAccess.file_exists(GOLDEN),"Frozen baseline oracle exists")
		if FileAccess.file_exists(GOLDEN):
			check(serialized == FileAccess.get_file_as_string(GOLDEN),"All reward outcomes, typed state, RNG, notifications, charges and saved bytes match frozen release")
		test_cache_boundaries()
	print("Reward batch v38 equivalence: %d checks, %d failures, %d cases" % [checks,failures,rows.size()])
	quit(1 if failures else 0)

func death_batch(batch: int, repetition: int, kills_before: int, fail_save: bool) -> void:
	var arena := Arena.new()
	var state := ObservedState.new()
	arena.state = state
	arena.build_save_path = "user://death-%d-%d-%d-%s.json" % [batch,repetition,kills_before,str(fail_save)]
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.rng.seed = 380037
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.telegraphs.reset()
	arena.auto_fire = false
	arena.spawn_timer = 100000.0
	arena.reward_kills = kills_before
	arena.health = 10.0
	arena.mana = 0.0
	check(arena.use_flask("flask_1").ok and arena.use_flask("flask_2").ok,"Actual flasks consume charges before root rewards")
	var notifications: Array = []
	var weak_state: WeakRef = weakref(state)
	state.changed.connect(func() -> void:
		var current: ObservedState = weak_state.get_ref()
		notifications.append([current.revision(),current.snapshot().items.keys(),current._busy]))
	for i: int in range(batch):
		var enemy: Dictionary = arena.monster_runtime.create_root("crawler",1,arena.player_pos+Vector2(80+i*3,0),"ordinary","normal",[],true)
		enemy.spawn = 0.0
		arena.enemies.append(enemy)
	state.fail_write = fail_save
	arena._begin_progress_transaction()
	for enemy: Dictionary in arena.enemies:
		arena._damage_enemy(enemy,float(enemy.health)+1.0,Color.WHITE)
	arena._end_progress_transaction()
	var row := state_record(state,arena.rng)
	row.merge({"case":"deaths","batch":batch,"repetition":repetition,"kills_before":kills_before,"failed_save":fail_save,
		"reward_kills":arena.reward_kills,"notifications":notifications,"charges":arena.flask_runtime.snapshot(),
		"attempts_before_retry":state.save_attempts,"saves_before_retry":state.successful_saves,
		"dirty_before_retry":arena._progress_save_dirty,"file_before_retry":FileAccess.get_file_as_string(arena.build_save_path) if FileAccess.file_exists(arena.build_save_path) else ""})
	check(Rules.reason(state.snapshot()).is_empty(),"Each accepted full reward candidate remains valid")
	if fail_save:
		check(state.successful_saves == 0 and arena._progress_save_dirty,"Failed batch save stays dirty with no success receipt")
		var before := fingerprint(state.snapshot())
		var rng_before := arena.rng.state
		state.fail_write = false
		check(arena._flush_progress(true),"Existing explicit flush retries a failed write")
		check(fingerprint(state.snapshot()) == before and arena.rng.state == rng_before,"Retry changes no items, UID, revision or RNG")
	row["final_save"] = FileAccess.get_file_as_string(arena.build_save_path)
	row["final_attempts"] = state.save_attempts
	row["final_saves"] = state.successful_saves
	row["final_dirty"] = arena._progress_save_dirty
	check(row.final_save == row.state,"Final disk bytes are the exact canonical memory serialization")
	rows.append(row)
	arena.queue_free()
	await process_frame

func rejection(state: ObservedState, rng: RandomNumberGenerator, label: String, action: Callable) -> void:
	var before := state_record(state,rng)
	var returned: Variant = action.call()
	var after := state_record(state,rng)
	check(returned == false if returned is bool else returned.is_empty(),label+": rejected")
	check(before.typed_state_sha256 == after.typed_state_sha256 and before.rng == after.rng,label+": no state/UID/revision/RNG mutation")
	rows.append({"case":label,"returned":returned,"after":after})

func test_rejections() -> void:
	var state := ObservedState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 380037
	for request: Array in [[0,"","current"],[31,"","current"],[1,"unknown","current"],[1,"","unknown"]]:
		rejection(state,rng,"bad-equipment-"+str(request),func() -> String: return state.award_equipment(rng,request[0],request[1],request[2]))
	rejection(state,rng,"unknown-gem",func() -> String: return state.award_gem("skill:unknown"))
	rejection(state,rng,"unknown-flask",func() -> String: return state.award_flask("flask:unknown"))
	state._busy = true
	rejection(state,rng,"busy-equipment",func() -> String: return state.award_equipment(rng,1))
	state._busy = false
	var seed_state := state.snapshot()
	for field: String in ["revision","next_item_serial"]:
		var limit := seed_state.duplicate(true)
		limit[field] = Rules.MAX_SERIAL
		state._accept_memory(limit)
		rejection(state,rng,"limit-"+field,func() -> String: return state.award_equipment(rng,1))
	state._accept_memory(seed_state)
	var duplicate: Dictionary = state.item(state.snapshot().items.keys()[0])
	rejection(state,rng,"duplicate-uid",func() -> bool: return state._admit_reward_item(duplicate))
	# Warm an exact valid value, then mutate same-UID payload without changing
	# revision. Complete-value keys must reject this rather than reuse metadata.
	var gear: Dictionary = Model.Gear.generate_for_pool(rng,"gear_005000",30,"rare","legacy")
	var wrapped: Dictionary = Items.wrap_equipment(gear)
	check(not Items.metadata_for_instance(wrapped).is_empty(),"Warm valid exact gear footprint")
	wrapped.payload.affixes[0].value = 999999
	rejection(state,rng,"same-uid-mutated-affix",func() -> bool: return state._admit_reward_item(wrapped))
	var gem := Gems.create_instance("item_005001","skill:bolt")
	check(not Items.metadata_for_instance(gem).is_empty(),"Warm exact integer payload")
	gem.payload.level = 1.0
	rejection(state,rng,"same-uid-wrong-numeric-type",func() -> bool: return state._admit_reward_item(gem))
	# Unchanged instances cannot hide a mutated candidate outside metadata.
	var invalid := seed_state.duplicate(true)
	invalid.bindings[0].keycode = KEY_C
	state._accept_memory(invalid)
	rejection(state,rng,"invalid-final-bindings",func() -> String: return state.award_equipment(rng,1))
	state._accept_memory(seed_state)
	var persisted_path := "user://invalid-persist-boundary.json"
	check(state.save_build(persisted_path) == OK,"Persist valid boundary fixture")
	var saved_bytes := FileAccess.get_file_as_bytes(persisted_path)
	var saved_attempts := state.save_attempts
	var bad_save := seed_state.duplicate(true)
	bad_save.bindings[0].keycode = KEY_C
	state._accept_memory(bad_save)
	var save_result := state.save_build(persisted_path)
	check(save_result == ERR_INVALID_DATA and state.save_attempts == saved_attempts,"Full persistence validation rejects illegal non-item candidate before write")
	check(FileAccess.get_file_as_bytes(persisted_path) == saved_bytes,"Rejected candidate leaves previous save bytes intact")
	rows.append({"case":"invalid-persistence","result":save_result,"saved_bytes":saved_bytes.hex_encode(),"after":state_record(state,rng)})
	state._accept_memory(seed_state)
	var full := seed_state.duplicate(true)
	for uid: String in full.locations.keys():
		if full.locations[uid].kind == "bag":
			full.locations.erase(uid)
			full.items.erase(uid)
	var serial := 1000
	for page: int in range(2):
		for y: int in range(10):
			for x: int in range(12):
				var uid := "item_%06d" % serial
				full.items[uid] = Gems.create_instance(uid,"skill:bolt")
				full.locations[uid] = {"kind":"bag","page":page,"x":x,"y":y}
				serial += 1
	full.next_item_serial = serial
	check(Rules.reason(full).is_empty(),"Constructed full 240-cell fixture is legal")
	state._accept_memory(full)
	rejection(state,rng,"full-bag-equipment",func() -> String: return state.award_equipment(rng,1))
	rejection(state,rng,"full-bag-jewel",func() -> String: return state.award_jewel(rng))
	rejection(state,rng,"full-bag-random-gem",func() -> String: return state.award_random_gem(rng))
	rejection(state,rng,"full-bag-flask",func() -> String: return state.award_flask("flask:life"))
	# Fragmented cells versus the actual 1x2 flask footprint.
	for vertical: bool in [false,true]:
		var fragmented := full.duplicate(true)
		for uid: String in ["item_001000","item_001012" if vertical else "item_001001"]:
			fragmented.items.erase(uid)
			fragmented.locations.erase(uid)
		state._accept_memory(fragmented)
		var awarded := state.award_flask("flask:life")
		check(awarded.is_empty() != vertical,"Flask needs vertical capacity")
		rows.append({"case":"fragmented-"+str(vertical),"awarded":awarded,"after":state_record(state,rng)})
	# Recovery and independent item ownership still gate all ordinary rewards.
	var recovery := seed_state.duplicate(true)
	var recovery_uid: String = ""
	for uid: String in recovery.locations:
		if recovery.locations[uid].kind == "bag": recovery_uid = uid; break
	recovery.locations[recovery_uid] = {"kind":"recovery","index":0}
	state._accept_memory(recovery)
	rejection(state,rng,"pending-recovery",func() -> String: return state.award_equipment(rng,1))

func test_cache_boundaries() -> void:
	# Dynamic lookup lets this same script run unchanged against the frozen
	# release, which does not contain these private implementation counters.
	var catalog: Variant = Items
	catalog._metadata_cache.clear()
	catalog._metadata_cache_order.clear()
	var good := Gems.create_instance("item_008000","skill:bolt")
	var original := good.duplicate(true)
	var metadata := Items.metadata_for_instance(good)
	var size_before: int = catalog._metadata_cache.size()
	metadata.size[0] = 999
	metadata.kind = "changed"
	check(Items.metadata_for_instance(good) == {"kind":"skill_gem","category":"","size":[1,1]},"Cached returned dictionaries and nested size arrays are detached")
	good.payload.level = 1.0
	check(Items.metadata_for_instance(good).is_empty(),"Exact typed key rejects same-UID wrong numeric type")
	check(catalog._metadata_cache.size() == size_before,"Invalid values never populate the positive cache")
	good.payload.level = 1
	check(good == original and not Items.metadata_for_instance(good).is_empty(),"Restoring the exact item reuses only its valid value")
	var support := Gems.create_instance("item_008001","support:focus")
	check(not Items.metadata_for_instance(support).is_empty(),"Warm support metadata before mutable registry membership change")
	var registry_entry: Dictionary = Gems.Supports.SUPPORTS.focus
	Gems.Supports.SUPPORTS.erase("focus")
	check(Items.metadata_for_instance(support).is_empty(),"Removed dynamic support membership invalidates the exact-value cache key")
	Gems.Supports.SUPPORTS.focus = registry_entry
	check(not Items.metadata_for_instance(support).is_empty(),"Restored support membership returns the unchanged metadata")
	var rng := RandomNumberGenerator.new()
	rng.seed = 380038
	var expected_rng := rng.state
	for serial: int in range(8100,8100+int(catalog._METADATA_CACHE_LIMIT)+5):
		var item := Gems.create_instance("item_%06d" % serial,"skill:bolt")
		check(not Items.metadata_for_instance(item).is_empty(),"Bounded-cache pressure fixture is valid")
	check(catalog._metadata_cache.size() == catalog._METADATA_CACHE_LIMIT and catalog._metadata_cache_order.size() == catalog._METADATA_CACHE_LIMIT,"Cache and FIFO remain at their fixed entry bound")
	check(not Items.metadata_for_instance(original).is_empty(),"Evicted exact values revalidate successfully")
	check(rng.state == expected_rng,"Cache traffic does not consume reward randomness")
