extends SceneTree
## Path-costed, equal-point budget regressions against real runtime stat/damage APIs.
## These samples and explicit caps are guardrails, not an exhaustive gameplay proof.
const Adapter = preload("res://scripts/mechanics/passive_balance_adapter.gd")
const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const Passives = preload("res://scripts/passive_data.gd")
const Model = preload("res://scripts/build_state.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check_source_and_config()
	_check_graph_placement()
	_check_semantics_and_caps()
	_check_path_budgets()
	_check_monster_budget()
	print("Passive source and balance: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.00002, "%s %.8f / %.8f" % [label, value, expected])

func _read(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _check_source_and_config() -> void:
	var config: Dictionary = _read(Adapter.PATH)
	_expect(Adapter.validation_errors().is_empty(), "Final source-calibrated config validates")
	var source: Dictionary = _read("res://data/poe_passive_registry.json")
	_expect(source.source.commit == config.source.commit and source.source.data_sha256 == config.source.data_sha256, "Source and runtime have same immutable provenance")
	_expect(source.coverage.source_records == 3390 and source.coverage.source_mastery_effects_deduplicated == 353, "Pinned source coverage stays explicit")
	_expect(source.modifiers.size() == 2974, "Every distinct source expression has a record")
	var index: Dictionary = {}
	var supported: int = 0
	var unsupported: int = 0
	var occurrences: int = 0
	for modifier: Dictionary in source.modifiers:
		_expect(not index.has(modifier.modifier_id), "Source modifier identity unique")
		index[modifier.modifier_id] = modifier
		occurrences += modifier.source_refs.size()
		if modifier.status == "supported_archetype":
			supported += 1
			_expect(source.families.has(modifier.family), "Supported source family is explicit")
		else:
			unsupported += 1
			_expect(modifier.status == "unsupported" and not str(modifier.reason).is_empty(), "Every unsupported rule has a reason")
		_expect(not modifier.has("icon") and not modifier.has("raw_text") and not modifier.has("name"), "Registry excludes source art and creative names/prose")
	_expect(supported == 98 and unsupported == 2876 and occurrences == 5357, "Complete supported/unsupported coverage reconciliation")
	for id: String in config.definitions:
		for ref: Dictionary in config.definitions[id].source_refs:
			_expect(index.has(ref.modifier_id), "Every runtime grant traces to fixed source modifier")
			var record: Dictionary = index[ref.modifier_id]
			_expect(record.status == "supported_archetype" and record.source_value == ref.source_value and record.source_mode == ref.source_mode, "Source values preserved independently of game calibration")
			_expect(record.source_refs.has(ref.source_node), "Exact source node and stat index retained")
	for field: String in ["definitions", "node_overrides", "player_passive_caps"]:
		var invalid: Dictionary = config.duplicate(true)
		invalid[field] = []
		_expect(not Adapter.validate_config(invalid).is_empty(), "Invalid schema rejected: " + field)
	var changed: Dictionary = config.duplicate(true)
	changed.definitions.ember_power.stats.damage = 10000.0
	_expect(not Adapter.validate_config(changed).is_empty(), "Numeric drift away from explicit source formula fails closed")
	changed = config.duplicate(true)
	changed.definitions.ember_power.stats.projectile_count = 20.0
	_expect(not Adapter.validate_config(changed).is_empty(), "Arbitrary projectile count cannot sneak in as a passive")
	changed = config.duplicate(true)
	changed.definitions.ember_power.source_refs[0].source_mode = "more"
	_expect(not Adapter.validate_config(changed).is_empty(), "More cannot be mislabeled as supported increased")

func _check_graph_placement() -> void:
	var nodes: Dictionary = Passives.get_nodes()
	_expect(nodes.size() == 181 and Passives.get_edges().size() == 360, "Original tree topology preserved")
	var distance: Dictionary = {"origin": 0}
	var queue: Array[String] = ["origin"]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for next: String in Passives.get_neighbors(id):
			if not distance.has(next):
				distance[next] = int(distance[id]) + 1
				queue.append(next)
	var placements: Dictionary = {}
	for id: String in Adapter.node_overrides():
		_expect(nodes.has(id) and nodes[id].type == "small", "Only explicit small nodes replaced: " + id)
		var mechanism: String = Adapter.node_override(id)
		_expect(Passives.get_node_mechanisms(id) == [mechanism], "Replacement really reaches live tree: " + id)
		_expect(distance[id] == int(id.split("_")[1]) and distance[id] >= 3, "Real path cost includes all travel nodes: " + id)
		placements[mechanism] = int(placements.get(mechanism, 0)) + 1
	_expect(placements.size() == 4, "Four new typed mechanisms placed")
	for mechanism: String in placements:
		_expect(placements[mechanism] == 3, "Scoped increase appears exactly three times: " + mechanism)
		_expect(not Registry.is_supported(mechanism, "monster"), "Unsupported monster scopes are explicit player-only")

func _check_semantics_and_caps() -> void:
	var stats: Dictionary = {"global_increased": 0.1, "projectile_increased": 0.2, "elemental_increased": 0.3, "area_increased": 0.4}
	var modifiers: Array = Combat.modifiers(stats)
	var arrow: Dictionary = Damage.packet({"fire": 100.0}, ["projectile"], "test")
	var explosion: Dictionary = Damage.packet({"fire": 100.0}, ["area", "explosion"], "test")
	_near(Damage.resolve(arrow, modifiers).total, 160.0, "Global/projectile/elemental increases ADD, no multiplicative inflation")
	_near(Damage.resolve(explosion, modifiers).total, 180.0, "Projectile increase excluded from independent explosion")
	modifiers.append({"id": "test_more", "mode": "more", "value": 0.5})
	_near(Damage.resolve(arrow, modifiers).total, 240.0, "Explicit more remains a distinct multiplier")
	var large: Dictionary = {}
	for stat: String in Adapter.player_caps():
		large[stat] = 1000000.0
	var copy: Dictionary = large.duplicate()
	var capped: Dictionary = Adapter.cap_player_passives(large)
	_expect(large == copy and capped == Adapter.player_caps(), "Caps apply to a fresh aggregate copy")
	for definition: Dictionary in Adapter.definitions().values():
		_expect(not definition.stats.has("projectile_count"), "Passive bundles never multiply carrier count")
		_expect(not definition.stats.has("more"), "No source more mechanism is silently flattened into additive grants")

func _check_path_budgets() -> void:
	var fixture: Dictionary = _read("res://tests/passive_balance_cases.json")
	_expect(fixture.policy_version == Adapter.policy_version(), "Case snapshot belongs to final calibration")
	_expect(fixture.cases.size() == 240, "Five tiers with 48 equal-point paths each")
	var peaks: Dictionary = {}
	for sample: Dictionary in fixture.cases:
		var build = Model.new()
		build.equipped.clear()
		build.level = 1000
		build.talent_points = Model.BASE_TALENT_POINTS + build.level - 1
		for id: String in sample.allocation_order:
			_expect(build.allocate_passive(id), "Legal path allocation: " + sample.id + "/" + id)
		_expect(build.allocated_nodes.size() == int(sample.points) + 1, "Equal-point cost includes travel/socket nodes")
		var result: Dictionary = _metrics(build)
		var bounds: Dictionary = fixture.bounds[str(int(sample.points))]
		for key: String in result:
			_near(result[key], sample.metrics[key], "Runtime matches independent budget calculation: " + sample.id + "/" + key)
			if bounds.has(key):
				_expect(float(result[key]) <= float(bounds[key]) + 0.00002, "Measured build remains inside declared envelope: " + sample.id + "/" + key)
		var point_key: String = str(int(sample.points))
		if not peaks.has(point_key):
			peaks[point_key] = {}
		for key: String in result:
			peaks[point_key][key] = maxf(float(peaks[point_key].get(key, 0.0)), float(result[key]))
	print("PASSIVE_BUDGET_PEAKS=" + JSON.stringify(peaks))

func _metrics(build: RefCounted) -> Dictionary:
	var s: Dictionary = build.get_stats()
	var snapshot: Dictionary = build.get_combat_snapshot()
	var basic: Dictionary = Damage.packet({"physical": float(s.damage)}, ["hit", "attack", "projectile"], "basic")
	var elemental: Dictionary = Damage.packet({"lightning": float(s.damage)}, ["hit", "spell", "projectile"], "bolt")
	return {"basic_dps": float(Damage.resolve(basic, snapshot.modifiers).total) / 18.0 * float(s.attack_speed) / 1.7,
		"tornado_arrow": float(Damage.resolve(Combat.tornado_packet(snapshot, "parent"), snapshot.modifiers).total) / 18.0,
		"elemental_projectile": float(Damage.resolve(elemental, snapshot.modifiers).total) / 18.0,
		"explosion": float(Damage.resolve(Combat.tornado_packet(snapshot, "explosion"), snapshot.modifiers).total) / (18.0 * 0.9),
		"ehp": (float(s.max_health) + float(s.max_shield)) / 180.0,
		"movement": float(s.move_speed) / 240.0, "mana_sustain": float(s.mana_regen) / 9.0, "shield_recovery": float(s.shield_regen) / 13.0}

func _check_monster_budget() -> void:
	var ids: Array[String] = Registry.get_ids("monster")
	_expect(ids.size() == 13, "Only the thirteen fully implemented flat bundles are monster-eligible")
	var maxima: Dictionary = {"damage": 0.0, "speed": 0.0, "ehp": 0.0, "attack_speed": 0.0}
	for template: String in ["crawler", "skitter", "brute"]:
		var baseline: Dictionary = Monsters.make_enemy(1, template, 1, Vector2.ZERO, "ordinary", "rare", [])
		for first: String in ids:
			for second: String in ids:
				var enemy: Dictionary = Monsters.make_enemy(2, template, 1, Vector2.ZERO, "ordinary", "rare", [first, second])
				_expect(not enemy.is_empty(), "Two supported full bundles resolve for monsters")
				if enemy.is_empty():
					continue
				for stat: String in ["damage", "speed", "attack_speed"]:
					var ratio: float = float(enemy[stat]) / float(baseline[stat])
					maxima[stat] = maxf(float(maxima[stat]), ratio)
					_expect(ratio <= 1.5, "Two-bundle monster offensive/mobility budget bounded")
				var ehp: float = (float(enemy.max_health) + float(enemy.max_shield)) / float(baseline.max_health)
				maxima.ehp = maxf(float(maxima.ehp), ehp)
				_expect(ehp <= 1.5, "Two-bundle monster EHP budget bounded against equal rarity/species")
	print("MONSTER_PASSIVE_BUDGET_PEAKS=" + JSON.stringify(maxima))
