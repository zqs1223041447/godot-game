extends SceneTree
## Focused v45 compile/snapshot contracts, with the actual released v44 PCK oracle.
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Burn = preload("res://scripts/combat/burn_rules.gd")
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")
const CriticalRuntime = preload("res://scripts/combat/critical_strike_runtime.gd")
const Data = preload("res://scripts/game_data.gd")
const POLICY: Dictionary = {"duration": 3.0, "rate_fraction": 0.30, "hit_multiplier": 0.75, "mana_multiplier": 1.20}
const BASELINE: String = "res://docs/qa/v045/ignite-compile-v44.bin"
var checks: int = 0
var failures: int = 0
var pair_count: int = 0
var frozen_casts: int = 0

func _initialize() -> void:
	var sources_before: Dictionary = _source_hashes()
	_test_admission()
	_test_profiles_and_scopes()
	_test_support_composition()
	_test_detachment_and_recompile()
	_test_projectile_lineage()
	_test_projectile_endings()
	_test_released_baseline()
	check(_source_hashes() == sources_before, "Relevant production source hashes unchanged during test")
	print("Ignite compilation: %d checks, %d failures; %d compatible Ignite pairs; %d exact released-v44 casts" % [checks, failures, pair_count, frozen_casts])
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
		"spell_added_cold": 15.0, "spell_added_lightning": 7.0}
	if critical:
		stats.crit_base_chance = 1.0
		stats.crit_base_multiplier = 2.0
	return Combat.snapshot(stats, ["return_on_range", "explode_on_flight_end"])

func _roles(skill: String) -> Array:
	return ["parent", "child"] if skill == "tornado" else ["direct"]

func _test_admission() -> void:
	check(Data.SKILLS.size() == 10, "All ten active skills are accounted for")
	check(Burn.PLAYER_POLICY == POLICY, "Player Ignite policy is exactly 3s, 30%, hit .75 and mana 1.20")
	var definition: Dictionary = Supports.get_definition("ignite")
	check(definition.get("skills") == ["meteor", "tornado"], "Ignite has exactly the two authored native-fire skills")
	var valid: int = 0
	var invalid: int = 0
	var enriched: Dictionary = _snapshot()
	enriched.added_damage.attack.fire = 999.0
	enriched.added_damage.spell.merge({"fire": 999.0})
	for skill: String in Data.SKILLS:
		var allowed: bool = skill in ["meteor", "tornado"]
		var enriched_base: Dictionary = Compiler.compile_group(skill, enriched, [])
		check(enriched_base.ok, "Added-fire eligibility fixture itself is valid: " + skill)
		if enriched_base.ok and not allowed and skill not in ["dash", "ward"]:
			var packet: Dictionary = enriched_base.packets.bounces[0] if skill == "chain" else enriched_base.packets["direct" if skill in ["nova", "cleave"] else "projectile"]
			check(float(packet.base.get("fire", 0.0)) > 0.0, "Ineligible offensive skill actually receives added fire: " + skill)
		check(Supports.compatibility_reason(skill, ["ignite"]).is_empty() == allowed, "Registry eligibility: " + skill)
		check(Compiler.compile_group(skill, _snapshot(), ["ignite"]).ok == allowed, "Compiler eligibility: " + skill)
		var added_ignite: Dictionary = Compiler.compile_group(skill, enriched, ["ignite"])
		var added_focus: Dictionary = Compiler.compile_group(skill, enriched, ["fire_focus"])
		check(added_ignite.ok == allowed, "Equipment-added fire cannot open Ignite eligibility: %s (%s)" % [skill, added_ignite.error])
		check(added_focus.ok == allowed, "Existing native fire-focus eligibility remains stable: %s (%s)" % [skill, added_focus.error])
		if allowed: valid += 1
		else: invalid += 1
	check(valid == 2 and invalid == 8, "Two accepted and all eight rejected active skills tested")
	check(not Compiler.compile_group("basic", enriched, ["ignite"]).ok, "Basic attacks reject Ignite")
	check(not Compiler.compile_group("tornado", _snapshot(), ["ignite", "ignite"]).ok, "Duplicate Ignite rejects")
	check(not Compiler.compile_group("tornado", _snapshot(), ["ignite", "focus", "volley", "fire_focus", "efficiency", "quickcast"]).ok, "A sixth support rejects")
	check(not Compiler.compile_skill("tornado", _snapshot(), ["ignite", "focus", "volley"]).ok, "Legacy two-slot limit remains enforced")

func _test_profiles_and_scopes() -> void:
	for skill: String in ["meteor", "tornado"]:
		var base: Dictionary = Compiler.compile_group(skill, _snapshot(), [])
		var cast: Dictionary = Compiler.compile_group(skill, _snapshot(), ["ignite"])
		check(base.ok and cast.ok, "Base and Ignite compile: " + skill)
		if not base.ok or not cast.ok: continue
		check(cast.snapshot.burn_policy == POLICY, "Execution snapshot owns exact burn policy: " + skill)
		check(cast.packets == base.packets and cast.recipe == base.recipe and cast.initial_count == base.initial_count, "Ignite leaves assembled packets and delivery recipe unchanged: " + skill)
		near(cast.mana, base.mana * 1.20, "Ignite cost once: " + skill)
		near(cast.cooldown, base.cooldown, "Ignite cooldown unchanged: " + skill)
		check(cast.burn_profile.enabled and cast.burn_profile.stacking == "strongest_refresh_equal", "Preview has enabled strongest/equal-refresh semantics: " + skill)
		check(cast.burn_profile.roles.keys() == _roles(skill), "Preview has only primary roles: " + skill)
		for key: String in POLICY: near(cast.burn_profile[key], POLICY[key], "Preview policy " + key)
		for role: String in _roles(skill):
			var original: Dictionary = Damage.resolve(base.packets[role], base.snapshot.modifiers)
			var resolved: Dictionary = Damage.resolve(cast.packets[role], cast.snapshot.modifiers)
			for type: String in original.components:
				near(resolved.components[type], original.components[type] * 0.75, "All primary components receive Ignite exactly once: %s/%s/%s" % [skill, role, type])
			var preview: Dictionary = cast.burn_profile.roles[role]
			near(preview.fire_before_defense, resolved.components.fire, "Preview uses post-primary-modifier fire: " + role)
			near(preview.dps, resolved.components.fire * 0.30, "Preview DPS: " + role)
			near(preview.total, resolved.components.fire * 0.30 * 3.0, "Preview three-second amount: " + role)
			var critical: Dictionary = Compiler.compile_group(skill, _snapshot(true), ["ignite"])
			check(critical.burn_profile == cast.burn_profile, "Preview excludes critical multiplier: " + role)
			var resisted: Dictionary = Damage.resolve(cast.packets[role], cast.snapshot.modifiers, {"fire": 0.75})
			near(preview.fire_before_defense, resisted.components.fire * 4.0, "Preview excludes target resistance: " + role)
		if skill == "tornado":
			check(Damage.resolve(cast.packets.secondary, cast.snapshot.modifiers) == Damage.resolve(base.packets.secondary, base.snapshot.modifiers), "Independent secondary explosion is not penalized")
			check(not cast.burn_profile.roles.has("secondary"), "Independent explosion has no burn preview role")
		var zero: Dictionary = Compiler.compile_group(skill, Combat.snapshot({"damage": 0.0}, []), ["ignite"])
		check(zero.ok, "Zero-damage cast remains a valid displayable cast: " + skill)
		if zero.ok:
			for role: String in _roles(skill):
				check(zero.burn_profile.roles[role] == {"fire_before_defense": 0.0, "dps": 0.0, "total": 0.0}, "Zero damage displays zero burn: " + role)
				check(not Burn.from_fire_hit(zero.burn_profile.roles[role].fire_before_defense, zero.snapshot.burn_policy).ok, "Zero fire cannot start a burn: " + role)

func _test_support_composition() -> void:
	for skill: String in ["meteor", "tornado"]:
		for support: String in Supports.supports_for_skill(skill):
			if support == "ignite": continue
			pair_count += 1
			_check_composition(skill, [support, "ignite"])
		_check_composition(skill, ["ignite", "fire_focus", "efficiency", "quickcast", "concentrate"] if skill == "meteor" else ["ignite", "fire_focus", "focus", "volley", "efficiency"])
	var focused: Dictionary = Compiler.compile_group("tornado", _snapshot(), ["fire_focus", "ignite"])
	var plain: Dictionary = Compiler.compile_group("tornado", _snapshot(), ["ignite"])
	for role: String in _roles("tornado"):
		var a: Dictionary = Damage.resolve(focused.packets[role], focused.snapshot.modifiers)
		var b: Dictionary = Damage.resolve(plain.packets[role], plain.snapshot.modifiers)
		near(a.components.fire, b.components.fire * 1.20, "Fire-focus fire multiplier combines once: " + role)
		near(a.components.physical, b.components.physical * 0.80, "Fire-focus off-type multiplier combines once: " + role)
		near(focused.burn_profile.roles[role].dps, plain.burn_profile.roles[role].dps * 1.20, "Fire-focus increases burn through original fire hit once: " + role)

func _check_composition(skill: String, links: Array) -> void:
	var before: Array = links.duplicate(true)
	var raw: Dictionary = _snapshot()
	var raw_before: PackedByteArray = var_to_bytes(raw)
	var cast: Dictionary = Compiler.compile_group(skill, raw, links)
	var reverse: Array = links.duplicate()
	reverse.reverse()
	check(cast.ok, "Compatible Ignite links compile: %s/%s" % [skill, str(links)])
	if not cast.ok: return
	check(var_to_bytes(cast) == var_to_bytes(Compiler.compile_group(skill, raw, reverse)), "Support order gives exact identical compiled bytes: %s/%s" % [skill, str(links)])
	check(links == before and raw_before == var_to_bytes(raw), "Composition never mutates input")
	var without: Array = links.duplicate()
	without.erase("ignite")
	var base: Dictionary = Compiler.compile_group(skill, raw, without)
	check(base.ok and cast.recipe == base.recipe and cast.packets == base.packets, "Existing support delivery and base assembly preserved")
	near(cast.mana, base.mana * 1.20, "Mana composes once with existing supports")
	near(cast.cooldown, base.cooldown, "Existing support cooldown preserved")
	check(_ignite_modifiers(cast.snapshot) == 1, "Only one primary Ignite modifier")
	for role: String in _roles(skill):
		var a: Dictionary = Damage.resolve(cast.packets[role], cast.snapshot.modifiers)
		var b: Dictionary = Damage.resolve(base.packets[role], base.snapshot.modifiers)
		for type: String in b.components: near(a.components[type], b.components[type] * 0.75, "Composition scales primary component once: " + type)
		near(cast.burn_profile.roles[role].dps, a.components.fire * 0.30, "Composition preview follows all primary modifiers once")
	if skill == "tornado":
		check(Damage.resolve(cast.packets.secondary, cast.snapshot.modifiers) == Damage.resolve(base.packets.secondary, base.snapshot.modifiers), "Composition leaves independent secondary damage unchanged")

func _test_detachment_and_recompile() -> void:
	var raw: Dictionary = _snapshot()
	var before: PackedByteArray = var_to_bytes(raw)
	var cast: Dictionary = Compiler.compile_group("tornado", raw, ["ignite"])
	var other: Dictionary = Compiler.compile_group("tornado", raw, ["ignite"])
	check(before == var_to_bytes(raw), "Ignite compilation is pure")
	check(not Compiler.compile_group("tornado", cast.snapshot, ["ignite"]).ok, "Compiled burn snapshot cannot be compiled again")
	for injected: Variant in [POLICY, {}, {"duration": true, "rate_fraction": 0.3}, {"duration": 3.0, "rate_fraction": NAN}, "bad"]:
		var poisoned: Dictionary = raw.duplicate(true)
		poisoned.burn_policy = injected
		check(not Compiler.compile_group("tornado", poisoned, []).ok, "Raw input cannot inject any burn_policy")
		check(not Compiler.compile_basic(poisoned).ok, "Basic compile cannot smuggle burn_policy")
	cast.snapshot.burn_policy.duration = 9.0
	cast.burn_profile.roles.parent.dps = 999.0
	cast.burn_profile.rate_fraction = 9.0
	cast.snapshot.compiled_packets.parent.base.fire = 999.0
	check(cast.burn_profile.duration == 3.0, "Preview is detached from snapshot policy")
	check(other.snapshot.burn_policy == POLICY and other.burn_profile.rate_fraction == 0.30, "Independent casts own independent policies")
	check(Burn.PLAYER_POLICY == POLICY and before == var_to_bytes(raw), "Output mutation cannot alter static policy or raw input")
	check(other == Compiler.compile_group("tornado", raw, ["ignite"]), "Output mutation cannot alter later casts")

func _test_projectile_lineage() -> void:
	var raw: Dictionary = _snapshot(true)
	var cast: Dictionary = Compiler.compile_group("tornado", raw, ["ignite", "fire_focus", "volley"])
	var critical = CriticalRuntime.new()
	critical.reset(45)
	var frozen: Dictionary = critical.freeze(cast.snapshot).snapshot
	var frozen_before: PackedByteArray = var_to_bytes(frozen)
	var runtime = Runtime.new()
	var shots: Array[Dictionary] = []
	check(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, frozen, 100, cast.initial_count) == 5, "Volley launches exactly five frozen parents")
	for shot: Dictionary in shots:
		check(shot.snapshot == frozen and _ignite_modifiers(shot.snapshot) == 1, "Parent inherits frozen burn and critical state once")
	raw.base_damage = 900.0
	cast.snapshot.burn_policy.duration = 40.0
	var events: Array[Dictionary] = runtime.advance(shots, 0.5, [], Vector2.ZERO, 100)
	check(_count(events, "split") == 5 and shots.size() == 15, "Each frozen parent splits into exactly three children")
	check(_count(events, "explosion") == 0, "Splitting is not a natural explosion ending")
	for child: Dictionary in shots:
		check(child.snapshot == frozen and child.snapshot.burn_policy == POLICY and _ignite_modifiers(child.snapshot) == 1, "Child keeps original policy without reapplying Ignite")
		check(child.snapshot.critical_roll == frozen.critical_roll, "Child inherits the already-frozen critical roll")
	events = runtime.advance(shots, 0.5, [], Vector2.ZERO, 100)
	check(_count(events, "return_started") == 15 and shots.size() == 15, "All children enter the return phase once")
	for returning: Dictionary in shots:
		check(returning.state == "returning" and returning.snapshot == frozen, "Returning child preserves original frozen snapshot")
		check(_ignite_modifiers(returning.snapshot) == 1, "Returning child has exactly one Ignite modifier")
	check(var_to_bytes(frozen) == frozen_before and critical.events == 1, "Lineage neither mutates source snapshot nor rerolls critical")
	# Contact events carry the same immutable policy for outbound and returning phases.
	for phase: String in ["outbound", "returning"]:
		var single: Dictionary = _carrier(runtime, frozen, {"range": 1000.0})
		single.state = phase
		var contact_shots: Array[Dictionary] = [single]
		var targets: Array[Dictionary] = [{"id": 1, "pos": Vector2(40, 0), "radius": 5.0, "health": 100.0, "spawn": 0.0}]
		var contacts: Array[Dictionary] = runtime.advance(contact_shots, 0.3, targets, Vector2.ZERO, 100)
		check(_count(contacts, "hit") == 1, "Contact fixture hits in phase " + phase)
		for event: Dictionary in contacts:
			if event.type == "hit": check(event.snapshot == frozen and event.phase == phase and _ignite_modifiers(event.snapshot) == 1, "Hit event keeps original burn policy in phase " + phase)

func _test_projectile_endings() -> void:
	var cast: Dictionary = Compiler.compile_group("tornado", _snapshot(), ["ignite"])
	for reason: String in ["range_consumed", "lifetime_expired"]:
		var runtime = Runtime.new()
		var snapshot: Dictionary = cast.snapshot.duplicate(true)
		snapshot.effects = ["explode_on_flight_end"]
		var before: PackedByteArray = var_to_bytes(snapshot)
		var carrier: Dictionary = _carrier(runtime, snapshot, {"range": 20.0 if reason == "range_consumed" else 1000.0, "lifetime": 10.0 if reason == "range_consumed" else 0.1})
		var shots: Array[Dictionary] = [carrier]
		var events: Array[Dictionary] = runtime.advance(shots, 0.2, [], Vector2.ZERO, 100)
		check(shots.is_empty() and carrier.end_reason == reason and _count(events, "explosion") == 1, "Exactly one natural explosion: " + reason)
		for event: Dictionary in events:
			if event.type != "explosion": continue
			var clean: Dictionary = snapshot.duplicate(true)
			clean.erase("burn_policy")
			check(event.snapshot == clean and not event.snapshot.has("burn_policy"), "Natural explosion erases only burn policy: " + reason)
			check(event.payload == cast.packets.secondary, "Natural explosion retains independent secondary packet")
		check(var_to_bytes(snapshot) == before and carrier.snapshot.burn_policy == POLICY, "Explosion cannot strip parent snapshot in place")
		check(runtime.advance(shots, 1.0, [], Vector2.ZERO, 100).is_empty(), "Terminal carrier cannot explode twice")
	for ending: String in ["hit_consumed", "terrain_collision", "budget_cancelled", "run_reset"]:
		var runtime = Runtime.new()
		var carrier: Dictionary = _carrier(runtime, cast.snapshot, {"pierce": 0 if ending == "hit_consumed" else -1, "range": 20.0, "split": ending == "budget_cancelled", "role": "parent" if ending == "budget_cancelled" else "child"})
		var shots: Array[Dictionary] = [carrier]
		var targets: Array[Dictionary] = []
		if ending == "hit_consumed": targets.append({"id": 8, "pos": Vector2(10, 0), "radius": 2.0, "health": 100.0, "spawn": 0.0})
		var events: Array[Dictionary]
		if ending == "run_reset": events = runtime.cancel_all(shots)
		elif ending == "terrain_collision": events = runtime.advance(shots, 0.2, targets, Vector2.ZERO, 100, Callable(), func(_a: Vector2, _b: Vector2, _r: float) -> Dictionary: return {"hit": true, "fraction": 0.25})
		else: events = runtime.advance(shots, 0.2, targets, Vector2.ZERO, 1 if ending == "budget_cancelled" else 100)
		check(shots.is_empty() and carrier.end_reason == ending, "Nonnatural ending reached: " + ending)
		check(_count(events, "explosion") == 0 and _count(events, "flight_ended") == 0, "Nonnatural ending never dispatches explosion: " + ending)
		check(carrier.snapshot.burn_policy == POLICY, "Cancellation does not rewrite frozen policy: " + ending)

func _carrier(runtime, snapshot: Dictionary, changes: Dictionary = {}) -> Dictionary:
	var spec: Dictionary = {"speed": 200.0, "range": 1000.0, "lifetime": 10.0, "radius": 4.0, "pierce": -1, "role": "child", "split": false}
	spec.merge(changes, true)
	return runtime.make_projectile(Vector2.ZERO, Vector2.RIGHT, spec, Combat.event_packet(snapshot, "tornado", str(spec.role)), snapshot, runtime.new_cast(), Color.WHITE)

func _ignite_modifiers(snapshot: Dictionary) -> int:
	var count: int = 0
	for modifier: Dictionary in snapshot.modifiers:
		if modifier.get("id") == "support:ignite": count += 1
	return count

func _count(events: Array[Dictionary], type: String) -> int:
	var count: int = 0
	for event: Dictionary in events:
		if event.type == type: count += 1
	return count

func _test_released_baseline() -> void:
	check(FileAccess.file_exists(BASELINE), "Actual released-v44 external probe fixture exists")
	if not FileAccess.file_exists(BASELINE): return
	var file = FileAccess.open(BASELINE, FileAccess.READ)
	var baseline: Dictionary = file.get_var(false)
	file.close()
	check(baseline.schema == 1 and not baseline.source_has_ignite, "Oracle was produced by a pre-Ignite compiler")
	var base_skills: Dictionary = {}
	var rich_skills: Dictionary = {}
	var sizes: Dictionary = {0: 0, 2: 0, 5: 0}
	for record: Dictionary in baseline.records:
		var before: PackedByteArray = var_to_bytes(record.snapshot)
		var current: Dictionary = Compiler.compile_basic(record.snapshot) if record.skill == "basic" else Compiler.compile_group(record.skill, record.snapshot, record.supports)
		check(current.ok and var_to_bytes(current) == record.cast_bytes, "Exact var_to_bytes matches released v44: " + record.id)
		check(var_to_bytes(record.snapshot) == before, "Released oracle input remains unchanged: " + record.id)
		check(not current.has("burn_profile") and not current.snapshot.has("burn_policy"), "No-Ignite output acquires no burn fields: " + record.id)
		frozen_casts += 1
		sizes[record.supports.size()] += 1
		if record.supports.is_empty() and record.skill != "basic":
			if str(record.id).begins_with("base/"): base_skills[record.skill] = true
			else: rich_skills[record.skill] = true
	check(frozen_casts == 42 and base_skills.size() == 10 and rich_skills.size() == 10, "Frozen v44 covers all ten skills with base and rich fixtures plus basic")
	check(sizes == {0: 22, 2: 12, 5: 8}, "Frozen v44 includes twelve old pair and eight old five-support representative casts")

func _source_hashes() -> Dictionary:
	var result: Dictionary = {}
	var files: PackedStringArray = DirAccess.get_files_at("res://scripts/combat")
	files.sort()
	for file: String in files:
		if file.ends_with(".gd"): result["scripts/combat/" + file] = FileAccess.get_sha256("res://scripts/combat/" + file)
	for file: String in ["scripts/game_data.gd", "scripts/items/weapon_local_rules.gd"]:
		result[file] = FileAccess.get_sha256("res://" + file)
	return result
