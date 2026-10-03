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
		"current_loot_profile_id": Equipment.CURRENT_LOOT_PROFILE_ID, "save_version": Build.SAVE_VERSION, "fire_encounter": Monsters.fire_encounter_policy(), "current_loot_profile": Equipment.current_loot_profile(),
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
	result["source_tree"] = source_tree_reference()
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
		for tier: Dictionary in family.tiers:
			var instance: Dictionary = {"id": "gear_000001", "base_id": family.eligible_bases[0], "rarity": "magic",
				"item_level": tier.level, "affixes": [{"id": id, "tier": tier.tier, "value": tier.max}]}
			family.formatted_examples.append(Equipment.definition(instance).affix_lines[0])
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
	var fresh: RefCounted = Build.new()
	var full: RefCounted = Build.new()
	for item_id: String in Data.COMBAT_STARTER_ITEMS:
		full.equip(item_id)
	var normal_bow: RefCounted = local_build(_local_instance())
	var rolled_bow: RefCounted = local_build(_local_instance(["whetstone_edge", "tempered_edge", "wellturn", "beatlink"], "rare"))
	var builds: Dictionary = {"fresh": fresh, "full_tornado": full, "local_normal": normal_bow, "local_max": rolled_bow}
	result["configurations"] = {
		"fresh": {"name": "新建角色", "equipped": fresh.equipped.duplicate(), "allocated_nodes": fresh.allocated_nodes.duplicate(), "socketed_jewels": {}, "stats": fresh.get_stats()},
		"full_tornado": {"name": "龙卷机制装备示例", "equipped": full.equipped.duplicate(), "allocated_nodes": full.allocated_nodes.duplicate(), "socketed_jewels": {}, "stats": full.get_stats()}}
	for config: String in ["local_normal", "local_max"]:
		var build: RefCounted = builds[config]
		result.configurations[config] = {"name": "普通白蜡长弓" if config == "local_normal" else "白蜡长弓 · 双局部前缀上限示例",
			"equipped": build.equipped.duplicate(), "allocated_nodes": build.allocated_nodes.duplicate(), "socketed_jewels": {},
			"stats": build.get_stats(), "equipment_instances": build.equipment_instances.duplicate(true),
			"weapon_definition": build.get_item_definition(build.equipped.weapon)}
	for id: String in Data.SKILLS:
		var skill: Dictionary = Data.SKILLS[id].duplicate(true)
		skill["compatible_supports"] = Supports.supports_for_skill(id)
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
			if not is_equal_approx(_direct_total(before), _direct_total(after)):
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
		var example_wave: int = target_wave if id == target_id else 1
		template["example_wave"] = example_wave
		template["runtime_example"] = Monsters.make_enemy(1, id, example_wave, Vector2.ZERO, context)
		template["contact_components"] = Monsters.contact_components(template.runtime_example)
		template["mechanism_text"] = Monsters.mechanism_text(template.runtime_example)
		template["telegraph_policy"] = Monsters.telegraph_policy(template.runtime_example)
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
		"slots":slots,"gem_definitions":GemCatalogData.definitions(),"default_build":state.snapshot(),"default_stats":state.get_stats(),"default_casts":casts,"five_link_example":support_cast_brief(five),
		"gem_reward":{"eligible_root_kill_interval":30,"definition_count":24,"uniform_selection":true,"level":1,"quality":0,"duplicate_definitions_have_distinct_uid":true,"failed_admission_restores_rng":true},
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
static func crafting_examples() -> Dictionary:
	var instance: Dictionary = _local_instance(["whetstone_edge"], "magic")
	var build: RefCounted = local_build(instance)
	assert(build.unequip("weapon"))
	var cost: int = int(Craft.recalibrate_plan(instance, 0).cost[Craft.MATERIAL_ID])
	build.crafting.materials[Craft.MATERIAL_ID] = cost
	var snapshot: Dictionary = build._snapshot()
	var context: Dictionary = {"revision": 0, "materials": snapshot.crafting.materials.duplicate(true),
		"inventory": snapshot.inventory.duplicate(true), "equipment_instances": snapshot.equipment_instances.duplicate(true),
		"equipped": snapshot.equipped.duplicate(true), "backpack_positions": snapshot.backpack_positions.duplicate(true), "save_writable": true}
	var metadata: Dictionary = Craft.metadata()
	metadata["integration_status"] = "implemented"
	var result: Dictionary = {Craft.MATERIAL_ID: {"name": "校准碎片", "kind": "material",
		"description": "回收背包中的随机魔法、稀有装备获得。用于重掷已有词缀数值；没有额外击杀掉落或升级赠送。",
		"maximum": Build.MAX_CRAFT_MATERIALS, "rules": metadata,
		"max_revision": Build.MAX_CRAFT_REVISION, "save_version": Build.SAVE_VERSION}}
	for operation: String in ["salvage", "recalibrate"]:
		var quote: Dictionary = CraftPlanner.quote(context, operation, instance.id)
		var planned: Dictionary = CraftPlanner.plan(context, quote, 20261002)
		assert(quote.ok and planned.ok)
		var candidate: Dictionary = snapshot.duplicate(true)
		for field: String in ["inventory", "equipment_instances", "equipped", "backpack_positions"]:
			candidate[field] = planned.candidate[field].duplicate(true)
		candidate.crafting = {"materials": planned.candidate.materials.duplicate(true), "revision": planned.candidate.revision}
		assert(not build._validate_snapshot(candidate).is_empty(), "Craft reference must validate the full build including jewels and layout")
		result[operation] = {"name": "回收" if operation == "salvage" else "数值校准", "kind": "operation",
			"description": "消耗此装备，获得校准碎片。" if operation == "salvage" else "消耗校准碎片，重掷现有词缀的整数数值；结果可能降低或不变。",
			"rules_version": Craft.RULES_VERSION, "eligible_base_ids": metadata.base_ids,
			"example": {"source": instance.duplicate(true), "before_definition": Equipment.definition(instance),
				"quote": quote, "balance_before": cost, "balance_after": planned.candidate.materials[Craft.MATERIAL_ID],
				"revision_before": 0, "revision_after": planned.candidate.revision,
				"after_instance": planned.candidate.equipment_instances.get(instance.id, {}),
				"after_definition": Equipment.definition(planned.candidate.equipment_instances.get(instance.id, {})),
				"full_candidate_valid": true, "example_seed": 20261002}}
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
	metadata["integrated_templates"] = Monsters.TELEGRAPH_TEMPLATES.keys()
	metadata["policy"] = policy
	metadata["description"] = "灰烬守卫以固定范围重击代替接触攻击。先锁定地面位置，再结算一次；移出范围可以躲避。"
	metadata["example"] = {"source": enemy, "source_wave": enemy.wave, "start": admitted.attack,
		"halfway": halfway, "event": event, "recovery": runtime.state_for(1), "cases": cases,
		"player_radius": Arena.PLAYER_RADIUS, "move_speed": fresh.get_stats().move_speed,
		"shield_before": 10.0, "health_before": 100.0, "armor_instance": armor,
		"armor_definition": Equipment.definition(armor), "movement_assumption": "straight_unobstructed_motion_from_warning_start"}
	return {TelegraphProfiles.PROFILE_ID: metadata}


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
			var applied: Dictionary = EncounterCompiler.apply_to_enemy(before,compiled.profile)
			assert(applied.ok)
			definition.examples[template] = {"before":before,"after":applied.enemy}
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
