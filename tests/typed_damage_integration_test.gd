extends SceneTree
## v0.7 real-scene typed hit/loot contracts. Always use disposable XDG roots.
## Synthetic statistics isolate published formula examples; separate tests equip real rolls.
const Model = preload("res://scripts/build_state.gd")
const Data = preload("res://scripts/game_data.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const FRESH_PATH: String = "user://typed_damage_integration_fresh.json"
const EXAMPLES: Dictionary = {
	"basic": {"physical": 110.0, "fire": 20.0},
	"tornado": {"physical": 70.0, "fire": 60.0},
	"bolt": {"cold": 48.0, "lightning": 224.0},
	"frost": {"cold": 110.5, "lightning": 34.0},
	"nova": {"cold": 81.0, "lightning": 378.0},
	"meteor": {"fire": 430.0, "cold": 129.0, "lightning": 172.0},
	"chain": {"cold": 66.0, "lightning": 308.0},
}

class FixtureState extends "res://scripts/build_state.gd":
	var stat_overrides: Dictionary = {}
	var snapshot_overrides: Dictionary = {}
	func get_stats() -> Dictionary:
		var result: Dictionary = super.get_stats()
		result.merge(stat_overrides, true)
		return result
	func get_combat_snapshot() -> Dictionary:
		var result: Dictionary = super.get_combat_snapshot()
		result.merge(snapshot_overrides.duplicate(true), true)
		return result

var arena: Node
var checks: int = 0
var failures: int = 0
var _finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fresh = Model.new()
	_expect(fresh.save_build() == OK and fresh.save_build(FRESH_PATH) == OK, "Fixtures are confined to disposable user directory")
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = FixtureState.new()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	_case(_test_published_packets, "published values through actual casts and traces")
	_case(_test_zero_and_old_damage, "zero additions and original universal plus-eight")
	_case(_test_scope_and_supports, "actual typed increased and support scope")
	_case(_test_all_secondary_carriers, "every carrier excludes additions from secondary")
	_case(_test_real_equipment_and_frozen_lineage, "actual rolled gear survives split return and expiry")
	_case(_test_spell_gear_freeze, "added spell points and ailments remain frozen")
	_case(_test_admission_and_fail_closed, "payment capacity cooldown and malformed inputs")
	_case(_test_natural_expanded_loot, "natural expanded drops preserve death accounting")
	_case(_test_invalid_startup_protection, "invalid original save survives scene autosave")
	print("Typed damage integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	_finished = false
	test.call()
	_expect(_finished, "Case completes without script exception: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.0001, "%s (actual %.8f, expected %.8f)" % [label, value, expected])


func _points(actual: Dictionary, expected: Dictionary, label: String) -> void:
	for type: String in Damage.TYPES:
		_near(float(actual.get(type, 0.0)), float(expected.get(type, 0.0)), label + "/" + type)


func _reset(examples: bool = true) -> void:
	arena.state.stat_overrides.clear()
	arena.state.snapshot_overrides.clear()
	_expect(arena.state.load_build(FRESH_PATH), "Fresh state restores through live signal connection")
	arena.restart_run()
	arena.auto_fire = false
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.spawn_timer = 99999.0
	arena.player_pos = Vector2(500, 300)
	arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 7700701
	for slot: String in Model.EQUIPMENT_SLOTS:
		arena.state.unequip(slot)
	if examples:
		arena.state.stat_overrides = {"damage": 100.0, "attack_added_physical": 10.0,
			"attack_added_fire": 20.0, "spell_added_cold": 30.0, "spell_added_lightning": 40.0}
		arena.state.changed.emit()


func _enemy(position: Vector2 = Vector2(600, 300), template: String = "crawler", rarity: String = "normal") -> Dictionary:
	var result: Dictionary = arena._spawn_monster(template, position, "ordinary", rarity, [])
	if not result.is_empty():
		result.spawn = 0.0
	return result


func _target(position: Vector2 = Vector2(600, 300), clear_shots: bool = true) -> Dictionary:
	if clear_shots:
		arena.projectile_runtime.cancel_all(arena.projectiles)
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.damage_trace.clear()
	arena.event_counts.clear()
	arena.total_damage = 0.0
	var target: Dictionary = _enemy(position)
	target.radius = 0.0
	target.health = 100000.0
	target.max_health = 100000.0
	target.shield = 0.0
	target.resistances = {}
	target.speed = 0.0
	return target


func _cast(skill: String) -> Dictionary:
	if skill == "basic":
		var snapshot: Dictionary = arena.state.get_combat_snapshot()
		var packet: Dictionary = Combat.event_packet(snapshot, "basic", "projectile")
		arena.auto_fire = true
		arena.attack_timer = 0.0
		arena._update_auto_attack()
		arena.auto_fire = false
		_expect(arena.projectiles.size() == 1, "Actual basic autoattack emits one carrier")
		return {"ok": true, "snapshot": snapshot, "packets": {"projectile": packet}, "mana": 0.0}
	arena.state.slot_skill(0, skill)
	arena.cooldowns[skill] = 0.0
	arena.mana = 100.0
	var compiled: Dictionary = arena.state.get_skill_cast(skill)
	_expect(compiled.ok and arena.cast_skill(0), "Actual cast uses valid compiled skill: " + skill)
	_near(arena.mana, 100.0 - float(compiled.mana), "Actual compiled mana charged once: " + skill)
	_near(arena.cooldowns[skill], Data.SKILLS[skill].cooldown, "Typed points do not change cooldown: " + skill)
	return compiled


func _packet(compiled: Dictionary, skill: String) -> Dictionary:
	if skill == "tornado":
		return compiled.packets.parent
	if skill in ["basic", "bolt", "frost"]:
		return compiled.packets.projectile
	if skill == "chain":
		return compiled.packets.bounces[0]
	return compiled.packets.direct


func _hit(skill: String) -> Dictionary:
	var target: Dictionary = _target()
	var compiled: Dictionary = _cast(skill)
	var packet: Dictionary = _packet(compiled, skill)
	if skill in ["basic", "tornado", "bolt", "frost"]:
		for shot: Dictionary in arena.projectiles:
			_expect(shot.payload == packet, "Real carrier stores the compiled typed packet: " + skill)
		arena._update_projectiles(0.25)
	_expect(arena.damage_trace.size() == 1, "One isolated target receives exactly one event: " + skill)
	if arena.damage_trace.is_empty():
		return {}
	var record: Dictionary = arena.damage_trace[0]
	var raw: Dictionary = {}
	for detail: Dictionary in record.details:
		raw[detail.type] = detail.base
	_points(raw, packet.base, "Trace raw base equals compiled preview: " + skill)
	_expect(record.assembly == packet.assembly and record.tags == packet.tags and record.skill_id == skill,
		"Trace preserves compiled assembly and delivery identity: " + skill)
	var resolved: Dictionary = Damage.resolve(packet, compiled.snapshot.modifiers)
	_points(record.components, resolved.components, "Actual resolver agrees with preview: " + skill)
	_near(100000.0 - float(target.health), resolved.total, "Actual health loss agrees with typed resolution: " + skill)
	return record


func _test_published_packets() -> void:
	_reset()
	for skill: String in EXAMPLES:
		var record: Dictionary = _hit(skill)
		_points(record.get("components", {}), EXAMPLES[skill], "Published formula through main: " + skill)
		_expect(record.get("assembly", {}).get("stage") == "hit_base", "Actual hit records assembly stage: " + skill)
		var expected_slow: float = 3.0 if skill == "frost" else 0.6 if skill == "nova" else 0.35 if skill == "chain" else 0.0
		_near(arena.enemies[0].slow, expected_slow, "Added cold does not invent or alter a built-in slow: " + skill)
	var preview: Dictionary = arena.combat_preview()
	_points(preview.packets.parent.base, EXAMPLES.tornado, "F6 preview uses assembled parent")
	_points(preview.packets.child.base, {"physical": 49.0, "fire": 42.0}, "F6 preview uses assembled child")
	_points(preview.packets.secondary.base, {"fire": 90.0}, "F6 preview uses zero-effectiveness secondary")
	# All five actual chain applications, including independently decreasing additions.
	_target()
	for index: int in range(1, 5):
		var target: Dictionary = _enemy(Vector2(600 + index * 60, 300))
		target.health = 100000.0
		target.shield = 0.0
		target.resistances = {}
	var cast: Dictionary = _cast("chain")
	_expect(arena.damage_trace.size() == 5 and cast.packets.bounces.size() == 5, "Actual chain emits exactly five precompiled hits")
	for index: int in range(arena.damage_trace.size()):
		var coefficient: float = 2.2 - index * 0.2
		_points(arena.damage_trace[index].components, {"cold": 30.0 * coefficient, "lightning": 140.0 * coefficient}, "Actual chain bounce %d" % index)
		_expect(arena.damage_trace[index].assembly == cast.packets.bounces[index].assembly, "Chain trace retains matching bounce assembly")
	for skill: String in ["dash", "ward"]:
		_target()
		var nondamage: Dictionary = _cast(skill)
		_expect(nondamage.packets.is_empty() and arena.damage_trace.is_empty() and arena.projectiles.is_empty(), "Added points cannot manufacture damage for " + skill)
	_finished = true


func _test_zero_and_old_damage() -> void:
	_reset(false)
	var old_coefficients: Dictionary = {"basic": 1.0, "tornado": 1.0, "bolt": 1.6, "frost": 0.85, "nova": 2.7, "meteor": 4.3, "chain": 2.2}
	for skill: String in old_coefficients:
		arena.state.unequip("weapon")
		var bare: Dictionary = _hit(skill)
		_near(bare.total, 18.0 * float(old_coefficients[skill]), "Zero additions reproduce old naked hit: " + skill)
		_expect(bare.assembly.added.is_empty(), "Zero additions leave no phantom typed component: " + skill)
		_expect(arena.state.equip("ember_wand"), "Original plus-eight item equips")
		var wand: Dictionary = _hit(skill)
		_near(wand.total - bare.total, 8.0 * float(old_coefficients[skill]), "Original damage plus eight remains universal: " + skill)
	# Child and secondary also keep the original global base arithmetic.
	var bare_snapshot: Dictionary = Combat.snapshot({"damage": 18.0}, [])
	var wand_snapshot: Dictionary = arena.state.get_combat_snapshot()
	for role: String in ["child", "explosion"]:
		var coefficient: float = 0.7 if role == "child" else 0.9
		_near(Damage.resolve(Combat.tornado_packet(wand_snapshot, role), []).total - Damage.resolve(Combat.tornado_packet(bare_snapshot, role), []).total,
			8.0 * coefficient, "Old plus eight reaches " + role)
	_finished = true


func _test_scope_and_supports() -> void:
	# Independent scopes: [stat, increment, skills, eligible damage types].
	var scopes: Array = [
		["global_increased", 0.2, EXAMPLES.keys(), Damage.TYPES],
		["fire_increased", 0.7, EXAMPLES.keys(), ["fire"]],
		["cold_increased", 0.8, EXAMPLES.keys(), ["cold"]],
		["lightning_increased", 0.9, EXAMPLES.keys(), ["lightning"]],
		["spell_increased", 0.5, ["bolt", "frost", "nova", "meteor", "chain"], Damage.TYPES],
		["attack_elemental_increased", 0.6, ["basic", "tornado"], ["fire", "cold", "lightning"]],
		["projectile_increased", 0.3, ["basic", "tornado", "bolt", "frost"], Damage.TYPES],
		["area_increased", 1.0, ["nova", "meteor"], Damage.TYPES],
	]
	for scope: Array in scopes:
		_reset()
		arena.state.stat_overrides[scope[0]] = scope[1]
		arena.state.changed.emit()
		for skill: String in EXAMPLES:
			var expected: Dictionary = EXAMPLES[skill].duplicate(true)
			for type: String in expected:
				if scope[2].has(skill) and scope[3].has(type):
					expected[type] *= 1.0 + float(scope[1])
			_points(_hit(skill).components, expected, "Actual scope " + scope[0] + "/" + skill)
	for skill: String in ["tornado", "bolt", "frost"]:
		for links: Array in [["focus"], ["volley"], ["volley", "focus"], ["focus", "volley"]]:
			_reset()
			arena.state.set_skill_supports(skill, links)
			var expected: Dictionary = EXAMPLES[skill].duplicate(true)
			var factor: float = (1.25 if links.has("focus") else 1.0) * (0.8 if links.has("volley") else 1.0)
			for type: String in expected:
				expected[type] *= factor
			_points(_hit(skill).components, expected, "Support scales complete intrinsic-plus-added component: " + skill + str(links))
	_finished = true


func _test_all_secondary_carriers() -> void:
	for skill: String in ["basic", "tornado", "bolt", "frost"]:
		_reset()
		arena.state.equip("detonation_charm")
		# Keep the equipped effect while independently isolating applicable increases.
		arena.state.stat_overrides.merge({"global_increased": 0.2, "elemental_increased": 0.3, "fire_increased": 0.4,
			"spell_increased": 7.0, "attack_elemental_increased": 8.0, "projectile_increased": 9.0}, true)
		arena.state.changed.emit()
		if skill != "basic":
			arena.state.set_skill_supports(skill, ["focus", "volley"])
		var target: Dictionary = _target()
		_cast(skill)
		target.pos = Vector2(2000, 300)
		if skill == "tornado":
			arena._update_projectiles(0.5)
		var carrier: Dictionary = arena.projectiles[arena.projectiles.size() / 2]
		arena.projectiles.clear()
		arena.projectiles.append(carrier)
		# Controlled exclusive lifetime endpoint, with an actual compiled carrier.
		carrier.pos = Vector2(500, 300)
		carrier.velocity = Vector2(100, 0)
		carrier.speed = 100.0
		carrier.range = 1000.0
		carrier.distance = 0.0
		carrier.age = 0.0
		carrier.lifetime = 1.0
		carrier.radius = 0.0
		carrier.pierce = -1
		target.pos = Vector2(600, 300)
		arena.damage_trace.clear()
		arena._update_projectiles(1.0)
		_expect(arena.damage_trace.size() == 1 and arena.event_counts.get("explosion", 0) == 1, "Natural end emits one actual secondary: " + skill)
		if not arena.damage_trace.is_empty():
			var blast: Dictionary = arena.damage_trace[0]
			_points(blast.components, {"fire": 171.0}, "Only global elemental and fire affect secondary: " + skill)
			_expect(blast.tags == ["hit", "area", "secondary", "explosion"] and blast.skill_id == skill,
				"Secondary excludes attack spell projectile while retaining provenance: " + skill)
			_expect(blast.assembly.added.is_empty() and blast.assembly.added_effectiveness == 0.0 and blast.assembly.get("added_damage_sources", []).is_empty(), "Secondary excludes typed points and their sources: " + skill)
			_near(blast.details[0].base, 90.0, "Secondary raw base has no added points: " + skill)
		_near(target.slow, 0.0, "Secondary does not inherit a cold carrier slow")
		var before: Array = arena.damage_trace.duplicate(true)
		arena._update_projectiles(3.0)
		_expect(arena.damage_trace == before, "Expired secondary cannot repeat: " + skill)
	_finished = true


func _install_focus(spell: bool = false) -> String:
	var id: String = "gear_%06d" % arena.state.next_equipment_id
	var affixes: Array = [
		{"id": "spell_added_cold" if spell else "attack_added_physical", "tier": 3, "value": 6},
		{"id": "spell_added_lightning" if spell else "attack_added_fire", "tier": 3, "value": 6},
		{"id": "farweave", "tier": 3, "value": 18},
		{"id": "coalglow", "tier": 3, "value": 20},
	]
	var instance: Dictionary = {"id": id, "base_id": "runewood_focus", "rarity": "rare", "item_level": 16, "affixes": affixes}
	_expect(Catalog.validate_instance(instance), "Real expanded fixture respects prefix count, family, tier and roll ranges")
	arena.state.equipment_instances[id] = instance
	arena.state.inventory.append(id)
	arena.state.next_equipment_id += 1
	arena.state._sync_backpack()
	_expect(arena.state.equip(id), "Expanded gear enters the actual change signal/autosave path")
	return id


func _test_real_equipment_and_frozen_lineage() -> void:
	_reset(false)
	var gear: String = _install_focus()
	arena.state.equip("return_mantle")
	arena.state.equip("detonation_charm")
	arena.state.set_skill_supports("tornado", ["focus"])
	var cast: Dictionary = _cast("tornado")
	var frozen: Dictionary = cast.snapshot.duplicate(true)
	_points(cast.packets.parent.base, {"physical": 16.8, "fire": 13.2}, "Real affix integer points assemble once")
	_points(cast.packets.child.base, {"physical": 11.76, "fire": 9.24}, "Real child applies its own effectiveness")
	_expect(cast.packets.parent.assembly.added_damage_sources.size() == 2, "Real equipped source records reach compiled attack assembly")
	# Mutating a caller preview must not reach live carriers or the nested frozen map.
	cast.packets.child.base.physical = 99999.0
	cast.packets.child.assembly.added_damage_sources[0].value = 99999.0
	for slot: String in Model.EQUIPMENT_SLOTS:
		arena.state.unequip(slot)
	_expect(arena.state.discard_equipment(gear), "Source equipment can be discarded after release")
	arena.state.set_skill_supports("tornado", ["volley"])
	arena._update_projectiles(0.5)
	_expect(arena.projectiles.size() == 9 and arena.event_counts.get("split", 0) == 3, "Old cast retains three parents and nine children after build changes")
	var center: Dictionary = {}
	for child: Dictionary in arena.projectiles:
		_expect(child.snapshot == frozen, "Child retains original detached typed source and support snapshot")
		_points(child.payload.base, {"physical": 11.76, "fire": 9.24}, "Child consumes frozen assembled packet")
		if absf(float(child.velocity.y)) < 0.001 and float(child.velocity.x) > 0.0:
			center = child
	_expect(not center.is_empty(), "Center child is available for real return path")
	if center.is_empty():
		return
	var target: Dictionary = _target(Vector2(center.pos) + Vector2.RIGHT * 30.0, false)
	arena._update_projectiles(0.05)
	target.resistances = {"physical": 0.25, "fire": 0.5}
	arena._update_projectiles(0.15)
	var expected: Dictionary = {"physical": 11.76 * 1.38 * 1.25 * 0.75, "fire": 9.24 * 1.88 * 1.25 * 0.5}
	_expect(arena.damage_trace.size() == 1, "Exactly one old child hits before returning")
	if not arena.damage_trace.is_empty():
		_points(arena.damage_trace[0].components, expected, "Old typed offense uses target mitigation at impact")
	arena._update_projectiles(0.4)
	_expect(arena.event_counts.get("return_started", 0) == 9, "Original return grant survives equipment removal")
	for child: Dictionary in arena.projectiles:
		_expect(child.snapshot == frozen and child.state == "returning", "Return retains frozen packet and original source identity")
	arena._update_projectiles(0.6)
	var return_hits: int = 0
	for record: Dictionary in arena.damage_trace:
		if record.phase == "returning":
			return_hits += 1
			_points(record.components, expected, "Real return reuses original complete typed packet")
	_expect(return_hits == 1, "Typed child hits a target once per travel leg")
	target.pos = Vector2(center.pos) + Vector2(center.velocity) * (float(center.lifetime) - float(center.age))
	target.resistances.fire = 0.75
	arena.damage_trace.clear()
	arena._update_projectiles(1.0)
	var blasts: int = 0
	for record: Dictionary in arena.damage_trace:
		if record.tags.has("explosion"):
			blasts += 1
			_points(record.components, {"fire": 18.0 * 0.9 * 1.7 * 0.25}, "Frozen secondary excludes additions and support but reads live mitigation")
			_expect(record.assembly.added.is_empty() and record.assembly.get("added_damage_sources", []).is_empty(), "Frozen secondary carries no attack source record")
	_expect(blasts >= 1 and arena.projectiles.is_empty() and arena.event_counts.get("explosion", 0) == 9, "Lineage ends once with bounded nine secondary events")
	_points(_hit("tornado").components, {"physical": 18.0 * 0.6 * 0.8, "fire": 18.0 * 0.4 * 0.8}, "Next cast uses new build and volley rather than discarded additions")
	_finished = true


func _test_spell_gear_freeze() -> void:
	for skill: String in ["bolt", "frost", "nova", "meteor", "chain"]:
		_reset(false)
		var gear: String = _install_focus(true)
		var target: Dictionary = _target()
		var cast: Dictionary = _cast(skill)
		var expected: Dictionary
		match skill:
			"bolt": expected = {"cold": 9.6, "lightning": 38.4}
			"frost": expected = {"cold": 20.4, "lightning": 5.1}
			"nova": expected = {"cold": 16.2, "lightning": 64.8}
			"meteor": expected = {"fire": 77.4, "cold": 25.8, "lightning": 25.8}
			_: expected = {"cold": 13.2, "lightning": 52.8}
		var packet: Dictionary = _packet(cast, skill)
		_points(packet.base, expected, "Real spell affixes reach every spell: " + skill)
		_expect(packet.assembly.added_damage_sources.size() == 2, "Real spell assembly contains only matching source records")
		if skill in ["bolt", "frost"]:
			arena.state.unequip("weapon")
			_expect(arena.state.discard_equipment(gear), "Spell source removed during actual flight")
			arena._update_projectiles(0.25)
		_expect(arena.damage_trace.size() == 1, "One real equipped spell event reaches target")
		if not arena.damage_trace.is_empty():
			_points(arena.damage_trace[0].components, Damage.resolve(packet, cast.snapshot.modifiers).components, "Equipped spell hit retains complete frozen packet")
		_near(target.slow, 3.0 if skill == "frost" else 0.6 if skill == "nova" else 0.35 if skill == "chain" else 0.0, "Cold additions do not add an ailment: " + skill)
	_finished = true


func _test_admission_and_fail_closed() -> void:
	for skill: String in ["tornado", "bolt", "frost"]:
		_reset()
		arena.state.slot_skill(0, skill)
		arena.state.set_skill_supports(skill, ["volley", "focus"])
		var cast: Dictionary = arena.state.get_skill_cast(skill)
		arena.mana = float(cast.mana) - 0.0001
		arena.cooldowns[skill] = 0.0
		_expect(not arena.cast_skill(0) and arena.projectiles.is_empty(), "Typed skill refuses insufficient exact mana: " + skill)
		_near(arena.mana, float(cast.mana) - 0.0001, "Refusal cannot consume mana")
		_near(arena.cooldowns[skill], 0.0, "Refusal cannot start cooldown")
		for index: int in range(arena.MAX_PROJECTILES - int(cast.initial_count) + 1):
			arena.projectiles.append({"sentinel": index})
		var original: Array = arena.projectiles.duplicate(true)
		arena.mana = 100.0
		_expect(not arena.cast_skill(0) and arena.projectiles == original and arena.total_shots == 0, "Typed support volley still has all-or-none capacity admission")
		_near(arena.mana, 100.0, "Capacity refusal is free")
		_near(arena.cooldowns[skill], 0.0, "Capacity refusal starts no cooldown")
		arena.projectiles.pop_back()
		arena.mana = cast.mana
		_expect(arena.cast_skill(0) and arena.projectiles.size() == arena.MAX_PROJECTILES and arena.total_shots == cast.initial_count, "Exact remaining capacity and compiled mana admit complete typed volley")
		arena.projectiles.clear()
		_near(arena.mana, 0.0, "Exact cost charges once without rounding")
	var malformed: Array = [
		{"added_damage": {"attack": {"physical": NAN, "fire": 0.0}, "spell": {"cold": 0.0, "lightning": 0.0}}},
		{"added_damage": {"attack": {"physical": 1.0, "fire": 0.0}, "spell": {"cold": -1.0, "lightning": 0.0}}},
		{"added_damage": {"projectile": {"fire": 20.0}}},
		{"added_damage_sources": [{"item_id": "x", "affix_id": "attack_added_fire", "stat": "attack_added_fire", "scope": "spell", "damage_type": "fire", "value": 2.0}]},
		{"added_damage_sources": [{"item_id": "x", "affix_id": "spell_added_cold", "stat": "spell_added_cold", "scope": "spell", "damage_type": "cold", "value": INF}]},
		{"compiled_skill_id": "bolt", "compiled_packets": {}},
	]
	for poison: Dictionary in malformed:
		_reset()
		arena.state.snapshot_overrides = poison
		for skill: String in ["tornado", "bolt", "frost", "nova", "meteor", "chain"]:
			arena.state.slot_skill(0, skill)
			arena.mana = 100.0
			arena.cooldowns[skill] = 0.0
			_expect(not arena.cast_skill(0) and arena.projectiles.is_empty() and arena.damage_trace.is_empty(), "Malformed typed snapshot rejects before scene execution: " + skill)
			_near(arena.mana, 100.0, "Invalid compilation consumes no mana")
			_near(arena.cooldowns[skill], 0.0, "Invalid compilation starts no cooldown")
		_target()
		arena.auto_fire = true
		arena.attack_timer = 0.0
		arena._update_auto_attack()
		_expect(arena.projectiles.is_empty() and arena.total_shots == 0 and arena.attack_timer == 0.0, "Malformed typed basic fails before emission and cadence payment")
	_finished = true


func _kill(enemy: Dictionary) -> void:
	arena._damage_enemy(enemy, float(enemy.health) + float(enemy.shield) + 1.0, Color.WHITE)


func _loot() -> Dictionary:
	return {"instances": arena.state.equipment_instances.duplicate(true), "next": arena.state.next_equipment_id, "inventory": arena.state.inventory.duplicate()}


func _test_natural_expanded_loot() -> void:
	_reset(false)
	var expanded_seen: bool = false
	var legacy_seen: bool = false
	# Release each dropped item so this seeded reward exercise never hits the bag cap.
	for index: int in range(48):
		arena.reward_kills = 7
		var root_enemy: Dictionary = _enemy(Vector2(600, 300), "brute", "rare")
		var stale: Dictionary = root_enemy.duplicate(true)
		arena.enemies.append(root_enemy)
		var serial: int = arena.state.next_equipment_id
		_kill(root_enemy)
		var id: String = "gear_%06d" % serial
		_expect(arena.state.next_equipment_id == serial + 1 and arena.state.equipment_instances.size() == 1,
			"Rare root at eighth-kill boundary awards exactly one item")
		if not arena.state.equipment_instances.has(id):
			continue
		var item: Dictionary = arena.state.equipment_instances[id]
		_expect(Catalog.validate_instance(item) and item.rarity == "rare", "Natural reward is a valid forced-rare instance")
		expanded_seen = expanded_seen or item.base_id == "runewood_focus"
		legacy_seen = legacy_seen or Catalog.BASES.has(item.base_id)
		var before: Dictionary = _loot()
		_kill(root_enemy)
		_kill(stale)
		_expect(_loot() == before and arena.reward_kills == 8, "Duplicate and detached corpse cannot replay either pool reward")
		arena._flush_monster_spawns()
		_expect(arena.state.discard_equipment(id), "Seeded loot fixture frees its unequipped dropped item")
	_expect(expanded_seen and legacy_seen, "Actual root reward route reaches both legacy and expanded pools")
	arena.reward_kills = 7
	var splitter: Dictionary = _enemy(Vector2(600, 300), "splitter", "rare")
	_kill(splitter)
	arena._flush_monster_spawns()
	var before: Dictionary = _loot()
	for child: Dictionary in arena.enemies.duplicate():
		child.rarity = "rare"
		_kill(child)
	arena._flush_monster_spawns()
	_expect(_loot() == before and arena.reward_kills == 8, "Rare-looking descendants grant no typed gear or reward cadence")
	arena.start_monster_demo()
	before = _loot()
	var depth: int = 0
	while not arena.enemies.is_empty() and depth < 5:
		for enemy: Dictionary in arena.enemies.duplicate():
			_kill(enemy)
		arena._flush_monster_spawns()
		depth += 1
	_expect(arena.enemies.is_empty() and _loot() == before and arena.reward_kills == 0, "Demo roots, boss and descendants award neither pool")
	var persisted = Model.new()
	_expect(persisted.load_build() and persisted.equipment_instances == arena.state.equipment_instances and persisted.next_equipment_id == arena.state.next_equipment_id,
		"Natural mixed-pool rewards survive actual autosave exactly")
	_finished = true


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _test_invalid_startup_protection() -> void:
	var original: String = FileAccess.get_file_as_string("user://build_save.json")
	var future: Dictionary = arena.state._snapshot()
	future.version = 999
	for text: String in ["\n  { invalid original bytes \n", "\n" + JSON.stringify(future, "  ", false, true) + "\n"]:
		_expect(_write_text("user://build_save.json", text), "Invalid-startup fixture writes within disposable root")
		var protected_arena: Node = load("res://scenes/main.tscn").instantiate()
		protected_arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
		root.add_child(protected_arena)
		protected_arena.set_process(false)
		protected_arena.hud.set_process(false)
		_expect(protected_arena.hud._active_panel == "pause" and protected_arena.hud.is_blocking(), "Invalid or future original starts paused with a visible protection panel")
		_expect(not protected_arena.state.last_load_error.is_empty() and not protected_arena.state.save_block_reason().is_empty(), "Main retains diagnosed load error and same-path write guard")
		_expect(protected_arena.hud._panel_footer.text.contains("原存档已保护") and protected_arena.hud._panel_footer.tooltip_text.contains(protected_arena.state.save_block_reason()), "Save protection remains visible beyond a transient notification")
		var exit_button: Button = protected_arena.hud.find_child("ExitButton", true, false)
		_expect(exit_button != null and exit_button.text == "退出（未保存）", "Protected pause exit truthfully warns progress is unsaved")
		protected_arena.hud.notify("an unrelated transient result")
		_expect(protected_arena.hud._panel_footer.text.contains("原存档已保护"), "Unrelated notifications cannot erase persistent save warning")
		_expect(FileAccess.get_file_as_string("user://build_save.json") == text, "Startup and restart preserve original invalid bytes")
		_expect(protected_arena.state.equip("swift_blade"), "A reversible equipment change exercises real automatic-save callback")
		_expect(not protected_arena.save_build() and FileAccess.get_file_as_string("user://build_save.json") == text, "Build changes and manual scene save cannot overwrite protected original")
		_expect(protected_arena.state.save_build("user://typed_safe_copy.json") == OK and not protected_arena.state.save_block_reason().is_empty(), "Scene state can Save As without unlocking original")
		_expect(_write_text("user://build_save.json", original) and protected_arena.state.load_build(), "A valid restored original reloads successfully")
		_expect(protected_arena.state.save_block_reason().is_empty() and protected_arena.save_build(), "Successful restored load explicitly clears original write protection")
		root.remove_child(protected_arena)
		protected_arena.free()
	_finished = true
