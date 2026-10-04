extends SceneTree
const Camps = preload("res://scripts/world/map_camp_admission.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const MapCatalog = preload("res://scripts/world/map_catalog.gd")
const Modifiers = preload("res://scripts/encounters/encounter_catalog.gd")
const Admission = preload("res://scripts/world/map_admission.gd")
const Encounter = preload("res://scripts/encounters/encounter_admission.gd")
const Geometry = preload("res://scripts/world/map_geometry.gd")
const View = preload("res://scripts/visuals/world_view.gd")
var checks: int = 0
var failures: int = 0
var positive_groups: int = 0
var rejection_cases: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _initialize() -> void:
	var selections: Array = [[]]
	for id: String in Modifiers.get_ids(): selections.append([id])
	selections.append(["enemy_max_health_120", "enemy_shield_from_health_20"])
	selections.append(["enemy_damage_115", "enemy_attack_speed_110"])
	selections.append(["enemy_armour_80", "enemy_move_speed_110"])
	for map_id: String in MapCatalog.MAPS:
		for normal_ids: Array in selections:
			for special_ids: Array in [[], ["elemental_aegis"], ["frost_patrol"], ["storm_patrol"]]:
				var compiled: Dictionary = Maps.compile(map_id, normal_ids, special_ids)
				if compiled.ok: _positive(compiled.profile)
		for tier: int in range(1, 4):
			_positive(Maps.compile_normal(map_id, tier, [], []).profile)
			var normal: Dictionary = Maps.compile_normal(map_id, tier, ["enemy_max_health_120", "enemy_shield_from_health_20"], ["elemental_aegis"])
			if normal.ok: _positive(normal.profile)
		_failures(Maps.compile(map_id, [], []).profile)
	_boundary_checks()
	print("Map camp admission: %d checks, %d failures; %d staged groups, %d rejected groups" % [checks, failures, positive_groups, rejection_cases])
	quit(1 if failures else 0)


func _runtime() -> RefCounted:
	var runtime = Runtime.new()
	var parent: Dictionary = runtime.create_root("splitter", 5, Vector2(150, 250))
	parent.health = 0.0
	runtime.process_death(parent)
	runtime.create_root("brute", 5, Vector2(350, 250))
	return runtime


func _geometry(map_id: String) -> RefCounted:
	var geometry = Geometry.new()
	check(geometry.configure(map_id, View.WORLD_ARENA), "Fixture configures the actual map geometry")
	if geometry.has_walls():
		geometry.direction(View.WORLD_ARENA.position + Vector2(100, 350), View.WORLD_ARENA.position + Vector2(1740, 350), 14.0)
	return geometry


func _entries(profile: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var templates: Array[String] = ["crawler", "skitter", "brute", "splitter", "brood_host", "brute", "skitter", "ember_guard"]
	var count: int = 8 if profile.id == "old_garden" else 12
	for index: int in range(count):
		var template_id: String = templates[index % templates.size()]
		var source: Dictionary = Monsters.TEMPLATES[template_id]
		var roll: Dictionary = {"template": template_id, "rarity": source.rarity, "mechanisms": source.mechanisms.duplicate(true)}
		if template_id == "brute": roll.rarity = "magic"; roll.mechanisms = ["gale_stride"]
		if template_id == "skitter": roll.rarity = "rare"; roll.mechanisms = ["ember_power", "aegis_capacity"]
		var special: String = Maps.special_template(profile, roll)
		if not special.is_empty(): template_id = special
		entries.append({"template_id": template_id, "rarity": roll.rarity, "mechanisms": roll.mechanisms,
			"position": View.WORLD_ARENA.position + Vector2(120 + (index % 4) * 80, 140 + (index / 4) * 80), "admission_index": index + 1})
	return entries


func _boss_entry(profile: Dictionary) -> Array[Dictionary]:
	return [{"template_id": profile.boss_id, "rarity": "", "mechanisms": [], "position": View.WORLD_ARENA.position + Vector2(140, 340)}]


func _preserving(runtime: RefCounted, profile: Variant, entries: Variant, geometry: RefCounted,
		player: Variant, available: Variant, context: String = "ordinary") -> Dictionary:
	var before: PackedByteArray = var_to_bytes(Encounter._snapshot(runtime))
	var templates_before: PackedByteArray = var_to_bytes(runtime.templates)
	var errors_before: PackedByteArray = var_to_bytes(runtime.validation_errors)
	var entries_before: PackedByteArray = var_to_bytes(entries)
	var profile_before: PackedByteArray = var_to_bytes(profile)
	var geometry_before: PackedByteArray = var_to_bytes([geometry.snapshot(), geometry._routes])
	var player_before: PackedByteArray = var_to_bytes(player)
	seed(430003)
	var expected_random: Array[int] = [randi(), randi(), randi()]
	seed(430003)
	var result: Dictionary = Camps.plan(runtime, profile, entries, geometry, player, available, context)
	check([randi(), randi(), randi()] == expected_random, "Plan leaves the global RNG stream untouched")
	check(var_to_bytes(Encounter._snapshot(runtime)) == before, "Plan preserves the exact original runtime checkpoint")
	check(var_to_bytes(runtime.templates) == templates_before and var_to_bytes(runtime.validation_errors) == errors_before, "Plan preserves original templates and validation state")
	check(var_to_bytes(entries) == entries_before and var_to_bytes(profile) == profile_before, "Plan preserves entries and the compiled profile byte for byte")
	check(var_to_bytes([geometry.snapshot(), geometry._routes]) == geometry_before and var_to_bytes(player) == player_before, "Plan preserves geometry, routes, and player position")
	return result


func _positive(profile: Dictionary) -> void:
	var geometry: RefCounted = _geometry(profile.id)
	for context: String in ["ordinary", "map_boss"]:
		var runtime: RefCounted = _runtime()
		var entries: Array[Dictionary] = _entries(profile) if context == "ordinary" else _boss_entry(profile)
		var before: Dictionary = Encounter._snapshot(runtime)
		var result: Dictionary = _preserving(runtime, profile, entries, geometry, View.WORLD_ARENA.get_center(), entries.size(), context)
		check(result.ok and result.error.is_empty() and result.enemies.size() == entries.size(), "Whole group stages with exact capacity: " + profile.summary + " / " + context)
		if not result.ok: continue
		positive_groups += 1
		var expected = Runtime.new(runtime.templates)
		Encounter._restore(expected, before.duplicate(true))
		var seen: Dictionary = {}
		for index: int in range(entries.size()):
			var entry: Dictionary = entries[index]
			var enemy: Dictionary = result.enemies[index]
			var reference: Dictionary = Admission.create_root(expected, profile, entry.template_id, profile.wave, entry.position, context, entry.rarity, entry.mechanisms, true)
			check(reference.ok and var_to_bytes(reference.enemy) == var_to_bytes(enemy), "Every named actor field equals the existing map admission source")
			check(enemy.id == before.next_id + index + 1 and not seen.has(enemy.id), "Staged identities are sequential and unique")
			seen[enemy.id] = true
			check(enemy.pos == entry.position and enemy.spawn == 0.6 and enemy.wave == profile.wave, "Exact position, wave, and catalog spawn delay remain unchanged")
			var expected_radius: float = float(Monsters.SPECIES[enemy.kind].radius) * (1.25 if context == "map_boss" else 1.0)
			check(enemy.radius == expected_radius and enemy.radius <= (27.5 if context == "map_boss" else 22.0), "Geometry uses actual species/boss radius")
			check(enemy.root_id == enemy.id and enemy.generation == 0 and enemy.reward_eligible, "Every staged actor is a reward-eligible root")
			if not profile.normal_ids.is_empty(): check(enemy.has("encounter_source"), "Normal modifiers retain their actual source metadata")
			if profile.special_ids.has("elemental_aegis"): check(enemy.has("map_defense_source"), "Aegis retains its actual source metadata")
			if context == "map_boss": check(enemy.map_boss_attack_id == profile.boss_attack_id and enemy.template_id == profile.boss_id, "Boss template and named map attack use the actual profile")
		check(var_to_bytes(result.runtime_checkpoint) == var_to_bytes(Encounter._snapshot(expected)), "Returned checkpoint exactly matches existing factory authority")
		check(result.runtime_checkpoint.queue == before.queue and result.runtime_checkpoint.trace == before.trace, "Pending descendants and existing trace are retained")
		for id: int in before.roots: check(result.runtime_checkpoint.roots[id] == before.roots[id], "Existing roots and processed lineage remain intact")
		Encounter._restore(runtime, result.runtime_checkpoint.duplicate(true))
		var repeated: Dictionary = _preserving(runtime, profile, entries, geometry, View.WORLD_ARENA.get_center(), 100, context)
		check(repeated.ok and repeated.enemies[0].id == result.enemies[-1].id + 1, "After caller commits, another plan receives new IDs; once-only ownership remains with caller")
		if repeated.ok:
			for enemy: Dictionary in repeated.enemies: check(not seen.has(enemy.id), "Committed identities are never reused")
		# Returned state is detached from live state until the caller explicitly commits.
		var original: PackedByteArray = var_to_bytes(Encounter._snapshot(runtime))
		repeated.runtime_checkpoint.roots.clear()
		repeated.enemies[0].health = 0.0
		check(var_to_bytes(Encounter._snapshot(runtime)) == original, "Editing a later plan cannot mutate committed runtime")


func _reject(runtime: RefCounted, profile: Variant, entries: Variant, geometry: RefCounted,
		player: Variant, available: Variant, label: String, context: String = "ordinary") -> void:
	var result: Dictionary = _preserving(runtime, profile, entries, geometry, player, available, context)
	rejection_cases += 1
	check(not result.ok and not result.error.is_empty() and result.enemies.is_empty() and result.runtime_checkpoint.is_empty(), label + ": failure exposes neither a partial group nor a staged checkpoint")


func _failures(profile: Dictionary) -> void:
	var runtime: RefCounted = _runtime()
	var geometry: RefCounted = _geometry(profile.id)
	var entries: Array[Dictionary] = _entries(profile)
	var player: Vector2 = View.WORLD_ARENA.get_center()
	for index: int in [0, 1, entries.size() - 1]:
		var invalid: Array[Dictionary] = entries.duplicate(true)
		invalid[index].template_id = "missing"
		_reject(runtime, profile, invalid, geometry, player, 100, "Invalid kth template %d" % index)
		invalid = entries.duplicate(true); invalid[index].position = View.WORLD_ARENA.position - Vector2.ONE
		_reject(runtime, profile, invalid, geometry, player, 100, "Outside kth position %d" % index)
		invalid = entries.duplicate(true); invalid[index].position = player + Vector2(229.999, 0)
		_reject(runtime, profile, invalid, geometry, player, 100, "Too-close kth position %d" % index)
		invalid = entries.duplicate(true); invalid[index].position = Vector2(NAN, 250)
		_reject(runtime, profile, invalid, geometry, player, 100, "Nonfinite kth position %d" % index)
		if geometry.has_walls():
			invalid = entries.duplicate(true); invalid[index].position = geometry.snapshot().walls[0].get_center()
			_reject(runtime, profile, invalid, geometry, player, 100, "Wall kth position %d" % index)
	var bad: Array[Dictionary] = entries.duplicate(true)
	bad[1].position = bad[0].position + Vector2(1, 0)
	_reject(runtime, profile, bad, geometry, player, 100, "Valid first member then overlapping second member")
	for available: Variant in [entries.size() - 1, 0, -1, 101, true, false, float(entries.size()), 100.0, "100", null]:
		_reject(runtime, profile, entries, geometry, player, available, "Invalid/full-group-insufficient capacity " + str(available))
	for value: Variant in [null, {}, [], Vector2.INF, Vector2(NAN, 0)]:
		_reject(runtime, profile, entries, geometry, value, 100, "Invalid player")
	for value: Variant in [null, {}, [], entries.slice(0, entries.size() - 1)]:
		_reject(runtime, profile, value, geometry, player, 100, "Invalid or incomplete entry list")
	bad = entries.duplicate(true); bad.append(entries[0].duplicate(true))
	_reject(runtime, profile, bad, geometry, player, 100, "Oversized group")
	for field: String in ["template_id", "rarity", "mechanisms", "position"]:
		bad = entries.duplicate(true); bad[1].erase(field)
		_reject(runtime, profile, bad, geometry, player, 100, "Missing second-entry field " + field)
	for value: Variant in [true, 1.0, 0, -1, null]:
		bad = entries.duplicate(true); bad[1].admission_index = value
		_reject(runtime, profile, bad, geometry, player, 100, "Invalid optional admission index")
	bad = entries.duplicate(true); bad[1].rarity = "reserved"
	_reject(runtime, profile, bad, geometry, player, 100, "Factory rejects second-entry rarity")
	bad = entries.duplicate(true); bad[1].mechanisms = ["missing_mechanism"]
	_reject(runtime, profile, bad, geometry, player, 100, "Factory rejects second-entry mechanism")
	for wave: Variant in [0, -1, true, float(profile.wave), INF, NAN]:
		var invalid_profile: Dictionary = profile.duplicate(true); invalid_profile.wave = wave
		_reject(runtime, invalid_profile, entries, geometry, player, 100, "Invalid profile/wave")
	_reject(runtime, {}, entries, geometry, player, 100, "Missing profile")
	_reject(runtime, profile, entries, geometry, player, 100, "Invalid context", "death_child")
	var mismatched: RefCounted = _geometry("broken_ruins" if profile.id == "old_garden" else "old_garden")
	_reject(runtime, profile, entries, mismatched, player, 100, "Mismatched geometry")
	var corrupt: RefCounted = _runtime()
	corrupt.templates.crawler.defense_stats = {"fire_resistance": NAN}
	_reject(corrupt, profile, entries, geometry, player, 100, "Invalid template numeric stat")
	var boss: Array[Dictionary] = _boss_entry(profile)
	_reject(runtime, profile, boss, geometry, player, 0, "Boss still requires its full group", "map_boss")
	boss[0].template_id = "brute"
	_reject(runtime, profile, boss, geometry, player, 100, "Boss must match the actual profile", "map_boss")
	_reject(runtime, profile, entries, geometry, player, 100, "Boss group must contain exactly one member", "map_boss")


func _boundary_checks() -> void:
	var profile: Dictionary = Maps.compile("old_garden", [], []).profile
	var geometry: RefCounted = _geometry(profile.id)
	var runtime: RefCounted = _runtime()
	var entries: Array[Dictionary] = _entries(profile)
	entries[0].position = View.WORLD_ARENA.position + Vector2(14.0, 40.0)
	entries[1].position = entries[0].position + Vector2(24.0, 0.0)
	var player: Vector2 = entries[0].position + Vector2(0, 230.0)
	# Keep the other members far enough from this deliberately exact player limit.
	for index: int in range(2, entries.size()): entries[index].position += Vector2(1000, 0)
	var result: Dictionary = _preserving(runtime, profile, entries, geometry, player, 100)
	check(result.ok, "Exact body-boundary tangency, sum-of-radii tangency, and 230-unit player separation are admitted")
	var without_index: Array[Dictionary] = entries.duplicate(true)
	for entry: Dictionary in without_index: entry.erase("admission_index")
	check(_preserving(runtime, profile, without_index, geometry, player, 100).ok, "Optional roster admission indices may be absent")
	entries[1].position.x -= 0.001
	_reject(runtime, profile, entries, geometry, player, 100, "Actual crawler/skitter radii overlap below 24 units")
	entries = _entries(profile)
	entries[2].position.x = View.WORLD_ARENA.position.x + 21.999
	_reject(runtime, profile, entries, geometry, View.WORLD_ARENA.get_center(), 100, "22-radius ordinary footprint crosses boundary without clamping")
	var boss: Array[Dictionary] = _boss_entry(profile)
	boss[0].position.x = View.WORLD_ARENA.position.x + 27.499
	_reject(runtime, profile, boss, geometry, View.WORLD_ARENA.get_center(), 100, "27.5-radius boss footprint crosses boundary without clamping", "map_boss")
	boss[0].position.x = View.WORLD_ARENA.position.x + 27.5
	check(_preserving(runtime, profile, boss, geometry, View.WORLD_ARENA.get_center(), 1, "map_boss").ok, "Boss exact-radius boundary tangency is admitted")
