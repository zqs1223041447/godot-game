extends SceneTree
## v056: actual main, owned equipment UIDs and injected Godot Input events.
## Headless Input coverage is not physical-mouse, visual or Windows acceptance.
## The same external script can capture frozen v055 without changing its files.
const Model = preload("res://scripts/canonical_game_state.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Critical = preload("res://scripts/combat/critical_strike_runtime.gd")
const TEST_PATH = "user://town_test_build_save.json"
const GROUP = "group_000009"
const DUAL = ["39725", "63649", "49806", "6580", "19711", "20010", "36704"]
const MELEE_CRIT = ["50986", "47389", "42911", "40867", "476", "24865", "6741", "14056", "34400", "24914", "38664", "56460"]
var checks := 0
var failures := 0
var completed := false
var sections := {}
var report := {}
var arena: Node
var blade := ""
var bow := ""
var baseline: Array = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func near(actual: float, expected: float, label: String) -> void:
	check(is_finite(actual) and absf(actual - expected) <= maxf(1e-8, absf(expected) * 1e-9), "%s got=%.12f expected=%.12f" % [label, actual, expected])
func section(test: Callable) -> void:
	var before := checks
	completed = false
	test.call()
	check(completed, "Section completed without script exception: " + test.get_method())
	sections[test.get_method()] = checks - before

func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v056-consumers-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78); return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false); arena.hud.set_process(false)
	arena.auto_fire = false
	check(arena.enter_town_test(arena.world_context().revision).ok, "Actual explicit test-town transition selects isolated profile")
	for slot: String in arena.state.equipped_items().keys():
		check(arena.state.unequip(slot), "Real initial equipment returned to bag: " + slot)
	check(arena.start_map(arena.map_draft().revision).ok, "Actual map command enables combat")
	section(legacy_sequence)
	var capture := OS.get_environment("FORGEBLADE_BASELINE_CAPTURE")
	if not capture.is_empty():
		FileAccess.open(capture, FileAccess.WRITE).store_buffer(var_to_bytes(baseline))
	else:
		var baseline_path := OS.get_environment("FORGEBLADE_BASELINE_EXPECTED")
		if not baseline_path.is_empty():
			check(FileAccess.get_file_as_bytes(baseline_path) == var_to_bytes(baseline), "Complete short non-forgeblade main observation bytes equal frozen v055")
		for test: Callable in [prepare_blade, auto_geometry, manual_input, admission_and_capacity, simultaneous_and_switch, real_sources, lifecycle_and_reload]: section(test)
	mouse(false)
	report.merge({"checks": checks, "failures": failures, "sections": sections,
		"input_scope": "Headless Godot Input injection, actual main paths; not physical mouse or Windows visual acceptance",
		"default_attributes": "20 strength and 20 intelligence; physical melee increase 4%",
		"legacy_frames": baseline.size()})
	var output := OS.get_environment("FORGEBLADE_GAMEPLAY_REPORT")
	if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true))
	print("Forgeblade basic actual-main: %d checks, %d failures; %s" % [checks, failures, JSON.stringify(sections)])
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)

func affix(id: String) -> Dictionary:
	return {"id": id, "tier": 3, "value": int(Gear.affix_definition(id).tiers[2].max)}
func own(base: String, affixes: Array = []) -> String:
	var uid := "gear_%06d" % int(arena.state.snapshot().next_item_serial)
	var item := {"id": uid, "base_id": base, "rarity": "normal" if affixes.is_empty() else "rare", "item_level": 30, "affixes": affixes}
	check(Gear.validate_instance(item) and arena.state._admit_reward_item(Items.wrap_equipment(item)), "Admit valid actual owned UID: " + base)
	check(arena.state.save_build(TEST_PATH) == OK, "Persist coherent owned item before equip")
	return uid
func clean() -> void:
	mouse(false)
	arena.enemies.clear(); arena.projectiles.clear(); arena.pickups.clear()
	arena.damage_trace.clear(); arena.combat_trace.clear(); arena.attack_admission_trace.clear(); arena.event_counts.clear()
	arena.particles.clear(); arena.floating_text.clear()
	arena.monster_runtime = arena.MonsterLifecycle.new(); arena.projectile_runtime = arena.Projectiles.new()
	arena.leech_runtime.clear(); arena.group_cooldowns.reset(); arena.visual_cues = arena.VisualCueRuntime.new()
	arena.critical_runtime.reset(56001); arena.rng.seed = 56002
	arena.player_pos = arena.ARENA.get_center(); arena.player_facing = Vector2.RIGHT
	arena.alive = true; arena.auto_fire = false; arena.attack_timer = 0.0; arena.spawn_timer = 10000.0
	arena._stats = arena.state.get_stats(); arena._refresh_leech_caps()
	arena.health = float(arena._stats.max_health) * 0.25; arena.mana = float(arena._stats.max_mana) * 0.5
	arena.shield = 0.0; arena.invulnerable = 0.0; arena.elapsed = 0.0; arena.total_shots = 0
	arena._simulation_accumulator = 0.0; arena._autosave_timer = 0.0
	arena._geometry.configure("normal", arena.ARENA)
	while arena.hud.is_blocking(): arena.hud.close_panel()
	for id: String in arena.cooldowns: arena.cooldowns[id] = 0.0
func enemy(offset: Vector2, radius: float = 1.0) -> Dictionary:
	var value: Dictionary = arena._spawn_monster("crawler", arena.player_pos + offset, "ordinary", "", [], false)
	value.spawn = 0.0; value.health = 10000.0; value.max_health = 10000.0; value.shield = 0.0; value.max_shield = 0.0
	value.armour = 0.0; value.evasion = 0.0; value.evasion_entropy = 50.0; value.resistances = {}; value.radius = radius
	value.attack_timer = 1000.0
	return value
func mouse(pressed: bool, direction: Vector2 = Vector2.RIGHT) -> void:
	if arena == null: return
	var world: Vector2 = arena.player_pos + direction.normalized() * 100.0
	# Input injection uses physical pixels, including headless viewport stretch.
	var screen: Vector2 = root.get_screen_transform() * arena.View.world_to_screen(arena, world)
	var motion := InputEventMouseMotion.new()
	motion.position = screen; motion.global_position = screen
	Input.parse_input_event(motion)
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT; button.pressed = pressed
	button.position = screen; button.global_position = screen
	Input.parse_input_event(button)
	Input.flush_buffered_events()
func actual_manual(direction: Vector2 = Vector2.RIGHT) -> void:
	mouse(true, direction)
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "Injected mouse reaches real Godot Input state")
	var actual: Vector2 = arena.get_global_mouse_position() - arena.player_pos
	check(actual.normalized().dot(direction.normalized()) > 0.999, "Viewport injected mouse produces requested world direction actual=%s expected=%s" % [actual, direction * 100.0])
	arena._update_auto_attack()
	mouse(false, direction)
func observation() -> Dictionary:
	return {"enemies": arena.enemies.duplicate(true), "projectiles": arena.projectiles.duplicate(true),
		"damage": arena.damage_trace.duplicate(true), "combat": arena.combat_trace.duplicate(true),
		"admission": arena.attack_admission_trace.duplicate(true), "events": arena.event_counts.duplicate(true),
		"timer": arena.attack_timer, "facing": arena.player_facing, "pos": arena.player_pos,
		"health": arena.health, "mana": arena.mana, "shield": arena.shield, "shots": arena.total_shots,
		"rng": arena.rng.state, "critical": arena.critical_runtime.checkpoint(),
		"ids": [arena.projectile_runtime.next_projectile_id, arena.projectile_runtime.next_cast_id],
		"leech": arena.leech_runtime.snapshot(), "group_debt": arena.group_cooldowns.snapshot(),
		"state": arena.state.snapshot(), "save": FileAccess.get_file_as_bytes(TEST_PATH)}
func legacy_sequence() -> void:
	var fixed := ""
	for uid: String in arena.state.snapshot().items:
		if arena.state.item(uid).definition_id == "equipment:prism_bow": fixed = uid
	check(not fixed.is_empty(), "Legacy fixed bow is an actual original owned UID")
	bow = own("ashwood_bow")
	var focus := own("runewood_focus", [affix("attack_added_physical"), affix("attack_added_fire"), affix("prismedge"), affix("coalglow")])
	for entry: Array in [["unarmed", ""], ["ashwood", bow], ["runewood", focus], ["fixed", fixed]]:
		if arena.state.equipped_items().has("weapon"): check(arena.state.unequip("weapon"), "Legacy real unequip")
		if not str(entry[1]).is_empty(): check(arena.state.equip(entry[1]), "Legacy real equip " + str(entry[0]))
		clean(); arena.auto_fire = true
		enemy(Vector2(100, 0)); enemy(Vector2(200, 8))
		for frame: int in range(24):
			arena._process(1.0 / 60.0)
			baseline.append({"weapon": entry[0], "frame": frame, "observation": observation()})
		check(arena.total_shots > 0 and not arena.damage_trace.is_empty(), "Short actual legacy automatic sequence contains shot and settlement: " + str(entry[0]))
	completed = true

func prepare_blade() -> void:
	if arena.state.equipped_items().has("weapon"): check(arena.state.unequip("weapon"), "Unequip old projectile weapon")
	blade = own("forgeblade")
	check(arena.state.equip(blade), "Equip real forgeblade UID")
	clean()
	var stats: Dictionary = arena.state.get_stats()
	near(stats.strength, 20.0, "Real default strength is 20")
	near(stats.intelligence, 20.0, "Real default intelligence is 20")
	near(stats.melee_physical_increased, 0.04, "Default strength supplies four-percent melee physical")
	var cast: Dictionary = arena.state.get_basic_cast()
	check(cast.ok and cast.packets.keys() == ["direct"], "Sword basic compiles only a direct packet")
	if not cast.ok or not cast.packets.has("direct"): return
	check(cast.packets.direct.tags == ["hit", "attack", "melee"], "Sword basic has hit/attack/melee with no area/projectile")
	near(cast.packets.direct.base.physical, 22.0, "White sword raw basic B18 plus local W4")
	near(Damage.resolve(cast.packets.direct, cast.snapshot.modifiers).total, 22.0 * 1.04, "Real 20 strength contributes once after raw base")
	near(cast.recipe.radius, 60.0, "Basic reach is 60")
	near(cast.recipe.half_angle, PI / 4.0, "Basic full angle is 90 degrees")
	check(int(cast.recipe.max_targets) == 1, "Basic admits one target")
	var profile: Dictionary = arena.state.call("get_basic_attack_profile")
	check(profile.delivery == "melee" and profile.radius == 60.0 and profile.half_angle == PI / 4.0 and profile.max_targets == 1, "Lightweight basic profile matches actual compiled geometry")
	var saved_profile := var_to_bytes(profile)
	profile.radius = 999.0
	check(var_to_bytes(arena.state.call("get_basic_attack_profile")) == saved_profile, "Public basic profile is detached")
	var gem: String = arena.state.award_gem("skill:cleave")
	check(not gem.is_empty() and arena.state.move_item(gem, {"kind": "skill_main", "group_id": GROUP}, arena.state.revision(), TEST_PATH).ok, "Cleave uses real gem in existing group")
	var cleave: Dictionary = arena.state.get_group_cast(GROUP)
	near(cleave.recipe.radius, 95.0, "Cleave reach unchanged")
	near(cleave.recipe.half_angle, PI / 2.0, "Cleave full angle unchanged at 180")
	near(cleave.packets.direct.base.physical, 61.6, "Cleave retains 280-percent B plus W")
	near(cleave.mana, 12.0, "Cleave still costs 12 mana")
	near(cleave.cooldown, 1.4, "Cleave still has 1.4-second cooldown")
	completed = true

func auto_geometry() -> void:
	for row: Array in [["far", Vector2(80, 0), 1.0, false], ["near", Vector2(40, 0), 1.0, true], ["rear_reaim", Vector2(-40, 0), 1.0, true], ["large_arc_touch", Vector2(70, 0), 10.0, true], ["large_arc_outside", Vector2(70.01, 0), 10.0, false]]:
		clean(); arena.auto_fire = true
		var target := enemy(row[1], row[2]); var mana_before: float = arena.mana
		arena._update_auto_attack()
		check((arena.damage_trace.size() == 1) == row[3], "Automatic proximity/body boundary " + str(row[0]))
		check(arena.projectiles.is_empty(), "Automatic sword makes no carrier " + str(row[0]))
		check(arena.critical_runtime.events == int(row[3]) and arena.critical_runtime.draws == int(row[3]), "Automatic only genuine swing rolls critical " + str(row[0]))
		near(arena.mana, mana_before, "Automatic is free " + str(row[0]))
		near(arena.attack_timer, 1.0 / maxf(0.2, arena._stats.attack_speed) if row[3] else 0.0, "Automatic timing " + str(row[0]))
		if row[3]: check(arena.player_facing.dot((Vector2(target.pos) - arena.player_pos).normalized()) > 0.9999, "Automatic faces eligible target " + str(row[0]))
	clean(); arena.auto_fire = true
	var first := enemy(Vector2(40, 0)); var second := enemy(Vector2(0, 40))
	arena._update_auto_attack()
	check(arena.damage_trace.size() == 1 and arena.damage_trace[0].target_id == first.id and second.health == 10000.0, "Equidistant automatic targeting retains original array order and one target")
	clean(); arena.auto_fire = true
	var far_first := enemy(Vector2(55, 0)); var close_second := enemy(Vector2(30, 0))
	arena._update_auto_attack()
	check(arena.damage_trace.size() == 1 and arena.damage_trace[0].target_id == close_second.id and far_first.health == 10000.0, "Automatic attacks closest body once")
	clean(); arena.auto_fire = true
	var spawning := enemy(Vector2(10, 0)); spawning.spawn = 0.2
	var dead := enemy(Vector2(20, 0)); dead.health = 0.0
	arena._update_auto_attack()
	check(arena.critical_runtime.events == 0 and arena.attack_timer == 0.0, "Dead/birth-protected targets do not trigger auto swing")
	clean(); arena.auto_fire = true
	arena._geometry.configure("broken_ruins", arena.ARENA)
	var wall: Rect2 = arena._geometry.snapshot().walls[0]
	arena.player_pos = wall.position + Vector2(-1, 100)
	var blocked := enemy(Vector2(58, 0))
	check(not arena._terrain_visible(arena.player_pos, blocked.pos), "Wall fixture is physically occluded within basic reach")
	arena._update_auto_attack()
	check(arena.damage_trace.is_empty() and arena.critical_runtime.events == 0 and arena.attack_timer == 0.0, "Automatic cannot swing through wall")
	var visible := enemy(Vector2(-40, 0))
	arena._update_auto_attack()
	check(arena.damage_trace.size() == 1 and arena.damage_trace[0].target_id == visible.id and blocked.health == 10000.0, "Occluded target cannot displace visible close target")
	completed = true

func manual_input() -> void:
	clean()
	var mana_before: float = arena.mana
	actual_manual()
	check(arena.damage_trace.is_empty() and arena.projectiles.is_empty(), "Manual empty swing has no fabricated hit/carrier")
	check(arena.critical_runtime.events == 1 and arena.critical_runtime.draws == 1, "Manual empty swing freezes critical exactly once")
	near(arena.attack_timer, 1.0 / maxf(0.2, arena._stats.attack_speed), "Empty manual swing consumes real attack timer")
	near(arena.mana, mana_before, "Empty manual swing costs zero mana")
	var checkpoint: Dictionary = arena.critical_runtime.checkpoint()
	actual_manual()
	check(arena.critical_runtime.checkpoint() == checkpoint, "Held-click during debt cannot reroll")
	for row: Array in [["front", Vector2(40, 0), 1.0, true], ["rear", Vector2(-40, 0), 1.0, false], ["outside_cone", Vector2(0, 40), 1.0, false], ["large_edge_touch", Vector2(35, 35) + Vector2(-1, 1).normalized() * 10.0, 10.0, true], ["large_edge_outside", Vector2(35, 35) + Vector2(-1, 1).normalized() * 10.05, 10.0, false]]:
		clean(); enemy(row[1], row[2]); actual_manual()
		check((arena.damage_trace.size() == 1) == row[3], "Manual fixed mouse-facing sector " + str(row[0]))
		check(arena.player_facing.dot(Vector2.RIGHT) > 0.999 and arena.critical_runtime.events == 1, "Manual faces mouse and rolls once " + str(row[0]))
	clean(); var first := enemy(Vector2(40, 10)); var second := enemy(Vector2(40, -10))
	actual_manual()
	check(arena.damage_trace.size() == 1 and arena.damage_trace[0].target_id == first.id and second.health == 10000.0, "Manual tie preserves old actor order and cannot become cleave")
	clean(); arena._geometry.configure("broken_ruins", arena.ARENA)
	var wall: Rect2 = arena._geometry.snapshot().walls[0]
	arena.player_pos = wall.position + Vector2(-1, 100); enemy(Vector2(58, 0))
	actual_manual()
	check(arena.damage_trace.is_empty() and arena.critical_runtime.events == 1 and arena.attack_timer > 0.0, "Manual wall swing pays timer and one roll without damage")
	completed = true

func admission_and_capacity() -> void:
	clean(); arena.auto_fire = true
	var evade := enemy(Vector2(30, 0)); evade.evasion = 1000000000.0; evade.evasion_entropy = 0.0
	var other := enemy(Vector2(40, 0))
	var expected: Dictionary = arena.AttackHit.resolve(arena.state.get_basic_cast().snapshot.accuracy, evade.evasion, 0.0)
	arena._update_auto_attack()
	check(arena.damage_trace.is_empty() and other.health == 10000.0, "Evaded chosen basic does not spill into second target")
	check(arena.attack_admission_trace.size() == 1 and not arena.attack_admission_trace[0].hit, "Actual accuracy/evasion consumer records one denied hit")
	near(evade.evasion_entropy, expected.entropy, "Existing deterministic evasion entropy path preserved")
	check(arena.critical_runtime.events == 1 and arena.critical_runtime.draws == 1 and arena.attack_timer > 0.0, "Evaded genuine swing still consumes one critical event and timer")
	clean(); arena.auto_fire = true; enemy(Vector2(30, 0))
	arena.projectiles.resize(arena.MAX_PROJECTILES)
	for index: int in range(arena.MAX_PROJECTILES): arena.projectiles[index] = {"test_capacity_sentinel": index}
	var shots := var_to_bytes(arena.projectiles)
	arena._update_auto_attack()
	check(arena.damage_trace.size() == 1 and var_to_bytes(arena.projectiles) == shots, "MAX_PROJECTILES capacity cannot block or mutate melee basic")
	clean()
	for uid: String in arena.state.snapshot().items:
		if arena.state.item(uid).definition_id in ["equipment:return_mantle", "equipment:detonation_charm"]:
			check(arena.state.equip(uid), "Equip actual fixed return/explosion item")
	clean(); arena.auto_fire = true; enemy(Vector2(30, 0)); arena._update_auto_attack()
	arena._update_projectiles(2.0)
	check(arena.projectiles.is_empty() and arena.damage_trace.size() == 1 and not arena.event_counts.has("explosion") and not arena.event_counts.has("return_started"), "Fixed return/natural-end explosion effects cannot attach to direct sword basic")
	for slot: String in arena.state.equipped_items().keys():
		var uid: String = arena.state.equipped_items()[slot]
		if arena.state.item(uid).definition_id in ["equipment:return_mantle", "equipment:detonation_charm"]:
			check(arena.state.unequip(slot), "Restore exact fixed-effect UID through its canonical slot")
	check(arena.state.get_combat_snapshot().effects.is_empty(), "Temporary fixed-effect fixture is fully removed")
	completed = true

func simultaneous_and_switch() -> void:
	clean(); arena.auto_fire = true
	var first := enemy(Vector2(30, 0)); var second := enemy(Vector2(70, 0))
	arena._update_auto_attack()
	var basic_debt: float = arena.attack_timer
	var mana_before: float = arena.mana
	check(arena.cast_group(GROUP), "Independent cleave can follow basic while attack timer remains owed")
	near(arena.attack_timer, basic_debt, "Cleave does not reset basic timer")
	near(arena.mana, mana_before - 12.0, "Only cleave charges mana")
	near(arena.group_cooldown_remaining(GROUP), 1.4, "Cleave uses existing group cooldown")
	check(arena.damage_trace.size() == 3 and second.health < 10000.0 and first.health < second.health, "Basic hits one; parallel cleave reaches both with its own larger sector")
	check(arena.critical_runtime.events == 2 and arena.critical_runtime.draws == 2, "Basic and cleave have separate genuine cast rolls")
	arena.attack_timer = 0.0
	arena._update_auto_attack()
	check(arena.critical_runtime.events == 3 and arena.damage_trace.size() == 4, "Basic remains available during active cleave group cooldown")
	check(arena.state.unequip("weapon") and arena.state.equip(bow), "Switch sword to real owned bow")
	near(arena.attack_timer, basic_debt, "Sword-to-bow switch retains existing basic attack debt")
	check(arena.state.get_basic_cast().packets.has("projectile"), "New bow cast returns to projectile delivery")
	var checkpoint: Dictionary = arena.critical_runtime.checkpoint()
	arena._update_auto_attack()
	check(arena.critical_runtime.checkpoint() == checkpoint and arena.projectiles.is_empty(), "Switch cannot bypass owed basic timer")
	clean(); arena.auto_fire = true; enemy(Vector2(100, 0)); arena._update_auto_attack()
	check(arena.projectiles.size() == 1, "Real bow creates an in-flight legacy carrier")
	var frozen := var_to_bytes(arena.projectiles)
	var old_packet: Dictionary = arena.projectiles[0].payload.duplicate(true)
	var old_snapshot: Dictionary = arena.projectiles[0].snapshot.duplicate(true)
	var old_debt: float = arena.attack_timer
	check(arena.state.unequip("weapon") and arena.state.equip(blade), "Switch in-flight bow to real sword")
	near(arena.attack_timer, old_debt, "Bow-to-sword switch retains owed attack interval")
	check(var_to_bytes(arena.projectiles) == frozen, "Switch leaves complete active arrow bytes frozen")
	check(arena.state.get_basic_cast().packets.has("direct"), "Next cast changes to direct sword delivery")
	arena._update_projectiles(0.25)
	check(arena.damage_trace.size() == 1 and arena.damage_trace[0].tags.has("projectile") and not arena.damage_trace[0].tags.has("melee"), "Prior flying arrow still settles through original projectile attack")
	var expected: Dictionary = Damage.resolve(old_packet, old_snapshot.modifiers)
	var factor: float = old_snapshot.get("critical_roll", {}).get("multiplier", 1.0)
	near(arena.damage_trace[0].total, expected.total * factor, "Prior arrow damage uses launch packet and launch critical freeze")
	completed = true

func real_sources() -> void:
	clean()
	var model: Model = arena.state
	check(model.unequip("weapon"), "Remove white sword before source fixture")
	var rare := own("forgeblade", [affix("whetstone_edge"), affix("tempered_edge"), affix("deepwell"), affix("wellturn"), affix("global_critical_chance"), affix("global_critical_multiplier")])
	check(model.equip(rare), "Equip legal six-affix T3 sword UID")
	var cast: Dictionary = model.get_basic_cast()
	near(cast.packets.direct.base.physical, 31.0, "Basic consumes full local sword W13 once at 100 percent")
	near(cast.critical.primary.chance, 0.07, "Real equipment global critical chance applies")
	near(cast.critical.primary.multiplier, 1.65, "Real equipment global critical multiplier applies")
	var original := model.snapshot()
	var candidate := original.duplicate(true)
	candidate.progress.level = 119; candidate.progress.xp = 0
	candidate.talents.class_id = 4; candidate.talents.allocated = MELEE_CRIT.duplicate()
	candidate.talents.normal_points = 124 - MELEE_CRIT.size()
	check(model.Rules.reason(candidate).is_empty(), "Real connected full melee-critical source build validates")
	model._accept_memory(candidate)
	arena._on_build_changed()
	var invested: Dictionary = model.get_basic_cast()
	var source_stats: Dictionary = model.get_stats()
	check(source_stats.melee_crit_chance_increased > 0.0 and source_stats.melee_crit_multiplier_add > 0.0, "Connected source nodes produce authoritative melee critical stats")
	near(invested.critical.primary.chance, source_stats.crit_base_chance * (1.0 + source_stats.crit_chance_increased + source_stats.melee_crit_chance_increased), "Basic has global plus melee critical scope from actual nodes")
	near(invested.critical.primary.multiplier, source_stats.crit_base_multiplier + source_stats.crit_multiplier_add + source_stats.melee_crit_multiplier_add, "Actual melee multiplier joins global once")
	var captured := var_to_bytes(invested)
	model._accept_memory(original)
	arena._on_build_changed()
	check(var_to_bytes(invested) == captured and model.get_basic_cast().critical == cast.critical, "Source replacement invalidates next cache and preserves returned prior cast")
	check(model.select_class(4, model.revision(), TEST_PATH).ok, "Real class transaction selects Duelist for dual leech")
	model.add_xp(100); check(model.save_build(TEST_PATH) == OK, "Real XP budget persists")
	for node: String in DUAL: check(model.allocate_passive(node, 0, model.revision(), TEST_PATH).ok, "Real connected dual-leech transaction " + node)
	clean(); arena.auto_fire = true
	cast = model.get_basic_cast()
	near(cast.leech.health.attack_fraction, 0.004, "Actual source life leech enters basic")
	near(cast.leech.mana.attack_fraction, 0.004, "Actual source mana leech enters basic")
	var runtime := Critical.new(); var chosen := -1
	for value: int in range(56000, 57000):
		runtime.reset(value)
		if runtime.freeze(cast.snapshot).snapshot.critical_roll.critical: chosen = value; break
	check(chosen >= 0, "Real critical profile has deterministic critical sample")
	arena.critical_runtime.reset(chosen)
	var target := enemy(Vector2(30, 0)); target.armour = 80.0; target.shield = 5.0; target.max_shield = 5.0
	var life_before: float = arena.health; var mana_before: float = arena.mana
	var state_before := var_to_bytes(model.snapshot()); var save_before := FileAccess.get_file_as_bytes(TEST_PATH)
	arena._update_auto_attack()
	check(arena.damage_trace.size() == 1, "Real source/equipment automatic sword settles one hit")
	if arena.damage_trace.is_empty(): return
	var hit: Dictionary = arena.damage_trace[0]
	var raw: float = Damage.resolve(cast.packets.direct, cast.snapshot.modifiers).total * cast.critical.primary.multiplier
	var defended := raw * (1.0 - 80.0 / (80.0 + 5.0 * raw))
	near(hit.total, defended, "Actual critical sword goes through hit-size armour formula")
	near(hit.shield_spent, 5.0, "Actual sword spends shield before health")
	near(hit.leech.health, defended * 0.004, "Only actual defended loss supplies life leech")
	near(hit.leech.mana, defended * 0.004, "Only actual defended loss supplies mana leech")
	near(arena.health, life_before, "Basic leech is not instant life gain")
	near(arena.mana, mana_before, "Free basic does not instantly change mana")
	arena._advance_leech(1.0)
	near(arena.health - life_before, hit.leech.health, "Actual main advances finite life recovery")
	near(arena.mana - mana_before, hit.leech.mana, "Actual main advances finite mana recovery")
	check(var_to_bytes(model.snapshot()) == state_before and FileAccess.get_file_as_bytes(TEST_PATH) == save_before, "Basic attack and leech remain runtime-only")
	check(model.Rules.reason(model.snapshot()).is_empty(), "Post-combat canonical save remains valid")
	blade = rare
	report.real_source_hit = hit
	completed = true

func lifecycle_and_reload() -> void:
	clean(); arena.auto_fire = true; enemy(Vector2(30, 0))
	var before := observation()
	arena.hud.open_panel("inventory")
	arena._process(0.2)
	check(observation() == before, "Blocking inventory freezes real process before automatic melee")
	arena.hud.close_panel()
	arena.alive = false
	arena._process(0.2)
	var after := observation()
	check(after == before, "Dead process cannot swing, roll or advance debt")
	arena.alive = true
	arena._process(1.0 / 60.0)
	check(arena.damage_trace.size() == 1 and arena.critical_runtime.events == 1, "Resumed actual process reaches automatic melee input path")
	var cast: Dictionary = arena.state.get_basic_cast()
	var profile: Dictionary = arena.state.call("get_basic_attack_profile")
	var saved: Dictionary = arena.state.snapshot()
	check(arena.state.save_build(TEST_PATH) == OK, "Actual final source and equipment build saves")
	var loaded := Model.new()
	check(loaded.load_build(TEST_PATH), "Saved forgeblade source build reloads")
	check(loaded.snapshot() == saved and loaded.get_basic_cast() == cast and loaded.call("get_basic_attack_profile") == profile, "Save/reload preserves full state and both cached basic projections")
	check(saved.version == 34, "Basic attack introduces no new save schema")
	var count_before: int = loaded._cast_compile_count
	for index: int in range(20): loaded.call("get_basic_attack_profile")
	check(loaded._cast_compile_count == count_before, "Repeated lightweight target-profile reads do not recompile cast")
	check(arena.return_to_town(arena.world_context().revision).ok, "Actual return-to-town command succeeds")
	clean(); arena.auto_fire = true; enemy(Vector2(30, 0)); mouse(true)
	var crit_before: Dictionary = arena.critical_runtime.checkpoint()
	arena._process(0.2)
	check(arena.damage_trace.is_empty() and arena.critical_runtime.checkpoint() == crit_before and arena.attack_timer == 0.0, "Town process blocks both auto and held mouse attacks")
	mouse(false)
	completed = true
