extends SceneTree
## Offline reference export. Only fresh in-memory builds; never loads/saves user data.
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
const Maps = preload("res://scripts/world/map_catalog.gd")
const MapRules = preload("res://scripts/world/map_compiler.gd")
const CampLayoutData=preload("res://scripts/world/map_camp_layout.gd")
const CampAdmissionData=preload("res://scripts/world/map_camp_admission.gd")
const SunwellRoster=preload("res://scripts/world/sunwell_roster_rules.gd")
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
const SourceCoverage = preload("res://tools/export_source_execution_coverage.gd")

func _initialize() -> void:
	var target: String = "res://docs/reference/catalog.json"
	if not OS.get_cmdline_user_args().is_empty():
		target = OS.get_cmdline_user_args()[0]
	var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		push_error("Cannot open reference output: " + target)
		quit(1)
		return
	var content: Dictionary = collect()
	file.store_string(JSON.stringify(clean(content), "\t", true, true) + "\n")
	file.close()
	print("Reference exported: " + target)
	if target == "res://docs/reference/catalog.json":
		var coverage: Dictionary = SourceCoverage.build_report()
		assert(not coverage.is_empty() and coverage.integrity.ok)
		var coverage_file: FileAccess = FileAccess.open(SourceCoverage.OUTPUT_PATH, FileAccess.WRITE)
		if coverage_file == null:
			push_error("Cannot write source tree coverage report")
			quit(1)
			return
		coverage_file.store_string(SourceCoverage.serialize_report(coverage))
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
	result["monster_attacks"] = telegraph_examples()
	result["encounters"] = encounter_examples()
	result["canonical"] = canonical_examples()
	result["currencies"] = currency_examples()
	result["flasks"] = flask_examples()
	result["town_maps"] = town_map_examples()
	result["map_camps"]={}
	for map_id:String in Maps.MAPS:
		var camp_layout:Dictionary=CampLayoutData.layout(map_id,Arena.ARENA)
		assert(camp_layout.ok)
		result.map_camps[map_id]=camp_layout.landmarks
	result["normal_journey"] = normal_journey_examples()
	result["sunwell_terrace"] = sunwell_examples()
	result["burning"] = burning_examples()
	result["ember_proliferation"] = ember_proliferation_examples()
	result["shock"] = shock_examples()
	result["source_fire_dot"] = source_fire_dot_examples()
	result["source_faster_burn"] = source_faster_burn_examples()
	result["forgeblade"] = forgeblade_examples()
	result["melee_basic"] = melee_basic_examples(result.forgeblade)
	result["normal_gem_trading"]={"offers":Canonical.GemTrade.offers(),"recycle_credit":Canonical.GemTrade.RECYCLE_CREDIT,"currency":Canonical.GemTrade.MATERIAL_ID,"location":"normal_town","level":1,"quality":0,"recycle_location":"bag","schema":Canonical.Rules.VERSION,"test_supply_separate":true,"pricing":"初版可调整预算；每次无词缀地图净得4碎片"}
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
			var combinations: Array = support_combinations(skill.compatible_supports)
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
		var mechanism: Dictionary = Registry.get_definition(id)
		# No source-game names, prose, art, or layout are redistributed.
		var refs: Array = []
		for source: Dictionary in mechanism.get("source_refs", []):
			refs.append({"modifier_id": source.get("modifier_id"), "target_stat": source.get("target_stat"),
				"adaptation": source.get("adaptation"), "source_value": source.get("source_value"),
				"scale": source.get("scale"), "reference_base": source.get("reference_base")})
		mechanism["source_refs"] = refs
		mechanism["description"] = Passives.describe_stats(mechanism.stats)
		result.mechanisms[id] = mechanism
	for id: String in Monsters.TEMPLATES:
		var template: Dictionary = Monsters.TEMPLATES[id].duplicate(true)
		var context: String = "level_boss" if template.rarity == "boss" else "demo"
		var example_wave: int = target_wave if id == target_id else int(Monsters.ELEMENTAL_ENCOUNTERS[id].minimum_wave) if Monsters.ELEMENTAL_ENCOUNTERS.has(id) else 1
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
			choices[str(int(choice.effect))] = SourceLocalization.display_lines(choice.stats)
			raw_lines.append_array(choice.stats)
		for raw_line: String in raw_lines:
			if not source_lines.has(raw_line):
				source_lines[raw_line] = {"text": SourceLocalization.display_lines([raw_line]),
					"status": SourceLocalization.line_status(raw_line)}
		var partition_label: String = "标准主树" if node.partition == "standard" else "扩展珠宝分区 · 仅浏览" if node.partition == "expansion" else SourceLocalization.partition_label(node.partition)
		partitions[node.partition] = partition_label
		nodes[id] = {"name": SourceLocalization.node_name(id),
			"stats": SourceLocalization.display_lines(node.stats),
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
		var geometry:=MapGeometryData.new();geometry.configure(map.id,Arena.ARENA)
		var layout:Dictionary=geometry.snapshot();var walls:Array=[]
		for wall:Rect2 in layout.walls:walls.append({"position":wall.position,"size":wall.size})
		examples[map.id]={"compiled":compiled.profile,"special_replacements":replacements,
			"geometry":{"bounds":{"position":layout.bounds.position,"size":layout.bounds.size},"walls":walls,"spawn":layout.spawn,
				"collision":"radius_expanded_sweep_slide","navigation":"shared_radius_visibility_graph","projectile_wall_end":"terrain_collision",
				"wall_triggers_natural_end":false,"area_line_of_sight":true}}
		if layout.has("obstacle_style"):
			examples[map.id].geometry.obstacle_style=layout.obstacle_style
			examples[map.id].geometry.entry=CampLayoutData.layout(map.id,Arena.ARENA).landmarks.entry
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
		"mode":"optional_town_test","normal_save":"user://build_save.json","test_save":"user://town_test_build_save.json",
		"clone_policy":"explicit_first_entry_only","supply_setting":"testing/town_supply_enabled","map_reward_bonus":false,
		"save_version":Canonical.Rules.VERSION,"retired_profile_writes":false,"map_runtime_persistent":false,
		"reserved_character_key":"C","legacy_C_binding":"unbound_with_notice_and_raw_byte_backup"}


static func crafting_examples() -> Dictionary:
	var metadata: Dictionary = Craft.metadata()
	metadata["integration_status"] = "implemented"
	var result: Dictionary = {Craft.MATERIAL_ID: {"name": "校准碎片", "kind": "material",
		"description": "回收背包中的随机魔法、稀有装备获得。真实堆叠物品，用于校准、赋魔、升格、补缀、重铸与定向重铸；待安置碎片不能直接消费。",
		"maximum": Canonical.ShardCatalog.INVENTORY_LIMIT, "rules": metadata,
		"max_revision": Canonical.Rules.MAX_SERIAL, "save_version": Canonical.Rules.VERSION}}
	for operation: String in Craft.operation_ids():
		var instance: Dictionary = _local_instance(["whetstone_edge"], "magic")
		if Craft.Targeted.operation_ids().has(operation) and operation != "targeted_reforge_damage":
			instance = _local_instance(["global_critical_chance"], "magic", "wayglass_token")
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
	return {"mana": cast.mana, "cooldown": cast.cooldown, "initial_count": cast.initial_count,
		"recipe": cast.recipe.duplicate(true), "summary": Preview.summary(cast), "details": Preview.details(cast)}

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


static func sunwell_examples()->Dictionary:
	var map_id:String="sunwell_terrace"
	var layout:Dictionary=CampLayoutData.layout(map_id,Arena.ARENA).landmarks
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
