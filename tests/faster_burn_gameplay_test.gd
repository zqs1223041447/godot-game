extends SceneTree
## Narrow actual-main v054 consumers. Fixture grants lawful levels and owned gems;
## the Faster burn node itself is allocated/refunded through the real transaction API.
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Burn = preload("res://scripts/combat/burn_rules.gd")
const OldBurn = preload("res://docs/qa/v054-consumers/v053_burn_rules.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Projectiles = preload("res://scripts/combat/projectile_runtime.gd")
const Monsters = preload("res://scripts/monsters/monster_runtime.gd")
const Telegraphs = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Shock = preload("res://scripts/combat/shock_rules.gd")
const PREFIX: Array[String] = ["50986", "39725", "63649", "49806", "6580", "19711", "20010", "23471", "5237", "6363", "29937", "8544"]
var arena: Node
var checks := 0
var failures := 0
var sections: Dictionary = {}


func _initialize() -> void: call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func near(actual: float, expected: float, label: String) -> void:
	check(is_finite(actual) and absf(actual - expected) <= maxf(0.000000001, absf(expected) * 0.000000000001), "%s got=%s expected=%s" % [label, actual, expected])


func clean() -> void:
	arena.enemies.clear(); arena.projectiles.clear(); arena.pickups.clear()
	# reset() intentionally preserves monotonic actor/attack identities. Fresh
	# runtimes make complete A/B traces comparable without erasing provenance.
	arena.monster_runtime = Monsters.new(); arena.telegraphs = Telegraphs.new()
	arena.burn_runtime.reset(); arena.shock_runtime.reset()
	arena.projectile_runtime = Projectiles.new(); arena.leech_runtime.clear(); arena.feedback_runtime.reset()
	arena.damage_trace.clear(); arena.incoming_damage_trace.clear(); arena.burn_trace.clear(); arena.combat_trace.clear()
	arena.telegraph_trace.clear(); arena.event_counts.clear(); arena._ember_deaths.clear(); arena._ember_projectile_clock.clear()
	arena.group_cooldowns.reset(); arena.elapsed = 0.0; arena._burn_step_active = false; arena._burn_incoming_time = -1.0
	arena._burn_immunity_until = 0.0; arena.alive = true; arena.invulnerable = 0.0; arena.damage_delay = 0.0
	arena.auto_fire = false; arena.spawn_timer = 1000.0; arena._autosave_timer = 0.0; arena.wave = 1
	arena._world_mode = "normal"; arena._geometry.configure("old_garden", arena.ARENA)
	arena._stats = arena.state.get_stats()
	for field: String in ["life_regen", "mana_regen", "shield_regen", "shield_recharge_rate", "armour", "evasion", "fire_resistance", "lightning_resistance"]:
		arena._stats[field] = 0.0
	arena._stats.max_health = 10000.0; arena._stats.max_shield = 5000.0; arena._stats.max_mana = 10000.0
	arena.health = 10000.0; arena.shield = 5000.0; arena.mana = 10000.0
	arena.player_pos = arena.ARENA.get_center(); arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 54054; arena.critical_runtime.reset(54054); arena._player_evasion_entropy = 50.0
	arena.hud.close_panel()
	for id: String in arena.Data.SKILLS: arena.cooldowns[id] = 0.0


func target(offset: Vector2 = Vector2(80, 0), template: String = "brute") -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster(template, arena.player_pos + offset, "ordinary", "", [], false)
	enemy.spawn = 0.0; enemy.health = 10000.0; enemy.max_health = 10000.0
	enemy.shield = 0.0; enemy.max_shield = 0.0; enemy.armour = 0.0; enemy.evasion = 0.0; enemy.radius = 1.0
	enemy.resistances = {}; enemy.speed = 0.0; enemy.attack_timer = 1000.0
	enemy.shield_regen = 0.0; enemy.shield_recharge_rate = 0.0
	return enemy


func cast(support: String = "ignite", multiplier: float = 0.10, critical: bool = false, amount: float = 20.0) -> Dictionary:
	return Compiler.compile_group("meteor", Combat.snapshot({"damage": amount, "fire_increased": 0.5,
		"global_increased": 0.2, "fire_dot_multiplier_add": 0.10, "damaging_ailments_faster": multiplier,
		"crit_base_chance": 1.0 if critical else 0.0, "crit_base_multiplier": 2.0}, []), [support])


func attach(enemy: Dictionary, compiled: Dictionary, cast_id: int = 1) -> Dictionary:
	arena._apply_damage_packet(enemy, compiled.packets.direct, compiled.snapshot, Color.ORANGE, 0.0, {"cast_id": cast_id})
	return status(enemy)


func status(enemy: Dictionary) -> Dictionary: return arena.burn_runtime.status_for("monster", int(enemy.id))


func purity() -> Dictionary:
	return {"rng": arena.rng.state, "critical": arena.critical_runtime.checkpoint(), "leech": arena.leech_runtime.snapshot(),
		"model": arena.state.snapshot(), "saves": arena.state.successful_saves,
		"bytes": FileAccess.get_file_as_bytes(arena.build_save_path)}


func advance(at: float) -> void:
	arena.elapsed = at
	arena._advance_monster_burns(at)


func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v054-consumers-"):
		quit(78); return
	if not OS.get_environment("FASTER_BURN_LEGACY_OUTPUT").is_empty():
		await legacy_probe()
		return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena)
	await process_frame
	arena.set_process(false); arena.hud.set_process(false)
	check(arena.save_build(), "Fresh isolated current-schema build saved")
	actual_hit_and_tick()
	proliferation_once()
	mixed_ownership()
	enemy_and_shock_unchanged()
	allocation_and_frozen_projectiles()
	compressed_death_boundaries()
	simultaneous_deaths_and_los()
	dps_over_total_arbitration()
	print("Faster burn actual gameplay: %d checks, %d failures; sections %s" % [checks, failures, JSON.stringify(sections)])
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)


func actual_hit_and_tick() -> void:
	var start := checks
	for support: String in ["ignite", "ember_proliferation"]:
		for critical: bool in [false, true]:
			var observations: Array[Dictionary] = []
			for multiplier: float in [0.0, 0.04 + 0.06]:
				clean(); var enemy := target(); enemy.resistances.fire = 0.25
				var compiled := cast(support, multiplier, critical)
				var mana: float = arena.mana
				check(arena._execute_compiled(compiled), "Actual main executes supported meteor with frozen passive")
				check(arena.damage_trace.size() == 1, "Single isolated real meteor direct hit")
				var record: Dictionary = arena.damage_trace.back()
				var live := status(enemy)
				check(not live.is_empty(), "Actual surviving direct hit attaches burn")
				if live.is_empty(): continue
				var expected: float = float(OldBurn.from_fire_hit(record.before_defense_components.fire, compiled.snapshot.burn_policy, compiled.snapshot.get("fire_dot_multiplier", 0.0)).raw_dps) * (1.0 + multiplier)
				near(live.raw_dps, expected, "Runtime uses post-hit/critical raw fire and passive exactly once")
				near(live.raw_dps, float(compiled.burn_profile.roles.direct.dps) * (2.0 if critical else 1.0), "Real burn agrees with noncritical preview and one critical factor")
				near(live.remaining, 3.0 / (1.0 + multiplier), "New passive compresses actual duration")
				near(live.raw_dps * live.remaining, expected / (1.0 + multiplier) * 3.0, "Theoretical lifetime total preserved within max(1e-9, 1e-12 * abs(base_total))")
				near(mana - arena.mana, compiled.mana, "Supported cast pays existing mana once")
				var health: float = enemy.health; var before := purity()
				advance(0.5)
				near(health - float(enemy.health), expected * 0.5 * 0.75, "Actual burn life loss applies half-second and resistance once")
				check(purity() == before, "Passive-enhanced nonlethal tick adds no RNG, critical, leech, model mutation or save")
				observations.append({"hit": record.duplicate(true), "dps": live.raw_dps, "duration": live.remaining,
					"critical": arena.critical_runtime.checkpoint(), "rng": arena.rng.state, "saves": arena.state.successful_saves})
			if observations.size() == 2:
				check(var_to_bytes(observations[0].hit) == var_to_bytes(observations[1].hit), "Passive leaves complete actual hit trace unchanged")
				near(observations[1].dps, observations[0].dps * 1.10, "Actual additive ten-percent source changes only burn DPS")
				check(observations[0].critical == observations[1].critical and observations[0].rng == observations[1].rng and observations[0].saves == observations[1].saves, "Adding passive changes neither cast RNG streams nor saves")
	sections.direct_hit_and_health = checks - start


func proliferation_once() -> void:
	var start := checks
	clean(); var source := target(Vector2(80, 0)); var receiver := target(Vector2(190, 0)); var third := target(Vector2(300, 0))
	var compiled := cast("ember_proliferation", 0.10)
	var original := attach(source, compiled)
	near(original.raw_dps, compiled.burn_profile.roles.direct.dps, "Source owns already-multiplied DPS")
	advance(0.25)
	arena._stats.damaging_ailments_faster = 10.0
	arena._damage_enemy(source, 1000000.0, Color.WHITE)
	var inherited := status(receiver)
	check(not inherited.is_empty() and inherited.provenance.ember_generation == 1, "Actual death transfers a one-hop ember")
	if inherited.is_empty(): return
	near(inherited.raw_dps, original.raw_dps, "Transfer inherits calculated DPS, with no passive reapplied")
	near(inherited.provenance.ember_expiry, 3.0 / 1.10, "Transfer keeps original compressed absolute expiry")
	near(inherited.remaining, 3.0 / 1.10 - 0.25, "Transfer keeps only compressed remaining duration")
	near(receiver.health, 10000.0, "Transfer admission has no instant hit or DOT")
	receiver.resistances.fire = 0.5
	var before := purity(); advance(0.75)
	near(10000.0 - float(receiver.health), float(original.raw_dps) * 0.5 * 0.5, "Recipient life loses already-scaled DPS using its own defense")
	check(purity() == before, "Transferred passive-enhanced tick consumes no RNG or save")
	arena._damage_enemy(receiver, 1000000.0, Color.WHITE)
	check(status(third).is_empty(), "Inherited receiver death never re-proliferates")
	sections.proliferation_once = checks - start


func mixed_ownership() -> void:
	var start := checks
	# Multiplied DPS participates in existing stronger/weaker/equal arbitration.
	# Equal policies deliberately use the same exact final rate, avoiding a
	# near-equal fixture that would only pretend to exercise equality.
	clean(); var enemy := target(); var ember := cast("ember_proliferation", 0.10)
	var plain := ember.duplicate(true)
	plain.snapshot.erase("burn_proliferation")
	var a := attach(enemy, plain, 10)
	check(not a.provenance.has("ember_generation"), "Plain owner begins without propagation lineage")
	var weak := cast("ember_proliferation", 0.0)
	arena.elapsed = 0.5
	var b := attach(enemy, weak, 20)
	check(b.provenance.cast_id == 10 and not b.provenance.has("ember_generation"), "Weaker unboosted ember cannot steal stronger plain ownership")
	near(b.remaining, 3.0 / 1.10 - 0.5, "Weaker replacement cannot refresh compressed expiry")
	var equal := attach(enemy, ember, 30)
	check(equal.provenance.cast_id == 30 and equal.provenance.ember_generation == 0, "Equal calculated DPS refresh takes incoming ember ownership")
	near(equal.provenance.ember_expiry, 0.5 + 3.0 / 1.10, "Equal direct hit refreshes using incoming compressed duration")
	arena.elapsed = 1.0
	var stronger := attach(enemy, cast("ignite", 0.10), 40)
	check(stronger.raw_dps > equal.raw_dps and stronger.provenance.cast_id == 40 and not stronger.provenance.has("ember_generation"), "Stronger ignite wins and removes old ember lineage")
	var ignored := attach(enemy, ember, 50)
	check(ignored.provenance.cast_id == 40, "Weaker ember cannot restore propagation ownership")
	var current := status(enemy)
	var equal_ember: Dictionary = arena.burn_runtime.apply("monster", enemy.id, 7, current.raw_dps, 3.0, 1.0,
		{"cast_id": 60, "skill_id": "meteor", "ember_generation": 0, "ember_expiry": 4.0})
	check(equal_ember.ok and equal_ember.reason == "equal" and status(enemy).source_id == 7, "Exact equal runtime admission takes incoming source and lineage")
	var receiver := target(Vector2(180, 0)); arena.elapsed = 1.5
	arena._damage_enemy(enemy, 1000000.0, Color.WHITE)
	var inherited := status(receiver)
	check(not inherited.is_empty() and inherited.provenance.cast_id == 60, "Only final winning ember provenance propagates on death")
	if not inherited.is_empty():
		near(inherited.raw_dps, current.raw_dps, "Mixed ownership transfer preserves winning DPS exactly")
		near(inherited.provenance.ember_expiry, 4.0, "Mixed ownership transfer preserves winning direct-hit expiry")
	sections.mixed_ownership = checks - start


func enemy_and_shock_unchanged() -> void:
	var start := checks
	var enemy_results: Array[Dictionary] = []
	for multiplier: float in [0.0, 10.0]:
		clean(); arena._stats.damaging_ailments_faster = multiplier
		var enemy := target(Vector2(80, 0), "ember_guard"); enemy.attack_timer = 0.0; enemy.damage = 20.0
		arena._start_enemy_telegraphs()
		var attack: Dictionary = arena.telegraphs.state_for(enemy.id)
		var oracle: Dictionary = OldBurn.from_fire_hit(attack.packet.base.fire, attack.burn_policy)
		arena.tick(0.7); enemy.attack_timer = 1000.0
		var live: Dictionary = arena.burn_runtime.status_for("player", 0)
		check(not live.is_empty(), "Real enemy telegraph attaches player burn")
		if live.is_empty(): continue
		near(live.raw_dps, oracle.raw_dps, "Player passive does not alter enemy burn derivation")
		var shield: float = arena.shield; arena.tick(0.5)
		near(shield - arena.shield, float(oracle.raw_dps) * 0.18, "Enemy burn preserves existing hit-protection clipping")
		enemy_results.append({"packet": attack.packet, "policy": attack.burn_policy, "status": live,
			"health": arena.health, "shield": arena.shield, "trace": arena.incoming_damage_trace.duplicate(true)})
	if enemy_results.size() == 2: check(var_to_bytes(enemy_results[0]) == var_to_bytes(enemy_results[1]), "Enemy burn complete actual observations unchanged by player passive")
	var shock_results: Array[Dictionary] = []
	for multiplier: float in [0.0, 10.0]:
		clean(); var enemy := target()
		var compiled: Dictionary = Compiler.compile_group("nova", Combat.snapshot({"damage": 20.0, "damaging_ailments_faster": multiplier}, []), ["shock"])
		check(arena._execute_compiled(compiled), "Actual Shock cast remains admitted")
		shock_results.append({"status": arena.shock_runtime.status_at("monster", enemy.id, 0.0), "hit": arena.damage_trace.duplicate(true), "health": enemy.health})
		check(arena.burn_runtime.is_empty(), "Faster burn passive alone never turns lightning into a burn")
	check(var_to_bytes(shock_results[0]) == var_to_bytes(shock_results[1]), "Actual Shock status, direct hit and health remain byte-identical")
	sections.enemy_burn_and_shock = checks - start


func allocation_and_frozen_projectiles() -> void:
	var start := checks
	for support: String in ["ignite", "ember_proliferation"]:
		allocate_frozen(support)
	sections.real_allocation_and_frozen_carriers = checks - start


func allocate_frozen(support: String) -> void:
	clean()
	var model: RefCounted = arena.state
	var candidate: Dictionary = model.snapshot()
	candidate.progress = {"level": 8, "xp": 0}; candidate.talents.class_id = 4
	candidate.talents.allocated = PREFIX.duplicate(); candidate.talents.normal_points = 1; candidate.revision += 1
	check(Rules.reason(candidate).is_empty() and model._commit(candidate, arena.build_save_path).ok, "Lawful level-eight Duelist prefix with one earned unspent point commits")
	var support_uid: String = model.award_gem("support:" + support)
	var group_id := ""
	for group: Dictionary in model.snapshot().skill_groups:
		if model.skill_group(group.id).skill_id == "tornado": group_id = group.id
	check(not group_id.is_empty() and not support_uid.is_empty(), "Real tornado group and owned supported gem UID found")
	check(model.move_item(support_uid, {"kind": "skill_support", "group_id": group_id, "index": 0}, model.revision(), arena.build_save_path).ok, "Owned support slots through genuine model transaction")
	var previous: Dictionary = model.get_group_cast(group_id)
	var initial_stats: Dictionary = model.get_stats()
	var rng: int = arena.rng.state; var crit: Dictionary = arena.critical_runtime.checkpoint(); var saves: int = model.successful_saves
	check(model.available_passives().has("11364") and model.allocate_passive("11364", 0, model.revision(), arena.build_save_path).ok, "New full source node allocates via real guarded entry point")
	near(model.get_stats().damaging_ailments_faster - float(initial_stats.get("damaging_ailments_faster", 0.0)), 0.05, "Actual source allocation produces five percent once")
	check(model.talent_points == 0 and model.successful_saves == saves + 1, "Allocation spends exactly one point and only its actual transaction save")
	check(arena.rng.state == rng and arena.critical_runtime.checkpoint() == crit, "Passive transaction never consumes combat RNG")
	var boosted: Dictionary = model.get_group_cast(group_id)
	check(boosted.ok and boosted.snapshot.burn_faster == 0.05, "Real cached group cast freezes actual source multiplier")
	check(var_to_bytes(boosted.packets) == var_to_bytes(previous.packets), "Allocating the pure passive changes no direct/secondary packet")
	near(boosted.burn_profile.roles.parent.dps, previous.burn_profile.roles.parent.dps * 1.05, "Real model parent burn preview scales once")
	near(boosted.burn_profile.roles.child.dps, previous.burn_profile.roles.child.dps * 1.05, "Real model child burn preview scales once")
	check("\n".join(Preview.burn_lines(boosted)).contains("燃烧结算加快 5%"), "Actual model-to-burn-lines preview explains allocated five percent")
	var loaded := Model.new()
	check(loaded.load_build(arena.build_save_path) and loaded.get_group_cast(group_id) == boosted, "Allocated source and group consumer survive real disk reload")
	clean(); var far := target(Vector2(600, 0))
	check(arena.cast_group(group_id) and arena.projectiles.size() == int(boosted.initial_count), "Actual equipped group emits complete passive-enhanced tornado")
	var parents: Array = arena.projectiles.duplicate(false)
	var carrier: Dictionary = parents[parents.size() / 2]
	var frozen: PackedByteArray = var_to_bytes(carrier.snapshot)
	var parent_target := target(Vector2.ZERO)
	parent_target.pos = Vector2(carrier.pos) + Vector2(carrier.velocity).normalized() * 30.0
	saves = model.successful_saves; rng = arena.rng.state; crit = arena.critical_runtime.checkpoint()
	check(model.refund_passive("11364", model.revision(), arena.build_save_path).ok, "Actual source node refunds while projectiles remain in flight")
	check(model.successful_saves == saves + 1 and model.talent_points == 1 and model.get_stats() == initial_stats, "Refund reverses source with only one normal transaction save")
	check(arena.rng.state == rng and arena.critical_runtime.checkpoint() == crit, "Refund does not alter either RNG stream")
	check(model.get_group_cast(group_id) == previous, "Future compiled cast returns exactly to pre-allocation recipe")
	for parent: Dictionary in parents: check(var_to_bytes(parent.snapshot) == frozen, "Every active parent retains original frozen passive snapshot")
	arena._update_projectiles(0.1)
	var parent_burn := status(parent_target)
	check(not parent_burn.is_empty(), "Active parent lands real hit after refund")
	if not parent_burn.is_empty():
		var crit_factor: float = float(carrier.snapshot.get("critical_roll", {}).get("multiplier", 1.0))
		near(parent_burn.raw_dps, float(boosted.burn_profile.roles.parent.dps) * crit_factor, "Post-refund parent burn consumes frozen source exactly once")
		near(parent_burn.remaining, 3.0 / 1.05, "Post-refund parent keeps frozen compressed lifetime")
	parent_target.pos = arena.player_pos + Vector2(1000, 1000); far.pos = arena.player_pos + Vector2(1200, 1000)
	arena._update_projectiles(0.3)
	check(arena.projectiles.size() == int(boosted.initial_count) * 3, "Actual parents split to original three children each")
	if not arena.projectiles.is_empty():
		var child: Dictionary = arena.projectiles[0]
		for spawned: Dictionary in arena.projectiles:
			check(spawned.generation == 1 and var_to_bytes(spawned.snapshot) == frozen, "Every actual child inherits original passive snapshot without reapplying it")
		var child_target := target(Vector2.ZERO)
		child_target.pos = Vector2(child.pos) + Vector2(child.velocity).normalized() * 15.0
		arena._update_projectiles(0.1)
		var child_burn := status(child_target)
		check(not child_burn.is_empty(), "Real descendant projectile lands after original source refund")
		if not child_burn.is_empty():
			var crit_factor: float = float(child.snapshot.get("critical_roll", {}).get("multiplier", 1.0))
			near(child_burn.raw_dps, float(boosted.burn_profile.roles.child.dps) * crit_factor, "Post-refund child uses child coefficient and frozen multiplier once")
			near(child_burn.remaining, 3.0 / 1.05, "Post-refund descendant keeps original compressed lifetime")


func legacy_probe() -> void:
	# Fixed v053 main is compared against current main with identical current
	# dependencies and save schema. This isolates zero-passive consumer behavior;
	# the separate pure suite freezes the published compiler/Combat/Burn sources.
	var output: String = OS.get_environment("FASTER_BURN_LEGACY_OUTPUT")
	arena = load("res://scenes/main.tscn").instantiate()
	if OS.get_environment("FASTER_BURN_LEGACY_OLD") == "1":
		arena.set_script(load("res://docs/qa/v054-consumers/v053_main.gd"))
	root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.hud.close_panel()
	arena._world_mode = "normal"; arena.rng.seed = 540882; arena.restart_run()
	arena.hud.close_panel(); arena._world_mode = "normal"
	arena.enemies.clear(); arena.monster_runtime = Monsters.new(); arena.spawn_timer = 1000.0
	arena.player_pos = arena.ARENA.get_center(); arena.auto_fire = true
	arena._stats.life_regen = 1000.0; arena._stats.mana_regen = 1000.0
	arena._stats.max_health = 10000.0; arena.health = 10000.0
	check(not arena.state.get_combat_snapshot().has("burn_faster"), "Zero-source real model snapshot omits optional passive")
	for index: int in range(12):
		var enemy: Dictionary = arena._spawn_monster(["crawler", "skitter", "brute"][index % 3], arena.player_pos + Vector2(80 + index * 11, 20 if index % 2 else -20))
		enemy.spawn = 0.0
		# Three hit deaths exercise progression while durable neighbours keep
		# actual burn application/ticks alive throughout the observation window.
		enemy.health = 1.0 if index < 3 else 1000.0
		enemy.max_health = enemy.health
	var observations: Array = []
	var casts := 0
	var max_burning := 0
	var burn_frames := 0
	var settled_segments: Dictionary = {}
	for step: int in range(120):
		if step in [0, 60]:
			if arena._execute_compiled(Compiler.compile_group("meteor", arena.state.get_combat_snapshot(), ["ignite"])): casts += 1
		if step in [10, 80]:
			if arena._execute_compiled(Compiler.compile_group("tornado", arena.state.get_combat_snapshot(), ["ember_proliferation"])): casts += 1
		if step in [20, 100]:
			if arena._execute_compiled(Compiler.compile_group("chain", arena.state.get_combat_snapshot(), [])): casts += 1
		arena.tick(1.0 / 60.0)
		max_burning = maxi(max_burning, arena.burn_runtime.statuses().size())
		if not arena.burn_trace.is_empty(): burn_frames += 1
		for segment: Dictionary in arena.burn_trace:
			if float(segment.to_time) > float(segment.from_time) and float(segment.raw_amount) > 0.0 and float(segment.settlement.health_lost) > 0.0:
				settled_segments[var_to_bytes(segment).hex_encode()] = segment
		observations.append([arena.enemies.duplicate(true), arena.projectiles.duplicate(true),
			arena.monster_runtime.queue.duplicate(true), arena.monster_runtime.roots.duplicate(true), arena.rng.state,
			arena.state.snapshot(), arena.health, arena.mana, arena.shield, arena.combat_trace.duplicate(true),
			arena.damage_trace.duplicate(true), arena.incoming_damage_trace.duplicate(true),
			arena.group_cooldowns.snapshot(), arena.flask_runtime.snapshot(), arena.burn_runtime.statuses(),
			arena.shock_runtime.statuses(arena.elapsed), arena.burn_trace.duplicate(true), arena.critical_runtime.checkpoint(),
			arena.leech_runtime.snapshot(), [arena.feedback_runtime._time, arena.feedback_runtime._pending.duplicate(true), arena.feedback_runtime._visible.duplicate(true)],
			arena.particles.duplicate(true), arena.floating_text.duplicate(true), arena.state.successful_saves,
			FileAccess.get_file_as_bytes(arena.build_save_path)])
	check(arena.elapsed > 1.99 and casts > 0 and arena.kills > 0 and arena.total_damage > 0.0, "Zero-source probe exercises real casts, hits, deaths and progression")
	check(max_burning > 0 and burn_frames > 0, "Zero-source probe exercises real burn attachments and health-settled ticks")
	check(not settled_segments.is_empty(), "Probe contains distinct positive-width segments with real burn health loss")
	var settled_health := 0.0
	for segment: Dictionary in settled_segments.values(): settled_health += float(segment.settlement.health_lost)
	check(arena.save_build(), "Zero-source probe final save succeeds")
	var bytes: PackedByteArray = var_to_bytes(observations)
	FileAccess.open(output + ".bin", FileAccess.WRITE).store_buffer(bytes)
	FileAccess.open(output + ".save", FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(arena.build_save_path))
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
	var report: Dictionary = {"ticks": 120, "casts": casts, "kills": arena.kills, "reward_kills": arena.reward_kills,
		"damage": arena.total_damage, "events": arena.event_counts, "rng": arena.rng.state,
		"observation_bytes": bytes.size(), "observation_sha256": hash.finish().hex_encode(),
		"max_burning": max_burning, "frames_with_burn_damage": burn_frames,
		"unique_positive_width_health_loss_segments": settled_segments.size(), "burn_health_loss": settled_health,
		"checks": checks, "failures": failures, "published_v053_commit": "e3a5f7559ecbcb2cb56a9c192d75899fdcf43b3a"}
	FileAccess.open(output + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true))
	print("FASTER_BURN_LEGACY ", JSON.stringify(report))
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)


func compressed_death_boundaries() -> void:
	var start := checks
	var zero_death := 0.0
	var fast_death := 0.0
	for faster: float in [0.0, 0.25]:
		clean()
		# Smaller receiver ID proves global event time precedes target traversal.
		var receiver := target(Vector2(180, 0)); var source := target(Vector2(80, 0))
		var original := attach(source, cast("ember_proliferation", faster))
		var dps: float = original.raw_dps
		var base_dps: float = dps / (1.0 + faster)
		source.health = base_dps * 0.5
		var expiry: float = 3.0 / (1.0 + faster)
		arena._stats.damaging_ailments_faster = 100.0
		arena._stats.fire_dot_multiplier_add = 100.0
		advance(1.0)
		check(source.health <= 0.0 and source.death_processed, "Exact early burn boundary kills source once")
		var death_at := -1.0
		for segment: Dictionary in arena.burn_trace:
			if int(segment.target_id) == int(source.id) and float(segment.settlement.health_lost) > 0.0:
				death_at = float(segment.to_time)
		near(death_at, 0.5 / (1.0 + faster), "Faster burn kills same-life source at compressed early time")
		if faster == 0.0: zero_death = death_at
		else: fast_death = death_at
		var inherited := status(receiver)
		check(not inherited.is_empty() and inherited.provenance.ember_generation == 1, "Early DOT death transfers generation one")
		if inherited.is_empty(): continue
		near(inherited.raw_dps, dps, "Later stats do not multiply transferred DPS")
		near(inherited.provenance.ember_expiry, expiry, "Early transfer preserves original compressed absolute expiry")
		near(inherited.remaining, expiry - 1.0, "Only post-death remainder remains after current tick")
		near(10000.0 - float(receiver.health), dps * (1.0 - death_at), "Recipient burns only after precise source death")
		arena._stats.damaging_ailments_faster = 0.0
		arena._stats.fire_dot_multiplier_add = 0.0
		var before := purity(); advance(expiry)
		check(status(receiver).is_empty(), "Exact original compressed expiry clears transferred state")
		near(10000.0 - float(receiver.health), dps * (expiry - death_at), "Transferred lifetime consumes remainder only, regardless of later stats")
		check(purity() == before, "Expiry settlement creates no RNG, leech, build or save mutation")
		var health: float = receiver.health; advance(expiry + 100.0)
		check(receiver.health == health, "Spent transferred burn never pays again")
	check(fast_death < zero_death, "Actual faster DOT death occurs before zero-speed death")
	# An exact-expiry DOT death cannot propagate zero remaining duration.
	clean(); var source := target(Vector2(80, 0)); var receiver := target(Vector2(180, 0))
	var original := attach(source, cast("ember_proliferation", 0.25))
	source.health = float(original.raw_dps) * float(original.remaining)
	advance(original.remaining)
	check(source.health <= 0.0 and source.death_processed and status(receiver).is_empty(), "Death exactly at compressed expiry produces no transfer")
	check(arena.burn_runtime.is_empty() and arena._ember_deaths.is_empty(), "Exact-expiry boundary leaves no spendable burn or queued death")
	# An inherited target dying before expiry still cannot create a second hop.
	clean(); source = target(Vector2(80, 0)); receiver = target(Vector2(190, 0)); var third := target(Vector2(300, 0))
	original = attach(source, cast("ember_proliferation", 0.25))
	source.health = float(original.raw_dps) * 0.4
	receiver.health = float(original.raw_dps) * 0.4
	advance(1.0)
	check(source.health <= 0.0 and receiver.health <= 0.0 and status(third).is_empty(), "Early inherited DOT death stops at one hop")
	sections.compressed_death_and_expiry = checks - start


func simultaneous_deaths_and_los() -> void:
	var start := checks
	var orders: Array = []
	for reverse_order: bool in [false, true]:
		clean(); var first := target(Vector2(0, 0)); var second := target(Vector2(1, 0))
		var compiled := cast("ember_proliferation", 0.25)
		var initial := attach(first, compiled, 11); attach(second, compiled, 22)
		first.health = float(initial.raw_dps) * 0.5; second.health = float(initial.raw_dps) * 0.5
		var crowd: Array[Dictionary] = []
		for i: int in range(10): crowd.append(target(Vector2(10 + i * 5, 0)))
		var stronger := attach(crowd[0], cast("ignite", 0.0, false, 200.0), 33)
		if reverse_order: arena.enemies.reverse()
		advance(0.5)
		check(first.health <= 0.0 and second.health <= 0.0, "Simultaneous compressed burns settle both deaths before selection")
		for i: int in range(crowd.size()):
			var received := status(crowd[i])
			if i == 0:
				check(received.provenance.cast_id == 33 and received.raw_dps == stronger.raw_dps, "Stronger recipient retains ownership and still consumes nearest-eight slot")
			elif i < 8:
				check(not received.is_empty() and received.provenance.cast_id == 22 and received.provenance.ember_generation == 1, "Sorted simultaneous equal source IDs choose deterministic latest ownership")
				if not received.is_empty():
					near(received.raw_dps, initial.raw_dps, "Two simultaneous transfers do not add or remultiply speed")
					near(received.provenance.ember_expiry, 2.4, "Simultaneous transfers retain compressed deadline")
			else: check(received.is_empty(), "No reshuffle to ninth or tenth candidate after weaker transfer rejects")
		orders.append(arena.burn_runtime.statuses())
		check(arena._ember_deaths.is_empty(), "Simultaneous death queue fully drains")
	check(var_to_bytes(orders[0]) == var_to_bytes(orders[1]), "Reversing actor traversal leaves complete winner states byte-identical")
	clean(); arena._geometry.configure("broken_ruins", arena.ARENA)
	var wall: Rect2 = arena._geometry.snapshot().walls[0]
	var source := target(Vector2.ZERO); var blocked := target(Vector2.ZERO); var visible := target(Vector2.ZERO)
	source.pos = wall.position + Vector2(-20, 100)
	blocked.pos = wall.position + Vector2(76, 100); visible.pos = source.pos + Vector2(-40, 0)
	var newborn := target(Vector2.ZERO); newborn.pos = source.pos + Vector2(0, 20); newborn.spawn = 0.5
	var initial := attach(source, cast("ember_proliferation", 0.25))
	arena._damage_enemy(source, 1000000.0, Color.WHITE)
	check(status(blocked).is_empty() and status(newborn).is_empty() and not status(visible).is_empty(), "Faster transfer preserves actual terrain LOS and birth protection")
	near(status(visible).raw_dps, initial.raw_dps, "Visible receiver inherits rate exactly once")
	near(status(visible).provenance.ember_expiry, 2.4, "Visible receiver inherits compressed deadline")
	sections.simultaneous_selection_and_los = checks - start


func dps_over_total_arbitration() -> void:
	var start := checks
	clean(); var enemy := target()
	var greater_total := cast("ember_proliferation", 0.0, false, 30.0)
	var greater_dps := cast("ember_proliferation", 1.0, false, 20.0)
	check(greater_dps.burn_profile.roles.direct.dps > greater_total.burn_profile.roles.direct.dps and greater_dps.burn_profile.roles.direct.total < greater_total.burn_profile.roles.direct.total, "Real compiler fixture deliberately opposes DPS and theoretical total ranking")
	attach(enemy, greater_total, 101)
	arena.elapsed = 0.1
	var won := attach(enemy, greater_dps, 102)
	check(won.provenance.cast_id == 102, "Higher actual DPS wins despite smaller theoretical lifetime total")
	near(won.remaining, 1.5, "Higher-DPS incoming owner gets its compressed duration")
	arena.elapsed = 0.2
	var ignored := attach(enemy, greater_total, 103)
	check(ignored.provenance.cast_id == 102, "Lower DPS cannot replace winner despite greater total")
	near(ignored.provenance.ember_expiry, 1.6, "Rejected lower-DPS candidate cannot refresh compressed expiry")
	var equal_long := cast("ember_proliferation", 0.0, false, 40.0)
	check(equal_long.burn_profile.roles.direct.dps == greater_dps.burn_profile.roles.direct.dps, "Equal-DPS fixture is exactly equal, not approximate")
	arena.elapsed = 0.3
	var equal := attach(enemy, equal_long, 104)
	check(equal.provenance.cast_id == 104, "Exact equal DPS takes latest long-lived ownership")
	near(equal.remaining, 3.0, "Equal DPS refresh uses incoming duration")
	arena.elapsed = 0.4
	equal = attach(enemy, greater_dps, 105)
	check(equal.provenance.cast_id == 105, "Exact equal DPS takes latest shorter-lived ownership regardless of total")
	near(equal.remaining, 1.5, "Equal DPS refresh may compress instead of extending duration")
	near(equal.provenance.ember_expiry, 1.9, "Equal-DPS shorter owner supplies authoritative absolute deadline")
	sections.dps_not_total_ownership = checks - start
