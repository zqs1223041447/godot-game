class_name SourceTreeLocalization
extends RefCounted
## Display-only Chinese mapping for the pinned English passive-tree source.
## Source strings and IDs remain authoritative and are never rewritten.
const Data = preload("res://scripts/passives/source_tree_data.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const PATH := "res://data/passive_source/localization_zh_CN.json"
const SOURCE_SHA256 := "7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122"
const NOT_IMPLEMENTED := "（暂未实装）"
const TERM_NOTE := "词缀说明：提高/降低为同类加算；额外提高/额外降低为独立乘算；倍率词缀上的加号数值表示倍率百分点加算。持续时间降低表示持续时间缩短。"

# A parser match is not sufficient by itself. These closed-world groups name
# the actual runtime paths that consume each parsed stat after SourceTree.apply_stats.
const STAT_CONSUMER_GROUPS := {
	"physical_fire_conversion": {
		"evidence": "source_tree_runtime.gd::apply_stats -> combat_data.gd::snapshot/event_packet -> physical_fire_conversion_rules.gd::from_stats/apply -> damage_resolver.gd conversion provenance",
		"code_checks": [
			{"path": "scripts/passives/source_tree_runtime.gd", "contains": "result.physical_to_fire_conversion"},
			{"path": "scripts/combat/combat_data.gd", "contains": "Conversion.from_stats(stats)"},
			{"path": "scripts/combat/combat_data.gd", "contains": "Conversion.apply"},
			{"path": "scripts/combat/physical_fire_conversion_rules.gd", "contains": "static func apply"},
		],
		"stats": ["physical_to_fire_conversion"]
	},
	"attributes_and_capacity": {
		"evidence": "source_tree_runtime.gd::apply_stats; canonical_game_state.gd::_stats_for; main.gd resource and hit paths",
		"code_checks": [
			{"path": "scripts/canonical_game_state.gd", "contains": "SourceTree.apply_stats(stats,candidate)"},
			{"path": "scripts/canonical_game_state.gd", "contains": "_stats_for(candidate)"},
			{"path": "scripts/main.gd", "contains": "Defense.incoming_source_hit(components,_stats"},
		],
		"stats": ["strength", "dexterity", "intelligence", "max_health", "max_mana", "max_shield", "life_regen", "life_regen_percent", "accuracy", "accuracy_increased", "evasion", "evasion_increased", "armour", "armour_increased", "fire_resistance", "cold_resistance", "lightning_resistance"]
	},
	"zealots_oath": {
		"evidence": "source_tree_runtime.gd::apply_stats -> zealots_oath_rules.gd::profile -> canonical_game_state.gd::get_stats -> main.gd continuous resource regeneration",
		"code_checks": [
			{"path": "scripts/passives/source_tree_runtime.gd", "contains": "ZealotsOath.profile"},
			{"path": "scripts/mechanics/zealots_oath_rules.gd", "contains": "static func profile"},
			{"path": "scripts/canonical_game_state.gd", "contains": "get_regeneration_profile"},
			{"path": "scripts/main.gd", "contains": "float(_stats.shield_regeneration_rate) * delta"},
		],
		"stats": ["zealots_oath"]
	},
	"iron_reflexes": {
		"evidence": "source_tree_runtime.gd::apply_stats -> iron_reflexes_rules.gd::profile -> canonical_game_state.gd::get_stats -> existing attack admission and physical hit mitigation",
		"code_checks": [
			{"path": "scripts/passives/source_tree_runtime.gd", "contains": "IronReflexes.profile"},
			{"path": "scripts/mechanics/iron_reflexes_rules.gd", "contains": "static func profile"},
			{"path": "scripts/canonical_game_state.gd", "contains": "get_defense_conversion_profile"},
		],
		"stats": ["iron_reflexes"]
	},
	"elemental_resistance_caps": {
		"evidence": "source_tree_runtime.gd::apply_stats -> canonical_game_state.gd::_stats_for -> defense_rules.gd::resistance_profile/source_profile/incoming_burn -> main.gd incoming hit and burn settlement",
		"code_checks": [
			{"path": "scripts/canonical_game_state.gd", "contains": "maximum_fire_resistance_add"},
			{"path": "scripts/mechanics/defense_rules.gd", "contains": "static func resistance_profile"},
			{"path": "scripts/mechanics/defense_rules.gd", "contains": "static func source_profile"},
			{"path": "scripts/mechanics/defense_rules.gd", "contains": "static func incoming_burn"},
			{"path": "scripts/main.gd", "contains": "Defense.incoming_source_hit(components,_stats"},
			{"path": "scripts/main.gd", "contains": "Defense.incoming_burn("},
		],
		"stats": ["maximum_fire_resistance_add", "maximum_cold_resistance_add", "maximum_lightning_resistance_add"]
	},
	"damage_and_rates": {
		"evidence": "combat_data.gd::modifiers -> damage_resolver.gd; canonical_game_state.gd::_stats_for -> main.gd combat/movement/resource tick",
		"code_checks": [
			{"path": "scripts/combat/combat_data.gd", "contains": "static func modifiers(stats: Dictionary)"},
			{"path": "scripts/canonical_game_state.gd", "contains": "physical_increased"},
		],
		"stats": ["physical_increased", "chaos_increased", "melee_physical_increased", "attack_physical_increased", "global_increased", "projectile_increased", "spell_increased", "fire_increased", "cold_increased", "lightning_increased", "elemental_increased", "area_increased", "attack_speed_increased", "move_speed_increased", "mana_regen_increased"]
	},
	"spatial": {
		"evidence": "source_spatial_rules.gd -> skill_compiler.gd and combat delivery/area resolution",
		"code_checks": [
			{"path": "scripts/combat/source_spatial_rules.gd", "contains": "static func from_stats(stats:Dictionary)"},
			{"path": "scripts/combat/source_spatial_rules.gd", "contains": "projectile_speed_increased"},
			{"path": "scripts/combat/skill_compiler.gd", "contains": "const Spatial = preload"},
		],
		"stats": ["area_size_increased", "spell_area_size_increased", "melee_area_size_increased", "projectile_speed_increased"]
	},
	"shield_recharge": {
		"evidence": "defense_rules.gd::recharge_profile -> canonical_game_state.gd and main.gd shield recovery",
		"code_checks": [
			{"path": "scripts/mechanics/defense_rules.gd", "contains": "static func recharge_profile"},
			{"path": "scripts/mechanics/defense_rules.gd", "contains": "shield_recharge_start_faster"},
		],
		"stats": ["shield_recharge_rate_increased", "shield_recharge_start_faster"]
	},
	"resource_cost": {
		"evidence": "source_resource_rules.gd -> skill_compiler.gd and main.gd skill-cost admission",
		"code_checks": [
			{"path": "scripts/combat/source_resource_rules.gd", "contains": "static func from_stats(stats:Dictionary)"},
			{"path": "scripts/combat/source_resource_rules.gd", "contains": "mana_cost_efficiency_increased"},
			{"path": "scripts/combat/skill_compiler.gd", "contains": "ResourceCost"},
		],
		"stats": ["mana_cost_efficiency_increased", "mana_cost_increased"]
	},
	"flasks": {
		"evidence": "flask_modifier_rules.gd -> flask runtime use/charge settlement",
		"code_checks": [
			{"path": "scripts/combat/flask_modifier_rules.gd", "contains": "flask_charges_gained_increased"},
			{"path": "scripts/combat/flask_modifier_rules.gd", "contains": "static func charge_gain"},
		],
		"stats": ["flask_life_recovery_increased", "flask_mana_recovery_increased", "flask_charges_gained_increased"]
	},
	"resolute_technique": {
		"evidence": "source_tree_runtime.gd::apply_stats -> canonical_game_state.gd::_stats_for -> resolute_technique_rules.gd -> combat_data.gd snapshot -> skill_compiler.gd/attack_hit_rules.gd/critical_strike_rules.gd -> main.gd hit settlement",
		"code_checks": [
			{"path": "scripts/canonical_game_state.gd", "contains": "resolute_technique"},
			{"path": "scripts/combat/resolute_technique_rules.gd", "contains": "static func active"},
			{"path": "scripts/combat/resolute_technique_rules.gd", "contains": "cannot_deal_critical_strikes"},
			{"path": "scripts/combat/combat_data.gd", "contains": "resolute_technique"},
			{"path": "scripts/combat/skill_compiler.gd", "contains": "hit_policy"},
			{"path": "scripts/combat/attack_hit_rules.gd", "contains": "if hits_cannot_be_evaded:"},
			{"path": "scripts/combat/critical_strike_rules.gd", "contains": "Resolute.active"},
		],
		"stats": ["resolute_technique"]
	},
	"critical": {
		"evidence": "critical_strike_rules.gd -> combat compilation and hit resolution",
		"code_checks": [
			{"path": "scripts/combat/critical_strike_rules.gd", "contains": "static func from_stats"},
			{"path": "scripts/combat/critical_strike_rules.gd", "contains": "crit_multiplier_add"},
		],
		"stats": ["crit_chance_increased", "attack_crit_chance_increased", "spell_crit_chance_increased", "melee_crit_chance_increased", "projectile_attack_crit_chance_increased", "crit_multiplier_add", "spell_crit_multiplier_add", "melee_crit_multiplier_add", "projectile_attack_crit_multiplier_add"]
	},
	"leech": {
		"evidence": "leech_rules.gd -> main.gd attack-hit recovery runtime",
		"code_checks": [
			{"path": "scripts/combat/leech_rules.gd", "contains": "static func from_stats"},
			{"path": "scripts/combat/leech_rules.gd", "contains": "life_leech_max_rate_increased"},
		],
		"stats": ["attack_life_leech", "attack_mana_leech", "physical_attack_life_leech", "physical_attack_mana_leech", "life_leech_rate_increased", "mana_leech_rate_increased", "life_leech_max_rate_increased", "mana_leech_max_rate_increased"]
	},
	"fire_dot": {
		"evidence": "burn_rules.gd::multiplier_from_stats/raw_fire_dps -> burn compiler and runtime",
		"code_checks": [
			{"path": "scripts/combat/burn_rules.gd", "contains": "fire_dot_multiplier_add"},
			{"path": "scripts/combat/burn_rules.gd", "contains": "static func raw_fire_dps"},
		],
		"stats": ["fire_dot_multiplier_add"]
	},
	"mana_before_life": {
		"evidence": "source_tree_runtime.gd::apply_stats -> canonical_game_state.gd::_stats_for -> defense_rules.gd::mana_guard_profile/settle_with_mana -> main.gd incoming settlement",
		"code_checks": [
			{"path": "scripts/canonical_game_state.gd", "contains": "damage_taken_from_mana_before_life"},
			{"path": "scripts/mechanics/defense_rules.gd", "contains": "static func mana_guard_profile"},
			{"path": "scripts/mechanics/defense_rules.gd", "contains": "static func settle_with_mana"},
			{"path": "scripts/main.gd", "contains": "incoming_source_hit(components,_stats"},
			{"path": "scripts/main.gd", "contains": "shield,health,\"player\",mana,mana_ratio"},
			{"path": "scripts/main.gd", "contains": "settlement.remaining_mana"},
		],
		"stats": ["damage_taken_from_mana_before_life"]
	},
	"damaging_ailment_timing": {
		"evidence": "source_stat_patterns.gd::FASTER_BURN_PATTERNS -> source_tree_runtime.gd schema33 -> burn_rules.gd::raw_fire_dps/burn_duration",
		"code_checks": [
			{"path": "scripts/passives/source_stat_patterns.gd", "contains": "FASTER_BURN_PATTERNS"},
			{"path": "scripts/passives/source_tree_runtime.gd", "contains": "FASTER_BURN_SAVE_VERSION"},
			{"path": "scripts/combat/burn_rules.gd", "contains": "damaging_ailments_faster"},
			{"path": "scripts/combat/burn_rules.gd", "contains": "burn_duration("},
		],
		"stats": ["damaging_ailments_faster"]
	}
}

static var _document: Dictionary = {}
static var _node_names: Dictionary = {}
static var _lines: Dictionary = {}
static var _classes: Dictionary = {}
static var _partitions: Dictionary = {}
static var _status_cache: Dictionary = {}


static func ready() -> bool:
	if not _document.is_empty():
		return true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary or parsed.get("schema_version") != 1:
		return false
	if not parsed.get("source") is Dictionary or parsed.source.get("sha256") != SOURCE_SHA256:
		return false
	if not Data.ready() or Data.SOURCE_SHA256 != SOURCE_SHA256:
		return false
	if not parsed.get("nodes") is Dictionary or not parsed.get("lines") is Dictionary \
			or not parsed.get("classes") is Dictionary or not parsed.get("partitions") is Dictionary:
		return false
	_document = parsed
	_node_names = parsed.nodes
	_lines = parsed.lines
	_classes = parsed.classes
	_partitions = parsed.partitions
	return true


static func node_name(node_id: String) -> String:
	if not ready():
		return "节点名称缺失"
	var row: Variant = _node_names.get(node_id)
	if not row is Dictionary or not row.get("zh_CN") is String or str(row.get("zh_CN", "")).is_empty():
		return "节点名称缺失"
	return str(row.zh_CN)


static func class_label(source_name: String) -> String:
	if not ready():
		return "职业名称缺失"
	return str(_classes.get(source_name, "职业名称缺失"))


static func partition_label(source_key: String) -> String:
	if not ready():
		return "子树名称缺失"
	var row: Variant = _partitions.get(source_key)
	if not row is Dictionary or not row.get("zh_CN") is String:
		return "子树名称缺失"
	return str(row.zh_CN)


static func source_effect_line(raw_line: String) -> String:
	if not ready():
		return "词缀翻译缺失"
	var value: Variant = _lines.get(raw_line)
	if not value is String or str(value).is_empty():
		return "词缀翻译缺失"
	return str(value)


static func line_status(raw_line: String) -> Dictionary:
	if _status_cache.has(raw_line):
		return _status_cache[raw_line].duplicate(true)
	var result := {"implemented": false, "parser_supported": false, "missing_consumers": [], "grants": []}
	if not ready() or not _lines.has(raw_line):
		_status_cache[raw_line] = result
		return result.duplicate(true)
	var parsed := Runtime.line_effect(raw_line, Runtime.CURRENT_SAVE_VERSION)
	result.parser_supported = bool(parsed.get("supported", false))
	result.grants = parsed.get("grants", []).duplicate(true)
	if not result.parser_supported or result.grants.is_empty():
		_status_cache[raw_line] = result
		return result.duplicate(true)
	var missing: Array[String] = []
	for grant: Dictionary in result.grants:
		var found := false
		for group: String in STAT_CONSUMER_GROUPS:
			if STAT_CONSUMER_GROUPS[group].stats.has(str(grant.get("stat", ""))):
				found = not str(STAT_CONSUMER_GROUPS[group].evidence).is_empty()
				break
		if not found:
			missing.append(str(grant.get("stat", "未知统计项")))
	result.missing_consumers = missing
	result.implemented = missing.is_empty()
	_status_cache[raw_line] = result.duplicate(true)
	return result


static func display_line(raw_line: String) -> String:
	var rendered := source_effect_line(raw_line)
	if rendered == "词缀翻译缺失":
		return rendered + NOT_IMPLEMENTED
	return rendered if bool(line_status(raw_line).implemented) else rendered + NOT_IMPLEMENTED


static func display_lines(raw_lines: Array, separator: String = "\n") -> String:
	var rendered: Array[String] = []
	for raw_line: String in raw_lines:
		rendered.append(display_line(raw_line))
	return separator.join(rendered)
