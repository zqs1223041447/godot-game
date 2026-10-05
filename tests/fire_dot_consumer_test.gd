extends SceneTree
## Focused v053 consumer contract against fixed, published v052 source.
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Burn = preload("res://scripts/combat/burn_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Critical = preload("res://scripts/combat/critical_strike_runtime.gd")
const OldCompiler = preload("res://docs/qa/v053-consumers/v052_skill_compiler.gd")
const OldCombat = preload("res://docs/qa/v053-consumers/v052_combat_data.gd")
const OldBurn = preload("res://docs/qa/v053-consumers/v052_burn_rules.gd")
const BASE_SHA = "0abadf05c94545fb7585f5a7565cd7a8930c26cd"
var checks := 0
var failures := 0
var sections: Dictionary = {}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func near(actual: float, expected: float, label: String) -> void:
	check(is_finite(actual) and absf(actual - expected) <= maxf(0.000000001, absf(expected) * 0.000000001),
		label + " got=%s expected=%s" % [actual, expected])


func stats() -> Dictionary:
	return {"damage": 71.125, "attack_added_fire": 13.25, "spell_added_cold": 7.5,
		"fire_increased": 0.35, "global_increased": 0.18, "projectile_increased": 0.12,
		"crit_base_chance": 0.0, "crit_base_multiplier": 2.0}


func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v053-consumers-"):
		quit(78); return
	zero_compatibility()
	invalid_boundaries()
	additive_consumers()
	critical_basis()
	print("Fire DoT consumers: %d checks, %d failures; published v052 %s; sections %s" % [checks, failures, BASE_SHA, JSON.stringify(sections)])
	quit(1 if failures else 0)


func zero_compatibility() -> void:
	var start := checks
	for source: Dictionary in [{}, stats(), {"damage": 0.0}, {"damage": 1e90, "fire_increased": 0.123456789}]:
		for effects: Array in [[], ["return_on_range", "explode_on_flight_end"]]:
			var old_snapshot: Dictionary = OldCombat.snapshot(source, effects)
			for zero: Variant in [null, 0, 0.0, -0.0]:
				var current_stats: Dictionary = source.duplicate(true)
				if zero != null: current_stats.fire_dot_multiplier_add = zero
				var current: Dictionary = Combat.snapshot(current_stats, effects)
				check(not current.has("fire_dot_multiplier"), "Absent/numeric-zero source omits the new snapshot key")
				check(var_to_bytes(current) == var_to_bytes(old_snapshot), "Complete snapshot bytes equal published v052")
				check(var_to_bytes(Compiler.compile_basic(current)) == var_to_bytes(OldCompiler.compile_basic(old_snapshot)), "Complete basic compiled bytes equal published v052")
				for skill: String in Combat.Data.SKILLS:
					check(var_to_bytes(Compiler.compile_group(skill, current, [])) == var_to_bytes(OldCompiler.compile_group(skill, old_snapshot, [])), "Complete normal compiled bytes equal published v052: " + skill)
				for skill: String in ["meteor", "tornado"]:
					for support: String in ["ignite", "ember_proliferation"]:
						var previous: Dictionary = OldCompiler.compile_group(skill, old_snapshot, [support])
						var compiled: Dictionary = Compiler.compile_group(skill, current, [support])
						check(previous.ok and compiled.ok, "Both complete supported recipes compile: " + skill + "/" + support)
						check(var_to_bytes(compiled) == var_to_bytes(previous), "Complete supported compiled bytes equal fixed v052, including recipe/policy/roles: " + skill + "/" + support)
	for fire: float in [0.000001, 0.1, 17.3, 213.225, 1e90]:
		for policy: Dictionary in [Burn.PLAYER_POLICY, Burn.ENEMY_POLICY]:
			check(var_to_bytes(Burn.from_fire_hit(fire, policy)) == var_to_bytes(OldBurn.from_fire_hit(fire, policy)), "Default two-argument burn keeps full published result bytes")
			check(var_to_bytes(Burn.from_fire_hit(fire, policy, 0.0)) == var_to_bytes(OldBurn.from_fire_hit(fire, policy)), "Explicit zero burn keeps full published result bytes")
	sections.zero_v052_bytes = checks - start


func invalid_boundaries() -> void:
	var start := checks
	for invalid: Variant in [true, false, NAN, INF, -INF, -0.01, "0.1", null, [], {}]:
		var source: Dictionary = stats()
		source.fire_dot_multiplier_add = invalid
		var snapshot: Dictionary = Combat.snapshot(source, [])
		check(snapshot.has("fire_dot_multiplier") and typeof(snapshot.fire_dot_multiplier) == typeof(invalid), "Invalid source is retained for rejection, never coerced/omitted")
		for support: Array in [[], ["ignite"], ["ember_proliferation"]]:
			check(not Compiler.compile_group("meteor", snapshot, support).ok, "Invalid source fails compilation, including no-burn casts")
		check(not Burn.from_fire_hit(100.0, Burn.PLAYER_POLICY, invalid).ok, "Runtime rejects invalid nonnegative multiplier")
	for invalid: Variant in [true, false, NAN, INF, -INF, -0.01, 0, 0.0, "0.1", null, [], {}]:
		var snapshot: Dictionary = Combat.snapshot(stats(), [])
		snapshot.fire_dot_multiplier = invalid
		check(not Compiler.compile_group("meteor", snapshot, ["ignite"]).ok, "Explicit snapshot value must be positive finite numeric, including zero rejection")
	for support: String in ["ignite", "ember_proliferation"]:
		var snapshot: Dictionary = Combat.snapshot({"damage": 1e307, "fire_dot_multiplier_add": 1000.0}, [])
		check(not Compiler.compile_group("meteor", snapshot, [support]).ok, "Multiplication overflow rejects compiled burn: " + support)
	var bad_rate: Dictionary = Burn.from_fire_hit(1e308, Burn.PLAYER_POLICY, 1000.0)
	check(not bad_rate.ok and bad_rate.raw_dps == 0.0, "Derived DPS overflow fails closed")
	check(not Burn.from_fire_hit(1e308, Burn.PLAYER_POLICY, 2.0).ok, "Finite DPS with overflowing lifetime total fails closed")
	check(Burn.from_fire_hit(100.0, Burn.PLAYER_POLICY, 0).ok, "Raw runtime API retains numeric zero default")
	sections.invalid_and_overflow = checks - start


func additive_consumers() -> void:
	var start := checks
	var source: Dictionary = stats()
	var total: float = 0.04 + 0.06
	source.fire_dot_multiplier_add = total
	var boosted: Dictionary = Combat.snapshot(source, ["explode_on_flight_end"])
	var plain: Dictionary = OldCombat.snapshot(source, ["explode_on_flight_end"])
	near(boosted.fire_dot_multiplier, 0.10, "Two source contributions sum to ten percent")
	check(var_to_bytes(boosted.modifiers) == var_to_bytes(plain.modifiers), "Fire DoT source never becomes a generic hit modifier")
	for skill: String in ["meteor", "tornado"]:
		for supports: Array in [[], ["ignite"], ["ember_proliferation"]]:
			var current: Dictionary = Compiler.compile_group(skill, boosted, supports)
			var previous: Dictionary = OldCompiler.compile_group(skill, plain, supports)
			check(current.ok and previous.ok, "Nonzero recipe compiles: " + skill + str(supports))
			if not current.ok or not previous.ok: continue
			check(var_to_bytes(current.packets) == var_to_bytes(previous.packets), "Direct and secondary packet bytes unchanged")
			check(var_to_bytes(current.recipe) == var_to_bytes(previous.recipe) and current.mana == previous.mana and current.cooldown == previous.cooldown, "Movement, mana and cooldown unchanged")
			for role: String in (["parent", "child"] if skill == "tornado" else ["direct"]):
				var current_hit: Dictionary = Damage.resolve(current.packets[role], current.snapshot.modifiers)
				var old_hit: Dictionary = Damage.resolve(previous.packets[role], previous.snapshot.modifiers)
				check(var_to_bytes(current_hit) == var_to_bytes(old_hit), "Real resolved hit unchanged: " + role)
				if supports.is_empty(): continue
				var profile: Dictionary = current.burn_profile
				var expected: float = float(previous.burn_profile.roles[role].dps) * (1.0 + total)
				near(profile.roles[role].dps, expected, "Burn preview applies summed multiplier once: " + role)
				near(profile.roles[role].total, expected * 3.0, "Three-second lifetime amount scales once")
				check(profile.duration == 3.0 and profile.fire_dot_multiplier == total, "Duration fixed and additive source exposed separately")
				near(Burn.from_fire_hit(current_hit.components.fire, current.snapshot.burn_policy, total).raw_dps, expected, "Runtime derivation agrees with fixed oracle arithmetic")
			if supports.is_empty(): check(not current.has("burn_profile"), "Passive alone does not create a burn")
	# Lightning, its shock policy, and all hit/support costs keep the old values.
	for skill: String in ["bolt", "nova", "chain"]:
		var current: Dictionary = Compiler.compile_group(skill, boosted, ["shock"])
		var previous: Dictionary = OldCompiler.compile_group(skill, plain, ["shock"])
		check(current.ok and previous.ok and current.shock_profile == previous.shock_profile, "Fire DoT source leaves Shock policy unchanged: " + skill)
		var detached: Dictionary = current.duplicate(true)
		detached.snapshot.erase("fire_dot_multiplier")
		check(var_to_bytes(detached) == var_to_bytes(previous), "Full Shock compile differs only by inert optional source key")
	sections.additive_and_unaffected = checks - start


func critical_basis() -> void:
	var start := checks
	var source: Dictionary = stats()
	source.crit_base_chance = 1.0
	source.fire_dot_multiplier_add = 0.10
	for skill: String in ["meteor", "tornado"]:
		for support: String in ["ignite", "ember_proliferation"]:
			var current: Dictionary = Compiler.compile_group(skill, Combat.snapshot(source, []), [support])
			var previous: Dictionary = OldCompiler.compile_group(skill, OldCombat.snapshot(source, []), [support])
			var runtime := Critical.new()
			runtime.reset(53053)
			var frozen: Dictionary = runtime.freeze(current.snapshot).snapshot
			check(frozen.critical_roll.critical and frozen.critical_roll.multiplier == 2.0, "Guaranteed critical freezes one double multiplier")
			for role: String in (["parent", "child"] if skill == "tornado" else ["direct"]):
				var fire: float = float(previous.burn_profile.roles[role].fire_before_defense) * 2.0
				var expected: float = float(OldBurn.from_fire_hit(fire, previous.snapshot.burn_policy).raw_dps) * 1.10
				near(Burn.from_fire_hit(fire, frozen.burn_policy, frozen.fire_dot_multiplier).raw_dps, expected, "Critical fire basis and new multiplier each consumed once: " + role)
				near(current.burn_profile.roles[role].dps * 2.0, expected, "Noncritical preview becomes critical burn with one critical factor")
	sections.critical_basis = checks - start
