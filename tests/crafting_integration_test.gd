extends SceneTree
const Model = preload("res://scripts/build_state.gd")
var arena: Node2D
var checks: int = 0
var failures: int = 0
var crafted_observations: int = 0
var reenter_xp: bool = false
var attempt_nested: bool = false
var nested_item: String = ""
var nested_rejected: bool = false

func _initialize() -> void: call_deferred("_run")
func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var location: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	if not location.begins_with("/tmp/godot-crafting-qa-") or OS.get_name() != "Linux" or not OS.get_user_data_dir().begins_with(location + "/"):
		quit(78)
		return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.auto_fire = false
	arena.spawn_timer = 99999.0
	arena.state.changed.connect(_observe)
	var rng := RandomNumberGenerator.new()
	rng.seed = 150150
	var target: String = arena.state.award_equipment(rng,30,"magic","local_weapon")
	var spare: String = arena.state.award_equipment(rng,30,"rare","current")
	_expect(not target.is_empty() and not spare.is_empty(), "Real scene admits normal catalog rewards")
	var quote: Dictionary = arena.state.crafting_quote("salvage",spare)
	_expect(quote.ok, "Scene-owned spare has actual salvage quote")
	var writes: int = arena.state.primary_save_attempt_count
	var refreshes: int = arena.progress_hud_refresh_count
	var autosaves: int = arena.progress_save_attempt_count
	var result: Dictionary = arena.state.execute_crafting(quote.handle,quote.source_instance)
	_expect(result.ok and arena.state.primary_save_attempt_count == writes+1, "Craft commits one primary disk write")
	_expect(arena.progress_hud_refresh_count == refreshes+1 and arena.progress_save_attempt_count == autosaves, "Craft notification refreshes once without a redundant ordinary autosave")
	_expect(not arena._progress_save_dirty and not arena._progress_save_requested and _saved(), "Complete already-saved notification leaves no false pending persistence")
	for unused: int in range(5):
		spare = arena.state.award_equipment(rng,30,"rare","current")
		quote = arena.state.crafting_quote("salvage",spare)
		_expect(quote.ok and arena.state.execute_crafting(quote.handle,quote.source_instance).ok, "Natural surplus funds calibration inside actual scene")
	var old_stats: Dictionary = arena.get_stats().duplicate(true)
	var before: Dictionary = arena.state._snapshot()
	quote = arena.state.crafting_quote("recalibrate",target)
	writes = arena.state.primary_save_attempt_count
	autosaves = arena.progress_save_attempt_count
	result = arena.state.execute_crafting(quote.handle,quote.source_instance)
	_expect(result.ok and arena.state.primary_save_attempt_count == writes+1 and arena.progress_save_attempt_count == autosaves, "Calibration also saves exactly once through real changed routing")
	_expect(arena.get_stats() == old_stats and _saved(), "Unworn calibration does not add phantom equipped stats")
	_expect(arena.state.equip(target), "Calibrated weapon equips via normal transaction")
	var definition: Dictionary = arena.state.get_item_definition(target)
	_expect(arena.state.get_combat_snapshot().weapon_profile == definition.weapon_profile, "Equipped combat input reads newly rolled local weapon authority")
	_expect(arena.state.unequip("weapon"), "Return weapon before further calibration")
	# A pending ordinary-progress save must survive a failed craft and be included
	# in the complete snapshot when the same craft succeeds after recovery.
	_expect(DirAccess.make_dir_absolute("user://build_save.json.tmp") == OK, "Only test-owned temporary destination conflicts")
	arena.state.add_xp(2)
	_expect(arena._progress_save_dirty, "Ordinary failed save remains pending")
	quote = arena.state.crafting_quote("recalibrate",target)
	before = arena.state._snapshot()
	var disk: PackedByteArray = FileAccess.get_file_as_bytes("user://build_save.json")
	result = arena.state.execute_crafting(quote.handle,quote.source_instance)
	_expect(not result.ok and result.code == "save_failed" and arena.state._snapshot() == before, "Scene crafting failure preserves all pending progress, item, wallet and sequence")
	_expect(FileAccess.get_file_as_bytes("user://build_save.json") == disk and arena._progress_save_dirty, "Failure never clears preexisting dirty progress or alters durable bytes")
	_expect(DirAccess.remove_absolute("user://build_save.json.tmp") == OK, "Remove test-owned conflict")
	result = arena.state.execute_crafting(quote.handle,quote.source_instance)
	_expect(result.ok and _saved() and not arena._progress_save_dirty and arena.state.xp == before.xp, "Recovered craft atomically saves the complete latest progress too")
	# A reentrant normal mutation after the craft has persisted must be saved
	# separately; a craft receipt can never hide a changed snapshot.
	spare = arena.state.award_equipment(rng,30,"rare","current")
	quote = arena.state.crafting_quote("salvage",spare)
	writes = arena.state.primary_save_attempt_count
	autosaves = arena.progress_save_attempt_count
	var xp: int = arena.state.xp
	reenter_xp = true
	result = arena.state.execute_crafting(quote.handle,quote.source_instance)
	_expect(result.ok and not reenter_xp and arena.state.xp == xp+1, "Observer mutation actually reenters changed during craft notification")
	_expect(arena.state.primary_save_attempt_count == writes+2 and arena.progress_save_attempt_count == autosaves+1 and _saved(), "Reentrant mutation defeats old receipt and gets its own complete save")
	nested_item = arena.state.award_equipment(rng,30,"rare","current")
	spare = arena.state.award_equipment(rng,30,"rare","current")
	quote = arena.state.crafting_quote("salvage",spare)
	var revision: int = arena.state.crafting.revision
	attempt_nested = true
	result = arena.state.execute_crafting(quote.handle,quote.source_instance)
	_expect(result.ok and nested_rejected and arena.state.inventory.has(nested_item) and arena.state.crafting.revision == revision+1, "Nested crafting request is rejected while first commit notifies")
	var persisted: Dictionary = arena.state._snapshot()
	arena.restart_run()
	_expect(arena.state._snapshot() == persisted and _saved(), "Real restart retains wallet, sequence and recalibrated ownership")
	_expect(crafted_observations >= 10, "Observers checked durable bytes during actual crafting changes")
	arena.free()
	print("Crafting integration: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _saved() -> bool:
	return FileAccess.get_file_as_string("user://build_save.json") == JSON.stringify(arena.state._snapshot(),"\t",true,true)

func _observe() -> void:
	if not arena.state.crafting_change_already_saved(): return
	crafted_observations += 1
	_expect(_saved(), "Signal observers only see complete already-durable craft states")
	if reenter_xp:
		reenter_xp = false
		arena.state.add_xp(1)
	if attempt_nested:
		attempt_nested = false
		var quote: Dictionary = arena.state.crafting_quote("salvage",nested_item)
		var result: Dictionary = arena.state.execute_crafting(quote.handle,quote.source_instance)
		nested_rejected = not result.ok and result.code == "busy"
