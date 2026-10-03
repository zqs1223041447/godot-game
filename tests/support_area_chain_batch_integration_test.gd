extends SceneTree
## Full legal nova/meteor/chain matrix through main.cast_skill.
const Model = preload("res://scripts/build_state.gd")
const Data = preload("res://scripts/game_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Registry = preload("res://scripts/combat/support_registry.gd")
const FRESH: String = "user://support_area_chain_batch_fresh.json"
const HEALTH: float = 10000.0
const EPSILON: float = 0.01
const ELIGIBLE: Dictionary = {
	"nova": ["breadth", "concentrate", "lightning_focus", "efficiency", "quickcast"],
	"meteor": ["breadth", "concentrate", "fire_focus", "efficiency", "quickcast"],
	"chain": ["chain_extension", "chain_reach", "lightning_focus", "efficiency", "quickcast"],
}
const MANA: Dictionary = {"breadth": 1.20, "concentrate": 1.20, "lightning_focus": 1.15,
	"fire_focus": 1.15, "efficiency": 0.80, "quickcast": 1.40, "chain_extension": 1.30, "chain_reach": 1.15}

class FixtureState extends "res://scripts/build_state.gd":
	func get_combat_snapshot() -> Dictionary:
		var result: Dictionary = super.get_combat_snapshot()
		# Test-only five-component source; not an obtainable equipment claim.
		# Real equipped weapons still set the base damage.
		result.added_damage.spell = {"physical": 2.0, "fire": 3.0, "cold": 5.0, "lightning": 7.0, "chaos": 1.0}
		return result

var arena: Node
var checks: int = 0
var failures: int = 0
var completed: bool = false
var row_label: String = "setup"
var rows: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("%s: %s" % [row_label, label])

func near(actual: float, expected: float, label: String) -> void:
	expect(absf(actual - expected) < 0.00001, "%s %.9f / %.9f" % [label, actual, expected])

func points(actual: Dictionary, expected: Dictionary, label: String) -> void:
	for type: String in Damage.TYPES:
		near(float(actual.get(type, 0.0)), float(expected.get(type, 0.0)), label + "/" + type)

static func combinations(ids: Array) -> Array:
	var result: Array = [[]]
	for i: int in ids.size():
		result.append([ids[i]])
		for j: int in range(i + 1, ids.size()):
			result.append([ids[i], ids[j]])
	return result

func run() -> void:
	var isolated: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	if OS.get_name() != "Linux" or not isolated.begins_with("/tmp/godot-") or not OS.get_user_data_dir().simplify_path().begins_with(isolated + "/"):
		printerr("Area/chain batch write tests require disposable Linux /tmp/godot-* XDG roots")
		quit(78)
		return
	var fresh := Model.new()
	expect(fresh.save_build() == OK and fresh.save_build(FRESH) == OK, "Guarded isolated initial saves")
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = FixtureState.new()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	for test: Callable in [_area_matrix, _chain_matrix, _chain_sparse, _chain_range_boundaries, _no_targets, _next_cast_and_live_defense]:
		completed = false
		test.call()
		expect(completed, "Case returned normally: " + test.get_method())
	expect(rows.size() == 48, "Exactly 16 nova + 16 meteor + 16 chain matrix rows")
	print("SUPPORT_AREA_CHAIN_BATCH " + JSON.stringify({"rows": rows.size(), "matrix": rows}))
	print("Support area/chain batch integration: %d checks, %d failures" % [checks, failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)

func prepare(skill: String, links: Array) -> Dictionary:
	row_label = skill + "/" + str(links)
	expect(arena.state.load_build(FRESH), "Restore complete fresh build through live model")
	arena.restart_run()
	arena.auto_fire = false
	arena.spawn_timer = 9999.0
	arena.player_pos = Vector2(700, 350)
	arena.player_facing = Vector2.RIGHT
	arena.hud.close_panel()
	expect(arena.state.slot_skill(0, skill), "Slot actual skill")
	if arena.state.get_skill_supports(skill) != links:
		expect(arena.state.set_skill_supports(skill, links), "Set actual support transaction")
	var requested: Array = links.duplicate()
	requested.sort()
	var installed: Array = arena.state.get_skill_supports(skill)
	installed.sort()
	expect(installed == requested, "All requested links installed")
	var cast: Dictionary = arena.state.get_skill_cast(skill)
	expect(cast.ok and cast.initial_count == 0, "Compiles with no initial projectile budget")
	var cost: float = float(Data.SKILLS[skill].mana)
	var cooldown: float = float(Data.SKILLS[skill].cooldown)
	for id: String in links:
		cost *= float(MANA[id])
		if id == "efficiency": cooldown *= 1.15
		if id == "quickcast": cooldown *= 0.80
	near(cast.mana, cost, "Unrounded combined mana")
	near(cast.cooldown, cooldown, "Combined resource cooldown")
	return cast

func target(at: Vector2, template: String = "crawler", born: bool = false) -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster(template, at, "ordinary", "", [])
	expect(not enemy.is_empty(), "Real catalog monster admitted")
	if enemy.is_empty(): return enemy
	enemy.health = HEALTH
	enemy.max_health = HEALTH
	enemy.shield = 9.0
	enemy.spawn = 1.0 if born else 0.0
	expect(enemy.pos == at, "Fixture positions remain inside actual arena")
	if template == "ember_guard":
		near(enemy.resistances.fire, 0.25, "Authored guard fire defense remains real")
	return enemy

func cues(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cue: Dictionary in arena.visual_cues.cues:
		if cue.kind == kind: result.append(cue)
	return result

func cast_exact(cast: Dictionary) -> void:
	var before_hits: Array = arena.damage_trace.duplicate(true)
	var before_cues: Array = arena.visual_cues.cues.duplicate(true)
	arena.mana = float(cast.mana) - 0.001
	var before_mana: float = arena.mana
	expect(not arena.cast_skill(0), "Every combination rejects just below exact mana")
	expect(arena.mana == before_mana and arena.cooldowns[cast.skill_id] == 0.0
		and arena.damage_trace == before_hits and arena.visual_cues.cues == before_cues, "Failed admission changes no payment, cooldown, hit or cue")
	arena.mana = float(cast.mana)
	expect(arena.cast_skill(0), "Actual public cast accepts exact mana")
	near(arena.mana, 0.0, "Exact compiled mana paid once")
	near(arena.cooldowns[cast.skill_id], cast.cooldown, "Compiled cooldown paid once")
	expect(arena.projectiles.is_empty() and arena.total_shots == 0, "No projectile or shot count for area/chain casts")
	before_hits = arena.damage_trace.duplicate(true)
	before_cues = arena.visual_cues.cues.duplicate(true)
	arena.mana = 100.0
	expect(not arena.cast_skill(0) and arena.mana == 100.0 and arena.damage_trace == before_hits
		and arena.visual_cues.cues == before_cues, "Cooldown rejects another cast atomically")
	near(arena.cooldowns[cast.skill_id], cast.cooldown, "Rejected repeat preserves cooldown")

func check_hit(enemy: Dictionary, before: Dictionary, packet: Dictionary, cast: Dictionary, slow: float) -> void:
	var hits: Array[Dictionary] = []
	for hit: Dictionary in arena.damage_trace:
		if hit.target_id == enemy.id: hits.append(hit)
	expect(hits.size() == 1, "Each selected identity hit exactly once")
	if hits.size() != 1: return
	var hit: Dictionary = hits[0]
	var expected: Dictionary = Damage.resolve(packet, cast.snapshot.modifiers, before.resistances)
	var raw: Dictionary = Damage.resolve(packet, cast.snapshot.modifiers)
	points(hit.components, expected.components, "Actual typed components use frozen packet plus live defenses")
	points(hit.before_defense_components, raw.components, "Pre-defense typed trace matches frozen packet")
	var prevented: Dictionary = {}
	for type: String in Damage.TYPES:
		prevented[type] = float(raw.components.get(type, 0.0)) - float(expected.components.get(type, 0.0))
	points(hit.prevented_components, prevented, "Defense applies exactly once per component")
	expect(hit.details == expected.details and hit.assembly == packet.assembly and hit.tags == packet.tags
		and hit.skill_id == cast.skill_id, "Actual hit keeps full typed modifier and assembly provenance")
	near(hit.total, expected.total, "Actual total is frozen typed sum")
	var absorbed: float = minf(float(before.shield), float(expected.total))
	near(hit.shield_spent, absorbed, "Shield pays after typed resistance")
	near(hit.health_lost, float(expected.total) - absorbed, "Trace records remaining life loss")
	near(enemy.shield, float(before.shield) - absorbed, "Actual shield settlement")
	near(enemy.health, float(before.health) - float(expected.total) + absorbed, "Actual health settlement")
	near(enemy.slow, slow, "Existing skill slow duration preserved")

func check_untouched(enemy: Dictionary, before: Dictionary) -> void:
	near(enemy.health, before.health, "Unselected life unchanged")
	near(enemy.shield, before.shield, "Unselected shield unchanged")
	near(enemy.slow, before.slow, "Unselected slow unchanged")
	for hit: Dictionary in arena.damage_trace:
		expect(hit.target_id != enemy.id, "Unselected identity absent from trace")

func check_detached(cast: Dictionary) -> void:
	var frozen: Dictionary = cast.duplicate(true)
	var old_cues: Array = arena.visual_cues.cues.duplicate(true)
	var old_trace: Array = arena.damage_trace.duplicate(true)
	expect(arena.state.equip("swift_blade"), "Actual downstream equipment change")
	var replacement: Array = ["efficiency"] if cast.support_ids.is_empty() else []
	expect(arena.state.set_skill_supports(cast.skill_id, replacement), "Actual downstream support change")
	var next: Dictionary = arena.state.get_skill_cast(cast.skill_id)
	expect(next.ok and next.snapshot.base_damage != cast.snapshot.base_damage, "Next compilation observes actual weapon change")
	expect(cast == frozen and arena.visual_cues.cues == old_cues and arena.damage_trace == old_trace,
		"Stored cast, emitted cues and settled trace remain detached from later equipment/links")

func _area_matrix() -> void:
	for skill: String in ["nova", "meteor"]:
		var registered: Array = Registry.supports_for_skill(skill)
		registered.sort()
		var eligible: Array = ELIGIBLE[skill].duplicate()
		eligible.sort()
		expect(registered == eligible and combinations(eligible).size() == 16, "Exact area eligibility and complete two-slot matrix")
		for links: Array in combinations(eligible):
			var cast: Dictionary = prepare(skill, links)
			var frozen: Dictionary = cast.duplicate(true)
			var area: float = (1.44 if links.has("breadth") else 1.0) * (0.64 if links.has("concentrate") else 1.0)
			var radius: float = (155.0 if skill == "nova" else 110.0) * sqrt(area)
			near(cast.recipe.radius, radius, "Radius takes one square root of multiplied area")
			near(cast.recipe.get("area_multiplier", 1.0), area, "Combined area multiplier")
			if links.has("breadth") and links.has("concentrate"):
				near(area, 0.9216, "Paired area product")
				near(radius, 148.8 if skill == "nova" else 105.6, "Paired fractional radius")
			var center: Vector2 = arena.player_pos
			var core: Dictionary = target(center)
			var inner: Dictionary = target(center, "ember_guard")
			inner.pos = center + Vector2(radius + float(inner.radius) - EPSILON, 0.0)
			var outside: Dictionary = target(center - Vector2(radius + 14.0 + EPSILON, 0.0))
			var born: Dictionary = target(center + Vector2(2.0, 0.0), "crawler", true)
			var corpse: Dictionary = target(center + Vector2(1.0, 0.0))
			corpse.health = 0.0
			var selected: Array[Dictionary] = [core, inner]
			# Vector2 is float32. Avoid a falsely exact fractional boundary;
			# integral radii still prove inclusive equality, every row tests epsilon.
			if absf(radius - roundf(radius)) < 0.000001:
				selected.append(target(center + Vector2(0.0, roundf(radius) + 14.0)))
			var before: Array[Dictionary] = []
			for enemy: Dictionary in selected: before.append(enemy.duplicate(true))
			var ignored: Array[Dictionary] = [outside, born, corpse]
			var ignored_before: Array[Dictionary] = []
			for enemy: Dictionary in ignored: ignored_before.append(enemy.duplicate(true))
			cast_exact(cast)
			expect(arena.damage_trace.size() == selected.size(), "Only geometrically eligible live targets hit")
			for i: int in selected.size():
				check_hit(selected[i], before[i], frozen.packets.direct, frozen, 0.6 if skill == "nova" else 0.0)
			for i: int in ignored.size(): check_untouched(ignored[i], ignored_before[i])
			var pulses: Array[Dictionary] = cues(skill)
			expect(pulses.size() == 1, "One area cue per actual cast")
			if not pulses.is_empty():
				near(pulses[0].radius, radius, "VFX radius equals exact compiled radius")
				expect(pulses[0].origin == center, "Actual pulse uses expected center")
			expect(cast == frozen, "Actual cast does not mutate held compilation")
			rows.append({"skill": skill, "supports": links, "radius": radius, "hits": selected.size(), "mana": cast.mana, "cooldown": cast.cooldown})
			check_detached(cast)
	completed = true

func chain_targets(step: float, count: int) -> Array[Dictionary]:
	arena.player_pos = Vector2(130.0, 160.0)
	var result: Array[Dictionary] = []
	for i: int in count:
		# Five across, then down and back: nearest-neighbor path inside arena.
		var column: int = i if i < 5 else 9 - i
		var row: int = 0 if i < 5 else 1
		result.append(target(Vector2(250.0 + column * step, 160.0 + row * step), "ember_guard" if i % 2 else "crawler"))
	return result

func verify_chain(cast: Dictionary, targets: Array[Dictionary], before: Array[Dictionary], count: int) -> void:
	expect(arena.damage_trace.size() == count, "Chain target count includes initial target")
	var arcs: Array[Dictionary] = cues("chain")
	expect(arcs.size() == count, "One chain cue per successful target")
	var identities: Array[int] = []
	var origin: Vector2 = arena.player_pos
	var cast_id: int = 0
	for i: int in targets.size():
		if i >= count:
			check_untouched(targets[i], before[i])
			continue
		var packet: Dictionary = cast.packets.bounces[i]
		near(packet.assembly.base_coefficient, 2.2 - i * 0.2, "Per-index intrinsic coefficient still decays")
		near(packet.assembly.added_effectiveness, 2.2 - i * 0.2, "Per-index added effectiveness still decays")
		check_hit(targets[i], before[i], packet, cast, 0.35)
		if i >= arcs.size() or i >= arena.damage_trace.size(): continue
		var hit: Dictionary = arena.damage_trace[i]
		expect(hit.target_id == targets[i].id and not identities.has(int(hit.target_id)), "Nearest valid chain order never repeats identity")
		identities.append(int(hit.target_id))
		if i == 0: cast_id = int(hit.cast_id)
		expect(cast_id > 0 and hit.cast_id == cast_id, "One shared actual chain cast identity")
		expect(arcs[i].target_id == targets[i].id and arcs[i].origin == origin and arcs[i].destination == targets[i].pos,
			"VFX arc records selected origin, endpoint and identity")
		origin = targets[i].pos

func _chain_matrix() -> void:
	var registered: Array = Registry.supports_for_skill("chain")
	registered.sort()
	var eligible: Array = ELIGIBLE.chain.duplicate()
	eligible.sort()
	expect(registered == eligible and combinations(eligible).size() == 16, "Exact chain eligibility and complete two-slot matrix")
	for links: Array in combinations(eligible):
		var cast: Dictionary = prepare("chain", links)
		var frozen: Dictionary = cast.duplicate(true)
		var count: int = 7 if links.has("chain_extension") else 5
		expect(cast.recipe.hit.bounce_count == count and cast.packets.bounces.size() == count, "Recipe and packets contain all total targets")
		near(cast.recipe.first_range, 600.0, "Every support combination preserves initial acquisition")
		near(cast.recipe.followup_range, 286.0 if links.has("chain_reach") else 220.0, "Compiled followup range")
		var targets: Array[Dictionary] = chain_targets(180.0, 8)
		var corpse: Dictionary = target(Vector2(150.0, 160.0))
		corpse.health = 0.0
		var born: Dictionary = target(Vector2(170.0, 160.0), "crawler", true)
		var ignored_before: Array[Dictionary] = [corpse.duplicate(true), born.duplicate(true)]
		var before: Array[Dictionary] = []
		for enemy: Dictionary in targets: before.append(enemy.duplicate(true))
		# Duplicate world entry is still the same identity, not another target.
		arena.enemies.append(targets[0])
		cast_exact(cast)
		verify_chain(frozen, targets, before, count)
		check_untouched(corpse, ignored_before[0])
		check_untouched(born, ignored_before[1])
		expect(cast == frozen, "Chain settlement never mutates frozen packets")
		rows.append({"skill": "chain", "supports": links, "hits": count, "first_range": cast.recipe.first_range,
			"followup_range": cast.recipe.followup_range, "mana": cast.mana, "cooldown": cast.cooldown})
		check_detached(cast)
	completed = true

func _chain_sparse() -> void:
	for links: Array in [[], ["chain_extension"], ["chain_reach"], ["chain_extension", "chain_reach"]]:
		var cast: Dictionary = prepare("chain", links)
		row_label += "/sparse250"
		var targets: Array[Dictionary] = chain_targets(250.0, 8)
		var before: Array[Dictionary] = []
		for enemy: Dictionary in targets: before.append(enemy.duplicate(true))
		cast_exact(cast)
		var count: int = (7 if links.has("chain_extension") else 5) if links.has("chain_reach") else 1
		verify_chain(cast, targets, before, count)
	completed = true

func _chain_range_boundaries() -> void:
	for links: Array in [[], ["chain_reach"], ["chain_extension", "chain_reach"]]:
		for distance: float in [599.99, 600.0, 600.01]:
			var cast: Dictionary = prepare("chain", links)
			row_label += "/first" + str(distance)
			arena.player_pos = Vector2(130.0, 200.0)
			var enemy: Dictionary = target(arena.player_pos + Vector2(distance, 0.0))
			var before: Dictionary = enemy.duplicate(true)
			cast_exact(cast)
			if distance < 600.0:
				expect(arena.damage_trace.size() == 1, "Initial acquisition just inside unchanged 600")
				check_hit(enemy, before, cast.packets.bounces[0], cast, 0.35)
			else:
				expect(arena.damage_trace.is_empty() and cues("chain").is_empty(), "Initial range preserves legacy strict comparison even with reach")
				check_untouched(enemy, before)
		var range_value: float = 286.0 if links.has("chain_reach") else 220.0
		for distance: float in [range_value - EPSILON, range_value, range_value + EPSILON]:
			var cast: Dictionary = prepare("chain", links)
			row_label += "/followup" + str(distance)
			arena.player_pos = Vector2(130.0, 200.0)
			var targets: Array[Dictionary] = [target(Vector2(250.0, 200.0)), target(Vector2(250.0 + distance, 200.0), "ember_guard")]
			var before: Array[Dictionary] = [targets[0].duplicate(true), targets[1].duplicate(true)]
			cast_exact(cast)
			verify_chain(cast, targets, before, 2 if distance < range_value else 1)
	completed = true

func _no_targets() -> void:
	for skill: String in ELIGIBLE:
		for links: Array in combinations(ELIGIBLE[skill]):
			var cast: Dictionary = prepare(skill, links)
			row_label += "/empty"
			cast_exact(cast)
			expect(arena.damage_trace.is_empty(), "Empty arena produces no phantom hit")
			var emitted: Array[Dictionary] = cues(skill)
			expect(emitted.size() == (0 if skill == "chain" else 1), "No-target cues preserve original semantics")
			if skill != "chain" and not emitted.is_empty():
				near(emitted[0].radius, cast.recipe.radius, "Empty-area VFX retains compiled radius")
				var expected_origin: Vector2 = arena.player_pos if skill == "nova" else arena.player_pos + arena.player_facing * 220.0
				expect(emitted[0].origin == expected_origin, "No-target area center or meteor fallback remains authored")
	completed = true

func _next_cast_and_live_defense() -> void:
	for skill: String in ELIGIBLE:
		var links: Array = ["chain_extension", "chain_reach"] if skill == "chain" else ["breadth", "concentrate"]
		var old: Dictionary = prepare(skill, links)
		row_label += "/successive"
		var enemy: Dictionary = target(arena.player_pos, "ember_guard")
		var before: Dictionary = enemy.duplicate(true)
		cast_exact(old)
		var packet: Dictionary = old.packets.bounces[0] if skill == "chain" else old.packets.direct
		check_hit(enemy, before, packet, old, 0.35 if skill == "chain" else 0.6 if skill == "nova" else 0.0)
		check_detached(old)
		var fresh: Dictionary = arena.state.get_skill_cast(skill)
		arena.damage_trace.clear()
		arena.visual_cues.reset()
		arena.cooldowns[skill] = 0.0
		enemy.health = HEALTH
		enemy.shield = 9.0
		enemy.slow = 0.0
		enemy.defense_stats = {"fire_resistance": 0.5}
		enemy.resistances = Defense.defense_profile(enemy.defense_stats, "monster").effective_resistances
		before = enemy.duplicate(true)
		cast_exact(fresh)
		packet = fresh.packets.bounces[0] if skill == "chain" else fresh.packets.direct
		check_hit(enemy, before, packet, fresh, 0.35 if skill == "chain" else 0.6 if skill == "nova" else 0.0)
		# Isolate current target defense from later caster equipment with the old
		# immutable packet through the existing hit consumer.
		arena.damage_trace.clear()
		enemy.health = HEALTH
		enemy.shield = 9.0
		enemy.slow = 0.0
		before = enemy.duplicate(true)
		packet = old.packets.bounces[0] if skill == "chain" else old.packets.direct
		arena._apply_damage_packet(enemy, packet, old.snapshot, Color.WHITE, 0.0)
		check_hit(enemy, before, packet, old, 0.0)
	completed = true
