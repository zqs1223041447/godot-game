extends SceneTree
## Real canonical ownership, transactions and Main key dispatch, without simulation frames.
const Model = preload("res://scripts/canonical_game_state.gd")
const Legacy = preload("res://scripts/build_state.gd")
var arena: Node
var checks := 0
var failures := 0
var dash_group := ""
var path := "user://quick-dash.json"
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func press(code: int, down: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = down; event.echo = echo
	arena._unhandled_key_input(event)
func reset() -> void:
	arena.alive = true; arena._world_mode = "normal"; arena.hud.close_panel()
	arena.player_pos = arena.ARENA.get_center(); arena.player_facing = Vector2.RIGHT
	arena.mana = arena._stats.max_mana; arena.group_cooldowns.reset(); arena.cooldowns.clear()
	arena.invulnerable = 0.0
func observed() -> Array:
	return [arena.player_pos, arena.mana, arena.invulnerable, arena.group_cooldowns.snapshot(), arena.cooldowns.duplicate(), arena.critical_runtime.checkpoint()]
func accepted_dash(code: int, label: String) -> void:
	var start: Vector2 = arena.player_pos
	var mana_before: float = arena.mana
	var cast: Dictionary = arena.state.get_group_cast(dash_group)
	press(code)
	check(arena.player_pos.distance_to(start + Vector2(175, 0)) < 0.001, label + " moves once")
	check(is_equal_approx(arena.mana, mana_before - float(cast.mana)), label + " pays once")
	check(is_equal_approx(arena.group_cooldown_remaining(dash_group), float(cast.cooldown)), label + " uses group/gem cooldown")
	check(arena.cooldowns.is_empty(), label + " creates no legacy cooldown")
func unchanged_key(code: int, label: String, down: bool = true, echo: bool = false) -> void:
	var before := observed(); press(code, down, echo)
	check(observed() == before, label)
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-quick-dash-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false; arena.enemies.clear()
	var state := Model.new(); check(state.save_build(path) == OK, "Canonical fixture saved")
	arena.state = state; arena._stats = state.get_stats()
	for group: Dictionary in state.snapshot().skill_groups:
		if state.skill_group(group.id).skill_id == "dash": dash_group = group.id
	check(not dash_group.is_empty(), "Canonical equipped dash exists")
	if dash_group.is_empty(): quit(1); return
	for code: int in [KEY_4, KEY_E, KEY_6, KEY_F1]:
		check(state.bind_group(dash_group, code, state.revision(), path).ok, "Bind dash " + str(code))
		reset(); accepted_dash(KEY_SPACE, "Space with binding " + str(code))
		unchanged_key(code, "Bound key cannot bypass Space cooldown")
		reset(); accepted_dash(code, "Bound key " + str(code))
		unchanged_key(KEY_SPACE, "Space cannot bypass bound-key cooldown")
	# Taking its key makes the equipped active row unbound; Space still means equipped dash.
	check(state.bind_group("group_000001", KEY_F1, state.revision(), path).ok, "Dash key reassigned to another row")
	reset(); accepted_dash(KEY_SPACE, "Unbound active dash")
	reset(); unchanged_key(KEY_SPACE, "Release ignored", false); unchanged_key(KEY_SPACE, "Echo ignored", true, true)
	arena.alive = false; unchanged_key(KEY_SPACE, "Dead dash rejected"); reset()
	arena.mana = 0.0; unchanged_key(KEY_SPACE, "Insufficient mana rejected"); reset()
	for panel: String in ["pause", "inventory", "skills"]:
		arena.hud.open_panel(panel); unchanged_key(KEY_SPACE, "Blocked by " + panel); reset()
	for mode: String in ["town", "map_complete"]:
		arena._world_mode = mode; unchanged_key(KEY_SPACE, "Safe mode " + mode); reset()
	# A retained eleventh row is valid canonical data but inactive at capacity ten.
	var uid: String = state.skill_group(dash_group).main_uid
	var snapshot := state.snapshot()
	snapshot.skill_groups.append({"id":"group_000011"})
	snapshot.locations[uid] = {"kind":"skill_main", "group_id":"group_000011"}
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(snapshot))
	check(state.load_build(path), "Retained inactive row loads through canonical validation")
	check(state.active_group_capacity() == 10 and not state.get_group_cast("group_000011").ok, "Eleventh row inactive, unlike unbound active row")
	reset(); unchanged_key(KEY_SPACE, "Inactive dash rejected")
	check(state.move_item(uid, state.first_bag_position(uid), state.revision(), path).ok, "Unequip dash")
	reset(); unchanged_key(KEY_SPACE, "Bag-only dash rejected")
	# Legacy fixture support keeps the prior five-slot path.
	arena.state = Legacy.new(); arena._stats = arena.state.get_stats(); reset()
	var start: Vector2 = arena.player_pos; press(KEY_SPACE)
	check(arena.player_pos.distance_to(start + Vector2(175, 0)) < 0.001 and arena.cooldowns.get("dash", 0.0) > 0.0, "Legacy fixture Space still casts dash")
	print("QUICK_DASH_BINDING checks=%d failures=%d" % [checks, failures])
	arena.queue_free(); await process_frame; quit(1 if failures else 0)
