extends SceneTree
## Standalone shared-mechanism contract; no arena or other test runner required.

const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const Passives = preload("res://scripts/passive_data.gd")
const Model = preload("res://scripts/build_state.gd")
const Items = preload("res://scripts/game_data.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_source_tree()
	_check_actor_contract()
	_check_identifiers()
	_check_live_definition()
	_check_invalid_tuning()
	_check_save_schema()
	_check_scoped_damage()
	print("Shared mechanism registry: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(is_equal_approx(value, expected), "%s (actual %.6f, expected %.6f)" % [label, value, expected])


func _check_source_tree() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/passive_balance.json")) as Dictionary
	var nodes: Dictionary = Passives.get_nodes()
	_expect(nodes.size() == 181, "All original graph node IDs remain")
	_expect(Passives.get_node_stats(Passives.START_ID).is_empty(), "Origin remains free of stats")
	_expect(source.schema_version == 1 and source.policy_version == "poe-passive-v1", "Intentional balance change is explicitly versioned")
	var seen: Dictionary = {}
	var raw: Dictionary = {}
	var totals: Dictionary = Model.BASE_STATS.duplicate()
	var build := Model.new()
	for slot: String in Model.EQUIPMENT_SLOTS:
		_add(totals, Items.ITEMS[build.equipped[slot]]["stats"])
	build.allocated_nodes.clear()
	build.allocated_nodes.append(Passives.START_ID)
	var changed_baseline_nodes: int = 0
	var override_counts: Dictionary = {}
	for sector_index: int in range(Passives.SECTORS.size()):
		var sector: String = Passives.SECTORS[sector_index]["id"]
		for ring_index: int in range(Passives.RING_COUNTS.size()):
			var ring: int = ring_index + 1
			for index: int in range(Passives.RING_COUNTS[ring_index]):
				var id: String = Passives.node_id(sector, ring, index)
				var node: Dictionary = nodes[id]
				var expected: Dictionary = {}
				if node.type != "socket":
					var mechanism: String = str(source.node_overrides.get(id, _original_mechanism(sector_index, ring, index, node.type == "notable")))
					expected = source.definitions[mechanism].stats
					_expect(node.mechanism_ids == [mechanism], "Stable graph placement follows versioned policy: " + id)
					seen[mechanism] = true
					_expect(node.description == Passives.describe_stats(expected), "Description shows resolved numbers: " + id)
					_expect(not source.definitions[mechanism].source_refs.is_empty(), "Every live mechanism records verifiable source facts")
					if expected != _original_stats(sector_index, ring, index, node.type == "notable"):
						changed_baseline_nodes += 1
						_expect(not str(source.definitions[mechanism].adaptation).is_empty(), "Intentional baseline change has adaptation metadata")
					if source.node_overrides.has(id):
						_expect(node.type == "small", "New scoped affix replaces one ordinary node")
						override_counts[mechanism] = int(override_counts.get(mechanism, 0)) + 1
						_expect(_distance_from_origin(id) == ring, "New affix keeps the stated 3–6 point route budget")
				else:
					_expect(node.mechanism_ids.is_empty(), "Sockets grant only their jewels")
				_expect(Passives.get_node_stats(id) == expected, "Resolved stats use source-backed authority: " + id)
				_expect(node.stats == expected, "Presentation matches resolved stats: " + id)
				build.allocated_nodes.append(id)
				_add(raw, expected)
	_expect(changed_baseline_nodes == 168, "All 168 stat nodes intentionally use policy-v1 numbers, keeping 12 sockets")
	_expect(seen.size() == 23 and Registry.get_ids().size() == 23, "Original 19 and four scoped bundles have stable shared identities")
	_expect(source.node_overrides.size() == 12 and override_counts.size() == 4, "Scoped affixes replace exactly 12 budgeted nodes")
	for id: String in override_counts:
		_expect(override_counts[id] == 3, "Every new scoped mechanism has exactly three placements")
	var capped: Dictionary = raw.duplicate()
	var saturated: int = 0
	for stat: String in raw:
		capped[stat] = minf(float(raw[stat]), float(source.player_passive_caps[stat]))
		if float(raw[stat]) > float(capped[stat]):
			saturated += 1
	_add(totals, capped)
	var actual: Dictionary = build.get_stats()
	_expect(saturated > 0, "Extreme full-tree fixture actually exercises aggregate safety caps")
	_expect(actual.size() == totals.size(), "Full character retains all supported stat fields")
	for stat: String in totals:
		_near(actual[stat], totals[stat], "Only combined talent contribution is capped: " + stat)
	_expect(build.socket_jewel("ember_3_0", "jewel_000001"), "Extreme build can equip a normal owned jewel")
	_add(totals, build.get_jewel_stats("jewel_000001"))
	actual = build.get_stats()
	for stat: String in totals:
		_near(actual[stat], totals[stat], "Jewel and equipment contributions remain outside talent caps: " + stat)
	var one: float = float(Registry.resolve("ember_power").stats.damage)
	_near(Registry.resolve_grants(["ember_power", "ember_power"]).stats.damage, one * 2.0, "Repeated nodes stack before player aggregate caps")


func _check_actor_contract() -> void:
	var monster_ids: Array[String] = Registry.get_ids("monster")
	_expect(monster_ids.size() == 13, "Only complete monster-supported bundles enter monster pools")
	_expect(Registry.get_ids("player").size() == 23, "Players support every current bundle")
	_expect(Registry.get_ids("unknown").is_empty(), "Unknown actors have no eligible mechanisms")
	for id: String in Registry.get_ids():
		var definition: Dictionary = Registry.get_definition(id)
		var player: Dictionary = Registry.resolve(id, "player")
		_expect(player.ok and player.stats == definition.stats, "Player resolves full bundle: " + id)
		_expect(definition.kind == "stat_bundle", "Only declared stat bundles are executable")
		if Registry.is_supported(id, "monster"):
			var monster: Dictionary = Registry.resolve(id, "monster")
			_expect(monster.ok and monster.stats == player.stats, "Both actors use identical numeric authority: " + id)
			var scaled: Dictionary = Registry.resolve(id, "monster", 2.5)
			_expect(scaled.ok and scaled.stats.size() == definition.stats.size(), "Role coefficient keeps full supported bundle")
			for stat: String in definition.stats:
				_near(scaled.stats[stat], float(definition.stats[stat]) * 2.5, "Role coefficient applies uniformly: " + id + "/" + stat)
				_expect(Registry.MONSTER_STATS.has(stat), "Every resolved monster field has an explicit runtime consumer")
		else:
			var rejected: Dictionary = Registry.resolve(id, "monster")
			_expect(not rejected.ok and rejected.stats.is_empty(), "Unsupported package fails closed: " + id)
			_expect(not definition.support_reason.is_empty() and not definition.supported_actors.has("monster"), "Player-only reason is explicit: " + id)
	for id: String in ["tide_capacity", "tide_flow", "tide_mastery", "prism_reserve", "prism_recovery", "prism_mastery", "poe_global_damage", "poe_projectile_damage", "poe_elemental_damage", "poe_area_damage"]:
		var rejected: Dictionary = Registry.resolve_grants(["ember_power", id], "monster")
		_expect(not rejected.ok and rejected.stats.is_empty(), "Mixed grants never silently discard unsupported mana: " + id)
	_expect(Registry.resolve_grants([], "monster").ok, "An actor may have no grants")
	_expect(not Registry.resolve_grants([], "caster").ok, "Empty grants do not bypass actor validation")
	for coefficient: float in [NAN, INF, -1.0]:
		var invalid: Dictionary = Registry.resolve("ember_power", "monster", coefficient)
		_expect(not invalid.ok and invalid.stats.is_empty(), "Invalid role coefficient is atomic")


func _check_identifiers() -> void:
	var migrated: Dictionary = Registry.migrate_ids(["talent.ember.power", "gale_stride"])
	_expect(migrated.ok and migrated.ids == ["ember_power", "gale_stride"], "Explicit aliases migrate to stable canonical IDs")
	_expect(migrated.aliases_applied == {"talent.ember.power": "ember_power"}, "Migration reports the exact compatibility substitution")
	_expect(Registry.resolve("talent.ember.power", "monster").stats == Registry.resolve("ember_power", "monster").stats, "Alias and canonical semantics match")
	_expect(Registry.get_definition("talent.gale.stride").id == "gale_stride", "Definition lookup accepts only declared aliases")
	for id: String in ["unknown", "", "ember", "ember_power_v999", "res://scripts/main.gd", "return_on_range"]:
		_expect(Registry.canonical_id(id).is_empty() and Registry.get_definition(id).is_empty(), "Unknown ID has no inferred executable meaning: " + id)
		var result: Dictionary = Registry.resolve_grants(["ember_power", id])
		_expect(not result.ok and result.stats.is_empty() and result.mechanism_ids.is_empty() and not result.errors.is_empty(), "Unknown grant fails atomically: " + id)
	for malformed: Variant in [null, 12, true, {}, [], {"id": "ember_power", "stats": {"damage": 999}}]:
		var result: Dictionary = Registry.resolve_grants(["ember_power", malformed])
		_expect(not result.ok and result.stats.is_empty(), "Inline payloads cannot define executable effects")
	var copied: Dictionary = Registry.get_definition("ember_power")
	var expected_damage: float = float(copied.stats.damage)
	copied.stats.damage = 9999.0
	_near(Registry.resolve("ember_power").stats.damage, expected_damage, "Returned metadata cannot mutate registry authority")


func _check_live_definition() -> void:
	var build := Model.new()
	_expect(build.allocate_passive("ember_1_0") and build.allocate_passive("ember_2_0"), "Allocate original stable node IDs")
	var cached_nodes: Dictionary = Passives.get_nodes()
	var before: Dictionary = build.get_stats()
	var original: Dictionary = Registry.get_definition("ember_power").stats
	var spawned_snapshot: Dictionary = Registry.resolve("ember_power", "monster")
	var before_revision: int = Registry.get_revision()
	var tuned_damage: float = float(original.damage) + 9.0
	_expect(Registry.set_definition_stats("ember_power", {"damage": tuned_damage}), "Update one shared authoritative definition")
	_expect(Registry.get_revision() > before_revision, "Validated content edit advances definition revision")
	_near(build.get_stats().damage, float(before.damage) + 9.0, "Existing character resolves changed definition without rebuild")
	_near(build.get_combat_snapshot().base_damage, float(before.damage) + 9.0, "Next player cast snapshots changed authoritative number")
	_near(Registry.resolve("ember_power", "monster").stats.damage, tuned_damage, "New monster resolution sees the exact same definition edit")
	_near(spawned_snapshot.stats.damage, float(original.damage), "Already resolved monster snapshot stays immutable")
	_expect(Passives.get_node_description("ember_2_0") == Passives.describe_stats({"damage": tuned_damage}), "Tree presentation reflects new resolved number")
	_near(cached_nodes["ember_2_0"].stats.damage, tuned_damage, "Retained tree views receive refreshed presentation projection")
	cached_nodes["ember_2_0"].stats.damage = 99999.0
	_near(build.get_stats().damage, float(before.damage) + 9.0, "Gameplay ignores mutated presentation stats")
	_expect(Registry.set_definition_stats("ember_power", original), "Restore definition after live-edit test")
	_expect(build.get_stats() == before, "Restoring the single definition restores the whole character")
	_expect(Passives.get_node_description("ember_2_0") == Passives.describe_stats(original), "Presentation refresh follows restored definition")
	var result: Dictionary = Registry.resolve("ember_power")
	_expect(result.schema_version == Registry.SCHEMA_VERSION and result.definition_revision == Registry.get_revision(), "Resolution records definition schema and revision")


func _check_invalid_tuning() -> void:
	var before: Dictionary = Registry.get_definition("ember_power")
	var revision: int = Registry.get_revision()
	for payload: Dictionary in [{}, {"damage": NAN}, {"damage": INF}, {"damage": -1.0}, {"damage": true}, {"damage": "99"}, {"move_speed": 9.0}, {"damage": 2.0, "arbitrary_effect": 1.0}]:
		_expect(not Registry.set_definition_stats("ember_power", payload), "Invalid or altered effect contract is rejected")
		_expect(Registry.get_definition("ember_power") == before, "Rejected edit leaves definition unchanged")
	_expect(not Registry.set_definition_stats("unknown", {"damage": 3.0}), "Tuning cannot register unknown executable effects")
	_expect(Registry.get_revision() == revision, "Rejected edits never advance revision")
	_expect(not Registry.set_definition_stats("grove_guard", {"max_health": 8.0}), "Mixed bundle tuning cannot drop shield field")


func _check_save_schema() -> void:
	var build := Model.new()
	_expect(build.allocate_passive("ember_1_0"), "Save fixture uses valid allocation")
	var snapshot: Dictionary = build._snapshot()
	_expect(snapshot.version == Model.SAVE_VERSION, "Current save schema retains stable passive IDs")
	_expect(snapshot.allocated_nodes == ["origin", "ember_1_0"], "Saves continue storing stable graph IDs")
	_expect(not snapshot.has("mechanism_ids") and not snapshot.has("definition_revision"), "Derived mechanism definitions are not persisted into player saves")
	_expect(not build._validate_snapshot(snapshot).is_empty(), "Existing schema-3 validator still accepts the build")


func _add(target: Dictionary, stats: Dictionary) -> void:
	for stat: String in stats:
		target[stat] = float(target.get(stat, 0.0)) + float(stats[stat])


func _original_stats(sector: int, ring: int, index: int, notable: bool) -> Dictionary:
	# Frozen pre-registry compatibility fixture, deliberately independent of live data.
	var variant: int = (ring + index) % 3
	var small: Array[Dictionary] = [
		{"damage": 2.0} if variant != 1 else {"damage": 1.0, "attack_speed": 0.025},
		{"max_health": 9.0} if variant != 1 else {"max_health": 5.0, "max_shield": 3.0},
		{"max_mana": 7.0} if variant != 1 else {"max_mana": 3.0, "mana_regen": 0.4},
		{"attack_speed": 0.045, "move_speed": 2.0} if variant != 1 else {"move_speed": 5.0},
		{"max_shield": 7.0} if variant != 1 else {"max_shield": 3.0, "shield_regen": 0.55},
		{"damage": 1.0, "max_health": 4.0} if variant == 0 else ({"max_mana": 4.0, "max_shield": 4.0} if variant == 1 else {"mana_regen": 0.3, "shield_regen": 0.4}),
	]
	var major: Array[Dictionary] = [
		{"damage": 7.0, "attack_speed": 0.08}, {"max_health": 30.0, "max_shield": 8.0},
		{"max_mana": 22.0, "mana_regen": 1.2}, {"attack_speed": 0.16, "move_speed": 12.0},
		{"max_shield": 22.0, "shield_regen": 1.7}, {"damage": 3.0, "max_health": 12.0, "max_mana": 8.0, "max_shield": 8.0},
	]
	return major[sector] if notable else small[sector]


func _check_scoped_damage() -> void:
	var projectile: Dictionary = Damage.packet({"physical": 10.0, "fire": 10.0}, ["hit", "attack", "projectile"], "tornado")
	var explosion: Dictionary = Damage.packet({"fire": 20.0}, ["hit", "area", "secondary", "explosion"], "tornado")
	for id: String in ["poe_global_damage", "poe_projectile_damage", "poe_elemental_damage", "poe_area_damage"]:
		var stats: Dictionary = Registry.resolve(id, "player").stats
		var snapshot: Dictionary = Combat.snapshot(stats, [])
		var amount: float = float(stats.values()[0])
		var expected_projectile: float = 20.0
		var expected_explosion: float = 20.0
		if id in ["poe_global_damage", "poe_projectile_damage"]:
			expected_projectile += 20.0 * amount
		elif id == "poe_elemental_damage":
			expected_projectile += 10.0 * amount
		if id in ["poe_global_damage", "poe_elemental_damage", "poe_area_damage"]:
			expected_explosion += 20.0 * amount
		_near(Damage.resolve(projectile, snapshot.modifiers).total, expected_projectile, "Scoped talent affects only matching projectile components: " + id)
		_near(Damage.resolve(explosion, snapshot.modifiers).total, expected_explosion, "Scoped talent respects explosion delivery tags: " + id)
		_expect(Passives.describe_stats(stats).contains("%"), "Native increased affix is presented as a percentage")
		_expect(snapshot.effects.is_empty() and snapshot.projectile_count == 0, "Source-backed bundles grant no unimplemented behavior or projectile multiplication")


func _distance_from_origin(target: String) -> int:
	var distance: Dictionary = {Passives.START_ID: 0}
	var queue: Array[String] = [Passives.START_ID]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if id == target:
			return int(distance[id])
		for neighbor: String in Passives.get_neighbors(id):
			if not distance.has(neighbor):
				distance[neighbor] = int(distance[id]) + 1
				queue.append(neighbor)
	return -1


func _original_mechanism(sector: int, ring: int, index: int, notable: bool) -> String:
	var variant: int = (ring + index) % 3
	var small: Array[String] = [
		"ember_power" if variant != 1 else "ember_fervor",
		"grove_vitality" if variant != 1 else "grove_guard",
		"tide_capacity" if variant != 1 else "tide_flow",
		"gale_alacrity" if variant != 1 else "gale_stride",
		"aegis_capacity" if variant != 1 else "aegis_recovery",
		"prism_vigor" if variant == 0 else ("prism_reserve" if variant == 1 else "prism_recovery"),
	]
	var major: Array[String] = ["ember_mastery", "grove_mastery", "tide_mastery", "gale_mastery", "aegis_mastery", "prism_mastery"]
	return major[sector] if notable else small[sector]
