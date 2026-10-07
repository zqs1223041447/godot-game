extends SceneTree
## One bounded v93 export. No Main, old exporter, maps, RNG, art or save writes.
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Supply = preload("res://scripts/items/chaos_resistance_affix_profile.gd")
const Fixture = preload("res://tests/chaos_resistance_equipment_test.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Profiles = preload("res://scripts/monsters/telegraph_profiles.gd")
const Maps = preload("res://scripts/world/map_catalog.gd")
const OUTPUT := "res://docs/qa/v093-reference/chaos-defense-fragment.json"


static func clean(value: Variant) -> Variant:
	if value is Vector2: return [value.x, value.y]
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[str(key)] = clean(value[key])
		return result
	if value is Array:
		var result := []
		for item: Variant in value: result.append(clean(item))
		return result
	return value


static func evidence(path: String) -> Dictionary:
	assert(FileAccess.file_exists("res://" + path), "Missing reference input: " + path)
	return {"path": path, "sha256": FileAccess.get_sha256("res://" + path)}


static func build_snapshot() -> Dictionary:
	var fixture_source := evidence("docs/qa/v093-integration/equipped-fixture.json")
	var main_source := evidence("docs/qa/v093-integration/main-result.json")
	var run_source := evidence("docs/qa/v093-integration/main-run.json")
	var accepted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + main_source.path))
	var run: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + run_source.path))
	assert(int(accepted.checks) == 130 and int(accepted.failures) == 0 and accepted.labels.is_empty())
	assert(int(run.exit_code) == 0)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + fixture_source.path))
	var candidate: Dictionary = Model.Rules.decode(raw)
	assert(not candidate.is_empty() and Model.Rules.reason(candidate, Source.reason).is_empty())
	assert(Model.Rules.VERSION == 51 and Equipment.CURRENT_VOCABULARY == 51 and Source.CURRENT_SAVE_VERSION == 49)
	var rings := []
	for uid: String in accepted.rings:
		var item: Dictionary = candidate.items[uid].payload
		assert(item == Fixture.legal_ring(uid) and Equipment.validate_instance(item))
		assert(candidate.locations[uid].kind == "equipment" and candidate.locations[uid].slot_id in ["ring_1", "ring_2"])
		rings.append({"location": candidate.locations[uid], "instance": item, "definition": Equipment.definition(item)})
	assert(rings.size() == 2 and rings[0].location.slot_id != rings[1].location.slot_id)
	var stats := Model._stats_for(candidate)
	var equipped_profile := Defense.chaos_resistance_profile(stats)
	assert(equipped_profile.ok and equipped_profile.effective == 0.5)
	var family := Equipment.affix_definition("ring_voidward")
	family.pools = ["build_nine_slot_v51"]
	family.eligible_bases = [Supply.RING_BASE_ID]
	family.formatted_examples = []; family.formatted_ranges = []
	family.affected_skills = []; family.other_consumers = []
	for tier: Dictionary in family.tiers:
		var item := Fixture.legal_ring("gear_000721", tier.tier, tier.max)
		assert(Equipment.validate_instance(item))
		family.formatted_examples.append(Equipment.definition(item).affix_lines[0])
		family.formatted_ranges.append({"min": Equipment.affix_display({"id":"ring_voidward","tier":tier.tier,"value":tier.min}).value_text,
			"max": Equipment.affix_display(item.affixes[0]).value_text})
	var eligible := []
	for id: String in Equipment.all_affix_ids():
		if Equipment.family_eligible(id, Supply.RING_BASE_ID): eligible.append(id)
	var monster := Monsters.TEMPLATES.chaos_guard.duplicate(true)
	var enemy := Monsters.make_enemy(1, "chaos_guard", 5, Vector2.ZERO, "demo")
	assert(not enemy.is_empty() and enemy.resistances.chaos == 0.25)
	monster.example_wave = 5; monster.runtime_example = enemy
	monster.contact_components = Monsters.contact_components(enemy)
	monster.mechanism_text = Monsters.mechanism_text(enemy)
	monster.telegraph_policy = Monsters.telegraph_policy(enemy)
	monster.attack_reference = "locked_circle_chaos"
	monster.defense_profile = {"effective_resistances": enemy.resistances}
	var attack := Profiles.metadata(Profiles.CHAOS_GUARD)
	attack.id = "locked_circle_chaos"; attack.name = monster.telegraph_policy.name
	attack.policy = monster.telegraph_policy; attack.integrated_templates = ["chaos_guard"]
	attack.description = "只在明确选择蚀影巡逻后替换原重壳体名额；锁定玩家起手位置，完整预警后结算一次纯混沌命中。"
	var special := Maps.SPECIAL.chaos_patrol.duplicate(true)
	special.id = "chaos_patrol"; special.completion_reward_bonus = 0
	special.reward_description = "测试模式不增加完成奖励"
	var normal_special := {}
	for entry: Dictionary in Maps.options(false).special_modifiers:
		if entry.id == "chaos_patrol": normal_special = entry
	assert(int(normal_special.completion_reward_bonus) == 2)
	var examples := []
	for wave: int in [5, 10]:
		var sample := Monsters.make_enemy(1, "chaos_guard", wave, Vector2.ZERO, "demo")
		var components := {"chaos": float(Monsters.contact_components(sample).chaos) * float(Profiles.CHAOS_GUARD.damage_multiplier)}
		var settlements := {}
		for resistance: float in [0.0, 0.25, 0.5]:
			var settlement := Defense.incoming_source_hit(components, {"chaos_resistance":resistance}, 0.0, 100.0)
			assert(settlement.ok)
			settlements[str(int(resistance * 100))] = settlement
		examples.append({"wave":wave,"source_damage":sample.damage,"packet_components":components,"settlements":settlements})
	var caps := []
	for value: float in [-0.2, 0.0, 0.25, 0.5, 0.75, 1.0]: caps.append(Defense.chaos_resistance_profile({"chaos_resistance":value}))
	var rule := {"metadata":Defense.chaos_resistance_metadata(),"save_version":Model.Rules.VERSION,
		"source_policy":Source.CURRENT_SAVE_VERSION,"equipment_vocabulary":Equipment.CURRENT_VOCABULARY,
		"base_id":Supply.RING_BASE_ID,"affix_id":"ring_voidward","pool_id":"build_nine_slot_v51",
		"current_loot_profile_id":Equipment.CURRENT_LOOT_PROFILE_ID,"ring_slots":["ring_1","ring_2"],
		"equipped_profile":equipped_profile,"rings":rings,"cap_examples":caps,"hit_examples":examples,
		"actual_main_report":main_source,"actual_main_run":run_source,"actual_main_fixture":fixture_source,
		"actual_main_checks":accepted.checks,"actual_main_receipts":accepted.receipts,"normal_special":normal_special,
		"scope":"Read-only lawful actual-Main fixture and its receipts, plus bounded catalog/DefenseRules scalar examples. No Main, map generation, new random gear, saves, images or source-tree coverage export."}
	assert(FileAccess.get_sha256("res://" + fixture_source.path) == fixture_source.sha256)
	return {"game_version":ProjectSettings.get_setting("application/config/version"),"save_version":Model.Rules.VERSION,
		"current_loot_profile_id":Equipment.CURRENT_LOOT_PROFILE_ID,"current_loot_profile":Equipment.current_loot_profile(),
		"new_pool":Equipment.pool_profile("build_nine_slot_v51"),"affix":family,"ring_eligible_affixes":eligible,
		"monster":monster,"attack":attack,"special":special,"chaos_defense":rule}


func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	assert(isolated.begins_with("/tmp/godot-v093-reference-") and OS.get_user_data_dir().begins_with(isolated + "/"))
	assert(not FileAccess.file_exists(OUTPUT), "Keep the original bounded export evidence")
	var result := build_snapshot()
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(clean(result), "\t", true, true) + "\n"); file.close()
	print("Chaos defense fragment: lawful Main130/0 and two magic single-suffix rings reused read-only; no full export, Main, maps, RNG, save or art")
	quit(0)
