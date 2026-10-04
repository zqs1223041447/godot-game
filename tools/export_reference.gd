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
const GemCatalogData = preload("res://scripts/items/gem_catalog.gd")
const EquipmentSlotsData = preload("res://scripts/items/equipment_slots.gd")
const Flasks = preload("res://scripts/items/flask_catalog.gd")
const FlaskRuntime = preload("res://scripts/combat/flask_runtime.gd")
const FlaskModifiers = preload("res://scripts/combat/flask_modifier_rules.gd")
const Town = preload("res://scripts/town/town_catalog.gd")
const Maps = preload("res://scripts/world/map_catalog.gd")
const MapRules = preload("res://scripts/world/map_compiler.gd")
const CampLayoutData=preload("res://scripts/world/map_camp_layout.gd")
const MapGeometryData = preload("res://scripts/world/map_geometry.gd")
const MapDefense = preload("res://scripts/world/map_defense_rules.gd")
const MapBosses=preload("res://scripts/monsters/map_boss_profiles.gd")
const MapAdmission=preload("res://scripts/world/map_admission.gd")
const MonsterRuntime=preload("res://scripts/monsters/monster_runtime.gd")
const AttackRules = preload("res://scripts/combat/attack_hit_rules.gd")

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
	result["map_camps"]={"old_garden":CampLayoutData.layout("old_garden",Arena.ARENA).landmarks,"broken_ruins":CampLayoutData.layout("broken_ruins",Arena.ARENA).landmarks}
	result["normal_journey"] = normal_journey_examples()
	result["normal_gem_trading"]={"offers":Canonical.GemTrade.offers(),"recycle_credit":Canonical.GemTrade.RECYCLE_CREDIT,"currency":Canonical.GemTrade.MATERIAL_ID,"location":"normal_town","level":1,"quality":0,"recycle_location":"bag","schema":Canonical.Rules.VERSION,"test_supply_separate":true,"pricing":"初版可调整预算；每次无词缀地图净得4碎片"}
	result["source_tree"] = source_tree_reference()
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
			var normal: Dictionary = _local_instance()
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
		"gem_reward":{"eligible_root_kill_interval":30,"definition_count":GemCatalogData.definitions().size(),"uniform_selection":true,"level":1,"quality":0,"duplicate_definitions_have_distinct_uid":true,"failed_admission_restores_rng":true},
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
		"description": "回收背包中的随机魔法、稀有装备获得。真实堆叠物品，用于校准、赋魔、升格、补缀与重铸；待安置碎片不能直接消费。",
		"maximum": Canonical.ShardCatalog.INVENTORY_LIMIT, "rules": metadata,
		"max_revision": Canonical.Rules.MAX_SERIAL, "save_version": Canonical.Rules.VERSION}}
	for operation: String in Craft.operation_ids():
		var instance: Dictionary = _local_instance(["whetstone_edge"], "magic")
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
		result[operation] = {"name": presentation.label, "kind": "operation",
			"description": presentation.description, "risk": presentation.risk,
			"rule": metadata.operations[operation], "rules_version": Craft.CURRENT_RULES_VERSION, "eligible_base_ids": metadata.base_ids,
			"example": {"source": instance.duplicate(true), "before_definition": Equipment.definition(instance),
				"quote": quote, "balance_before": 100, "balance_after": planned.candidate.materials[Craft.MATERIAL_ID],
				"revision_before": 0, "revision_after": planned.candidate.revision,
				"after_instance": planned.candidate.equipment_instances.get(instance.id, {}),
				"after_definition": Equipment.definition(planned.candidate.equipment_instances.get(instance.id, {})),
				"full_candidate_valid": true, "save_version": candidate.version, "example_seed": 20261003}}
	return result

## Hand-authored legal examples derive every roll from the live family tiers.
## No random generator, save path, migration, or player-owned build is accessed.
static func _local_instance(affix_ids: Array = [], rarity: String = "normal") -> Dictionary:
	var affixes: Array = []
	var level: int = Equipment.MIN_ITEM_LEVEL
	for id: String in affix_ids:
		var family: Dictionary = Equipment.affix_definition(id)
		var tier: Dictionary = family.tiers.back()
		level = maxi(level, int(tier.level))
		affixes.append({"id": id, "tier": tier.tier, "value": tier.max})
	return {"id": "gear_000001", "base_id": WeaponLocal.BASE_ID, "rarity": rarity, "item_level": level, "affixes": affixes}

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
	metadata["description"] = "灰烬守卫以固定范围重击代替接触攻击。先锁定地面位置，再结算一次；移出范围可以躲避。"
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
	return examples


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
