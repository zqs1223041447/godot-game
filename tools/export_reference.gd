extends SceneTree
## Offline reference export. Fresh builds and validated QA fixtures only; no user data.
const Data = preload("res://scripts/game_data.gd")
const Build = preload("res://scripts/build_state.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const AreaRules = preload("res://scripts/combat/area_support_rules.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Passives = preload("res://scripts/passive_data.gd")
const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const SourceMonster = preload("res://scripts/mechanics/source_monster_grants.gd")
const Balance = preload("res://scripts/mechanics/passive_balance_adapter.gd")
const Rules = preload("res://scripts/passives/allocation_rules.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const WeaponLocal = preload("res://scripts/items/weapon_local_rules.gd")
const Projectiles = preload("res://scripts/combat/projectile_runtime.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const CraftPlanner = preload("res://scripts/items/crafting_transaction_planner.gd")
const Telegraphs = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const TelegraphProfiles = preload("res://scripts/monsters/telegraph_profiles.gd")
const Arena = preload("res://scripts/main.gd")
# Historical fixed-arena examples retain their original geometry. Main.ARENA
# is instance state now; current exploration snapshots use their own layout.
const LEGACY_REFERENCE_BOUNDS: Rect2 = preload("res://scripts/visuals/world_view.gd").WORLD_ARENA
const EncounterCatalog = preload("res://scripts/encounters/encounter_catalog.gd")
const EncounterCompiler = preload("res://scripts/encounters/encounter_compiler.gd")
const Canonical = preload("res://scripts/canonical_game_state.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const SourceLocalization = preload("res://scripts/passives/source_tree_localization.gd")
const GemCatalogData = preload("res://scripts/items/gem_catalog.gd")
const EquipmentSlotsData = preload("res://scripts/items/equipment_slots.gd")
const Flasks = preload("res://scripts/items/flask_catalog.gd")
const FlaskRuntime = preload("res://scripts/combat/flask_runtime.gd")
const FlaskModifiers = preload("res://scripts/combat/flask_modifier_rules.gd")
const Town = preload("res://scripts/town/town_catalog.gd")
const EquipmentPurchaseReference = preload("res://tools/equipment_purchase_reference.gd")
const JewelPurchaseReference = preload("res://tools/jewel_purchase_reference.gd")
const FlaskPurchaseReference = preload("res://tools/flask_purchase_reference.gd")
const ChaosAegisReference = preload("res://tools/chaos_aegis_reference.gd")
const Maps = preload("res://scripts/world/map_catalog.gd")
const MapRules = preload("res://scripts/world/map_compiler.gd")
const CampLayoutData=preload("res://scripts/world/map_camp_layout.gd")
const CampAdmissionData=preload("res://scripts/world/map_camp_admission.gd")
const SunwellRoster=preload("res://scripts/world/sunwell_roster_rules.gd")
const MistSkitterRoster=preload("res://scripts/world/mist_skitter_roster_rules.gd")
const CampRosterData=preload("res://scripts/world/map_camp_state.gd")
const ThirdMapMigrationData=preload("res://scripts/save/third_map_migration.gd")
const MapGeometryData = preload("res://scripts/world/map_geometry.gd")
const MapDefense = preload("res://scripts/world/map_defense_rules.gd")
const MapBosses=preload("res://scripts/monsters/map_boss_profiles.gd")
const MapAdmission=preload("res://scripts/world/map_admission.gd")
const MonsterRuntime=preload("res://scripts/monsters/monster_runtime.gd")
const AttackRules = preload("res://scripts/combat/attack_hit_rules.gd")
const BurnRuntime = preload("res://scripts/combat/burn_runtime.gd")
const EmberMigration = preload("res://scripts/save/ember_gem_migration.gd")
const ShockRuntimeData = preload("res://scripts/combat/shock_runtime.gd")
const ShockMigration = preload("res://scripts/save/shock_gem_migration.gd")
const FireDotMigration = preload("res://scripts/save/fire_dot_migration.gd")
const FasterBurnMigrationData = preload("res://scripts/save/faster_burn_migration.gd")
const ForgebladeMigrationData = preload("res://scripts/save/forgeblade_migration.gd")
const ManaGuardMigrationData = preload("res://scripts/save/mana_guard_migration.gd")
const ResoluteRules = preload("res://scripts/combat/resolute_technique_rules.gd")
const GloveRingMigration = preload("res://scripts/save/glove_ring_affix_migration.gd")
const FrostLockMigration = preload("res://scripts/save/frost_lock_gem_migration.gd")
const FreezeRuntimeData = preload("res://scripts/combat/freeze_runtime.gd")
const SourceCoverage = preload("res://tools/export_source_execution_coverage.gd")

func _initialize() -> void:
	var target: String = "res://docs/reference/catalog.json"
	if not OS.get_cmdline_user_args().is_empty():
		target = OS.get_cmdline_user_args()[0]
	# Validate every fixture before opening/truncating the previous artifact.
	var elemental: bool = OS.get_cmdline_user_args().has("--elemental-conversion-fragment")
	var narrow: bool = elemental or OS.get_cmdline_user_args().has("--source-monster-fragment")
	var content: Dictionary = elemental_conversion_fragment() if elemental else source_monster_fragment() if narrow else collect()
	var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		push_error("Cannot open reference output: " + target)
		quit(1)
		return
	file.store_string(JSON.stringify(clean(content), "\t", true, true) + "\n")
	file.close()
	print("Reference exported: " + target)
	if elemental:
		var current_coverage: Dictionary = SourceCoverage.build_report()
		assert(not current_coverage.is_empty() and current_coverage.integrity.ok)
		var current_file: FileAccess = FileAccess.open("res://docs/qa/v078-reference/source-tree-coverage.json", FileAccess.WRITE)
		assert(current_file != null)
		current_file.store_string(SourceCoverage.serialize_report(current_coverage))
		current_file.close()
	if target == "res://docs/reference/catalog.json" and not narrow:
		var coverage: Dictionary = SourceCoverage.build_report()
		assert(not coverage.is_empty() and coverage.integrity.ok)
		var coverage_text: String = SourceCoverage.serialize_report(coverage)
		if FileAccess.file_exists(SourceCoverage.OUTPUT_PATH) and FileAccess.get_file_as_string(SourceCoverage.OUTPUT_PATH) == coverage_text:
			print("Source tree coverage unchanged; retained existing file")
		else:
			var coverage_file: FileAccess = FileAccess.open(SourceCoverage.OUTPUT_PATH, FileAccess.WRITE)
			if coverage_file == null:
				push_error("Cannot write source tree coverage report")
				quit(1)
				return
			coverage_file.store_string(coverage_text)
			coverage_file.close()
			print("Source tree coverage exported: " + SourceCoverage.OUTPUT_PATH)
	quit(0)

static func collect() -> Dictionary:
	var result: Dictionary = {"schema_version": 3,
		"game_version": ProjectSettings.get_setting("application/config/version", "development"),
		"sources": {"passive": Balance.source_manifest(), "affix": _affix_source()},
		"equipment": {}, "affixes": {}, "fixed_items": Data.ITEMS.duplicate(true),
		"skills": {}, "supports": Supports.SUPPORTS.duplicate(true), "jewels": {},
		"jewel_affixes": {}, "passives": Passives.get_nodes().duplicate(true),
		"edges": Passives.get_edges().duplicate(true), "sectors": Passives.SECTORS,
		"mechanisms": {}, "monsters": {}, "monster_rarities": Monsters.RARITIES,
		"equipment_rarities": Equipment.RARITIES, "jewel_rarities": Jewels.RARITIES,
		"equipment_pools": Equipment.pool_profiles(), "loot_profiles": Equipment.loot_profiles(),
		"current_loot_profile_id": Canonical.LOOT_PROFILE_ID, "save_version": Build.SAVE_VERSION, "fire_encounter": Monsters.fire_encounter_policy(), "elemental_encounters": Monsters.elemental_encounter_policy(), "current_loot_profile": Equipment.loot_profile(Canonical.LOOT_PROFILE_ID),
		"passive_caps": Balance.player_caps(), "passive_policy": Balance.policy_version(),
		"effects": Recipes.EFFECTS, "tornado_recipe": Recipes.TORNADO,
		"limits": {"max_supports": Supports.MAX_SUPPORTS, "initial_projectiles": Compiler.MAX_INITIAL_PROJECTILES,
			"min_item_level": Equipment.MIN_ITEM_LEVEL, "max_item_level": Equipment.MAX_ITEM_LEVEL}}
	result["area_support_examples"] = area_examples()
	result["support_program_examples"] = support_program_examples()
	result["projectile_support_examples"] = piercing_examples()
	result["crafting"] = crafting_examples()
	result["jewel_crafting"] = preload("res://tools/jewel_crafting_reference.gd").build_snapshot()
	result["monster_attacks"] = telegraph_examples()
	result["encounters"] = encounter_examples()
	result["canonical"] = canonical_examples()
	result["currencies"] = currency_examples()
	result["flasks"] = flask_examples()
	result["town_maps"] = town_map_examples()
	result["ginkgo_west_storm"] = preload("res://tools/ginkgo_west_storm_reference.gd").collect()
	result["ruins_corridor_frost"] = preload("res://tools/ruins_corridor_frost_reference.gd").collect()
	result["map_camps"]={}
	for map_id:String in Maps.MAPS:
		var camp_layout:Dictionary=CampLayoutData.layout(map_id,LEGACY_REFERENCE_BOUNDS)
		assert(camp_layout.ok)
		result.map_camps[map_id]=camp_layout.landmarks
	result["normal_journey"] = normal_journey_examples()
	result["sunwell_terrace"] = sunwell_examples()
	result["burning"] = burning_examples()
	result["ember_proliferation"] = ember_proliferation_examples()
	result["shock"] = shock_examples()
	result["source_fire_dot"] = source_fire_dot_examples()
	result["source_faster_burn"] = source_faster_burn_examples()
	result["mana_guard"] = mana_guard_examples()
	result["elemental_resistance_caps"] = elemental_resistance_cap_examples()
	result["elemental_defense_affixes"] = elemental_defense_affix_examples()
	result["defense_rating_affixes"] = defense_rating_affix_examples()
	result["iron_reflexes"] = iron_reflexes_examples()
	result["zealots_oath"] = zealots_oath_examples()
	result["physical_fire_conversion"] = physical_fire_conversion_examples()
	result["precise_technique"] = precise_technique_examples()
	result["glove_ring_affixes"] = glove_ring_affix_examples()
	result["ambush"] = ambush_examples()
	result["inward_pull"] = inward_pull_examples()
	result["chain_shock_build"] = chain_shock_build_example()
	result["frost_lock"] = frost_lock_examples()
	result["source_monster_movement"] = source_monster_movement_examples()
	result["source_monster_damage_life"] = source_monster_damage_life_examples()
	result["source_monster_shield_recharge"] = source_monster_shield_recharge_examples()
	result["resolute_technique"] = resolute_technique_examples()
	result["forgeblade"] = forgeblade_examples()
	result["melee_basic"] = melee_basic_examples(result.forgeblade)
	result["normal_gem_trading"]={"offers":Canonical.GemTrade.offers(),"recycle_credit":Canonical.GemTrade.RECYCLE_CREDIT,"currency":Canonical.GemTrade.MATERIAL_ID,"location":"normal_town","level":1,"quality":0,"recycle_location":"bag","schema":Canonical.Rules.VERSION,"test_supply_separate":true,"pricing":"初版可调整预算；每次无词缀地图净得4碎片"}
	result["purity_of_flesh"] = purity_of_flesh_reference()
	result["arcane_will"] = arcane_will_reference()
	result["source_tree"] = source_tree_reference()
	result["source_tree_localization"] = source_tree_localization_reference(result.source_tree)
	result["source_spatial"] = source_spatial_examples()
	result["source_recharge"] = source_recharge_examples()
	result["source_mana_cost"] = source_mana_cost_examples()
	result["source_flasks"] = source_flask_examples()
	result["source_critical"] = source_critical_examples()
	result["source_leech"] = source_leech_examples()
	result["map_bosses"] = map_boss_examples()
	result["save_version"] = Canonical.Rules.VERSION
	result["current_loot_profile_id"] = Canonical.LOOT_PROFILE_ID
	result["current_loot_profile"] = Equipment.loot_profile(Canonical.LOOT_PROFILE_ID)
	result.crafting.calibration_shard.save_version=Canonical.Rules.VERSION
	result.limits.max_supports = Supports.GROUP_MAX_SUPPORTS
	var base_ids: Array = Equipment.all_base_ids()
	var affix_ids: Array = Equipment.all_affix_ids()
	for id: String in base_ids:
		var base: Dictionary = Equipment.base_definition(id)
		base["pool"] = Equipment.pool_for_base(id)
		base["eligible_affixes"] = []
		for affix_id: String in affix_ids:
			if Equipment.family_eligible(affix_id, id):
				base.eligible_affixes.append(affix_id)
		base["stats_text"] = Passives.describe_stats(base.stats)
		if base.get("stage") == WeaponLocal.STAGE:
			var normal: Dictionary = _local_instance([], "normal", id)
			base["normal_instance"] = normal
			base["normal_definition"] = Equipment.definition(normal)
		result.equipment[id] = base
	for id: String in affix_ids:
		var family: Dictionary = Equipment.affix_definition(id)
		family["pools"] = []
		for pool_id: String in result.equipment_pools:
			if result.equipment_pools[pool_id].affix_ids.has(id):
				family.pools.append(pool_id)
		family["eligible_bases"] = []
		for base_id: String in base_ids:
			if Equipment.family_eligible(id, base_id):
				family.eligible_bases.append(base_id)
		family["formatted_examples"] = []
		family["formatted_ranges"] = []
		for tier: Dictionary in family.tiers:
			var instance: Dictionary = {"id": "gear_000001", "base_id": family.eligible_bases[0], "rarity": "magic",
				"item_level": tier.level, "affixes": [{"id": id, "tier": tier.tier, "value": tier.max}]}
			family.formatted_examples.append(Equipment.definition(instance).affix_lines[0])
			family.formatted_ranges.append({"min":Equipment.affix_display({"id":id,"tier":tier.tier,"value":tier.min}).value_text,"max":Equipment.affix_display({"id":id,"tier":tier.tier,"value":tier.max}).value_text})
		result.affixes[id] = family
	var defense: Dictionary = Defense.metadata()
	# These are explicitly authored demonstration inputs, not universal game damage.
	var example_components: Dictionary = {"physical": 20.0, "fire": 20.0}
	var example_stats: Dictionary = {"fire_resistance": 0.25}
	defense["worked_example"] = {"input_components": example_components, "defense_stats": example_stats,
		"shield_before": 10.0, "health_before": 100.0,
		"trace": Defense.incoming_hit(example_components, example_stats, 10.0, 100.0, "player"),
		"monster_trace": Defense.incoming_hit(example_components, example_stats, 10.0, 100.0, "monster")}
	defense["cap_examples"] = []
	for amount: float in [-0.2, 0.0, 0.25, 0.75, 1.0]:
		defense.cap_examples.append(Defense.defense_profile({"fire_resistance": amount}, "player"))
	result["defenses"] = {defense.id: defense}
	var target_id: String = result.fire_encounter.template_id
	var target_wave: int = int(result.fire_encounter.minimum_wave)
	var target: Dictionary = Monsters.make_enemy(1, target_id, target_wave, Vector2.ZERO, "demo")
	result["known_target"] = {"template_id": target_id, "wave": target_wave,
		"defense_profile": Defense.defense_profile(target.defense_stats, "monster"),
		"shield": target.shield, "health": target.health}
	var fresh: RefCounted = Canonical.new()
	var full: RefCounted = Build.new()
	for item_id: String in Data.COMBAT_STARTER_ITEMS:
		full.equip(item_id)
	var normal_bow: RefCounted = local_build(_local_instance())
	var rolled_bow: RefCounted = local_build(_local_instance(["whetstone_edge", "tempered_edge", "wellturn", "beatlink"], "rare"))
	var builds: Dictionary = {"fresh": fresh, "full_tornado": full, "local_normal": normal_bow, "local_max": rolled_bow}
	result["configurations"] = {
		"fresh": {"name": "新建角色（当前源树属性）", "equipped": fresh.equipped.duplicate(), "allocated_nodes": fresh.snapshot().talents.allocated.duplicate(), "socketed_jewels": {}, "stats": fresh.get_stats()},
		"full_tornado": {"name": "历史龙卷装备演算（未含源树三属性）", "equipped": full.equipped.duplicate(), "allocated_nodes": full.allocated_nodes.duplicate(), "socketed_jewels": {}, "stats": full.get_stats()}}
	for config: String in ["local_normal", "local_max"]:
		var build: RefCounted = builds[config]
		result.configurations[config] = {"name": "普通白蜡长弓" if config == "local_normal" else "白蜡长弓 · 双局部前缀上限示例",
			"equipped": build.equipped.duplicate(), "allocated_nodes": build.allocated_nodes.duplicate(), "socketed_jewels": {},
			"stats": build.get_stats(), "equipment_instances": build.equipment_instances.duplicate(true),
			"weapon_definition": build.get_item_definition(build.equipped.weapon)}
	for id: String in Data.SKILLS:
		var skill: Dictionary = Data.SKILLS[id].duplicate(true)
		skill["compatible_supports"] = Supports.supports_for_skill(id)
		skill["minimum_save_version"] = 17 if Data.NEW_SKILL_IDS.has(id) else 14
		skill["examples"] = {}
		for config: String in builds:
			var build: RefCounted = builds[config]
			# Preserve the historical zero/two-slot reference rows. The new
			# delivery mode has a small explicit five-slot-compatible chapter.
			var historical_supports: Array = skill.compatible_supports.duplicate()
			historical_supports.erase("ambush")
			historical_supports.erase("inward_pull")
			historical_supports.erase("frost_lock")
			var combinations: Array = support_combinations(historical_supports)
			skill.examples[config] = []
			for combination: Array in combinations:
				if not Supports.compatibility_reason(id, combination).is_empty():
					continue
				var cast: Dictionary = Compiler.compile_skill(id, build.get_combat_snapshot(), combination)
				assert(cast.get("ok", false), "Reference examples require a successful production cast")
				var packets: Array = []
				for entry: Dictionary in Preview.entries(cast):
					var defended: Dictionary = Damage.resolve(entry.packet, cast.snapshot.modifiers, target.resistances)
					packets.append({"label": entry.label, "packet": entry.packet,
						"resolved": Damage.resolve(entry.packet, cast.snapshot.modifiers),
						"known_target_resolved": defended, "known_target_settlement": Defense.settle_resolved(defended, target.shield, target.health),
						"active": entry.label != "独立爆炸" or cast.snapshot.effects.has("explode_on_flight_end")})
				skill.examples[config].append({"supports": cast.support_ids, "mana": cast.mana, "cooldown": cast.cooldown,
					"initial_count": cast.initial_count, "summary": Preview.summary(cast), "details": Preview.details(cast),
					"recipe": cast.recipe, "packets": packets})
		result.skills[id] = skill
	# Cross-links compare the real compiler's direct hit results; no copied scope rules.
	for affix_id: String in result.affixes:
		var family: Dictionary = result.affixes[affix_id]
		family["affected_skills"] = []
		family["other_consumers"] = []
		var before_snapshot: Dictionary = fresh.get_combat_snapshot()
		var after_snapshot: Dictionary
		if family.get("stage") == WeaponLocal.STAGE:
			var candidate: RefCounted = local_build(_local_instance([affix_id], "magic"))
			before_snapshot = normal_bow.get_combat_snapshot()
			after_snapshot = candidate.get_combat_snapshot()
			family["scope_evidence"] = {"baseline_instance": normal_bow.equipment_instances[normal_bow.equipped.weapon],
				"candidate_instance": candidate.equipment_instances[candidate.equipped.weapon],
				"baseline_stats": normal_bow.get_stats(), "candidate_stats": candidate.get_stats(), "skills": {}}
		else:
			var boosted: Dictionary = fresh.get_stats()
			boosted[family.stat] = float(boosted.get(family.stat, 0.0)) + 1.0
			after_snapshot = Recipes.snapshot(boosted, [])
		for skill_id: String in Data.SKILLS:
			var before: Dictionary = Compiler.compile_skill(skill_id, before_snapshot, [])
			var after: Dictionary = Compiler.compile_skill(skill_id, after_snapshot, [])
			if not is_equal_approx(_direct_total(before), _direct_total(after)) or (Equipment.BuildAffixes.AFFIX_IDS.has(affix_id) and (before.get("critical",{})!=after.get("critical",{}) or before.get("leech",{})!=after.get("leech",{}))):
				family.affected_skills.append(skill_id)
			if family.has("scope_evidence"):
				family.scope_evidence.skills[skill_id] = {"before": _direct_total(before), "after": _direct_total(after),
					"secondary_unchanged": before.packets.get("secondary", {}) == after.packets.get("secondary", {})}
		if family.has("scope_evidence"):
			var before_basic: Dictionary = Recipes.event_packet(before_snapshot, "basic", "projectile")
			var after_basic: Dictionary = Recipes.event_packet(after_snapshot, "basic", "projectile")
			family.scope_evidence["basic"] = {"before": Damage.resolve(before_basic, before_snapshot.modifiers),
				"after": Damage.resolve(after_basic, after_snapshot.modifiers)}
			if not is_equal_approx(family.scope_evidence.basic.before.total, family.scope_evidence.basic.after.total):
				family.other_consumers.append("basic")
	var weapon_stage: Dictionary = WeaponLocal.metadata()
	weapon_stage["examples"] = {}
	for config: String in ["local_normal", "local_max"]:
		var build: RefCounted = builds[config]
		var snapshot: Dictionary = build.get_combat_snapshot()
		var resolved: Dictionary = WeaponLocal.resolve(snapshot.weapon_profile)
		var sample: Dictionary = {"configuration": config, "instance": build.equipment_instances[build.equipped.weapon],
			"definition": build.get_item_definition(build.equipped.weapon), "resolved_weapon": resolved, "snapshot": snapshot, "hits": {}}
		var tornado: Dictionary = Compiler.compile_skill("tornado", snapshot, [])
		for role: String in ["basic", "parent", "child", "secondary"]:
			var packet: Dictionary = Recipes.event_packet(snapshot, "basic", "projectile") if role == "basic" else tornado.packets[role]
			var defended: Dictionary = Damage.resolve(packet, snapshot.modifiers, target.resistances)
			sample.hits[role] = {"packet": packet, "resolved": Damage.resolve(packet, snapshot.modifiers),
				"known_target_resolved": defended, "known_target_settlement": Defense.settle_resolved(defended, target.shield, target.health),
				"active": role != "secondary" or snapshot.effects.has("explode_on_flight_end")}
		weapon_stage.examples[config] = sample
	result["weapon_stages"] = {weapon_stage.id: weapon_stage}
	for id: String in Jewels.BASES:
		var jewel: Dictionary = Jewels.BASES[id].duplicate(true)
		jewel["kind"] = "ordinary"
		jewel["examples"] = []
		for instance: Dictionary in Jewels.starter_jewels().values():
			if instance.base == id:
				jewel.examples.append({"name": Jewels.display_name(instance), "description": Jewels.get_description(instance), "stats": Jewels.get_stats(instance)})
		result.jewels[id] = jewel
	for id: String in Jewels.AFFIXES:
		var affix: Dictionary = Jewels.AFFIXES[id].duplicate(true)
		affix["range_text"] = Passives.describe_stats({affix.stat: affix.min}) + " ～ " + Passives.describe_stats({affix.stat: affix.max})
		result.jewel_affixes[id] = affix
	for id: String in Registry.get_ids():
		result.mechanisms[id] = mechanism_reference(id)
	for id: String in Monsters.TEMPLATES:
		var template: Dictionary = Monsters.TEMPLATES[id].duplicate(true)
		var context: String = "level_boss" if template.rarity == "boss" else "demo"
		var example_wave: int = target_wave if id == target_id else int(Monsters.ELEMENTAL_ENCOUNTERS[id].minimum_wave) if Monsters.ELEMENTAL_ENCOUNTERS.has(id) else 1
		if id == "mist_skitter":
			context = "ordinary"
			example_wave = int(MapRules.compile_normal("sunwell_terrace", 2, [], []).profile.wave)
		template["example_wave"] = example_wave
		template["runtime_example"] = Monsters.make_enemy(1, id, example_wave, Vector2.ZERO, context)
		template["contact_components"] = Monsters.contact_components(template.runtime_example)
		template["mechanism_text"] = Monsters.mechanism_text(template.runtime_example)
		template["telegraph_policy"] = Monsters.telegraph_policy(template.runtime_example)
		if Monsters.ELEMENTAL_ENCOUNTERS.has(id):
			template["attack_reference"] = "locked_circle_"+str(Monsters.ELEMENTAL_ENCOUNTERS[id].element)
			template["natural_selection"] = Monsters.ELEMENTAL_ENCOUNTERS[id].duplicate(true)
		template["defense_profile"] = Defense.defense_profile(template.runtime_example.defense_stats, "monster")
		template["source_ratings"] = AttackRules.monster_profile(int(template.runtime_example.kind))
		if id == "mist_skitter":
			template.source_ratings.evasion = template.runtime_example.evasion
			template["encounter_budget"] = mist_skitter_examples(template.runtime_example)
		result.monsters[id] = template
	result["special_coverage"] = {}
	for id: String in Jewels.SPECIAL_BASES:
		var special: Dictionary = Jewels.base_definition(id)
		var instance: Dictionary = Jewels.generate_special("jewel_000004")
		special["kind"] = "special"
		special["description"] = Jewels.get_description(instance)
		special["rule"] = Jewels.allocation_rule(instance)
		result.jewels[id] = special
	var graph: Dictionary = Passives.get_nodes()
	for socket_id: String in graph:
		if graph[socket_id].type != "socket":
			continue
		var path: Array = _path_to(socket_id, graph)
		var jewel: Dictionary = Jewels.generate_special("jewel_000004")
		var owned: Dictionary = {jewel.id: jewel}
		var sockets: Dictionary = {socket_id: jewel.id}
		var analysis: Dictionary = Rules.analyze(path, sockets, owned)
		var remote_example: String = ""
		for id: String in graph:
			if path.has(id) or not analysis.granted_by.has(id):
				continue
			var candidate: Array = path.duplicate()
			candidate.append(id)
			var proposed: Dictionary = Rules.analyze(candidate, sockets, owned)
			if proposed.legal and proposed.remote_nodes.has(id):
				remote_example = id
				if graph[id].type == "notable":
					break
		var remote_path: Array = path.duplicate()
		if not remote_example.is_empty():
			remote_path.append(remote_example)
		result.special_coverage[socket_id] = {"path": path, "connected": analysis,
			"disconnected": Rules.analyze([Passives.START_ID, socket_id], sockets, owned),
			"remote_example": remote_example, "with_remote": Rules.analyze(remote_path, sockets, owned)}
	return result


static func canonical_examples()->Dictionary:
	var state:=Canonical.new()
	var bag:Dictionary=state.bag_layout()
	var casts:Dictionary={}
	for group:Dictionary in state.snapshot().skill_groups:
		var cast:Dictionary=state.get_group_cast(group.id)
		if cast.get("ok",false):casts[group.id]={"skill_id":cast.skill_id,"mana":cast.mana,"cooldown":cast.cooldown,"summary":Preview.summary(cast),"details":Preview.details(cast)}
	var slots:Dictionary={}
	for slot:String in EquipmentSlotsData.all_slots():slots[slot]=EquipmentSlotsData.category_for_slot(slot)
	var five:=Compiler.compile_group("frost",state.get_combat_snapshot(),["swift_projectiles","heavy_projectiles","lingering_chill","efficiency","quickcast"])
	return {"save_version":Canonical.Rules.VERSION,"bag_pages":bag.pages,"bag_columns":bag.columns,"bag_rows":bag.rows,"base_skill_groups":10,"support_slots":5,
		"flask_slots":state.flask_slots(),"slots":slots,"gem_definitions":GemCatalogData.definitions(),"default_build":state.snapshot(),"default_stats":state.get_stats(),"default_casts":casts,"five_link_example":support_cast_brief(five),
		"gem_reward":{"eligible_root_kill_interval":30,"definition_count":GemCatalogData.definitions().size(),"mode":"test","normal_frozen_definition_count":Canonical.Journey.GEM_DEFINITIONS.size(),"uniform_selection":true,"level":1,"quality":0,"duplicate_definitions_have_distinct_uid":true,"failed_admission_restores_rng":true},
		"defense_example":Defense.incoming_source_hit({"physical":100.0,"fire":100.0,"cold":100.0,"lightning":100.0},{"armour":500.0,"fire_resistance":0.5,"cold_resistance":0.25,"lightning_resistance":0.75},100.0,200.0),
		"monster_ratings":{"crawler":AttackRules.monster_profile(0),"skitter":AttackRules.monster_profile(1),"brute":AttackRules.monster_profile(2)},
		"skitter_accuracy_example":{"base_accuracy":140,"base_chance":AttackRules.chance(140,320),"extra_ten_dex_accuracy":160,"improved_chance":AttackRules.chance(160,320)}}


static func currency_examples()->Dictionary:
	if Canonical.Rules.VERSION < 16: return {}
	var instance := {"uid":"catalog_currency_example","kind":"currency",
		"definition_id":"currency:"+Craft.MATERIAL_ID,"payload":{"quantity":1}}
	var definition: Dictionary = Canonical.Items.definition_for_instance(instance)
	assert(not definition.is_empty(),"Current-schema currency must resolve through the real item catalog")
	assert(int(definition.get("stack_limit",0)) > 0,"Currency stack limit must be exported by its definition")
	return {Craft.MATERIAL_ID:{"name":str(definition.name),"description":str(definition.get("description","")),
		"definition_id":instance.definition_id,"size":[1,1],"stack_limit":int(definition.stack_limit),
		"example_quantity":1,"quantity_source":"items[uid].payload.quantity","save_version":Canonical.Rules.VERSION,
		"bag_pages":Canonical.new().bag_layout(),"example_instance":instance}}


static func mechanism_reference(id: String) -> Dictionary:
	var mechanism: Dictionary = Registry.get_definition(id)
	var refs: Array = []
	for source: Dictionary in mechanism.get("source_refs", []):
		if SourceMonster.owns(id):
			refs.append(source.duplicate(true))
		else:
			refs.append({"modifier_id": source.get("modifier_id"), "target_stat": source.get("target_stat"),
				"adaptation": source.get("adaptation"), "source_value": source.get("source_value"),
				"scale": source.get("scale"), "reference_base": source.get("reference_base")})
	mechanism["source_refs"] = refs
	# Capacity mode is separate from flat stats; 0.05 must display as 5%, never +0.05 life.
	var descriptions: PackedStringArray = []
	var flat_description: String = Passives.describe_stats(mechanism.stats)
	if id == "source_aegis_recovery":
		flat_description = "能量护盾回复率提高 %s%%" % str(float(mechanism.stats.shield_recharge_rate_increased) * 100.0)
	if not flat_description.is_empty(): descriptions.append(flat_description)
	for stat: String in mechanism.get("capacity_increased", {}):
		assert(stat in ["max_health", "max_shield"])
		var label: String = "最大生命" if stat == "max_health" else "最大能量护盾"
		descriptions.append("%s提高 %s%%" % [label, str(float(mechanism.capacity_increased[stat]) * 100.0)])
	mechanism["description"] = "\n".join(descriptions)
	return mechanism


## Narrow integration never parses or rewrites historical catalog values in Godot.
## Python merges these new values into the exact checked-in baseline text.
static func source_monster_fragment() -> Dictionary:
	var mechanisms: Dictionary = {}
	for id: String in SourceMonster.IDS:
		mechanisms[id] = mechanism_reference(id)
	var updates: Dictionary = _source_monster_current_updates()
	return {"game_version":ProjectSettings.get_setting("application/config/version"),
		"mechanisms":mechanisms, "source_monster_shield_recharge":source_monster_shield_recharge_examples(),
		"movement_updates":updates,
		"damage_life_updates":updates.merged({"current_source_definition_count":SourceMonster.IDS.size(),
			"cache":"按五个明确ID独立缓存来源身份、原始行与当前政策；复苏两行作为原子包；最多五项，出生快照冻结，每帧不重新解析",
			"sampler":"ordinary_roll_source_damage_life冻结v2伤害/生命池；ordinary_roll_current为v3，仅把普通三物种最后两个辉壁槽替换为新ID；见源护盾与回复章节；无额外RNG、名额或奖励"})}


static func _source_monster_current_updates() -> Dictionary:
	return {"current_definition_count":Registry.get_ids().size(),
		"stride_pool":Monsters.STRIDE_AFFIX_POOL.duplicate(),
		"damage_life_pool":Monsters.DAMAGE_LIFE_AFFIX_POOL.duplicate(),
		"current_pool":Monsters.CURRENT_AFFIX_POOL.duplicate(),
		"legacy_roll_policy":Monsters.LEGACY_ROLL_POLICY,"stride_roll_policy":Monsters.STRIDE_ROLL_POLICY,
		"damage_life_roll_policy":Monsters.DAMAGE_LIFE_ROLL_POLICY,"current_roll_policy":Monsters.CURRENT_ROLL_POLICY}


static func source_monster_shield_recharge_examples() -> Dictionary:
	var bindings: Dictionary = {}
	for pair: Array in [["source_aegis_capacity","aegis_capacity"],["source_aegis_recovery","aegis_recovery"]]:
		var id: String = pair[0]
		var source: Dictionary = SourceMonster.resolve(id)
		assert(source.ok)
		var definition: Dictionary = source.definition
		var entries: Array = definition.source_refs
		var effects: Array[Dictionary] = []
		var grants: Array = []
		for entry: Dictionary in entries:
			var effect: Dictionary = SourceTree.line_effect(entry.raw_line, SourceTree.CURRENT_SAVE_VERSION)
			assert(effect.supported and effect.grants.size() == 1)
			effects.append(effect)
			grants.append_array(effect.grants)
		assert(grants == definition.typed_grants)
		var player: Dictionary = Registry.resolve(id,"player")
		var monster: Dictionary = Registry.resolve(id,"monster")
		var legacy: Dictionary = Registry.resolve(pair[1],"monster")
		assert(player.ok and monster.ok and legacy.ok)
		assert(player.stats == monster.stats and player.capacity_increased == monster.capacity_increased)
		assert(not player.stats.has("max_shield") and not player.stats.has("shield_regen"))
		assert(not monster.stats.has("max_shield") and not monster.stats.has("shield_regen"))
		assert(not player.stats.has("shield_recharge_start_faster"))
		bindings[id] = {"legacy_id":pair[1],"definition":definition,"source_entries":entries,
			"source_effects":effects,"player_grant":player,"monster_grant":monster,
			"legacy_grant":legacy,"actor_coefficient":monster.role_coefficient}
	var shield_map: Dictionary = EncounterCompiler.compile(["enemy_shield_from_health_20"])
	var strong_map: Dictionary = EncounterCompiler.compile(["enemy_max_health_120","enemy_shield_from_health_20"])
	assert(shield_map.ok and strong_map.ok)
	var variants: Dictionary = {"base":[],"legacy_capacity":["aegis_capacity"],
		"legacy_recovery":["aegis_recovery"],"legacy_pair":["aegis_capacity","aegis_recovery"],
		"current_capacity":["source_aegis_capacity"],"current_recovery":["source_aegis_recovery"],
		"current_pair":["source_aegis_capacity","source_aegis_recovery"]}
	var budget: Array[Dictionary] = []
	for sample: Array in [["crawler",2],["brute",10]]:
		var template_id: String = sample[0]
		var wave: int = sample[1]
		var examples: Dictionary = {}
		for key: String in variants:
			var plain: Dictionary = Monsters.make_enemy(1,template_id,wave,Vector2.ZERO,"demo","rare",variants[key])
			assert(not plain.is_empty())
			var profile: Dictionary = _monster_recharge_reference(plain)
			var mapped: Dictionary = EncounterCompiler.apply_to_enemy(plain,shield_map.profile)
			var strong: Dictionary = EncounterCompiler.apply_to_enemy(plain,strong_map.profile)
			assert(mapped.ok and strong.ok)
			var multiplier: float = float(plain.get("source_shield_profile",{}).get("capacity_multiplier",1.0))
			var map_base: float = float(plain.max_health) * 0.20
			var added: float = map_base * multiplier
			assert(is_equal_approx(mapped.enemy.max_shield,plain.max_shield + added))
			assert(is_equal_approx(strong.enemy.max_shield,mapped.enemy.max_shield))
			assert(is_equal_approx(strong.enemy.max_health,plain.max_health * 1.20))
			var damaged: Dictionary = plain.duplicate(true)
			damaged.shield = maxf(0.0,float(plain.shield) - 1.0)
			var damaged_map: Dictionary = EncounterCompiler.apply_to_enemy(damaged,shield_map.profile)
			assert(damaged_map.ok)
			assert(is_equal_approx(damaged.max_shield - damaged.shield,damaged_map.enemy.max_shield - damaged_map.enemy.shield))
			examples[key] = {"plain":plain,"recharge_profile":profile,"map":mapped.enemy,
				"strong_map":strong.enemy,"map_base_shield":map_base,"map_shield_bonus":added,
				"damaged_plain":damaged,"damaged_map":damaged_map.enemy,
				"missing_shield_preserved":damaged.max_shield - damaged.shield}
		assert(is_equal_approx(examples.current_capacity.plain.max_shield,3.3696))
		assert(is_equal_approx(examples.current_capacity.recharge_profile.rate,0.0))
		assert(is_equal_approx(examples.current_recovery.plain.max_shield,1.6224))
		assert(is_equal_approx(examples.current_recovery.recharge_profile.rate,0.46475))
		assert(is_equal_approx(examples.current_pair.plain.max_shield,5.2416))
		assert(is_equal_approx(examples.current_pair.recharge_profile.rate,0.46475))
		budget.append({"template_id":template_id,"wave":wave,"rarity":"rare","examples":examples})
	var result: Dictionary = _source_monster_current_updates()
	result.merge({"bindings":bindings,"budget":budget,"legacy_pool":Monsters.AFFIX_POOL.duplicate(),
		"legacy_definition_count":Balance.definitions().size(),"current_source_definition_count":SourceMonster.IDS.size(),
		"save_version":Canonical.Rules.VERSION,"equipment_vocabulary":Equipment.CURRENT_VOCABULARY,
		"source_policy":SourceTree.CURRENT_SAVE_VERSION,"budget_policy":Monsters.ShieldSupply.POLICY,
		"supplies":Monsters.ShieldSupply.SUPPLIES.duplicate(true),"shield_map_profile":shield_map.profile,
		"strong_shield_map_profile":strong_map.profile,
		"capacity_formula":"(legacy_flat_shield + sum_authored_monster_shield_supply) * (1 + sum_source_max_shield_increased)",
		"recharge_formula":"(legacy_flat_recharge_rate + sum_authored_monster_recharge_supply) * (1 + sum_source_recharge_rate_increased)",
		"map_formula":"existing_canonical_shield + (0.20 * canonical_max_health_before_strong) * frozen_capacity_multiplier",
		"boundary":"只绑定58218:0与原子组合21929:1、6949:1；不授予同节点其他行、整节点或更快开始回复；源授予没有固定护盾或固定回复，玩家不获怪物供给",
		"snapshot":"source_shield_profile冻结budget_policy、supplies、基础护盾/回复与capacity_multiplier；地图仅读取出生快照，不重解析源树，不对旧护盾S再次乘提高",
		"map_order":"M=0.20×强健前canonical最大生命；有新身份时当前与最大护盾各加M×冻结倍率，无新身份仍各加原M；缺失护盾量保持；这是新身份的有意预算变化，不宣称旧新地图等价",
		"cache":"最多五个明确身份缓存；复苏两条来源与两种类型化授予原子验证、原子失效；source_entry仅第一条展示别名，以source_entries和source_refs读取完整双来源",
		"budget_scope":"第2波金色巡游体与第10波金色重壳体；真实MonsterCatalog与EncounterCompiler生成；独立原创怪物预算，不是PoE固定效果或DPS，也不声称全局平衡",
		"sampler":"ordinary_roll_current采用source_shield_v3，仅替换普通三物种五槽池最后两槽；legacy、stride、damage_life三代入口冻结；历史别名、显式特殊模板、首领、后代、RNG消耗、名额与奖励资格不变"})
	return result


static func _monster_recharge_reference(enemy: Dictionary) -> Dictionary:
	var inputs: Dictionary = enemy.mechanism_stats.duplicate(true)
	inputs.shield_regen = enemy.shield_regen
	var profile: Dictionary = Defense.recharge_profile(inputs,"monster")
	assert(profile.ok and is_equal_approx(profile.delay,4.0))
	assert(is_equal_approx(float(enemy.get("shield_recharge_rate",enemy.shield_regen)),profile.rate))
	return profile


static func source_monster_damage_life_examples() -> Dictionary:
	var bindings: Dictionary = {}
	for pair: Array in [["source_ember_power", "ember_power"], ["source_grove_vitality", "grove_vitality"]]:
		var id: String = pair[0]
		var source: Dictionary = SourceMonster.resolve(id)
		assert(source.ok)
		var definition: Dictionary = source.definition
		var entry: Dictionary = definition.source_entry
		var effect: Dictionary = SourceTree.line_effect(entry.raw_line, SourceTree.CURRENT_SAVE_VERSION)
		var player: Dictionary = Registry.resolve(id, "player")
		var monster: Dictionary = Registry.resolve(id, "monster")
		var legacy: Dictionary = Registry.resolve(pair[1], "monster")
		assert(effect.supported and player.ok and monster.ok and legacy.ok)
		assert(effect.grants.size() == 1 and effect.grants == definition.typed_grants)
		assert(player.stats == monster.stats and monster.stats == source.stats)
		assert(player.get("capacity_increased", {}) == monster.get("capacity_increased", {}))
		assert(monster.get("capacity_increased", {}) == source.get("capacity_increased", {}))
		bindings[id] = {"legacy_id":pair[1], "definition":definition, "source_entry":entry,
			"source_effect":effect, "player_grant":player, "monster_grant":monster,
			"legacy_grant":legacy, "actor_coefficient":monster.role_coefficient}
	var damage_increase: float = bindings.source_ember_power.monster_grant.stats.global_increased
	var life_increase: float = bindings.source_grove_vitality.monster_grant.capacity_increased.max_health
	var budget: Array[Dictionary] = []
	for wave: int in [1, 6, 10, 15]:
		var rarity: String = "magic" if wave == 1 else "rare"
		for template_id: String in ["crawler", "skitter", "brute"]:
			var base: Dictionary = Monsters.make_enemy(1, template_id, wave, Vector2.ZERO, "demo", rarity, [])
			var old_damage: Dictionary = Monsters.make_enemy(1, template_id, wave, Vector2.ZERO, "demo", rarity, ["ember_power"])
			var current_damage: Dictionary = Monsters.make_enemy(1, template_id, wave, Vector2.ZERO, "demo", rarity, ["source_ember_power"])
			var old_life: Dictionary = Monsters.make_enemy(1, template_id, wave, Vector2.ZERO, "demo", rarity, ["grove_vitality"])
			var current_life: Dictionary = Monsters.make_enemy(1, template_id, wave, Vector2.ZERO, "demo", rarity, ["source_grove_vitality"])
			for enemy: Dictionary in [base, old_damage, current_damage, old_life, current_life]: assert(not enemy.is_empty())
			var species: Dictionary = Monsters.SPECIES[int(Monsters.TEMPLATES[template_id].kind)]
			var tier: Dictionary = Monsters.RARITIES[rarity]
			var hp_base: float = float(species.health) * (1.0 + (wave - 1) * 0.16) * float(tier.health)
			var damage_base: float = (float(species.damage) + (wave - 1) * 0.7) * float(tier.damage)
			assert(is_equal_approx(base.health, hp_base) and is_equal_approx(base.damage, damage_base))
			assert(is_equal_approx(old_life.health, base.health + float(bindings.source_grove_vitality.legacy_grant.stats.max_health)))
			assert(is_equal_approx(old_damage.damage, base.damage + float(bindings.source_ember_power.legacy_grant.stats.damage)))
			assert(is_equal_approx(current_life.health, base.health * (1.0 + life_increase)))
			assert(is_equal_approx(current_damage.damage, base.damage * (1.0 + damage_increase)))
			budget.append({"template_id":template_id, "wave":wave, "rarity":rarity,
				"species":species.duplicate(true), "rarity_multipliers":{"health":tier.health, "damage":tier.damage},
				"base":base, "legacy_damage":old_damage, "current_damage":current_damage,
				"legacy_life":old_life, "current_life":current_life,
				"damage_delta":current_damage.damage - old_damage.damage,
				"life_delta":current_life.health - old_life.health})
	var mixed_damage: Dictionary = Monsters.make_enemy(1, "brute", 6, Vector2.ZERO, "demo", "rare", ["ember_power", "source_ember_power"])
	var mixed_life: Dictionary = Monsters.make_enemy(1, "brute", 6, Vector2.ZERO, "demo", "rare", ["grove_vitality", "source_grove_vitality"])
	var plain: Dictionary = Monsters.make_enemy(1, "brute", 6, Vector2.ZERO, "demo", "rare", [])
	assert(is_equal_approx(mixed_damage.damage, (plain.damage + float(bindings.source_ember_power.legacy_grant.stats.damage)) * (1.0 + damage_increase)))
	assert(is_equal_approx(mixed_life.health, (plain.health + float(bindings.source_grove_vitality.legacy_grant.stats.max_health)) * (1.0 + life_increase)))
	var unsupported: Dictionary = Registry.resolve("poe_global_damage", "monster")
	assert(not unsupported.ok)
	return {"bindings":bindings, "budget":budget,
		"mixed_fixed_before_increased":{"base":plain, "damage":mixed_damage, "life":mixed_life},
		"legacy_player_only_rejection":unsupported,
		"legacy_pool":Monsters.AFFIX_POOL.duplicate(), "stride_pool":Monsters.STRIDE_AFFIX_POOL.duplicate(),
		"damage_life_pool":Monsters.DAMAGE_LIFE_AFFIX_POOL.duplicate(), "damage_life_roll_policy":Monsters.DAMAGE_LIFE_ROLL_POLICY,
		"current_pool":Monsters.CURRENT_AFFIX_POOL.duplicate(), "legacy_roll_policy":Monsters.LEGACY_ROLL_POLICY,
		"stride_roll_policy":Monsters.STRIDE_ROLL_POLICY, "current_roll_policy":Monsters.CURRENT_ROLL_POLICY,
		"legacy_definition_count":Balance.definitions().size(), "current_source_definition_count":SourceMonster.IDS.size(),
		"current_definition_count":Registry.get_ids().size(), "save_version":Canonical.Rules.VERSION,
		"equipment_vocabulary":Equipment.CURRENT_VOCABULARY, "source_policy":SourceTree.CURRENT_SAVE_VERSION,
		"damage_formula":"((species_damage + (wave - 1) * 0.7) * rarity_damage + flat_damage) * (1 + sum_global_increased)",
		"life_formula":"(species_health * (1 + (wave - 1) * 0.16) * rarity_health + flat_max_health) * (1 + sum_max_health_increased)",
		"budget_scope":"独立单词缀工厂对照；第1波蓝色，第6/10/15波金色；每格由实际MonsterCatalog生成，地图倍率前；不是自然分布或DPS评分",
		"boundary":"只绑定13219:0的伤害提高和52282:0的最大生命提高；不授予整个节点、升华资格、Body Transfiguration或其他源效果",
		"cache":"按五个明确ID独立缓存来源身份、原始行与当前政策；复苏两行作为原子包；最多五项，出生快照冻结，每帧不重新解析",
		"map_order":"先固定基底，再同类increased加算并乘一次，之后应用现有地图倍率；20% canonical生命护盾仍按既有依赖取最终canonical生命",
		"sampler":"ordinary_roll_source_damage_life冻结v2伤害/生命池；ordinary_roll_current为v3，仅把普通三物种最后两个辉壁槽替换为新ID；见源护盾与回复章节；无额外RNG、名额或奖励"}


static func source_monster_movement_examples() -> Dictionary:
	var source: Dictionary = SourceMonster.resolve(SourceMonster.ID)
	assert(source.ok, "Source movement reference requires the validated current source entry")
	var definition: Dictionary = source.definition
	var entry: Dictionary = definition.source_entry
	var effect: Dictionary = SourceTree.line_effect(entry.raw_line, SourceTree.CURRENT_SAVE_VERSION)
	var player: Dictionary = Registry.resolve(SourceMonster.ID, "player")
	var monster: Dictionary = Registry.resolve(SourceMonster.ID, "monster")
	var legacy: Dictionary = Registry.resolve("gale_stride", "monster")
	assert(effect.supported and player.ok and monster.ok and legacy.ok)
	assert(effect.grants.size() == 1 and player.stats == monster.stats and monster.stats == source.stats)
	assert(float(effect.grants[0].value) == float(monster.stats.move_speed_increased))
	var budget: Array[Dictionary] = []
	for wave: int in [1, 6, 10, 15]:
		for template_id: String in ["crawler", "skitter", "brute"]:
			var base: Dictionary = Monsters.make_enemy(1, template_id, wave, Vector2.ZERO, "demo", "magic", [])
			var old: Dictionary = Monsters.make_enemy(1, template_id, wave, Vector2.ZERO, "demo", "magic", ["gale_stride"])
			var current: Dictionary = Monsters.make_enemy(1, template_id, wave, Vector2.ZERO, "demo", "magic", [SourceMonster.ID])
			assert(not base.is_empty() and not old.is_empty() and not current.is_empty())
			assert(is_equal_approx(current.speed, base.speed * (1.0 + float(monster.stats.move_speed_increased))))
			budget.append({"template_id": template_id, "wave": wave, "base": base, "legacy": old, "current": current,
				"speed_delta": current.speed - old.speed, "relative_to_legacy": current.speed / old.speed - 1.0})
	return {"mechanism_id": SourceMonster.ID, "legacy_id": "gale_stride", "save_version": Canonical.Rules.VERSION,
		"equipment_vocabulary": Equipment.CURRENT_VOCABULARY, "source_policy": SourceTree.CURRENT_SAVE_VERSION,
		"definition": definition, "source_entry": entry, "source_effect": effect, "player_grant": player,
		"monster_grant": monster, "legacy_grant": legacy, "actor_coefficient": monster.role_coefficient,
		"legacy_pool": Monsters.AFFIX_POOL.duplicate(), "stride_pool": Monsters.STRIDE_AFFIX_POOL.duplicate(), "current_pool": Monsters.CURRENT_AFFIX_POOL.duplicate(),
		"legacy_roll_policy": Monsters.LEGACY_ROLL_POLICY, "stride_roll_policy": Monsters.STRIDE_ROLL_POLICY, "current_roll_policy": Monsters.CURRENT_ROLL_POLICY,
		"damage_life_pool":Monsters.DAMAGE_LIFE_AFFIX_POOL.duplicate(), "damage_life_roll_policy":Monsters.DAMAGE_LIFE_ROLL_POLICY,
		"legacy_definition_count": Balance.definitions().size(), "current_definition_count": Registry.get_ids().size(),
		"budget": budget, "formula": "(species + wave + other_flat) * (1 + move_speed_increased)",
		"budget_scope": "同物种、波次与蓝色稀有度的单移动词缀对照；由实际MonsterCatalog生成，地图倍率前；不是综合难度评分",
		"current_admission": "当前Main普通入场及当前地图据点显式选择current入口；历史ordinary_roll与旧地图帮助函数保持",
		"boundary": "只绑定63417的stat_index 1；不授予同节点护甲、整个节点、升华资格或其他源基石"}


static func source_tree_reference()->Dictionary:
	var nodes:Dictionary={}
	var standard:Dictionary={}
	for id:String in SourceTree.Data.standard_ids():standard[id]=true
	var edges:Array=[]
	for id:String in standard:
		for adjacent:String in SourceTree.Data.adjacency(id):
			if id<adjacent:edges.append([id,adjacent])
	for id:String in SourceTree.Data.nodes():
		var node:=SourceTree.Data.node(id)
		var effect:=SourceTree.node_effect(id)
		var choices:Array=[]
		for choice:Dictionary in node.mastery_effects:
			choices.append({"effect":int(choice.effect),"stats":choice.stats,"execution":SourceTree.node_effect(id,int(choice.effect))})
		nodes[id]={"id":id,"name":node.name,"type":node.type,"stats":node.stats,"position":node.position,"has_position":node.has_position,
			"standard_graph":standard.has(id),"source_proxy":bool(node.source.get("isProxy",false)),"blighted_only":bool(node.source.get("isBlighted",false)),
			"execution":effect,"mastery_choices":choices,"neighbors":SourceTree.Data.adjacency(id) if standard.has(id) else [],
			"partition":str(node.source.get("ascendancyName","expansion" if node.source.has("expansionJewel") else "standard"))}
	return {"source_version":"3.29.1","source_commit":"8bd138b32ea2631455cac5935bfab089f826094f","source_sha256":SourceTree.Data.SOURCE_SHA256,
		"source_url":"https://github.com/grindinggear/skilltree-export/tree/8bd138b32ea2631455cac5935bfab089f826094f","nodes":nodes,"edges":edges,"starts":SourceTree.Data.class_starts(),"points":SourceTree.Data.source_points()}


## Display-only export. English source records and execution stay authoritative above.
## The shared Godot localization adapter owns translations and per-line support status.
static func source_tree_localization_reference(source: Dictionary) -> Dictionary:
	assert(SourceLocalization.ready(), "Reference requires the pinned Chinese passive mapping")
	var nodes: Dictionary = {}
	var source_lines: Dictionary = {}
	var partitions: Dictionary = {}
	for id: String in source.nodes:
		var node: Dictionary = source.nodes[id]
		var choices: Dictionary = {}
		var raw_lines: Array = node.stats.duplicate()
		for choice: Dictionary in node.mastery_choices:
			choices[str(int(choice.effect))] = SourceLocalization.display_lines(choice.stats,"\n",id)
			raw_lines.append_array(choice.stats)
		for raw_line: String in raw_lines:
			if not source_lines.has(raw_line):
				source_lines[raw_line] = {"text": SourceLocalization.display_lines([raw_line]),
					"status": SourceLocalization.line_status(raw_line)}
		var partition_label: String = "标准主树" if node.partition == "standard" else "扩展珠宝分区 · 仅浏览" if node.partition == "expansion" else SourceLocalization.partition_label(node.partition)
		partitions[node.partition] = partition_label
		nodes[id] = {"name": SourceLocalization.node_name(id),
			"stats": SourceLocalization.display_lines(node.stats,"\n",id),
			"partition": partition_label, "mastery_choices": choices}
	return {"locale": "zh-CN", "source_sha256": SourceTree.Data.SOURCE_SHA256,
		"nodes": nodes, "lines": source_lines, "partitions": partitions,
		"not_implemented_suffix": SourceLocalization.NOT_IMPLEMENTED}


## Pure example plans: no model-issued handles, userdata reads or save writes.
## Full candidates still pass the same BuildState inventory/jewel validator.
static func town_map_examples()->Dictionary:
	var stock:Dictionary={}
	for service:String in ["skill_merchant","equipment_merchant","jewel_merchant"]:stock[service]=Town.offers(service)
	var options:=Maps.options()
	var examples:Dictionary={}
	for map:Dictionary in options.maps:
		var special:Array=["storm_patrol"] if map.id=="broken_ruins" else ["frost_patrol"]
		var compiled:=MapRules.compile(map.id,["enemy_max_health_120","enemy_move_speed_110"],special)
		assert(compiled.ok)
		var replacements:Dictionary={}
		for species:String in ["crawler","brute","skitter"]:
			replacements[species]=MapRules.special_template(compiled.profile,{"template":species,"rarity":"normal","mechanisms":[]})
		var geometry:=MapGeometryData.new();geometry.configure(map.id,LEGACY_REFERENCE_BOUNDS)
		var layout:Dictionary=geometry.snapshot();var walls:Array=[]
		for wall:Rect2 in layout.walls:walls.append({"position":wall.position,"size":wall.size})
		examples[map.id]={"compiled":compiled.profile,"special_replacements":replacements,
			"geometry":{"bounds":{"position":layout.bounds.position,"size":layout.bounds.size},"walls":walls,"spawn":layout.spawn,
				"collision":"radius_expanded_sweep_slide","navigation":"shared_radius_visibility_graph","projectile_wall_end":"terrain_collision",
				"wall_triggers_natural_end":false,"area_line_of_sight":true}}
		if layout.has("obstacle_style"):
			examples[map.id].geometry.obstacle_style=layout.obstacle_style
			examples[map.id].geometry.entry=CampLayoutData.layout(map.id,LEGACY_REFERENCE_BOUNDS).landmarks.entry
	var defenses:Dictionary={}
	var aegis:Dictionary=MapRules.compile("old_garden",[],["elemental_aegis"]).profile
	var packet:Dictionary=Damage.packet({"physical":100.0,"fire":100.0,"cold":100.0,"lightning":100.0,"chaos":100.0},["hit"],"reference_aegis")
	for template:String in ["crawler","ember_guard"]:
		var source:Dictionary=Monsters.make_enemy(1,template,4,Vector2.ZERO,"ordinary")
		var applied:Dictionary=MapDefense.apply_to_enemy(source,aegis)
		assert(applied.ok)
		defenses[template]={"source_stats":source.defense_stats,"raw_resistances":applied.enemy.map_defense_source.raw_resistances,
			"effective_resistances":applied.enemy.resistances,"incoming":packet.base,
			"before_components":Damage.resolve(packet,[],source.resistances).components,
			"after_components":Damage.resolve(packet,[],applied.enemy.resistances).components}
	return {"services":Town.services(),"stock":stock,"options":options,"examples":examples,"defense_examples":defenses,
		"equipment_purchase":EquipmentPurchaseReference.collect(),
		"jewel_purchase":JewelPurchaseReference.collect(),
		"flask_purchase":FlaskPurchaseReference.collect(),
		"chaos_aegis":ChaosAegisReference.collect(),
		"mode":"optional_town_test","normal_save":"user://build_save.json","test_save":"user://town_test_build_save.json",
		"clone_policy":"explicit_first_entry_only","supply_setting":"testing/town_supply_enabled","map_reward_bonus":false,
		"save_version":Canonical.Rules.VERSION,"retired_profile_writes":false,"map_runtime_persistent":false,
		"reserved_character_key":"C","legacy_C_binding":"unbound_with_notice_and_raw_byte_backup"}


static func crafting_examples(selected_operations: Array = []) -> Dictionary:
	var metadata: Dictionary = Craft.metadata()
	metadata["integration_status"] = "implemented"
	var result: Dictionary = {Craft.MATERIAL_ID: {"name": "校准碎片", "kind": "material",
		"description": "回收背包中的随机魔法、稀有装备获得。真实堆叠物品，用于校准、赋魔、升格、补缀、重铸与定向重铸；待安置碎片不能直接消费。",
		"maximum": Canonical.ShardCatalog.INVENTORY_LIMIT, "rules": metadata,
		"max_revision": Canonical.Rules.MAX_SERIAL, "save_version": Canonical.Rules.VERSION}}
	for operation: String in Craft.operation_ids():
		if not selected_operations.is_empty() and not selected_operations.has(operation): continue
		var instance: Dictionary = _crafting_example_instance(operation)
		instance.id = "gear_000001"
		if operation == "enchant": instance.rarity = "normal"; instance.affixes = []
		var model := Canonical.new()
		assert(model._admit_reward_item(Canonical.Items.wrap_equipment(instance)))
		var snapshot := model.snapshot()
		assert(model._set_bag_currency_balance(snapshot, 100).ok)
		model._accept_memory(snapshot)
		var context := model._craft_context(instance.id, "user://reference-only-not-written.json")
		var quote: Dictionary = CraftPlanner.quote(context, operation, instance.id)
		var planned: Dictionary = CraftPlanner.plan(context, quote, 20261003)
		assert(quote.ok and planned.ok)
		var candidate: Dictionary = snapshot.duplicate(true)
		var released := {}
		if operation == "salvage":
			released = candidate.locations[instance.id].duplicate(true)
			candidate.items.erase(instance.id); candidate.locations.erase(instance.id)
		else: candidate.items[instance.id] = Canonical.Items.wrap_equipment(planned.candidate.equipment_instances[instance.id])
		candidate.crafting = {"revision": planned.candidate.revision}
		assert(model._set_bag_currency_balance(candidate, planned.candidate.materials[Craft.MATERIAL_ID], released).ok)
		candidate.revision += 1
		assert(Canonical.Rules.reason(candidate).is_empty(), "Craft reference must validate the full current canonical build")
		var presentation := Craft.operation_metadata(operation)
		var name: String = presentation.label
		if presentation.get("targeted", false): name += " · " + presentation.target_label
		result[operation] = {"name": name, "kind": "operation",
			"description": presentation.description, "risk": presentation.risk,
			"rule": metadata.operations[operation], "rules_version": quote.rules_version, "eligible_base_ids": metadata.base_ids,
			"example": {"source": instance.duplicate(true), "before_definition": Equipment.definition(instance),
				"quote": quote, "balance_before": 100, "balance_after": planned.candidate.materials[Craft.MATERIAL_ID],
				"revision_before": 0, "revision_after": planned.candidate.revision,
				"after_instance": planned.candidate.equipment_instances.get(instance.id, {}),
				"after_definition": Equipment.definition(planned.candidate.equipment_instances.get(instance.id, {})),
				"full_candidate_valid": true, "save_version": candidate.version, "example_seed": 20261003}}
		if presentation.get("targeted", false):
			result[operation].merge(_targeted_crafting_constraints(operation), true)
	return result


## The four resistance targets need a legal resistance-bearing base. Keep all
## historical operation witnesses exact rather than rerolling their examples.
static func _crafting_example_instance(operation: String) -> Dictionary:
	if operation == "targeted_reforge_armour":
		return _crafting_probe_instance("emberhide_vest", 16, "magic")
	if operation in ["targeted_reforge_fire_resistance", "targeted_reforge_cold_resistance",
		"targeted_reforge_lightning_resistance", "targeted_reforge_chaos_resistance"]:
		return _crafting_probe_instance("nine_slot_etched_ring", 16, "magic")
	var instance: Dictionary = _local_instance(["whetstone_edge"], "magic")
	if Craft.Targeted.operation_ids().has(operation) and operation != "targeted_reforge_damage":
		instance = _local_instance(["global_critical_chance"], "magic", "wayglass_token")
	return instance


## Eligibility is proven by production quotes for legal catalog instances,
## including rare completion limits, rather than copied from the base inventory.
static func _targeted_crafting_constraints(operation: String) -> Dictionary:
	var target: Dictionary = Craft.Targeted.TARGETS[operation]
	var eligible_base_ids: Array[String] = []
	var eligibility: Array[Dictionary] = []
	for base_id: String in Equipment.all_base_ids():
		var entry: Dictionary = {"base_id": base_id, "minimum_item_level_by_rarity": {},
			"target_family_ids": [], "target_tiers_at_maximum_level": []}
		var pool: Array[Dictionary] = Craft.Expansion._pool(base_id, Equipment.MAX_ITEM_LEVEL, [])
		for tier: Dictionary in pool:
			if not target.families.has(tier.id): continue
			entry.target_tiers_at_maximum_level.append(tier.duplicate(true))
			if not entry.target_family_ids.has(tier.id): entry.target_family_ids.append(tier.id)
		for rarity: String in Craft.Targeted.COSTS:
			var maximum_source: Dictionary = _crafting_probe_instance(base_id, Equipment.MAX_ITEM_LEVEL, rarity)
			if maximum_source.is_empty() or not Craft.operation_quote(maximum_source, operation).ok: continue
			for level: int in range(Equipment.MIN_ITEM_LEVEL, Equipment.MAX_ITEM_LEVEL + 1):
				var source: Dictionary = _crafting_probe_instance(base_id, level, rarity)
				if not source.is_empty() and Craft.operation_quote(source, operation).ok:
					entry.minimum_item_level_by_rarity[rarity] = level
					break
		if not entry.minimum_item_level_by_rarity.is_empty():
			eligible_base_ids.append(base_id)
			eligibility.append(entry)
	var costs: Dictionary = {}
	for rarity: String in Craft.Targeted.COSTS:
		var source: Dictionary = _crafting_probe_instance(eligible_base_ids[0], Equipment.MAX_ITEM_LEVEL, rarity)
		var quote: Dictionary = Craft.operation_quote(source, operation)
		assert(quote.ok)
		costs[rarity] = int(quote.cost[Craft.MATERIAL_ID])
	return {"targeted": true, "target_id": target.id, "target_label": target.label,
		"target_family_ids": target.families.duplicate(), "eligible_base_ids": eligible_base_ids,
		"eligibility": eligibility, "cost_by_rarity": costs,
		"catalog_vocabulary": Equipment.CURRENT_VOCABULARY,
		"eligibility_maximum_item_level": Equipment.MAX_ITEM_LEVEL,
		"eligibility_note": "仅下列底材存在可达合法结果；物品等级仍限制阶级，最终以当前装备报价为准。普通、固定、已穿戴装备不可用；无合法目标不收费。",
		"selection_note": "先按目录正权重抽取可完成的目标家族与阶级，再从合法池补足；保持稀有度，不保留原词缀，也不保证高阶或更强。"}


static func _crafting_probe_instance(base_id: String, level: int, rarity: String) -> Dictionary:
	var pool: Array[Dictionary] = Craft.Expansion._pool(base_id, level, [])
	if pool.is_empty(): return {}
	var first: Dictionary = pool[0]
	var instance: Dictionary = {"id": "gear_000001", "base_id": base_id, "rarity": "magic",
		"item_level": level, "affixes": [{"id": first.id, "tier": first.tier, "value": first.min}]}
	if not Equipment.validate_instance(instance): return {}
	if rarity == "rare":
		var expanded: Dictionary = Craft.Expansion.plan(instance, "elevate", 20261003)
		if not expanded.ok: return {}
		instance = expanded.instance
	assert(Equipment.validate_instance(instance))
	return instance

## Hand-authored legal examples derive every roll from the live family tiers.
## No random generator, save path, migration, or player-owned build is accessed.
static func _local_instance(affix_ids: Array = [], rarity: String = "normal", base_id: String = WeaponLocal.BASE_ID) -> Dictionary:
	var affixes: Array = []
	var level: int = Equipment.MIN_ITEM_LEVEL
	for id: String in affix_ids:
		var family: Dictionary = Equipment.affix_definition(id)
		var tier: Dictionary = family.tiers.back()
		level = maxi(level, int(tier.level))
		affixes.append({"id": id, "tier": tier.tier, "value": tier.max})
	return {"id": "gear_000001", "base_id": base_id, "rarity": rarity, "item_level": level, "affixes": affixes}

## Isolated item/profile examples use B18 and explicit 5% / 150% critical bases.
## They intentionally omit class attributes, passives and all other equipment;
## Canonical's starting class can add modifiers after the same raw packet.
static func forgeblade_examples() -> Dictionary:
	var pool: Dictionary = Equipment.pool_profiles().forgeblade_v34
	var families: Dictionary = {}
	for id: String in pool.affix_ids: families[id] = Equipment.affix_definition(id)
	var result: Dictionary = {"base_id":"forgeblade", "pool_id":"forgeblade_v34", "save_version":34,
		"icon_source":"res://assets/art/equipment/forgeblade.png", "icon_file":"originals/forgeblade.png",
		"base":Equipment.base_definition("forgeblade"), "pool":pool, "families":families,
		"current_loot_profile_id":Canonical.LOOT_PROFILE_ID, "current_loot_profile":Equipment.loot_profile(Canonical.LOOT_PROFILE_ID),
		"local_consumers":WeaponLocal.metadata().consumers_by_base.forgeblade,
		"example_scope":"真实合法装备实例→目录派生属性与武器profile→实际编译器；隔离B18、基础暴击5%/150%，无职业三属性、天赋、其他装备或辅助。不是默认角色伤害或实战DPS。",
		"formula":"W=(4+本武器附加物理)×(1+本武器物理提高)", "examples":{}, "crafting":{},
		"global_scope":"本地W仅短刃普通近战basic/direct与裂刃cleave/direct；全局暴击仍作用于攻击、法术及独立secondary，最大魔力与魔力恢复仍是角色全局资源。"}
	result["legal_family_sets"] = {}
	for rarity: String in Equipment.RARITIES:
		var accepted: Array = []
		for mask: int in range(1 << pool.affix_ids.size()):
			var candidate: Dictionary = {"id":"gear_000001","base_id":"forgeblade","rarity":rarity,"item_level":1,"affixes":[]}
			var ids: Array = []
			for index: int in range(pool.affix_ids.size()):
				if mask & (1 << index):
					var id: String = pool.affix_ids[index]
					ids.append(id)
					var tier: Dictionary = families[id].tiers[0]
					candidate.affixes.append({"id":id,"tier":1,"value":tier.min})
			if Equipment.validate_instance(candidate):accepted.append(ids)
		result.legal_family_sets[rarity] = accepted
	var configurations: Array = [
		["normal", "普通无词缀", [], "normal", 1, false],
		["dual_t1_min", "合法金装 · 双本地T1最低", ["whetstone_edge","tempered_edge","deepwell","wellturn"], "rare", 1, false],
		["dual_t1_max", "合法金装 · 双本地T1最高", ["whetstone_edge","tempered_edge","deepwell","wellturn"], "rare", 1, true],
		["six_t1_max", "合法六族T1最高", pool.affix_ids, "rare", 1, true],
		["six_t3_max", "合法六族T3最高", pool.affix_ids, "rare", 3, true]]
	for config: Array in configurations:
		var instance: Dictionary = _forgeblade_instance(config[2],config[3],config[4],config[5])
		var definition: Dictionary = Equipment.definition(instance)
		assert(Equipment.validate_instance(instance) and not definition.is_empty())
		var stats: Dictionary = {"damage":18.0,"crit_base_chance":0.05,"crit_base_multiplier":1.5}
		stats.merge(definition.stats)
		var snapshot: Dictionary = Recipes.snapshot(stats,["explode_on_flight_end"])
		snapshot.weapon_profile = definition.weapon_profile.duplicate(true)
		var no_local: Dictionary = snapshot.duplicate(true)
		no_local.erase("weapon_profile")
		var casts: Dictionary = {}
		var ids: Array = Data.SKILLS.keys()
		ids.append("basic")
		for skill: String in ids:
			var cast: Dictionary = Compiler.compile_basic(snapshot) if skill == "basic" else Compiler.compile_skill(skill,snapshot,[])
			var before: Dictionary = Compiler.compile_basic(no_local) if skill == "basic" else Compiler.compile_skill(skill,no_local,[])
			assert(cast.ok and before.ok)
			var hits: Dictionary = {}
			var packets: Dictionary = _forgeblade_packets(cast.packets)
			var baseline_packets: Dictionary = _forgeblade_packets(before.packets)
			if skill == "basic":
				# Keep the actual melee event recipe while isolating just W.
				# Removing the profile before dispatch would select an old projectile.
				baseline_packets = {"direct": Recipes.BaseCompiler.assemble(no_local.base_damage,
					Recipes._event_recipe(snapshot, "basic", "direct", 0), no_local.added_damage,
					no_local.get("added_damage_sources", []))}
			for role: String in packets:
				var packet: Dictionary = packets[role]
				var resolved: Dictionary = Damage.resolve(packet,cast.snapshot.modifiers)
				var local: Dictionary = packet.get("assembly",{}).get("weapon",{})
				var contribution: float = float(local.get("contribution",{}).get("physical",0.0))
				if skill not in ["basic", "cleave"] or role != "direct":
					assert(is_zero_approx(contribution) and packet == baseline_packets[role])
				var critical: Dictionary = cast.get("critical",{}).get("secondary" if role == "secondary" else "primary",{})
				var expected: float = float(resolved.total) * (1.0+float(critical.get("chance",0.0))*(float(critical.get("multiplier",1.0))-1.0))
				hits[role] = {"packet":packet,"resolved":resolved,"local_contribution":contribution,
					"no_local_packet":baseline_packets[role],"critical":critical,"expected_zero_defense":expected}
			casts[skill] = {"hits":hits,"critical":cast.get("critical",{}),"mana":cast.get("mana",0.0),"cooldown":cast.get("cooldown",0.0)}
		result.examples[config[0]] = {"name":config[1],"instance":instance,"definition":definition,
			"stats":stats,"snapshot":snapshot,"weapon":WeaponLocal.resolve(snapshot.weapon_profile),"casts":casts}
	var magic: Dictionary = _forgeblade_instance(["whetstone_edge"],"magic",1,true)
	var rare: Dictionary = result.examples.six_t3_max.instance
	for operation: String in Craft.operation_ids():
		var instance: Dictionary = result.examples.normal.instance if operation == "enchant" else magic
		var quote: Dictionary = Craft.operation_quote(instance,operation)
		var row: Dictionary = {"presentation":Craft.operation_metadata(operation),"instance":instance,"quote":quote}
		if Craft.Targeted.operation_ids().has(operation):
			row["rare_quote"] = Craft.operation_quote(rare,operation)
			row["eligible_families"] = []
			for id: String in pool.affix_ids:
				if Craft.Targeted.TARGETS[operation].families.has(id):row.eligible_families.append(id)
			if quote.ok:
				var planned: Dictionary = Craft.Targeted.plan(instance,operation,550055)
				assert(planned.ok and Equipment.validate_instance(planned.instance))
				row["planned_instance"] = planned.instance
			else:
				assert(quote.code == "no_legal_target")
		result.crafting[operation] = row
	var old: Dictionary = Canonical.new().snapshot()
	old.version = 33
	var migrated: Dictionary = ForgebladeMigrationData.migrate_v33(old,SourceTree.reason)
	assert(not migrated.is_empty())
	var changed: Array = []
	for key: String in old:
		if old[key] != migrated[key]:changed.append(key)
	assert(changed == ["version"])
	result["migration"] = {"from_version":old.version,"to_version":migrated.version,"changed_fields":changed,
		"items_preserved":old.items == migrated.items,"talents_preserved":old.talents == migrated.talents,
		"fresh_has_forgeblade":false,"old_vocabulary_rejects_forgeblade":not Equipment.validate_instance_for_version(result.examples.normal.instance,33),
		"backup_contract":"完整冻结schema33校验后原字节备份，再仅升级version；失败不改原文件，不赠装备、碎片或点数。",
		"evidence_scope":"本卡纯迁移函数示例不读写存档；原字节备份与失败事务由forgeblade_migration_test独立验证。"}
	for wrapped: Dictionary in old.items.values():
		assert(wrapped.definition_id != "equipment:forgeblade")
	return result


## The same real compiler records both the authored event and class modifiers.
## Canonical candidates use the production transfer planner and validation in
## memory; the offline exporter never calls equip/save or a user save path.
static func melee_basic_examples(blade: Dictionary) -> Dictionary:
	var result: Dictionary = {"base_id":"forgeblade", "save_version":Canonical.Rules.VERSION,
		"recipe":Recipes.BASIC_MELEE.duplicate(true), "examples":{}, "equipped_examples":{},
		"legacy_inflight":{}, "timing":"沿用attack_timer与当前attack_speed；没有独立技能冷却或魔力支付。",
		"admission":"自动攻击只在近战距离内选取敌人，圈外不空挥；手动允许空挥并消耗原攻击间隔。",
		"scope":"hit + attack + melee；不含area，不受范围或投射物速度提高，也不占投射物容量，无返回或飞行结束爆炸。",
		"balance":"贴身普攻与裂刃组合输出提高是v0.56新行为，不是旧同seed战斗结果等价；以下是逐次成功命中，不是实战DPS。"}
	for key: String in blade.examples:
		var example: Dictionary = blade.examples[key]
		var cast: Dictionary = Compiler.compile_basic(example.snapshot)
		assert(cast.ok and cast.packets.keys() == ["direct"] and cast.recipe == Recipes.BASIC_MELEE)
		result.examples[key] = _melee_reference_cast(cast)
	var cleave: Dictionary = Compiler.compile_skill("cleave", blade.examples.normal.snapshot, [])
	result["cleave"] = _melee_reference_cast(cleave)
	for key: String in ["normal", "six_t3_max"]:
		var model: RefCounted = Canonical.new()
		for uid: String in model.equipped_items().values():
			_reference_move(model, uid, model.first_bag_position(uid))
		var instance: Dictionary = blade.examples[key].instance.duplicate(true)
		instance.id = "gear_%06d" % int(model.snapshot().next_item_serial)
		assert(Equipment.validate_instance(instance))
		assert(model._admit_reward_item(Canonical.Items.wrap_equipment(instance)))
		_reference_move(model, instance.id, {"kind":"equipment", "slot_id":"weapon"})
		assert(model.equipped_items() == {"weapon":instance.id})
		var cast: Dictionary = model.get_basic_cast()
		assert(cast.ok and cast.recipe == Recipes.BASIC_MELEE)
		result.equipped_examples[key] = {"instance":model.item(instance.id), "location":model.location(instance.id),
			"equipped":model.equipped_items(), "stats":model.get_stats(), "talents":model.snapshot().talents,
			"snapshot":model.get_combat_snapshot(), "basic":_melee_reference_cast(cast),
			"cleave":_melee_reference_cast(Compiler.compile_skill("cleave", model.get_combat_snapshot(), [])),
			"save_attempts":model.save_attempts}
		assert(model.save_attempts == 0)
	var frozen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v056-reference/v055-basic-snapshots.json"))
	for key: String in frozen:
		var snapshot: Dictionary = frozen[key].snapshot
		var packet: Dictionary = Recipes.event_packet(snapshot, "basic", "projectile")
		var secondary: Dictionary = Recipes.secondary_packet(snapshot, "basic")
		assert(packet == snapshot.compiled_packets.projectile and secondary == snapshot.compiled_packets.secondary)
		assert(Recipes.event_packet(snapshot, "basic", "direct").is_empty())
		result.legacy_inflight[key] = {"source_commit":frozen[key].source_commit, "source_path":frozen[key].source_path,
			"projectile":packet, "secondary":secondary, "resolved":Damage.resolve(packet, snapshot.modifiers),
			"retains_frozen_packets":true}
	return result


static func _melee_reference_cast(cast: Dictionary) -> Dictionary:
	assert(cast.ok)
	var packet: Dictionary = cast.packets.direct
	return {"recipe":cast.recipe.duplicate(true), "full_angle_degrees":rad_to_deg(float(cast.recipe.half_angle) * 2.0),
		"packets":cast.packets.duplicate(true), "resolved":Damage.resolve(packet, cast.snapshot.modifiers),
		"critical":cast.get("critical", {}).duplicate(true), "mana":cast.get("mana", 0.0),
		"cooldown":cast.get("cooldown", 0.0), "has_mana_field":cast.has("mana"),
		"has_cooldown_field":cast.has("cooldown"), "summary":Preview.summary(cast), "details":Preview.details(cast)}


static func _reference_move(model: RefCounted, uid: String, destination: Dictionary) -> void:
	var candidate: Dictionary = model.snapshot()
	var planned: Dictionary = Canonical.Transfer.move_paged(Canonical.Items.metadata_for_items(candidate.items),
		candidate.locations, Canonical.Migration.paged_location_context(candidate, model._socket_ids), uid,
		destination, candidate.revision, candidate.revision)
	assert(planned.ok)
	candidate.locations = planned.locations
	candidate.revision = planned.revision
	assert(Canonical.Rules.reason(candidate, model._talent_validator, model._socket_ids).is_empty())
	model._accept_memory(candidate)


static func _forgeblade_packets(packets: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for role: String in packets:
		if role == "bounces":
			for index: int in range(packets[role].size()):result["bounce_"+str(index)] = packets[role][index]
		else:result[role] = packets[role]
	return result


static func _forgeblade_instance(ids: Array, rarity: String, tier_number: int, maximum: bool) -> Dictionary:
	var instance: Dictionary = {"id":"gear_000001","base_id":"forgeblade","rarity":rarity,"item_level":1,"affixes":[]}
	for id: String in ids:
		var tier: Dictionary = Equipment.affix_definition(id).tiers[tier_number-1]
		instance.item_level = maxi(instance.item_level,int(tier.level))
		instance.affixes.append({"id":id,"tier":tier_number,"value":tier.max if maximum else tier.min})
	assert(Equipment.validate_instance(instance))
	return instance


static func local_build(instance: Dictionary) -> RefCounted:
	assert(Equipment.validate_instance(instance), "Reference equipment must be a legal real instance")
	var build: RefCounted = Build.new()
	build.equipment_instances = {instance.id: instance.duplicate(true)}
	build.inventory.append(instance.id)
	build.next_equipment_id = Equipment.serial_from_id(instance.id) + 1
	build._sync_backpack()
	var equipped_ok: bool = build.equip(instance.id)
	assert(equipped_ok, "Reference equipment must equip through BuildState")
	assert(not build._validate_snapshot(build._snapshot()).is_empty(), "Reference build must satisfy actual save schema without writing a save")
	return build


static func flask_examples()->Dictionary:
	var examples:Dictionary={}
	var state:=Canonical.new()
	for id:String in Flasks.DEFINITIONS:
		var definition:Dictionary=Flasks.definition(id)
		var maximum:float=state.get_stats().max_health if definition.resource=="health" else state.get_stats().max_mana
		var runtime:=FlaskRuntime.new();var uid:="reference_flask"
		assert(runtime.reset({uid:id}))
		var current:Dictionary={"health":10.0,"mana":10.0};var maxima:Dictionary={"health":float(state.get_stats().max_health),"mana":float(state.get_stats().max_mana)}
		var used:Dictionary=runtime.use(uid,float(current[definition.resource]),maximum)
		assert(used.ok)
		var rows:Array=[{"time":0.0,"resource":10.0,"charges":used.charges}]
		for index:int in range(6):
			var gain:Dictionary=runtime.advance(0.5,current,maxima)
			current.health+=float(gain.health);current.mana+=float(gain.mana)
			rows.append({"time":float(index+1)*0.5,"resource":current[definition.resource],"charges":runtime.snapshot().charges_by_uid[uid]})
		var before_charge:int=runtime.snapshot().charges_by_uid[uid]
		runtime.charge_rewarded_kill([uid])
		definition["id"]=id.substr("flask:".length())
		definition["status"]="implemented";definition["origin"]="original"
		definition["save_version"]=Flasks.SAVE_VERSION
		definition["example"]={"maximum_at_use":maximum,"resource_before":10.0,"rows":rows,"restored":float(current[definition.resource])-10.0,"before_kill_charges":before_charge,"after_valid_root_charges":runtime.snapshot().charges_by_uid[uid],"passive_regeneration_included":false}
		definition["acquisition"]={"starter_each":1,"eligible_root_interval":Flasks.REWARD_INTERVAL,"sequence":[Flasks.reward_definition(Flasks.REWARD_INTERVAL),Flasks.reward_definition(Flasks.REWARD_INTERVAL*2)],"extra_rng":false}
		definition["rules"]={"slots":Flasks.Locations.FLASK_SLOTS.duplicate(),"runtime_persisted":false,"reset":"actual_new_battle","move_refills":false,"same_resource_stacks":false,"early_end":"resource_full","shield_restore":false,"ailment_removal":false}
		examples[definition.id]=definition
	return examples


static func telegraph_examples() -> Dictionary:
	var enemy: Dictionary = Monsters.make_enemy(1, "ember_guard", int(Monsters.FIRE_ENCOUNTER.minimum_wave), Vector2(100, 0), "demo")
	enemy.spawn = 0.0
	var policy: Dictionary = Monsters.telegraph_policy(enemy)
	var runtime := Telegraphs.new()
	var admitted: Dictionary = runtime.start(enemy, Vector2.ZERO, policy.profile)
	assert(admitted.ok)
	var warning: float = float(policy.profile.windup_seconds)
	assert(runtime.advance(warning * 0.5, [enemy]).is_empty())
	var halfway: Dictionary = runtime.state_for(1)
	var events: Array[Dictionary] = runtime.advance(warning * 0.5, [enemy])
	assert(events.size() == 1)
	var event: Dictionary = events[0]
	var armor: Dictionary = {"id": "gear_000001", "base_id": "emberhide_vest", "rarity": "normal", "item_level": 5, "affixes": []}
	var protected_build: RefCounted = local_build(armor)
	var fresh: RefCounted = Build.new()
	var dodged: Vector2 = Vector2(float(fresh.get_stats().move_speed) * warning, 0)
	var cases: Dictionary = {}
	for id: String in ["standing", "armored", "moving"]:
		var player: Vector2 = dodged if id == "moving" else Vector2.ZERO
		var build_stats: Dictionary = protected_build.get_stats() if id == "armored" else fresh.get_stats()
		var stats: Dictionary = {"fire_resistance": build_stats.get("fire_resistance", 0.0)}
		var inside: bool = Telegraphs.overlaps(event, player, Arena.PLAYER_RADIUS)
		cases[id] = {"position": player, "inside": inside, "defense_stats": stats,
			"settlement": Defense.incoming_hit(event.packet.base, stats, 10.0, 100.0, "player") if inside else {}}
		assert(not inside or cases[id].settlement.ok, "Reference heavy hit must use a supported defense profile")
	var metadata: Dictionary = TelegraphProfiles.metadata(policy.profile)
	metadata["integrated_templates"] = ["ember_guard"]
	metadata["policy"] = policy
	metadata["description"] = "灰烬守卫以固定范围重击代替接触攻击。先锁定地面位置；火分量一半立即结算，另一半分3秒燃烧，原总预算不增加，移出范围可完全躲避。"
	metadata["example"] = {"source": enemy, "source_wave": enemy.wave, "start": admitted.attack,
		"halfway": halfway, "event": event, "recovery": runtime.state_for(1), "cases": cases,
		"player_radius": Arena.PLAYER_RADIUS, "move_speed": fresh.get_stats().move_speed,
		"shield_before": 10.0, "health_before": 100.0, "armor_instance": armor,
		"armor_definition": Equipment.definition(armor), "movement_assumption": "straight_unobstructed_motion_from_warning_start"}
	var result: Dictionary = {TelegraphProfiles.PROFILE_ID: metadata}
	for template_id: String in Monsters.ELEMENTAL_ENCOUNTERS:
		var elemental: Dictionary = elemental_telegraph_example(template_id)
		result[elemental.id] = elemental
	return result


static func elemental_telegraph_example(template_id: String) -> Dictionary:
	var rule: Dictionary = Monsters.ELEMENTAL_ENCOUNTERS[template_id]
	var element: String = rule.element
	var source: Dictionary = Monsters.make_enemy(1,template_id,int(rule.minimum_wave),Vector2(100,0),"demo")
	source.spawn = 0.0
	var policy: Dictionary = Monsters.telegraph_policy(source)
	var runtime := Telegraphs.new()
	var admission: Dictionary = runtime.start(source,Vector2.ZERO,policy.profile)
	assert(admission.ok)
	assert(runtime.advance(float(policy.profile.windup_seconds)*0.5,[source]).is_empty())
	var halfway: Dictionary = runtime.state_for(1)
	var events: Array[Dictionary] = runtime.advance(float(policy.profile.windup_seconds)*0.5,[source])
	assert(events.size()==1)
	var event: Dictionary = events[0]
	var fresh := Canonical.new()
	var guarded := Canonical.new()
	var path: Array[String] = ["58833","48828","33508","36881"]
	if element=="lightning": path.append("35503")
	var candidate: Dictionary = guarded.snapshot()
	candidate.talents.allocated = path.duplicate()
	candidate.talents.normal_points -= path.size()-1
	assert(Canonical.Rules.reason(candidate).is_empty(),"Reference resistance example must be a legal fresh-level tree build")
	guarded._accept_memory(candidate)
	var cases: Dictionary = {}
	var distance: float = float(fresh.get_stats().move_speed)*float(policy.profile.windup_seconds)
	for case_id: String in ["standing","armored","moving"]:
		var position: Vector2 = Vector2(distance,0) if case_id=="moving" else Vector2.ZERO
		var stats: Dictionary = guarded.get_stats() if case_id=="armored" else fresh.get_stats()
		var inside: bool = Telegraphs.overlaps(event,position,Arena.PLAYER_RADIUS)
		cases[case_id] = {"position":position,"inside":inside,"defense_stats":stats,
			"settlement":Defense.incoming_source_hit(event.packet.base,stats,5.0,100.0,"player") if inside else {}}
		assert(not inside or cases[case_id].settlement.ok)
	var metadata: Dictionary = TelegraphProfiles.metadata(policy.profile)
	metadata.id = "locked_circle_"+element
	metadata.name = source.name+" · 冰冷预警" if element=="cold" else source.name+" · 闪电预警"
	metadata["element"] = element
	metadata["integrated_templates"] = [template_id]
	metadata["policy"] = policy
	metadata["natural_selection"] = rule.duplicate(true)
	metadata["description"] = "仅替换原抽签的同物种名额，保留白蓝金与共享词缀、基础属性和奖励。锁定地面，完整预警后一次元素攻击；走开或攻击闪避可避开，不施加冻结或感电。"
	if policy.has("shock_policy"):
		metadata["description"] = "仅替换原抽签的同物种名额，保留白蓝金与共享词缀、基础属性和奖励。锁定地面，完整预警后一次闪电攻击；走开或攻击闪避可避开。实际正值闪电损伤结算后施加1秒感电，后续命中受伤提高15%；本次施加不自增伤，持续伤害不受影响。"
	metadata["protection_label"] = "实际源树路径 · %d%%对应抗性" % int(round(float(guarded.get_stats()[element+"_resistance"])*100.0))
	metadata["example"] = {"source":source,"source_wave":source.wave,"start":admission.attack,"halfway":halfway,
		"event":event,"recovery":runtime.state_for(1),"cases":cases,"player_radius":Arena.PLAYER_RADIUS,
		"move_speed":fresh.get_stats().move_speed,"shield_before":5.0,"health_before":100.0,"allocated_path":path,
		"movement_assumption":"straight_unobstructed_motion_from_warning_start","attack_admission_note":"Displayed values are conditioned on attack admission; existing evasion may prevent the hit."}
	return metadata


static func encounter_examples() -> Dictionary:
	var result: Dictionary = {}
	for id: String in EncounterCatalog.get_ids():
		var definition: Dictionary = EncounterCatalog.get_definition(id)
		var compiled: Dictionary = EncounterCompiler.compile([id])
		assert(compiled.ok)
		definition["profile"] = compiled.profile.duplicate(true)
		definition["status"] = "implemented"
		definition["examples"] = {}
		for template: String in ["crawler","ember_guard","brood_host"]:
			var before: Dictionary = Monsters.make_enemy(1,template,3,Vector2.ZERO,"demo")
			# This shared actor default is also installed by main; expose it for
			# the new armour comparison without inventing a UI-only base value.
			before.armour=AttackRules.monster_profile(int(before.kind)).armour
			var applied: Dictionary = EncounterCompiler.apply_to_enemy(before,compiled.profile)
			assert(applied.ok)
			definition.examples[template] = {"before":before,"after":applied.enemy,
				"before_telegraph":Monsters.telegraph_policy(before),"after_telegraph":Monsters.telegraph_policy(applied.enemy)}
		result[id] = definition
	return result

## Enumerate each zero-, one-, and two-slot candidate exactly once. Available
## support count can grow independently of the two-slot equipment limit.
static func support_combinations(compatible_ids: Array) -> Array:
	assert(Supports.MAX_SUPPORTS == 2, "Reference enumeration follows the two-slot contract")
	var result: Array = [[]]
	for id: String in compatible_ids:
		result.append([id])
	for first: int in range(compatible_ids.size()):
		for second: int in range(first + 1, compatible_ids.size()):
			result.append([compatible_ids[first], compatible_ids[second]])
	return result


## One carrier, six stationary targets, no defense or return item. Counts come
## from actual collision events, not a parallel browser implementation.
static func piercing_examples() -> Dictionary:
	var result: Dictionary = {"fixture": "one_carrier_six_stationary_targets", "target_count": 6,
		"source": "SkillCompiler + ProjectileRuntime.advance + DamageResolver", "skills": {}}
	var build = Build.new()
	for skill_id: String in ["bolt", "frost"]:
		var row: Dictionary = {}
		for mode: String in ["before", "after"]:
			var links: Array = [] if mode == "before" else ["pierce"]
			var cast: Dictionary = Compiler.compile_skill(skill_id, build.get_combat_snapshot(), links)
			assert(cast.ok, "Pierce reference fixture must compile")
			var runtime = Projectiles.new()
			var targets: Array[Dictionary] = []
			for index: int in range(6):
				targets.append({"id": index + 1, "pos": Vector2(80.0 * (index + 1), 0),
					"radius": 10.0, "health": 1000.0, "spawn": 0.0})
			var spec: Dictionary = {"speed": cast.recipe.speed, "range": 650.0, "lifetime": 1.7,
				"radius": 5.5, "pierce": cast.recipe.pierce, "slow": cast.recipe.slow}
			var shots: Array[Dictionary] = [runtime.make_projectile(Vector2.ZERO, Vector2.RIGHT,
				spec, cast.packets.projectile, cast.snapshot, runtime.new_cast(), Color.WHITE)]
			var hit_ids: Array[int] = []
			for event: Dictionary in runtime.advance(shots, 1.6, targets, Vector2.ZERO, 180):
				if event.type == "hit":
					hit_ids.append(int(event.target_id))
			row[mode] = {"supports": cast.support_ids, "pierce": cast.recipe.pierce,
				"observed_hits": hit_ids, "mana": cast.mana,
				"hit_damage": Damage.resolve(cast.packets.projectile, cast.snapshot.modifiers).total}
		result.skills[skill_id] = row
	return result


static func _direct_total(cast: Dictionary) -> float:
	var total: float = 0.0
	for entry: Dictionary in Preview.entries(cast):
		if entry.label != "独立爆炸":
			total += float(Damage.resolve(entry.packet, cast.snapshot.modifiers).total)
	return total

static func _path_to(target: String, graph: Dictionary) -> Array:
	var queue: Array = [Passives.START_ID]
	var previous: Dictionary = {Passives.START_ID: ""}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == target:
			break
		for neighbor: String in graph[current].neighbors:
			if not previous.has(neighbor):
				previous[neighbor] = current
				queue.append(neighbor)
	var path: Array = []
	var cursor: String = target
	while not cursor.is_empty():
		path.push_front(cursor)
		cursor = previous[cursor]
	return path

static func _affix_source() -> Dictionary:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/reference/poe_affixes/source_manifest.json"))
	return {"source_version": source.source_version, "source_kind": source.source_kind,
		"export_repository": source.export_repository, "export_commit": source.export_commit,
		"parser_reference_commit": source.parser_reference_commit, "status": "research_only"}

static func clean(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[str(key)] = clean(value[key])
		return result
	if value is Array or value is PackedStringArray:
		var result: Array = []
		for item: Variant in value:
			result.append(clean(item))
		return result
	if value is Vector2 or value is Vector2i:
		return [value.x, value.y]
	if value is Color:
		return "#" + value.to_html(false)
	if value is Resource:
		return value.resource_path
	return value

## Values use the same compiler, circle test and hit resolver as the actual scene.
## These are fixed layouts, not a claim of target density or total DPS.
static func area_examples() -> Dictionary:
	var build := Build.new()
	var enemy: Dictionary = Monsters.make_enemy(1, "crawler", 1, Vector2.ZERO, "demo")
	var result: Dictionary = {"source": "SkillCompiler + AreaSupportRules.contains_target + DamageResolver",
		"mechanism_reference": {"title": "GGG 2.6.0 Area of Effect Changes", "date": "2017-02-26",
			"url": "https://www.pathofexile.com/forum/view-thread/1838713/filter-account-type/staff",
			"scope": "Historical area/radius distinction only; all support values are original game balance."},
		"target_radius": enemy.radius, "skills": {}}
	for skill_id: String in ["nova", "meteor"]:
		var row: Dictionary = {}
		var base_radius: float = Data.SKILLS[skill_id].area_recipe.radius
		for mode: String in ["base", "wide", "concentrated", "combined"]:
			var links: Array = {"base": [], "wide": ["breadth"], "concentrated": ["concentrate"], "combined": ["breadth", "concentrate"]}[mode]
			var cast: Dictionary = Compiler.compile_skill(skill_id, build.get_combat_snapshot(), links)
			assert(cast.ok)
			var damage: Dictionary = Damage.resolve(cast.packets.direct, cast.snapshot.modifiers)
			var layouts: Dictionary = {}
			for layout: String in ["single", "cluster", "near_original_edge", "outer_band"]:
				var points: Array[Vector2] = [Vector2.ZERO]
				if layout != "single":
					for i: int in range(1, 5):
						var distance: float = base_radius * 0.55 if layout == "cluster" else base_radius * 0.95 + float(enemy.radius) if layout == "near_original_edge" else base_radius * 1.15 + 12.0
						points.append(Vector2.RIGHT.rotated(i * TAU / 4.0) * distance)
				var hits: Array[int] = []
				for i: int in points.size():
					if AreaRules.contains_target(Vector2.ZERO, points[i], cast.recipe.radius, enemy.radius): hits.append(i)
				layouts[layout] = {"points": points, "hit_indices": hits, "total_before_defense": damage.total * hits.size()}
			row[mode] = {"radius": cast.recipe.radius, "area_multiplier": cast.recipe.get("area_multiplier", 1.0),
				"mana": cast.mana, "cooldown": cast.cooldown, "hit_damage": damage.total, "layouts": layouts}
		result.skills[skill_id] = row
	return result


static func support_program_examples() -> Dictionary:
	var build := Build.new()
	var snapshot: Dictionary = build.get_combat_snapshot()
	var result: Dictionary = {}
	for id: String in Supports.SUPPORTS:
		var definition: Dictionary = Supports.get_definition(id)
		var family: String = str(definition.get("family", "area" if definition.requires.has("area_hit") else "projectile"))
		var examples: Dictionary = {}
		for skill_id: String in Data.SKILLS:
			if not Supports.compatibility_reason(skill_id, [id]).is_empty(): continue
			var before: Dictionary = Compiler.compile_skill(skill_id, snapshot, [])
			var after: Dictionary = Compiler.compile_skill(skill_id, snapshot, [id])
			assert(before.ok and after.ok)
			examples[skill_id] = {"before": support_cast_brief(before), "after": support_cast_brief(after)}
		result[id] = {"family": family, "native_recipe_eligibility": true, "examples": examples}
	return result

static func support_cast_brief(cast: Dictionary) -> Dictionary:
	var result: Dictionary = {"mana": cast.mana, "cooldown": cast.cooldown, "initial_count": cast.initial_count,
		"recipe": cast.recipe.duplicate(true), "summary": Preview.summary(cast), "details": Preview.details(cast)}
	if cast.has("trap_profile"): result["trap_profile"] = cast.trap_profile.duplicate(true)
	if cast.has("area_impulse_profile"): result["area_impulse_profile"] = cast.area_impulse_profile.duplicate(true)
	return result


static func inward_pull_examples() -> Dictionary:
	var model := Canonical.new()
	var snapshot: Dictionary = model.get_combat_snapshot()
	var examples: Dictionary = {}
	var selections: Dictionary = {
		"nova": {"base": [], "ambush_shock": ["ambush", "shock"]},
		"meteor": {"base": [], "ambush_ember_area": ["ambush", "ember_proliferation", "breadth", "concentrate"]},
		"cleave": {"base": [], "ring_area": ["encircling_cleave", "breadth", "physical_focus", "efficiency"]},
		"frost": {"base": [], "pierce_lingering": ["pierce", "heavy_projectiles", "lingering_chill", "efficiency"]},
		"shade_bolt": {"base": [], "pierce_focus": ["pierce", "heavy_projectiles", "focus", "efficiency"]},
	}
	for skill_id: String in selections:
		var rows: Dictionary = {}
		for mode: String in selections[skill_id]:
			var other_supports: Array = selections[skill_id][mode].duplicate()
			var linked: Array = other_supports.duplicate()
			linked.append("inward_pull")
			var before: Dictionary = Compiler.compile_group(skill_id, snapshot, other_supports)
			var after: Dictionary = Compiler.compile_group(skill_id, snapshot, linked)
			assert(before.ok and after.ok and after.has("area_impulse_profile"))
			assert(Compiler.InwardPull.policy_error(after.area_impulse_profile).is_empty())
			assert(after.area_impulse_profile == after.snapshot.area_impulse_policy)
			assert(not before.has("area_impulse_profile") and not before.snapshot.has("area_impulse_policy"))
			assert(before.recipe == after.recipe and before.cooldown == after.cooldown and before.packets == after.packets)
			for field: String in ["trap_profile", "burn_profile", "shock_profile", "critical"]:
				assert(before.get(field, {}) == after.get(field, {}))
			var role: String = "projectile" if skill_id in ["frost", "shade_bolt"] else "direct"
			assert(Damage.resolve(before.packets[role], before.snapshot.modifiers) == Damage.resolve(after.packets[role], after.snapshot.modifiers))
			rows[mode] = {"before": _inward_pull_cast_brief(before), "after": _inward_pull_cast_brief(after)}
		examples[skill_id] = rows
	var quote: Dictionary = Canonical.GemTrade.quote("buy", "support:inward_pull")
	var test_offer: Dictionary = Town.offer("support:inward_pull")
	assert(quote.ok and test_offer.available)
	return {"minimum_save_version": Compiler.InwardPull.SAVE_VERSION, "source_policy": SourceTree.CURRENT_SAVE_VERSION,
		"equipment_vocabulary": Equipment.CURRENT_VOCABULARY, "support_id": "inward_pull",
		"skills": Compiler.InwardPull.SKILLS, "policy": examples.nova.base.after.area_impulse_profile,
		"icon_source": GemCatalogData.definition("support:inward_pull").icon, "icon_file": "originals/inward_pull.png",
		"example_stats": model.get_stats(), "examples": examples, "merchant_quote": quote, "test_offer": test_offer,
		"normal_reward_pool_includes_support": Canonical.Journey.GEM_DEFINITIONS.has("support:inward_pull"),
		"normal_reward_definition_count": Canonical.Journey.GEM_DEFINITIONS.size(),
		"example_scope": "同一新建角色的真实战斗快照，仅在对应辅助组合加入牵引并调用生产Compiler.compile_group；显示非暴击、防御前单次命中与冻结配置，不是DPS或实际战斗位移",
		"direction": "新星与陨星将原向外冲量反转为朝本次技能中心；新星使用施放圆心、陨星使用实际落点、伏击使用已放置符印位置；裂刃只在原攻击成功命中结算后，朝施放时角色位置施加同速冲量，闪避、出生保护与遮挡均不牵引；冰霜脉冲与蚀影飞弹主投射命中后拉向本次发射时角色位置，不追随后来移动的角色或投射物位置；目标与原点重合时冲量为零",
		"movement": "圆形法术替换原190冲量方向，裂刃成功命中新增190牵引，冰霜与蚀影主投射命中的原45向外冲量替换为190向内冲量；沿用原520/秒衰减、怪物移动、分离和墙体碰撞；没有持续吸附、瞬移、自动追踪或强制汇聚，不保证拉到圆心",
		"snapshot": "compiled.area_impulse_profile与snapshot.area_impulse_policy保存独立副本；裂刃使用本次冻结策略与施放原点，拆卸不撤销已施加的冲量；冰霜与蚀影每枚投射物保留本次角色脚下原点，命中事件沿用该原点与冻结策略，拆卸不改变在途投射物；符印伏击在放置时冻结牵引，之后换装、退款或拆卸辅助不改变已有符印",
		"scope": "奥能新星、陨星坠落、裂刃斩、冰霜脉冲与蚀影飞弹可装配；占用一个辅助槽，魔力乘1.20，伤害、冷却、弹数、穿透、减速、范围与伏击触发半径不变；裂刃保留前方180度，搭配环斩才覆盖360度；没有牵引时不新增空策略字段，裂刃没有该冲量，原法术向外冲量保持",
		"statuses": "冰霜保留原冰缓与霜锁准入／时序，牵引不新增冰霜异常时长；感电、点燃或余烬扩散继续使用原准入与结算顺序；牵引不改变它们的数值，点燃与余烬仍互斥",
		"damage_scope": "新星与陨星仍是原direct法术、范围、命中；裂刃仍是攻击、近战、范围、命中；冰霜与蚀影仍是projectile法术、投射物、命中，独立爆炸不牵引；不添加trap伤害标签，不开放陷阱伤害、牵引词族或新的源树消费者",
		"risk": "自心新星、裂刃、冰霜与蚀影会把敌人拉向施放位置，也可能增加贴身风险；地形、分离、敌人原移动与离散步长都会影响实际位移",
		"migration": "牵引原始最低存档版本为43，历史42→43迁移先严格校验并保留原字节备份；本次蚀影兼容扩展保持现行schema61，不赠宝石或碎片，不改既有里程碑奖励身份表"}


static func _inward_pull_cast_brief(cast: Dictionary) -> Dictionary:
	var result: Dictionary = _ambush_cast_brief(cast)
	result["snapshot"] = {}
	if cast.snapshot.has("area_impulse_policy"):
		result.snapshot["area_impulse_policy"] = cast.snapshot.area_impulse_policy.duplicate(true)
	return result


static func ambush_examples() -> Dictionary:
	var model := Canonical.new()
	var snapshot: Dictionary = model.get_combat_snapshot()
	var examples: Dictionary = {}
	var selections: Dictionary = {
		"nova": {"base": [], "shock": ["shock"], "wide": ["breadth"],
			"concentrated": ["concentrate"], "combined_area": ["breadth", "concentrate"]},
		"meteor": {"base": [], "ignite": ["ignite"], "ember": ["ember_proliferation"],
			"combined_area": ["breadth", "concentrate"]},
		"chain": {"base": [], "reach_shock": ["chain_reach", "shock"],
			"extended": ["chain_extension", "chain_reach", "shock", "efficiency"]},
	}
	for skill_id: String in selections:
		var rows: Dictionary = {}
		for mode: String in selections[skill_id]:
			var other_supports: Array = selections[skill_id][mode].duplicate()
			var linked: Array = other_supports.duplicate()
			linked.append("ambush")
			var before: Dictionary = Compiler.compile_group(skill_id, snapshot, other_supports)
			var after: Dictionary = Compiler.compile_group(skill_id, snapshot, linked)
			assert(before.ok and after.ok and after.has("trap_profile"))
			assert(Compiler.Ambush.profile_error(after.trap_profile).is_empty())
			assert(before.recipe == after.recipe and before.cooldown == after.cooldown)
			assert(not (after.packets.bounces[0] if skill_id == "chain" else after.packets.direct).tags.has("trap"))
			rows[mode] = {"before": _ambush_cast_brief(before), "after": _ambush_cast_brief(after)}
		examples[skill_id] = rows
	var quote: Dictionary = Canonical.GemTrade.quote("buy", "support:ambush")
	var test_offer: Dictionary = Town.offer("support:ambush")
	assert(quote.ok and test_offer.available)
	return {"minimum_save_version": Compiler.Ambush.SAVE_VERSION, "source_policy": SourceTree.CURRENT_SAVE_VERSION,
		"equipment_vocabulary": Equipment.CURRENT_VOCABULARY, "support_id": "ambush",
		"skills": Compiler.Ambush.SKILLS, "policy": examples.nova.base.after.trap_profile,
		"icon_source": GemCatalogData.definition("support:ambush").icon, "icon_file": "originals/ambush.png",
		"example_stats": model.get_stats(), "examples": examples, "merchant_quote": quote, "test_offer": test_offer,
		"normal_reward_pool_includes_support": Canonical.Journey.GEM_DEFINITIONS.has("support:ambush"),
		"normal_reward_definition_count": Canonical.Journey.GEM_DEFINITIONS.size(),
		"example_scope": "同一新建角色的真实战斗快照，只替换表列辅助并调用生产Compiler.compile_group；非暴击、未计目标防御的单次命中与原异常配置，不是DPS或实际装配存档",
		"placement": "按下技能只在脚下固定位置放置，不立即造成命中；所有技能组共享名额，布防完成后由当前活敌、出生门禁、目标体型与真实视线共同判定触发",
		"payment": "位置、配置、共享容量、魔力和冷却都通过才放置；成功扣费并记录原冷却，满额失败不消耗魔力、冷却、随机抽样或施放ID；符印不占弹体容量",
		"snapshot": "成功放置时冻结技能、伤害、范围、连锁跳数及一次主暴击；之后换装、退款或移除辅助不改变已有符印，也不释放未触发名额；触发时读取目标当前防御",
		"geometry": "触发半径固定70并计入目标体型。新星与陨星仍以符印为圆心范围命中，范围辅助与源范围属性只改变爆发圈；连锁首跳命中实际触发者，再从该目标寻找最近且未命中的可见活敌，沿用原跳数与后续距离。远链只扩大续跳距离，不扩大触发距离；原600首跳寻敌距离不用于符印触发",
		"timing": "固定模拟tick在该步投射物与燃烧事件结算后观察当前活敌，不承诺连续扫掠；符印按ID逐枚重读活目标，先前击杀不能供下一枚触发；精确到期先于触发，未触发过期直接消失，不爆炸",
		"lifecycle": "暂停冻结；死亡、重开、地图完成或离开、切换存档取消全部符印；临时符印和计时器不写入存档",
		"statuses": "新星与连锁可与感电同用，先结算本次命中再向存活目标施加，后续命中受益；陨星可接点燃或余烬扩散，两者仍互斥，沿原火分量与持续伤害准入；伏击不额外重复应用伤害倍率",
		"damage_scope": "新星与陨星仍为direct法术、范围、命中；连锁仍为bounce法术、连锁、命中，每跳只应用一次原伏击伤害倍率。不添加trap伤害标签，不开放陷阱伤害或其他未实现的源树陷阱属性消费者",
		"provenance": "符印向原范围或连锁命中入口传递放置时的真实cast_id与phase=trap；普通直接Area历史cast_id=0记录保留，普通连锁继续使用其原施放ID",
		"migration": "符印原始最低存档版本42；本次连锁兼容扩展保持当前schema61，不新增宝石ID、不赠宝石或碎片、不改变旧里程碑奖励身份表"}


static func _ambush_cast_brief(cast: Dictionary) -> Dictionary:
	var result: Dictionary = support_cast_brief(cast)
	result["support_ids"] = cast.support_ids.duplicate()
	var packet: Dictionary = cast.packets.bounces[0] if cast.skill_id == "chain" else cast.packets.projectile if cast.skill_id in ["frost", "shade_bolt"] else cast.packets.direct
	result["packet"] = packet.duplicate(true)
	result["resolved"] = Damage.resolve(packet, cast.snapshot.modifiers)
	if cast.skill_id == "chain":
		result["bounce_totals"] = []
		for bounce: Dictionary in cast.packets.bounces:
			result.bounce_totals.append(Damage.resolve(bounce, cast.snapshot.modifiers).total)
	for field: String in ["burn_profile", "shock_profile", "critical"]:
		if cast.has(field): result[field] = cast[field].duplicate(true)
	return result

static func source_spatial_examples()->Dictionary:
	var examples:Array=[]
	for entry:Dictionary in [
		{"field":"area_size_increased","value":0.12,"node_id":"5560","skill":"nova"},
		{"field":"spell_area_size_increased","value":0.1,"node_id":"51801","skill":"meteor"},
		{"field":"melee_area_size_increased","value":0.1,"node_id":"11700","skill":"cleave"},
		{"field":"projectile_speed_increased","value":0.1,"node_id":"44306","skill":"tornado"}]:
		var stats:Dictionary={"damage":20.0};stats[entry.field]=entry.value
		var base:Dictionary=Compiler.compile_skill(entry.skill,Recipes.snapshot({"damage":20.0},["return_on_range","explode_on_flight_end"]),[])
		var current:Dictionary=Compiler.compile_skill(entry.skill,Recipes.snapshot(stats,["return_on_range","explode_on_flight_end"]),[])
		assert(base.ok and current.ok)
		examples.append({"input":entry,"source_node":SourceTree.Data.node(entry.node_id),"source_effect":SourceTree.node_effect(entry.node_id),"before":base,"after":current,"details":Preview.details(current)})
	var slow:Dictionary=Compiler.compile_skill("bolt",Recipes.snapshot({"damage":20.0,"projectile_speed_increased":-0.1},[]),[])
	return {"minimum_save_version":20,"fields":Compiler.Spatial.STATS,"examples":examples,"reduced_speed_example":slow,
		"area_formula":"最终半径 = 基础半径 × sqrt((1 + 全局面积 increased + 适用技能面积 increased) × 辅助面积 more 乘积)",
		"speed_formula":"最终速度 = 基础速度 × (1 + 投射速度 increased - reduced) × 辅助速度乘积",
		"area_damage_is_separate":true,"secondary_explosion_scope":"仅全局面积；独立爆炸不带法术或近战标签",
		"unchanged_limits":["投射物射程","寿命上限","贯穿次数","命中伤害公式","耗魔","冷却","墙体终止优先级"],
		"snapshot_rule":"施放时冻结；母箭、子箭和返回读取最终配方，不二次增加",
		"example_scope":"隔离演算输入，只演示单项几何增幅；不是整个源节点的伤害预估或已分配构筑",
		"legacy_rule":"v19先按旧执行覆盖完整验证并保存原字节备份，再迁移到v20；旧版本注入新节点拒绝"}


static func source_recharge_examples()->Dictionary:
	var examples:Array=[]
	for id:String in ["3452","23690"]:
		var effect:Dictionary=SourceTree.node_effect(id)
		var stats:Dictionary={"shield_regen":10.0}
		for grant:Dictionary in effect.grants:
			if grant.stat in ["shield_recharge_rate_increased","shield_recharge_start_faster"]:stats[grant.stat]=float(stats.get(grant.stat,0.0))+float(grant.value)
		var profile:Dictionary=Defense.recharge_profile(stats,"player")
		assert(profile.ok and effect.status=="full")
		examples.append({"node_id":id,"source_node":SourceTree.Data.node(id),"source_effect":effect,"input":stats,"before":Defense.recharge_profile({"shield_regen":10.0}),"after":profile,"monster_after":Defense.recharge_profile(stats,"monster")})
	return {"minimum_save_version":21,"rate_stat":"shield_recharge_rate_increased","start_stat":"shield_recharge_start_faster","base_delay":Defense.RECHARGE_BASE_DELAY,"examples":examples,
		"rate_formula":"实际每秒充能 = 本游戏平面基底 × (1 + 充能速率 increased 总和)",
		"delay_formula":"下一次有效损伤等待 = 本游戏4秒基底 / (1 + 更快开始充能总和)",
		"timing":"有效损伤命中锁定当次等待；闪避、无敌与零伤害不重置；跨阈值只按剩余delta恢复",
		"changes":"换装或退款立即更新后续速率，已开始等待不改，下一次有效命中采用新等待值",
		"ward":"护盾技能仍独立立即恢复75%最大护盾并清等待",
		"example_scope":"以10每秒原型基底隔离展示充能两属性；不代表源节点的全部护盾上限或PoE完整基底",
		"unsupported":["格挡触发充能","压制触发充能","护盾充能转为生命","伤害不打断充能","最大抗性与压制节点其余未实现部分"],
		"legacy_rule":"v20先按旧执行门槛验证并原字节备份再迁移；旧版本注入新充能节点拒绝"}


static func source_mana_cost_examples()->Dictionary:
	var examples:Array=[]
	for node_ids:Array in [["10835"],["26960"],["10835","26960"]]:
		var stats:Dictionary={"damage":20.0};var source_nodes:Array=[]
		for id:String in node_ids:
			var effect:Dictionary=SourceTree.node_effect(id);assert(effect.status=="full");source_nodes.append({"node_id":id,"stats":SourceTree.Data.node(id).stats,"effect":effect})
			for grant:Dictionary in effect.grants:
				if grant.stat in Compiler.ResourceCost.STATS:stats[grant.stat]=float(stats.get(grant.stat,0.0))+float(grant.value)
		var cast:Dictionary=Compiler.compile_group("nova",Recipes.snapshot(stats,[]),["efficiency","quickcast"]);assert(cast.ok)
		examples.append({"source_nodes":source_nodes,"input":stats,"compiled":cast,"source_factors":cast.cost_factors})
	var mastery_entrances:Array=[]
	for id:String in SourceTree.Data.standard_ids():
		for option:Dictionary in SourceTree.Data.node(id).mastery_effects:
			if int(option.effect)==12119:mastery_entrances.append(id)
	return {"mastery":{"effect_id":12119,"entrances":mastery_entrances,"increased_efficiency":0.15,"unique_effect_rule":"相同精通效果ID最多选择一次；先达本组普通连通显著节点"},"minimum_save_version":22,"fields":Compiler.ResourceCost.STATS,"formula":"最终魔力 = 原辅助后魔力 × (1 + 成本增加总和) / (1 + 成本效率总和)","formula_origin":"本游戏明确实现规则；不把效率当线性reduced，不声称完整PoE公式","skills":Data.SKILLS.keys(),"examples":examples,"free_basic_attack":true,"float_payment":true,"unchanged":["伤害","冷却债务","技能效果","射程与范围"],"snapshot":"点击施放时读当前构筑编译结果；已产生的group/main UID冷却不会因改成本或移动宝石重置","legacy_rule":"严格旧21验证与原字节备份后迁移22，UID/点数/进度/revision保留；旧版本注入新节点拒绝","unsupported":["法术限定效率","诅咒与链接技能成本","生命转费","保留效率"],"example_scope":"新星加节能/疾咏，隔离展示成本字段；节点其余魔力/恢复收益仍由对应原消费者结算"}


static func source_flask_examples()->Dictionary:
	var examples:Array=[]
	for id:String in ["18402","17546","60648"]:
		var effect:Dictionary=SourceTree.node_effect(id);assert(effect.status=="full")
		var stats:Dictionary={}
		for grant:Dictionary in effect.grants:
			if grant.stat in FlaskModifiers.STATS:stats[grant.stat]=float(stats.get(grant.stat,0.0))+float(grant.value)
		var profiles:Dictionary={}
		for definition_id:String in Flasks.DEFINITIONS:profiles[definition_id]=FlaskModifiers.profile(definition_id,stats,100.0)
		examples.append({"node_id":id,"stats":SourceTree.Data.node(id).stats,"input":stats,"profiles":profiles})
	var runtime:=FlaskRuntime.new();var uid:="reference_charge";assert(runtime.reset({uid:"flask:life"}))
	for i:int in range(3):assert(runtime.use(uid,0.0,100.0).ok);runtime.clear_effects()
	var charge_rows:Array=[]
	for i:int in range(20):
		runtime.charge_rewarded_kill([uid],{"flask_charges_gained_increased":0.15})
		var state:Dictionary=runtime.snapshot()
		charge_rows.append({"root_kills":i+1,"whole_charges":state.charges_by_uid[uid],"remainder_micro":state.get("charge_remainders_micro",{}).get(uid,0)})
	var newly_complete:Array=[]
	for id:String in SourceTree.Data.standard_ids():
		if SourceTree.node_effect(id,0,22).status!="full" and SourceTree.node_effect(id,0,23).status=="full":newly_complete.append(id)
	newly_complete.sort()
	return {"minimum_save_version":23,"fields":FlaskModifiers.STATS,"new_complete_ordinary_nodes":newly_complete,"examples":examples,"charge_rows":charge_rows,"charge_unit":FlaskModifiers.CHARGE_UNIT,
		"recovery_formula":"本次总回复 = 使用时对应最大资源 × 35% × (1 + 相应药剂回复增幅)",
		"charge_formula":"每个有效奖励根怪获得充能 = 1 × (1 + 充能获取增幅)",
		"locked_recovery":"使用时冻结本次总量与3秒速率；期间换装或退款不重算，当前资源上限仍限制实际回复",
		"charge_lifecycle":"余量按同一药剂UID累计，换槽或移入背包不清零；只有当时装备的药剂获充能，满30在本次合法奖励时丢弃超额与余量",
		"reward_gate":"后代、演示怪及重复死亡不获充能；保持原奖励RNG与物品输出",
		"unchanged":"基础30充能、每次消耗10、持续3秒；同资源不叠加，满资源或回复中不扣费",
		"legacy_rule":"严格旧22验证并原字节备份后迁移23；旧版本注入新药剂节点拒绝，不额外赠物或点数",
		"runtime_persisted":false,"example_scope":"100资源上限隔离示例，仅展示本批药剂字段，节点其他生命或魔力收益仍由原消费者结算",
		"unsupported":["药剂持续时间","定时或命中获得充能","压制触发充能","药剂期间持续伤害减免"]}


static func map_boss_examples()->Dictionary:
	var examples:Dictionary={};var stats:Dictionary=Canonical.new().get_stats()
	for map_id:String in Maps.MAPS:
		var map:Dictionary=MapRules.compile(map_id,[],[]).profile;var factory:=MonsterRuntime.new()
		var admitted:Dictionary=MapAdmission.create_root(factory,map,"rift_warden",map.wave,Vector2(120,0),"map_boss","",[],true);assert(admitted.ok)
		var enemy:Dictionary=admitted.enemy;enemy.spawn=0.0
		var policy:Dictionary=Monsters.telegraph_policy(enemy);var definition:=MapBosses.definition(map.boss_attack_id)
		var center:Vector2=enemy.pos if policy.target_rule=="self_at_start" else Vector2.ZERO
		var runtime:=Telegraphs.new();var started:Dictionary=runtime.start(enemy,center,policy.profile,policy.visual_pattern);assert(started.ok)
		var events:Array[Dictionary]=runtime.advance(policy.profile.windup_seconds,[enemy]);assert(events.size()==1)
		var event:Dictionary=events[0];var cases:Dictionary={}
		for key:String in ["standing","moving"]:
			var at:Vector2=Vector2.ZERO if key=="standing" else Vector2(-float(stats.move_speed)*float(policy.profile.windup_seconds),0)
			var inside:bool=Telegraphs.overlaps(event,at,Arena.PLAYER_RADIUS)
			cases[key]={"position":at,"inside":inside,"settlement":Defense.incoming_source_hit(event.packet.base,stats,5.0,100.0,"player") if inside else {}}
		assert(cases.standing.inside and not cases.moving.inside)
		examples[map_id]={"definition":definition,"policy":policy,"source":enemy,"event":event,"start":started.attack,"cases":cases,
			"player_radius":Arena.PLAYER_RADIUS,"scope":"无词缀地图首领与默认防御构筑的相对坐标示例；直线退离、不含障碍或闪避概率",
			"rules":"替代此地图首领接触攻击，动作停追击，攻速只缩恢复；开始检查来源视线，结算检查固定圆心视线；死亡/返城取消",
			"preserves":"原普通首领、生命护盾/机制、奖励与死亡4后代保持；后代不继承新攻击；无新存档字段"}
		if policy.visual_pattern=="sunwell_echo":
			examples[map_id].preserves="原普通首领、生命护盾/机制、奖励与死亡后代保持；后代不继承新攻击；本次动作状态不存档"
			# Keep the shared single-event profile metadata unchanged. Only this
			# authored map pattern receives a sequence, with real runtime events.
			var next_events:Array[Dictionary]=runtime.advance(float(definition.pulse_interval),[enemy],true)
			assert(next_events.size()==int(definition.pulse_count)-1)
			events.append_array(next_events)
			var pulses:Array=[];var deadlines:Array=[];var normalized_clock:float=0.0
			for pulse:Dictionary in events:
				normalized_clock+=float(pulse.step_time)
				assert(is_equal_approx(normalized_clock,float(pulse.attack_age)) and pulse.center==started.attack.center)
				var pulse_cases:Dictionary={}
				for key:String in ["standing","moving"]:
					var at:Vector2=Vector2.ZERO if key=="standing" else Vector2(-float(stats.move_speed)*normalized_clock,0)
					var inside:bool=Telegraphs.overlaps(pulse,at,Arena.PLAYER_RADIUS)
					pulse_cases[key]={"position":at,"inside":inside,
						"settlement":Defense.incoming_source_hit(pulse.packet.base,stats,5.0,100.0,"player") if inside else {}}
				assert(pulse_cases.standing.inside and not pulse_cases.moving.inside)
				deadlines.append(normalized_clock)
				pulses.append({"event":pulse,"normalized_deadline":normalized_clock,"cases":pulse_cases})
			var recovery_state:Dictionary=runtime.state_for(enemy.id)
			var final_events:Array[Dictionary]=runtime.advance(float(policy.profile.recovery_seconds),[enemy],true)
			assert(recovery_state.phase=="recovery" and final_events.is_empty() and runtime.active_count()==0)
			examples[map_id]["sequence"]={"pulse_count":int(definition.pulse_count),"pulse_interval":definition.pulse_interval,
				"locked_center":started.attack.center,"normalized_deadlines":deadlines,"pulses":pulses,
				"contact_components":Monsters.contact_components(enemy),"total_contact_multiplier":float(policy.profile.damage_multiplier)*events.size(),
				"base_recovery_seconds":definition.profile.recovery_seconds,"actual_recovery_seconds":policy.profile.recovery_seconds,
				"source_attack_speed":enemy.attack_speed,"recovery_state":recovery_state,"complete_after_recovery":runtime.active_count()==0,
				"move_speed":stats.move_speed,"default_profile_max_events":TelegraphProfiles.metadata().max_events_per_attack,
				"settlement_scope":"两次均为独立命中示例，各从护盾5、生命100开始；实际仍逐次检查位置、墙视线、闪避与受击保护，不将示例生命扣减相加"}
	return examples


static func mist_skitter_examples(enemy: Dictionary) -> Dictionary:
	var map_id: String = "sunwell_terrace"
	var layout: Dictionary = CampLayoutData.layout(map_id, LEGACY_REFERENCE_BOUNDS).landmarks
	var baseline: Dictionary = Monsters.make_enemy(1, "skitter", int(enemy.wave), Vector2.ZERO, "ordinary")
	var baseline_evasion: float = float(AttackRules.monster_profile(int(baseline.kind)).evasion)
	var chances: Array = []
	# Formula probes, not authored equipment, build rankings, or extra damage.
	for accuracy: float in [100.0, 284.0, 304.0, 414.0, 600.0]:
		var ordinary: Dictionary = AttackRules.resolve(accuracy, float(enemy.evasion))
		var old: Dictionary = AttackRules.resolve(accuracy, baseline_evasion)
		var resolute: Dictionary = AttackRules.resolve(accuracy, float(enemy.evasion), 50.0, ResoluteRules.active({"resolute_technique":1.0}))
		assert(ordinary.ok and old.ok and resolute.ok)
		chances.append({"accuracy":accuracy, "mist_chance":ordinary.chance,
			"baseline_chance":old.chance, "resolute_chance":resolute.chance})
	var appearances: Array = []
	for tier: int in [1, 2, 3]:
		var profile: Dictionary = MapRules.compile_normal(map_id, tier, [], []).profile
		appearances.append({"tier":tier, "wave":profile.wave, "eligible":MistSkitterRoster.eligible_profile(profile)})
	var roster_examples: Array = []
	for tier: int in [2, 3]:
		for specials: Array in [[], ["storm_patrol"]]:
			var profile: Dictionary = MapRules.compile_normal(map_id, tier, [], specials).profile
			var state := CampRosterData.new()
			assert(state.begin(profile, layout, 43).ok)
			var admissions: Dictionary = {}
			for camp: Dictionary in layout.camps:
				var indices: Array = []
				for entry: Dictionary in state.entries(str(camp.id)):
					if entry.template_id == "mist_skitter":indices.append(entry.admission_index)
				assert(indices.size() <= 1)
				admissions[camp.id] = indices
			roster_examples.append({"tier":tier, "wave":profile.wave,
				"special_ids":profile.special_ids, "mist_admission_indices":admissions})
	var fixed_test: Dictionary = MapRules.compile(map_id, [], []).profile
	assert(not MistSkitterRoster.eligible_profile(fixed_test))
	return {"policy":Monsters.MIST_SKITTER_POLICY.duplicate(true), "baseline_template":"skitter",
		"baseline_example":baseline, "baseline_evasion":baseline_evasion,
		"accuracy_probes":chances, "formal_profiles":appearances,
		"fixed_test_wave":fixed_test.wave, "fixed_test_eligible":false,
		"maximum_per_camp":1, "maximum_per_map":layout.camps.size(),
		"map_root_count":Maps.MAPS[map_id].ordinary_target,
		"roster_example_seed":43, "roster_examples":roster_examples}


static func sunwell_examples()->Dictionary:
	var map_id:String="sunwell_terrace"
	var layout:Dictionary=CampLayoutData.layout(map_id,LEGACY_REFERENCE_BOUNDS).landmarks
	var tiers:Array=[];var roster:Dictionary={}
	var ordinary_ids:Array=[]
	for entry:Dictionary in Maps.options(false).normal_modifiers:
		if ordinary_ids.size()<int(Maps.options(false).max_normal):ordinary_ids.append(entry.id)
	for tier:int in range(1,MapRules.NormalCatalog.LABELS.size()+1):
		var base:Dictionary=MapRules.compile_normal(map_id,tier,[],[]).profile
		var special_ids:Array=[]
		for special_id:String in Maps.SPECIAL:
			if int(base.wave)>=int(Maps.SPECIAL[special_id].minimum_wave):special_ids.append(special_id)
		var selected_special:Array=[] if special_ids.is_empty() else [special_ids[0]]
		var bonus:Dictionary=MapRules.compile_normal(map_id,tier,ordinary_ids,selected_special).profile
		tiers.append({"base":base,"eligible_special_ids":special_ids,"maximum_bonus_example":bonus})
		var camps:Dictionary={}
		for camp:Dictionary in layout.camps:
			var examples:Array=[]
			for ordinal:int in range(1,int(camp.root_count)+1):
				var roll:Dictionary={"template":SunwellRoster.BASE_TEMPLATES[0],"rarity":"normal","mechanisms":[]}
				examples.append(SunwellRoster.template_for_roll(int(base.wave),str(camp.id),ordinal,roll))
			camps[camp.id]=examples
		roster[str(base.wave)]=camps
	var old:Dictionary=Canonical.new().snapshot()
	old.version=Canonical.Rules.V29_VERSION;old.journey=Canonical.Journey.empty_legacy()
	var migrated:Dictionary=ThirdMapMigrationData.migrate_v29(old)
	assert(not migrated.is_empty())
	var prototype:Dictionary=Monsters.make_enemy(1,"crawler",int(Maps.MAPS[map_id].wave),Vector2.ZERO,"ordinary")
	return {"map_id":map_id,"save_version":Canonical.Rules.VERSION,"tiers":tiers,
		"patterns":SunwellRoster.PATTERNS,"roster_examples_by_wave":roster,
		"roster_scope":"只展示原抽签为基础物种的按位替换；灰烬保留名额，分裂体与母巢保留原抽签且占用序号；稀有度、机制与奖励不变；所选巡逻词缀最后按编排物种替换",
		"elemental_gates":Monsters.ELEMENTAL_ENCOUNTERS,
		"player_clearance":CampAdmissionData.PLAYER_CLEARANCE,"spawn_seconds":prototype.spawn,
		"migration_example":{"from_version":old.version,"to_version":migrated.version,
			"before_best_tiers":old.journey.best_tiers,"after_best_tiers":migrated.journey.best_tiers,
			"items_preserved":old.items==migrated.items,"currencies_preserved":old.items==migrated.items and old.crafting==migrated.crafting}}


static func source_critical_examples()->Dictionary:
	var examples:Array=[]
	for node_ids:Array in [[],["35894"],["35894","28754"],["53493"],["38664","56460"],["14804","12794"]]:
		var stats:Dictionary={"damage":20.0,"crit_base_chance":0.05,"crit_base_multiplier":1.5}
		var sources:Array=[]
		for id:String in node_ids:
			var effect:Dictionary=SourceTree.node_effect(id);assert(effect.status=="full")
			sources.append({"id":id,"lines":SourceTree.Data.node(id).stats,"effect":effect})
			for grant:Dictionary in effect.grants:
				if grant.stat in Compiler.Critical.STAT_KEYS:stats[grant.stat]=float(stats.get(grant.stat,0.0))+float(grant.value)
		var profiles:Dictionary={}
		for skill_id:String in ["tornado","cleave","nova","shade_bolt"]:
			var cast:Dictionary=Compiler.compile_group(skill_id,Recipes.snapshot(stats,["explode_on_flight_end"]),[]);assert(cast.ok)
			profiles[skill_id]=cast.critical
		examples.append({"source_nodes":sources,"input":stats,"profiles":profiles})
	var newly_complete:Array=[]
	for id:String in SourceTree.Data.standard_ids():
		if SourceTree.Data.node(id).type!="mastery" and SourceTree.node_effect(id,0,23).status!="full" and SourceTree.node_effect(id,0,24).status=="full":newly_complete.append(id)
	newly_complete.sort()
	return {"minimum_save_version":24,"fields":Compiler.Critical.STAT_KEYS,"base_chance":0.05,"base_multiplier":1.5,"natural_monster_base_chance":0.0,"new_complete_ordinary_nodes":newly_complete,"new_mastery_effect_ids":[],"examples":examples,
		"chance_formula":"基础暴击几率 × (1 + 全局与匹配作用域的增加之和)，限制0%至100%",
		"multiplier_formula":"基础150% + 全局与匹配作用域的暴击倍率百分点",
		"cast_rule":"施放获准后冻结一次主命中结果；范围目标、连锁、母子弹与返回共用；未命中不造成暴击伤害",
		"secondary_rule":"每次真实自然到期爆炸独立抽取，仅采用全局属性；同一爆炸内所有目标共用，碰墙/消耗/取消不触发",
		"damage_order":"伤害增幅 → 暴击倍率 → 抗性与按本次命中大小结算的护甲 → 护盾 → 生命",
		"randomness":"独立战斗随机流不从掉落随机流抽数；0%和100%不抽随机数，失败施放不改变随机流",
		"legacy_rule":"严格旧23词汇验证并保留原字节备份后迁移24；物品/UID/节点/点数保持，旧版本注入新暴击节点拒绝",
		"balance_change":"本批玩家新增5%基础暴击和150%基础倍率；这是显式平衡变化，自然怪物保持0%",
		"example_scope":"只提取所列源节点的暴击字段展示作用域，不代替真实连通/预算要求；其余节点效果仍由原消费者结算",
		"unsupported":["幸运","局部武器暴击","暴击触发","召唤物暴击","条件暴击","暴击异常/持续伤害"]}


static func source_leech_examples()->Dictionary:
	var routes:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v040/source-leech-example-paths.json"))
	var coverage:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v040/source-leech-coverage.json"))
	var examples:Array=[]
	for entry:Dictionary in routes.examples:
		var model:=Canonical.new();var candidate:Dictionary=model.snapshot()
		candidate.progress.level=int(entry.required_level);candidate.progress.xp=0;candidate.talents.class_id=int(entry.class_id)
		candidate.talents.allocated=entry.allocated.duplicate();candidate.talents.normal_points=int(candidate.progress.level)+4-int(entry.points_spent)
		assert(model.Rules.reason(candidate).is_empty(),"Reference route must be a real legal build")
		model._accept_memory(candidate)
		examples.append({"id":entry.id,"required_level":entry.required_level,"points_spent":entry.points_spent,
			"allocated":entry.allocated,"profile":model.get_leech_profile(),"tornado":model.get_skill_cast("tornado").get("leech",{}),
			"nova":model.get_skill_cast("nova").get("leech",{})})
	return {"minimum_save_version":25,"examples":examples,"new_complete_ordinary_nodes":coverage.new_full_standard_ordinary_nodes,
		"new_full_mastery_effect_ids":coverage.new_full_mastery_distinct_effect_ids,"new_reachable_mastery_effect_count":coverage.new_reachable_mastery_effect_count,
		"new_reachable_ordinary_count":20,"physical_mana_source_locked":true,
		"damage_basis":"防御后实际扣除的护盾与生命之和；不含过量伤害。物理份额按最终物理伤害占比分摊",
		"amount_formula":"实际损伤 × 攻击偷取率 + 实际物理份额 × 物理攻击偷取率；每次最多为施放时对应资源上限的10%",
		"rate_formula":"每实例每秒为施放时资源上限的2% × (1 + 对应速率增加)",
		"cap_formula":"全体每秒最多为当前资源上限的20% × (1 + 对应总上限增加)，超过部分不积压",
		"lifecycle":"命中后下一模拟步开始；满额立即清除对应资源实例；死亡、重开、返城、档案切换清除，暂停冻结，不存档",
		"scope":"本游戏初版规则，玩家攻击命中有效；母箭、子箭、返回继承冻结比例，每个实际目标分别结算；不含攻击标签的独立爆炸不偷取",
		"coverage_note":"21个新增完整普通节点，其中20个从七起点可达；1个精通效果句式完整但入口前置未实现，当前不可分配；物理攻击魔力节点另含未实现效果仍锁定",
		"unsupported":["即时偷取","过量伤害偷取","满额保留","召唤物偷取","护盾偷取","条件偷取"]}


static func normal_journey_examples()->Dictionary:
	var tiers:Array=[]
	for map_id:String in Canonical.Journey.MAP_IDS:
		for tier:int in range(1,4):
			var result:Dictionary=MapRules.compile_normal(map_id,tier,[],[])
			assert(result.ok)
			tiers.append(result.profile)
	return {"minimum_save_version":26,"default_scene":"normal_town","tiers":tiers,
		"normal_bonus":1,"special_bonus":2,"maximum_bonus":4,"free_test_stock_isolated":true,
		"gem_interval":Canonical.Journey.GEM_INTERVAL,"flask_interval":Canonical.Journey.FLASK_INTERVAL,
		"gem_vocabulary":Canonical.Journey.GEM_DEFINITIONS,"initial_journey":Canonical.Journey.empty(),
		"lifecycle":"入图先保存费用与唯一run_id；完成一次保存解锁与待领。死亡重试再次付费；放弃不退；重新载入未完地图回正式城镇",
		"claims":"地图碎片待领阻止新正式图，宝石药剂待领不阻止；领取只提交实际可入包部分，失败原子保留",
		"isolation":"测试供应与测试击杀只在独立档；正常档不能领取测试商店物品；正常竞技练习也计累计合法根怪",
		"migration":"严格旧25验证与原字节备份后增加空旅程，不追补过去击杀；现有UID/构筑/物品/货币保持",
		"balance":"本游戏可调整原型；未引入新正常商店经济、随机地图物品或完整终局系统"}


static func burning_examples()->Dictionary:
	var examples:Dictionary={}
	for id:String in ["meteor","tornado"]:
		var cast:Dictionary=Compiler.compile_group(id,Recipes.snapshot({"damage":100.0},[]),["ignite"])
		assert(cast.ok and cast.has("burn_profile"))
		examples[id]={"profile":cast.burn_profile,"mana":cast.mana,"cooldown":cast.cooldown,"details":Preview.details(cast)}
	return {"save_version":28,"support_id":"ignite","icon_file":"originals/ignite.png","player_policy":Compiler.Burn.PLAYER_POLICY,"enemy_policy":Compiler.Burn.ENEMY_POLICY,"examples":examples,
		"scope":"已解析主命中火分量只作为一次基数；持续扣伤不再套主命中、投射物、暴击或偷取",
		"stacking":"单目标一条，更强覆盖，同强采用新条时长刷新；基础3秒，加速后使用压缩时长，弱条忽略",
		"secondary":"独立装备爆炸不继承；母子和返回沿原获准主命中规则",
		"defense_example":Defense.incoming_burn(100.0,0.25,10.0,100.0,"player"),
		"enemy_budget":{"contact_damage":20.0,"physical_hit":14.0,"fire_hit":7.0,"fire_burn_dps":7.0/3.0,"duration":3.0,"total_before_defense":28.0},
		"immunity":"尊重原伤害免疫；期间时长流逝、不补扣，持续伤害本身不授予受击保护",
		"source_words":"本游戏燃烧原型；schema32接入8个完整火焰持续伤害节点，schema33接入3个完整更快伤害异常节点；当前仅由玩家燃烧消费，不代表流血、中毒或完整异常体系已实现"}


static func shock_examples()->Dictionary:
	var examples:Dictionary={}
	var incompatible:Dictionary={}
	for id:String in Data.SKILLS:
		var reason:String=Supports.compatibility_reason(id,["shock"])
		if not reason.is_empty():
			incompatible[id]=reason
			continue
		var snapshot:Dictionary=Recipes.snapshot({"damage":100.0},[])
		var before:Dictionary=Compiler.compile_group(id,snapshot,[])
		var after:Dictionary=Compiler.compile_group(id,snapshot,["shock"])
		assert(before.ok and after.ok and after.has("shock_profile"))
		examples[id]={"profile":after.shock_profile,"before_hit":_direct_total(before),
			"supported_hit":_direct_total(after),"before_mana":before.mana,"mana":after.mana,
			"details":Preview.details(after),"unsupported_cast_has_policy":before.snapshot.has("shock_policy")}
	# Read existing status, settle the applying hit, and only then attach it.
	# A deliberately simple 100-lightning input makes the ordering inspectable.
	var runtime:=ShockRuntimeData.new()
	var started_at:float=10.0
	var first_status:Dictionary=runtime.status_at("monster",1,started_at)
	var first_hit:Dictionary=Defense.incoming_hit({"lightning":100.0},{},0.0,1000.0,"monster",first_status.hit_damage_taken_increased)
	var admission:Dictionary=Compiler.Shock.from_lightning_hit(first_hit.health_lost,Compiler.Shock.PLAYER_POLICY)
	assert(first_hit.ok and admission.ok)
	var applied:Dictionary=runtime.apply("monster",1,0,started_at,Compiler.Shock.PLAYER_POLICY,{"skill_id":"bolt"})
	assert(applied.ok and applied.applied)
	var later_at:float=10.5
	var later_status:Dictionary=runtime.status_at("monster",1,later_at)
	var later_hit:Dictionary=Defense.incoming_hit({"lightning":100.0},{},0.0,1000.0,"monster",later_status.hit_damage_taken_increased)
	var refreshed:Dictionary=runtime.apply("monster",1,0,later_at,Compiler.Shock.PLAYER_POLICY,{"skill_id":"nova"})
	assert(refreshed.ok and refreshed.refreshed)
	var refresh_status:Dictionary=runtime.status_at("monster",1,later_at)
	var expired:Dictionary=runtime.status_at("monster",1,later_at+float(Compiler.Shock.PLAYER_POLICY.duration))
	var enemy:Dictionary=Monsters.make_enemy(1,"storm_skitter",int(Monsters.ELEMENTAL_ENCOUNTERS.storm_skitter.minimum_wave),Vector2.ZERO,"demo")
	var enemy_attack:Dictionary=Monsters.telegraph_policy(enemy)
	var old:Dictionary=Canonical.new().snapshot()
	old.version=Canonical.Rules.V30_VERSION
	var migrated:Dictionary=ShockMigration.migrate_v30(old)
	assert(not migrated.is_empty())
	var changed_fields:Array=[]
	for field:String in old:
		if old[field]!=migrated[field]:changed_fields.append(field)
	assert(changed_fields==["version"])
	var quote:Dictionary=Canonical.GemTrade.quote("buy","support:shock")
	var test_offer:Dictionary=Town.offer("support:shock")
	assert(quote.ok and test_offer.available)
	var reward_ordinals:Array=[]
	for ordinal:int in range(1,Canonical.Journey.GEM_DEFINITIONS.size()+2):
		reward_ordinals.append({"ordinal":ordinal,"definition_id":Canonical.Journey.gem_definition(ordinal)})
	return {"save_version":Supports.Shock.SAVE_VERSION,"support_id":"shock",
		"icon_file":"originals/shock.png","icon_source":GemCatalogData.definition("support:shock").icon,
		"player_policy":Compiler.Shock.PLAYER_POLICY,"enemy_policy":Compiler.Shock.ENEMY_POLICY,
		"examples":examples,"incompatible_skills":incompatible,"enemy_template":"storm_skitter","enemy_attack":enemy_attack,
		"settlement_example":{"input_components":{"lightning":100.0},"started_at":started_at,"later_at":later_at,
			"first_status":first_status,"first_hit":first_hit,"admission":admission,"applied":applied,
			"later_status":later_status,"later_hit":later_hit,"refreshed":refreshed,"refresh_status":refresh_status,
			"expired":expired,"burn_while_shocked":Defense.incoming_burn(100.0,0.0,0.0,1000.0,"monster")},
		"merchant_quote":quote,"test_offer":test_offer,
		"migration_example":{"from_version":old.version,"to_version":migrated.version,"changed_fields":changed_fields,
			"items_before":old.items.size(),"items_after":migrated.items.size(),"granted_items":0},
		"normal_reward_pool_includes_support":Canonical.Journey.GEM_DEFINITIONS.has("support:shock"),"reward_ordinals":reward_ordinals,
		"scope":"仅显式装配感电辅助的奥术飞弹、奥能新星与连锁闪电主命中可施加；敌方仅雷纹锁点预警附加，接触攻击与其他闪电伤害不会自动感电，独立装备爆炸不继承",
		"settlement":"先读取已有感电并结算命中，再按实际正值闪电损伤对存活目标施加；施加这条感电的命中不享受自己的增伤，后续命中才受益",
		"damage_scope":"所有后续命中类型共用受击增伤；持续伤害不受影响，感电本身不造成伤害",
		"stacking":"单目标一条，同强刷新完整时长，不叠加；截止时间本身已失效",
		"lifecycle":"暂停冻结，目标死亡移除，返城与重开清空；状态不存盘，不新增随机抽样、暴击、偷取或奖励路径",
		"migration":"严格验证旧schema30后迁移schema31，仅版本字段变化，不赠物、不退款、不改既有UID或旧奖励序号",
		"source_words":"本游戏固定原型，仅显式支持；不解锁尚未实现的源树感电或异常词条"}


static func ember_proliferation_examples()->Dictionary:
	var examples:Dictionary={}
	var incompatible:Dictionary={}
	for id:String in Data.SKILLS:
		var reason:String=Supports.compatibility_reason(id,["ember_proliferation"])
		if not reason.is_empty():
			incompatible[id]=reason
			continue
		var cast:Dictionary=Compiler.compile_group(id,Recipes.snapshot({"damage":100.0},[]),["ember_proliferation"])
		assert(cast.ok and cast.has("burn_profile"))
		examples[id]={"profile":cast.burn_profile,"mana":cast.mana,"cooldown":cast.cooldown,"details":Preview.details(cast)}
	var exclusive:Array=[]
	for selection:Array in [["ignite","ember_proliferation"],["ember_proliferation","ignite"]]:
		var result:Dictionary=Compiler.compile_group("meteor",Recipes.snapshot({"damage":100.0},[]),selection)
		assert(not result.ok)
		exclusive.append({"selection":selection,"error":result.error})
	# An actual stored burn and the production selector provide the transfer example.
	var runtime:=BurnRuntime.new()
	var started_at:float=10.0
	var transferred_at:float=11.75
	var duration:float=float(Compiler.Ember.POLICY.duration)
	var raw_dps:float=float(examples.meteor.profile.roles.direct.dps)
	var attached:Dictionary=runtime.apply("monster",90,0,raw_dps,duration,started_at,
		{"skill_id":"meteor","ember_generation":0,"ember_expiry":started_at+duration})
	assert(attached.ok and attached.applied)
	var source:Dictionary=runtime.status_for("monster",90)
	var inherited:Dictionary=Compiler.Proliferation.transfer(source,transferred_at)
	assert(inherited.ok and not inherited.burn.is_empty())
	var received:Dictionary=runtime.apply("monster",1,90,inherited.burn.raw_dps,inherited.burn.duration,
		transferred_at,inherited.burn.provenance)
	assert(received.ok and received.applied)
	var recipient:Dictionary=runtime.status_for("monster",1)
	var second_hop:Dictionary=Compiler.Proliferation.transfer(recipient,transferred_at+0.25)
	var expired:Dictionary=Compiler.Proliferation.transfer(source,started_at+duration)
	assert(second_hop.ok and second_hop.burn.is_empty() and expired.ok and expired.burn.is_empty())
	var geometry:=MapGeometryData.new()
	assert(geometry.configure("broken_ruins",Rect2(0,0,1800,1000)))
	var origin:=Vector2(560,300)
	var candidates:Array=[]
	for id:int in range(1,11):
		candidates.append({"id":id,"pos":origin-Vector2(id*5,0),"health":100.0,"spawn":0.0})
	candidates.append_array([
		{"id":90,"pos":origin,"health":100.0,"spawn":0.0},
		{"id":201,"pos":Vector2(650,300),"health":100.0,"spawn":0.0},
		{"id":202,"pos":origin-Vector2(4,0),"health":100.0,"spawn":1.0},
		{"id":203,"pos":origin-Vector2(3,0),"health":0.0,"spawn":0.0},
		{"id":204,"pos":origin-Vector2(float(Compiler.Proliferation.POLICY.radius)+1.0,0),"health":100.0,"spawn":0.0}])
	var selected:Dictionary=Compiler.Proliferation.select_targets(origin,90,candidates,geometry.visible)
	assert(selected.ok and selected.target_ids==[1,2,3,4,5,6,7,8])
	var old:Dictionary=Canonical.new().snapshot()
	old.version=Canonical.Rules.V28_VERSION
	old.journey=Canonical.Journey.empty_legacy()
	var migrated:Dictionary=EmberMigration.migrate_v28(old)
	assert(not migrated.is_empty())
	var changed_fields:Array=[]
	for field:String in old:
		if old[field]!=migrated[field]:changed_fields.append(field)
	assert(changed_fields==["version"])
	var quote:Dictionary=Canonical.GemTrade.quote("buy","support:ember_proliferation")
	assert(quote.ok)
	return {"save_version":Compiler.Ember.SAVE_VERSION,"support_id":"ember_proliferation",
		"icon_file":"originals/ember_proliferation.png","player_policy":Compiler.Ember.POLICY,
		"proliferation_policy":Compiler.Proliferation.POLICY,"examples":examples,
		"incompatible_skills":incompatible,"mutually_exclusive_with":["ignite"],"exclusive_examples":exclusive,
		"transfer_example":{"started_at":started_at,"transferred_at":transferred_at,"source":source,
			"transfer":inherited,"recipient":recipient,"second_hop":second_hop,"at_expiry":expired},
		"selection_example":{"map_id":"broken_ruins","origin":origin,"source_id":90,"candidates":candidates,
			"target_ids":selected.target_ids,"wall_blocked_id":201,"spawn_protected_id":202,
			"dead_id":203,"outside_radius_id":204,"over_cap_ids":[9,10]},
		"migration_example":{"from_version":old.version,"to_version":migrated.version,"changed_fields":changed_fields,
			"items_before":old.items.size(),"items_after":migrated.items.size(),"granted_items":0},
		"merchant_quote":quote,"normal_reward_pool_includes_support":Canonical.Journey.GEM_DEFINITIONS.has("support:ember_proliferation"),
		"scope":"仅陨星直接命中与龙卷母子获准主命中；主命中防御前火焰分量只取一次基数，独立装备爆炸不继承",
		"transfer_rule":"已有余烬燃烧的目标死亡才扩散；继承同一原始每秒伤害与原绝对截止时间，按距离再按ID选最多8个存活可见目标，不穿墙、不选出生保护目标",
		"instant_kill_rule":"瞬杀且未形成燃烧状态不传；已有有效余烬燃烧的目标可在后续命中或燃烧致死时扩散",
		"stacking":"与点燃共用单目标最强燃烧：更强覆盖，同强替换并采用新条自己的截止时间，弱条忽略；扩散不叠加也不重置基础或压缩后的完整时长",
		"lifecycle":"不新增命中、暴击、偷取、随机抽样或奖励路径；暂停冻结，返城与重开清空，燃烧状态不存盘",
		"migration":"严格验证旧schema28与原字节备份后迁移schema29，仅版本字段变化，不赠物、不退款、不改旅程或既有UID"}


## Controlled source-stat examples use the production snapshot and compiler.
## Full legal routes below are validated separately and retain every other grant.
static func source_fire_dot_examples() -> Dictionary:
	var coverage: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v053-source/source-coverage.json"))
	assert(coverage.new_schema == 32 and coverage.source_sha256 == SourceTree.Data.SOURCE_SHA256)
	var nodes: Dictionary = {}
	for id: String in coverage.new_full_nodes:
		var node: Dictionary = SourceTree.Data.node(id)
		var current: Dictionary = SourceTree.node_effect(id, 0, 32)
		var old: Dictionary = SourceTree.node_effect(id, 0, 31)
		assert(current.status == "full" and old.status != "full")
		nodes[id] = {"name": node.name, "source_lines": node.stats, "fraction": coverage.new_full_nodes[id],
			"execution": current, "legacy_execution": old}
	var examples: Array = []
	for source_ids: Array in [["4713"], ["4713", "5916"]]:
		var fraction: float = 0.0
		for id: String in source_ids:
			for grant: Dictionary in nodes[id].execution.grants:
				if grant.stat == "fire_dot_multiplier_add": fraction += float(grant.value)
		for skill: String in ["meteor", "tornado"]:
			for support: String in ["ignite", "ember_proliferation"]:
				var base: Dictionary = Compiler.compile_group(skill, Recipes.snapshot({"damage":100.0}, []), [support])
				var zero: Dictionary = Compiler.compile_group(skill, Recipes.snapshot({"damage":100.0,"fire_dot_multiplier_add":0.0}, []), [support])
				var increased: Dictionary = Compiler.compile_group(skill, Recipes.snapshot({"damage":100.0,"fire_dot_multiplier_add":fraction}, []), [support])
				assert(base.ok and zero.ok and increased.ok and base == zero)
				examples.append({"source_nodes":source_ids,"fraction":fraction,"skill_id":skill,"support_id":support,
					"base":base,"explicit_zero":zero,"increased":increased,"details":Preview.details(increased)})
	var class_paths: Array = coverage.classes.duplicate(true)
	for entry: Dictionary in class_paths:
		for id: String in entry.paths_to_new_nodes:
			var path: Array = entry.paths_to_new_nodes[id]
			var candidate: Dictionary = _fire_dot_route_candidate(int(entry.class_id), path)
			assert(Canonical.Rules.reason(candidate).is_empty() and SourceTree.reason(candidate).is_empty())
			var old: Dictionary = candidate.duplicate(true)
			old.version = 31
			assert(not SourceTree.reason(old).is_empty())
		entry.legal_current_routes = true
		entry.legacy_routes_rejected = true
	var legal_examples: Array = []
	for choice: Dictionary in [{"class_id":1,"target":"2550"},{"class_id":3,"target":"11924"},{"class_id":5,"target":"29049"}]:
		var path: Array = class_paths[int(choice.class_id)].paths_to_new_nodes[choice.target]
		var candidate: Dictionary = _fire_dot_route_candidate(int(choice.class_id), path)
		var model := Canonical.new()
		model._accept_memory(candidate)
		var stats: Dictionary = model.get_stats()
		var compiled: Dictionary = Compiler.compile_group("meteor", Recipes.snapshot(stats, []), ["ignite"])
		assert(compiled.ok)
		legal_examples.append({"class_id":choice.class_id,"target":choice.target,"allocated":path,
			"points_spent":path.size()-1,"required_level":maxi(1,path.size()-5),"stats":stats,"cast":compiled})
	var scaled: Dictionary = Compiler.compile_group("meteor", Recipes.snapshot({"damage":100.0,"fire_dot_multiplier_add":0.10}, []), ["ember_proliferation"])
	var runtime := BurnRuntime.new()
	var applied: Dictionary = runtime.apply("monster",90,0,scaled.burn_profile.roles.direct.dps,scaled.burn_profile.duration,10.0,
		{"skill_id":"meteor","ember_generation":0,"ember_expiry":13.0})
	assert(applied.ok and applied.applied)
	var source: Dictionary = runtime.status_for("monster",90)
	var transfer: Dictionary = Compiler.Proliferation.transfer(source,11.75)
	assert(transfer.ok and not transfer.burn.is_empty())
	var received: Dictionary = runtime.apply("monster",1,90,transfer.burn.raw_dps,transfer.burn.duration,11.75,transfer.burn.provenance)
	assert(received.ok and received.applied)
	var shock_base: Dictionary = Compiler.compile_group("bolt",Recipes.snapshot({"damage":100.0},[]),["shock"])
	var shock_bonus: Dictionary = Compiler.compile_group("bolt",Recipes.snapshot({"damage":100.0,"fire_dot_multiplier_add":0.10},[]),["shock"])
	assert(shock_base.ok and shock_bonus.ok and shock_base.shock_profile == shock_bonus.shock_profile)
	var old_save: Dictionary = Canonical.new().snapshot()
	old_save.version = 31
	var migrated: Dictionary = FireDotMigration.migrate_v31(old_save,SourceTree.reason)
	assert(not migrated.is_empty())
	var changed_fields: Array = []
	for key: String in old_save:
		if old_save[key] != migrated[key]: changed_fields.append(key)
	assert(changed_fields == ["version"])
	return {"minimum_save_version":32,"stat":"fire_dot_multiplier_add","snapshot_field":"fire_dot_multiplier",
		"source_sha256":SourceTree.Data.SOURCE_SHA256,"nodes":nodes,"class_paths":class_paths,
		"examples":examples,"legal_build_examples":legal_examples,
		"new_complete_ordinary_nodes":coverage.new_full_nodes.keys(),"new_mastery_effect_ids":[],
		"newly_reachable_existing_node":"1550","older_legal_allocations_gaining_effects":coverage.older_legal_allocations_gaining_effects,
		"transfer_example":{"fraction":0.10,"started_at":10.0,"transferred_at":11.75,"source":source,"transfer":transfer,"recipient":runtime.status_for("monster",1)},
		"unchanged_consumers":{"shock_before":shock_base,"shock_after":shock_bonus,"enemy_burn":Compiler.Burn.from_fire_hit(7.0,Compiler.Burn.ENEMY_POLICY)},
		"migration_example":{"from_version":old_save.version,"to_version":migrated.version,"changed_fields":changed_fields,
			"items_before":old_save.items.size(),"items_after":migrated.items.size(),"talents_preserved":old_save.talents==migrated.talents},
		"formula":"燃烧每秒原始火伤 = 已结算的防御前主命中火分量 × 燃烧比例 × (1 + 火焰持续伤害加成之和)",
		"units":"源词句+4%与+6%相加为0.10；属性、施放快照与燃烧预览中的加成字段都保存0.10，最终伤害因子才是1.10",
		"snapshot_rule":"获准施放冻结一次加成；没有来源或显式零值时省略可选字段，保持旧编译数据结构与数值",
		"preview_rule":"燃烧预览各命中角色的每秒伤害与完整时长总量已经应用一次加成，显示层不得再次乘算",
		"scope":"只增强玩家点燃与余烬扩散的燃烧；直接命中、持续时长、魔力、冷却、感电与敌方燃烧不变；独立装备爆炸不继承",
		"transfer_rule":"余烬接收者直接继承已经增强的每秒伤害及原绝对截止时间，不重新读取来源或再次乘算",
		"coverage_note":"8个新增完整普通节点；七职业各自可达的非起点普通节点由676变685，其中额外1个是原本已完整的1550变得可达，不是第9个新机制",
		"complete_gate":"仍逐节点执行全部源效果；包含未实现附加效果、武器或条件限定的节点整体锁定，0个新增精通效果",
		"legacy_rule":"schema31及更早版本使用冻结旧执行词汇，合法旧档不可能含这8个节点；严格旧档验证后迁移schema32，仅改变版本，不赠物、不退款、不改UID与旧节点效果",
		"example_scope":"前后表只隔离所列节点的火焰持续伤害字段，其余输入固定；七职业路径另经真实构筑校验，三条完整合法路线示例保留沿途全部属性，可达集合不代表123点能全部同时分配",
		"unsupported":["通用持续伤害加成","攻击限定持续伤害","条件持续伤害","新的装备词缀池","新宝石"],"new_images":[]}


static func _fire_dot_route_candidate(class_id: int, path: Array) -> Dictionary:
	var candidate: Dictionary = Canonical.new().snapshot()
	candidate.progress.level = 119
	candidate.progress.xp = 0
	candidate.talents.class_id = class_id
	candidate.talents.allocated = path.duplicate()
	candidate.talents.normal_points = 123 - (path.size() - 1)
	return candidate


## v54 evidence comes from the real compiler and current whole-build validator.
## Export effective DPS/duration/total; the HTML never reapplies either fraction.
static func source_faster_burn_examples() -> Dictionary:
	var coverage: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v054-source/source-coverage.json"))
	assert(coverage.new_schema == 33 and coverage.source_sha256 == SourceTree.Data.SOURCE_SHA256)
	var nodes: Dictionary = {}
	var source_ids: Array = ["11364", "43684", "59766"]
	var faster: float = 0.0
	for id: String in source_ids:
		var node: Dictionary = SourceTree.Data.node(id)
		var current: Dictionary = SourceTree.node_effect(id, 0, 33)
		var old: Dictionary = SourceTree.node_effect(id, 0, 32)
		assert(current.status == "full" and old.status != "full")
		var fraction: float = 0.0
		for grant: Dictionary in current.grants:
			if grant.stat == "damaging_ailments_faster": fraction += float(grant.value)
		faster += fraction
		nodes[id] = {"name":node.name,"source_lines":node.stats,"fraction":fraction,"execution":current,"legacy_execution":old}
	assert(is_equal_approx(faster,0.25))
	var examples: Array = []
	for multiplier: float in [0.0,0.10]:
		for skill: String in ["meteor","tornado"]:
			for support: String in ["ignite","ember_proliferation"]:
				var base_stats: Dictionary = {"damage":100.0,"fire_dot_multiplier_add":multiplier}
				var zero_stats: Dictionary = base_stats.duplicate(true)
				zero_stats.damaging_ailments_faster = 0.0
				var after_stats: Dictionary = base_stats.duplicate(true)
				after_stats.damaging_ailments_faster = faster
				var base: Dictionary = Compiler.compile_group(skill,Recipes.snapshot(base_stats,[]),[support])
				var zero: Dictionary = Compiler.compile_group(skill,Recipes.snapshot(zero_stats,[]),[support])
				var after: Dictionary = Compiler.compile_group(skill,Recipes.snapshot(after_stats,[]),[support])
				assert(base.ok and zero.ok and after.ok and var_to_bytes(base) == var_to_bytes(zero))
				for role: String in after.burn_profile.roles:
					var prior: Dictionary = base.burn_profile.roles[role]
					var effective: Dictionary = after.burn_profile.roles[role]
					assert(absf(float(effective.total)-float(prior.total)) <= maxf(1.0e-9,1.0e-12*absf(float(prior.total))))
				examples.append({"source_nodes":source_ids,"fire_dot_multiplier":multiplier,"faster_fraction":faster,
					"skill_id":skill,"support_id":support,"base":base,"explicit_zero":zero,"faster":after,
					"zero_bytes_equal":var_to_bytes(base)==var_to_bytes(zero),"details":Preview.details(after)})
	var class_paths: Array = coverage.classes.duplicate(true)
	for entry: Dictionary in class_paths:
		for id: String in entry.paths_to_new_nodes:
			var candidate: Dictionary = _fire_dot_route_candidate(int(entry.class_id),entry.paths_to_new_nodes[id])
			assert(Canonical.Rules.reason(candidate).is_empty() and SourceTree.reason(candidate).is_empty())
			var old: Dictionary = candidate.duplicate(true)
			old.version = 32
			assert(not SourceTree.reason(old).is_empty())
		entry.legal_current_routes = true
		entry.legacy_routes_rejected = true
	var route: Array = class_paths[4].paths_to_new_nodes["59766"]
	for id: String in source_ids: assert(route.has(id))
	var candidate: Dictionary = _fire_dot_route_candidate(4,route)
	var model := Canonical.new()
	model._accept_memory(candidate)
	var stats: Dictionary = model.get_stats()
	assert(is_equal_approx(float(stats.damaging_ailments_faster),faster))
	var legal_cast: Dictionary = Compiler.compile_group("meteor",Recipes.snapshot(stats,[]),["ignite"])
	assert(legal_cast.ok)
	var scaled: Dictionary = Compiler.compile_group("meteor",Recipes.snapshot({"damage":100.0,"fire_dot_multiplier_add":0.10,"damaging_ailments_faster":faster},[]),["ember_proliferation"])
	var started_at: float = 10.0
	var transferred_at: float = 11.75
	var expiry: float = started_at + float(scaled.burn_profile.duration)
	var runtime := BurnRuntime.new()
	var applied: Dictionary = runtime.apply("monster",90,0,scaled.burn_profile.roles.direct.dps,scaled.burn_profile.duration,started_at,
		{"skill_id":"meteor","ember_generation":0,"ember_expiry":expiry})
	assert(applied.ok and applied.applied)
	var source: Dictionary = runtime.status_for("monster",90)
	var transfer: Dictionary = Compiler.Proliferation.transfer(source,transferred_at)
	assert(transfer.ok and not transfer.burn.is_empty())
	var received: Dictionary = runtime.apply("monster",1,90,transfer.burn.raw_dps,transfer.burn.duration,transferred_at,transfer.burn.provenance)
	assert(received.ok and received.applied)
	var after_expiry: Dictionary = Compiler.Proliferation.transfer(source,expiry)
	assert(after_expiry.ok and after_expiry.burn.is_empty())
	var shock_base: Dictionary = Compiler.compile_group("bolt",Recipes.snapshot({"damage":100.0,"fire_dot_multiplier_add":0.10},[]),["shock"])
	var shock_faster: Dictionary = Compiler.compile_group("bolt",Recipes.snapshot({"damage":100.0,"fire_dot_multiplier_add":0.10,"damaging_ailments_faster":faster},[]),["shock"])
	assert(shock_base.ok and shock_faster.ok and shock_base.shock_profile == shock_faster.shock_profile)
	var old_save: Dictionary = Canonical.new().snapshot()
	old_save.version = 32
	var migrated: Dictionary = FasterBurnMigrationData.migrate_v32(old_save,SourceTree.reason)
	assert(not migrated.is_empty())
	var changed_fields: Array = []
	for key: String in old_save:
		if old_save[key] != migrated[key]: changed_fields.append(key)
	assert(changed_fields == ["version"])
	var blocked: Dictionary = {}
	for id: String in ["48823","19686"]:
		var node: Dictionary = SourceTree.Data.node(id)
		blocked[id] = {"name":node.name,"source_lines":node.stats,"standard_graph":SourceTree.Data.standard_ids().has(id),
			"execution":SourceTree.node_effect(id,0,33),"legacy_execution":SourceTree.node_effect(id,0,32)}
	return {"minimum_save_version":33,"stat":"damaging_ailments_faster","snapshot_field":"burn_faster",
		"source_version":"3.29.1","source_sha256":SourceTree.Data.SOURCE_SHA256,"nodes":nodes,"class_paths":class_paths,
		"examples":examples,"legal_build_examples":[{"class_id":4,"target":"59766","allocated":route,"points_spent":route.size()-1,
			"required_level":maxi(1,route.size()-5),"stats":stats,"cast":legal_cast}],
		"new_complete_ordinary_nodes":source_ids,"newly_reachable_existing_nodes":[],"new_mastery_effect_ids":[],"mastery_occurrences":0,
		"blocked_matching_nodes":blocked,"older_legal_allocations_gaining_effects":coverage.older_legal_allocations_gaining_effects,
		"transfer_example":{"fire_dot_multiplier":0.10,"faster_fraction":faster,"started_at":started_at,"transferred_at":transferred_at,
			"profile":scaled.burn_profile,"source":source,"transfer":transfer,"recipient":runtime.status_for("monster",1),"at_expiry":after_expiry},
		"unchanged_consumers":{"shock_before":shock_base,"shock_after":shock_faster,"enemy_burn":Compiler.Burn.from_fire_hit(7.0,Compiler.Burn.ENEMY_POLICY)},
		"migration_example":{"from_version":old_save.version,"to_version":migrated.version,"changed_fields":changed_fields,
			"items_before":old_save.items.size(),"items_after":migrated.items.size(),"talents_preserved":old_save.talents==migrated.talents},
		"formula":"先按既有火焰持续伤害加成M结算燃烧每秒伤害，再乘(1 + 更快伤害异常之和F)；最终时长 = 基础3秒 / (1 + F)",
		"units":"5% + 5% + 15%相加为F=0.25，最终每秒因子为1.25；M=0.10仍独立使用1.10因子，F不作逐节点连乘",
		"total_rule":"更快只压缩交付时间，原始完整时长总量理论不变；不代表实际战斗DPS或击杀伤害必然增加。总量允许浮点误差max(1e-9,1e-12×旧总量绝对值)",
		"snapshot_rule":"初始获准施放冻结snapshot.burn_faster；退款或换装不重算飞行中、延迟中与已经存在的燃烧",
		"preview_rule":"燃烧profile.burn_faster保存F，非零时base_duration保存基础3秒，duration保存压缩时长；roles的dps与total已经生效，显示层不得再次乘算",
		"zero_rule":"无来源与显式F=0均省略新增快照和预览键；即使已有非零火焰持续伤害加成，旧编译字节结构仍保持",
		"scope":"当前仅玩家点燃与余烬扩散燃烧消费该源属性；直接命中、魔力、冷却、感电和敌方燃烧保持；尚未实现流血、中毒或完整伤害异常体系",
		"transfer_rule":"余烬直接继承已计算的每秒伤害与压缩后的原绝对截止时间；不重读天赋、不再次乘F、不重置基础或完整压缩时长",
		"coverage_note":"仅3个新增完整标准普通节点，七职业各自非起点普通节点可达数685→688；没有其他新增可达节点或精通",
		"complete_gate":"48823 Deadly Draw仍含未实现的弓技能持续伤害；非标准19686 Wasting Affliction仍含未实现的异常伤害提高，两者保持partial、不可分配",
		"legacy_rule":"schema32及更早版本保持冻结词汇；严格验证旧32后迁移33，仅版本字段改变，不赠物、不退款、不改旧节点或UID",
		"example_scope":"八组比较隔离F，M分别取0与0.10，使用真实编译器的陨星直接角色与龙卷母子角色；完整三节点支路另保留沿途全部属性，21条职业路线均经实际完整构筑验证",
		"unsupported":["流血","中毒","通用异常伤害提高","弓技能限定持续伤害","新装备词缀池","新宝石"],"new_images":[]}


## v58 resource examples execute production rules; Python only formats these values.
## Route candidates are validated whole builds, not interactive allocation evidence.
## Short, read-only v59 examples use the production profile and existing source witness.
## No duplicate parser, inferred support labels, persistence or gameplay replay.
static func elemental_resistance_cap_examples() -> Dictionary:
	var expected: Array = ["15522", "24133", "25989", "34917", "42009", "45341", "48929", "50029", "5065", "53118", "60031", "6043"]
	var opened: Array = []
	var nodes: Dictionary = {}
	for id: String in SourceTree.Data.standard_ids():
		if SourceTree.node_effect(id, 0, 35).status != "full" and SourceTree.node_effect(id, 0, 36).status == "full": opened.append(id)
	opened.sort()
	assert(opened == expected) # Historical v59 opening window is fixed at35→36.
	var boundaries: Dictionary = {}
	for id: String in expected + ["11820", "20832", "40743", "38683", "42313", "44203", "48803", "54766"]:
		var raw: Dictionary = SourceTree.Data.node(id)
		var choices: Array = []
		for choice: Dictionary in raw.mastery_effects:
			choices.append({"effect":int(choice.effect), "source_lines":choice.stats, "execution":SourceTree.node_effect(id, int(choice.effect))})
		var entry: Dictionary = {"name":raw.name, "source_lines":raw.stats, "execution":SourceTree.node_effect(id),
			"legacy_execution":SourceTree.node_effect(id, 0, 35), "standard_graph":SourceTree.Data.standard_ids().has(id), "mastery_choices":choices}
		if expected.has(id): nodes[id] = entry
		else: boundaries[id] = entry
	var mastery_boundaries: Dictionary = {}
	for id: String in SourceTree.Data.nodes():
		for choice: Dictionary in SourceTree.Data.node(id).mastery_effects:
			if int(choice.effect) not in [34383, 7137, 61283, 1727]: continue
			var key: String = str(int(choice.effect))
			if not mastery_boundaries.has(key):
				mastery_boundaries[key] = {"effect":int(choice.effect), "source_lines":choice.stats,
					"execution":SourceTree.node_effect(id, int(choice.effect)), "host_nodes":[]}
			mastery_boundaries[key].host_nodes.append(id)
	assert(mastery_boundaries.size() == 4)
	var cases: Dictionary = {}
	for spec: Dictionary in [{"id":"default_75", "raw":1.0, "bonus":0.0}, {"id":"raw_40_cap_83", "raw":0.4, "bonus":0.08},
		{"id":"raw_75_cap_83", "raw":0.75, "bonus":0.08}, {"id":"raw_83_cap_83", "raw":0.83, "bonus":0.08},
		{"id":"raw_100_cap_83", "raw":1.0, "bonus":0.08}, {"id":"safety_ceiling", "raw":1.0, "bonus":0.25}]:
		var stats: Dictionary = {}
		for element: String in Defense.ELEMENTS:
			stats[element + "_resistance"] = spec.raw
			stats["maximum_" + element + "_resistance_add"] = spec.bonus
		var profile: Dictionary = Defense.resistance_profile(stats)
		var hits: Dictionary = {}
		for element: String in Defense.ELEMENTS:
			hits[element] = Defense.incoming_source_hit({element:100.0}, stats, 0.0, 200.0)
			assert(hits[element].ok)
		var burn: Dictionary = Defense.incoming_burn(100.0, spec.raw, 0.0, 200.0, "player", 0.0, 0.0, spec.bonus)
		assert(profile.ok and burn.ok and is_equal_approx(burn.damage_total, hits.fire.damage_total))
		cases[spec.id] = {"stats":stats, "profile":profile, "hits":hits, "fire_burn":burn}
	var witness_path: String = "res://docs/qa/v059-source/allocation-witness.json"
	var witness: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(witness_path))
	var candidate: Dictionary = Canonical.new().snapshot()
	candidate.progress = {"level":int(witness.level), "xp":0}
	candidate.talents.class_id = int(witness.class_id)
	candidate.talents.allocated = witness.allocated.duplicate()
	candidate.talents.masteries = {}
	candidate.talents.normal_points = int(witness.level) + 4 - int(witness.spent)
	assert(Canonical.Rules.reason(candidate).is_empty() and SourceTree.reason(candidate).is_empty())
	var model := Canonical.new()
	model._accept_memory(candidate)
	var live: Dictionary = model.get_resistance_profile()
	assert(live.ok and model.save_attempts == 0)
	for element: String in Defense.ELEMENTS:
		assert(is_equal_approx(live.raw_resistances[element], float(witness.expected_raw[element])))
		assert(is_equal_approx(live.maximum_resistances[element], 0.83) and is_equal_approx(live.effective_resistances[element], 0.83))
	var base: Dictionary = Equipment.base_definition("emberhide_vest")
	var affix: Dictionary = Equipment.affix_definition("emberward")
	var equipment: Dictionary = {"base_id":"emberhide_vest", "affix_id":"emberward", "base_raw_fire":base.stats.fire_resistance,
		"affix_max_raw_fire":float(affix.tiers[-1].max) / 100.0, "equipment_cold_sources":[], "equipment_lightning_sources":[]}
	equipment.maximum_raw_fire = equipment.base_raw_fire + equipment.affix_max_raw_fire
	for id: String in Equipment.all_base_ids():
		var stats: Dictionary = Equipment.base_definition(id).stats
		assert(not stats.has("cold_resistance") and not stats.has("lightning_resistance"))
	for id: String in Equipment.all_affix_ids():
		var stat: String = Equipment.affix_definition(id).stat
		if stat == "cold_resistance": equipment.equipment_cold_sources.append(id)
		if stat == "lightning_resistance": equipment.equipment_lightning_sources.append(id)
	return {"minimum_save_version":36, "source_policy":SourceTree.CURRENT_SAVE_VERSION, "source_version":"3.29.1", "source_sha256":SourceTree.Data.SOURCE_SHA256,
		"base_cap":Defense.FIRE_RESISTANCE_CAP, "safety_cap":Defense.ELEMENTAL_RESISTANCE_SAFETY_CAP,
		"nodes":nodes, "new_complete_ordinary_nodes":opened, "boundaries":boundaries, "mastery_boundaries":mastery_boundaries, "examples":cases,
		"default_profile":Canonical.new().get_resistance_profile(), "equipment":equipment,
		"reachable_build":{"class_id":int(witness.class_id), "level":int(witness.level), "points_spent":int(witness.spent), "allocated":witness.allocated,
			"stats":model.get_stats(), "profile":live, "whole_build_valid":true, "save_attempts":model.save_attempts, "witness_path":witness_path},
		"new_images":[], "producer":"SourceTree.current36 → CanonicalGameState.get_resistance_profile → Defense.resistance_profile / incoming_source_hit / incoming_burn",
		"formula":"当前上限 = min(83%, 75% + 对应最大抗性加成)；有效抗性 = clamp(原始抗性, 0%, 当前上限)",
		"source_reminder":"源资料90%提醒原样保留；本游戏安全上限为83%，不采用90%预算",
		"timing":"最大抗性是结算时的当前防御；换装、分配和退款只影响后续命中与燃烧，不冻结到攻击者施放快照，不改已算伤害或燃烧原始每秒伤害",
		"scope":"只接入无条件最大火、冰、电抗性；全元素句展开三字段，每ID一次。寻枝珠宝只影响连接准入，不重复授予属性",
		"route_scope":"野蛮人69级73点的普通连通可行见证，保留沿途全部属性，无写档；不是全局最省点或完整配装最优结论",
		"migration":"schema36先严格校验旧35，原文件逐字节备份后只迁版本；不赠点、不赠物，旧35注入新完整节点仍拒绝"}


# Offline reward probe: only presentation is stubbed; the production reward method
# selects the current pool and computes ilvl. No scene, save, or user file is used.
class ReferenceRewardHud extends CanvasLayer:
	func notify(_message: String) -> void: pass


static func _elemental_vest_example(ids: Array) -> Dictionary:
	var model := Canonical.new()
	var candidate: Dictionary = model.snapshot()
	var previous_body: String = str(model.equipped_items().get("body_armour", ""))
	if not previous_body.is_empty():
		candidate.locations[previous_body] = model.first_bag_position(previous_body)
	var uid: String = "gear_%06d" % int(candidate.next_item_serial)
	var instance: Dictionary = {"id":uid, "base_id":"emberhide_vest", "rarity":"normal" if ids.is_empty() else "rare", "item_level":16, "affixes":[]}
	for id: String in ids:
		var tier: Dictionary = Equipment.affix_definition(id).tiers[-1]
		instance.affixes.append({"id":id, "tier":int(tier.tier), "value":int(tier.max)})
	assert(Equipment.validate_instance(instance))
	candidate.items[uid] = Canonical.Items.wrap_equipment(instance)
	candidate.locations[uid] = {"kind":"equipment", "slot_id":"body_armour"}
	candidate.next_item_serial += 1
	assert(Canonical.Rules.reason(candidate).is_empty())
	model._accept_memory(candidate)
	var stats: Dictionary = model.get_stats()
	var profile: Dictionary = model.get_resistance_profile()
	var hits: Dictionary = {}
	var gaps: Dictionary = {"default_75":{}, "safety_83":{}}
	for element: String in Defense.ELEMENTS:
		hits[element] = Defense.incoming_source_hit({element:100.0}, stats, 0.0, 200.0)
		assert(hits[element].ok)
		gaps.default_75[element] = maxf(0.0, Defense.FIRE_RESISTANCE_CAP - profile.raw_resistances[element])
		gaps.safety_83[element] = maxf(0.0, Defense.ELEMENTAL_RESISTANCE_SAFETY_CAP - profile.raw_resistances[element])
	assert(profile.ok and model.save_attempts == 0)
	return {"instance":instance, "definition":Equipment.definition(instance), "stats":stats, "profile":profile,
		"hits":hits, "additional_raw_required":gaps, "whole_build_valid":true, "save_attempts":model.save_attempts}


static func elemental_defense_affix_examples() -> Dictionary:
	var new_ids: Array = Equipment.ElementalDefense.AFFIX_IDS.duplicate()
	var families: Dictionary = {}
	for id: String in new_ids:
		var family: Dictionary = Equipment.affix_definition(id)
		assert(Equipment.ElementalDefense.valid_family(family))
		families[id] = family
	var examples: Dictionary = {
		"white_base":_elemental_vest_example([]),
		"six_max":_elemental_vest_example(["rootwell", "deepwell", "lanternveil", "emberward", "rimeward", "stormward"]),
		"mana_recovery":_elemental_vest_example(["rootwell", "deepwell", "lanternveil", "wellturn", "rimeward", "stormward"])}
	var full: Dictionary = examples.six_max
	assert(full.definition.stats.max_health == 40.0 and full.definition.stats.max_mana == 22.0 and full.definition.stats.max_shield == 22.0)
	assert(is_equal_approx(full.profile.raw_resistances.fire, 0.4) and is_equal_approx(full.profile.raw_resistances.cold, 0.25) and is_equal_approx(full.profile.raw_resistances.lightning, 0.25))
	var pool: Dictionary = Equipment.pool_profiles()[Equipment.CURRENT_DEFENSE_POOL_ID]
	var boundaries: Dictionary = {}
	for level: int in [1, 7, 8, 15, 16, 30]:
		var accepted: Dictionary = {}
		for id: String in new_ids: accepted[id] = []
		for entry: Dictionary in Equipment._profile_eligible_tiers("emberhide_vest", level, "suffix", pool):
			if accepted.has(entry.id): accepted[entry.id].append(entry.tier)
		boundaries[str(level)] = accepted
	var maps: Dictionary = {}
	for map_id: String in Canonical.Journey.MAP_IDS:
		var compiled: Dictionary = MapRules.compile_normal(map_id, 3, [], [])
		assert(compiled.ok)
		var arena := Arena.new()
		arena.state = Canonical.new()
		arena.hud = ReferenceRewardHud.new()
		arena.wave = int(compiled.profile.wave)
		arena.rng.seed = 600037
		var before: Dictionary = arena.state.snapshot()
		var uid: String = "gear_%06d" % int(before.next_item_serial)
		arena._award_kill_equipment({"rarity":"rare", "equipment_pool":"defense"})
		var awarded: Dictionary = arena.state.item(uid).payload
		assert(not awarded.is_empty() and arena.state.save_attempts == 0)
		var tiers: Array = []
		for entry: Dictionary in Equipment._profile_eligible_tiers("emberhide_vest", int(awarded.item_level), "suffix", pool):
			if entry.id == new_ids[0]: tiers.append(entry.tier)
		maps[map_id] = {"map_profile":compiled.profile, "item_level":awarded.item_level, "eligible_tiers":tiers,
			"sample":awarded, "save_attempts":arena.state.save_attempts, "producer":"Main._award_kill_equipment → Canonical.award_equipment"}
		arena.hud.free()
		arena.free()
	var targeted: Array = []
	for id: String in Craft.Targeted.TARGETS.targeted_reforge_damage.families:
		if Equipment.family_eligible(id, "emberhide_vest"):
			var family: Dictionary = Equipment.affix_definition(id)
			targeted.append({"id":id, "kind":family.kind, "group":family.group})
	assert(not targeted.is_empty())
	for family: Dictionary in targeted: assert(family.kind == "suffix")
	var reforge: Dictionary = {}
	for seed_value: int in range(1, 4097):
		var planned: Dictionary = Craft.operation_plan(full.instance, "reforge", seed_value, Equipment.ElementalDefense.MIN_SAVE_VERSION)
		assert(planned.ok)
		var ids: Array = []
		for affix: Dictionary in planned.instance.affixes: ids.append(affix.id)
		if ids.has("emberward") and ids.has("rimeward") and ids.has("stormward"):
			reforge = {"seed":seed_value, "plan":planned}
			break
	assert(not reforge.is_empty(), "Bounded ordinary reforge witness must contain all three resistance suffixes")
	var offer: Dictionary = Town.offer("base:emberhide_vest")
	var supplied: Dictionary = Town.make_item(offer, 1)
	assert(supplied.payload.rarity == "normal" and supplied.payload.affixes.is_empty())
	return {"minimum_save_version":Equipment.ElementalDefense.MIN_SAVE_VERSION, "vocabulary":Equipment.CURRENT_VOCABULARY,
		"source_policy":SourceTree.CURRENT_SAVE_VERSION, "base_id":"emberhide_vest", "new_families":families,
		"authored_vocabulary":Equipment.ElementalDefense.MIN_SAVE_VERSION, "authored_pool_id":"defense_v37", "reforge_vocabulary":Equipment.ElementalDefense.MIN_SAVE_VERSION,
		"pool_id":Equipment.CURRENT_DEFENSE_POOL_ID, "pool":pool, "loot_profile_id":Equipment.CURRENT_LOOT_PROFILE_ID,
		"loot_profile":Equipment.loot_profile(Equipment.CURRENT_LOOT_PROFILE_ID), "rarities":Equipment.RARITIES.duplicate(true),
		"slot_targets":EquipmentSlotsData.targets_for_category("body_armour"), "examples":examples,
		"tier_boundaries":boundaries, "formal_map_tier_iii":maps, "test_supply":{"offer":offer, "instance":supplied},
		"damage_target_families":targeted, "ordinary_reforge_witness":reforge,
		"producer":"EquipmentCatalog → canonical validated in-memory equipment location → Canonical.get_resistance_profile → Defense.incoming_source_hit",
		"budget_scope":"单件胸甲合法六词顶值演算；不是掉落保证、免费成装、全局最优或完整构筑平衡结论",
		"tradeoff":"三抗占满三个后缀，放弃元素增伤、魔力恢复与移速；伤害定向重铸保证一个真实伤害后缀，不能同时保留三抗",
		"supply_scope":"自然新池只替换10%防御入口；新自然分布及后续随机状态有意改变，显式旧pool/profile仍保留历史结果",
		"migration":"schema37严格校验旧36并保留原字节备份后仅迁版本；旧装备不自动重掷、补词或换UID，天赋源政策仍36",
		"new_images":[]}


static func _rating_vest_model(affixes: Array, class_id: int = 0) -> Dictionary:
	var model := Canonical.new()
	var candidate: Dictionary = model.snapshot()
	candidate.talents.class_id = class_id
	candidate.talents.allocated = [SourceTree.Data.start_for_class(class_id)]
	var previous_body: String = str(model.equipped_items().get("body_armour", ""))
	if not previous_body.is_empty(): candidate.locations[previous_body] = model.first_bag_position(previous_body)
	var uid: String = "gear_%06d" % int(candidate.next_item_serial)
	var instance: Dictionary = {"id":uid, "base_id":"emberhide_vest", "rarity":"normal" if affixes.is_empty() else ("magic" if affixes.size() == 1 else "rare"), "item_level":16, "affixes":affixes.duplicate(true)}
	assert(Equipment.validate_instance(instance))
	candidate.items[uid] = Canonical.Items.wrap_equipment(instance)
	candidate.locations[uid] = {"kind":"equipment", "slot_id":"body_armour"}
	candidate.next_item_serial += 1
	assert(Canonical.Rules.reason(candidate).is_empty())
	model._accept_memory(candidate)
	var stats: Dictionary = model.get_stats()
	assert(model.save_attempts == 0)
	return {"instance":instance, "definition":Equipment.definition(instance), "stats":stats,
		"class_id":class_id, "whole_build_valid":true, "save_attempts":model.save_attempts}


static func _rating_catalog_attack(map_id: String, tier: int, boss: bool, armour: float) -> Dictionary:
	var compiled: Dictionary = MapRules.compile_normal(map_id, tier, [], [])
	assert(compiled.ok)
	var species: String = "rift_warden" if boss else "crawler"
	var enemy: Dictionary = Monsters.make_enemy(620001, species, int(compiled.profile.wave), Vector2.ZERO,
		"map_boss" if boss else "ordinary", "boss" if boss else "normal", Monsters.TEMPLATES[species].mechanisms.duplicate() if boss else [])
	var applied: Dictionary = EncounterCompiler.apply_to_enemy(enemy, EncounterCompiler.compile(["enemy_damage_115"] if boss else []).profile)
	assert(applied.ok)
	enemy = applied.enemy
	if boss: enemy.map_boss_attack_id = Maps.MAPS[map_id].boss_attack_id
	var components: Dictionary = Monsters.contact_components(enemy)
	var policy: Dictionary = Monsters.telegraph_policy(enemy)
	if not policy.is_empty():
		for type: String in components: components[type] *= float(policy.profile.damage_multiplier)
		if policy.has("burn_policy"): components.fire *= float(policy.burn_policy.upfront_fire_multiplier)
	var before: Dictionary = Defense.incoming_source_hit(components, {"armour":0.0}, 0.0, 100000.0)
	var after: Dictionary = Defense.incoming_source_hit(components, {"armour":armour}, 0.0, 100000.0)
	assert(before.ok and after.ok)
	return {"map_id":map_id, "tier":tier, "wave":compiled.profile.wave, "species":species,
		"damage_modifier":boss, "attack_id":str(enemy.get("map_boss_attack_id", "contact")), "components":components,
		"armour":armour, "before":before, "after":after, "accuracy":AttackRules.monster_profile(int(enemy.kind)).accuracy}


static func defense_rating_affix_examples() -> Dictionary:
	var families: Dictionary = {}
	var boundaries: Dictionary = {}
	var pool: Dictionary = Equipment.pool_profiles()[Equipment.CURRENT_DEFENSE_POOL_ID]
	var prefixes: Array = []
	for id: String in pool.affix_ids:
		if Equipment.affix_definition(id).kind == "prefix": prefixes.append(id)
	assert(prefixes.size() == 5)
	for id: String in Equipment.DefenseRatings.AFFIX_IDS:
		families[id] = Equipment.affix_definition(id)
		assert(Equipment.DefenseRatings.valid_family(families[id]))
	for level: int in [1, 7, 8, 15, 16, 30]:
		var available: Dictionary = {"ironhide":[], "mistweave":[]}
		for entry: Dictionary in Equipment._profile_eligible_tiers("emberhide_vest", level, "prefix", pool):
			if available.has(entry.id): available[entry.id].append(entry.tier)
		boundaries[str(level)] = available
	var examples: Dictionary = {"white_base":_rating_vest_model([])}
	for resource: String in ["rootwell", "deepwell", "lanternveil"]:
		var entries: Array = []
		for id: String in ["ironhide", "mistweave", resource, "emberward", "rimeward", "stormward"]:
			var tier: Dictionary = Equipment.affix_definition(id).tiers[-1]
			entries.append({"id":id, "tier":int(tier.tier), "value":int(tier.max)})
		examples[resource] = _rating_vest_model(entries)
	var evasion_rows: Array = []
	var accuracy: float = float(AttackRules.monster_profile(0).accuracy)
	for class_id: int in range(7):
		var baseline: Dictionary = _rating_vest_model([], class_id)
		for tier: Dictionary in families.mistweave.tiers:
			for bound: String in ["min", "max"]:
				var rating: int = int(tier[bound])
				var example: Dictionary = _rating_vest_model([{"id":"mistweave", "tier":int(tier.tier), "value":rating}], class_id)
				var admission: Dictionary = AttackRules.resolve(accuracy, float(example.stats.evasion))
				assert(admission.ok)
				evasion_rows.append({"class_id":class_id, "tier":tier.tier, "bound":bound, "flat_item_evasion":rating,
					"base_dexterity":example.stats.dexterity, "baseline_evasion":baseline.stats.evasion,
					"baseline_hit_chance":AttackRules.chance(accuracy, float(baseline.stats.evasion)),
					"effective_evasion":example.stats.evasion, "enemy_accuracy":accuracy, "hit_chance":admission.chance,
					"whole_build_valid":example.whole_build_valid, "save_attempts":example.save_attempts})
	var armour: float = float(examples.rootwell.stats.armour)
	var attacks: Array = [_rating_catalog_attack("old_garden", 1, false, armour)]
	for map_id: String in Canonical.Journey.MAP_IDS: attacks.append(_rating_catalog_attack(map_id, 3, true, armour))
	var scope_hits: Dictionary = {}
	for type: String in Damage.TYPES:
		var before: Dictionary = Defense.incoming_source_hit({type:100.0}, {"armour":0.0}, 0.0, 1000.0)
		var after: Dictionary = Defense.incoming_source_hit({type:100.0}, {"armour":armour}, 0.0, 1000.0)
		assert(before.ok and after.ok)
		if type != "physical": assert(is_equal_approx(before.damage_total, after.damage_total))
		scope_hits[type] = {"before":before, "after":after}
	return {"minimum_save_version":Equipment.DefenseRatings.MIN_SAVE_VERSION, "vocabulary":Equipment.CURRENT_VOCABULARY,
		"source_policy":SourceTree.CURRENT_SAVE_VERSION, "base_id":"emberhide_vest", "new_families":families,
		"pool_id":Equipment.CURRENT_DEFENSE_POOL_ID, "pool":pool, "loot_profile_id":Equipment.CURRENT_LOOT_PROFILE_ID,
		"loot_profile":Equipment.loot_profile(Equipment.CURRENT_LOOT_PROFILE_ID), "prefix_families":prefixes, "rarities":Equipment.RARITIES.duplicate(true),
		"tier_boundaries":boundaries, "examples":examples, "evasion_rows":evasion_rows, "catalog_attacks":attacks, "scope_hits":scope_hits,
		"burn_example":Defense.incoming_burn(100.0, 0.0, 0.0, 1000.0), "new_images":[],
		"producer":"EquipmentCatalog → validated Canonical.get_stats → SourceTree.apply_stats → AttackHitRules / DefenseRules",
		"rating_order":"装备与珠宝、源天赋固定值先加到角色原始基数，再由源天赋执行器统一提高一次；护甲不是本地防具倍率，闪避还读取合计敏捷",
		"tradeoff":"五个前缀族争三个名额。双防御配生命会放弃魔力、护盾前缀；改配魔力或护盾则放弃生命前缀。三抗仍占满后缀，与伤害、魔力恢复和移速竞争",
		"scope":"护甲只降低物理命中；闪避只决定attack命中准入，物理与元素攻击均可躲避。非attack命中与持续燃烧不读闪避；已有燃烧不会因提高双防御而消失",
		"budget_scope":"实际目录单次命中与七职业最终统计的隔离比较；不包含攻击频率、走位、抗性、护盾或魔力分担，不是实战DPS或平均存活提升",
		"accuracy_scope":"当前自然怪accuracy为100，等级波次、稀有度与地图增伤不提高accuracy；不推断未来怪物曲线",
		"migration":"schema39严格验证旧38并原字节备份，只升级版本；旧物品、UID、点数、货币与旅程保持，不补词或重掷。源政策仍38，schema37/38映射旧装备词汇37",
		"legacy_scope":"新canonical_v39只替换原10%防御入口；其余六分池权重与顺序保持。显式旧defense、defense_v37、canonical_v37及设备词汇1–38保留历史输出、拒绝语义与随机状态"}


## v64: actual legal equipment and complete canonical candidates, no user saves.
static func _iron_reflexes_model(route: Array, affix_ids: Array, level: int, enabled: bool) -> Dictionary:
	var model := Canonical.new()
	var candidate: Dictionary = model.snapshot()
	var previous: String = str(model.equipped_items().get("body_armour", ""))
	if not previous.is_empty(): candidate.locations[previous] = model.first_bag_position(previous)
	var uid: String = "gear_%06d" % int(candidate.next_item_serial)
	var affixes: Array = []
	for id: String in affix_ids:
		var tier: Dictionary = Equipment.affix_definition(id).tiers[-1]
		affixes.append({"id":id, "tier":int(tier.tier), "value":int(tier.max)})
	var instance: Dictionary = {"id":uid, "base_id":"emberhide_vest", "rarity":"rare", "item_level":16, "affixes":affixes}
	assert(Equipment.validate_instance(instance))
	candidate.items[uid] = Canonical.Items.wrap_equipment(instance)
	candidate.locations[uid] = {"kind":"equipment", "slot_id":"body_armour"}
	candidate.next_item_serial += 1
	candidate.progress = {"level":level, "xp":0}
	candidate.talents.class_id = 4
	candidate.talents.allocated = route.duplicate()
	if enabled: candidate.talents.allocated.append("10661")
	candidate.talents.normal_points = level + 5 - candidate.talents.allocated.size()
	assert(Canonical.Rules.reason(candidate).is_empty() and SourceTree.reason(candidate).is_empty())
	model._accept_memory(candidate)
	var stats: Dictionary = model.get_stats()
	var profile: Dictionary = model.get_defense_conversion_profile()
	assert(profile.enabled == enabled and model.save_attempts == 0)
	var hits: Dictionary = {}
	for amount: float in [20.0, 100.0, 500.0]:
		hits[str(int(amount))] = Defense.incoming_source_hit({"physical":amount}, stats, 0.0, 10000.0)
	var elements: Dictionary = {}
	for type: String in ["fire", "cold", "lightning"]:
		elements[type] = Defense.incoming_source_hit({type:100.0}, stats, 0.0, 10000.0)
	return {"instance":instance, "definition":Equipment.definition(instance), "class_id":4, "level":level,
		"allocated":candidate.talents.allocated, "points_spent":candidate.talents.allocated.size()-1,
		"points_remaining":candidate.talents.normal_points, "stats":stats, "profile":profile,
		"shared_increased":SourceTree._shared_defense_increased(candidate), "physical_hits":hits, "elemental_hits":elements,
		"burn":Defense.incoming_burn(100.0, float(stats.fire_resistance), 0.0, 10000.0),
		"enemy_accuracy":float(AttackRules.monster_profile(0).accuracy),
		"enemy_hit_chance":AttackRules.chance(float(AttackRules.monster_profile(0).accuracy), float(stats.evasion)),
		"whole_build_valid":true, "save_attempts":model.save_attempts}


static func iron_reflexes_examples() -> Dictionary:
	var route: Array = ["50986", "39725", "63649", "49806", "6580", "19711", "20010", "23471", "5237", "6363", "29937", "8544"]
	var branch: Array = ["24377", "35568"]
	var dual: Array = ["ironhide", "mistweave", "rootwell", "emberward", "rimeward", "stormward"]
	var legacy: Array = ["rootwell", "emberward", "rimeward", "stormward"]
	var examples: Dictionary = {}
	for spec: Dictionary in [
		{"id":"dual_ratings", "route":route, "affixes":dual, "level":8},
		{"id":"dual_ratings_hybrid", "route":route+branch, "affixes":dual, "level":10},
		{"id":"resources_hybrid", "route":route+branch, "affixes":legacy, "level":10}]:
		var before: Dictionary = _iron_reflexes_model(spec.route, spec.affixes, spec.level, false)
		var after: Dictionary = _iron_reflexes_model(spec.route, spec.affixes, spec.level, true)
		assert(before.instance == after.instance and before.stats.accuracy == after.stats.accuracy)
		for type: String in before.elemental_hits:
			assert(before.elemental_hits[type].damage_total == after.elemental_hits[type].damage_total)
		assert(before.burn.damage_total == after.burn.damage_total)
		var base_armour: float = float(before.definition.stats.get("armour", 0.0))
		var base_evasion: float = 15.0 + float(before.definition.stats.get("evasion", 0.0))
		var ia: float = float(before.stats.armour_increased)
		var ie: float = float(before.stats.evasion_increased)
		var shared: float = float(after.shared_increased)
		assert(is_equal_approx(before.stats.armour, base_armour*(1.0+ia)))
		assert(is_equal_approx(before.stats.evasion, base_evasion*(1.0+ie+floorf(before.stats.dexterity/5.0)*0.01)))
		assert(is_equal_approx(after.profile.armour, base_armour*(1.0+ia)+base_evasion*(1.0+ia+ie-shared)))
		examples[spec.id] = {"before":before, "after":after,
			"inputs":{"base_armour":base_armour, "base_evasion":base_evasion, "armour_increased":ia, "evasion_increased":ie, "shared_increased":shared}}
	var node: Dictionary = SourceTree.Data.node("10661")
	var effect: Dictionary = SourceTree.node_effect("10661", 0, 40)
	var old: Dictionary = SourceTree.node_effect("10661", 0, 39)
	assert(effect.status == "full" and old.status == "unsupported")
	return {"minimum_save_version":SourceTree.IRON_REFLEXES_SAVE_VERSION, "source_policy":SourceTree.CURRENT_SAVE_VERSION,
		"equipment_vocabulary":Equipment.CURRENT_VOCABULARY, "source_version":"3.29.1", "source_sha256":SourceTree.Data.SOURCE_SHA256,
		"node":{"id":"10661", "name":node.name, "source_lines":node.stats, "execution":effect, "legacy_execution":old},
		"formula":"A0 × (1 + IA) + E0 × (1 + IA + IE − H)", "evasion":0.0,
		"hybrid_source":{"id":"35568", "source_lines":SourceTree.Data.node("35568").stats, "execution":SourceTree.node_effect("35568")},
		"route":route+["10661"], "hybrid_branch":branch, "examples":examples, "disabled_profile":Canonical.new().get_defense_conversion_profile(),
		"new_images":[], "producer":"EquipmentCatalog → validated CanonicalGameState.get_stats/get_defense_conversion_profile → AttackHitRules / DefenseRules",
		"base_scope":"A0、E0合计角色原始基础、已装备物品、珠宝与天赋固定值；本组实际装备和路线只有胸甲提供护甲/闪避固定值，角色基础闪避为15",
		"shared_rule":"H只扣除同一原始词句同时提供护甲与闪避提高的部分；不同原句的两个提高即使数值相同也分别生效，不能按两总量较小值去重",
		"dexterity_rule":"取消敏捷对闪避的提高；敏捷仍每点提供2命中，保留后续命中提高。最终闪避为0，沿既有攻击命中规则判定",
		"scope":"护甲只降低物理命中；元素命中与已存在的燃烧不会因转换护甲而减伤。开启后失去闪避，不能把护甲增幅当成总体生存提升",
		"example_scope":"同一合法决斗者逐行比较最后1点，完整保留沿途属性与其余默认装备。稀有胸甲为真实合法4或6词缀；既有双防御前缀仍与生命、魔力、护盾争三个前缀位，不新增物品或词族",
		"budget_scope":"生产Model导出的静态装备/天赋与单次命中预算；命中示例设当前护盾0、生命10000，不包含频率、走位或实战存活时长",
		"resource_rule":"点选、退款、换装只重算派生数值，不补当前生命、护盾、魔力，也不重置命中熵；C页转换贡献已计入最终护甲，不再相加",
		"migration":"schema40严格校验旧39并保留原文件字节备份，只升级版本；装备词汇与掉落池仍39，不赠物、不赠点、不改UID或重掷。旧39注入10661拒绝",
		"complete_gate":"仅10661完整原句接通；含其他未实现效果的混合节点仍不可分配；未分配时保留旧公式与字段，不新增计时器、战斗扫描或随机数"}


## v65: complete legal Model candidates; no user save access or synthetic stats.
static func zealots_oath_examples() -> Dictionary:
	var route: Array = ["47175", "31628", "9511", "23881", "26523", "6446", "10221", "50422", "50570", "29353", "44202", "23027", "60472", "26270", "64210", "7444", "63425"]
	var branch: Array = ["55649", "22285", "53793", "37884", "32482", "31033"]
	var fixture := Canonical.new()
	for uid: String in fixture.pending_items():
		var destination: Dictionary = fixture.first_bag_position(uid)
		assert(not destination.is_empty())
		_reference_move(fixture, uid, destination)
	var robe_uid: String = "gear_%06d" % int(fixture.snapshot().next_item_serial)
	assert(fixture._admit_reward_item(Canonical.Items.fixed_equipment(robe_uid, "guardian_robe")))
	_reference_move(fixture, robe_uid, {"kind":"equipment", "slot_id":"body_armour"})
	var instances: Dictionary = {}
	for base: String in ["tidebound_coat", "wayglass_token"]:
		var uid: String = "gear_%06d" % int(fixture.snapshot().next_item_serial)
		var tier: Dictionary = Equipment.affix_definition("lanternveil").tiers[2]
		var instance: Dictionary = {"id":uid, "base_id":base, "rarity":"magic", "item_level":16,
			"affixes":[{"id":"lanternveil", "tier":int(tier.tier), "value":int(tier.max)}]}
		assert(Equipment.validate_instance(instance) and fixture._admit_reward_item(Canonical.Items.wrap_equipment(instance)))
		instances[base] = instance
	_reference_move(fixture, instances.wayglass_token.id, {"kind":"equipment", "slot_id":"amulet"})
	var examples: Dictionary = {}
	for mode: String in ["before", "after", "changed_shield"]:
		var model := Canonical.new()
		var candidate: Dictionary = fixture.snapshot()
		candidate.progress = {"level":19, "xp":0}
		candidate.talents.class_id = 1
		candidate.talents.allocated = route.slice(0, route.size()-1) + branch + ["38906"]
		candidate.talents.normal_points = 1
		if mode != "before":
			candidate.talents.allocated.append("63425")
			candidate.talents.normal_points = 0
		assert(Canonical.Rules.reason(candidate).is_empty() and SourceTree.reason(candidate).is_empty())
		model._accept_memory(candidate)
		if mode == "changed_shield":
			_reference_move(model, instances.tidebound_coat.id, {"kind":"equipment", "slot_id":"body_armour"})
		var stats: Dictionary = model.get_stats()
		var profile: Dictionary = model.get_regeneration_profile()
		assert(profile.enabled == (mode != "before") and model.save_attempts == 0)
		assert(is_equal_approx(stats.life_regen_percent, 0.018))
		assert(is_equal_approx(profile.life_rate, 10.0 + 0.018 * stats.max_health) if mode == "before" else profile.life_rate == 0.0)
		assert(profile.shield_rate == 0.0 if mode == "before" else is_equal_approx(profile.shield_rate, 10.0 + 0.018 * stats.max_shield))
		var equipment: Dictionary = {}
		for slot: String in model.equipped_items():
			var uid: String = model.equipped_items()[slot]
			equipment[slot] = {"item":model.item(uid), "definition":model.item_definition(uid)}
		examples[mode] = {"class_id":1, "level":19, "allocated":model.snapshot().talents.allocated,
			"points_spent":model.snapshot().talents.allocated.size()-1, "points_remaining":model.talent_points,
			"stats":stats, "profile":profile, "equipment":equipment, "whole_build_valid":true, "save_attempts":model.save_attempts}
	var raw: Dictionary = SourceTree.Data.node("63425")
	var effect: Dictionary = SourceTree.node_effect("63425", 0, 41)
	var old: Dictionary = SourceTree.node_effect("63425", 0, 40)
	assert(effect.status == "full" and old.status == "unsupported")
	var sources: Dictionary = {}
	for id: String in ["31033", "32482", "38906"]:
		sources[id] = {"source_lines":SourceTree.Data.node(id).stats, "execution":SourceTree.node_effect(id)}
	return {"minimum_save_version":SourceTree.ZEALOTS_OATH_SAVE_VERSION, "source_policy":SourceTree.CURRENT_SAVE_VERSION,
		"equipment_vocabulary":Equipment.CURRENT_VOCABULARY, "source_version":"3.29.1", "source_sha256":SourceTree.Data.SOURCE_SHA256,
		"node":{"id":"63425", "name":raw.name, "source_lines":raw.stats, "execution":effect, "legacy_execution":old},
		"formula":"R + P × 最终最大护盾", "raw_flat_regeneration":10.0, "life_regeneration_fraction":0.018,
		"route":route, "regeneration_branch":branch, "shield_branch":["38906"], "sources":sources, "instances":instances,
		"examples":examples, "disabled_profile":Canonical.new().get_regeneration_profile(), "new_images":[],
		"producer":"EquipmentCatalog → validated CanonicalGameState.get_stats/get_regeneration_profile",
		"raw_rule":"R是原始固定生命再生每秒点数，P是原始同类百分比合计；固定值与百分比分别只计一次，不是已按生命计算值。容量和智慧提高先算最终最大护盾，再取该值作为百分比基数",
		"scope":"生命再生变为0；生命药剂、生命偷取、即时及拾取回复仍恢复生命，现有护盾充能与其等待延迟独立，再生可与充能相加",
		"timing":"沿既有1/60模拟资源阶段，在生命再生之后、药剂之前计入护盾再生；受伤与充能等待不阻止再生，不新增连续事件规划器",
		"capacity_rule":"满盾或最大护盾0时溢出丢弃，不回流生命；C页与F8显示潜在每秒速率，不是此刻实际已恢复量",
		"lifecycle":"死亡或暂停沿既有process门禁停止推进，不能救活致死伤害；分配、退款和换装只重算速率，不补当前资源",
		"example_scope":"同一19级野蛮人23点预算，未点花22点且余1点，点后花23点。保留默认其余装备及沿途属性；守护长袍加合法灯帷途镜坠，换装仅改为合法灯帷潮缄袍，不新增或赠送装备",
		"tradeoff":"失去生命再生后需靠既有生命恢复来源；更高护盾容量只提高百分比项，固定再生不跟随放大。换装还改变原充能供给，不能把盾再生增加称为整体生存提升",
		"migration":"schema41先严格验证旧40并备份原文件字节，只升级版本；源政策41、装备词汇39，不赠物品、点数，不改UID或重掷",
		"complete_gate":"只新增63425完整原句，标准图完整节点771→772，七职业各703→704可达非起点节点；混合未实现节点仍锁定。原始英文、身份、图结构保持，未分配不新增再生键、队列、扫描或随机抽样"}


static func mana_guard_examples() -> Dictionary:
	var node: Dictionary = SourceTree.Data.node("34098")
	var effect: Dictionary = SourceTree.node_effect("34098", 0, 35)
	var previous: Dictionary = SourceTree.node_effect("34098", 0, 34)
	assert(effect.status == "full" and previous.status == "unsupported")
	var derived: Dictionary = {}
	for grant: Dictionary in effect.grants:
		if grant.stat == Defense.MANA_GUARD_STAT:
			derived[grant.stat] = float(derived.get(grant.stat, 0.0)) + float(grant.value)
	var profile: Dictionary = Defense.mana_guard_profile(derived)
	assert(profile.ok and profile.enabled and is_equal_approx(profile.fraction, 0.4))
	var examples: Dictionary = {}
	for spec: Dictionary in [
		{"id":"full_mana", "shield":0.0, "mana":100.0, "health":200.0},
		{"id":"low_mana", "shield":0.0, "mana":10.0, "health":200.0},
		{"id":"partial_shield", "shield":30.0, "mana":100.0, "health":200.0},
		{"id":"full_shield", "shield":100.0, "mana":100.0, "health":200.0},
		{"id":"empty_mana", "shield":0.0, "mana":0.0, "health":200.0},
		{"id":"lethal", "shield":0.0, "mana":10.0, "health":20.0}]:
		var hit: Dictionary = Defense.incoming_source_hit({"fire":100.0}, {}, spec.shield, spec.health, "player", 0.0, spec.mana, profile.fraction)
		var burn: Dictionary = Defense.incoming_burn(100.0, 0.0, spec.shield, spec.health, "player", spec.mana, profile.fraction)
		assert(hit.ok and burn.ok)
		for field: String in ["damage_total", "shield_spent", "mana_spent", "health_lost", "overkill", "remaining_shield", "remaining_mana", "remaining_health"]:
			assert(var_to_bytes(hit[field]) == var_to_bytes(burn[field]))
		examples[spec.id] = {"input":spec, "hit":hit, "burn":burn}
	var zero_cases: Dictionary = {}
	for kind: String in ["legacy_hit", "source_hit", "burn"]:
		var old: Dictionary
		var zero: Dictionary
		if kind == "legacy_hit":
			old = Defense.incoming_hit({"fire":100.0}, {}, 30.0, 200.0)
			zero = Defense.incoming_hit({"fire":100.0}, {}, 30.0, 200.0, "player", 0.0, 100.0, 0.0)
		elif kind == "source_hit":
			old = Defense.incoming_source_hit({"fire":100.0}, {}, 30.0, 200.0)
			zero = Defense.incoming_source_hit({"fire":100.0}, {}, 30.0, 200.0, "player", 0.0, 100.0, 0.0)
		else:
			old = Defense.incoming_burn(100.0, 0.0, 30.0, 200.0)
			zero = Defense.incoming_burn(100.0, 0.0, 30.0, 200.0, "player", 100.0, 0.0)
		assert(var_to_bytes(old) == var_to_bytes(zero) and not zero.has("mana_spent") and not zero.has("remaining_mana"))
		zero_cases[kind] = {"omitted":old, "explicit_zero":zero, "variant_bytes_equal":var_to_bytes(old) == var_to_bytes(zero)}
	var mixed: Dictionary = Defense.incoming_source_hit({"physical":100.0,"fire":100.0,"cold":100.0,"lightning":100.0,"chaos":25.0},
		{"armour":500.0,"fire_resistance":0.25,"cold_resistance":0.5,"lightning_resistance":5.0}, 50.0, 200.0, "player", 0.15, 100.0, profile.fraction)
	assert(mixed.ok)
	var blocked: Dictionary = {}
	for id: String in ["42144", "922"]:
		var raw: Dictionary = SourceTree.Data.node(id)
		blocked[id] = {"name":raw.name, "source_lines":raw.stats, "standard_graph":SourceTree.Data.standard_ids().has(id),
			"execution":SourceTree.node_effect(id, 0, 35), "legacy_execution":SourceTree.node_effect(id, 0, 34)}
		assert(blocked[id].execution.status == "partial" and not blocked[id].standard_graph)
	var newly_complete: Array = []
	for id: String in SourceTree.Data.standard_ids():
		if SourceTree.Data.node(id).type != "mastery" and SourceTree.node_effect(id, 0, 34).status != "full" and SourceTree.node_effect(id, 0, 35).status == "full":
			newly_complete.append(id)
	newly_complete.sort()
	assert(newly_complete == ["34098"])
	var routes: Array = []
	for start: Dictionary in SourceTree.Data.class_starts():
		var path: Array = _mana_guard_supported_path(str(start.node_id))
		if path.is_empty(): continue
		var candidate: Dictionary = _fire_dot_route_candidate(int(start.class_index), path)
		assert(Canonical.Rules.reason(candidate).is_empty() and SourceTree.reason(candidate).is_empty())
		var old_candidate: Dictionary = candidate.duplicate(true)
		old_candidate.version = 34
		assert(not SourceTree.reason(old_candidate).is_empty())
		var model := Canonical.new()
		model._accept_memory(candidate)
		var live_profile: Dictionary = model.get_mana_guard_profile()
		assert(live_profile == profile)
		routes.append({"class_id":int(start.class_index), "class_name":start.class_name, "allocated":path,
			"points_spent":path.size()-1, "required_level":maxi(1,path.size()-5), "stats":model.get_stats(),
			"profile":live_profile, "whole_build_valid":true, "legacy34_rejected":true, "save_attempts":model.save_attempts})
	var old_save: Dictionary = Canonical.new().snapshot()
	old_save.version = 34
	var migrated: Dictionary = ManaGuardMigrationData.migrate_v34(old_save, SourceTree.reason)
	assert(not migrated.is_empty())
	var changed_fields: Array = []
	for key: String in old_save:
		if old_save[key] != migrated[key]: changed_fields.append(key)
	assert(changed_fields == ["version"])
	return {"minimum_save_version":35, "stat":Defense.MANA_GUARD_STAT, "source_version":"3.29.1", "source_sha256":SourceTree.Data.SOURCE_SHA256,
		"node":{"id":"34098", "name":node.name, "source_lines":node.stats, "execution":effect, "legacy_execution":previous},
		"profile":profile, "disabled_profile":Canonical.new().get_mana_guard_profile(), "new_complete_ordinary_nodes":newly_complete,
		"blocked_matching_nodes":blocked, "new_mastery_effect_ids":[], "new_images":[], "examples":examples, "zero_cases":zero_cases,
		"mixed_mitigation_example":mixed, "class_paths":routes,
		"migration_example":{"from_version":34,"to_version":migrated.version,"changed_fields":changed_fields,"granted_items":0,"granted_points":0},
		"producer":"SourceTree.node_effect → CanonicalGameState.get_mana_guard_profile → Defense.incoming_source_hit / incoming_burn / settle_with_mana",
		"order":"命中先沿既有护甲、抗性与感电结算；燃烧先结算火抗；然后护盾 → 对剩余伤害按比例支出当前魔力 → 生命，魔力不足由生命承担",
		"resource_rule":"与施法、药剂、再生和偷取共用当前魔力池；这是伤害分摊，不是魔力返还，也不提供免费施法",
		"damage_basis":"mana_spent独立于health_lost和shield_spent；浮字、偷取与命中归属沿原定义，过量伤害单列",
		"zero_rule":"缺省比例与显式0完全保留旧返回字段和Variant字节，不添加mana_spent或remaining_mana",
		"complete_gate":"本批仅34098完整接入；外图42144的8%与922的10%同族句可执行，其余未实现效果仍使混合节点整体锁定，升华分区不开放",
		"route_scope":"以下为生产源执行器上的受支持最短路径与完整构筑候选验证；未宣称通过交互逐点分配，且不代表123点能同时分配所有路线",
		"example_scope":"固定防御后100损伤、各行独立初始资源；hit与burn均直接调用生产防御规则，静态资源预算不是实战DPS",
		"legacy_rule":"schema35先严格按旧34词汇验证并保留原始文件逐字节备份；只显式迁移版本，不赠物、不赠点，旧无节点构筑机制保持",
		"unsupported":["生命或魔力Recoup","条件分摊","召唤物分摊","新增怪物魔力池","未完整实现的混合节点"]}


static func _mana_guard_supported_path(start_id: String) -> Array:
	var parents: Dictionary = {start_id:""}
	var queue: Array[String] = [start_id]
	var cursor: int = 0
	while cursor < queue.size():
		var id: String = queue[cursor]
		cursor += 1
		if id == "34098": return SourceCoverage._path_to(parents, start_id, id)
		var adjacent: Array = SourceTree.Data.adjacency(id).duplicate()
		adjacent.sort()
		for next: String in adjacent:
			if parents.has(next): continue
			var node: Dictionary = SourceTree.Data.node(next)
			if not SourceCoverage._path_exclusion(next, node, start_id).is_empty(): continue
			if SourceTree.node_effect(next, 0, 35).status != "full": continue
			parents[next] = id
			queue.append(next)
	return []


## v61: one fully legal in-memory source path, same equipment before/after.
## Numerical examples call current compiler/admission/damage/defense rules only.
static func resolute_technique_examples() -> Dictionary:
	var route: Array = ["47175", "31628", "9511", "23881", "26523", "6446", "10221", "50422", "50570", "29353", "63282", "31961"]
	var raw: Dictionary = SourceTree.Data.node("31961")
	var effect: Dictionary = SourceTree.node_effect("31961", 0, 38)
	assert(effect.status == "full" and effect.grants == [{"stat":"resolute_technique", "value":1.0, "mode":"flat"}])
	var fixture := Canonical.new()
	# Vacate all old slots first; never leave duplicate equipment locations.
	for uid: String in fixture.equipped_items().values():
		var bag: Dictionary = fixture.first_bag_position(uid)
		assert(not bag.is_empty())
		_reference_move(fixture, uid, bag)
	_reference_move(fixture, "prism_bow", {"kind":"equipment", "slot_id":"weapon"})
	_reference_move(fixture, "detonation_charm", {"kind":"equipment", "slot_id":"amulet"})
	var states: Dictionary = {}
	var target_evasion: float = float(AttackRules.monster_profile(1).evasion)
	var targets: Dictionary = {"evasive":{"evasion":target_evasion,"resistances":{},"armour":0.0},
		"no_evasion":{"evasion":0.0,"resistances":{},"armour":0.0}}
	var defense_input: Dictionary = {"armour":500.0, "fire_resistance":1.0, "cold_resistance":1.0, "lightning_resistance":1.0}
	var defense: Dictionary = Defense.source_profile(defense_input)
	assert(defense.get("ok", false) and defense.has("effective_resistances"))
	targets["armour_and_capped_resistance"] = {"evasion":target_evasion, "resistances":defense.effective_resistances, "armour":defense.armour}
	for mode: String in ["before", "after"]:
		var model := Canonical.new()
		var candidate: Dictionary = fixture.snapshot()
		candidate.progress = {"level":7, "xp":0}
		candidate.talents.class_id = 1
		candidate.talents.allocated = route.duplicate()
		candidate.talents.normal_points = 0
		if mode == "before":
			candidate.talents.allocated.pop_back()
			candidate.talents.normal_points = 1
		assert(Canonical.Rules.reason(candidate).is_empty() and SourceTree.reason(candidate).is_empty())
		model._accept_memory(candidate)
		var snapshot: Dictionary = model.get_combat_snapshot()
		assert(ResoluteRules.active(snapshot) == (mode == "after"))
		var casts: Dictionary = {}
		for skill: String in ["basic", "cleave", "tornado", "nova"]:
			var cast: Dictionary = model.get_basic_cast() if skill == "basic" else Compiler.compile_group(skill, snapshot, [])
			assert(cast.get("ok", false) and cast.has("packets") and cast.has("critical"))
			var hits: Dictionary = {}
			for role: String in cast.packets:
				if not cast.packets[role] is Dictionary: continue
				var packet: Dictionary = cast.packets[role]
				var profile_role: String = "secondary" if role == "secondary" else "primary"
				assert(cast.critical.has(profile_role))
				var critical: Dictionary = cast.critical[profile_role]
				var cases: Dictionary = {}
				for target_id: String in targets:
					var target: Dictionary = targets[target_id]
					var admitted: Dictionary = AttackRules.resolve(float(snapshot.accuracy), float(target.evasion), 50.0, ResoluteRules.active(snapshot)) if packet.tags.has("attack") else {"ok":true,"hit":true,"chance":1.0,"entropy":50.0}
					assert(admitted.get("ok", false) and admitted.has("chance") and admitted.has("entropy"))
					var ordinary: Dictionary = Defense.apply_armour(Damage.resolve(packet, snapshot.modifiers, target.resistances), float(target.armour))
					var potential: Dictionary = Defense.apply_armour(Damage.resolve(packet, snapshot.modifiers, target.resistances, float(critical.multiplier)), float(target.armour))
					assert(not ordinary.has("error") and not potential.has("error") and ordinary.has("total") and potential.has("total"))
					var expected: float = float(ordinary.total) * (1.0 - float(critical.chance)) + float(potential.total) * float(critical.chance)
					cases[target_id] = {"admission":admitted, "successful_noncritical_hit":ordinary, "potential_critical_hit":potential,
						"expected_per_successful_hit":expected, "expected_per_attempt":expected * float(admitted.chance)}
				hits[role] = {"packet":packet, "critical":critical, "critical_role":profile_role, "targets":cases}
			casts[skill] = {"hit_policy":cast.get("hit_policy", {}), "hits":hits,
				"recipe":cast.recipe, "mana":cast.get("mana",0.0), "cooldown":cast.get("cooldown",0.0),
				"summary":Preview.summary(cast), "details":Preview.details(cast)}
		states[mode] = {"talents":candidate.talents, "progress":candidate.progress, "stats":model.get_stats(), "snapshot":snapshot,
			"casts":casts, "equipment":model.equipped_items(), "whole_build_valid":true, "save_attempts":model.save_attempts}
		assert(model.save_attempts == 0)
	assert(states.before.casts.basic.hits.projectile.targets.evasive.admission.chance < 1.0)
	assert(states.after.casts.basic.hits.projectile.targets.evasive.admission.chance == 1.0)
	var opened: Array = []
	for id: String in SourceTree.Data.standard_ids():
		if SourceTree.Data.node(id).type != "mastery" and SourceTree.node_effect(id,0,37).status != "full" and SourceTree.node_effect(id,0,38).status == "full": opened.append(id)
	assert(opened == ["31961"])
	var blocked: Dictionary = {}
	for id: String in ["63620", "40907", "35448"]:
		# This is the v38 historical example, not the current source coverage.
		blocked[id] = {"source_lines":SourceTree.Data.node(id).stats, "execution":SourceTree.node_effect(id, 0, 38)}
		assert(blocked[id].execution.status != "full")
	return {"minimum_save_version":38, "source_policy":SourceTree.CURRENT_SAVE_VERSION, "equipment_vocabulary":Equipment.CURRENT_VOCABULARY,
		"node":{"id":"31961", "name":raw.name, "source_lines":raw.stats, "execution":effect, "legacy_execution":SourceTree.node_effect("31961",0,37)},
		"policy":ResoluteRules.POLICY.duplicate(true), "new_complete_ordinary_nodes":opened, "new_mastery_effect_ids":[], "new_images":[],
		"route":route, "class_id":1, "required_level":7, "points_spent":11, "examples":states, "targets":targets,
		"defense_input":defense_input, "defense_profile":defense, "blocked_matching_nodes":blocked,
		"producer":"SourceTree → validated CanonicalGameState → SkillCompiler → AttackHitRules → DamageResolver / DefenseRules",
		"scope":"完整原双句只授予一个开关；所有命中不能被闪避但不能暴击，攻击、法术、母子箭、返回与独立爆炸均承担禁暴击代价",
		"bounds":"距离、墙体、出生保护、目标存活、支付和容量仍正常检查；成功命中仍结算护甲、抗性、护盾与生命",
		"timing":"施放时冻结；分配、退款和换装只影响新施放，旧飞行、母子箭、返回与独立爆炸保持各自快照",
		"randomness":"开启时命中率为1且闪避熵保持原值；私有暴击随机流零抽样，掉落随机流无新增抽样；未点路径保留旧字节与随机流，不要求开关前后私有暴击随机状态相同",
		"example_scope":"同一7级野蛮人合法路径，仅比较最后1点；两边都装备已有棱光长弓和终焰护符。技能按该角色快照无辅助编译，不宣称同时装配；预期值是一次尝试的统计比较，不是实战DPS",
		"defense_scope":"护甲500与原始三抗100%为既有防御规则的隔离输入；按当前默认75%上限结算，不代表新增怪物或平衡调整",
		"migration":"schema38严格验证旧37并原字节备份，只迁版本；装备词汇保持37，不赠物、不赠点、不重掷词缀"}


## Five narrow comparisons use validated in-memory source builds and the real
## compiler. No synthetic UI arithmetic, user saves, new items or images.
static func physical_fire_conversion_examples() -> Dictionary:
	var route: Array = ["47175", "31628", "9511", "23881", "26523", "6446", "10221", "54396", "2550"]
	var entrances: Array = ["11505", "19749", "34927", "37911", "38320", "40271", "48267", "63268"]
	var gateways: Dictionary = {"11505":"29049", "63268":"24324", "48267":"2550", "34927":"11924"}
	var source: Dictionary = {}
	for id: String in entrances:
		var node: Dictionary = SourceTree.Data.node(id)
		var selected: Dictionary = SourceTree.node_effect(id, 65020, 44)
		assert(selected.status == "full" and SourceTree.node_effect(id, 65020, 43).status == "unsupported")
		source[id] = {"group_id":node.group_id, "execution":selected, "reachable_group":gateways.has(id),
			"gateway_id":gateways.get(id, ""), "legacy_execution":SourceTree.node_effect(id,65020,43)}
	var target_stats: Dictionary = {"armour":{"armour":500.0}, "fire_resistance":{"fire_resistance":0.75}}
	var examples: Dictionary = {}
	for spec: Dictionary in [
		{"id":"basic_blade", "name":"短刃近战普攻", "skill":"basic", "base":"forgeblade", "supports":[], "affixes":["whetstone_edge","tempered_edge","deepwell","wellturn"]},
		{"id":"cleave_physical_focus", "name":"短刃裂刃＋物理专注", "skill":"cleave", "base":"forgeblade", "supports":["physical_focus"], "affixes":["whetstone_edge","tempered_edge","deepwell","wellturn"]},
		{"id":"tornado_physical_focus_ignite", "name":"长弓龙卷＋物理专注＋点燃", "skill":"tornado", "base":"ashwood_bow", "supports":["physical_focus","ignite"], "affixes":["whetstone_edge","tempered_edge","deepwell","wellturn"]},
		{"id":"tornado_fire_focus_ember", "name":"长弓龙卷＋火焰专注＋余烬扩散", "skill":"tornado", "base":"ashwood_bow", "supports":["fire_focus","ember_proliferation"], "affixes":["whetstone_edge","tempered_edge","deepwell","wellturn"]},
		{"id":"tornado_added", "name":"符木龙卷＋外部物理及火焰点伤", "skill":"tornado", "base":"runewood_focus", "supports":[], "affixes":["attack_added_physical","attack_added_fire","deepwell","wellturn"]}]:
		var pair: Dictionary = {"name":spec.name, "skill_id":spec.skill, "base_id":spec.base, "supports":spec.supports, "states":{}}
		for enabled: bool in [false,true]:
			var model := Canonical.new()
			var item: Dictionary = _local_instance(spec.affixes,"rare",spec.base)
			item.id = "gear_%06d" % int(model.snapshot().next_item_serial)
			assert(Equipment.validate_instance(item), "Conversion reference weapon must be legal: " + spec.id)
			assert(model._admit_reward_item(Canonical.Items.wrap_equipment(item)), "Conversion reference item must enter the real inventory: " + spec.id)
			_reference_move(model,item.id,{"kind":"equipment","slot_id":"weapon"})
			# Equip the already-owned detonation charm to retain a nonzero pure-fire
			# secondary packet in the tornado rows. This is not a new reward.
			_reference_move(model,"detonation_charm",{"kind":"equipment","slot_id":"amulet"})
			var candidate: Dictionary = model.snapshot()
			candidate.progress = {"level":5,"xp":0}
			candidate.talents.class_id = 1
			candidate.talents.allocated = route.duplicate()
			candidate.talents.masteries = {}
			candidate.talents.normal_points = 1
			if enabled:
				candidate.talents.allocated.append("48267")
				candidate.talents.masteries["48267"] = 65020
				candidate.talents.normal_points = 0
			assert(Canonical.Rules.reason(candidate).is_empty() and SourceTree.reason(candidate).is_empty())
			model._accept_memory(candidate)
			var input: Dictionary = model.get_combat_snapshot()
			var cast: Dictionary = Compiler.compile_basic(input) if spec.skill == "basic" else Compiler.compile_group(spec.skill,input,spec.supports)
			assert(cast.ok and model.save_attempts == 0)
			var state: Dictionary = {"stats":model.get_stats(), "snapshot":cast.snapshot, "instance":item,
				"allocated":candidate.talents.allocated, "points_remaining":model.talent_points,
				"whole_build_valid":true, "save_attempts":model.save_attempts, "hits":{},
				"support_ids":cast.get("support_ids",[]), "mana":cast.get("mana",0.0), "cooldown":cast.get("cooldown",0.0),
				"summary":Preview.summary(cast), "details":Preview.details(cast)}
			for field: String in ["conversion_profile", "burn_profile", "critical"]:
				if cast.has(field): state[field] = cast[field].duplicate(true)
			for role: String in cast.packets:
				var packet: Dictionary = cast.packets[role]
				var resolved: Dictionary = Damage.resolve(packet,cast.snapshot.modifiers)
				assert(not resolved.has("error"))
				var hit: Dictionary = {"packet":packet, "resolved":resolved, "defended":{}}
				for target_id: String in target_stats:
					var profile: Dictionary = Defense.source_profile(target_stats[target_id],"monster")
					var defended: Dictionary = Defense.apply_armour(Damage.resolve(packet,cast.snapshot.modifiers,profile.effective_resistances),profile.armour)
					var settlement: Dictionary = Defense.settle_resolved(defended,0.0,10000.0)
					assert(profile.ok and settlement.ok)
					hit.defended[target_id] = {"profile":profile,"resolved":defended,"settlement":settlement}
				state.hits[role] = hit
			pair.states["after" if enabled else "before"] = state
		var before: Dictionary = pair.states.before
		var after: Dictionary = pair.states.after
		assert(before.instance == after.instance and before.mana == after.mana and before.cooldown == after.cooldown)
		if before.hits.has("secondary"):
			assert(before.hits.secondary == after.hits.secondary and not after.hits.secondary.packet.has("conversion"))
		examples[spec.id] = pair
	return {"minimum_save_version":44,"source_policy":SourceTree.CURRENT_SAVE_VERSION,"equipment_vocabulary":Equipment.CURRENT_VOCABULARY,
		"effect_id":65020,"source_line":"40% of Physical Damage Converted to Fire Damage","source_version":"3.29.1","source_sha256":SourceTree.Data.SOURCE_SHA256,
		"fraction":0.4,"entrances":source,"reachable_gateways":gateways,"route":route,"mastery_id":"48267","class_id":1,"level":5,"point_budget":9,
		"targets":target_stats,"examples":examples,"new_images":[],
		"producer":"SourceTree → validated CanonicalGameState → SkillCompiler → DamageResolver → DefenseRules",
		"example_scope":"同一5级野蛮人9点预算：前置路线花8点，选精通后花9点。装备为既有合法四缀稀有武器，双T3伤害前缀加深汲与泉旋，其他装备保持默认，仅改穿已拥有的爆破护符；每组只切换同一精通。数值是不暴击、成功命中的单次伤害，不是DPS",
		"assembly":"先合计技能固有物理、按附加效用缩放的外部物理点伤与按命中系数缩放的局部武器物理，再把40%分给火焰、60%留作物理；原生火焰单独保留。龙卷自身原有60%物理/40%火焰分布不等于本次转换",
		"lineage":"转换火焰保留physical/fire两种伤害来源；每条modifier数组记录只匹配一次。increased相加，独立MORE逐条相乘；同时覆盖两类型的一条记录不重复，同id的不同记录仍各算一次",
		"focus":"物理专注或火焰专注对转换部分的两个独立条款均匹配，×1.20再×0.80＝×0.96；不能按id去重，也不是只取最终火焰标签。残余物理与原生火焰分别按自己的来源匹配",
		"defense":"同一最终类型先合并一次，再走当前护甲和抗性；物理只对残余物理计算随命中大小变化的护甲，火焰合并原生与转换部分后走火抗。转换不是无条件增伤，对应防御与专注搭配会改变收益",
		"burn":"仅既有可点燃命中继续点燃：最终防御前火焰合计只作为一次燃烧输入，然后火焰持续伤害加成与加速燃烧各算一次。燃烧tick不再转换或重吃命中增伤；没有新增普攻或裂刃点燃资格，纯火独立爆炸保持原规则",
		"leech":"全攻击偷取按实际造成的命中总量；物理攻击偷取只取防御后且受实际护盾/生命扣减限制的残余物理占比，转换火焰不再算物理偷取。燃烧仍不偷取",
		"snapshot":"施放时冻结原始组装、转换比例和modifier；退款或换装仅影响之后的新施放，已在途母箭、子箭和已建立燃烧保留原快照。无转换时不增加空profile、parts或转换字段",
		"availability":"仅原始Fire Mastery65020完整原句开放。8个入口共享唯一效果，当前4个原始显著天赋组可达；另外4组仍被未实现前置阻挡。退款后才可由另一入口重新选择，不是可叠加8次",
		"migration":"schema43→44先严格验证旧43并备份原字节；只升级版本，source44开放此一词汇，装备词汇仍39。不送点、宝石或装备，不改经济、原始源树英文、中文映射或素材",
		"bounds":"没有多段或其他类型转换、额外获得伤害、Avatar of Fire、DoT转换、穿透或新异常规则；本页不把编译验证当作实战或Windows成品验收"}


## v70: consume exactly the three passing actual-Main snapshots. Never create
## another item, choose a new route, or mutate/re-save the gameplay fixtures.
static func precise_technique_examples() -> Dictionary:
	var fixture_root: String = "res://docs/qa/v070-gameplay/fixtures/"
	var acceptance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v070-gameplay/acceptance.json"))
	assert(acceptance.get("passed", false), "Actual-Main section acceptance must pass first")
	var examples: Dictionary = {}
	for name: String in ["selected-above", "selected-below", "refunded"]:
		var path: String = fixture_root + name + ".json"
		var expected_path: String = fixture_root + name + "-expected.json"
		assert(FileAccess.file_exists(path) and FileAccess.file_exists(expected_path), "Passing actual-Main fixtures are required: " + name)
		var fixture_hash: String = FileAccess.get_sha256(path)
		var expected_hash: String = FileAccess.get_sha256(expected_path)
		assert(acceptance.fixtures.get(name + ".json") == fixture_hash and acceptance.fixtures.get(name + "-expected.json") == expected_hash, "Fixture must match passing actual-Main receipt: " + name)
		# These immutable receipts were recorded under schema45. Validate the
		# frozen envelope before the production version-only migration; never
		# relabel raw JSON or rewrite historical Main fixtures for the exporter.
		var historical: Dictionary = Canonical.Rules.decode_v45(JSON.parse_string(FileAccess.get_file_as_string(path)))
		assert(not historical.is_empty(), "Frozen schema45 gameplay fixture must validate: " + name)
		var schema46: Dictionary = GloveRingMigration.migrate_v45(historical, SourceTree.reason)
		assert(not schema46.is_empty() and int(schema46.version) == 46)
		var raw: Dictionary = FrostLockMigration.migrate_v46(schema46, SourceTree.reason)
		var expected_migration: Dictionary = historical.duplicate(true)
		expected_migration.version = Canonical.Rules.VERSION
		assert(raw == expected_migration, "Historical Main fixture may change only version in memory: " + name)
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
		assert(not raw.is_empty() and int(raw.version) == Canonical.Rules.VERSION and Canonical.Rules.reason(raw).is_empty() and SourceTree.reason(raw).is_empty(), "Current complete gameplay fixture must validate: " + name)
		var model := Canonical.new()
		model._accept_memory(raw.duplicate(true))
		var stats: Dictionary = model.get_stats()
		assert(JSON.parse_string(JSON.stringify(stats, "", true, true)) == expected.stats, "Rehydrated stats must match passing actual Main: " + name)
		var casts: Dictionary = {}
		for skill: String in ["basic", "cleave", "tornado"]:
			var cast: Dictionary = model.get_basic_cast() if skill == "basic" else model.get_group_cast(str(expected[skill].group_id))
			assert(cast.get("ok", false) and JSON.parse_string(JSON.stringify(cast, "", true, true)) == expected[skill], "Recompiled cast must match passing actual Main: " + name + "/" + skill)
			var hits: Dictionary = {}
			for role: String in cast.packets:
				var packet: Dictionary = cast.packets[role]
				var resolved: Dictionary = Damage.resolve(packet, cast.snapshot.modifiers)
				var critical_role: String = "secondary" if role == "secondary" else "primary"
				assert(not resolved.has("error") and cast.critical.has(critical_role))
				hits[role] = {"resolved":resolved, "critical":cast.critical[critical_role], "tags":packet.tags}
			casts[skill] = {"compiled":cast, "hits":hits, "summary":Preview.summary(cast), "details":Preview.details(cast)}
		var equipment: Dictionary = {}
		for slot: String in model.equipped_items():
			var uid: String = model.equipped_items()[slot]
			equipment[slot] = {"uid":uid, "item":raw.items[uid], "definition":model.item_definition(uid)}
		assert(model.save_attempts == 0 and model.snapshot() == raw)
		assert(FileAccess.get_sha256(path) == fixture_hash and FileAccess.get_sha256(expected_path) == expected_hash)
		examples[name] = {"fixture":"docs/qa/v070-gameplay/fixtures/" + name + ".json", "fixture_sha256":fixture_hash,
			"expected_fixture":"docs/qa/v070-gameplay/fixtures/" + name + "-expected.json", "expected_sha256":expected_hash,
			"stats":stats, "talents":raw.talents, "progress":raw.progress, "equipment":equipment,
			"whole_build_valid":true, "matches_actual_main":true, "save_attempts":model.save_attempts, "casts":casts}
	var node: Dictionary = SourceTree.Data.node("63620")
	var execution: Dictionary = SourceTree.node_effect("63620", 0, 45)
	assert(execution.status == "full" and SourceTree.node_effect("63620", 0, 44).status == "unsupported")
	return {"minimum_save_version":45, "source_policy":SourceTree.CURRENT_SAVE_VERSION, "equipment_vocabulary":Equipment.CURRENT_VOCABULARY,
		"node":{"id":"63620", "name":node.name, "source_lines":node.stats, "execution":execution, "legacy_execution":SourceTree.node_effect("63620",0,44)},
		"new_complete_ordinary_nodes":["63620"], "new_mastery_effect_ids":[], "new_images":[], "attack_more":0.4,
		"examples":examples, "producer":"Passing actual Main snapshots → current Canonical Rules / Model → SkillCompiler → DamageResolver",
		"condition":"A为最终命中值，L为最终最大生命；仅A严格大于L时获得一条40%攻击伤害MORE，等于或低于时为0。当前受伤生命不参与比较，喝药或回复不会切换条件",
		"scope":"该MORE必须同时匹配hit与attack，适用所有伤害类型，转换火焰也只计一次；普通攻击、裂刃、龙卷母子箭及返回攻击按各自冻结命中包结算。法术与独立爆炸不享受攻击MORE",
		"critical_cost":"只要分配精准技艺，无论A与L是否满足条件，所有攻击、法术及独立爆炸均不能暴击。既有潜在倍率可保留展示，但最终暴击率为0；不额外授予不能被闪避",
		"snapshot":"原始属性precise_technique为1；施放快照只冻结accuracy与max_health，编译profile公开enabled、accuracy、max_health、condition_met、attack_more、cannot_deal_critical_strikes与attack_applies。分配、退款及换装仅影响新施放，在途命中保持旧快照",
		"early_tradeoff":"游侠从原起点沿8点合法路线即可到达；裸装前置属性为A284、L141，早期容易满足条件，因此是已知的强势入口。持续堆生命会抬高L并失去攻击MORE，禁暴击代价仍在；这不是长期平衡或最优路线结论",
		"example_scope":"三个状态直接复用本批通过实际Main的快照：已点且A>L、已点且A<L、已退款。前两者以实际生命装备切换阈值；已点高于阈值与退款状态使用相同短刃和已装备物品，可直接比较增伤与暴击取舍，数值是成功且不暴击、零防御的一次命中，不是DPS",
		"availability":"仅节点63620的完整多行原文开放，不接受截断的增伤句、禁暴击半句或同义改写。没有新节点、宝石、词缀或图片；坚决技艺仍独立决定不能被闪避，两个禁暴击效果取并集",
		"migration":"schema44→45先按旧44完整验证并备份原字节，再只升级版本；源政策45、装备词汇39。不赠点、不赠物、不重掷，不改变原始源树、拓扑或经济",
		"bounds":"本节是实际Main快照的只读重编译与资料保全；实际在途、转换与暴击随机流证据见本批gameplay和rules记录。没有Windows、打包、tag或Release验收"}


## v72 reuses the exact passing Main states and expected casts. Endpoint probes
## below are isolated rule inputs, never substitute authored gear or builds.
static func glove_ring_affix_examples() -> Dictionary:
	var fixture_root: String = "res://docs/qa/v072-gameplay/fixtures/"
	var acceptance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v072-gameplay/acceptance.json"))
	assert(acceptance.get("passed", false), "v72 actual-Main acceptance must pass before reference export")
	var examples: Dictionary = {}
	for name: String in ["precise-equal", "precise-above", "glove-finesse", "rings-triple-default", "rings-source-cap83"]:
		var path: String = fixture_root + name + ".json"
		var expected_path: String = fixture_root + name + "-expected.json"
		assert(FileAccess.file_exists(path) and FileAccess.file_exists(expected_path), "Passing Main fixture required: " + name)
		var fixture_hash: String = FileAccess.get_sha256(path)
		var expected_hash: String = FileAccess.get_sha256(expected_path)
		assert(acceptance.fixtures.get(name + ".json") == fixture_hash and acceptance.fixtures.get(name + "-expected.json") == expected_hash, "Fixture must match passing Main receipt: " + name)
		var historical: Dictionary = Canonical.Rules.decode_v46(JSON.parse_string(FileAccess.get_file_as_string(path)))
		assert(not historical.is_empty(), "Frozen schema46 Main fixture must validate: " + name)
		var raw: Dictionary = FrostLockMigration.migrate_v46(historical, SourceTree.reason)
		var expected_migration: Dictionary = historical.duplicate(true)
		expected_migration.version = 47
		assert(raw == expected_migration, "Historical Main fixture may change only version in memory: " + name)
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
		assert(not raw.is_empty() and int(raw.version) == Canonical.Rules.VERSION and Canonical.Rules.reason(raw).is_empty() and SourceTree.reason(raw).is_empty(), "Complete Main fixture must validate: " + name)
		var model := Canonical.new()
		model._accept_memory(raw.duplicate(true))
		var stats: Dictionary = model.get_stats()
		var resistance: Dictionary = model.get_resistance_profile()
		assert(JSON.parse_string(JSON.stringify(stats, "", true, true)) == expected.stats, "Main stats must match at recorded JSON precision: " + name)
		assert(JSON.parse_string(JSON.stringify(resistance, "", true, true)) == expected.resistance, "Main resistance profile must match: " + name)
		var casts: Dictionary = {}
		for skill: String in ["basic", "cleave", "tornado"]:
			var cast: Dictionary = model.get_basic_cast() if skill == "basic" else model.get_group_cast(str(expected[skill].group_id))
			assert(cast.get("ok", false) and JSON.parse_string(JSON.stringify(cast, "", true, true)) == expected[skill], "Main cast must match: " + name + "/" + skill)
			casts[skill] = cast
		var equipment: Dictionary = {}
		for slot: String in model.equipped_items():
			var uid: String = model.equipped_items()[slot]
			equipment[slot] = {"uid":uid, "item":raw.items[uid], "definition":model.item_definition(uid)}
		assert(model.save_attempts == 0 and model.snapshot() == raw)
		assert(FileAccess.get_sha256(path) == fixture_hash and FileAccess.get_sha256(expected_path) == expected_hash)
		examples[name] = {"fixture":"docs/qa/v072-gameplay/fixtures/" + name + ".json", "fixture_sha256":fixture_hash,
			"expected_fixture":"docs/qa/v072-gameplay/fixtures/" + name + "-expected.json", "expected_sha256":expected_hash,
			"stats":stats, "resistance":resistance, "casts":casts, "equipment":equipment, "talents":raw.talents, "progress":raw.progress,
			"whole_build_valid":true, "matches_actual_main":true, "save_attempts":model.save_attempts}
	var families: Dictionary = {}
	for id: String in Equipment.GloveRingAffixes.AFFIX_IDS:
		families[id] = Equipment.affix_definition(id)
		assert(Equipment.GloveRingAffixes.valid_family(families[id]))
	var probes: Array = []
	var baseline_accuracy: float = 284.0
	var evasion: float = float(Monsters.MIST_SKITTER_POLICY.evasion)
	for tier: Dictionary in families.glove_accuracy.tiers:
		var endpoints: Dictionary = {}
		for end: String in ["min", "max"]:
			var accuracy: float = baseline_accuracy + float(tier[end])
			endpoints[end] = {"flat_accuracy":tier[end], "accuracy":accuracy, "chance":AttackRules.resolve(accuracy, evasion).chance}
		probes.append({"tier":tier.tier, "level":tier.level, "weight":tier.weight, "endpoints":endpoints})
	return {"minimum_save_version":Equipment.GloveRingAffixes.MIN_SAVE_VERSION, "equipment_vocabulary":Equipment.CURRENT_VOCABULARY,
		"source_policy":SourceTree.CURRENT_SAVE_VERSION, "new_families":families, "base_ids":[Equipment.GloveRingAffixes.GLOVE_BASE_ID, Equipment.GloveRingAffixes.RING_BASE_ID],
		"pool_id":"build_nine_slot_v46", "pool":Equipment.pool_profiles().build_nine_slot_v46,
		"loot_profile_id":Canonical.LOOT_PROFILE_ID, "loot_profile":Equipment.loot_profile(Canonical.LOOT_PROFILE_ID),
		"existing_slot_count":EquipmentSlotsData.all_slots().size(), "existing_random_base_count":Equipment.all_base_ids().size(), "existing_fixed_item_count":Data.ITEMS.size(),
		"examples":examples, "accuracy_probes":{"baseline_accuracy":baseline_accuracy, "evasion":evasion, "baseline_chance":AttackRules.resolve(baseline_accuracy, evasion).chance, "tiers":probes},
		"accuracy_scope":"精瞄是角色全局固定命中值，装备固定值先汇总，再与每点敏捷的2命中一起乘源命中提高；只放大一次。攻击准入仍读原命中规则，法术不进行攻击闪避",
		"prefix_tradeoff":"精瞄与生命、魔力、护盾竞争手套前缀；魔法至多1前1后，稀有至多3前3后。同族或同组不能在同一件物品重复",
		"ring_tradeoff":"双戒与胸甲各取三条T3最高抗性后缀，合计九条完美后缀才得到原始火90%、冰75%、电75%；这是合法极值，不是正常预期掉落。戒指三抗占满后缀，放弃暴击、魔力恢复、移速等选择",
		"cap_scope":"原始抗性、最大上限、有效抗性分别计算；原始值超过上限不继续减伤，提高上限也不会凭空补足原始抗性。装备抗性不授予最大抗性",
		"supply_scope":"已有九槽、15种随机底材和9件固定装备均保持；本批为现有手套与戒指增加构筑选择，不是补不存在的空槽。canonical_v46仅把原30%九槽入口替换为同五底材的新池，其余入口与权重顺序保持",
		"migration":"严格decode_v45和旧45全量验证后备份原字节，再仅迁version到46；源政策仍45，装备词汇46。旧词族元数据、物品UID与掷值保持，不重掷、不赠物或点数",
		"producer":"Passing actual Main snapshots → current Canonical Rules / Model → SkillCompiler / DefenseRules; isolated endpoints → AttackHitRules",
		"new_images":[], "bounds":"不新增底材、UI、素材、源节点或定向制作按钮；五个实际Main构筑仅只读重编译，本页不是DPS、最优构筑、长期掉落频率或Windows成品验收"}


## Rehydrate the passing real Main fixture; no authored reference gear or saves.
static func frost_lock_examples() -> Dictionary:
	var fixture: String = "docs/qa/v073-gameplay/fixtures/selected.json"
	var expected_fixture: String = "docs/qa/v073-gameplay/fixtures/selected-casts.json"
	var acceptance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v073-gameplay/acceptance-summary.json"))
	assert(acceptance.get("passed", false), "v73 actual Main must pass first")
	var fixture_hash: String = FileAccess.get_sha256("res://" + fixture)
	var expected_hash: String = FileAccess.get_sha256("res://" + expected_fixture)
	assert(acceptance.fixtures["fixtures/selected.json"] == fixture_hash and acceptance.fixtures["fixtures/selected-casts.json"] == expected_hash)
	var raw: Dictionary = Canonical.Rules.decode(JSON.parse_string(FileAccess.get_file_as_string("res://" + fixture)))
	assert(not raw.is_empty() and int(raw.version) == 47 and Canonical.Rules.reason(raw).is_empty() and SourceTree.reason(raw).is_empty())
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + expected_fixture))
	var model := Canonical.new()
	model._accept_memory(raw.duplicate(true))
	var casts: Dictionary = {"basic":model.get_basic_cast(), "frost":model.get_group_cast(str(expected.frost.group_id)),
		"plain_frost":Compiler.compile_group("frost", model.get_combat_snapshot(), [])}
	var stats: Dictionary = model.get_stats()
	assert(JSON.parse_string(JSON.stringify(stats, "", true, true)) == expected.stats)
	var examples: Dictionary = {}
	for key: String in casts:
		var cast: Dictionary = casts[key]
		assert(cast.get("ok", false) and JSON.parse_string(JSON.stringify(cast, "", true, true)) == expected[key], "v73 Main cast must match: " + key)
		var resolved: Dictionary = Damage.resolve(cast.packets.projectile, cast.snapshot.modifiers)
		examples[key] = {"compiled":cast, "resolved":resolved, "summary":Preview.summary(cast), "details":Preview.details(cast)}
	assert(model.save_attempts == 0 and model.snapshot() == raw)
	assert(FileAccess.get_sha256("res://" + fixture) == fixture_hash and FileAccess.get_sha256("res://" + expected_fixture) == expected_hash)
	var policy: Dictionary = Compiler.FrostLock.PLAYER_POLICY.duplicate(true)
	var durations: Dictionary = {}
	var runtime := FreezeRuntimeData.new()
	var id: int = 1
	for rarity: String in Compiler.FrostLock.RARITY_KEYS:
		assert(runtime.apply(id, rarity, 0.0, policy, {"skill_id":"frost", "phase":"projectile"}).applied)
		durations[rarity] = runtime.state_for(id)
		id += 1
	var split: Dictionary = runtime.frame_prefixes(0.5, 0.25)
	assert(split.ok)
	var blocked: float = float(split.by_id[1])
	var quote: Dictionary = Canonical.GemTrade.quote("buy", "support:frost_lock")
	var test_offer: Dictionary = Town.offer("support:frost_lock")
	assert(quote.ok and test_offer.available)
	return {"minimum_save_version":Supports.FrostLock.SAVE_VERSION, "source_policy":SourceTree.CURRENT_SAVE_VERSION,
		"equipment_vocabulary":Equipment.CURRENT_VOCABULARY, "support_id":"frost_lock", "skills":Supports.FrostLock.SKILLS,
		"mutually_exclusive_with":["lingering_chill"], "policy":policy, "max_targets":FreezeRuntimeData.MAX_TARGETS,
		"icon_source":GemCatalogData.definition("support:frost_lock").icon, "icon_file":"originals/frost_lock.png",
		"fixture":fixture, "fixture_sha256":fixture_hash, "expected_fixture":expected_fixture, "expected_sha256":expected_hash,
		"stats":stats, "examples":examples, "whole_build_valid":true, "matches_actual_main":true, "save_attempts":model.save_attempts,
		"merchant_quote":quote, "test_offer":test_offer, "normal_reward_pool_includes_support":Canonical.Journey.GEM_DEFINITIONS.has("support:frost_lock"),
		"normal_reward_definition_count":Canonical.Journey.GEM_DEFINITIONS.size(),
		"timing":{"states":durations, "partial_frame":{"start":0.5, "delta":0.25, "frozen_prefix":blocked, "active_delta":0.25-blocked}},
		"eligibility":"只有冰霜脉冲主投射物通过原出生与命中准入、造成正的实际冰伤盾血损失且目标仍存活，才进入冻结；抵消为零、致死、DOT、独立爆炸与其他技能附加冰伤不触发",
		"admission":"按当前命中结算边界elapsed附加，立即阻止tick末新预警起手；下一敌方阶段开始暂停，不追溯取消本tick已经结算的攻击",
		"paused":"暂停自主移动、接触攻击计时及预警蓄力、恢复、双响局部时钟；保留原锁定圆心、已过蓄力与pulse序号，解冻接续原攻击",
		"continuing":"外力冲量、怪物分离、墙体碰撞、燃烧、感电、其他状态与护盾恢复继续；仍可能被推移，冻结不暂停世界资源时钟",
		"expiry":"冻结不刷新、不叠加；解冻后免疫，跨技能组共用同一怪物ID。精确到期恢复，跨解冻帧仅推进剩余delta，预警事件相对时间补上冻结前缀",
		"snapshot":"施放时独立保存compiled.freeze_profile与snapshot.freeze_policy；在途投射物不因拆石、换装或退款改变。无辅助不添加空冻结字段；原3秒移动减缓保持",
		"cleanup":"最多100个既有怪物ID状态，免疫结束清理；死亡立即移除，玩家死亡、换图、返城、重启清空。公开冻结列表只显示正在冻结的怪物",
		"migration":"严格decode_v46与旧46完整验证，备份原字节后仅迁version到47；不赠宝石或碎片，装备词汇46、源政策45、既有26种正式奖励顺序保持",
		"example_scope":"直接复用通过实际Main的完整合法47存档，在内存只读重编译；无辅助冰霜为同快照对照。数值是非暴击、无防御单次主命中，不是DPS。时间示例调用FreezeRuntime，不重跑Main",
		"bounds":"仅新增一枚霜锁辅助及其灰白冰晶；不支持玩家被冻、碎冰、传播或新的冻结天赋。静态资料验证不等于原生、Windows或打包验收"}


## v78 exports only new authoritative examples and the four newly supported
## source sentences. Historical catalog data never enters this Godot process.
static func elemental_conversion_fragment() -> Dictionary:
	var affected_lines: Array[String] = ["40% of Physical Damage Converted to Cold Damage",
		"40% of Physical Damage Converted to Lightning Damage", "Damage Penetrates 6% Cold Resistance",
		"Damage Penetrates 6% Lightning Resistance"]
	var nodes: Dictionary = {}
	var localized_nodes: Dictionary = {}
	var localized_lines: Dictionary = {}
	for line: String in affected_lines:
		localized_lines[line] = {"text":SourceLocalization.display_lines([line]), "status":SourceLocalization.line_status(line)}
	for id: String in SourceTree.Data.nodes():
		var raw: Dictionary = SourceTree.Data.node(id)
		var affected: bool = false
		for line: String in raw.stats:
			if affected_lines.has(line): affected = true
		for choice: Dictionary in raw.mastery_effects:
			for line: String in choice.stats:
				if affected_lines.has(line): affected = true
		if not affected: continue
		var choices: Array = []
		var localized_choices: Dictionary = {}
		for choice: Dictionary in raw.mastery_effects:
			choices.append({"effect":int(choice.effect), "stats":choice.stats, "execution":SourceTree.node_effect(id,int(choice.effect))})
			localized_choices[str(int(choice.effect))] = SourceLocalization.display_lines(choice.stats,"\n",id)
		nodes[id] = {"execution":SourceTree.node_effect(id), "mastery_choices":choices}
		localized_nodes[id] = {"stats":SourceLocalization.display_lines(raw.stats,"\n",id), "mastery_choices":localized_choices}
	assert(nodes.size() == 13, "Only two notables and eleven existing mastery entrances change")
	var mechanisms: Dictionary = {}
	for id: String in SourceMonster.IDS: mechanisms[id] = mechanism_reference(id)
	return {"game_version":ProjectSettings.get_setting("application/config/version"), "save_version":Canonical.Rules.VERSION,
		"source_policy":SourceTree.CURRENT_SAVE_VERSION, "nodes":nodes, "localized_nodes":localized_nodes,
		"localized_lines":localized_lines, "mechanisms":mechanisms, "elemental_conversion":elemental_conversion_examples()}


static func _elemental_reference_hit(packet: Dictionary, cast: Dictionary) -> Dictionary:
	var resolved: Dictionary = Damage.resolve(packet,cast.snapshot.modifiers)
	assert(not resolved.has("error"))
	var before_defense: Dictionary = {}
	for detail: Dictionary in resolved.details: before_defense[detail.type] = detail.before_defense
	var targets: Dictionary = {}
	for spec: Dictionary in [
		{"id":"zero", "armour":0.0, "resistances":{}},
		{"id":"armour500", "armour":500.0, "resistances":{}},
		{"id":"elemental75", "armour":0.0, "resistances":{"fire":0.75,"cold":0.75,"lightning":0.75}},
		{"id":"elemental90", "armour":0.0, "resistances":{"fire":0.9,"cold":0.9,"lightning":0.9}},
		{"id":"elemental_floor", "armour":0.0, "resistances":{"fire":-1.0,"cold":-1.0,"lightning":-1.0}}]:
		var frozen: PackedByteArray = var_to_bytes(spec.resistances)
		var defended: Dictionary = Defense.apply_armour(Damage.resolve(packet,cast.snapshot.modifiers,spec.resistances),spec.armour)
		var settlement: Dictionary = Defense.settle_resolved(defended,0.0,10000.0)
		assert(not defended.has("error") and settlement.ok and frozen == var_to_bytes(spec.resistances))
		targets[spec.id] = {"resistances":spec.resistances,"armour":spec.armour,"resolved":defended,"settlement":settlement}
	return {"packet":packet, "before_defense":before_defense, "zero_target":resolved,"targets":targets}


static func elemental_conversion_examples() -> Dictionary:
	var root: String = "res://docs/qa/v078-gameplay/fixtures/"
	var acceptance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v078-gameplay/reference-acceptance.json"))
	assert(acceptance.get("passed",false), "Passing actual-Main receipt is required before the narrow F8 export")
	var examples: Dictionary = {}
	for name: String in ["zero","cold","cold-lightning","fire-cold-lightning"]:
		var path: String = root + name + ".json"
		var fixture_hash: String = FileAccess.get_sha256(path)
		assert(acceptance.fixtures.get(name+".json") == fixture_hash)
		var raw: Dictionary = Canonical.Rules.decode(JSON.parse_string(FileAccess.get_file_as_string(path)))
		assert(not raw.is_empty() and Canonical.Rules.reason(raw).is_empty() and SourceTree.reason(raw).is_empty())
		var model := Canonical.new()
		model._accept_memory(raw.duplicate(true))
		var stats: Dictionary = model.get_stats()
		var groups: Dictionary = {}
		for group: Dictionary in model.snapshot().skill_groups:
			var current: Dictionary = model.get_group_cast(str(group.id))
			if current.get("ok",false): groups[current.skill_id] = str(group.id)
		var casts: Dictionary = {}
		for skill: String in ["basic","cleave","tornado"]:
			var cast: Dictionary = model.get_basic_cast() if skill == "basic" else model.get_group_cast(str(groups[skill]))
			assert(cast.get("ok",false), "Read-only cast from passing Main fixture: "+name+"/"+skill)
			var hits: Dictionary = {}
			for role: String in cast.packets: hits[role] = _elemental_reference_hit(cast.packets[role],cast)
			casts[skill] = {"compiled":cast,"hits":hits,"summary":Preview.summary(cast),"details":Preview.details(cast)}
		assert(model.save_attempts == 0 and model.snapshot() == raw)
		assert(FileAccess.get_sha256(path) == fixture_hash)
		examples[name] = {"fixture":"docs/qa/v078-gameplay/fixtures/"+name+".json","fixture_sha256":fixture_hash,
			"stats":stats,"talents":raw.talents,"progress":raw.progress,"whole_build_valid":true,
			"actual_main_fixture":true,"read_only_rebuilt":true,"save_attempts":model.save_attempts,"casts":casts}
	var fixture: Script = load("res://tests/fixtures/v078/elemental_conversion_fixture.gd")
	return {"minimum_save_version":Canonical.Rules.VERSION,"source_policy":SourceTree.CURRENT_SAVE_VERSION,
		"equipment_vocabulary":Equipment.CURRENT_VOCABULARY,"class_id":fixture.CLASS_ID,"level":fixture.LEVEL,
		"point_budget":fixture.BUDGET,"normal_route":fixture.NORMAL_ROUTE,"masteries":fixture.MASTERIES,
		"new_complete_ordinary_nodes":["8833","56716"],"new_mastery_effect_ids":[4116,53046],"new_images":[],
		"examples":examples,"source_sha256":SourceTree.Data.SOURCE_SHA256,
		"producer":"Passing actual Main snapshots → Canonical Rules / Model → SkillCompiler → DamageResolver → DefenseRules",
		"scope":"同一23级女巫27点预算、同装备及真实技能组；zero仍保留两notable的30%元素提高和6%命中穿透，未用3点。每次成功不暴击命中，不是DPS",
		"conversion":"先组装全部物理；请求总和不超过100%时依各40%分配，超过时按总额归一。三40%各约三分之一，残余物理显式0；原生元素独立，龙卷60/40是更早组装",
		"lineage":"转换部分保留physical和最终元素来源；每个modifier数组条目只匹配一次，同id不同记录不去重；increased相加，独立MORE各乘；每种最终类型只一条detail",
		"focus":"物理专注对各转换部分×0.96；火焰专注对转火×0.96，对转冰霜及闪电仅×0.80；原生分量按自身来源",
		"penetration":"只按最终命中元素：已有有效抗性先clamp到[-1,0.9]，减6%后仅守-100%下限；零抗→-6%、75→69%、90→84%、原-100保持。目标stats不变，DOT不读",
		"preview":"默认空目标是零抗性，启用穿透的summary含穿透收益；before_defense不含。下表分别显示防御前与零抗性目标结果",
		"bounds":"不新增shock、frost_lock或原生元素专注适配；DOT不转换，既有纯fire独立爆炸保持。现有燃烧只读最终防御前fire合计一次",
		"leech":"全攻击偷取读实际护盾加生命损失；物理攻击偷取仅残余physical实际份额，三40%归一后为0；超杀不增加，DOT不偷取",
		"freeze":"施放时冻结转换、穿透与修饰器；母子箭、返回、符印及燃烧不受之后退款/换装/换辅助回溯，不二次转换",
		"migration":"严格验证并备份旧47原字节后升48；源执行政策48、装备词汇46，不赠点物，不重掷，不改UID；旧文件注入新词汇拒绝",
		"monster_metadata":"当前五个怪物源定义仅刷新源政策45→48的溯源metadata，数值不变，也未获得转换或穿透；旧actor出生快照冻结，不宣称新生actor全字节不变",
		"historical":"旧机制章节保留上批导出快照及数值；其中当前一词指该历史快照当时。当前开放状态以源节点条目、本章和source-tree-coverage.json为准"}


## Exact existing58218; shared by full and bounded reference export.
static func purity_of_flesh_reference() -> Dictionary:
	assert(SourceTree.node_effect("58218").status == "full")
	return {"node_id":"58218","minimum_save_version":60,"previous_save_version":59,
		"backup_suffix":".v59-backup.json","equipment_vocabulary":Canonical.Rules.equipment_vocabulary_for_save_version(60),
		"grants":SourceTree.node_effect("58218").grants,
		"templar_paid_points":10,"templar_route":["61525","63965","14151","27564","17735","58402","6764","14057","9386","5743","58218"]}


## Exact existing27163; node context deliberately excludes identical mana masteries.
static func arcane_will_reference() -> Dictionary:
	assert(SourceTree.node_effect("27163").status == "full")
	return {"node_id":"27163","minimum_save_version":61,"previous_save_version":60,
		"backup_suffix":".v60-backup.json","equipment_vocabulary":Canonical.Rules.equipment_vocabulary_for_save_version(61),
		"grants":SourceTree.node_effect("27163").grants,
		"line_status":SourceLocalization.line_status("Regenerate 5 Mana per second","27163"),
		"witch_paid_points":8,"witch_route":["54447","57226","21678","32210","8948","27929","7503","65203","27163"]}


## Read only the actual paid, saved and successfully cast chain build.
static func chain_shock_build_example() -> Dictionary:
	var fixture := "docs/qa/chain-shock-build/owned.json"
	var acceptance_path := "docs/qa/chain-shock-build/attempt-01.json"
	var acceptance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + acceptance_path))
	assert(acceptance.failures == 0 and acceptance.cases.size() == 9)
	assert(FileAccess.get_sha256("res://" + fixture) == acceptance.owned_sha256)
	var raw: Dictionary = Canonical.Rules.decode(JSON.parse_string(FileAccess.get_file_as_string("res://" + fixture)))
	assert(not raw.is_empty() and Canonical.Rules.reason(raw).is_empty())
	var model := Canonical.new()
	model._accept_memory(raw.duplicate(true))
	var owned: Dictionary = model.get_group_cast(acceptance.group_id)
	assert(owned.ok and JSON.parse_string(JSON.stringify(owned,"",true,true)) == acceptance.owned_cast)
	var rows: Array = []
	for links: Array in [[],["chain_reach"],["shock"],["chain_reach","shock"]]:
		var cast: Dictionary = Compiler.compile_group("chain",model.get_combat_snapshot(),links)
		assert(cast.ok)
		var hits: Array = []
		for packet: Dictionary in cast.packets.bounces:
			hits.append(Damage.resolve(packet,cast.snapshot.modifiers).total)
		rows.append({"links":cast.support_ids,"mana":cast.mana,"cooldown":cast.cooldown,
			"first_range":cast.recipe.first_range,"followup_range":cast.recipe.followup_range,
			"maximum_targets":cast.packets.bounces.size(),"noncritical_before_defense":hits})
	var prices: Dictionary = {}
	for definition: String in ["skill:chain","support:chain_reach","support:shock"]:
		var quote: Dictionary = Canonical.GemTrade.quote("buy",definition)
		assert(quote.ok)
		prices[definition] = quote.cost.calibration_shard
	assert(model.save_attempts == 0 and model.snapshot() == raw)
	return {"fixture":fixture,"fixture_sha256":acceptance.owned_sha256,"acceptance":acceptance_path,
		"acceptance_sha256":FileAccess.get_sha256("res://"+acceptance_path),"rows":rows,"prices":prices,
		"actual_sparse_cases":acceptance.cases.slice(0,4),"skill_id":"chain","support_ids":["chain_reach","shock"],
		"scope":"复用已有合法连锁和远链，只从正式商人购买感电4碎片；44→40，实际入包、装配、保存重载及Main施放通过。编译表为同一真实存档、非暴击、防御前各跳伤害；实战队列另用25%闪电抗性与5护盾，不是DPS或自然敌群密度保证",
		"role":"适合给分散且相邻距离小于286的敌群施加感电，最多5个不同目标；首个目标仍须小于600且可见，每次续跳也检查墙体。距离按目标中心计，不额外加怪物半径",
		"tradeoff":"远链与感电相乘：每跳主命中为原72%，魔力为原138%，原冷却4.5秒；不会新增目标数，触发感电的命中自身不增伤",
		"followup":"感电持续2秒，后续命中承伤提高15%；本构筑连锁冷却4.5秒，应接普攻或另一技能。本次实际奥术飞弹接续验证到期前×1.15、到期后×1；不影响持续伤害，不据此宣称总DPS提升",
		"assembly":"正式商人可购买连锁闪电8、远链4、感电4校准碎片；已有宝石直接复用。主动放同组主槽，远链和感电放该组两个辅助槽，保留三个空槽；可再拆卸，schema61不变",
		"limits":"没有新增宝石、辅助兼容或战斗机制；纯复用已有组合。验证为有限headless场景，未做画面、完整平衡、导出或封包验收"}
