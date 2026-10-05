extends SceneTree
## Exhaustive audit of the display-only Chinese map and canonical tree UI.
const Data = preload("res://scripts/passives/source_tree_data.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const PassivePanel = preload("res://scripts/ui/canonical_passive_panel.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const SOURCE_SHA256 := "7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122"
const EXPECTED_FIRE_DOT_NODES := ["4713", "5916", "13559", "31462", "54396", "2550", "11924", "29049"]
const FIRE_DOT_AMOUNTS := {"4713":"4", "5916":"6", "13559":"5", "31462":"5", "54396":"4", "2550":"10", "11924":"10", "29049":"12"}
const FIRE_MASTERY_NODES := ["11505", "19749", "34927", "37911", "38320", "40271", "48267", "63268"]
var checks := 0
var failures := 0
var number_re := RegEx.new()
var ascii_re := RegEx.new()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	number_re.compile("[+-]?\\d+(?:\\.\\d+)?")
	ascii_re.compile("[A-Za-z]")
	check(Data.ready() and Localization.ready(), "Pinned source data and localized mapping load")
	if not Data.ready() or not Localization.ready():
		finish()
		return
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Data.PATH))
	var localized: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Localization.PATH))
	check(raw.source.version == "3.29.1" and raw.source.data_sha256 == SOURCE_SHA256, "Source revision and pinned identity remain unchanged")
	check(Data.SOURCE_SHA256 == SOURCE_SHA256 and localized.source.sha256 == SOURCE_SHA256, "Display map is pinned to the same original source hash")
	check(raw.nodes.size() == 3390 and localized.nodes.size() == raw.nodes.size(), "All source node IDs have a translation record")
	check(localized.coverage.source_nodes == 3390 and localized.coverage.source_node_names == 3389, "Reported node-name coverage agrees with raw tree")
	check(localized.coverage.unique_source_node_names == 1910 and localized.coverage.unique_effect_lines == 2974, "All unique names and complete effect strings are covered")
	check(localized.coverage.effect_occurrences == 6981 and localized.coverage.mastery_options == 1837, "All node and mastery effect occurrences are counted")
	check(localized.coverage.multiline_effect_lines == 95 and localized.coverage.multiline_unreviewed == 0, "All multiline source entries have reviewed Chinese display text")
	check(localized.coverage.reviewed_long_single_line_effects == 134 and localized.coverage.long_single_line_unreviewed == 0, "All complex long single-line effects have reviewed Chinese display text")
	check(localized.coverage.standard_nodes == 2387 and localized.coverage.jewel_sockets == 60 and localized.coverage.expansion_jewel_nodes == 42, "Tree, socket, and expansion coverage counts agree")
	check(localized.coverage.classes == 7 and localized.coverage.ascendancy_partitions == 37, "All class and ascendancy picker labels are covered")
	check(localized.coverage.reminder_text_records_not_displayed_by_canonical_panel == 802 and localized.coverage.reminder_text_entries_not_displayed_by_canonical_panel == 1015, "Hidden source reminder text is counted separately from displayed labels")
	check(localized.coverage.untranslated_names == 0 and localized.coverage.untranslated_effect_lines == 0, "Builder reports no untranslated names or effects")
	audit_consumer_manifest()

	var all_raw_lines: Dictionary = {}
	var source_occurrences := 0
	var supported_occurrences := 0
	var unsupported_occurrences := 0
	var unsupported_unknown_consumer := 0
	for node_id: String in raw.nodes:
		var source_node: Dictionary = raw.nodes[node_id]
		var mapped: Dictionary = localized.nodes.get(node_id, {})
		var runtime_node := Data.node(node_id)
		check(not mapped.is_empty() and str(mapped.get("source", "")) == str(source_node.get("name", "")), "Node name mapping retains exact source identity: " + node_id)
		check(str(runtime_node.get("name", "")) == str(source_node.get("name", "")), "Runtime exposes unchanged English source node name: " + node_id)
		check(runtime_node.get("stats", []) == source_node.get("stats", []) and runtime_node.get("mastery_effects", []) == source_node.get("masteryEffects", []), "Raw stat strings and mastery IDs remain unchanged: " + node_id)
		check(not has_ascii(str(mapped.get("zh_CN", ""))), "Localized node name has no English residue: " + node_id)
		for raw_line: String in source_node.get("stats", []):
			source_occurrences += 1
			all_raw_lines[raw_line] = true
			audit_line(raw_line)
			var status := Localization.line_status(raw_line)
			if status.parser_supported:
				supported_occurrences += 1
				if not status.implemented: unsupported_unknown_consumer += 1
			else:
				unsupported_occurrences += 1
		for option: Dictionary in source_node.get("masteryEffects", []):
			for raw_line: String in option.get("stats", []):
				source_occurrences += 1
				all_raw_lines[raw_line] = true
				audit_line(raw_line)
				var status := Localization.line_status(raw_line)
				if status.parser_supported:
					supported_occurrences += 1
					if not status.implemented: unsupported_unknown_consumer += 1
				else:
					unsupported_occurrences += 1
	check(source_occurrences == 6981, "Every occurrence including mastery lines was audited")
	check(all_raw_lines.size() == 2974 and localized.lines.size() == all_raw_lines.size(), "Exact source-line dictionary has no missing or extra keys")
	check(supported_occurrences + unsupported_occurrences == source_occurrences, "Every complete raw effect was classified independently")
	check(unsupported_unknown_consumer == 0, "No parser-supported stat lacks a documented runtime consumer")
	print("Passive tree localization audit: %d nodes, %d line occurrences, %d unique lines; %d supported occurrences, %d marked occurrences, %d failures from parser support without consumers" % [raw.nodes.size(), source_occurrences, all_raw_lines.size(), supported_occurrences, unsupported_occurrences, unsupported_unknown_consumer])

	for class_row: Dictionary in raw.classes:
		var source_name := str(class_row.name)
		check(localized.classes.has(source_name) and not has_ascii(str(localized.classes.get(source_name, ""))), "Class label covered without changing its source key: " + source_name)
	for partition_key: String in raw.special_subtrees.ascendancies:
		var branch: Dictionary = raw.special_subtrees.ascendancies[partition_key]
		var row: Dictionary = localized.partitions.get(partition_key, {})
		check(not row.is_empty() and row.get("source") == branch.get("name", partition_key), "Ascendancy partition label preserves source key: " + partition_key)
		check(not has_ascii(str(row.get("zh_CN", ""))), "Ascendancy partition label is Chinese: " + partition_key)

	var operator_samples := {
		"1% increased Area of Effect per 50 Unreserved Maximum Mana, up to 100%": "提高",
		"10% reduced Attack Speed": "降低",
		"10% less Damage Taken from Damage over Time": "额外降低",
		"10% more Damage if you've Killed Recently": "额外提高",
		"+12% to Fire Damage over Time Multiplier": "+12%"
	}
	for source_line: String in operator_samples:
		var translated := Localization.source_effect_line(source_line)
		check(translated.contains(operator_samples[source_line]), "Distinct term contract is visible in translation: " + source_line)
	if localized.lines.has("+12% to Fire Damage over Time Multiplier"):
		var multiplier_zh: String = Localization.source_effect_line("+12% to Fire Damage over Time Multiplier")
		check(multiplier_zh.contains("倍率") and multiplier_zh.contains("+12%") and not multiplier_zh.contains("提高"), "Multiplier plus remains additive percentage points, not MORE")
	var faster_ailment := Localization.source_effect_line("Damaging Ailments deal damage 5% faster")
	check(faster_ailment == "伤害型异常状态的伤害结算加快5%", "Faster damaging ailments stay general, not narrowed to fire")
	var faster_status := Localization.line_status("Damaging Ailments deal damage 5% faster")
	if Runtime.CURRENT_SAVE_VERSION >= 33:
		check(faster_status.parser_supported and faster_status.implemented, "Schema 33 recognizes faster damaging-ailment stats and has a code-path consumer")
		check(not Localization.display_line("Damaging Ailments deal damage 5% faster").ends_with(Localization.NOT_IMPLEMENTED), "Implemented faster-ailment row has no false unsupported label")
	else:
		check(not faster_status.parser_supported and not faster_status.implemented, "Schema 32 does not claim the future faster-ailment consumer is implemented")
		check(Localization.display_line("Damaging Ailments deal damage 5% faster").ends_with(Localization.NOT_IMPLEMENTED), "Unrecognized faster-ailment row carries its unsupported label")
	var comparator_line := "Tinctures deactivate when you have 12 or more Mana Burn"
	check(Localization.source_effect_line(comparator_line) == "当你身上有12层或以上魔力燃烧时，灵药会停用", "‘or more’ stays a threshold comparison, not a MORE modifier")
	check(Localization.source_effect_line("10% more Damage if you've Killed Recently") == "伤害额外提高10%（若你近期击杀过敌人）", "Numeric MORE remains an independent multiplicative modifier")
	var ward_comparator := "Damage taken bypasses Unbroken Ward if the Hit deals less Damage than 15% of Ward"
	check(Localization.source_effect_line(ward_comparator) == "若该次击中造成的伤害低于灵护值的15%，所受伤害会绕过未破损灵护", "‘less than’ stays a comparison and Ward uses the localized game term")
	check(Localization.source_effect_line("1% increased Flask Charges gained per Mana Burn on you") == "你身上每层魔力燃烧，获得的药剂充能提高1%", "Flask charges use ‘充能’, with the per-stack scope intact")
	check(Localization.source_effect_line("Skills fire an additional Projectile") == "技能额外发射一个投射物", "‘fire’ in projectile effects is translated as ‘发射’")
	check(Localization.source_effect_line("Bow Attacks fire an additional Arrow") == "弓类攻击额外发射一支箭矢", "Bow projectiles keep the firing verb and arrow type")
	check(Localization.source_effect_line("Projectiles are fired in random directions") == "投射物会向随机方向发射", "Passive voice for projectile firing keeps the firing meaning")
	check(Localization.source_effect_line("Flasks gain 3 Charges every 3 seconds") == "每3秒，药剂获得3点药剂充能", "Periodic flask charge gains keep amount, interval, and charge wording")
	check(Localization.source_effect_line("50% chance for Flasks you use to not consume Charges") == "你使用药剂时，有50%几率不消耗药剂充能", "Flask charges used retain the flask-charge term")
	check(Localization.source_effect_line("1% of Damage Dealt by your Minions is Leeched to you as Life") == "召唤物造成的伤害中，有1%作为生命偷取转移给你", "Minion damage leeched to the player names the correct beneficiary")
	check(Localization.source_effect_line("Gain 25% increased Armour per 5 Power for 8 seconds when you Warcry, up to a maximum of 100%") == "使用战吼时，每5点战吼威力使护甲提高25%，持续8秒，最多提高100%", "Warcry Power stays distinct from Strength and retains per-5 scaling and duration")
	check(Localization.source_effect_line("10% faster start of Energy Shield Recharge") == "能量护盾充能启动加快10%", "Faster recharge start describes startup speed, preserving the percentage")
	check(Localization.source_effect_line("10% chance to Poison on Hit") == "击中敌人时，有10%几率使敌人中毒", "Poison-on-hit text identifies the enemy as the target")
	check(Localization.source_effect_line("10% chance to Ignite") == "有10%几率点燃敌人", "Ignite chance names the affected enemy")
	check(Localization.source_effect_line("10% chance to Shock") == "有10%几率使敌人感电", "Shock chance names the affected enemy")
	check(Localization.source_effect_line("10% chance to Freeze") == "有10%几率冻结敌人", "Freeze chance names the affected enemy")
	check(Localization.source_effect_line("10% Chance to Inflict Cold Exposure on Hit with Cold Damage") == "以冰霜伤害击中敌人时，有10%几率对其施加冰霜曝露", "Exposure chance names the hit enemy as the affected target")
	var active_enemy_conditions := {
		"+8% Chance to Block Attack Damage if you've Stunned an Enemy Recently": "若你近期曾击晕敌人，攻击伤害格挡几率+8%",
		"15% increased Area of Effect if you have Stunned an Enemy Recently": "若你近期曾击晕敌人，效果范围提高15%",
		"15% increased Elemental Damage if you've Chilled an Enemy Recently": "若你近期曾使敌人冰缓，元素伤害提高15%",
		"20% increased Elemental Damage if you've Ignited an Enemy Recently": "若你近期曾点燃敌人，元素伤害提高20%",
		"25% increased Elemental Damage if you've Shocked an Enemy Recently": "若你近期曾使敌人感电，元素伤害提高25%",
		"30% increased Damage if you have Shocked an Enemy Recently": "若你近期曾使敌人感电，伤害提高30%",
		"30% increased Damage if you've Shattered an Enemy Recently": "若你近期曾粉碎敌人，伤害提高30%",
		"30% increased Mana Regeneration Rate if you have Frozen an Enemy Recently": "若你近期曾冻结敌人，魔力回复速度提高30%",
		"30% increased Mana Regeneration Rate if you have Shocked an Enemy Recently": "若你近期曾使敌人感电，魔力回复速度提高30%",
		"Regenerate 1% of Energy Shield per second if you've Cursed an Enemy Recently": "若你近期曾诅咒敌人，每秒回复相当于最大能量护盾1%的能量护盾",
		"Regenerate 1% of Life per second if you have Stunned an Enemy Recently": "若你近期曾击晕敌人，每秒回复相当于最大生命1%的生命",
	}
	for source_line: String in active_enemy_conditions:
		check(localized.lines.has(source_line), "Active enemy action remains an exact source key: " + source_line)
		check(Localization.source_effect_line(source_line) == active_enemy_conditions[source_line], "Recent active actions name the enemy as target: " + source_line)
	check(Localization.source_effect_line("You cannot be Ignited if you've been Ignited Recently") == "近期被点燃后，你不会再次被点燃", "A self-applied ailment condition remains distinct from igniting an enemy")
	check(Localization.source_effect_line("Damaging Ailments Cannot Be inflicted on you while you already have one") == "当你已受到一种伤害型异常状态时，无法再被施加伤害型异常状态", "Damaging ailment prevention does not narrow to ‘other’ ailments")
	check(Localization.source_effect_line("Non-Damaging Ailments Cannot Be inflicted on you while you already have one") == "当你已受到一种非伤害性异常状态时，无法再被施加非伤害性异常状态", "Non-damaging ailment prevention does not narrow to ‘other’ ailments")
	check(Localization.source_effect_line("Prevent +3% of Suppressed Spell Damage per Bark below maximum") == "树皮层数每比上限少一层，额外防止+3%被压制的法术伤害", "Suppression prevention states the Bark deficit and preserves the percentage points")
	check(Localization.source_effect_line("10% chance to Avoid non-Damaging Ailments on you per Bark below maximum") == "树皮层数每比上限少一层，避免自身受到非伤害性异常状态的几率增加10%", "Ailment avoidance states the Bark deficit and retains the chance")
	check(Localization.source_effect_line("Warcries have 5% Chance to grant an Endurance, Frenzy or Power Charge per Power") == "战吼威力每有一点，战吼就有5%几率获得一个耐力球、狂怒球或暴击球", "Warcry Power and Power Charges use distinct Chinese terms")
	check(Localization.source_effect_line("25% chance to Steal Power, Frenzy, and Endurance Charges on Hit with Claws") == "使用爪类武器击中敌人时，有25%几率窃取暴击球、狂怒球与耐力球", "Stealing charge types keeps the enemy hit and charge names clear")
	for raw_line: String in all_raw_lines:
		var lower_line := raw_line.to_lower()
		var rendered := Localization.source_effect_line(raw_line)
		if lower_line.contains("flask") and lower_line.contains("charge") and (lower_line.find("flask") < lower_line.find("charge") or lower_line.contains("charges from a flask")):
			check(rendered.contains("充能") and not rendered.contains("药剂球"), "Flask Charge wording is consistent across the full source inventory: " + raw_line.left(60).replace("\n", " / "))
		if lower_line.contains("power"):
			if lower_line.contains("warcry") or lower_line.contains("enemy power"):
				check(rendered.contains("威力"), "Warcry or enemy Power is distinguished from Strength and Power Charges: " + raw_line.left(65).replace("\n", " / "))
			if lower_line.contains("power charge") or lower_line.contains("power, frenzy") or lower_line.contains("frenzy and power"):
				check(rendered.contains("暴击球"), "Power Charge maps to 暴击球 throughout the source inventory: " + raw_line.left(65).replace("\n", " / "))
		var is_projectile_firing := false
		for prefix: String in ["attack skills fire", "attacks fire", "bow attacks fire", "wand attacks fire", "skills fire", "first and final shots of barrage"]:
			if lower_line.begins_with(prefix):
				is_projectile_firing = true
				break
		if is_projectile_firing:
			check(rendered.contains("发射") and not rendered.contains("火焰"), "Projectile firing is translated as a verb: " + raw_line.left(65))
		var has_status := false
		for token: String in ["poison", "ignite", "shock", "freeze", "chill", "bleed", "maim", "taunt", "hinder", "exposure", "withered"]:
			if lower_line.contains(token):
				has_status = true
				break
		if lower_line.contains("chance") and has_status and not lower_line.contains("avoid") and not lower_line.contains("chance to deal") and not lower_line.contains("critical strike chance"):
			var status_zh := Localization.source_effect_line(raw_line)
			check(status_zh.contains("敌人") or status_zh.contains("目标") or status_zh.contains("其"), "Chance-to-ailment row identifies the affected target: " + raw_line.left(70).replace("\n", " / "))
	check(Localization.source_effect_line("+1% to Critical Strike Multiplier per 10 Maximum Energy Shield on Shield") == "盾牌上的最大能量护盾每有10点，暴击伤害倍率+1%", "Multiplier points keep their additive sign and per-10 scaling")
	check(Localization.source_effect_line("Life Recoup Effects instead occur over 3 seconds") == "生命延迟回复效果改为在3秒内完成", "Recoup duration is rendered as a recovery interval")
	check(Localization.source_effect_line("Recover 10% of Mana over 1 second when you use a Guard Skill") == "在1秒内回复相当于最大魔力10%的魔力（使用防护技能时）", "Recovery spread over seconds is not translated as exceeding a threshold")
	check(Localization.source_effect_line("Regenerate 5% of Energy Shield over 1 second when Stunned") == "在1秒内回复相当于最大能量护盾5%的能量护盾（受到眩晕时）", "Timed regeneration retains its duration and stun condition")
	check(Localization.source_effect_line("20% increased Maximum total Life Recovery per second from\nLeech if you've dealt a Critical Strike recently") == "若你近期造成过暴击，生命偷取每秒总回复上限提高20%", "Multiline Leech recovery keeps its complete condition and source scope")
	check(Localization.node_name("14518") == "战斗补给", "Reviewed node name uses a natural Chinese label")
	check(Localization.node_name("65210") == "橡木之心", "Reviewed node name keeps the established fantasy phrase")
	for node_id: String in ["6912", "25934", "35118", "39338"]:
		check(Localization.node_name(node_id) == "双手武器专精", "Reviewed mastery label names the weapon type: " + node_id)

	for node_id: String in EXPECTED_FIRE_DOT_NODES:
		var found := false
		for raw_line: String in Runtime.lines_for(node_id):
			if raw_line == "+%s%% to Fire Damage over Time Multiplier" % FIRE_DOT_AMOUNTS[node_id]:
				found = true
				check(Localization.line_status(raw_line).implemented, "V53 Fire DoT consumer remains supported: " + node_id)
				check(not Localization.display_line(raw_line).ends_with(Localization.NOT_IMPLEMENTED), "V53 Fire DoT line has no false unsupported label: " + node_id)
		check(found, "V53 Fire DoT node keeps its original ID and raw stat: " + node_id)
	for node_id: String in FIRE_MASTERY_NODES:
		var fire_choice: Dictionary = {}
		for option: Dictionary in Data.node(node_id).mastery_effects:
			if int(option.effect) == 36313: fire_choice = option
		check(not fire_choice.is_empty(), "Fire mastery effect ID remains unchanged: " + node_id)
		if fire_choice.is_empty(): continue
		var first: String = str(fire_choice.stats[0])
		var second: String = str(fire_choice.stats[1])
		check(Localization.line_status(first).implemented and not Localization.display_line(first).ends_with(Localization.NOT_IMPLEMENTED), "Fire DoT multiplier row is implemented: " + node_id)
		check(not Localization.line_status(second).implemented and Localization.display_line(second).ends_with(Localization.NOT_IMPLEMENTED), "Unsupported Ignite Duration row gets its own marker: " + node_id)
		check(Runtime.node_effect(node_id, 36313).status == "partial", "Supported and unsupported mastery rows remain partial: " + node_id)
	for node_id: String in ["11364", "43684", "59766"]:
		var node := Data.node(node_id)
		var amount := "15" if node_id == "59766" else "5"
		var expected := "Damaging Ailments deal damage %s%% faster" % amount
		check(node.stats.has(expected), "Faster-ailment node retains source effect and stable ID: " + node_id)
		var node_status := Localization.line_status(expected)
		check(node_status.implemented == (Runtime.CURRENT_SAVE_VERSION >= 33), "Faster-ailment implementation status follows the active schema: " + node_id)
		check(Localization.display_line(expected).ends_with(Localization.NOT_IMPLEMENTED) == (Runtime.CURRENT_SAVE_VERSION < 33), "Faster-ailment display marker follows the active schema: " + node_id)
	var deadly_draw := Data.node("48823")
	check(deadly_draw.stats.size() == 2, "Deadly Draw retains its two independent source effects")
	for raw_line: String in deadly_draw.stats:
		var row_implemented := str(raw_line) == "Damaging Ailments deal damage 10% faster" and Runtime.CURRENT_SAVE_VERSION >= 33
		check(Localization.line_status(str(raw_line)).implemented == row_implemented, "Deadly Draw classifies each source row independently: " + str(raw_line))
		check(Localization.display_line(str(raw_line)).ends_with(Localization.NOT_IMPLEMENTED) == (not row_implemented), "Deadly Draw appends a marker only to unsupported rows")
	if Runtime.CURRENT_SAVE_VERSION >= 33:
		check(Runtime.node_effect("48823").status == "partial", "Deadly Draw remains partial because its Bow DoT row is unsupported")

	var wind_dancer := Data.node("11239")
	var wind_line: String = str(wind_dancer.stats[0])
	check(not Runtime.line_effect(wind_line, 32).supported and not Localization.line_status(wind_line).implemented, "Wind Dancer multiline entry is judged as one unsupported source effect")
	var wind_display := Localization.display_line(wind_line)
	check(wind_display.count(Localization.NOT_IMPLEMENTED) == 1 and not has_ascii(wind_display), "Multiline entry renders fully in Chinese with one trailing marker")
	check(wind_display.contains("额外降低") and wind_display.contains("额外提高") and wind_display.contains("20%") and wind_display.contains("10%"), "Multiline source preserves distinct more/less meanings and values")

	var game := Game.new()
	var before: Dictionary = game.snapshot()
	for raw_line: String in all_raw_lines:
		Localization.display_line(raw_line)
	var after: Dictionary = game.snapshot()
	check(before == after, "Reading localized names and line statuses does not mutate game state")

	await audit_panel(game)
	finish()


func audit_consumer_manifest() -> void:
	var seen_stats: Dictionary = {}
	for group_name: String in Localization.STAT_CONSUMER_GROUPS:
		var group: Dictionary = Localization.STAT_CONSUMER_GROUPS[group_name]
		check(not str(group.get("evidence", "")).is_empty(), "Consumer group has a named runtime path: " + group_name)
		check(group.get("stats", []).size() > 0, "Consumer group names the stats it consumes: " + group_name)
		var code_checks: Array = group.get("code_checks", [])
		check(not code_checks.is_empty(), "Consumer group has source-code checks: " + group_name)
		for stat: String in group.get("stats", []):
			check(not seen_stats.has(stat), "Every supported stat maps to one consumer group: " + stat)
			seen_stats[stat] = group_name
		for code_check: Dictionary in code_checks:
			var relative_path := str(code_check.get("path", ""))
			var source_path := "res://" + relative_path
			check(not relative_path.is_empty() and FileAccess.file_exists(source_path), "Consumer manifest source file exists: " + relative_path)
			if not FileAccess.file_exists(source_path):
				continue
			var must_match := group_name != "damaging_ailment_timing" or Runtime.CURRENT_SAVE_VERSION >= 33
			if must_match:
				var source_text := FileAccess.get_file_as_string(source_path)
				check(source_text.contains(str(code_check.get("contains", ""))), "Consumer manifest marker matches executable source: " + relative_path + " :: " + str(code_check.get("contains", "")))
	check(seen_stats.has("damaging_ailments_faster"), "Schema 33 timing stat has a consumer-group entry before the latest runtime is integrated")


func audit_line(raw_line: String) -> void:
	var translated := Localization.source_effect_line(raw_line)
	check(translated != "词缀翻译缺失" and not has_ascii(translated), "Exact source effect has Chinese display mapping")
	check(number_tokens(raw_line) == number_tokens(translated), "Source numeric values and signs are preserved: " + raw_line.left(70).replace("\n", " / "))
	var status := Localization.line_status(raw_line)
	var displayed := Localization.display_line(raw_line)
	var marker_count := displayed.count(Localization.NOT_IMPLEMENTED)
	check(marker_count == (0 if status.implemented else 1), "One status marker exactly when the complete source line lacks implementation")


func has_ascii(value: String) -> bool:
	return ascii_re.search(value) != null


func number_tokens(value: String) -> Array[String]:
	var result: Array[String] = []
	for match: RegExMatch in number_re.search_all(value):
		result.append(match.get_string())
	result.sort()
	return result


func audit_panel(game: RefCounted) -> void:
	var panel := PassivePanel.new()
	root.add_child(panel)
	panel.setup(game, "user://passive-tree-localization-test.json")
	await process_frame
	check(panel._class.item_count == 7, "Canonical class picker retains all seven original class choices")
	for index: int in range(panel._class.item_count):
		check(not has_ascii(panel._class.get_item_text(index)), "Canonical class picker displays Chinese")
	check(panel._partition.item_count == 39, "Canonical partition picker includes standard, all ascendancies, and expansion view")
	for index: int in range(panel._partition.item_count):
		check(not has_ascii(panel._partition.get_item_text(index)), "Canonical partition picker displays Chinese")
	check(panel._tree._nodes.size() == 2387, "Canonical tree UI retains source node positions and identity")
	for node_id: String in panel._tree._nodes:
		var row: Dictionary = panel._tree._nodes[node_id]
		check(not has_ascii(str(row.name)) and not has_ascii(str(row.description)), "Canonical tree canvas has no raw English name or stat: " + node_id)
	for index: int in range(1, panel._partition.item_count):
		panel._change_partition(index)
		await process_frame
		for node_id: String in panel._tree._nodes:
			var row: Dictionary = panel._tree._nodes[node_id]
			check(not has_ascii(str(row.name)) and not has_ascii(str(row.description)), "Browsable source partition has no raw English name or stat: " + node_id)
	panel._change_partition(0)
	await process_frame
	check(not has_ascii(panel._allocate.text) and not has_ascii(panel._refund.text) and not has_ascii(panel._socket.text) and not has_ascii(panel._return.text), "Passive point and jewel-slot controls display Chinese")
	check(not has_ascii(panel._search.placeholder_text) and not has_ascii(panel._summary.text) and not has_ascii(panel._summary.tooltip_text), "Search and tree status help display Chinese")
	panel.selected_node_id = "11505"
	panel._refresh_details()
	for index: int in range(panel._mastery.item_count):
		check(not has_ascii(panel._mastery.get_item_text(index)), "Mastery choices display translated effects")
	panel._find_node("wind dancer")
	check(panel.selected_node_id == "11239", "English source names remain hidden search aliases")
	check(not has_ascii(panel._detail.text) and panel._detail.text.contains("暂未实装"), "Selected passive detail displays Chinese text and line status")
	panel._node_hovered("11239", Rect2())
	check(not has_ascii(panel._tree.tooltip_text), "Tree hover tooltip displays localized name and effects")
	panel.queue_free()
	await process_frame


func finish() -> void:
	print("Source tree Chinese localization: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
