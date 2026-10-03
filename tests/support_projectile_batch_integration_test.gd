extends SceneTree
## Batch acceptance through the actual main scene; never run against a player save.
## Stationary, high-health point targets isolate geometric hits and real settlement.
const Model = preload("res://scripts/build_state.gd")
const Registry = preload("res://scripts/combat/support_registry.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const FRESH: String = "user://support_projectile_batch_fresh.json"
const ELIGIBLE: Dictionary = {
	"tornado": ["volley", "focus", "physical_focus", "fire_focus", "efficiency", "quickcast"],
	"bolt": ["volley", "focus", "pierce", "swift_projectiles", "heavy_projectiles", "lightning_focus", "efficiency", "quickcast"],
	"frost": ["volley", "focus", "pierce", "swift_projectiles", "heavy_projectiles", "cold_focus", "lingering_chill", "efficiency", "quickcast"],
}
const PRIMARY: Dictionary = {"volley": 0.8, "focus": 1.25, "pierce": 0.85, "heavy_projectiles": 1.2, "lingering_chill": 0.9}
const TYPED: Dictionary = {"physical_focus": "physical", "fire_focus": "fire", "cold_focus": "cold", "lightning_focus": "lightning"}
const HEALTH: float = 100000.0
const RESISTANCES: Dictionary = {"physical": 0.25, "fire": 0.5, "cold": 0.2, "lightning": -0.1, "chaos": 0.1}

class CountingState extends "res://scripts/build_state.gd":
	var compile_calls: int = 0
	func get_skill_cast(skill_id: String) -> Dictionary:
		compile_calls += 1
		return super.get_skill_cast(skill_id)

var arena: Node
var checks: int = 0
var failures: int = 0
var completed: bool = false
var rows: int = 0
var row_label: String = "startup"
var counts: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _prove_isolation():
		quit(2)
		return
	if OS.get_cmdline_user_args().has("--probe-only"):
		quit(0)
		return
	var fresh := Model.new()
	_expect(fresh.save_build() == OK and fresh.save_build(FRESH) == OK, "Only proven disposable user storage receives fixtures")
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = CountingState.new()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	for test: Callable in [_all_combinations, _admission_boundaries, _typed_and_local_equipment, _frozen_travel_and_chill, _slow_movement, _phase_ledger, _return_budgets, _ineligible_tornado]:
		completed = false
		test.call()
		_expect(completed, "Case completed without a script exception: " + test.get_method())
	arena.free()
	print("SUPPORT_PROJECTILE_BATCH " + JSON.stringify({"rows": rows, "per_skill_combinations": counts}))
	print("Support projectile batch integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _prove_isolation() -> bool:
	var expected: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	var actual: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = OS.get_name() == "Linux" and expected.begins_with("/tmp/godot-") \
		and actual.begins_with(expected + "/") and actual == OS.get_user_data_dir().simplify_path()
	_expect(safe, "Before any save, user:// and OS userdir must lie below explicit disposable /tmp/godot-* XDG_DATA_HOME")
	if safe:
		print("ISOLATION PROVED: user://=" + actual)
	return safe


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL [%s]: %s" % [row_label, label])


func _near(actual: float, expected: float, label: String) -> void:
	_expect(is_finite(actual) and absf(actual - expected) < 0.0001, "%s (%.8f / %.8f)" % [label, actual, expected])


func _points(actual: Dictionary, expected: Dictionary, label: String) -> void:
	for type: String in Damage.TYPES:
		_near(float(actual.get(type, 0.0)), float(expected.get(type, 0.0)), label + "/" + type)


func _combinations(ids: Array) -> Array:
	var result: Array = [[]]
	for i: int in ids.size():
		result.append([ids[i]])
		for j: int in range(i + 1, ids.size()):
			result.append([ids[i], ids[j]])
	return result


func _prepare(skill: String, links: Array, explosion: bool = false) -> void:
	row_label = skill + "/" + str(links)
	_expect(arena.state.load_build(FRESH), "Fresh build reload preserves live state signal connections")
	arena.restart_run()
	arena.hud.close_panel()
	arena.auto_fire = false
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.spawn_timer = 99999.0
	arena.player_pos = Vector2(500, 300)
	arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 190105
	for slot: String in Model.EQUIPMENT_SLOTS:
		arena.state.unequip(slot)
	arena.state.slot_skill(0, skill)
	if not links.is_empty():
		_expect(arena.state.set_skill_supports(skill, links), "Real support transaction accepts complete row")
	if explosion:
		_expect(arena.state.equip("detonation_charm"), "Old independent explosion comes from actual equipment")
	arena.mana = 100.0
	arena.cooldowns[skill] = 0.0


func _cast() -> bool:
	arena.state.compile_calls = 0
	var accepted: bool = arena.cast_skill(0)
	_expect(arena.state.compile_calls == 1, "Real cast compiles exactly once for admission, payment and emission")
	return accepted


func _target(at: Vector2, birth: bool = false, shield: float = 0.0) -> Dictionary:
	var target: Dictionary = arena._spawn_monster("crawler", at, "ordinary", "normal", [])
	target.spawn = 1.0 if birth else 0.0
	target.radius = 0.0
	target.health = HEALTH
	target.max_health = HEALTH
	target.shield = shield
	target.resistances = RESISTANCES.duplicate()
	target.speed = 0.0
	return target


func _center() -> Dictionary:
	for shot: Dictionary in arena.projectiles:
		if absf(float(shot.velocity.y)) < 0.0001 and float(shot.velocity.x) > 0.0:
			return shot
	_expect(false, "Actual emitted carriers contain a center heading")
	return {}


func _damage_records(projectile_id: int, secondary: bool = false) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for record: Dictionary in arena.damage_trace:
		if int(record.projectile_id) == projectile_id and record.tags.has("secondary") == secondary:
			records.append(record)
	return records


func _verify_hit(target: Dictionary, shot: Dictionary, cast: Dictionary, role: String, baseline: Dictionary, links: Array, shield_before: float = 0.0) -> void:
	var records: Array[Dictionary] = _damage_records(int(shot.id))
	_expect(records.size() == 1, "Swept collision produces exactly one center primary hit")
	if records.size() != 1:
		return
	var packet: Dictionary = cast.packets[role]
	var preview_packet: Dictionary = {}
	for entry: Dictionary in Preview.entries(cast):
		if entry.packet.role == role:
			preview_packet = entry.packet
	_expect(preview_packet == packet and shot.payload == packet, "Preview and real carrier consume the exact compiled raw packet")
	var expected: Dictionary = Damage.resolve(preview_packet, cast.snapshot.modifiers, target.resistances)
	var unlinked: Dictionary = Damage.resolve(baseline.packets[role], baseline.snapshot.modifiers, target.resistances)
	var independent: Dictionary = unlinked.components.duplicate(true)
	for type: String in independent:
		for id: String in links:
			independent[type] *= float(PRIMARY.get(id, 1.0))
			if TYPED.has(id):
				independent[type] *= 1.2 if TYPED[id] == type else 0.8
	_points(records[0].components, expected.components, "Actual typed components agree with compiled preview under current defenses")
	_points(records[0].components, independent, "Independent support algebra agrees per component")
	_near(records[0].total, expected.total, "Actual hit total matches preview resolved against current resistance")
	_near(target.shield, maxf(0.0, shield_before - float(expected.total)), "Real shield settlement consumes exact resolved points")
	_near(HEALTH - float(target.health), maxf(0.0, float(expected.total) - shield_before), "Real health settlement follows shield")
	_near(target.slow, shot.slow, "Actual target receives the compiled existing slow duration")
	_expect(records[0].cast_id == shot.cast_id and records[0].skill_id == cast.skill_id, "Hit trace preserves cast and skill identity")


func _all_combinations() -> void:
	for skill: String in ELIGIBLE:
		var expected: Array = ELIGIBLE[skill].duplicate()
		expected.sort()
		var actual: Array = Registry.supports_for_skill(skill)
		actual.sort()
		_expect(actual == expected, "Exact projectile eligibility, with no skipped newly legal row")
		counts[skill] = 0
		for links: Array in _combinations(ELIGIBLE[skill]):
			_prepare(skill, links, true)
			var baseline: Dictionary = Compiler.compile_skill(skill, arena.state.get_combat_snapshot(), [])
			var cast: Dictionary = arena.state.get_skill_cast(skill)
			var frozen: Dictionary = cast.snapshot.duplicate(true)
			var protected: Dictionary = _target(Vector2(575, 300), true)
			var target: Dictionary = _target(Vector2(620, 300), false, 3.0)
			_expect(cast.ok and _cast(), "Real scene accepts legal row")
			rows += 1
			counts[skill] += 1
			_expect(arena.projectiles.size() == cast.initial_count and arena.total_shots == cast.initial_count, "Real emission equals compiled full volley count")
			_near(arena.mana, 100.0 - float(cast.mana), "Real payment uses exact combined compiled mana")
			_near(arena.cooldowns[skill], cast.cooldown, "Real cooldown uses exact combined compiled cooldown")
			var center: Dictionary = _center()
			var cast_id: int = int(center.cast_id)
			for shot: Dictionary in arena.projectiles:
				_expect(shot.snapshot == frozen and shot.cast_id == cast_id, "Every actual carrier owns the frozen snapshot and one cast identity")
				if skill != "tornado":
					_near(shot.speed, cast.recipe.speed, "Actual speed consumes combined compiled travel factor")
					# Vector2 uses float32 in standard Godot; allow two relative ULPs
					# for its length, while scalar speed/payment/settlement stay strict.
					_expect(absf(Vector2(shot.velocity).length() - float(cast.recipe.speed)) <= float(cast.recipe.speed) * 0.0000002, "Actual vector velocity uses compiled speed within float32 precision")
					_near(shot.slow, cast.recipe.slow, "Actual carrier stores compiled slow")
					_expect(shot.pierce == cast.recipe.pierce, "Actual carrier stores independent compiled pierce")
					_near(shot.range, 650.0, "Original range stays 650, including slow projectiles")
					_near(shot.lifetime, 1.7, "Original lifetime stays 1.7, including slow projectiles")
			arena._update_projectiles(120.0 / float(center.speed))
			_near(protected.health, HEALTH, "Birth-protected target takes no primary damage")
			_near(protected.slow, 0.0, "Birth-protected target receives no slow")
			_expect(arena.damage_trace.size() == 1, "Point geometry produces only the center primary hit")
			_verify_hit(target, center, cast, "parent" if skill == "tornado" else "projectile", baseline, links, 3.0)
			arena.enemies.clear()
			if skill == "tornado":
				arena._update_projectiles(0.5 - float(center.age))
				_expect(arena.projectiles.size() == int(cast.initial_count) * 3, "Supported real parents still produce exactly three actual children")
				center = _center()
				for child: Dictionary in arena.projectiles:
					_expect(child.cast_id == cast_id and child.snapshot == frozen and child.generation == 1, "All descendants preserve frozen cast identity")
				target = _target(Vector2(center.pos) + Vector2(60, 0))
				arena.damage_trace.clear()
				arena._update_projectiles(0.25)
				_verify_hit(target, center, cast, "child", baseline, links)
				arena.enemies.clear()
			# Remove live effect/support sources before a real natural flight end.
			arena.state.set_skill_supports(skill, [])
			_expect(arena.state.unequip("charm"), "Actual equipment swap removes explosion from future casts")
			_expect(center.snapshot == frozen, "Link/equipment removal cannot rewrite this in-flight snapshot")
			var remaining: float = minf((float(center.range) - float(center.distance)) / float(center.speed), float(center.lifetime) - float(center.age))
			var endpoint: Vector2 = Vector2(center.pos) + Vector2(center.velocity) * remaining
			target = _target(endpoint + Vector2(0, 65))
			target.resistances.fire = 0.75
			var birth_blast: Dictionary = _target(endpoint + Vector2(0, 60), true)
			arena.damage_trace.clear()
			arena._update_projectiles(3.0)
			var blasts: Array[Dictionary] = _damage_records(int(center.id), true)
			_expect(blasts.size() == 1, "Center carrier delivers exactly one actual independent explosion to mature target")
			var expected_blast: Dictionary = Damage.resolve(baseline.packets.secondary, baseline.snapshot.modifiers, target.resistances)
			for blast: Dictionary in blasts:
				_points(blast.components, expected_blast.components, "Independent explosion excludes every primary-only support")
				_expect(blast.cast_id == cast_id and not blast.tags.has("projectile"), "Secondary keeps old cast identity and its independent delivery tags")
			_near(birth_blast.health, HEALTH, "Natural-end secondary also respects birth protection")
			_expect(arena.projectiles.is_empty(), "Supported flight ends without hidden lifetime compensation")
			_expect(arena.event_counts.get("explosion", 0) == int(cast.initial_count) * (3 if skill == "tornado" else 1), "Every natural carrier ends with exactly one old equipment explosion")
			var events: Dictionary = arena.event_counts.duplicate(true)
			arena._update_projectiles(3.0)
			_expect(arena.event_counts == events, "Finished supported lineage cannot replay effects")
	_expect(rows == 105 and counts == {"tornado": 22, "bolt": 37, "frost": 46}, "All 105 legal zero/one/two-support scene rows completed")
	completed = true


func _admission_state() -> Dictionary:
	return {"shots": arena.projectiles.duplicate(true), "mana": arena.mana, "cooldowns": arena.cooldowns.duplicate(true),
		"total": arena.total_shots, "cast": arena.projectile_runtime.next_cast_id, "projectile": arena.projectile_runtime.next_projectile_id,
		"events": arena.event_counts.duplicate(true), "rng": arena.rng.state, "damage": arena.total_damage,
		"cues": arena.visual_cues.cues.duplicate(true), "particles": arena.particles.duplicate(true)}


func _admission_boundaries() -> void:
	for skill: String in ELIGIBLE:
		for links: Array in [["volley", "quickcast"], ["efficiency", "quickcast"]]:
			_prepare(skill, links)
			var cast: Dictionary = arena.state.get_skill_cast(skill)
			arena.mana = float(cast.mana) - 0.001
			var before: Dictionary = _admission_state()
			_expect(not _cast() and _admission_state() == before, "Fraction below compiled mana rejects before payment, cooldown, RNG, IDs or effects")
			arena.mana = float(cast.mana)
			_expect(_cast(), "Exactly compiled fractional mana admits")
			_near(arena.mana, 0.0, "Exact balance leaves no negative residue")
			before = _admission_state()
			_expect(not _cast() and _admission_state() == before, "Combined compiled cooldown prevents immediate repeat cast")
			var prototype: Dictionary = arena.projectiles.front().duplicate(true)
			arena.projectiles.clear()
			for index: int in range(arena.MAX_PROJECTILES - int(cast.initial_count) + 1):
				arena.projectiles.append(prototype.duplicate(true))
			arena.mana = 100.0
			arena.cooldowns[skill] = 0.0
			before = _admission_state()
			_expect(not _cast() and _admission_state() == before, "One missing slot rejects whole supported volley without payment or partial emission")
			arena.projectiles.pop_back()
			_expect(_cast() and arena.projectiles.size() == arena.MAX_PROJECTILES, "Exactly enough capacity admits the whole supported volley")
			_near(arena.mana, 100.0 - float(cast.mana), "Capacity-boundary admission charges compiled cost once")
	completed = true


func _install(base_id: String, affix_ids: Array) -> String:
	var id: String = "gear_%06d" % arena.state.next_equipment_id
	var affixes: Array = []
	for family: String in affix_ids:
		var tier: Dictionary = Equipment.affix_definition(family).tiers[2]
		affixes.append({"id": family, "tier": int(tier.tier), "value": int(tier.max)})
	var item: Dictionary = {"id": id, "base_id": base_id, "rarity": "rare", "item_level": 16, "affixes": affixes}
	_expect(Equipment.validate_instance(item), "Typed/local fixture is a legal catalog item with actual affix budgets")
	arena.state.equipment_instances[id] = item
	arena.state.inventory.append(id)
	arena.state.next_equipment_id += 1
	arena.state._sync_backpack()
	_expect(arena.state.equip(id), "Fixture equips through real signal and stat recomputation")
	return id


func _typed_and_local_equipment() -> void:
	for skill: String in ELIGIBLE:
		var links: Array = ["physical_focus", "fire_focus"] if skill == "tornado" else ["lightning_focus", "heavy_projectiles"] if skill == "bolt" else ["cold_focus", "lingering_chill"]
		_prepare(skill, links)
		_install("ashwood_bow" if skill == "tornado" else "runewood_focus",
			["whetstone_edge", "tempered_edge", "farweave", "coalglow", "beatlink", "wellturn"] if skill == "tornado" else
			["spell_added_cold", "spell_added_lightning", "farweave", "rimeecho", "sparkthread", "wellturn"])
		var cast: Dictionary = arena.state.get_skill_cast(skill)
		var baseline: Dictionary = Compiler.compile_skill(skill, arena.state.get_combat_snapshot(), [])
		var packet: Dictionary = cast.packets.parent if skill == "tornado" else cast.packets.projectile
		if skill == "tornado":
			_near(packet.base.physical, 18.0 * 0.6 + (4.0 + 6.0) * 1.3, "Local physical stage precedes primary-only type factors")
			_near(packet.base.fire, 18.0 * 0.4, "Local weapon points are not converted into authored fire")
		else:
			var coefficient: float = 1.6 if skill == "bolt" else 0.85
			_near(packet.base.cold, (18.0 if skill == "frost" else 0.0) * coefficient + 6.0 * coefficient, "Actual rolled cold additions use skill effectiveness")
			_near(packet.base.lightning, (18.0 if skill == "bolt" else 0.0) * coefficient + 6.0 * coefficient, "Actual rolled lightning additions use skill effectiveness")
		var target: Dictionary = _target(Vector2(620, 300), false, 4.0)
		_expect(_cast(), "Typed/local real equipment cast succeeds")
		var center: Dictionary = _center()
		arena._update_projectiles(120.0 / float(center.speed))
		_verify_hit(target, center, cast, "parent" if skill == "tornado" else "projectile", baseline, links, 4.0)
	completed = true


func _frozen_travel_and_chill() -> void:
	for skill: String in ["bolt", "frost"]:
		var old_links: Array = ["swift_projectiles", "lightning_focus"] if skill == "bolt" else ["swift_projectiles", "lingering_chill"]
		var next_links: Array = ["heavy_projectiles", "quickcast"] if skill == "bolt" else ["heavy_projectiles", "cold_focus"]
		_prepare(skill, old_links)
		var gear_id: String = _install("runewood_focus", ["spell_added_cold", "spell_added_lightning", "farweave", "rimeecho", "sparkthread", "wellturn"])
		var cast: Dictionary = arena.state.get_skill_cast(skill)
		var baseline: Dictionary = Compiler.compile_skill(skill, arena.state.get_combat_snapshot(), [])
		var target: Dictionary = _target(Vector2(850, 300))
		_expect(_cast(), "Frozen travel probe enters through actual cast")
		var center: Dictionary = _center()
		var old_id: int = int(center.cast_id)
		var frozen: Dictionary = center.snapshot.duplicate(true)
		var raw: Dictionary = center.payload.duplicate(true)
		arena._update_projectiles(0.1)
		_expect(arena.state.set_skill_supports(skill, next_links) and arena.state.unequip("weapon") and arena.state.discard_equipment(gear_id), "Real links/equipment are replaced and old rolled source discarded in flight")
		_expect(arena.state.slot_skill(1, skill), "Hotbar swap preserves existing cast")
		for shot: Dictionary in arena.projectiles:
			_expect(shot.snapshot == frozen and shot.payload == raw and shot.cast_id == old_id, "Every old carrier retains detached offense after links, gear and slot change")
			_near(shot.speed, cast.recipe.speed, "Old travel speed remains frozen")
			_near(shot.slow, cast.recipe.slow, "Old slow duration remains frozen")
		target.resistances = {"cold": 0.6, "lightning": 0.35}
		arena._update_projectiles(350.0 / float(center.speed) - 0.1)
		_verify_hit(target, center, cast, "projectile", baseline, old_links)
		arena.enemies.clear()
		arena._update_projectiles(3.0)
		arena.state.slot_skill(0, skill)
		arena.cooldowns[skill] = 0.0
		arena.mana = 100.0
		var next_cast: Dictionary = arena.state.get_skill_cast(skill)
		var next_baseline: Dictionary = Compiler.compile_skill(skill, arena.state.get_combat_snapshot(), [])
		target = _target(Vector2(620, 300))
		_expect(_cast(), "Next actual cast consumes the changed live build")
		center = _center()
		_expect(center.cast_id != old_id and center.snapshot == next_cast.snapshot and center.payload != raw, "Next cast receives fresh identity and changed offense")
		_near(center.speed, (780.0 if skill == "bolt" else 520.0) * 0.75, "Next cast uses heavy projectile speed")
		_near(center.slow, 3.0 if skill == "frost" else 0.0, "Next frost cast restores original slow duration")
		_near(arena.mana, 100.0 - float(next_cast.mana), "Next cast pays new support cost")
		_near(arena.cooldowns[skill], next_cast.cooldown, "Next cast starts new support cooldown")
		arena._update_projectiles(120.0 / float(center.speed))
		_verify_hit(target, center, next_cast, "projectile", next_baseline, next_links)
	completed = true


func _return_budgets() -> void:
	for skill: String in ["bolt", "frost"]:
		for travel: String in ["swift_projectiles", "heavy_projectiles"]:
			_prepare(skill, ["pierce", travel])
			_expect(arena.state.equip("return_mantle"), "Real equipment grants range return")
			var original: Dictionary = _target(Vector2(1100, 300))
			_expect(_cast(), "Combined travel/pierce return probe casts")
			var center: Dictionary = _center()
			var original_budget: int = int(center.pierce)
			var cast_id: int = int(center.cast_id)
			arena._update_projectiles(650.0 / float(center.speed))
			_expect(center.state == "returning" and center.pierce == original_budget - 1, "Return shares outbound-spent pierce and does not refill")
			_near(center.age, 650.0 / float(center.speed), "Changed speed changes arrival time without resetting age")
			_near(center.lifetime, 1.7, "Return never extends original lifetime")
			for x: float in [1130.0, 1060.0, 1030.0, 1000.0]:
				_target(Vector2(x, 300))
			arena._update_projectiles(0.6)
			var hits: Array[Dictionary] = _damage_records(int(center.id))
			var short_return: bool = skill == "frost" and travel == "heavy_projectiles"
			_expect(hits.size() == (1 if short_return else original_budget + 1), "Shared hit budget or original lifetime, whichever ends first, limits actual impacts")
			_expect(center.end_reason == ("lifetime_expired" if short_return else "hit_consumed"), "Heavy frost expires naturally before an unreachable return target")
			var ledger: Dictionary = {}
			for hit: Dictionary in hits:
				var key: String = "%s:%d" % [hit.phase, hit.target_id]
				_expect(not ledger.has(key) and hit.cast_id == cast_id, "No same-phase duplicate target and no return cast-identity reset")
				ledger[key] = true
			_expect(ledger.has("outbound:%d" % int(original.id)), "Original target is hit outbound")
			_expect(ledger.has("returning:%d" % int(original.id)) == not short_return, "Only lifetime-permitted return can revisit original target")
			if short_return:
				_near(center.age, 1.7, "Heavy frost is not silently given compensating flight time")
				_near(center.distance, 520.0 * 0.75 * 1.7, "Heavy frost original lifetime permits only 663 total travel units")
	completed = true


func _slow_movement() -> void:
	for links: Array in [[], ["heavy_projectiles", "lingering_chill"]]:
		_prepare("frost", links)
		var target: Dictionary = _target(Vector2(1000, 300))
		_expect(_cast(), "Slow movement probe receives a real frost collision")
		var center: Dictionary = _center()
		arena._update_projectiles(500.0 / float(center.speed))
		_near(target.slow, 4.5 if links.has("lingering_chill") else 3.0, "Real hit initializes the existing slow clock")
		# This probe alone gives the otherwise stationary fixture an authored
		# movement speed; the actual enemy update consumes its real hit slow.
		target.speed = 100.0
		target.knockback = Vector2.ZERO
		for index: int in range(5):
			var previous: Vector2 = target.pos
			arena._update_enemies(0.5)
			_near(previous.x - float(target.pos.x), 18.0, "Existing slow strength stays 0.36 during its active clock")
		var before_expiry: Vector2 = target.pos
		arena._update_enemies(0.5)
		_near(before_expiry.x - float(target.pos.x), 18.0 if links.has("lingering_chill") else 50.0, "Lingering chill actually delays full-speed movement at the original expiry")
		_near(target.slow, 1.5 if links.has("lingering_chill") else 0.0, "Actual enemy update counts down the compiled duration")
		if links.has("lingering_chill"):
			arena._update_enemies(1.0)
			before_expiry = target.pos
			arena._update_enemies(0.5)
			_near(target.slow, 0.0, "Extended slow still expires at 4.5 seconds")
			_near(before_expiry.x - float(target.pos.x), 50.0, "Expired extended slow restores original movement strength")
	completed = true


func _phase_ledger() -> void:
	for skill: String in ["bolt", "frost"]:
		_prepare(skill, ["pierce", "swift_projectiles"])
		var target: Dictionary = _target(Vector2(620, 300))
		_expect(_cast(), "Phase-ledger probe casts combined travel/pierce support")
		var center: Dictionary = _center()
		arena._update_projectiles(120.0 / float(center.speed))
		var remaining: int = int(center.pierce)
		var health: float = float(target.health)
		target.pos = Vector2(center.pos) + Vector2(20, 0)
		arena._update_projectiles(40.0 / float(center.speed))
		_expect(_damage_records(int(center.id)).size() == 1 and center.pierce == remaining and target.health == health, "Same target re-entering a later sweep cannot spend pierce or take damage twice in one phase")
	completed = true


func _ineligible_tornado() -> void:
	for id: String in ["swift_projectiles", "heavy_projectiles", "lingering_chill"]:
		_prepare("tornado", [])
		var build: Dictionary = arena.state._snapshot()
		_expect(not arena.state.set_skill_supports("tornado", [id]) and arena.state._snapshot() == build, "Tornado rejects travel/slow helper atomically: " + id)
		arena.state.skill_supports.tornado = [id] # Deliberately corrupt only this fixture.
		var before: Dictionary = _admission_state()
		_expect(not _cast() and _admission_state() == before, "Corrupt ineligible tornado fails closed before actual payment or emission")
	completed = true
