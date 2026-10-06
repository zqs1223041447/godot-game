extends SceneTree
## Bounded v75 integration; frozen f2427f3 fixtures change only preload isolation.
## Run only after shared import: tools/run_source_damage_life_checks.py.
const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const Catalog = preload("res://scripts/monsters/monster_catalog.gd")
const Camp = preload("res://scripts/world/map_camp_state.gd")
const Source = preload("res://scripts/mechanics/source_monster_grants.gd")
const Data = preload("res://scripts/passives/source_tree_data.gd")
const Parser = preload("res://scripts/passives/source_tree_runtime.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Encounter = preload("res://scripts/encounters/encounter_admission.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Admission = preload("res://scripts/world/map_admission.gd")
const Layout = preload("res://scripts/world/map_camp_layout.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const Telegraphs = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const OldRegistry = preload("res://docs/qa/v075-integration-tests/frozen/registry.gd")
const OldSource = preload("res://docs/qa/v075-integration-tests/frozen/source.gd")
const OldCatalog = preload("res://docs/qa/v075-integration-tests/frozen/catalog.gd")
const OldCamp = preload("res://docs/qa/v075-integration-tests/frozen/camp_state.gd")
const OldRuntime = preload("res://docs/qa/v075-integration-tests/frozen/monster_runtime.gd")
const LegacyRegistry = preload("res://docs/qa/v074-integration-tests/frozen/registry.gd")
const DAMAGE := "source_ember_power"
const LIFE := "source_grove_vitality"
const GALE := "source_gale_stride"
const SEEDS: Array[int] = [7, 73, 75075]
const WAVES: Array[int] = [1, 6, 15]
const SECTION_NAMES: Array[String] = ["registry", "sampling", "camps", "arithmetic_maps", "special_lineages", "cache_transactions", "main_adoption", "combat_consumers"]
var checks := 0
var failures := 0
var sections: Dictionary = {}
var observations: Dictionary = {}
var completed := false
var arena: Node

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error("SOURCE_DAMAGE_LIFE: " + label)
	return ok
func exact(actual: Variant, expected: Variant, label: String) -> bool:
	return check(var_to_bytes(actual) == var_to_bytes(expected), label)
func near(actual: float, expected: float, label: String) -> bool:
	return check(is_finite(actual) and absf(actual - expected) <= maxf(1e-8, absf(expected) * 1e-11), "%s actual=%s expected=%s" % [label, actual, expected])
func section(label: String) -> void:
	var before := checks
	var failed_before := failures
	completed = false
	call(label)
	check(completed, label + " reaches final assertion without script exception")
	sections[label] = {"checks": checks - before, "failures": failures - failed_before}
	print("V075_SECTION " + label + " " + JSON.stringify(sections[label]))
func remapped(ids: Array) -> Array:
	var result := ids.duplicate(true)
	for i: int in range(result.size()):
		if result[i] == "ember_power": result[i] = DAMAGE
		elif result[i] == "grove_vitality": result[i] = LIFE
	return result
func unchanged_fields(enemy: Dictionary) -> Dictionary:
	var copy := enemy.duplicate(true)
	for key: String in ["health", "max_health", "damage", "mechanism_ids", "mechanism_stats", "mechanism_source_grants", "mechanism_policy"]: copy.erase(key)
	return copy
func saved_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v075-"):
		push_error("Disposable v075 runner XDG fixture required"); quit(78); return
	var selected := OS.get_environment("V075_INTEGRATION_SECTIONS").split(",", false)
	for name: String in selected:
		if not SECTION_NAMES.has(name): push_error("Unknown test section: " + name); quit(78); return
	for name: String in SECTION_NAMES:
		if not selected.is_empty() and not selected.has(name): continue
		if name in ["main_adoption", "combat_consumers"] and arena == null:
			arena = load("res://scenes/main.tscn").instantiate()
			root.add_child(arena)
			arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
		section(name)
	var report := {"baseline_commit":"f2427f3", "checks":checks, "failures":failures,
		"sections":sections, "observations":observations, "seeds":SEEDS, "waves":WAVES,
		"rolls_per_seed_wave":12, "source_execution_version":Parser.CURRENT_SAVE_VERSION,
		"test_scope":"bounded integration, explicit ember fixture is not a new natural spawn policy"}
	var output := OS.get_environment("V075_INTEGRATION_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report, "\t") + "\n")
	print("Source damage/life integration: %d checks, %d failures" % [checks, failures])
	if arena != null: arena.free()
	quit(1 if failures else 0)

func registry() -> void:
	var legacy_ids: Array[String] = LegacyRegistry.get_ids()
	check(legacy_ids.size() == 23, "Frozen v73 registry retains all 23 legacy identities")
	var expected_ids: Array[String] = OldRegistry.get_ids()
	expected_ids.append(DAMAGE); expected_ids.append(LIFE)
	exact(Registry.get_ids(), expected_ids, "Ordered typed Array[String] adds exactly the two source identities")
	exact(Registry.MONSTER_STATS, OldRegistry.MONSTER_STATS, "Legacy monster stat whitelist is not widened")
	for id: String in legacy_ids:
		exact(Registry.get_definition(id), LegacyRegistry.get_definition(id), "All23 legacy definition bytes: " + id)
		for actor: String in ["player", "monster"]:
			for coefficient: float in [0.0, 0.5, 1.0]:
				exact(Registry.resolve(id, actor, coefficient), LegacyRegistry.resolve(id, actor, coefficient), "All23 legacy actor/coefficient bytes: %s/%s/%s" % [id, actor, coefficient])
	for alias: String in LegacyRegistry.ALIASES:
		for actor: String in ["player", "monster"]:
			exact(Registry.resolve(alias, actor), LegacyRegistry.resolve(alias, actor), "Legacy alias bytes: " + alias + actor)
	exact(Source.resolve(GALE), OldSource.resolve(GALE), "Complete Gale source success shape remains v74 byte exact")
	exact(Registry.get_definition(GALE), OldRegistry.get_definition(GALE), "Complete Gale registry definition remains v74 byte exact")
	for actor: String in ["player", "monster"]:
		for coefficient: float in [0.0, 0.5, 1.0]:
			exact(Registry.resolve(GALE, actor, coefficient), OldRegistry.resolve(GALE, actor, coefficient), "Gale actor/coefficient result bytes")
	check(not Registry.resolve("poe_global_damage", "monster").ok, "Legacy global damage is still player-only")
	for ids: Array in [[DAMAGE, "poe_global_damage"], [LIFE, "poe_global_damage"], [GALE, DAMAGE, LIFE, "unknown"]]:
		var rejected: Dictionary = Registry.resolve_grants(ids, "monster")
		check(not rejected.ok and rejected.stats.is_empty() and rejected.mechanism_ids.is_empty() and not rejected.has("capacity_increased") and not rejected.has("source_grants"), "Mixed failure clears stats, capacities, identities and provenance")
	for id: String in [DAMAGE, LIFE]:
		check(Source.owns(id) and Registry.canonical_id(id) == id, "Exact source ID admission " + id)
		check(not Registry.set_definition_stats(id, {"damage":999.0}), "Legacy tuning cannot mutate source identity " + id)
		var node: String = "13219" if id == DAMAGE else "52282"
		var entry: Dictionary = Data.stat_entry(node, 0)
		var parsed: Dictionary = Parser.line_effect(entry.raw_line)
		var expected: Dictionary = {"stat":"global_increased", "mode":"increased", "value":0.10} if id == DAMAGE else {"stat":"max_health", "mode":"increased", "value":0.05}
		check(parsed.supported and parsed.grants.size() == 1 and parsed.grants[0] == expected, "Exact native line stat, mode and parser amount " + id)
		for actor: String in ["player", "monster"]:
			for coefficient: float in [0.0, 0.5, 1.0]:
				var resolved: Dictionary = Registry.resolve(id, actor, coefficient)
				check(resolved.ok, "Both actors accept typed source " + id)
				exact(resolved.source_grants[0].source_entry, entry, "Exact node/index/current provenance " + id)
				if id == LIFE:
					check(resolved.stats.is_empty() and not resolved.stats.has("max_health"), "Life increase never leaks into flat stats")
					near(resolved.capacity_increased.max_health, 0.05 * coefficient, "Role coefficient scales native capacity")
				else: near(resolved.stats.global_increased, 0.10 * coefficient, "Role coefficient scales native global increase")
	var doubled: Dictionary = Registry.resolve_grants([DAMAGE, DAMAGE, LIFE, LIFE], "monster")
	near(doubled.stats.global_increased, 0.20, "Two ten percent grants add to twenty percent")
	near(doubled.capacity_increased.max_health, 0.10, "Two five percent capacity grants add to ten percent")
	check(doubled.source_grants.size() == 4, "Repeated grants retain independent attribution")
	check(not Source.owns("source_poe_global_damage") and not Source.resolve("13219").ok and not Source.resolve("source_ember_mastery").ok, "No prefix, node, whole-node or mastery admission")
	completed = true

func sampling() -> void:
	exact(Catalog.AFFIX_POOL, OldCatalog.AFFIX_POOL, "Legacy pool byte exact")
	exact(Catalog.STRIDE_AFFIX_POOL, OldCatalog.CURRENT_AFFIX_POOL, "Explicit v1 pool byte exact")
	exact(Catalog.CURRENT_AFFIX_POOL, remapped(OldCatalog.CURRENT_AFFIX_POOL), "v2 pool replaces only damage and life IDs")
	check(Catalog.LEGACY_ROLL_POLICY == "legacy_flat_v1" and Catalog.STRIDE_ROLL_POLICY == "source_stride_v1" and Catalog.CURRENT_ROLL_POLICY == "source_damage_life_v2", "All three policy names are explicit and stable")
	var seen := {DAMAGE:0, LIFE:0, "splitter":0, "brood_host":0}
	for seed_value: int in SEEDS:
		for wave: int in WAVES:
			var legacy := RandomNumberGenerator.new(); legacy.seed = seed_value
			var old_legacy := RandomNumberGenerator.new(); old_legacy.seed = seed_value
			var stride := RandomNumberGenerator.new(); stride.seed = seed_value
			var old_stride := RandomNumberGenerator.new(); old_stride.seed = seed_value
			var current := RandomNumberGenerator.new(); current.seed = seed_value
			for index: int in range(12):
				exact([Catalog.ordinary_roll(legacy, wave), legacy.state], [OldCatalog.ordinary_roll(old_legacy, wave), old_legacy.state], "Historical sampler and RNG bytes")
				var old: Dictionary = OldCatalog.ordinary_roll_current(old_stride, wave)
				exact([Catalog.ordinary_roll_source_stride(stride, wave), stride.state], [old, old_stride.state], "Explicit source_stride_v1 sampler and RNG bytes")
				var expected := old.duplicate(true)
				if old.template in ["crawler", "skitter", "brute"]: expected.mechanisms = remapped(old.mechanisms)
				var actual: Dictionary = Catalog.ordinary_roll_current(current, wave)
				exact([actual, current.state], [expected, old_stride.state], "Current sampler changes only eligible IDs and preserves RNG")
				for id: String in [DAMAGE, LIFE]:
					if actual.mechanisms.has(id): seen[id] += 1
				if actual.template in ["splitter", "brood_host"]: seen[actual.template] += 1
				var old_enemy: Dictionary = OldCatalog.make_enemy(index + 1, old.template, wave, Vector2(500,400), "ordinary", old.rarity, old.mechanisms)
				exact(Catalog.make_enemy(index + 1, old.template, wave, Vector2(500,400), "ordinary", old.rarity, old.mechanisms), old_enemy, "Every sampled explicit v74 factory result remains byte exact")
				var enemy: Dictionary = Catalog.make_enemy(index + 1, actual.template, wave, Vector2(500,400), "ordinary", actual.rarity, actual.mechanisms)
				exact(unchanged_fields(enemy), unchanged_fields(old_enemy), "Current rolled speed, shields, timers, rewards and other fields unchanged")
				if actual.mechanisms.has(DAMAGE):
					near(enemy.damage, (float(old_enemy.damage) - float(OldRegistry.resolve("ember_power", "monster").stats.damage)) * 1.10, "Only a selected source damage affix replaces its historical flat amount")
				else: exact(enemy.damage, old_enemy.damage, "Absent source damage preserves the sampled damage bytes")
				if actual.mechanisms.has(LIFE):
					near(enemy.max_health, (float(old_enemy.max_health) - float(OldRegistry.resolve("grove_vitality", "monster").stats.max_health)) * 1.05, "Only a selected source life affix replaces its historical flat amount")
				else: exact(enemy.max_health, old_enemy.max_health, "Absent source life preserves the sampled HP bytes")
	for key: String in seen: check(seen[key] > 0, "Bounded fixtures exercise actual selection " + key)
	observations.sampled = seen
	completed = true

func camps() -> void:
	var substitutions := 0
	for map_id: String in ["old_garden", "broken_ruins", "sunwell_terrace"]:
		var profile: Dictionary = Maps.compile(map_id, [], []).profile
		var landmarks: Dictionary = Layout.layout(map_id, View.WORLD_ARENA).landmarks
		for seed_value: int in [7, 73]:
			var old := OldCamp.new(); var legacy := Camp.new(); var stride := Camp.new(); var current := Camp.new()
			check(old.begin(profile, landmarks, seed_value).ok and legacy.begin(profile, landmarks, seed_value).ok, "Legacy camp preparation succeeds")
			exact(legacy.checkpoint(), old.checkpoint(), "Default camp checkpoint remains frozen historical bytes")
			legacy.begin(profile, landmarks, seed_value, Catalog.LEGACY_ROLL_POLICY)
			exact(legacy.checkpoint(), old.checkpoint(), "Explicit legacy camp checkpoint remains frozen bytes")
			old.begin(profile, landmarks, seed_value, OldCatalog.CURRENT_ROLL_POLICY)
			check(stride.begin(profile, landmarks, seed_value, Catalog.STRIDE_ROLL_POLICY).ok, "Explicit v1 camp policy is accepted")
			exact(stride.checkpoint(), old.checkpoint(), "v1 camp checkpoint remains full v74 bytes")
			var expected := old.checkpoint()
			for camp: Dictionary in expected.camps:
				for row: Dictionary in camp.entries:
					if row.template_id not in ["splitter", "brood_host", "rift_warden"]:
						row.mechanisms = remapped(row.mechanisms)
						if row.mechanisms.has(DAMAGE) or row.mechanisms.has(LIFE): substitutions += 1
			check(current.begin(profile, landmarks, seed_value, Catalog.CURRENT_ROLL_POLICY).ok, "v2 camp policy is accepted")
			exact(current.checkpoint(), expected, "Current camp roster differs only at eligible source identities")
			var before := current.checkpoint()
			check(not current.begin(profile, landmarks, seed_value, "invalid").ok, "Unknown camp policy is rejected")
			exact(current.checkpoint(), before, "Rejected policy leaves frozen roster intact")
	check(substitutions > 0, "Camp fixtures exercise new source identities")
	observations.camp_source_entries = substitutions
	completed = true

func arithmetic_maps() -> void:
	for kind: int in range(3):
		var template: String = ["crawler", "skitter", "brute"][kind]
		for wave: int in WAVES:
			var base: Dictionary = OldCatalog.make_enemy(1, template, wave, Vector2(500,400), "ordinary", "rare", [])
			var source: Dictionary = Catalog.make_enemy(1, template, wave, Vector2(500,400), "ordinary", "rare", [DAMAGE, LIFE])
			near(source.max_health, float(base.max_health) * 1.05, "Species/wave/rarity HP gets native five percent once")
			near(source.health, source.max_health, "New current HP equals maximum HP")
			near(source.damage, float(base.damage) * 1.10, "Species/wave/rarity damage gets native ten percent once")
			exact(unchanged_fields(source), unchanged_fields(base), "Source life/damage leave speed, shields, clocks and rewards unchanged")
			var mixed_life: Dictionary = Catalog.make_enemy(2, template, wave, Vector2(500,400), "ordinary", "rare", ["grove_vitality", LIFE])
			near(mixed_life.max_health, (float(base.max_health) + float(Registry.resolve("grove_vitality", "monster").stats.max_health)) * 1.05, "Historical flat life is inside source percentage base")
			var mixed_damage: Dictionary = Catalog.make_enemy(3, template, wave, Vector2(500,400), "ordinary", "rare", ["ember_power", DAMAGE])
			near(mixed_damage.damage, (float(base.damage) + float(Registry.resolve("ember_power", "monster").stats.damage)) * 1.10, "Historical flat damage is inside source percentage base")
			var repeated: Dictionary = Catalog.make_enemy(4, template, wave, Vector2(500,400), "ordinary", "rare", [DAMAGE, DAMAGE])
			near(repeated.damage, float(base.damage) * 1.20, "Repeated source damage is additive, never squared")
	var raw: Dictionary = Catalog.make_enemy(1, "brute", 6, Vector2(500,400), "ordinary", "rare", [DAMAGE, LIFE])
	var health_profile: Dictionary = Maps.compile("old_garden", ["enemy_max_health_120", "enemy_shield_from_health_20"], []).profile
	var health: Dictionary = Admission.create_root(Runtime.new(), health_profile, "brute", 6, Vector2(500,400), "ordinary", "rare", [DAMAGE, LIFE], true)
	check(health.ok, "Real MapCompiler life/shield admission succeeds")
	near(health.enemy.max_health, float(raw.max_health) * 1.20, "Map HP multiplier follows source capacity exactly once")
	near(health.enemy.health, health.enemy.max_health, "Map current HP equals maximum")
	near(health.enemy.max_shield, float(raw.max_health) * 0.20, "Shield uses canonical source HP, not map-multiplied HP twice")
	var damage_profile: Dictionary = Maps.compile("old_garden", ["enemy_damage_115"], []).profile
	var damage: Dictionary = Admission.create_root(Runtime.new(), damage_profile, "brute", 6, Vector2(500,400), "ordinary", "rare", ["ember_power", DAMAGE], true)
	var old: Dictionary = OldCatalog.make_enemy(1, "brute", 6, Vector2(500,400), "ordinary", "rare", ["ember_power"])
	near(damage.enemy.damage, float(old.damage) * 1.10 * 1.15, "Real map damage follows historical flat then source then map exactly once")
	var damage_line: String = Data._nodes["13219"].stats[0]
	var life_line: String = Data._nodes["52282"].stats[0]
	Data._nodes["13219"].stats[0] = "0% increased Damage"
	Data._nodes["52282"].stats[0] = "0% increased maximum Life"
	var zero: Dictionary = Catalog.make_enemy(1, "brute", 6, Vector2(500,400), "ordinary", "rare", [DAMAGE, LIFE])
	Data._nodes["13219"].stats[0] = damage_line; Data._nodes["52282"].stats[0] = life_line
	Source.resolve(DAMAGE); Source.resolve(LIFE)
	var absent: Dictionary = OldCatalog.make_enemy(1, "brute", 6, Vector2(500,400), "ordinary", "rare", [])
	exact([zero.health, zero.max_health, zero.damage, zero.speed], [absent.health, absent.max_health, absent.damage, absent.speed], "Zero and absent source keep historical float bytes")
	completed = true

func special_lineages() -> void:
	exact(Catalog.TEMPLATES, OldCatalog.TEMPLATES, "All authored templates including specials and death children remain unchanged")
	for template: String in ["splitter", "brood_host", "rift_warden", "ember_guard", "frost_guard", "storm_skitter", "mist_skitter"]:
		var context := "level_boss" if template == "rift_warden" else "ordinary"
		exact(Catalog.make_enemy(1, template, 6, Vector2(500,400), context), OldCatalog.make_enemy(1, template, 6, Vector2(500,400), context), "Natural special/boss factory bytes " + template)
	for template: String in ["splitter", "brood_host", "rift_warden"]:
		var current := Runtime.new(); var frozen := OldRuntime.new()
		var context := "level_boss" if template == "rift_warden" else "ordinary"
		var root_now: Dictionary = current.create_root(template, 6, Vector2(500,400), context)
		var root_old: Dictionary = frozen.create_root(template, 6, Vector2(500,400), context)
		root_now.health = 0.0; root_old.health = 0.0
		exact(current.process_death(root_now), frozen.process_death(root_old), "Special root death accounting remains frozen " + template)
		var children: Array[Dictionary] = current.drain(6, Rect2(0,0,1200,900))
		var old_children: Array[Dictionary] = frozen.drain(6, Rect2(0,0,1200,900))
		exact(children, old_children, "Actual death descendants retain historical IDs and full factory bytes " + template)
		for child: Dictionary in children:
			check(not child.mechanism_ids.has(DAMAGE) and not child.mechanism_ids.has(LIFE), "Source damage/life never migrate into authored death children")
	completed = true

func cache_transactions() -> void:
	for id: String in Source.IDS: Source.resolve(id)
	check(Source._cache_keys.size() == 3 and Source._cached_definitions.size() == 3, "Exactly three independent source cache entries")
	var gale_bytes := var_to_bytes(Source.resolve(GALE))
	var life_bytes := var_to_bytes(Source.resolve(LIFE))
	var existing: Dictionary = Catalog.make_enemy(1, "crawler", 6, Vector2(500,400), "ordinary", "rare", [DAMAGE, LIFE])
	var existing_bytes := var_to_bytes(existing)
	var damage_line: String = Data._nodes["13219"].stats[0]
	Data._nodes["13219"].stats[0] = "20% increased Damage"
	var changed: Dictionary = Source.resolve(DAMAGE)
	var spawned: Dictionary = Catalog.make_enemy(2, "crawler", 6, Vector2(500,400), "ordinary", "rare", [DAMAGE, LIFE])
	Data._nodes["13219"].stats[0] = damage_line
	Source.resolve(DAMAGE)
	near(changed.stats.global_increased, 0.20, "Changed exact source line refreshes its admission")
	near(spawned.damage, float(existing.damage) / 1.10 * 1.20, "Changed source affects only newly built enemy damage")
	exact(existing, bytes_to_var(existing_bytes), "Existing monster retains frozen life/damage/provenance")
	exact(Source.resolve(GALE), bytes_to_var(gale_bytes), "Damage cache refresh cannot evict or rewrite Gale")
	exact(Source.resolve(LIFE), bytes_to_var(life_bytes), "Damage cache refresh cannot evict or rewrite life")
	var restored_damage_bytes := var_to_bytes(Source.resolve(DAMAGE))
	var life_line: String = Data._nodes["52282"].stats[0]
	Data._nodes["52282"].stats[0] = "10% increased maximum Life"
	var grown: Dictionary = Catalog.make_enemy(3, "crawler", 6, Vector2(500,400), "ordinary", "rare", [DAMAGE, LIFE])
	Data._nodes["52282"].stats[0] = life_line; Source.resolve(LIFE)
	near(grown.max_health, float(existing.max_health) / 1.05 * 1.10, "Changed source capacity affects only newly built HP")
	exact(grown.health, grown.max_health, "Refreshed source capacity starts at full current life")
	exact(existing, bytes_to_var(existing_bytes), "Capacity refresh leaves the existing monster frozen")
	exact(Source.resolve(DAMAGE), bytes_to_var(restored_damage_bytes), "Life refresh preserves independent damage cache")
	exact(Source.resolve(GALE), bytes_to_var(gale_bytes), "Life refresh preserves independent Gale cache")
	var profile: Dictionary = Maps.compile("old_garden", [], []).profile
	for id: String in [DAMAGE, LIFE]:
		var node: String = "13219" if id == DAMAGE else "52282"
		var saved: String = Data._nodes[node].stats[0]
		var runtime := Runtime.new()
		var before := Encounter._snapshot(runtime)
		Data._nodes[node].stats[0] = "4% increased Armour"
		var invalid: Dictionary = Source.resolve(id)
		var bundle: Dictionary = Registry.resolve_grants([GALE, DAMAGE, LIFE], "monster")
		var factory: Dictionary = Catalog.make_enemy(2, "crawler", 6, Vector2(500,400), "ordinary", "magic", [id])
		var admitted: Dictionary = Admission.create_root(runtime, profile, "crawler", 6, Vector2(500,400), "ordinary", "magic", [id], true)
		var after := Encounter._snapshot(runtime)
		var unrelated: String = LIFE if id == DAMAGE else DAMAGE
		var unrelated_ok: bool = Source.resolve(unrelated).ok and Source.resolve(GALE).ok
		Data._nodes[node].stats[0] = saved
		var restored: Dictionary = Source.resolve(id)
		check(not invalid.ok and invalid.stats.is_empty() and invalid.definition.is_empty() and not invalid.has("capacity_increased"), "Invalid source has no stale success or fallback: " + id)
		check(not bundle.ok and bundle.stats.is_empty() and bundle.mechanism_ids.is_empty() and not bundle.has("source_grants") and not bundle.has("capacity_increased"), "Invalid mixed three-source bundle clears every effect")
		check(factory.is_empty() and not admitted.ok, "Invalid source rejects real factory and map transaction")
		exact(after, before, "Rejected admission rolls back IDs, roots, queue and trace")
		check(unrelated_ok and restored.ok, "Invalid source does not corrupt unrelated admissions and restoration succeeds")
	check(Source._cache_keys.size() == 3 and Source._cached_definitions.size() == 3, "Independent cache remains bounded after alternating failures")
	completed = true

func clean_main() -> void:
	arena._world_mode = "normal"; arena.enemies.clear(); arena.monster_runtime = Runtime.new()
	arena._geometry.configure("normal", arena.ARENA); arena.freeze_runtime.reset(); arena.telegraphs = Telegraphs.new()
	arena.burn_runtime.reset(); arena.shock_runtime.reset(); arena.feedback_runtime.reset()
	arena.incoming_damage_trace.clear(); arena.burn_trace.clear(); arena.telegraph_trace.clear(); arena.event_counts.clear()
	arena._burn_incoming_time = -1.0; arena._burn_immunity_until = 0.0
	arena.alive = true; arena.elapsed = 0.0; arena._burn_step_active = false
	arena.player_pos = Vector2(900,400); arena.spawn_timer = 1000.0; arena.auto_fire = false
	arena.rng.seed = 75075; arena.ordinary_admissions = 0; arena.demo_mode = false
	arena.invulnerable = 0.0; arena.damage_delay = 0.0
	arena._stats = arena.state.get_stats()
	for field: String in ["armour", "evasion", "fire_resistance", "life_regen", "shield_regen", "shield_recharge_rate"]: arena._stats[field] = 0.0
	arena.health = 10000.0; arena.shield = 0.0; arena._stats.max_health = 10000.0
	arena.hud.close_panel()
func main_observation() -> PackedByteArray:
	return var_to_bytes([arena.state.snapshot(), arena.state.successful_saves, saved_bytes(arena.build_save_path), arena.rng.state, Encounter._snapshot(arena.monster_runtime), arena.enemies, arena._map_camps.checkpoint(), arena._map_run.admitted, arena.rings])
func source_seed(id: String) -> int:
	for candidate: int in range(1,129):
		var rng := RandomNumberGenerator.new(); rng.seed = candidate
		if Catalog.ordinary_roll_current(rng,6).mechanisms.has(id): return candidate
	return -1

func main_adoption() -> void:
	clean_main(); arena.wave = 6
	var canonical: Dictionary = arena.state.snapshot()
	var disk := saved_bytes(arena.build_save_path)
	var save_count: int = arena.state.successful_saves
	var seeds: Dictionary = {}
	for id: String in [DAMAGE, LIFE]:
		clean_main(); arena.wave = 6
		var seed_value := source_seed(id); seeds[id] = seed_value
		check(seed_value > 0, "Bounded seed fixture finds current identity " + id)
		var expected_rng := RandomNumberGenerator.new(); expected_rng.seed = seed_value
		var expected: Dictionary = Catalog.ordinary_roll_current(expected_rng, 6)
		arena.rng.seed = seed_value
		var actual: Dictionary = arena._spawn_enemy(Vector2(500,400))
		check(not actual.is_empty() and actual.mechanism_ids == expected.mechanisms and actual.mechanism_ids.has(id), "Actual Main default spawn uses v2 source identity " + id)
		check(arena.rng.state == expected_rng.state, "Actual Main forced-position spawn uses exact sampler RNG")
		clean_main(); arena.wave = 6; arena.rng.seed = seed_value
		var natural: Dictionary = arena._spawn_enemy()
		check(not natural.is_empty() and natural.mechanism_ids.has(id) and arena.ordinary_admissions == 1, "Actual natural Main spawn adopts v2 source grant " + id)
	var profile: Dictionary = Maps.compile("old_garden", [], []).profile
	var before := main_observation()
	var prepared: Dictionary = arena._prepare_camp_run(profile, 1)
	check(prepared.ok, "Actual Main current camp preflight succeeds")
	if prepared.ok:
		var frozen: Dictionary = prepared.state.checkpoint()
		var manual := Camp.new(); manual.begin(profile, prepared.landmarks, frozen.seed, Catalog.CURRENT_ROLL_POLICY)
		exact(frozen, manual.checkpoint(), "Actual Main camp call adopts v2 current policy")
		var new_ids := 0
		for camp: Dictionary in frozen.camps:
			for row: Dictionary in camp.entries:
				if row.mechanisms.has(DAMAGE) or row.mechanisms.has(LIFE): new_ids += 1
		check(new_ids > 0, "Actual Main roster exercises damage/life replacement")
	exact(main_observation(), before, "Successful camp preflight preserves scene, runtime, RNG and save")
	for id: String in [DAMAGE, LIFE]:
		var node: String = "13219" if id == DAMAGE else "52282"
		var line: String = Data._nodes[node].stats[0]
		Data._nodes[node].stats[0] = "unsupported source fixture"
		var refused: Dictionary = arena._prepare_camp_run(profile, 1)
		Data._nodes[node].stats[0] = line; Source.resolve(id)
		check(not refused.ok, "Actual Main preflight rejects malformed current source " + id)
		exact(main_observation(), before, "Failure preserves RNG, IDs, runtime, canonical state and save " + id)
	exact(arena.state.snapshot(), canonical, "Main integration never changes canonical schema47 state")
	exact(saved_bytes(arena.build_save_path), disk, "Main integration never changes on-disk save bytes")
	check(arena.state.successful_saves == save_count and canonical.version == 47 and Parser.CURRENT_SAVE_VERSION == 45, "No save write, save schema or source execution change")
	observations.actual_main_seeds = seeds
	completed = true

func combat_consumers() -> void:
	clean_main(); arena.wave = 6
	var canonical: Dictionary = arena.state.snapshot()
	var disk := saved_bytes(arena.build_save_path)
	var enemy: Dictionary = arena._spawn_monster("crawler", arena.player_pos, "ordinary", "magic", [DAMAGE], false)
	enemy.spawn = 0.0; enemy.attack_timer = 0.0
	var rng_before: int = arena.rng.state
	arena._update_enemies(0.0)
	check(arena.incoming_damage_trace.size() == 1, "Actual contact attack settles exactly one hit")
	near(arena.incoming_damage_trace.back().raw_components.physical, enemy.damage, "Contact directly consumes already-scaled damage")
	check(arena.rng.state == rng_before, "Contact source scaling introduces no RNG")
	# Explicit targeted consumer fixture only. Natural ember_guard policy stays unchanged.
	clean_main(); arena.wave = 6
	var guard: Dictionary = arena._spawn_monster("ember_guard", arena.player_pos + Vector2(80,0), "demo", "rare", [DAMAGE, LIFE], false)
	guard.spawn = 0.0; guard.attack_timer = 0.0
	var raw_guard: Dictionary = OldCatalog.make_enemy(1, "ember_guard", 6, guard.pos, "demo", "rare", [])
	near(guard.damage, float(raw_guard.damage) * 1.10, "Targeted ember fixture receives source damage once")
	var contact: Dictionary = Catalog.contact_components(guard)
	near(contact.physical, guard.damage * 0.5, "Elemental split preserves physical half")
	near(contact.fire, guard.damage * 0.5, "Elemental split preserves fire half")
	exact(Catalog.telegraph_policy(guard), OldCatalog.telegraph_policy(raw_guard), "Source life/damage leave full warning/recovery/burn policy byte exact")
	arena._stats.fire_resistance = 0.50
	arena._start_enemy_telegraphs()
	var packet: Dictionary = arena.telegraphs.state_for(guard.id)
	check(not packet.is_empty(), "Actual targeted guard starts a telegraph")
	var frozen_packet := var_to_bytes(packet)
	var expected_fire := float(guard.damage) * 0.5 * 1.4 * 0.5
	near(packet.packet.base.physical, guard.damage * 0.5 * 1.4, "Telegraph physical packet applies heavy factor after source exactly once")
	near(packet.packet.base.fire, expected_fire, "Telegraph fire packet applies upfront half after source exactly once")
	var original_damage: float = guard.damage
	var line: String = Data._nodes["13219"].stats[0]
	Data._nodes["13219"].stats[0] = "20% increased Damage"
	var new_guard: Dictionary = Catalog.make_enemy(9, "ember_guard", 6, guard.pos, "demo", "rare", [DAMAGE, LIFE])
	Data._nodes["13219"].stats[0] = line; Source.resolve(DAMAGE)
	near(new_guard.damage, float(raw_guard.damage) * 1.20, "Updated source affects a new targeted fixture")
	near(guard.damage, original_damage, "Source refresh never rewrites existing live guard")
	exact(arena.telegraphs.state_for(guard.id), bytes_to_var(frozen_packet), "Source refresh leaves the complete in-flight packet/timers frozen")
	guard.damage = 999.0; guard.contact_weights = {"cold":1.0}
	arena.elapsed = 0.69; arena._advance_enemy_telegraphs(0.69)
	check(arena.incoming_damage_trace.is_empty(), "Source damage cannot shorten the original 0.7-second warning")
	arena.elapsed = 0.70; arena._advance_enemy_telegraphs(0.01)
	check(arena.incoming_damage_trace.size() == 1 and arena.telegraph_trace.size() == 1, "Original warning boundary settles one frozen hit")
	var hit: Dictionary = arena.incoming_damage_trace.back()
	near(hit.raw_components.fire, expected_fire, "Settled packet ignores later actor/source mutation")
	var burn: Dictionary = arena.burn_runtime.status_for("player", 0)
	check(not burn.is_empty(), "Real ember telegraph attaches an enemy burn")
	near(burn.raw_dps, expected_fire / 3.0, "Burn derives from frozen already-scaled fire, with no repeated global increase")
	near(burn.remaining, 3.0, "Source grants preserve original burn lifetime")
	var health_before: float = arena.health
	arena.invulnerable = 0.0; arena.elapsed = 1.2
	arena._advance_player_burn(1.2)
	near(health_before - float(arena.health), expected_fire / 3.0 * 0.5 * 0.5, "Actual burn applies elapsed half-second then player fire defense exactly once")
	near(arena.burn_trace.back().settlement.damage_total, expected_fire / 3.0 * 0.5 * 0.5, "Burn trace confirms defense follows frozen raw DPS")
	exact(arena.state.snapshot(), canonical, "Contact, telegraph and burn never mutate canonical build")
	exact(saved_bytes(arena.build_save_path), disk, "Contact, telegraph and burn preserve save bytes")
	observations.ember_targeted_fixture = {"damage":original_damage, "fire_packet":expected_fire, "burn_dps":burn.raw_dps, "warning_seconds":0.7, "natural_spawn_changed":false}
	completed = true
