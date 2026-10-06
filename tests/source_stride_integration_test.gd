extends SceneTree
## Bounded source-stride integration. Run with tools/run_source_stride_checks.py.
## Legacy fixtures originate at a1dd1acf, with only preload/class-name isolation.
const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const Catalog = preload("res://scripts/monsters/monster_catalog.gd")
const Camp = preload("res://scripts/world/map_camp_state.gd")
const OldRegistry = preload("res://docs/qa/v074-integration-tests/frozen/registry.gd")
const OldCatalog = preload("res://docs/qa/v074-integration-tests/frozen/catalog.gd")
const OldCamp = preload("res://docs/qa/v074-integration-tests/frozen/camp_state.gd")
const Source = preload("res://scripts/mechanics/source_monster_grants.gd")
const Data = preload("res://scripts/passives/source_tree_data.gd")
const Parser = preload("res://scripts/passives/source_tree_runtime.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Encounter = preload("res://scripts/encounters/encounter_admission.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Admission = preload("res://scripts/world/map_admission.gd")
const CampAdmission = preload("res://scripts/world/map_camp_admission.gd")
const Layout = preload("res://scripts/world/map_camp_layout.gd")
const Geometry = preload("res://scripts/world/map_geometry.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const Frost = preload("res://scripts/combat/frost_lock_rules.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const WAVES = [1, 6, 10, 15, 100]
const SEEDS = [7, 73, 74074]
var checks := 0
var failures := 0
var sections := {}
var arena: Node
var source_seed := -1
var completed := false

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error("SOURCE_STRIDE: " + label)
	return ok
func exact(actual: Variant, expected: Variant, label: String) -> bool:
	return check(var_to_bytes(actual) == var_to_bytes(expected), label)
func near(actual: float, expected: float, label: String) -> bool:
	return check(is_finite(actual) and absf(actual - expected) < maxf(0.0000001, absf(expected) * 0.000000001), "%s actual=%s expected=%s" % [label, actual, expected])
func section(callable: Callable, label: String) -> void:
	var before := checks
	var failed_before := failures
	completed = false
	callable.call()
	check(completed, label + " reaches final assertion without script exception")
	sections[label] = {"checks": checks - before, "failures": failures - failed_before}
func replaced(ids: Array) -> Array:
	var result := ids.duplicate(true)
	for i: int in range(result.size()):
		if result[i] == "gale_stride": result[i] = Source.ID
	return result
func without_source_changes(enemy: Dictionary) -> Dictionary:
	var result := enemy.duplicate(true)
	for key: String in ["speed", "mechanism_ids", "mechanism_stats", "mechanism_policy", "mechanism_source_grants"]: result.erase(key)
	return result
func saved_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v074-"):
		push_error("Disposable runner XDG fixture required"); quit(78); return
	section(legacy_registry, "all23_legacy_registry_bytes")
	section(legacy_sampling, "legacy_catalog_sampling_rng_bytes")
	section(source_projection, "source_species_wave_projection")
	section(camp_policies, "frozen_camp_policy")
	section(source_refresh, "source_cache_and_transactions")
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	section(main_adoption, "actual_main_current_adoption")
	section(main_motion, "actual_main_motion_freeze_slow_impulse")
	var report := {"baseline_commit":"a1dd1acf", "checks":checks, "failures":failures, "sections":sections,
		"seeds":SEEDS, "waves":WAVES, "rolls_per_seed_wave":6, "species":["crawler","skitter","brute"],
		"schema":arena.state.snapshot().version, "source_execution_version":Parser.CURRENT_SAVE_VERSION,
		"source_seed":source_seed}
	var output := OS.get_environment("V074_INTEGRATION_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report, "\t") + "\n")
	print("Source stride integration: %d checks, %d failures" % [checks, failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)

func legacy_registry() -> void:
	var ids: Array = OldRegistry.get_ids()
	check(ids.size() == 23, "Frozen registry has exactly 23 legacy identities")
	var expected_ids: Array[String] = OldRegistry.get_ids()
	expected_ids.append(Source.ID)
	exact(Registry.get_ids(), expected_ids, "Current registry preserves old ordered IDs and adds one identity")
	for id: String in ids:
		exact(Registry.get_definition(id), OldRegistry.get_definition(id), "Legacy complete definition bytes " + id)
		for actor: String in ["player", "monster"]:
			for coefficient: float in [0.0, 0.5, 1.0, 2.0]:
				exact(Registry.resolve(id, actor, coefficient), OldRegistry.resolve(id, actor, coefficient), "Legacy actor/coefficient result bytes %s/%s/%s" % [id, actor, coefficient])
	for alias: String in OldRegistry.ALIASES:
		for actor: String in ["player", "monster"]:
			exact(Registry.resolve(alias, actor), OldRegistry.resolve(alias, actor), "Legacy alias exact bytes " + alias + actor)
	var saved_revision: int = Registry._revision
	var old_revision: int = OldRegistry._revision
	var definitions: Dictionary = Registry._definitions.duplicate(true)
	var old_definitions: Dictionary = OldRegistry._definitions.duplicate(true)
	for id: String in ids:
		var changed: Dictionary = definitions[id].stats.duplicate(true)
		for stat: String in changed: changed[stat] = float(changed[stat]) * 1.125
		check(Registry.set_definition_stats(id, changed) == OldRegistry.set_definition_stats(id, changed), "Legacy tuning accepts same full bundle " + id)
		for actor: String in ["player", "monster"]:
			exact(Registry.resolve(id, actor), OldRegistry.resolve(id, actor), "Legacy tuning exact result bytes " + id + actor)
	Registry._definitions = definitions; Registry._revision = saved_revision
	OldRegistry._definitions = old_definitions; OldRegistry._revision = old_revision
	check(not Registry.set_definition_stats(Source.ID, {"move_speed_increased":0.5}), "Source identity cannot be overwritten by legacy tuning")
	completed = true

func legacy_sampling() -> void:
	exact(Catalog.AFFIX_POOL, OldCatalog.AFFIX_POOL, "Legacy affix pool unchanged")
	exact(Catalog.CURRENT_AFFIX_POOL, replaced(OldCatalog.AFFIX_POOL), "Current pool is one in-place identity substitution")
	var substitutions := 0
	for seed_value: int in SEEDS:
		for wave: int in WAVES:
			var legacy := RandomNumberGenerator.new(); legacy.seed = seed_value
			var original := RandomNumberGenerator.new(); original.seed = seed_value
			var current := RandomNumberGenerator.new(); current.seed = seed_value
			for index: int in range(6):
				var old: Dictionary = OldCatalog.ordinary_roll(original, wave)
				var historical: Dictionary = Catalog.ordinary_roll(legacy, wave)
				var actual: Dictionary = Catalog.ordinary_roll_current(current, wave)
				var expected := old.duplicate(true); expected.mechanisms = replaced(old.mechanisms)
				exact([historical, legacy.state], [old, original.state], "Frozen historical roll and RNG bytes")
				exact([actual, current.state], [expected, original.state], "Current roll only substitutes identity with exact same RNG")
				if actual.mechanisms.has(Source.ID): substitutions += 1
				exact(Catalog.make_enemy(index + 1, old.template, wave, Vector2(500,400), "ordinary", old.rarity, old.mechanisms),
					OldCatalog.make_enemy(index + 1, old.template, wave, Vector2(500,400), "ordinary", old.rarity, old.mechanisms), "Legacy sampled enemy exact bytes")
	check(substitutions > 0, "Bounded sampler actually exercises stride replacement")
	for template: String in ["crawler", "skitter", "brute"]:
		for rarity: String in ["normal", "magic", "rare"]:
			for wave: int in [1, 15, 100]:
				var mechanisms: Array = [] if rarity == "normal" else ["gale_stride"] if rarity == "magic" else ["gale_stride", "ember_power"]
				exact(Catalog.make_enemy(1, template, wave, Vector2(500,400), "ordinary", rarity, mechanisms),
					OldCatalog.make_enemy(1, template, wave, Vector2(500,400), "ordinary", rarity, mechanisms), "Explicit old species/rarity/wave bytes")
	completed = true

func source_projection() -> void:
	var entry: Dictionary = Data.stat_entry("63417", 1)
	var parsed: Dictionary = Parser.line_effect(entry.raw_line)
	exact(parsed.grants, [{"stat":"move_speed_increased", "value":0.04, "mode":"increased"}], "Current parser owns exact 4% typed effect")
	var player: Dictionary = Registry.resolve(Source.ID, "player")
	var monster: Dictionary = Registry.resolve(Source.ID, "monster")
	exact(player.stats, monster.stats, "Both actors receive same source percentage")
	exact(player.source_grants, monster.source_grants, "Both actors retain exact same source-entry provenance")
	exact(monster.source_grants[0].source_entry, entry, "Metadata identifies exact node/index/current source")
	check(not monster.stats.has("armour") and monster.stats.size() == 1, "Exact stat selection does not import node armour")
	var whole_grants: Array = Parser.node_effect("63417").grants
	check(whole_grants.size() > 1 and not Source._definition_for(entry, Parser._execution_policy(Parser.CURRENT_SAVE_VERSION), Parser.CURRENT_SAVE_VERSION, {"supported":true,"grants":whole_grants}).ok, "Fake whole-node grant with armour is rejected")
	for kind: int in range(3):
		var template: String = ["crawler", "skitter", "brute"][kind]
		for wave: int in WAVES:
			var base: Dictionary = OldCatalog.make_enemy(1, template, wave, Vector2(500,400), "ordinary", "magic", [])
			var current: Dictionary = Catalog.make_enemy(1, template, wave, Vector2(500,400), "ordinary", "magic", [Source.ID])
			near(current.speed, (float(Catalog.SPECIES[kind].speed) + mini(wave,15) * 1.4) * 1.04, "Species/wave base times source increase once")
			exact(without_source_changes(current), without_source_changes(base), "HP/damage/shield/timers/rewards/non-source fields unchanged")
			check(current.mechanism_ids == [Source.ID] and current.mechanism_source_grants.size() == 1, "New identity and provenance attached once")
			var mixed: Dictionary = Catalog.make_enemy(2, template, wave, Vector2(500,400), "ordinary", "rare", ["gale_stride", Source.ID])
			near(mixed.speed, (float(base.speed) + float(OldRegistry.resolve("gale_stride", "monster").stats.move_speed)) * 1.04, "Mixed historical flat enters percentage base once")
	var profile: Dictionary = Maps.compile("old_garden", ["enemy_move_speed_110"], []).profile
	var runtime := Runtime.new()
	var mapped: Dictionary = Admission.create_root(runtime, profile, "crawler", 6, Vector2(500,400), "ordinary", "rare", ["gale_stride", Source.ID], true)
	check(mapped.ok, "Actual map admission accepts mixed source grant")
	near(mapped.enemy.speed, (64.0 + 6 * 1.4 + 3.12) * 1.04 * 1.10, "Actual map 1.10 multiplier follows source stage")
	completed = true

func camp_policies() -> void:
	var new_count := 0
	for map_id: String in ["old_garden", "broken_ruins", "sunwell_terrace"]:
		var profile: Dictionary = Maps.compile(map_id, [], []).profile
		var landmarks: Dictionary = Layout.layout(map_id, View.WORLD_ARENA).landmarks
		for seed_value: int in SEEDS:
			var old := OldCamp.new(); var legacy := Camp.new(); var explicit := Camp.new(); var current := Camp.new()
			check(old.begin(profile,landmarks,seed_value).ok and legacy.begin(profile,landmarks,seed_value).ok and explicit.begin(profile,landmarks,seed_value,Catalog.LEGACY_ROLL_POLICY).ok and current.begin(profile,landmarks,seed_value,Catalog.CURRENT_ROLL_POLICY).ok, "Both camp policies compile supported map")
			exact(legacy.checkpoint(), old.checkpoint(), "Default camp retains full frozen old checkpoint bytes")
			exact(explicit.checkpoint(), old.checkpoint(), "Explicit old camp retains full frozen checkpoint bytes")
			var expected := old.checkpoint()
			for camp: Dictionary in expected.camps:
				for row: Dictionary in camp.entries:
					row.mechanisms = replaced(row.mechanisms)
					if row.mechanisms.has(Source.ID): new_count += 1
			exact(current.checkpoint(), expected, "Current camp differs only in stride identity")
			var before := current.checkpoint()
			check(not current.begin(profile,landmarks,seed_value,"unknown_policy").ok, "Unknown camp policy rejected")
			exact(current.checkpoint(), before, "Unknown camp policy leaves existing frozen roster intact")
	check(new_count > 0, "Camp fixtures actually include source stride")
	completed = true

func source_refresh() -> void:
	var existing: Dictionary = Catalog.make_enemy(1,"crawler",6,Vector2(500,400),"ordinary","magic",[Source.ID])
	var existing_bytes := var_to_bytes(existing)
	var original_line: String = Data._nodes["63417"].stats[1]
	var valid_before: Dictionary = Source.get_definition(Source.ID)
	# Narrow process-local fixture, always restored before returning; never writes source files.
	Data._nodes["63417"].stats[1] = "8% increased Movement Speed"
	var changed: Dictionary = Source.resolve(Source.ID)
	var changed_enemy: Dictionary = Catalog.make_enemy(2,"crawler",6,Vector2(500,400),"ordinary","magic",[Source.ID])
	Data._nodes["63417"].stats[1] = original_line
	var restored: Dictionary = Source.resolve(Source.ID)
	check(changed.ok and restored.ok, "Valid changed source refreshes adapter and original restores")
	near(float(changed.stats.get("move_speed_increased", -1.0)),0.08,"Changed parsed source produces 8%")
	near(float(changed_enemy.get("speed",-1.0)),(64.0+6*1.4)*1.08,"New spawn observes changed source")
	exact(existing,bytes_to_var(existing_bytes),"Existing live monster remains immutable after source refresh")
	exact(restored.definition,valid_before,"Original entry restores identical adapter definition")
	var profile: Dictionary = Maps.compile("old_garden",[],[]).profile
	var runtime := Runtime.new()
	var before := Encounter._snapshot(runtime)
	Data._nodes["63417"].stats[1] = "4% increased Armour"
	var invalid: Dictionary = Source.resolve(Source.ID)
	var rejected: Dictionary = Registry.resolve_grants(["ember_power",Source.ID],"monster")
	var factory: Dictionary = Catalog.make_enemy(2,"crawler",6,Vector2(500,400),"ordinary","magic",[Source.ID])
	var transaction: Dictionary = Admission.create_root(runtime,profile,"crawler",6,Vector2(500,400),"ordinary","magic",[Source.ID],true)
	var after := Encounter._snapshot(runtime)
	Data._nodes["63417"].stats[1] = original_line
	var recovered: Dictionary = Source.resolve(Source.ID)
	check(not invalid.ok and invalid.stats.is_empty() and invalid.definition.is_empty(),"Invalid replacement never returns cached success or numeric fallback")
	check(not rejected.ok and rejected.stats.is_empty() and rejected.mechanism_ids.is_empty() and not rejected.has("source_grants"),"Mixed bundle failure clears every stat/identity/provenance")
	check(factory.is_empty() and not transaction.ok,"Invalid source rejects catalog and actual map transaction")
	exact(after,before,"Rejected map admission rolls back IDs, roots, trace and queue")
	check(recovered.ok and recovered.stats == {"move_speed_increased":0.04},"Recovery succeeds without stale failure cache")
	exact(existing,bytes_to_var(existing_bytes),"Invalid source never rewrites existing enemy snapshot")
	completed = true

func main_observation() -> PackedByteArray:
	return var_to_bytes([arena.state.snapshot(),arena.state.successful_saves,saved_bytes(arena.build_save_path),arena.rng.state,Encounter._snapshot(arena.monster_runtime),arena.enemies,arena._map_camps.checkpoint(),arena._map_run.admitted,arena.rings])
func clean_main() -> void:
	arena._world_mode = "normal"; arena.enemies.clear(); arena.monster_runtime = Runtime.new()
	arena._geometry.configure("normal",arena.ARENA); arena.freeze_runtime.reset(); arena.telegraphs.reset()
	arena.alive = true; arena.elapsed = 0.0; arena._burn_step_active = false
	arena.player_pos = Vector2(900,400); arena.spawn_timer = 1000.0
	arena.rng.seed = 74074; arena.ordinary_admissions = 0

func main_adoption() -> void:
	clean_main(); arena.wave = 6
	var build_before: Dictionary = arena.state.snapshot()
	var save_before := saved_bytes(arena.build_save_path)
	var saves_before: int = arena.state.successful_saves
	for seed_value: int in range(1,65):
		var probe := RandomNumberGenerator.new(); probe.seed = seed_value
		if OldCatalog.ordinary_roll(probe,6).mechanisms.has("gale_stride"):
			source_seed = seed_value; break
	check(source_seed > 0, "Bounded seed search finds historical stride ordinary roll")
	var expected_rng := RandomNumberGenerator.new(); expected_rng.seed = source_seed
	var expected: Dictionary = Catalog.ordinary_roll_current(expected_rng,6)
	arena.rng.seed = source_seed
	var actual: Dictionary = arena._spawn_enemy(Vector2(500,400))
	check(not actual.is_empty() and actual.mechanism_ids == expected.mechanisms and actual.mechanism_ids.has(Source.ID), "Actual Main ordinary spawn adopts new source ID")
	check(arena.rng.state == expected_rng.state, "Actual forced-position Main spawn consumes only frozen sampler RNG")
	var profile: Dictionary = Maps.compile("old_garden",[],[]).profile
	var observation := main_observation()
	var prepared: Dictionary = arena._prepare_camp_run(profile,1)
	check(prepared.ok,"Actual Main prepares current camp policy")
	if prepared.ok:
		var checkpoint: Dictionary = prepared.state.checkpoint()
		var manual := Camp.new(); manual.begin(profile,prepared.landmarks,checkpoint.seed,Catalog.CURRENT_ROLL_POLICY)
		exact(checkpoint,manual.checkpoint(),"Actual Main camp preparation uses explicit current policy")
		var source_entries := 0
		for camp: Dictionary in checkpoint.camps:
			for entry: Dictionary in camp.entries:
				if entry.mechanisms.has(Source.ID): source_entries += 1
		check(source_entries > 0,"Actual prepared Main roster exercises source stride")
	exact(main_observation(),observation,"Successful camp preflight is read-only for scene/RNG/save/runtime")
	var source_line: String = Data._nodes["63417"].stats[1]
	Data._nodes["63417"].stats[1] = "unsupported movement fixture"
	var refused: Dictionary = arena._prepare_camp_run(profile,1)
	Data._nodes["63417"].stats[1] = source_line
	Source.resolve(Source.ID)
	check(not refused.ok,"Actual Main preflight rejects malformed source before admission")
	exact(main_observation(),observation,"Rejected Main preflight cannot consume RNG/IDs or change snapshots/saves")
	exact(arena.state.snapshot(),build_before,"Ordinary spawn and preflight leave canonical schema47 snapshot bytes unchanged")
	exact(saved_bytes(arena.build_save_path),save_before,"Ordinary spawn and preflight preserve on-disk save bytes")
	check(arena.state.successful_saves == saves_before and build_before.version == 47 and Parser.CURRENT_SAVE_VERSION == 45,"No save write, schema change or source execution-version change")
	completed = true

func main_motion() -> void:
	var results: Array = []
	for id: String in ["gale_stride",Source.ID]:
		for mode: String in ["plain","slow","frozen","thaw_prefix"]:
			clean_main(); arena.wave = 6
			var enemy: Dictionary = arena._spawn_monster("crawler",Vector2(500,400),"ordinary","magic",[id],false)
			enemy.spawn = 0.0; enemy.attack_timer = 100.0
			enemy.slow = 1.0 if mode == "slow" else 0.0
			enemy.knockback = Vector2(0,40)
			var delta := 0.2
			var active := delta
			if mode in ["frozen","thaw_prefix"]:
				check(arena.freeze_runtime.apply(enemy.id,enemy.rarity,0.0,Frost.PLAYER_POLICY).ok,"Real frozen status applies")
				arena.elapsed = 0.2 if mode == "frozen" else 0.7
				active = 0.0 if mode == "frozen" else 0.1
			else: arena.elapsed = delta
			var initial: Vector2 = enemy.pos
			var speed: float = enemy.speed * (0.36 if mode == "slow" else 1.0)
			var snapshot: Dictionary = arena.state.snapshot(); var disk := saved_bytes(arena.build_save_path); var rng_before: int = arena.rng.state
			arena._update_enemies(delta)
			check(Vector2(enemy.pos).distance_to(initial + Vector2(speed * active,40*delta)) < 0.0001,"Actual pursuit/slow/freeze prefix/external impulse uses unchanged formula " + id + mode)
			near(enemy.attack_timer,100.0-active,"Freeze prefix preserves same autonomous attack clock")
			exact([arena.state.snapshot(),saved_bytes(arena.build_save_path),arena.rng.state],[snapshot,disk,rng_before],"Motion/status validation changes neither save nor RNG")
			results.append({"id":id,"mode":mode,"distance":Vector2(enemy.pos).distance_to(initial),"speed":enemy.speed})
	sections.motion_examples = results
	completed = true
