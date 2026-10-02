extends SceneTree
## v0.13 acceptance through real scene inventory, cast, collision and autosave paths.
## Run only with isolated XDG data/config/cache; raw values are asserted separately
## from the same-source compiler/preview/resolver agreement.
const Model = preload("res://scripts/build_state.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Grid = preload("res://scripts/item_grid_view.gd")
const Batch = preload("res://tests/fixtures/progress_batch_fixture.gd")
const FRESH: String = "user://local_weapon_scene_fresh.json"
const EQUIPPED: String = "user://local_weapon_scene_equipped.json"

class FixtureState extends "res://scripts/build_state.gd":
	var snapshot_overrides: Dictionary = {}
	func get_combat_snapshot() -> Dictionary:
		var result: Dictionary = super.get_combat_snapshot()
		result.merge(snapshot_overrides.duplicate(true), true)
		return result

var arena: Node
var checks: int = 0
var failures: int = 0
var completed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var fresh := Model.new()
	_expect(fresh.save_build() == OK and fresh.save_build(FRESH) == OK, "Scene fixtures write to disposable user storage")
	_create()
	for test: Callable in [_natural_loot, _hits_and_previews, _local_toggle_invariance,
		_frozen_basic_and_tornado, _invalid_admission, _persistence_and_ui,
		_reward_exclusions_and_capacity, _v8_scene_migration]:
		completed = false
		test.call()
		_expect(completed, "Case finishes without a script exception: " + test.get_method())
	arena.free()
	print("Local weapon integration: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _near(actual: float, expected: float, label: String) -> void:
	_expect(is_finite(actual) and absf(actual - expected) < 0.0001,
		"%s (%.8f vs %.8f)" % [label, actual, expected])

func _points(actual: Dictionary, expected: Dictionary, label: String) -> void:
	for type: String in Damage.TYPES:
		_near(float(actual.get(type, 0.0)), float(expected.get(type, 0.0)), label + "/" + type)

func _create() -> void:
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = FixtureState.new()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)

func _reset() -> void:
	arena.state.snapshot_overrides.clear()
	_expect(arena.state.load_build(FRESH), "Reset loads valid state through live scene connection")
	arena.restart_run()
	arena.hud.close_panel()
	arena.auto_fire = false
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.spawn_timer = 99999.0
	arena.player_pos = Vector2(500, 300)
	arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 1301301
	for slot: String in Model.EQUIPMENT_SLOTS:
		arena.state.unequip(slot)

func _enemy(template: String = "crawler", rarity: String = "normal", position: Vector2 = Vector2(600, 300)) -> Dictionary:
	var target: Dictionary = arena._spawn_monster(template, position, "ordinary", rarity, [])
	if not target.is_empty():
		target.spawn = 0.0
	return target

func _target(guard: bool = false, position: Vector2 = Vector2(600, 300), clear_shots: bool = true) -> Dictionary:
	if clear_shots:
		arena.projectile_runtime.cancel_all(arena.projectiles)
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.damage_trace.clear()
	var target: Dictionary = _enemy("ember_guard" if guard else "crawler", "normal", position)
	target.radius = 0.0
	target.health = 100000.0
	target.max_health = 100000.0
	target.shield = 0.0
	target.speed = 0.0
	if guard:
		_expect(target.resistances == {"fire": 0.25}, "Guard keeps current catalog fire resistance")
	else:
		target.resistances = {}
	return target

func _max_affix(id: String) -> Dictionary:
	var tier: Dictionary = Equipment.affix_definition(id).tiers[2]
	return {"id": id, "tier": tier.tier, "value": tier.max}

func _install(normal: bool = false, locals: bool = true) -> String:
	var id: String = "gear_%06d" % arena.state.next_equipment_id
	var affixes: Array = []
	if not normal:
		for family: String in ["farweave", "coalglow", "beatlink", "wellturn"]:
			affixes.append(_max_affix(family))
		if locals:
			for family: String in ["whetstone_edge", "tempered_edge"]:
				affixes.append(_max_affix(family))
	var item: Dictionary = {"id": id, "base_id": "ashwood_bow", "rarity": "normal" if normal else "rare", "item_level": 16, "affixes": affixes}
	_expect(Equipment.validate_instance(item), "Fixture is legal real bow with prefix and suffix opportunity cost")
	arena.state.equipment_instances[id] = item
	arena.state.inventory.append(id)
	arena.state.next_equipment_id += 1
	arena.state._sync_backpack()
	_expect(arena.state.equip(id), "Bow equips through normal signal and autosave")
	_expect(not arena.state._validate_snapshot(arena.state._snapshot()).is_empty(), "Equipped fixture has valid complete ownership and layout")
	return id

func _cast(skill: String) -> Dictionary:
	if skill == "basic":
		var snapshot: Dictionary = arena.state.get_combat_snapshot()
		var packet: Dictionary = Combat.event_packet(snapshot, skill, "projectile")
		arena.auto_fire = true
		arena.attack_timer = 0.0
		arena._update_auto_attack()
		arena.auto_fire = false
		_expect(arena.projectiles.size() == 1, "Real autoattack emits exactly one carrier")
		return {"ok": true, "snapshot": snapshot, "packets": {"projectile": packet}}
	arena.state.slot_skill(0, skill)
	arena.cooldowns[skill] = 0.0
	arena.mana = 100.0
	var compiled: Dictionary = arena.state.get_skill_cast(skill)
	_expect(compiled.ok and arena.cast_skill(0), "Actual skill cast succeeds: " + skill)
	_near(arena.mana, 100.0 - float(compiled.mana), "Compiled mana charged once: " + skill)
	_near(arena.cooldowns[skill], compiled.cooldown, "Compiled cooldown applies: " + skill)
	return compiled

func _packet(cast: Dictionary, skill: String) -> Dictionary:
	if skill == "tornado":
		return cast.packets.parent
	if skill in ["basic", "bolt", "frost"]:
		return cast.packets.projectile
	if skill == "chain":
		return cast.packets.bounces[0]
	return cast.packets.direct

func _hit(skill: String, guard: bool = false) -> Dictionary:
	var target: Dictionary = _target(guard)
	var cast: Dictionary = _cast(skill)
	var packet: Dictionary = _packet(cast, skill)
	if skill in ["basic", "tornado", "bolt", "frost"]:
		for projectile: Dictionary in arena.projectiles:
			_expect(projectile.payload == packet, "Carrier owns exact compiled packet: " + skill)
		arena._update_projectiles(0.25)
	_expect(arena.damage_trace.size() == 1, "Isolated actual cast produces one collision: " + skill)
	if arena.damage_trace.is_empty():
		return {}
	var hit: Dictionary = arena.damage_trace[0].duplicate(true)
	var raw: Dictionary = {}
	for detail: Dictionary in hit.details:
		raw[detail.type] = detail.base
	_points(raw, packet.base, "Live raw points agree with compiled preview: " + skill)
	_points(hit.before_defense_components, Damage.resolve(packet, cast.snapshot.modifiers).components, "Displayed unmitigated components reach real hit: " + skill)
	var resolved: Dictionary = Damage.resolve(packet, cast.snapshot.modifiers, target.resistances)
	_points(hit.components, resolved.components, "Actual target resistance applies after offense: " + skill)
	_near(100000.0 - float(target.health), resolved.total, "Actual target health matches compiler and current defense: " + skill)
	_expect(hit.assembly == packet.assembly, "Outgoing trace retains actual raw local assembly: " + skill)
	return {"hit": hit, "cast": cast, "raw": raw}

func _kill(enemy: Dictionary) -> void:
	arena._damage_enemy(enemy, float(enemy.health) + float(enemy.shield) + 1.0, Color.WHITE)

func _loot() -> Dictionary:
	return {"items": arena.state.equipment_instances.duplicate(true), "inventory": arena.state.inventory.duplicate(),
		"next": arena.state.next_equipment_id, "positions": arena.state.backpack_positions.duplicate(true)}

func _natural_loot() -> void:
	_reset()
	var bow_seen: bool = false
	var pools: Dictionary = {}
	for index: int in range(64):
		arena.enemies.clear()
		arena.reward_kills = 7
		var enemy: Dictionary = _enemy("brute", "rare")
		var stale: Dictionary = enemy.duplicate(true)
		arena.enemies.append(enemy)
		var serial: int = arena.state.next_equipment_id
		_kill(enemy)
		var id: String = "gear_%06d" % serial
		_expect(arena.reward_kills == 8 and arena.state.next_equipment_id == serial + 1 and arena.state.equipment_instances.size() == 1,
			"Current-pool rare/eighth kill overlap grants only one item despite duplicated world entry")
		if arena.state.equipment_instances.has(id):
			var item: Dictionary = arena.state.equipment_instances[id]
			_expect(Equipment.validate_instance(item) and item.rarity == "rare", "Current natural reward respects complete real item contract")
			pools[Equipment.pool_for_base(item.base_id)] = true
			if item.base_id == "ashwood_bow":
				bow_seen = true
				_expect(arena.state.equip(id), "Actually dropped local bow equips")
				_expect(arena.state.get_combat_snapshot().weapon_profile == Equipment.weapon_profile(item), "Natural bow reaches combat through item resolver")
				arena.state.unequip("weapon")
			var before: Dictionary = _loot()
			_kill(enemy)
			_kill(stale)
			_expect(_loot() == before and arena.reward_kills == 8, "Corpse and copied identity cannot replay natural reward")
			_expect(arena.state.discard_equipment(id), "Release test loot without exceeding backpack capacity")
	_expect(bow_seen and pools.size() == 4, "Actual current reward route reaches local, defense, runewood and legacy pools")
	arena.wave = 3
	var guard_seen: bool = false
	for unused: int in range(8):
		var enemy: Dictionary = arena._spawn_enemy()
		if enemy.get("template_id", "") == "ember_guard":
			guard_seen = true
			arena.reward_kills = 7
			var id: String = "gear_%06d" % arena.state.next_equipment_id
			_kill(enemy)
			_expect(arena.state.equipment_instances[id].base_id == "emberhide_vest", "Natural guard retains its forced defense reward despite current bow pool")
			_expect(arena.reward_kills == 8 and arena.state.equipment_instances.size() == 1, "Guard rare/eighth overlap remains single reward")
			break
	_expect(guard_seen, "Seeded current encounters actually admit a natural guard")
	_expect(Batch.saved_matches(arena), "Natural rewards and equipment transactions save exact scene state")
	completed = true

func _hits_and_previews() -> void:
	for normal: bool in [true, false]:
		_reset()
		var id: String = _install(normal)
		var expected_w: float = 4.0 if normal else 13.0
		_near(arena.state.get_stats().damage, 18.0, "Local weapon never changes legacy B")
		_near(arena.state.get_item_definition(id).weapon_damage.physical, expected_w, "Real normal/rare local points equal final P4 budget")
		for guard: bool in [false, true]:
			for skill: String in ["basic", "tornado"]:
				var observation: Dictionary = _hit(skill, guard)
				var expected: Dictionary = {"physical": 18.0 + expected_w} if skill == "basic" else {"physical": 10.8 + expected_w, "fire": 7.2}
				_points(observation.raw, expected, "Independent B-only distribution plus local physical: " + skill)
				_expect(observation.hit.assembly.weapon.profile == Equipment.weapon_profile(arena.state.equipment_instances[id]), "Trace owns real equipped source identity")
				_near(observation.hit.assembly.weapon.components.physical, expected_w, "Trace records resolved W before coefficient")
				_expect(observation.hit.assembly.added.is_empty(), "Local prefixes never appear as external attack points")
				if skill == "tornado":
					var preview: Dictionary = arena.combat_preview()
					_expect(preview.packets == observation.cast.packets, "F6 preview reads exact real cast packets")
					_points(preview.parent.components, observation.hit.before_defense_components, "F6 parent prediction matches raw actual offense")
					_points(preview.packets.child.base, {"physical": (10.8 + expected_w) * 0.7, "fire": 5.04}, "Child coefficient separately scales B and W")
	completed = true

func _local_toggle_invariance() -> void:
	_reset()
	var id: String = _install(false, false)
	arena.state.equip("detonation_charm")
	var stats: Dictionary = arena.state.get_stats()
	var spells: Dictionary = {}
	var secondaries: Dictionary = {}
	for skill: String in ["bolt", "frost", "nova", "meteor", "chain"]:
		spells[skill] = _hit(skill, true)
	for skill: String in ["basic", "tornado", "bolt", "frost"]:
		secondaries[skill] = _expiry_hit(skill)
	var item: Dictionary = arena.state.equipment_instances[id]
	item.affixes.append(_max_affix("whetstone_edge"))
	item.affixes.append(_max_affix("tempered_edge"))
	_expect(Equipment.validate_instance(item), "Adding local affixes remains legal six-affix rare with three prefixes")
	arena.state.changed.emit()
	_expect(arena.state.get_stats() == stats, "Same item local-affix toggle leaves every character stat and attack rate unchanged")
	for skill: String in spells:
		var changed: Dictionary = _hit(skill, true)
		_expect(changed.cast.packets == spells[skill].cast.packets, "Same real item local on/off leaves all spell packets byte-equivalent: " + skill)
		_points(changed.hit.components, spells[skill].hit.components, "Same real item local on/off leaves actual spell hit unchanged: " + skill)
	for skill: String in secondaries:
		var changed: Dictionary = _expiry_hit(skill)
		_expect(changed.assembly == secondaries[skill].assembly, "Local on/off preserves complete independent explosion assembly: " + skill)
		_points(changed.components, secondaries[skill].components, "Local on/off preserves real expiry explosion: " + skill)
	completed = true

func _expiry_hit(skill: String) -> Dictionary:
	var target: Dictionary = _target(true)
	_cast(skill)
	target.pos = Vector2(2000, 300)
	if skill == "tornado":
		arena._update_projectiles(0.5)
	var carrier: Dictionary = arena.projectiles[arena.projectiles.size() / 2]
	arena.projectiles.clear()
	arena.projectiles.append(carrier)
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
	_expect(arena.damage_trace.size() == 1, "Exclusive lifetime endpoint produces one real explosion: " + skill)
	if arena.damage_trace.is_empty():
		return {}
	var hit: Dictionary = arena.damage_trace[0].duplicate(true)
	_expect(hit.tags == ["hit", "area", "secondary", "explosion"] and not hit.assembly.has("weapon") and hit.assembly.added.is_empty(), "Secondary has neither local W nor inherited attack/projectile scope")
	_near(hit.details[0].base, 16.2, "Independent explosion uses only old B times 0.9")
	var records: Array = arena.damage_trace.duplicate(true)
	arena._update_projectiles(3.0)
	_expect(arena.damage_trace == records, "Expired explosion cannot repeat")
	return hit

func _frozen_basic_and_tornado() -> void:
	_reset()
	var gear: String = _install()
	var target: Dictionary = _target(true)
	var basic: Dictionary = _cast("basic")
	arena.state.equip("ember_wand")
	arena._update_projectiles(0.25)
	_expect(arena.damage_trace.size() == 1 and arena.damage_trace[0].assembly == basic.packets.projectile.assembly, "Basic already in flight retains its local bow after fixed-weapon swap")
	_points(arena.damage_trace[0].components, Damage.resolve(basic.packets.projectile, basic.snapshot.modifiers, target.resistances).components, "Actual frozen basic uses original W and offense")
	var next: Dictionary = _hit("basic")
	_expect(not next.hit.assembly.has("weapon") and next.raw == {"physical": 26.0}, "Independent new basic uses newly equipped legacy weapon")
	arena.state.equip(gear)
	arena.state.equip("return_mantle")
	arena.state.equip("detonation_charm")
	arena.state.set_skill_supports("tornado", ["focus"])
	_target(false, Vector2(2000, 300))
	var cast: Dictionary = _cast("tornado")
	var frozen: Dictionary = cast.snapshot.duplicate(true)
	var parent: Dictionary = cast.packets.parent.duplicate(true)
	var child_packet: Dictionary = cast.packets.child.duplicate(true)
	var secondary: Dictionary = cast.packets.secondary.duplicate(true)
	# A legal later roll, then a gear swap, must not mutate any released carrier.
	for affix: Dictionary in arena.state.equipment_instances[gear].affixes:
		if affix.id == "whetstone_edge": affix.value = 5
		if affix.id == "tempered_edge": affix.value = 23
	_expect(Equipment.validate_instance(arena.state.equipment_instances[gear]), "Later local rolls remain legitimate T3 values")
	arena.state.changed.emit()
	_near(arena.state.get_item_definition(gear).weapon_damage.physical, 11.07, "Independent later build resolves its changed local rolls")
	cast.snapshot.weapon_profile.flat.physical = 99999.0
	cast.packets.child.assembly.weapon.profile.sources.clear()
	target = _target(true, Vector2(600, 300), false)
	arena._update_projectiles(0.25)
	_expect(arena.damage_trace.size() == 1 and arena.damage_trace[0].assembly == parent.assembly, "Actual mother hit remains frozen after legal source roll change and preview mutation")
	target.pos = Vector2(2000, 300)
	for slot: String in Model.EQUIPMENT_SLOTS:
		arena.state.unequip(slot)
	arena.state.set_skill_supports("tornado", ["volley"])
	arena._update_projectiles(0.25)
	_expect(arena.projectiles.size() == 9 and arena.event_counts.get("split", 0) == 3, "Original three parents yield nine children despite midflight equipment and support changes")
	var center: Dictionary = {}
	for child: Dictionary in arena.projectiles:
		_expect(child.snapshot == frozen and child.payload == child_packet, "Child preserves raw profile, provenance, modifiers and original compiled packet")
		if absf(float(child.velocity.y)) < 0.001 and float(child.velocity.x) > 0.0:
			center = child
	_expect(not center.is_empty(), "Center child exists for actual outward and return collision")
	if center.is_empty(): return
	target = _target(true, Vector2(center.pos) + Vector2.RIGHT * 30.0, false)
	arena._update_projectiles(0.05)
	target.resistances = {"physical": 0.25, "fire": 0.5}
	arena._update_projectiles(0.15)
	var expected: Dictionary = Damage.resolve(child_packet, frozen.modifiers, target.resistances)
	_expect(arena.damage_trace.size() == 1, "Exactly one original child hits before return")
	_points(arena.damage_trace[0].components, expected.components, "Frozen offense reads target resistance at actual impact")
	_expect(arena.damage_trace[0].assembly == child_packet.assembly, "Actual child trace preserves original local source roll")
	arena._update_projectiles(0.4)
	_expect(arena.event_counts.get("return_started", 0) == 9, "Original return effect survives unequipping")
	for child: Dictionary in arena.projectiles:
		_expect(child.snapshot == frozen and child.payload == child_packet and child.state == "returning", "Return starts with original packet and unchanged lifetime snapshot")
	arena._update_projectiles(0.6)
	var returning: int = 0
	for record: Dictionary in arena.damage_trace:
		if record.phase == "returning":
			returning += 1
			_points(record.components, expected.components, "Actual return hit uses original weapon points")
	_expect(returning == 1, "Child hits each travel leg exactly once")
	target.pos = Vector2(center.pos) + Vector2(center.velocity) * (float(center.lifetime) - float(center.age))
	target.resistances.fire = 0.75
	arena.damage_trace.clear()
	arena._update_projectiles(1.0)
	var blasts: int = 0
	for record: Dictionary in arena.damage_trace:
		if record.tags.has("explosion"):
			blasts += 1
			_expect(record.assembly == secondary.assembly and not record.assembly.has("weapon"), "Old expiry explosion retains its independent frozen B-only packet")
			_points(record.components, Damage.resolve(secondary, frozen.modifiers, target.resistances).components, "Expiry uses original offense and current mitigation")
	_expect(blasts > 0 and arena.projectiles.is_empty() and arena.event_counts.get("explosion", 0) == 9, "Nine-child lineage naturally terminates with one independent explosion per child")
	arena.state.equip(gear)
	var new_cast: Dictionary = _hit("tornado").cast
	_near(new_cast.packets.parent.assembly.weapon.components.physical, 11.07, "New cast independently sees changed legal local roll")
	_expect(new_cast.support_ids == ["volley"] and new_cast.initial_count == 5, "New cast independently sees replacement supports")
	completed = true

func _admission_state() -> Dictionary:
	return {"mana": arena.mana, "cooldowns": arena.cooldowns.duplicate(true), "projectiles": arena.projectiles.duplicate(true),
		"trace": arena.damage_trace.duplicate(true), "shots": arena.total_shots, "timer": arena.attack_timer,
		"rng": arena.rng.state, "runtime_cast": arena.projectile_runtime.next_cast_id, "runtime_projectile": arena.projectile_runtime.next_projectile_id}

func _invalid_admission() -> void:
	_reset()
	_install()
	var valid: Dictionary = arena.state.get_combat_snapshot().weapon_profile
	var poisons: Array = [{}, null, {"stage": "weapon_local"}]
	for pair: Array in [["stage", "global"], ["flat", {"physical": -1.0}], ["flat", {"physical": NAN}], ["base", {"physical": 3.0}]]:
		var profile: Dictionary = valid.duplicate(true)
		profile[pair[0]] = pair[1]
		poisons.append(profile)
	var forged: Dictionary = valid.duplicate(true)
	forged.sources[0].scope = "global"
	poisons.append(forged)
	for poison: Variant in poisons:
		arena.state.snapshot_overrides = {"weapon_profile": poison}
		_target()
		for skill: String in ["tornado", "bolt", "frost", "nova", "meteor", "chain", "dash", "ward"]:
			arena.state.slot_skill(0, skill)
			arena.mana = 100.0
			arena.cooldowns[skill] = 0.0
			var before: Dictionary = _admission_state()
			_expect(not arena.cast_skill(0) and _admission_state() == before, "Invalid raw local profile rejects before payment, cooldown, IDs and damage: " + skill)
		arena.auto_fire = true
		arena.attack_timer = 0.0
		var before: Dictionary = _admission_state()
		arena._update_auto_attack()
		_expect(_admission_state() == before, "Invalid local basic profile rejects before cadence, carrier and RNG")
		arena.auto_fire = false
	arena.state.snapshot_overrides.clear()
	arena.state.unequip("weapon")
	_expect(not arena.state.get_combat_snapshot().has("weapon_profile"), "Unequipped absence differs from explicitly invalid empty profile")
	_hit("tornado")
	_reset()
	_install()
	arena.state.slot_skill(0, "tornado")
	arena.state.set_skill_supports("tornado", ["volley", "focus"])
	var cast: Dictionary = arena.state.get_skill_cast("tornado")
	arena.mana = float(cast.mana) - 0.0001
	arena.cooldowns.tornado = 0.0
	var before: Dictionary = _admission_state()
	_expect(not arena.cast_skill(0) and _admission_state() == before, "Local weapon exact mana shortfall is atomic")
	for index: int in range(arena.MAX_PROJECTILES - int(cast.initial_count) + 1):
		arena.projectiles.append({"sentinel": index})
	arena.mana = 100.0
	before = _admission_state()
	_expect(not arena.cast_skill(0) and _admission_state() == before, "Local weapon supported volley capacity failure is completely atomic")
	arena.projectiles.pop_back()
	arena.mana = cast.mana
	_expect(arena.cast_skill(0) and arena.projectiles.size() == arena.MAX_PROJECTILES, "Exact available capacity admits all local-weapon parents")
	_near(arena.mana, 0.0, "Exact supported cost charged once")
	arena.projectiles.clear()
	completed = true

func _all_label_text(node: Node) -> String:
	var text: String = node.text + "\n" if node is Label else ""
	for child: Node in node.get_children():
		text += _all_label_text(child)
	return text

func _persistence_and_ui() -> void:
	_reset()
	var id: String = _install()
	arena.state.set_skill_supports("tornado", ["focus"])
	arena.state.slot_skill(0, "tornado")
	var saved: Dictionary = arena.state._snapshot()
	var compiled: Dictionary = arena.state.get_skill_cast("tornado")
	_expect(arena.state.save_build(EQUIPPED) == OK and Batch.saved_matches(arena), "Local equipment plus supports are stored by actual scene autosave")
	arena.state.equip("ember_wand")
	_expect(arena.state.load_build(EQUIPPED) and arena.state._snapshot() == saved, "Scene reload preserves exact local rolls, equipped identity and positions")
	_expect(arena.state.get_skill_cast("tornado") == compiled, "Reload recreates the same cast from stored canonical rolls")
	arena.restart_run()
	arena.enemies.clear()
	arena.auto_fire = false
	arena.player_pos = Vector2(500, 300)
	arena.player_facing = Vector2.RIGHT
	_expect(arena.state._snapshot() == saved and arena.state.get_skill_cast("tornado") == compiled, "Run restart retains exact legal local gear and compilation")
	arena.hud.open_panel("inventory")
	var panel: Node = arena.hud.find_child("InventoryPanel", true, false)
	panel.select_item("item:" + id)
	var item_label: Label = arena.hud.find_child("ItemStatsLabel", true, false)
	var derived: Label = arena.hud.find_child("DerivedStatsLabel", true, false)
	_expect(Grid.describe_item(arena.state, "item:" + id).get("short_name", "") == "长弓", "Inventory bow category names the actual longbow base")
	_expect(item_label.text.contains(arena.state.get_item_definition(id).weapon_damage_summary), "Inventory uses the same item-local W summary from equipment resolver")
	_expect(item_label.text.contains("= 13") and derived.text.contains("基伤 18"), "Item shows W13 while character base remains B18")
	_expect(derived.tooltip_text.contains("不含武器本地物理"), "Character base tooltip explains local points exclusion")
	arena.hud.open_panel("skills")
	var skill_panel: Node = arena.hud.find_child("SkillSupportPanel", true, false)
	skill_panel.select_skill("tornado")
	var skills_text: String = _all_label_text(skill_panel)
	var support_preview: Label = skill_panel.find_child("SupportCastPreview", true, false)
	_expect(skills_text.contains(Preview.summary(compiled)) and support_preview.tooltip_text.contains(Preview.assembly_line(compiled.packets.parent)), "K inspector displays same-source resolved and raw local assembly")
	arena.hud.open_panel("combat")
	var combat_text: String = _all_label_text(arena.hud._panel_body)
	_expect(combat_text.contains("通用基础伤害 18.0") and combat_text.contains(Preview.assembly_line(compiled.packets.parent)), "F6 inspector preserves B and displays real local contribution")
	var preview: Dictionary = arena.combat_preview()
	_expect(combat_text.contains("合计 %.2f" % float(preview.parent.total)) and combat_text.contains("合计 %.2f" % float(preview.child.total)), "F6 parent/child numbers match actual compiled preview")
	arena.hud.close_panel()
	_hit("tornado", true)
	completed = true

func _reward_exclusions_and_capacity() -> void:
	_reset()
	arena.reward_kills = 7
	var splitter: Dictionary = _enemy("splitter", "rare")
	_kill(splitter)
	arena._flush_monster_spawns()
	var before: Dictionary = _loot()
	for child: Dictionary in arena.enemies.duplicate():
		child.rarity = "rare"
		child.equipment_pool = "local_weapon"
		_kill(child)
	arena._flush_monster_spawns()
	_expect(_loot() == before and arena.reward_kills == 8, "Rare-looking local-pool descendants cannot grant bows or advance reward cadence")
	arena.start_monster_demo()
	before = _loot()
	var depth: int = 0
	while not arena.enemies.is_empty() and depth < 5:
		for enemy: Dictionary in arena.enemies.duplicate():
			enemy.equipment_pool = "local_weapon"
			_kill(enemy)
		arena._flush_monster_spawns()
		depth += 1
	_expect(arena.enemies.is_empty() and _loot() == before and arena.reward_kills == 0, "Actual demo roots, boss and descendants remain rewardless for local pool")
	_reset()
	var full: Dictionary = Batch.full_backpack()
	_expect(Batch.write_bytes("user://local_weapon_full.json", JSON.stringify(full).to_utf8_buffer()) and arena.state.load_build("user://local_weapon_full.json"), "Capacity fixture loads through normal validation")
	var enemy: Dictionary = _enemy("brute", "rare")
	enemy.equipment_pool = "local_weapon"
	var stale: Dictionary = enemy.duplicate(true)
	arena.reward_kills = 7
	before = _loot()
	_kill(enemy)
	_expect(_loot() == before and arena.reward_kills == 8, "Full inventory local reward preserves every item, position and serial")
	_expect(arena.state.discard_equipment("gear_000002"), "Test frees space using normal discard")
	before = _loot()
	_kill(stale)
	_expect(_loot() == before and arena.reward_kills == 8, "Freeing space cannot replay rejected local reward")
	completed = true

func _v8_scene_migration() -> void:
	arena.free()
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/local_weapon_v8_scene.json"))
	var original := PackedByteArray([239, 187, 191])
	original.append_array(("\r\n  " + JSON.stringify(legacy, "  ", false, true).replace("\n", "\r\n") + "\r\n\r\n").to_utf8_buffer())
	var path: String = "user://build_save.json"
	var backup: String = path + ".v8-backup.json"
	DirAccess.remove_absolute(backup)
	_expect(Batch.write_bytes(path, original), "Literal v8 fixture includes real BOM, CRLF and noncanonical formatting")
	_create()
	_expect(arena.state.migrated_from_v8 and arena.state.save_block_reason().is_empty(), "Real startup migrates valid v8")
	_expect(arena.hud.is_blocking() and arena.hud._active_panel == "inventory", "Startup opens migration explanation before gameplay")
	var expected: Dictionary = legacy.duplicate(true)
	expected.version = 9
	# JSON parses numbers as floats; compare both encodings in that same domain.
	var observed: Dictionary = JSON.parse_string(JSON.stringify(arena.state._snapshot()))
	_expect(observed == JSON.parse_string(JSON.stringify(expected)) and not arena.state.get_combat_snapshot().has("weapon_profile"), "Startup only updates schema and preserves all legacy rolls, supports, locations and build fields")
	_expect(FileAccess.get_file_as_bytes(path) == original and not FileAccess.file_exists(backup), "Startup and initial restart have not touched original bytes")
	_expect(arena.state.unequip("weapon"), "First real equipment edit triggers migration autosave")
	_expect(FileAccess.get_file_as_bytes(backup) == original, "First automatic write creates byte-exact BOM/CRLF v8 backup")
	_expect(Batch.saved_matches(arena) and JSON.parse_string(FileAccess.get_file_as_string(path)).version == 9, "First automatic write commits exact current scene schema9")
	var canonical: Dictionary = arena.state._snapshot()
	arena.free()
	_create()
	_expect(not arena.state.migrated_from_v8 and arena.state._snapshot() == canonical, "Fresh scene process initialization restores committed schema9 without repeating migration")
	_expect(FileAccess.get_file_as_bytes(backup) == original, "Second startup leaves original backup unchanged")
	completed = true
