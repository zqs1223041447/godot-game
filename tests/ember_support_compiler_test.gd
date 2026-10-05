extends SceneTree
## Focused Ember admission, cast and frozen-v046 contracts; no history-wide suite.
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Ember = preload("res://scripts/combat/ember_proliferation_support_rules.gd")
const Proliferation = preload("res://scripts/combat/ember_proliferation_rules.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Burn = preload("res://scripts/combat/burn_rules.gd")
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")
const CriticalRuntime = preload("res://scripts/combat/critical_strike_runtime.gd")
const Data = preload("res://scripts/game_data.gd")
const ID: String = "ember_proliferation"
const POLICY: Dictionary = {"duration": 3.0, "rate_fraction": 0.20, "hit_multiplier": 0.75, "mana_multiplier": 1.30}
const SPREAD: Dictionary = {"enabled": true, "radius": 120.0, "max_targets": 8, "max_hops": 1, "preserves_expiry": true}
const BASELINE: String = "res://docs/qa/v047-compiler/compiler-v046.bin"
var checks: int = 0
var failures: int = 0
var pairs: int = 0
var frozen_casts: int = 0


func _initialize() -> void:
	_test_admission()
	_test_profiles_and_scopes()
	_test_composition()
	_test_detachment_and_injection()
	_test_projectile_lineage_and_explosion()
	_test_frozen_v046()
	print("Ember support compiler: %d checks, %d failures; %d compatible pairs; %d exact frozen-v046 casts" % [checks, failures, pairs, frozen_casts])
	quit(1 if failures else 0)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) <= 0.0000001 * maxf(1.0, absf(expected)), "%s (%.12f vs %.12f)" % [label, actual, expected])


func _snapshot(critical: bool = false) -> Dictionary:
	var stats: Dictionary = {"damage": 100.0, "global_increased": 0.2,
		"projectile_increased": 0.5, "elemental_increased": 0.3,
		"attack_added_physical": 10.0, "attack_added_fire": 20.0,
		"spell_added_cold": 15.0, "spell_added_lightning": 7.0,
		"mana_cost_efficiency_increased": 0.25, "mana_cost_increased": 0.10}
	if critical:
		stats.crit_base_chance = 1.0
		stats.crit_base_multiplier = 2.0
	return Combat.snapshot(stats, ["return_on_range", "explode_on_flight_end"])


func _roles(skill: String) -> Array:
	return ["parent", "child"] if skill == "tornado" else ["direct"]


func _test_admission() -> void:
	check(Ember.POLICY == POLICY and Proliferation.POLICY == SPREAD, "Independent authored Ember and proliferation policies")
	check(Burn.PLAYER_POLICY == {"duration": 3.0, "rate_fraction": 0.30, "hit_multiplier": 0.75, "mana_multiplier": 1.20}, "Ignite policy remains exact")
	var definition: Dictionary = Supports.get_definition(ID)
	check(definition.get("name") == "余烬扩散辅助" and definition.get("skills") == ["meteor", "tornado"], "New identity, name and two native-fire skills")
	check(Supports.definition_error(definition).is_empty() and Ember.definition_error(definition).is_empty(), "Registry and provider validate authored definition")
	definition.operations[1].value = 1.0
	check(not Supports.definition_error(definition).is_empty() and not Ember.definition_error(definition).is_empty(), "Tampered support definition rejected")
	check(Supports.get_definition(ID).operations[1].value == 1.30, "Returned definitions are detached")
	var enriched: Dictionary = _snapshot()
	enriched.added_damage.attack.fire = 999.0
	enriched.added_damage.spell.merge({"fire": 999.0})
	for skill: String in Data.SKILLS:
		var allowed: bool = skill in ["meteor", "tornado"]
		var enriched_base: Dictionary = Compiler.compile_group(skill, enriched, [])
		check(enriched_base.ok, "Added-fire admission fixture is valid: " + skill)
		if enriched_base.ok and not allowed and skill not in ["dash", "ward"]:
			var packet: Dictionary = enriched_base.packets.bounces[0] if skill == "chain" else enriched_base.packets["direct" if skill in ["nova", "cleave"] else "projectile"]
			check(float(packet.base.get("fire", 0.0)) > 0.0, "Ineligible offensive skill actually receives added fire: " + skill)
		check(Supports.compatibility_reason(skill, [ID]).is_empty() == allowed, "Registry eligibility: " + skill)
		check(Compiler.compile_group(skill, _snapshot(), [ID]).ok == allowed, "Compiler eligibility: " + skill)
		check(Compiler.compile_group(skill, enriched, [ID]).ok == allowed, "Added fire cannot admit other skills: " + skill)
		check(Supports.supports_for_skill(skill).has(ID) == allowed, "Support selection follows real admission: " + skill)
	for skill: String in ["meteor", "tornado"]:
		for links: Array in [["ignite", ID], [ID, "ignite"]]:
			var raw: Dictionary = _snapshot()
			var before: PackedByteArray = var_to_bytes(raw)
			var links_before: PackedByteArray = var_to_bytes(links)
			var reason: String = Supports.compatibility_reason(skill, links)
			check(not reason.is_empty(), "Both mutual-exclusion orders reject in registry: " + skill)
			check(Compiler.compile_group(skill, raw, links) == {"ok": false, "error": reason}, "Compiler rejects with identical reason and no partial output")
			var program: Dictionary = Supports.compile_programs(skill, links)
			check(program.error == reason and program.modifiers.is_empty() and program.mana_multiplier == 1.0, "Program admission fails before any damage or cost mutation")
			check(before == var_to_bytes(raw) and links_before == var_to_bytes(links), "Mutual-exclusion failure never mutates inputs")
		check(not Supports.saved_links_reason(skill, [ID], 28).is_empty(), "Schema28 cannot admit Ember links")
		check(Supports.saved_links_reason(skill, [ID], 29).is_empty(), "Schema29 admits Ember links")
		check(Supports.saved_links_reason(skill, ["ignite"], 28).is_empty(), "Schema28 still admits Ignite")
		check(not Supports.saved_links_reason(skill, ["ignite", ID], 29).is_empty(), "Saved links cannot bypass mutual exclusion")
	for links: Variant in [null, "ember_proliferation", [ID, ID], [ID, 1], [ID, "unknown"]]:
		check(not Supports.compatibility_reason("tornado", links).is_empty(), "Malformed selection rejects: " + str(links))
		check(not Ember.compile_program("tornado", links).error.is_empty(), "Provider rejects malformed selection")
	check(not Compiler.compile_group("basic", _snapshot(), [ID]).ok, "Basic attacks reject Ember")
	check(not Compiler.compile_group("unknown", _snapshot(), [ID]).ok, "Unknown active skill rejects")
	check(not Compiler.compile_group("tornado", _snapshot(), [ID, ID]).ok, "Compiler rejects duplicate Ember")
	check(not Compiler.compile_group("tornado", _snapshot(), [ID, "focus", "volley", "fire_focus", "efficiency", "quickcast"]).ok, "Sixth support rejects")
	check(not Compiler.compile_skill("tornado", _snapshot(), [ID, "focus", "volley"]).ok, "Legacy two-slot limit remains")
	check(not Supports.compatibility_reason("tornado", [ID], 3).is_empty(), "Invalid slot capacity rejects")
	var empty: Dictionary = Ember.compile_program("meteor", [])
	check(empty.error.is_empty() and empty.modifiers.is_empty() and empty.mana_multiplier == 1.0, "Empty new provider has no effect")


func _test_profiles_and_scopes() -> void:
	for skill: String in ["meteor", "tornado"]:
		var base: Dictionary = Compiler.compile_group(skill, _snapshot(), [])
		var cast: Dictionary = Compiler.compile_group(skill, _snapshot(), [ID])
		check(base.ok and cast.ok, "New and base compile: " + skill)
		if not base.ok or not cast.ok: continue
		check(cast.snapshot.burn_policy == POLICY and cast.snapshot.burn_proliferation == SPREAD, "Execution snapshot owns both exact policies")
		check(cast.packets == base.packets and cast.recipe == base.recipe and cast.initial_count == base.initial_count, "Ember does not alter packet bases or delivery")
		near(cast.mana, base.mana * 1.30, "Mana factor exactly once after source cost factors")
		near(cast.cooldown, base.cooldown, "Cooldown unchanged")
		check(cast.burn_profile.enabled and cast.burn_profile.stacking == "strongest_refresh_equal", "Burn profile retains stacking semantics")
		check(cast.burn_profile.roles.keys() == _roles(skill), "Preview exposes only direct or parent/child roles")
		check(cast.burn_profile.proliferation == SPREAD, "Preview exposes authoritative propagation policy")
		for key: String in POLICY: near(cast.burn_profile[key], POLICY[key], "Preview policy: " + key)
		var critical: Dictionary = Compiler.compile_group(skill, _snapshot(true), [ID])
		check(critical.ok and critical.burn_profile == cast.burn_profile, "Burn preview excludes critical chance and multiplier")
		for role: String in _roles(skill):
			var original: Dictionary = Damage.resolve(base.packets[role], base.snapshot.modifiers)
			var resolved: Dictionary = Damage.resolve(cast.packets[role], cast.snapshot.modifiers)
			for type: String in original.components:
				near(resolved.components[type], original.components[type] * 0.75, "Each primary component pays damage once: %s/%s/%s" % [skill, role, type])
			var profile: Dictionary = cast.burn_profile.roles[role]
			check(profile.keys() == ["fire_before_defense", "dps", "total"], "Existing role field names and ordering retained")
			near(profile.fire_before_defense, resolved.components.fire, "Preview reads resolved noncritical fire")
			near(profile.dps, resolved.components.fire * 0.20, "Real burn DPS includes all modifiers exactly once")
			near(profile.total, profile.dps * 3.0, "Burn lifetime amount retains three seconds")
			var resisted: Dictionary = Damage.resolve(cast.packets[role], cast.snapshot.modifiers, {"fire": 0.75})
			near(profile.fire_before_defense, resisted.components.fire * 4.0, "Preview uses pre-defense fire")
			var actual_burn: Dictionary = Burn.from_fire_hit(resolved.components.fire, cast.snapshot.burn_policy)
			check(actual_burn.ok, "Same policy executes in actual burn rules")
			near(actual_burn.raw_dps, profile.dps, "Real noncritical burn matches displayed DPS")
		if skill == "tornado":
			check(Damage.resolve(cast.packets.secondary, cast.snapshot.modifiers) == Damage.resolve(base.packets.secondary, base.snapshot.modifiers), "Independent explosion avoids Ember damage penalty")
			check(not cast.burn_profile.roles.has("secondary"), "Independent explosion has no burn profile")
		var zero: Dictionary = Compiler.compile_group(skill, Combat.snapshot({"damage": 0.0}, []), [ID])
		check(zero.ok, "Zero damage remains displayable")
		if zero.ok:
			for role: String in _roles(skill):
				check(zero.burn_profile.roles[role] == {"fire_before_defense": 0.0, "dps": 0.0, "total": 0.0}, "Zero-fire preview has three zero values")
				check(not Burn.from_fire_hit(0.0, zero.snapshot.burn_policy).ok, "Zero fire cannot start burning")


func _test_composition() -> void:
	for skill: String in ["meteor", "tornado"]:
		for support: String in Supports.supports_for_skill(skill):
			if support in [ID, "ignite"]: continue
			pairs += 1
			_check_composition(skill, [support, ID])
		_check_composition(skill, [ID, "fire_focus", "efficiency", "quickcast", "concentrate"] if skill == "meteor" else [ID, "fire_focus", "focus", "volley", "efficiency"])


func _check_composition(skill: String, links: Array) -> void:
	var raw: Dictionary = _snapshot()
	var before: PackedByteArray = var_to_bytes(raw)
	var links_before: PackedByteArray = var_to_bytes(links)
	var cast: Dictionary = Compiler.compile_group(skill, raw, links)
	check(cast.ok, "Compatible Ember combination: %s/%s" % [skill, str(links)])
	if not cast.ok: return
	var reverse: Array = links.duplicate()
	reverse.reverse()
	check(var_to_bytes(cast) == var_to_bytes(Compiler.compile_group(skill, raw, reverse)), "Order reversal preserves complete cast bytes")
	check(before == var_to_bytes(raw) and links_before == var_to_bytes(links), "Composition is side-effect free")
	var without: Array = links.duplicate()
	without.erase(ID)
	var base: Dictionary = Compiler.compile_group(skill, raw, without)
	check(base.ok and cast.recipe == base.recipe and cast.packets == base.packets, "Old support recipe and base assembly retained")
	near(cast.mana, base.mana * 1.30, "Costs compose exactly once")
	near(cast.cooldown, base.cooldown, "Other support cooldown retained")
	check(_ember_modifiers(cast.snapshot) == 1, "One Ember primary modifier")
	for role: String in _roles(skill):
		var resolved: Dictionary = Damage.resolve(cast.packets[role], cast.snapshot.modifiers)
		var original: Dictionary = Damage.resolve(base.packets[role], base.snapshot.modifiers)
		for type: String in original.components: near(resolved.components[type], original.components[type] * 0.75, "Composed primary factor once: " + type)
		near(cast.burn_profile.roles[role].dps, resolved.components.fire * 0.20, "Composed preview follows final noncritical fire")
	if skill == "tornado":
		check(Damage.resolve(cast.packets.secondary, cast.snapshot.modifiers) == Damage.resolve(base.packets.secondary, base.snapshot.modifiers), "Composed independent explosion remains unchanged")


func _test_detachment_and_injection() -> void:
	var raw: Dictionary = _snapshot()
	var before: PackedByteArray = var_to_bytes(raw)
	var cast: Dictionary = Compiler.compile_group("tornado", raw, [ID])
	var other: Dictionary = Compiler.compile_group("tornado", raw, [ID])
	check(not Compiler.compile_group("tornado", cast.snapshot, [ID]).ok, "Compiled cast cannot re-enter compiler")
	for field: String in ["burn_policy", "burn_proliferation"]:
		for injected: Variant in [POLICY, SPREAD, {}, true, null, "bad", {"enabled": false}, {"radius": NAN}]:
			var poisoned: Dictionary = raw.duplicate(true)
			poisoned[field] = injected
			var poison_before: PackedByteArray = var_to_bytes(poisoned)
			check(not Compiler.compile_group("tornado", poisoned, []).ok, "Raw snapshot cannot inject reserved field: " + field)
			check(not Compiler.compile_basic(poisoned).ok, "Basic snapshot cannot inject reserved field: " + field)
			check(var_to_bytes(poisoned) == poison_before, "Invalid snapshot rejection is pure")
	cast.snapshot.burn_policy.duration = 9.0
	cast.snapshot.burn_proliferation.radius = 900.0
	cast.burn_profile.roles.parent.dps = 999.0
	cast.burn_profile.proliferation.max_targets = 99
	cast.snapshot.compiled_packets.parent.base.fire = 999.0
	check(cast.burn_profile.duration == 3.0 and cast.burn_profile.proliferation.radius == 120.0, "Preview policies do not alias snapshot policies")
	check(cast.snapshot.burn_proliferation.max_targets == 8, "Profile mutation cannot alter snapshot spread policy")
	check(other.snapshot.burn_policy == POLICY and other.snapshot.burn_proliferation == SPREAD, "Separate casts have independent policies")
	check(Ember.POLICY == POLICY and Proliferation.POLICY == SPREAD and before == var_to_bytes(raw), "Mutable output cannot alter static policies or input")
	check(other == Compiler.compile_group("tornado", raw, [ID]), "Later casts are unchanged after output mutation")


func _test_projectile_lineage_and_explosion() -> void:
	var cast: Dictionary = Compiler.compile_group("tornado", _snapshot(true), [ID, "fire_focus", "volley"])
	var critical = CriticalRuntime.new()
	critical.reset(47)
	var frozen: Dictionary = critical.freeze(cast.snapshot).snapshot
	var before: PackedByteArray = var_to_bytes(frozen)
	var runtime = Runtime.new()
	var shots: Array[Dictionary] = []
	check(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, frozen, 100, cast.initial_count) == 5, "Volley spawns five frozen parents")
	for shot: Dictionary in shots:
		check(shot.snapshot == frozen and _ember_modifiers(shot.snapshot) == 1, "Parent preserves frozen policies and one modifier")
	var events: Array[Dictionary] = runtime.advance(shots, 0.5, [], Vector2.ZERO, 100)
	check(_count(events, "split") == 5 and shots.size() == 15, "All five parents split into three children")
	for child: Dictionary in shots:
		check(child.snapshot == frozen and child.snapshot.burn_policy == POLICY and child.snapshot.burn_proliferation == SPREAD, "Child inherits original policies")
		check(_ember_modifiers(child.snapshot) == 1 and child.snapshot.critical_roll == frozen.critical_roll, "Child neither reapplies support nor rerolls critical")
	events = runtime.advance(shots, 0.5, [], Vector2.ZERO, 100)
	check(_count(events, "return_started") == 15, "All children enter return phase")
	for child: Dictionary in shots:
		check(child.state == "returning" and child.snapshot == frozen, "Returning child keeps original frozen policies")
	check(var_to_bytes(frozen) == before and critical.events == 1, "Lineage is pure and uses one critical freeze")
	for reason: String in ["range_consumed", "lifetime_expired"]:
		var ending = Runtime.new()
		var snapshot: Dictionary = cast.snapshot.duplicate(true)
		snapshot.effects = ["explode_on_flight_end"]
		var source_before: PackedByteArray = var_to_bytes(snapshot)
		var spec: Dictionary = {"speed": 200.0, "range": 20.0 if reason == "range_consumed" else 1000.0,
			"lifetime": 10.0 if reason == "range_consumed" else 0.1, "radius": 4.0, "pierce": -1, "role": "child", "split": false}
		var carrier: Dictionary = ending.make_projectile(Vector2.ZERO, Vector2.RIGHT, spec, Combat.event_packet(snapshot, "tornado", "child"), snapshot, ending.new_cast(), Color.WHITE)
		var carriers: Array[Dictionary] = [carrier]
		var endings: Array[Dictionary] = ending.advance(carriers, 0.2, [], Vector2.ZERO, 100)
		check(carriers.is_empty() and carrier.end_reason == reason and _count(endings, "explosion") == 1, "One independent natural explosion: " + reason)
		for event: Dictionary in endings:
			if event.type != "explosion": continue
			check(not event.snapshot.has("burn_policy") and not event.snapshot.has("burn_proliferation"), "Independent explosion carries no burn or propagation policy")
			check(event.payload == cast.packets.secondary, "Explosion keeps its independent packet")
		check(var_to_bytes(snapshot) == source_before, "Explosion policy cleanup never mutates parent snapshot")


func _ember_modifiers(snapshot: Dictionary) -> int:
	var count: int = 0
	for modifier: Dictionary in snapshot.modifiers:
		if modifier.get("id") == "support:" + ID: count += 1
	return count


func _count(events: Array[Dictionary], type: String) -> int:
	var count: int = 0
	for event: Dictionary in events:
		if event.type == type: count += 1
	return count


func _test_frozen_v046() -> void:
	check(FileAccess.file_exists(BASELINE), "Frozen-v046 external probe fixture exists")
	if not FileAccess.file_exists(BASELINE): return
	var file = FileAccess.open(BASELINE, FileAccess.READ)
	var baseline: Dictionary = file.get_var(false)
	file.close()
	check(baseline.schema == 1 and baseline.source_has_ignite and not baseline.source_has_ember, "Oracle used real pre-Ember v046 with Ignite")
	var ignite_casts: int = 0
	var plain_casts: int = 0
	for record: Dictionary in baseline.records:
		var before: PackedByteArray = var_to_bytes(record.snapshot)
		var current: Dictionary = Compiler.compile_basic(record.snapshot) if record.skill == "basic" else Compiler.compile_group(record.skill, record.snapshot, record.supports)
		check(current.ok and var_to_bytes(current) == record.cast_bytes, "Entire old cast matches frozen v046 bytes: " + record.id)
		check(var_to_bytes(record.snapshot) == before, "Frozen oracle input remains unchanged: " + record.id)
		if not current.ok: continue
		check(not current.snapshot.has("burn_proliferation"), "Old casts gain no propagation snapshot field")
		if record.supports.has("ignite"):
			ignite_casts += 1
			check(current.snapshot.burn_policy == Burn.PLAYER_POLICY and not current.burn_profile.has("proliferation"), "Ignite keeps exact old policy and profile shape")
		else:
			plain_casts += 1
			check(not current.has("burn_profile") and not current.snapshot.has("burn_policy"), "No-burning cast gains no burning fields")
		frozen_casts += 1
	check(frozen_casts == 38 and ignite_casts == 8 and plain_casts == 30, "38 focused old casts include eight Ignite and thirty no-burning cases")
