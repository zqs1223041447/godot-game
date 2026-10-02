extends SceneTree
## Shared defense contract: deterministic typed mitigation, then shield and health.

const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const Balance = preload("res://scripts/mechanics/passive_balance_adapter.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_support_and_origin()
	_test_profile()
	_test_mitigation_and_order()
	_test_resolver_compatibility()
	_test_invalid_hits()
	_test_invalid_resolved_hits()
	_test_copies_and_repeatability()
	print("Shared defense rules: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(is_equal_approx(value, expected), "%s (actual %.9f, expected %.9f)" % [label, value, expected])


func _rejected(result: Dictionary, label: String) -> void:
	_expect(result.get("ok") == false and not str(result.get("reason", "")).is_empty(), label)
	_expect(result.size() == 2, label + ": failure returns no partial settlement or profile")


func _test_support_and_origin() -> void:
	for actor: String in ["player", "monster"]:
		_expect(Defense.supports_stat("fire_resistance", actor), "Fire defense supports " + actor)
		_expect(Defense.support_reason("fire_resistance", actor).is_empty(), "Supported actor has no rejection reason")
		for stat: String in ["armor", "fire_penetration", "cold_resistance", "lightning_resistance", "chaos_resistance", "ailment_immunity", "chaos_bypass", "damage", ""]:
			_expect(not Defense.supports_stat(stat, actor), "Unsupported defense stat rejects: " + actor + "/" + stat)
			_rejected(Defense.defense_profile({"fire_resistance": 0.25, stat: 0.1}, actor), "Mixed unsupported profile rejects atomically")
		for stage: String in ["hit_base", "local_weapon", "ailment", "penetration", "shield_bypass", ""]:
			_expect(not Defense.supports_stat("fire_resistance", actor, stage), "Unsupported stage rejects: " + stage)
			_rejected(Defense.defense_profile({"fire_resistance": 0.25}, actor, stage), "Stage cannot enter through profile")
	_expect(not Defense.supports_stat("fire_resistance", "ally"), "Unknown actors reject")
	_rejected(Defense.defense_profile({}, "ally"), "Empty stats cannot bypass actor check")
	_expect(Registry.PLAYER_STATS.has("fire_resistance") and Registry.MONSTER_STATS.has("fire_resistance"), "Registry declares the same defense for both actors")
	_expect(not Balance.player_caps().has("fire_resistance"), "Original fire defense does not invent a sourced passive cap")
	_expect(Registry.get_ids().size() == 23, "Original defense does not alter sourced passive bundle identities")
	var info: Dictionary = Defense.metadata()
	_expect(info.origin == "original" and info.source_refs.is_empty(), "Metadata never labels authored fire defense as sourced PoE data")
	_expect(info.supported_actors == ["player", "monster"] and info.stage == "hit_mitigation", "Catalog has exact actor and stage support")
	_near(info.maximum_effective, 0.75, "Catalog cap comes from shared authority")
	_expect(info.settlement_order == ["resistance", "shield", "health"], "Catalog reflects executable settlement order")


func _test_profile() -> void:
	var neutral: Dictionary = Defense.defense_profile({})
	_expect(neutral.ok, "Missing defense stat is the neutral profile")
	_near(neutral.raw_resistances.fire, 0.0, "Neutral raw fire resistance")
	_near(neutral.effective_resistances.fire, 0.0, "Neutral effective fire resistance")
	for actor: String in ["player", "monster"]:
		var capped: Dictionary = Defense.defense_profile({"fire_resistance": 1.2}, actor)
		_near(capped.raw_resistances.fire, 1.2, "Raw total remains visible above cap: " + actor)
		_near(capped.effective_resistances.fire, 0.75, "Both actors use the authored effective cap: " + actor)
		var floor: Dictionary = Defense.defense_profile({"fire_resistance": -0.25}, actor)
		_near(floor.raw_resistances.fire, -0.25, "Finite raw total is retained below floor")
		_near(floor.effective_resistances.fire, 0.0, "Authored profile cannot create negative effective resistance")
	for malformed: Variant in [null, [], true, "0.25", 0.25]:
		_rejected(Defense.defense_profile(malformed), "Defense stats require a dictionary")
	for malformed: Variant in [null, {}, [], true, "0.25", NAN, INF, -INF]:
		_rejected(Defense.defense_profile({"fire_resistance": malformed}), "Defense value must be a finite scalar")
	_rejected(Defense.defense_profile({1: 0.25}), "Numeric defense keys reject")


func _test_mitigation_and_order() -> void:
	for actor: String in ["player", "monster"]:
		var hit: Dictionary = Defense.incoming_hit({"physical": 20.0, "fire": 20.0}, {"fire_resistance": 0.25}, 10.0, 100.0, actor)
		_expect(hit.ok and hit.actor == actor, "Same hit settles for " + actor)
		_expect(hit.raw_components == {"physical": 20.0, "fire": 20.0}, "Trace preserves pre-defense components")
		_expect(hit.components == {"physical": 20.0, "fire": 15.0}, "Only fire component is reduced")
		_expect(hit.mitigated_components == {"physical": 0.0, "fire": 5.0}, "Trace distinguishes prevented damage")
		_near(hit.damage_total, 35.0, "20 physical + 20 fire at 25% fire resistance = 35")
		_near(hit.shield_spent, 10.0, "Mitigated hit spends shield first")
		_near(hit.health_lost, 25.0, "Only remaining 25 reaches health")
		_near(hit.remaining_shield, 0.0, "Shield depletes")
		_near(hit.remaining_health, 75.0, "Health is 75 after the mixed hit")
		_near(hit.overkill, 0.0, "Nonlethal hit has no overkill")
	var five: Dictionary = Defense.incoming_hit({"physical": 20.0, "fire": 20.0, "cold": 20.0, "lightning": 20.0, "chaos": 20.0}, {"fire_resistance": 3.0}, 100.0, 30.0)
	_expect(five.ok and five.components.size() == 5, "All five known damage types remain distinct")
	_near(five.damage_total, 85.0, "75% authored fire cap does not mitigate other types")
	_near(five.shield_spent, 85.0, "Chaos consumes shield under this original bounded rule")
	_near(five.health_lost, 0.0, "No implicit chaos bypass")
	_near(five.remaining_shield, 15.0, "Unused shield remains")
	var lethal: Dictionary = Defense.incoming_hit({"physical": 50.0}, {}, 10.0, 25.0)
	_near(lethal.health_lost, 25.0, "Health loss never exceeds available health")
	_near(lethal.remaining_health, 0.0, "Lethal settlement floors health")
	_near(lethal.overkill, 15.0, "Excess damage is explicit for legacy enemy health adapters")
	var empty: Dictionary = Defense.incoming_hit({}, {}, 10.0, 20.0)
	_expect(empty.ok and empty.components.is_empty(), "Empty hit is valid zero damage")
	_near(empty.remaining_shield, 10.0, "Empty hit keeps shield")
	_near(empty.remaining_health, 20.0, "Empty hit keeps health")
	var zero: Dictionary = Defense.incoming_hit({"fire": 0}, {}, 0, 0)
	_expect(zero.ok and zero.damage_total == 0.0, "Zero components/resources are valid")


func _test_resolver_compatibility() -> void:
	var packet: Dictionary = Damage.packet({"physical": 20.0, "fire": 20.0}, ["hit", "spell"], "test")
	var modifiers: Array = [{"id": "test_more", "mode": "more", "value": 0.5}]
	var resolved: Dictionary = Damage.resolve(packet, modifiers, {"physical": -99.0, "fire": 99.0})
	var settled: Dictionary = Defense.settle_resolved(resolved, 10.0, 100.0)
	_expect(settled.ok, "Shared settlement accepts the existing resolver compatibility range")
	_near(settled.raw_components.physical, 30.0, "Shared settlement retains already applied offensive modifiers")
	_near(settled.components.physical, 60.0, "Resolver still clamps legacy negative resistance at -100%")
	_near(settled.components.fire, 3.0, "Resolver still clamps legacy high resistance at 90%")
	_near(settled.damage_total, resolved.total, "Settlement never applies fire resistance twice")
	_near(settled.mitigated_components.physical, -30.0, "Legacy amplification is visible as negative prevention")
	_near(settled.health_lost, 53.0, "Existing resolved damage uses the same shield-health order")
	var direct: Dictionary = Damage.resolve(Damage.packet({"physical": 20.0, "fire": 20.0}, ["hit"], "incoming_hit"), [], {"fire": 0.25})
	var original: Dictionary = Defense.settle_resolved(direct, 10.0, 100.0)
	var incoming: Dictionary = Defense.incoming_hit({"physical": 20.0, "fire": 20.0}, {"fire_resistance": 0.25}, 10.0, 100.0)
	for field: String in ["raw_components", "components", "mitigated_components", "damage_total", "shield_spent", "health_lost", "remaining_shield", "remaining_health", "overkill", "details"]:
		_expect(original[field] == incoming[field], "Incoming and outgoing share the exact production path: " + field)


func _test_invalid_hits() -> void:
	for malformed: Variant in [null, [], "20", 20.0, true]:
		_rejected(Defense.incoming_hit(malformed, {}, 10.0, 100.0), "Hit components require an object")
	for malformed: Variant in [null, {}, [], [10, 20], "20", true, -1.0, NAN, INF, -INF]:
		_rejected(Defense.incoming_hit({"physical": 20.0, "fire": malformed}, {}, 10.0, 100.0), "Malformed mixed component rejects the complete hit")
	for key: Variant in ["poison", "fire_resistance", "damage", "stage", 0, true]:
		_rejected(Defense.incoming_hit({"physical": 20.0, key: 10.0}, {}, 10.0, 100.0), "Unknown or nonstring damage type rejects")
	for malformed: Variant in [null, {}, [], "10", true, -1.0, NAN, INF, -INF]:
		_rejected(Defense.incoming_hit({"fire": 20.0}, {}, malformed, 100.0), "Invalid shield rejects before settlement")
		_rejected(Defense.incoming_hit({"fire": 20.0}, {}, 10.0, malformed), "Invalid health rejects before settlement")
	_rejected(Defense.incoming_hit({"physical": 1.0e308, "fire": 1.0e308}, {}, 0.0, 100.0), "Finite components cannot overflow their sum")
	_rejected(Defense.incoming_hit({"fire": 20.0}, {"fire_resistance": 0.25, "penetration": 1.0}, 10.0, 100.0), "Unsupported defense stage cannot ride along with a supported stat")
	_rejected(Defense.incoming_hit({"fire": 20.0}, {}, 10.0, 100.0, "unknown"), "Unknown actor cannot settle an incoming hit")


func _test_invalid_resolved_hits() -> void:
	var valid: Dictionary = Damage.resolve(Damage.packet({"physical": 20.0, "fire": 20.0}, [], "test"), [], {"fire": 0.25})
	for malformed: Variant in [null, [], "35", 35, {}, {"total": 35.0, "components": {"fire": 35.0}}]:
		_rejected(Defense.settle_resolved(malformed, 10.0, 100.0), "Malformed resolved contract rejects")
	var forged: Dictionary = valid.duplicate(true)
	forged["chaos_bypass"] = true
	_rejected(Defense.settle_resolved(forged, 10.0, 100.0), "Unknown settlement instructions reject")
	for malformed: Variant in [NAN, INF, -1, "35", true, 36.0]:
		forged = valid.duplicate(true)
		forged.total = malformed
		_rejected(Defense.settle_resolved(forged, 10.0, 100.0), "Invalid or inconsistent resolved total rejects")
	for malformed: Variant in [null, {}, "details", [], [null], [valid.details[0]], [valid.details[0], valid.details[0]]]:
		forged = valid.duplicate(true)
		forged.details = malformed
		_rejected(Defense.settle_resolved(forged, 10.0, 100.0), "Invalid, missing or repeated resolved details reject")
	for field: String in ["before_defense", "final", "resistance"]:
		for malformed: Variant in [null, {}, [], true, "0.25", NAN, INF, -INF]:
			forged = valid.duplicate(true)
			forged.details[0][field] = malformed
			_rejected(Defense.settle_resolved(forged, 10.0, 100.0), "Resolved detail numeric contract rejects: " + field)
	forged = valid.duplicate(true)
	forged.details[0].final = 21.0
	_rejected(Defense.settle_resolved(forged, 10.0, 100.0), "Detail/component mismatch rejects")
	forged = valid.duplicate(true)
	forged.details[0].resistance = 0.95
	_rejected(Defense.settle_resolved(forged, 10.0, 100.0), "Out-of-contract resistance rejects")
	_rejected(Defense.settle_resolved(valid, -1.0, 100.0), "Settlement validates shield independently")
	_rejected(Defense.settle_resolved(valid, 10.0, NAN), "Settlement validates health independently")


func _test_copies_and_repeatability() -> void:
	var components: Dictionary = {"physical": 20.0, "fire": 20.0}
	var stats: Dictionary = {"fire_resistance": 0.25}
	var before_components: Dictionary = components.duplicate(true)
	var before_stats: Dictionary = stats.duplicate(true)
	var result: Dictionary = Defense.incoming_hit(components, stats, 10.0, 100.0)
	var same: Dictionary = Defense.incoming_hit(components, stats, 10.0, 100.0)
	_expect(result == same, "Repeated hits are deterministic without RNG")
	_expect(components == before_components and stats == before_stats, "Successful resolution never mutates caller dictionaries")
	components.fire = 1000.0
	stats.fire_resistance = 0.75
	_near(result.raw_components.fire, 20.0, "Raw components do not alias incoming data")
	_near(result.raw_resistances.fire, 0.25, "Raw resistance does not alias caller stats")
	result.components.fire = 999.0
	result.raw_components.fire = 999.0
	result.effective_resistances.fire = 0.0
	result.details[1].modifiers.append("changed")
	_near(same.components.fire, 15.0, "Output components do not alias another result")
	_near(same.raw_components.fire, 20.0, "Raw output does not alias another result")
	_expect(same.details[1].modifiers.is_empty(), "Nested detail copies stay detached")
	var resolved: Dictionary = Damage.resolve(Damage.packet(before_components, [], "test"), [], {"fire": 0.25})
	var settled: Dictionary = Defense.settle_resolved(resolved, 10.0, 100.0)
	settled.details[0].modifiers.append("changed")
	settled.components.physical = 999.0
	_expect(resolved.details[0].modifiers.is_empty(), "Settlement copies nested resolver metadata")
	_near(resolved.components.physical, 20.0, "Settlement does not mutate resolver components")
	var copied: Dictionary = Defense.validate_components(before_components)
	copied.components.fire = 500.0
	_near(before_components.fire, 20.0, "Standalone component validation returns copied scalar data")
	var info: Dictionary = Defense.metadata()
	info.supported_actors.clear()
	info.settlement_order.clear()
	_expect(Defense.metadata().supported_actors.size() == 2 and Defense.metadata().settlement_order.size() == 3, "Catalog metadata cannot mutate rule authority")
	_near(Defense.incoming_hit({"fire": 20.0}, {"fire_resistance": 2.0}, 0.0, 100.0).damage_total, 5.0, "Mutating metadata cannot alter the cap")
