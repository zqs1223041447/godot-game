extends SceneTree
## Offline reference export. Only fresh in-memory builds; never loads/saves user data.
const Data = preload("res://scripts/game_data.gd")
const Build = preload("res://scripts/build_state.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Supports = preload("res://scripts/combat/support_catalog.gd")
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
			var combinations: Array = [[]]
			if not skill.compatible_supports.is_empty():
				for support_id: String in skill.compatible_supports:
					combinations.append([support_id])
				combinations.append(skill.compatible_supports.duplicate())
			skill.examples[config] = []
			for combination: Array in combinations:
				var cast: Dictionary = Compiler.compile_skill(id, build.get_combat_snapshot(), combination)
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
		template["defense_profile"] = Defense.defense_profile(template.runtime_example.defense_stats, "monster")
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
	assert(Equipment.validate_instance(instance), "Reference bow must be a legal real instance")
	var build: RefCounted = Build.new()
	build.equipment_instances = {instance.id: instance.duplicate(true)}
	build.inventory.append(instance.id)
	build.next_equipment_id = Equipment.serial_from_id(instance.id) + 1
	build._sync_backpack()
	var equipped_ok: bool = build.equip(instance.id)
	assert(equipped_ok, "Reference bow must equip through BuildState")
	assert(not build._validate_snapshot(build._snapshot()).is_empty(), "Reference build must satisfy actual save schema without writing a save")
	return build

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
	return value
