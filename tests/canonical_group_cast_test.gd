extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
var arena: Node
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	create_timer(30.0).timeout.connect(func(): push_error("Group cast watchdog expired"); quit(1))
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.enemies.clear()
	arena.auto_fire = false
	var state: Model = arena.state
	var path: String = arena.build_save_path
	check(state.save_build(path) == OK,"fixture save")
	var source := state.snapshot()
	for id: String in ["swift_projectiles","heavy_projectiles","lingering_chill","efficiency","quickcast"]:
		var uid := ""
		for item_uid: String in source.items:
			if source.items[item_uid].definition_id == "support:"+id: uid = item_uid
		var index: int = state.skill_group("group_000002").support_ids.size()
		if not check(not uid.is_empty(),"required owned support exists"): quit(1); return
		check(state.move_item(uid,{"kind":"skill_support","group_id":"group_000002","index":index},state.revision(),path).ok,"install actual link")
	# Enter combat through the current formal map flow; town correctly rejects casts.
	if not check(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok,"formal map draft accepted"): quit(1); return
	var entry: Dictionary = arena.start_map(arena.map_draft().revision)
	if not check(entry.ok,"formal combat map entered: " + JSON.stringify(entry)): quit(1); return
	arena.enemies.clear()
	arena._stats = state.get_stats()
	arena.mana = arena._stats.max_mana
	arena.hud.close_panel()
	var recipe := state.get_group_cast("group_000002")
	if not check(recipe.get("ok",false),"five-link recipe compiles"): quit(1); return
	var mana_before: float = arena.mana
	check(arena.cast_group("group_000002"),"real five-link cast admitted")
	if not check(arena.projectiles.size() == 5,"real five projectiles created"): quit(1); return
	check(is_equal_approx(arena.mana,mana_before-recipe.mana),"same recipe mana charged")
	check(is_equal_approx(arena.group_cooldown_remaining("group_000002"),recipe.cooldown),"same recipe cooldown consumed")
	check(is_equal_approx(arena.projectiles[0].slow,recipe.recipe.slow) and is_equal_approx(arena.projectiles[0].velocity.length(),recipe.recipe.speed),"actual projectile speed and chill use five-link recipe")
	mana_before = arena.mana
	check(not arena.cast_group("group_000002") and arena.mana == mana_before,"repeat click rejected before charge")
	var uid: String = state.skill_group("group_000002").main_uid
	check(state.move_item(uid,{"kind":"skill_main","group_id":"group_000009"},state.revision(),path).ok,"same gem moved")
	check(not arena.cast_group("group_000009") and arena.mana == mana_before,"moving main gem cannot refresh cooldown")
	var fresh: String = state.award_gem("skill:frost")
	if not check(not fresh.is_empty(),"independent same-name gem obtained"): quit(1); return
	check(state.move_item(fresh,{"kind":"skill_main","group_id":"group_000010"},state.revision(),path).ok,"same-name gem separate group")
	check(arena.cast_group("group_000010"),"different gem and row have independent cooldown")
	check(state.move_item(fresh,{"kind":"skill_main","group_id":"group_000002"},state.revision(),path).ok,"fresh gem moves into cooling group")
	mana_before = arena.mana
	check(not arena.cast_group("group_000002") and arena.mana == mana_before,"group debt also survives gem swap")
	arena.group_cooldowns.advance(20.0)
	check(arena.group_cooldown_remaining("group_000002") == 0,"elapsed time expires debt")
	arena.mana = 0
	var debt_before: Dictionary = arena.group_cooldowns.snapshot()
	check(not arena.cast_group("group_000002") and arena.group_cooldowns.snapshot() == debt_before,"mana reject does not start debt")
	arena.mana = arena._stats.max_mana
	while arena.projectiles.size() < arena.MAX_PROJECTILES: arena.projectiles.append(arena.projectiles[0].duplicate(true))
	mana_before = arena.mana
	check(not arena.cast_group("group_000002") and arena.mana == mana_before and arena.group_cooldowns.snapshot() == debt_before,"capacity reject no mana or cooldown")
	arena.projectile_runtime.cancel_all(arena.projectiles)
	check(arena.cast_group("group_000002"),"admitted cast after capacity restored")
	check(state.bind_group("group_000002",KEY_F1,state.revision(),path).ok,"binding moved")
	check(arena.group_cooldown_remaining("group_000002") > 0,"binding change preserves debt")
	arena.health = 1.0
	arena.shield = 0.0
	arena.invulnerable = 0.0
	arena.hit_player_components({"physical":1000.0})
	check(not arena.alive and arena.group_cooldowns.snapshot() == {"group_debts":{},"main_uid_debts":{}},"actual player death clears debt")
	arena.restart_run()
	check(arena.alive and arena.group_cooldowns.snapshot() == {"group_debts":{},"main_uid_debts":{}},"actual restart clears debt")
	print("Canonical group cast: %d checks, %d failures" % [checks,failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok
