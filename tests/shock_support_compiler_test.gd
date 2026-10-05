extends SceneTree
## Focused Shock admission, final cost, primary packet and acquisition contracts.
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Provider = preload("res://scripts/combat/shock_support_rules.gd")
const Shock = preload("res://scripts/combat/shock_rules.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const CriticalRuntime = preload("res://scripts/combat/critical_strike_runtime.gd")
const Data = preload("res://scripts/game_data.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Trade = preload("res://scripts/items/gem_trade_rules.gd")
const Town = preload("res://scripts/town/town_catalog.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const POLICY: Dictionary = {"duration": 2.0, "hit_damage_taken_increased": 0.15, "hit_multiplier": 0.80, "mana_multiplier": 1.20}
var checks: int = 0
var failures: int = 0
var pairs: int = 0


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-v052-") or not OS.get_user_data_dir().begins_with(xdg + "/"):
		quit(78)
		return
	_test_admission()
	_test_composition()
	_test_detachment_and_injection()
	_test_catalog_and_model()
	print("Shock support/compiler/catalog: %d checks, %d failures; %d compatible existing pairs" % [checks, failures, pairs])
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


func _test_admission() -> void:
	check(Shock.PLAYER_POLICY == POLICY, "Exact four-value player policy")
	var definition: Dictionary = Supports.get_definition("shock")
	check(definition.get("name") == "感电辅助" and definition.get("skills") == ["bolt", "nova", "chain"], "Authored identity, name and native-lightning skills")
	check(Supports.definition_error(definition).is_empty() and Provider.definition_error(definition).is_empty(), "Real registry validates provider metadata")
	definition.operations[0].value = 0.0
	check(not Supports.definition_error(definition).is_empty(), "Forged Shock definition rejected")
	check(Supports.get_definition("shock").operations[0].value == -0.20, "Definition is detached")
	var enriched: Dictionary = _snapshot(true)
	enriched.added_damage.attack.merge({"lightning": 999.0}, true)
	enriched.added_damage.spell.merge({"lightning": 999.0}, true)
	for skill: String in Data.SKILLS:
		var allowed: bool = skill in ["bolt", "nova", "chain"]
		var base: Dictionary = Compiler.compile_group(skill, enriched, [])
		check(base.ok, "Added-lightning and guaranteed-critical fixture valid: %s (%s)" % [skill, base.error])
		check(base.ok and not base.has("shock_profile") and not base.snapshot.has("shock_policy"), "Lightning and critical never add automatic Shock: " + skill)
		check(Supports.compatibility_reason(skill, ["shock"]).is_empty() == allowed, "Registry native admission: " + skill)
		check(Compiler.compile_group(skill, enriched, ["shock"]).ok == allowed, "Equipment-added lightning cannot expand admission: " + skill)
		check(Supports.supports_for_skill(skill).has("shock") == allowed, "Support selector follows exact admission: " + skill)
	for skill: String in ["bolt", "nova", "chain"]:
		check(not Supports.saved_links_reason(skill, ["shock"], 30).is_empty(), "Old30 cannot admit Shock links")
		check(Supports.saved_links_reason(skill, ["shock"], 31).is_empty(), "Current31 admits Shock links")
	for links: Variant in [null, "shock", ["shock", "shock"], ["shock", 1], ["shock", "unknown"]]:
		check(not Supports.compatibility_reason("bolt", links).is_empty(), "Malformed registry selection rejected")
		check(not Provider.compile_program("bolt", links).error.is_empty(), "Malformed provider selection rejected")
	check(not Compiler.compile_group("basic", enriched, ["shock"]).ok, "Basic attack is not a supported active")
	check(not Compiler.compile_group("bolt", enriched, ["shock", "focus", "volley", "lightning_focus", "efficiency", "quickcast"]).ok, "Sixth group support rejected")
	check(not Compiler.compile_skill("bolt", enriched, ["shock", "focus", "volley"]).ok, "Legacy two-slot boundary retained")
	check(not Supports.compatibility_reason("bolt", ["shock"], 3).is_empty(), "Unknown capacity rejected")
	var empty := Provider.compile_program("bolt", [])
	check(empty.error.is_empty() and empty.modifiers.is_empty() and empty.mana_multiplier == 1.0, "Unselected provider has no effect")


func _primary_packets(cast: Dictionary) -> Array:
	return cast.packets.bounces if cast.skill_id == "chain" else [cast.packets.projectile if cast.skill_id == "bolt" else cast.packets.direct]


func _check_composition(skill: String, links: Array) -> void:
	var raw := _snapshot()
	var before := var_to_bytes(raw)
	var links_before := links.duplicate()
	var cast := Compiler.compile_group(skill, raw, links)
	check(cast.ok, "Compatible support set compiles: %s/%s" % [skill, str(links)])
	if not cast.ok: return
	var reverse := links.duplicate()
	reverse.reverse()
	check(var_to_bytes(cast) == var_to_bytes(Compiler.compile_group(skill, raw, reverse)), "Canonical output independent of support order")
	check(var_to_bytes(raw) == before and links == links_before, "Compilation leaves raw snapshot and links intact")
	var others := links.duplicate()
	others.erase("shock")
	var base := Compiler.compile_group(skill, raw, others)
	check(base.ok and cast.packets == base.packets and cast.recipe == base.recipe and cast.initial_count == base.initial_count, "Existing assembled packets and delivery recipes retained")
	near(cast.mana, base.mana * 1.20, "Final mana includes Shock once with source cost authority")
	near(cast.cooldown, base.cooldown, "Existing cooldown factors retained")
	near(cast.cost_factors.final_mana, cast.mana, "Existing final mana receipt remains authoritative")
	check(cast.snapshot.shock_policy == POLICY and cast.snapshot.shock_policy.size() == 4, "Exact immutable execution policy")
	var profile: Dictionary = POLICY.duplicate(true)
	profile.merge({"enabled": true, "trigger": "positive_lightning_hit_after_settlement", "affects_hits_only": true,
		"affects_dot": false, "applies_after_current_hit": true, "stacking": "refresh_equal",
		"roles": ["projectile"] if skill == "bolt" else ["bounce"] if skill == "chain" else ["direct"]})
	check(cast.shock_profile == profile, "Exact preview policy and primary roles")
	var modifier_count := 0
	for modifier: Dictionary in cast.snapshot.modifiers:
		if modifier.get("id") == "support:shock": modifier_count += 1
	check(modifier_count == 1, "One Shock primary modifier only")
	var packets := _primary_packets(cast)
	var original := _primary_packets(base)
	for index: int in packets.size():
		check(cast.shock_profile.roles.has(packets[index].role), "Status role matches actual primary packet role")
		var actual: Dictionary = Damage.resolve(packets[index], cast.snapshot.modifiers)
		var expected: Dictionary = Damage.resolve(original[index], base.snapshot.modifiers)
		for type: String in expected.components:
			near(actual.components[type], expected.components[type] * 0.80, "Primary component penalized once: %s/%d/%s" % [skill, index, type])
	if skill == "bolt":
		check(Damage.resolve(cast.packets.secondary, cast.snapshot.modifiers) == Damage.resolve(base.packets.secondary, base.snapshot.modifiers), "Independent secondary explosion damage has no Shock penalty")
		check(not cast.shock_profile.roles.has("secondary"), "Secondary explosion has no status role")


func _test_composition() -> void:
	for skill: String in ["bolt", "nova", "chain"]:
		_check_composition(skill, ["shock"])
		for support: String in Supports.supports_for_skill(skill):
			if support == "shock": continue
			pairs += 1
			_check_composition(skill, [support, "shock"])
		_check_composition(skill, ["shock", "lightning_focus", "efficiency", "quickcast", "focus"] if skill == "bolt" else ["shock", "lightning_focus", "efficiency", "quickcast", "concentrate"] if skill == "nova" else ["shock", "lightning_focus", "efficiency", "quickcast", "chain_extension"])
		var critical := Compiler.compile_group(skill, _snapshot(true), ["shock"])
		var normal := Compiler.compile_group(skill, _snapshot(), ["shock"])
		check(critical.shock_profile == normal.shock_profile, "Critical does not alter Shock policy")
		var critical_runtime = CriticalRuntime.new()
		critical_runtime.reset(52)
		var frozen: Dictionary = critical_runtime.freeze(critical.snapshot).snapshot
		check(frozen.shock_policy == POLICY and critical_runtime.events == 1, "Existing critical freeze carries support policy unchanged")
		var zero := Compiler.compile_group(skill, Combat.snapshot({"damage": 0.0}, []), ["shock"])
		check(zero.ok and zero.shock_profile == normal.shock_profile, "Zero hit compiles without inventing status damage")
		check(not zero.snapshot.has("resource_modifiers") and not zero.has("cost_factors"), "Zero source path gains no resource fields")
	var lightning := Compiler.compile_basic(_snapshot(true))
	check(lightning.ok and not lightning.has("shock_profile") and not lightning.snapshot.has("shock_policy"), "Added-lightning critical basic remains unshocking")


func _test_detachment_and_injection() -> void:
	var raw := _snapshot()
	var before := var_to_bytes(raw)
	var cast := Compiler.compile_group("bolt", raw, ["shock"])
	var other := Compiler.compile_group("bolt", raw, ["shock"])
	check(not Compiler.compile_group("bolt", cast.snapshot, ["shock"]).ok, "Compiled snapshot cannot double-apply Shock")
	for value: Variant in [POLICY, {}, {"duration": true}, {"duration": NAN}, "bad", null]:
		var injected := raw.duplicate(true)
		injected.shock_policy = value
		check(not Compiler.compile_group("bolt", injected, []).ok and not Compiler.compile_group("bolt", injected, ["shock"]).ok, "Any raw Shock policy injection rejected")
		check(not Compiler.compile_basic(injected).ok, "Basic compiler rejects forged policy")
	cast.snapshot.shock_policy.duration = 10.0
	cast.shock_profile.hit_damage_taken_increased = 9.0
	cast.shock_profile.roles.append("secondary")
	check(cast.shock_profile.duration == 2.0 and cast.snapshot.shock_policy.hit_damage_taken_increased == 0.15, "Profile and snapshot detached from each other")
	check(other == Compiler.compile_group("bolt", raw, ["shock"]) and Shock.PLAYER_POLICY == POLICY and var_to_bytes(raw) == before, "Mutation cannot alter input, static policy or independent casts")


func _test_catalog_and_model() -> void:
	var definition := Gems.definition("support:shock")
	check(not definition.is_empty(), "Real catalog resolves Shock")
	if definition.is_empty(): return
	check(definition.name == "感电辅助" and definition.kind == "support_gem" and definition.skills == ["bolt", "nova", "chain"], "Real catalog metadata is exact")
	check(definition.icon == "res://assets/ui/grimoire/shock.png" and definition.icon_texture is Texture2D, "Actual imported Shock texture resolves")
	check(Gems.minimum_save_version("support:shock") == 31, "New gem has closed schema31 vocabulary")
	var instance := Gems.create_instance("item_999999", "support:shock")
	check(Gems.validate_instance(instance) and instance.payload == {"level": 1, "quality": 0}, "Instance remains fixed level1 quality0")
	check(Trade.quote("buy", "support:shock").cost == {"calibration_shard": 4}, "Formal price is exactly four shards")
	var rows := Trade.offers().filter(func(row: Dictionary): return row.definition_id == "support:shock")
	check(rows.size() == 1 and rows[0].cost == 4, "Dynamic formal catalog includes one Shock offer")
	var supplies := Town.offers("skill_merchant").filter(func(row: Dictionary): return row.definition_id == "support:shock")
	check(supplies.size() == 1 and supplies[0].available and supplies[0].price_label == "测试免费", "Existing test supply automatically includes Shock")
	var model := Model.new()
	check(model.snapshot().version == 31 and model.snapshot().items.values().filter(func(item: Dictionary): return item.definition_id == "support:shock").is_empty(), "Default full migration chain opens31 with no Shock grant")
	const PATH := "user://build_save.json"
	check(model.save_build(PATH) == OK, "Model saves current schema31")
	var offer := model.normal_gem_offers(PATH).filter(func(row: Dictionary): return row.definition_id == "support:shock")
	check(offer.size() == 1 and offer[0].cost == 4 and not offer[0].available, "Real formal offer enforces funds")
	var candidate := model.snapshot()
	check(model._set_bag_currency_balance(candidate, 4).ok, "Physical shard budget fixture admitted")
	candidate.revision += 1
	check(model._commit(candidate, PATH).ok, "Budget is an actual valid persisted model")
	var quote := model.gem_trade_quote("buy", "support:shock", model.revision(), PATH)
	check(quote.ok and quote.cost == {"calibration_shard": 4}, "Authoritative model issues four-shard quote")
	if not quote.ok: return
	var bought := model.execute_gem_trade(quote.handle, "support:shock")
	check(bought.ok and model.crafting_balance() == 0 and model.item(bought.get("uid", "")).definition_id == "support:shock", "Purchase deducts shards and creates one real UID")
	if not bought.ok: return
	var groups := {}
	for group: Dictionary in model.snapshot().skill_groups:
		groups[model.skill_group(group.id).skill_id] = group.id
	var initial := model.snapshot()
	var disk := FileAccess.get_file_as_bytes(PATH)
	check(not model.move_item(bought.uid, {"kind": "skill_support", "group_id": groups.meteor, "index": 0}, model.revision(), PATH).ok and model.snapshot() == initial and FileAccess.get_file_as_bytes(PATH) == disk, "Unsupported native-fire group rejects same purchased UID atomically")
	for skill: String in ["bolt", "nova", "chain"]:
		check(model.move_item(bought.uid, {"kind": "skill_support", "group_id": groups[skill], "index": 0}, model.revision(), PATH).ok, "Purchased UID equips in exact supported group: " + skill)
		var cast := model.get_group_cast(groups[skill])
		check(cast.ok and cast.snapshot.shock_policy == POLICY and cast.support_ids.has("shock"), "Model cast reaches support compiler: " + skill)
	var reopened := Model.new()
	check(reopened.load_build(PATH) and reopened.snapshot() == model.snapshot() and reopened.get_group_cast(groups.chain) == model.get_group_cast(groups.chain), "Purchased equipped UID and cast survive strict31 reopen")
	check(not FileAccess.get_file_as_string(PATH).contains('"shock_policy"'), "Transient compiled policy is not serialized")
