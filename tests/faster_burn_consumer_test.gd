extends SceneTree
## Complete consumer bytes and independent arithmetic against published v053.
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Burn = preload("res://scripts/combat/burn_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Critical = preload("res://scripts/combat/critical_strike_runtime.gd")
const OldCompiler = preload("res://docs/qa/v054-consumers/v053_skill_compiler.gd")
const OldCombat = preload("res://docs/qa/v054-consumers/v053_combat_data.gd")
const OldBurn = preload("res://docs/qa/v054-consumers/v053_burn_rules.gd")
const BASE_SHA = "e3a5f7559ecbcb2cb56a9c192d75899fdcf43b3a"
var checks := 0
var failures := 0
var sections: Dictionary = {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func near(actual: float, expected: float, label: String) -> void:
	check(is_finite(actual) and absf(actual - expected) <= maxf(1e-9, 1e-12 * absf(expected)),
		"%s got=%s expected=%s" % [label, actual, expected])

func stats() -> Dictionary:
	return {"damage": 71.125, "attack_added_fire": 13.25, "spell_added_cold": 7.5,
		"fire_increased": 0.35, "global_increased": 0.18, "projectile_increased": 0.12,
		"crit_base_chance": 0.0, "crit_base_multiplier": 2.0}

func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v054-consumers-"):
		quit(78); return
	zero_compatibility()
	invalid_boundaries()
	combined_consumers()
	critical_basis()
	print("Faster burn consumers: %d checks, %d failures; published v053 %s; sections %s" % [checks, failures, BASE_SHA, JSON.stringify(sections)])
	quit(1 if failures else 0)

func zero_compatibility() -> void:
	var start := checks
	for source: Dictionary in [{}, stats(), {"damage": 0.0}, {"damage": 1e90, "fire_increased": 0.123456789}, {"damage": 71.125, "fire_dot_multiplier_add": 0.04 + 0.06}]:
		for effects: Array in [[], ["return_on_range", "explode_on_flight_end"]]:
			var old_snapshot: Dictionary = OldCombat.snapshot(source, effects)
			for zero: Variant in [null, 0, 0.0, -0.0]:
				var current_stats: Dictionary = source.duplicate(true)
				if zero != null: current_stats.damaging_ailments_faster = zero
				var current: Dictionary = Combat.snapshot(current_stats, effects)
				check(not current.has("burn_faster"), "Absent/numeric zero speed omits new snapshot key")
				check(var_to_bytes(current) == var_to_bytes(old_snapshot), "Complete snapshot bytes equal published v053")
				check(var_to_bytes(Compiler.compile_basic(current)) == var_to_bytes(OldCompiler.compile_basic(old_snapshot)), "Complete basic compiled bytes equal published v053")
				for skill: String in Combat.Data.SKILLS:
					check(var_to_bytes(Compiler.compile_group(skill, current, [])) == var_to_bytes(OldCompiler.compile_group(skill, old_snapshot, [])), "Complete normal recipe bytes equal published v053: " + skill)
				for skill: String in ["meteor", "tornado"]:
					for support: String in ["ignite", "ember_proliferation"]:
						var previous: Dictionary = OldCompiler.compile_group(skill, old_snapshot, [support])
						var compiled: Dictionary = Compiler.compile_group(skill, current, [support])
						check(previous.ok and compiled.ok, "Both supported recipes compile: " + skill + "/" + support)
						check(var_to_bytes(compiled) == var_to_bytes(previous), "Complete supported recipe bytes equal fixed v053: " + skill + "/" + support)
	for fire: float in [0.000001, 0.1, 17.3, 213.225, 1e90]:
		for policy: Dictionary in [Burn.PLAYER_POLICY, Burn.ENEMY_POLICY]:
			for multiplier: float in [0.0, 0.04 + 0.06]:
				check(var_to_bytes(Burn.from_fire_hit(fire, policy, multiplier)) == var_to_bytes(OldBurn.from_fire_hit(fire, policy, multiplier)), "Default faster parameter preserves complete v053 result bytes")
				check(var_to_bytes(Burn.from_fire_hit(fire, policy, multiplier, 0.0)) == var_to_bytes(OldBurn.from_fire_hit(fire, policy, multiplier)), "Explicit zero faster preserves complete v053 result bytes")
	sections.zero_v053_bytes = checks - start

func invalid_boundaries() -> void:
	var start := checks
	for invalid: Variant in [true, false, NAN, INF, -INF, -0.01, "0.1", null, [], {}]:
		var source: Dictionary = stats(); source.damaging_ailments_faster = invalid
		var snapshot: Dictionary = Combat.snapshot(source, [])
		check(snapshot.has("burn_faster") and typeof(snapshot.burn_faster) == typeof(invalid), "Malformed speed retained for compiler rejection")
		for support: Array in [[], ["ignite"], ["ember_proliferation"]]:
			check(not Compiler.compile_group("meteor", snapshot, support).ok, "Invalid speed rejects full cast including unsupported burn")
		check(not Burn.from_fire_hit(100.0, Burn.PLAYER_POLICY, 0.1, invalid).ok, "Runtime rejects malformed speed")
	for invalid: Variant in [true, false, NAN, INF, -INF, -0.01, 0, 0.0, "0.1", null, [], {}]:
		var snapshot: Dictionary = Combat.snapshot(stats(), []); snapshot.burn_faster = invalid
		check(not Compiler.compile_group("meteor", snapshot, ["ignite"]).ok, "Optional snapshot speed must be positive finite numeric")
	check(not Burn.from_fire_hit(1e307, Burn.PLAYER_POLICY, 0.1, 1000.0).ok, "Overflowing final DPS rejected")
	check(not Compiler.compile_group("meteor", Combat.snapshot({"damage":1e307,"damaging_ailments_faster":1000.0}, []), ["ignite"]).ok, "Overflowing compiled burn rejected")
	sections.invalid_speed = checks - start

func combined_consumers() -> void:
	var start := checks
	var source: Dictionary = stats()
	var multiplier: float = 0.04 + 0.06
	var faster: float = 0.05 + 0.05 + 0.15
	source.fire_dot_multiplier_add = multiplier; source.damaging_ailments_faster = faster
	var boosted: Dictionary = Combat.snapshot(source, ["explode_on_flight_end"])
	var old_snapshot: Dictionary = OldCombat.snapshot(source, ["explode_on_flight_end"])
	near(boosted.burn_faster, 0.25, "Five plus five plus fifteen percent sum within speed family")
	near(boosted.fire_dot_multiplier, 0.10, "Four plus six percent sum within Fire DoT family")
	check(var_to_bytes(boosted.modifiers) == var_to_bytes(old_snapshot.modifiers), "Speed does not become a generic hit modifier")
	for skill: String in ["meteor", "tornado"]:
		for supports: Array in [[], ["ignite"], ["ember_proliferation"]]:
			var current: Dictionary = Compiler.compile_group(skill, boosted, supports)
			var previous: Dictionary = OldCompiler.compile_group(skill, old_snapshot, supports)
			check(current.ok and previous.ok, "Combined source recipe compiles: " + skill + str(supports))
			if not current.ok or not previous.ok: continue
			check(var_to_bytes(current.packets) == var_to_bytes(previous.packets), "Direct and secondary packet bytes unchanged")
			check(var_to_bytes(current.recipe) == var_to_bytes(previous.recipe) and current.mana == previous.mana and current.cooldown == previous.cooldown, "Movement, mana and cooldown unchanged")
			for role: String in (["parent", "child"] if skill == "tornado" else ["direct"]):
				var hit: Dictionary = Damage.resolve(current.packets[role], current.snapshot.modifiers)
				check(var_to_bytes(hit) == var_to_bytes(Damage.resolve(previous.packets[role], previous.snapshot.modifiers)), "Actual resolved hit bytes unchanged: " + role)
				if supports.is_empty(): continue
				var profile: Dictionary = current.burn_profile
				var base_dps: float = previous.burn_profile.roles[role].dps
				var expected_dps: float = base_dps * (1.0 + faster)
				var expected_duration: float = 3.0 / (1.0 + faster)
				near(profile.roles[role].dps, expected_dps, "Old fully scaled DPS consumes summed speed once: " + role)
				near(profile.duration, expected_duration, "Speed compresses base duration: " + role)
				near(profile.roles[role].total, float(previous.burn_profile.roles[role].total), "Theoretical lifetime total conserved within max(1e-9, 1e-12 * abs(base_total))")
				check(profile.roles[role].total == profile.roles[role].dps * profile.duration, "Preview total uses final DPS times final duration")
				check(profile.base_duration == 3.0 and profile.burn_faster == faster and profile.fire_dot_multiplier == multiplier, "Profile separates base duration and both additive families")
				var actual: Dictionary = Burn.from_fire_hit(hit.components.fire, current.snapshot.burn_policy, multiplier, faster)
				near(actual.raw_dps, expected_dps, "Runtime agrees with fixed compiler oracle DPS")
				near(actual.duration, expected_duration, "Runtime agrees with compressed preview duration")
			if supports.is_empty(): check(not current.has("burn_profile"), "Speed passive alone never creates a burn")
	for skill: String in ["bolt", "nova", "chain"]:
		var current: Dictionary = Compiler.compile_group(skill, boosted, ["shock"])
		var previous: Dictionary = OldCompiler.compile_group(skill, old_snapshot, ["shock"])
		check(current.ok and previous.ok and current.shock_profile == previous.shock_profile, "Speed leaves Shock policy unchanged: " + skill)
		var detached: Dictionary = current.duplicate(true); detached.snapshot.erase("burn_faster")
		check(var_to_bytes(detached) == var_to_bytes(previous), "Complete Shock recipe differs only by inert speed source")
	sections.combined_and_unaffected = checks - start

func critical_basis() -> void:
	var start := checks
	var source: Dictionary = stats(); source.crit_base_chance = 1.0
	source.fire_dot_multiplier_add = 0.10; source.damaging_ailments_faster = 0.25
	for skill: String in ["meteor", "tornado"]:
		for support: String in ["ignite", "ember_proliferation"]:
			var current: Dictionary = Compiler.compile_group(skill, Combat.snapshot(source, []), [support])
			var previous: Dictionary = OldCompiler.compile_group(skill, OldCombat.snapshot(source, []), [support])
			var runtime := Critical.new(); runtime.reset(54054)
			var frozen: Dictionary = runtime.freeze(current.snapshot).snapshot
			check(frozen.critical_roll.critical and frozen.critical_roll.multiplier == 2.0, "One critical double multiplier frozen")
			var before: Dictionary = runtime.checkpoint()
			for role: String in (["parent", "child"] if skill == "tornado" else ["direct"]):
				var fire: float = float(previous.burn_profile.roles[role].fire_before_defense) * 2.0
				var old: Dictionary = OldBurn.from_fire_hit(fire, previous.snapshot.burn_policy, 0.10)
				var burn: Dictionary = Burn.from_fire_hit(fire, frozen.burn_policy, frozen.fire_dot_multiplier, frozen.burn_faster)
				near(burn.raw_dps, old.raw_dps * 1.25, "Critical basis, multiplier and speed each consumed once: " + role)
				near(burn.raw_dps * burn.duration, old.raw_dps * old.duration, "Critical theoretical lifetime total conserved")
				near(current.burn_profile.roles[role].dps * 2.0, burn.raw_dps, "Preview becomes critical with exactly one critical factor")
			check(runtime.checkpoint() == before, "Burn derivation never advances cast RNG")
	sections.critical_and_rng = checks - start
