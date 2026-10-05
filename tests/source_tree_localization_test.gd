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
	check(not Localization.line_status("Damaging Ailments deal damage 5% faster").implemented, "Current schema does not claim the future faster-ailment consumer is implemented")
	var comparator_line := "Tinctures deactivate when you have 12 or more Mana Burn"
	check(Localization.source_effect_line(comparator_line) == "当你身上有12层或以上魔力燃烧时，灵药会停用", "‘or more’ stays a threshold comparison, not a MORE modifier")
	check(Localization.source_effect_line("10% more Damage if you've Killed Recently") == "伤害额外提高10%（若你近期击杀过敌人）", "Numeric MORE remains an independent multiplicative modifier")
	var ward_comparator := "Damage taken bypasses Unbroken Ward if the Hit deals less Damage than 15% of Ward"
	check(Localization.source_effect_line(ward_comparator) == "若该次击中造成的伤害低于灵护值的15%，所受伤害会绕过未破损灵护", "‘less than’ stays a comparison and Ward uses the localized game term")
	check(Localization.source_effect_line("1% increased Flask Charges gained per Mana Burn on you") == "你身上每层魔力燃烧，获得的药剂充能提高1%", "Flask charges use ‘充能’, with the per-stack scope intact")
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
	var deadly_draw := Data.node("48823")
	check(deadly_draw.stats.size() == 2, "Deadly Draw retains its two independent source effects")
	for raw_line: String in deadly_draw.stats:
		check(not Localization.line_status(str(raw_line)).implemented, "Deadly Draw marks each unimplemented row independently: " + str(raw_line))
		check(Localization.display_line(str(raw_line)).ends_with(Localization.NOT_IMPLEMENTED), "Deadly Draw appends the unsupported marker to each row")

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
