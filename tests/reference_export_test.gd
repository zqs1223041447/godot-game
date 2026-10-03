extends SceneTree
## Content drift tests compare the exported artifact to the live authorities.
const Exporter = preload("res://tools/export_reference.gd")
const Data = preload("res://scripts/game_data.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Passives = preload("res://scripts/passive_data.gd")
const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Rules = preload("res://scripts/passives/allocation_rules.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Build = preload("res://scripts/build_state.gd")
const Canonical = preload("res://scripts/canonical_game_state.gd")
const WeaponLocal = preload("res://scripts/items/weapon_local_rules.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	var three_supports: Array = ["volley", "focus", "pierce"]
	var combinations: Array = Exporter.support_combinations(three_supports)
	_expect(combinations == [[], ["volley"], ["focus"], ["pierce"], ["volley", "focus"], ["volley", "pierce"], ["focus", "pierce"]], "Three available supports produce exactly seven zero/one/two-slot candidates")
	_expect(Exporter.support_combinations([]) == [[]] and Exporter.support_combinations(["focus"]) == [[], ["focus"]], "Empty and single-support catalogs contain no duplicate examples")
	combinations[1].append("changed")
	_expect(three_supports == ["volley", "focus", "pierce"], "Reference combinations do not alias the source list")
	var current: Dictionary = Exporter.clean(Exporter.collect())
	_expect(current.crafting.size() == 3 and current.crafting.has_all(["calibration_shard","salvage","recalibrate"]), "One material and exactly two implemented crafting operations are browsable")
	_expect(current.crafting.calibration_shard.maximum == Build.MAX_CRAFT_MATERIALS and current.crafting.calibration_shard.save_version == Canonical.Rules.VERSION, "Preserved wallet limit and current canonical save schema")
	for operation: String in ["salvage","recalibrate"]:
		var craft: Dictionary = current.crafting[operation]
		var sample: Dictionary = craft.example
		_expect(sample.quote.ok and sample.full_candidate_valid and sample.revision_before == 0 and sample.revision_after == 1, "Real planner example produces one full valid transaction: " + operation)
		_expect(Equipment.validate_instance(sample.source) and craft.eligible_base_ids == Equipment.all_base_ids(), "Craft examples and all base links share real catalog eligibility")
		if operation == "salvage":
			_expect(sample.quote.materials.calibration_shard == 4 and sample.balance_before == 8 and sample.balance_after == 12 and sample.after_instance.is_empty(), "Independent one-T3 magic salvage arithmetic and consumed result")
		else:
			_expect(sample.quote.cost.calibration_shard == 8 and sample.balance_after == 0 and Equipment.validate_instance(sample.after_instance), "Independent calibration economics and legal replacement")
			_expect(sample.after_instance.id == sample.source.id and sample.after_instance.affixes[0].tier == 3 and sample.after_definition == Exporter.clean(Equipment.definition(sample.after_instance)), "Calibrated definition derives from exact planned result without copying a damage formula")
	_expect(current.monster_attacks.size() == 3 and current.monster_attacks.has("locked_circle"), "Three implemented typed monster action examples are browsable")
	_expect(current.encounters.size()==2,"Exactly two finite optional encounter modifiers are browsable")
	for id: String in current.encounters:
		var definition: Dictionary=current.encounters[id]
		_expect(definition.status=="implemented" and not definition.profile.reward_budget.enabled and not definition.profile.reward_budget.grants_rewards,"Reference does not turn reward metadata into actual loot")
		for sample: Dictionary in definition.examples.values():
			_expect(is_equal_approx(float(sample.after[definition.field]),float(sample.before[definition.field])*float(definition.multiplier)),"Challenge chart records exact single compiled transform")
			for field: String in ["damage","attack_speed","contact_weights","resistances","shield","max_shield","xp_reward"]:
				_expect(sample.after[field]==sample.before[field],"Challenge example preserves "+field)
	var attack: Dictionary = current.monster_attacks.locked_circle
	var heavy_example: Dictionary = attack.example
	_expect(attack.status == "implemented" and attack.integrated_templates == ["ember_guard"], "Reference distinguishes real guard integration from generic runtime capacity")
	_expect(heavy_example.start.phase == "windup" and heavy_example.halfway.phase == "windup" and heavy_example.recovery.phase == "recovery", "Example states come from actual runtime transitions")
	_expect(heavy_example.cases.standing.inside and heavy_example.cases.armored.inside and not heavy_example.cases.moving.inside, "Same geometric helper distinguishes standing and moved target")
	_expect(heavy_example.cases.moving.settlement.is_empty(), "A dodged event cannot fabricate a damage settlement")
	_expect(is_equal_approx(heavy_example.cases.standing.settlement.damage_total,32.592) and is_equal_approx(heavy_example.cases.armored.settlement.damage_total,30.1476), "Independent wave-three and 15 percent fire-armor arithmetic")
	_expect(heavy_example.cases.armored.settlement.components.physical == heavy_example.cases.standing.settlement.components.physical, "Armor reduces only fire in actual heavy hit example")
	_expect(heavy_example.event.packet.base == heavy_example.start.packet.base and heavy_example.event.center == heavy_example.start.center, "Reference event preserves frozen damage and locked center")
	_expect(attack.profile == Exporter.clean(Monsters.telegraph_policy(Monsters.make_enemy(1,"ember_guard",3,Vector2.ZERO,"demo")).profile), "Actual default guard policy defines the displayed times and geometry")
	for element: String in ["cold","lightning"]:
		var typed: Dictionary = current.monster_attacks["locked_circle_"+element]
		var base: Dictionary = typed.example.event.packet.base
		_expect(base.size()==1 and base.has(element),"Elemental example is the actual single component")
		_expect(is_equal_approx(typed.example.cases.armored.settlement.damage_total,typed.example.cases.standing.settlement.damage_total*0.82),"Actual legal fresh source path grants18 percent matching resistance")
		_expect(typed.example.allocated_path.size()<=6 and not typed.example.cases.moving.inside,"Fresh budget can reach example and original warning allows escape")
		_expect(current.elemental_encounters.extra_rewards==false and current.elemental_encounters.extra_rng==false,"Natural elemental selection adds no bonus or RNG")
	var piercing: Dictionary = current.projectile_support_examples.skills
	_expect(piercing.bolt.before.observed_hits == [1, 2] and piercing.bolt.after.observed_hits == [1, 2, 3, 4], "Reference bolt diagram records actual two versus four collisions")
	_expect(piercing.frost.before.observed_hits == [1, 2, 3] and piercing.frost.after.observed_hits == [1, 2, 3, 4, 5], "Reference frost diagram records actual three versus five collisions")
	_expect(is_equal_approx(piercing.bolt.after.hit_damage, 35.36) and is_equal_approx(piercing.bolt.after.mana, 8.4), "Reference values match independent default-build arithmetic")
	for skill_id: String in ["nova", "meteor"]:
		var area: Dictionary = current.area_support_examples.skills[skill_id]
		_expect(is_equal_approx(area.wide.radius / area.base.radius, 1.2) and area.wide.area_multiplier == 1.44, "Area diagram uses square-root radius conversion")
		_expect(is_equal_approx(area.wide.hit_damage, area.base.hit_damage * 0.85), "Area diagram preserves damage tradeoff")
		_expect(area.base.layouts.outer_band.hit_indices == [0] and area.wide.layouts.outer_band.hit_indices == [0,1,2,3,4], "Layout diagram records actual shared-circle coverage")
		_expect(is_equal_approx(area.wide.layouts.cluster.total_before_defense, area.base.layouts.cluster.total_before_defense * 0.85), "Already-covered layout loses damage")
	var existing: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/catalog.json"))
	_expect(existing is Dictionary, "export parses")
	if not existing is Dictionary:
		quit(1)
		return
	# Stringify after parsing canonicalizes JSON's int/float representation.
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(current, "", true, true))
	_expect(JSON.stringify(existing, "", true) == JSON.stringify(roundtrip, "", true), "committed JSON exactly matches live export")
	_ids(current.skills, Data.SKILLS.keys(), "all active skills")
	_ids(current.supports, Supports.SUPPORTS.keys(), "all support skills")
	_ids(current.equipment, Equipment.all_base_ids(), "legacy and expansion bases")
	_ids(current.affixes, Equipment.all_affix_ids(), "legacy and expansion affix families")
	_expect(current.equipment_pools == Equipment.pool_profiles(), "all detached runtime pool profiles")
	_expect(current.current_loot_profile == Equipment.loot_profile(Canonical.LOOT_PROFILE_ID), "current natural reward weights")
	_ids(current.jewels, Jewels.BASES.keys() + Jewels.SPECIAL_BASES.keys(), "ordinary and special jewels")
	_ids(current.passives, Passives.get_nodes().keys(), "all original nodes")
	_ids(current.mechanisms, Registry.get_ids(), "all shared mechanisms")
	_ids(current.monsters, Monsters.TEMPLATES.keys(), "all monster templates")
	_expect(current.skills.size() == 10 and current.supports.size() == 16, "bounded skill inventory")
	_expect(current.equipment.size() == 14 and current.affixes.size() == 26, "bounded equipment inventory")
	_expect(current.passives.size() == 181 and current.special_coverage.size() == 12, "historical 181-node research tree and socket coverage")
	for skill_id: String in current.skills:
		var skill: Dictionary = current.skills[skill_id]
		_expect(skill.compatible_supports == Supports.supports_for_skill(skill_id), "runtime compatibility " + skill_id)
		for config: String in ["fresh", "full_tornado", "local_normal", "local_max"]:
			_expect(skill.examples[config].size() == Exporter.support_combinations(skill.compatible_supports).size(), "all support combinations " + skill_id + "/" + config)
	_expect(current.configurations.fresh.equipped.weapon == "ember_wand", "fresh build does not assume mechanism bow")
	_expect(current.configurations.full_tornado.equipped.weapon == "prism_bow", "full example explicitly equips mechanism bow")
	_expect(current.sources.passive.version == "3.29.1", "passive source preserved")
	_expect(current.sources.affix.source_version == "3.29.3.3", "affix source preserved")
	_expect(current.sources.affix.export_commit == "a77305840b4cc8555eeeea144eac3eeddeff134b", "research commit preserved")
	for socket_id: String in current.special_coverage:
		var sample: Dictionary = current.special_coverage[socket_id]
		var jewel: Dictionary = Jewels.generate_special("jewel_000004")
		var analysis: Dictionary = Rules.analyze(sample.path, {socket_id: jewel.id}, {jewel.id: jewel})
		_expect(Exporter.clean(analysis) == sample.connected, "coverage uses shared analyzer " + socket_id)
		_expect(sample.connected.legal and sample.connected.active_sources.has(socket_id), "connected source activates " + socket_id)
		_expect(not sample.disconnected.legal and sample.disconnected.active_sources.is_empty(), "disconnected source cannot activate " + socket_id)
		_expect(sample.with_remote.legal and sample.with_remote.remote_nodes.has(sample.remote_example), "remote example is legal " + socket_id)
		for node_id: String in sample.connected.granted_by:
			_expect(current.passives[node_id].type in ["small", "notable"], "coverage excludes sockets and origin")
	_expect(current.monsters.size() == 9, "all original monster templates including fire encounter")
	_expect(current.fire_encounter == Monsters.fire_encounter_policy(), "encounter/reward policy from production catalog")
	var defense: Dictionary = current.defenses.fire_resistance
	var metadata: Dictionary = Defense.metadata()
	for key: String in metadata:
		_expect(defense[key] == Exporter.clean(metadata[key]), "shared defense metadata " + key)
	_expect(defense.origin == "original" and defense.source_refs.is_empty(), "new defense is original, not PoE-derived")
	var example: Dictionary = defense.worked_example
	var expected: Dictionary = Defense.incoming_hit(example.input_components, example.defense_stats, example.shield_before, example.health_before, "player")
	_expect(example.trace == Exporter.clean(expected), "diagram trace comes from production incoming_hit")
	_expect(example.trace.damage_total == 35.0 and example.trace.shield_spent == 10.0 and example.trace.health_lost == 25.0, "known forty-point input works through fire resistance then shield")
	_expect(example.trace.raw_components.physical == 20.0 and example.trace.raw_components.fire == 20.0, "worked example input preserved")
	for key: String in ["components", "damage_total", "shield_spent", "health_lost", "remaining_health"]:
		_expect(example.trace[key] == example.monster_trace[key], "player/monster example parity " + key)
	for profile: Dictionary in defense.cap_examples:
		_expect(profile == Exporter.clean(Defense.defense_profile({"fire_resistance": profile.raw_resistances.fire})), "clamp example from shared profile")
	_expect(current.known_target.wave == current.fire_encounter.minimum_wave, "known target uses first encounter wave")
	_expect(current.equipment.emberhide_vest.stats_text.contains("火焰抗性 +15") and current.equipment.emberhide_vest.stats_text.contains("%"), "base defense formatter keeps percentage units")
	_expect(current.affixes.emberward.eligible_bases == ["emberhide_vest"], "new suffix cannot leak into frozen bases")
	for id: String in current.monsters:
		var enemy: Dictionary = current.monsters[id].runtime_example
		_expect(current.monsters[id].contact_components == Exporter.clean(Monsters.contact_components(enemy)), "contact components from catalog " + id)
	for skill: Dictionary in current.skills.values():
		for config: Array in skill.examples.values():
			for cast: Dictionary in config:
				for packet: Dictionary in cast.packets:
					_expect(packet.known_target_settlement.ok, "known target settlement is valid")
					_expect(float(packet.known_target_resolved.total) <= float(packet.resolved.total) + 0.00001, "known positive fire defense never increases preview")
	_expect(current.schema_version == 3 and current.save_version == Canonical.Rules.VERSION, "reference and current canonical save schemas explicit")
	_expect(current.current_loot_profile_id == Canonical.LOOT_PROFILE_ID, "actual canonical reward profile identity")
	_expect(current.loot_profiles == Equipment.loot_profiles(), "historical and current pool weights exported")
	_expect(current.loot_profiles["v0.11"].size() == 3 and current.loot_profiles["v0.13"].size()==4 and current.current_loot_profile.size() == 5, "legacy three/four and new five-pool selections retained separately")
	_expect(current.canonical.gem_definitions.size()==26 and current.canonical.gem_reward.definition_count==26 and current.canonical.base_skill_groups==10 and current.canonical.support_slots==5 and current.canonical.slots.size()==9,"actual canonical groups/gems/equipment targets exported")
	_expect(current.source_tree.nodes.size()==3390 and current.source_tree.edges.size()==2697,"full source records and safe standard edges distinct from legacy181")
	_expect(current.source_tree.nodes["2151"].execution.status=="full" and current.source_tree.nodes["22497"].execution.status=="unsupported","source consumers and blocked cast-speed exposed accurately")
	_expect(current.canonical.five_link_example.initial_count==5 and current.canonical.five_link_example.recipe.slow==4.5,"actual five-link recipe exported")
	var local: Dictionary = current.weapon_stages.weapon_local
	for key: String in WeaponLocal.metadata():
		_expect(local[key] == Exporter.clean(WeaponLocal.metadata()[key]), "weapon-local metadata " + key)
	_expect(local.examples.local_normal.resolved_weapon.components.physical == 4.0, "normal bow has real P4")
	_expect(local.examples.local_max.resolved_weapon.components.physical == 13.0, "legal local maximum W13")
	_expect(current.equipment.ashwood_bow.size == [2, 3] and current.equipment.ashwood_bow.pool == "local_weapon", "new bow footprint and pool")
	_expect(current.equipment.ashwood_bow.normal_definition == Exporter.clean(Equipment.definition(local.examples.local_normal.instance)), "base entry shows real normal weapon definition")
	for config: String in local.examples:
		var sample: Dictionary = local.examples[config]
		_expect(Equipment.validate_instance(sample.instance), "local sample is legal " + config)
		var build: RefCounted = Exporter.local_build(sample.instance)
		var snapshot: Dictionary = build.get_combat_snapshot()
		_expect(sample.snapshot == Exporter.clean(snapshot), "sample uses actual equipped BuildState " + config)
		_expect(sample.definition == Exporter.clean(build.get_item_definition(build.equipped.weapon)), "weapon summary uses runtime definition " + config)
		_expect(sample.resolved_weapon == Exporter.clean(WeaponLocal.resolve(snapshot.weapon_profile)), "P/F/L/W uses actual local resolver " + config)
		_expect(not build.get_stats().has("weapon_added_physical") and not build.get_stats().has("weapon_physical_increased"), "local terms never enter global stats " + config)
		_expect(build.inventory.has(sample.instance.id) and build.next_equipment_id == 2, "legal sample ownership and next ID " + config)
		_expect(not build._validate_snapshot(build._snapshot()).is_empty(), "example fully satisfies current build schema in memory " + config)
		var cast: Dictionary = Compiler.compile_skill("tornado", snapshot, [])
		for role: String in sample.hits:
			var packet: Dictionary = Recipes.event_packet(snapshot, "basic", "projectile") if role == "basic" else cast.packets[role]
			var hit: Dictionary = sample.hits[role]
			_expect(hit.packet == Exporter.clean(packet), "diagram exact packet " + config + "/" + role)
			_expect(hit.resolved == Exporter.clean(Damage.resolve(packet, snapshot.modifiers)), "diagram exact damage " + config + "/" + role)
			_expect(packet.assembly.has("weapon") == (role != "secondary"), "only attack consumers have weapon trace " + config + "/" + role)
			_expect(hit.known_target_settlement == Exporter.clean(Defense.settle_resolved(hit.known_target_resolved, current.known_target.shield, current.known_target.health)), "diagram known-target settlement " + config + "/" + role)
	_expect(local.examples.local_normal.hits.secondary.packet == local.examples.local_max.hits.secondary.packet, "local rolls do not affect independent explosion")
	for affix_id: String in Equipment.LOCAL_WEAPON_AFFIXES:
		var family: Dictionary = current.affixes[affix_id]
		_expect(family.eligible_bases == [WeaponLocal.BASE_ID] and family.pools == ["local_weapon"], "local family exclusive scope " + affix_id)
		_expect(family.affected_skills == ["tornado"] and family.other_consumers == ["basic"], "local family links real active skill and separate basic consumer " + affix_id)
		var evidence: Dictionary = family.scope_evidence
		_expect(Equipment.validate_instance(evidence.baseline_instance) and Equipment.validate_instance(evidence.candidate_instance), "local scope compares real legal items " + affix_id)
		_expect(evidence.baseline_instance.rarity == "normal" and evidence.candidate_instance.rarity == "magic" and evidence.candidate_instance.affixes.size() == 1, "single-affix comparison has normal baseline " + affix_id)
		_expect(evidence.baseline_stats == evidence.candidate_stats, "local cross-link never mutates character stats " + affix_id)
		for skill_id: String in evidence.skills:
			var comparison: Dictionary = evidence.skills[skill_id]
			_expect((not is_equal_approx(comparison.before, comparison.after)) == (skill_id == "tornado"), "local scope comparison " + affix_id + "/" + skill_id)
			_expect(comparison.secondary_unchanged, "secondary excluded " + affix_id + "/" + skill_id)
		_expect(evidence.basic.after.total > evidence.basic.before.total, "ordinary attack independently evidenced " + affix_id)
	print("Reference export: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _ids(actual: Dictionary, expected: Array, label: String) -> void:
	var keys: Array = actual.keys()
	keys.sort()
	expected.sort()
	_expect(keys == expected, label)

func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
