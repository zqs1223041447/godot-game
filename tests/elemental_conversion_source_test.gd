extends SceneTree
## Exact four-entry source expansion, original-graph route and real transactions.
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Frozen = preload("res://tests/fixtures/v078/source_tree_runtime_v077.gd")
const Patterns = preload("res://scripts/passives/source_stat_patterns.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Fixture = preload("res://tests/fixtures/v078/elemental_conversion_fixture.gd")
const ROOT := "res://docs/qa/v078-source/"
const COLD_ENTRANCES := ["17380", "38207", "44179", "54887", "60170", "7023"]
const LIGHTNING_ENTRANCES := ["14122", "240", "37532", "58816", "63482"]
const FIRE_ENTRANCES := ["11505", "19749", "34927", "37911", "38320", "40271", "48267", "63268"]
var checks := 0
var failures := 0
var report := {"changed_effects":[],"route":Fixture.NORMAL_ROUTE,"level":Fixture.LEVEL,"budget":Fixture.BUDGET}

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t",true,true)+"\n")
	file.close()

func parser_checks() -> void:
	check(Source.CURRENT_SAVE_VERSION == 48 and Rules.VERSION == 48, "Current save and source policy48")
	for line: String in Patterns.ELEMENTAL_CONVERSION_ENTRIES:
		var grants := [Patterns.ELEMENTAL_CONVERSION_ENTRIES[line]]
		check(Patterns.parse_line(line).grants == grants, "Only exact original line grants: "+line)
		check(not Patterns.parse_line(line,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,false).supported, "Explicit schema48 gate closes exact entry")
		check(not Patterns.parse_line(line,false).supported, "Prior prerequisite policy closes new entry")
		for version: int in range(14,48):
			check(not Source.line_effect(line,version).supported and Source.line_effect(line,48).grants == grants and not Source.line_effect(line,version).supported, "Warm/cold caches isolate frozen version%d" % version)
		for bad: String in [" "+line,line+" ",line+".",line+"\n",line+"\r",line+" while on Full Life",line+" with Weapons",line.to_lower(),line.replace("40%","40.0%").replace("6%","6.0%"),line.replace("40%","50%").replace("6%","7%")]:
			check(not Patterns.parse_line(bad).supported, "Unapproved syntax remains closed: "+bad)
		var detached := Source.line_effect(line)
		detached.grants[0].value = 9.0
		check(Source.line_effect(line).grants == grants, "Grant cache is detached")
		check(Localization.line_status(line).implemented and not Localization.display_line(line).contains(Localization.NOT_IMPLEMENTED), "Existing Chinese line gains consumer-backed status only")
	for line: String in ["Damage Penetrates 6% Fire Resistance","Damage Penetrates 10% Cold Resistance","Gain 40% of Physical Damage as Extra Cold Damage","Gain 40% of Physical Damage as Extra Lightning Damage","50% of Physical, Cold and Lightning Damage Converted to Fire Damage\nDeal no Non-Fire Damage"]:
		check(not Source.line_effect(line).supported, "Unapproved penetration, extra damage and Avatar remain closed")
	for version: int in range(14,48): check(Source._execution_policy(version) == Frozen._execution_policy(version), "Explicit old execution policy stays frozen")

func closure_checks() -> void:
	for id: String in Source.Data.nodes():
		var node := Source.Data.node(id)
		var choices: Array = [0]
		for effect: Dictionary in node.mastery_effects: choices.append(int(effect.effect))
		for choice: int in choices:
			var old := Frozen.node_effect(id,choice,47)
			check(var_to_bytes(Source.node_effect(id,choice,47)) == var_to_bytes(old), "Every original node/choice remains frozen under47: %s:%d" % [id,choice])
			var now := Source.node_effect(id,choice,48)
			var allowed := (id in ["8833","56716"] and choice == 0) or (COLD_ENTRANCES.has(id) and choice == 4116) or (LIGHTNING_ENTRANCES.has(id) and choice == 53046)
			if allowed:
				check(now.status == "full" and now.unsupported.is_empty() and now != old, "Complete whitelisted original effect opens: %s:%d" % [id,choice])
				report.changed_effects.append("%s:%d" % [id,choice])
			else: check(var_to_bytes(now) == var_to_bytes(old), "No unrelated source effect changes: %s:%d" % [id,choice])
	check(report.changed_effects.size() == 13, "Exactly two complete notables and eleven mastery entrances change")
	check(Source.node_effect("8833").grants == [{"stat":"cold_increased","value":0.3,"mode":"increased"},{"stat":"cold_penetration","value":0.06,"mode":"flat"}], "Heart of Ice keeps original30% and adds original6%")
	check(Source.node_effect("56716").grants == [{"stat":"lightning_increased","value":0.3,"mode":"increased"},{"stat":"lightning_penetration","value":0.06,"mode":"flat"}], "Heart of Thunder keeps original30% and adds original6%")

func transaction_checks() -> void:
	var game := Game.new()
	var initial := game.snapshot()
	for stat: String in ["physical_to_cold_conversion","physical_to_lightning_conversion","cold_penetration","lightning_penetration"]: check(not game.get_stats().has(stat), "Unallocated build carries no optional stat: "+stat)
	var path := "user://source48-route.json"
	if not check(Fixture.prepare(game,path,[]).ok, "Real source route allocates every original edge"): return
	var zero := game.snapshot()
	var zero_stats := game.get_stats()
	check(zero.talents.allocated.size() == 25 and zero.talents.normal_points == 3 and Source.analyze(zero).spent == 24, "Twenty-five ordinary nodes include free root;24 paid points")
	check(zero.items == initial.items and zero.locations == initial.locations and zero.next_item_serial == initial.next_item_serial and zero.migration_ledger == initial.migration_ledger, "Source fixture preserves all item ownership, serial and ledger")
	check(is_equal_approx(zero_stats.cold_penetration,0.06) and is_equal_approx(zero_stats.lightning_penetration,0.06), "Zero-mastery route retains both six-percent prerequisites")
	write_json(ROOT+"fixtures/zero.json",zero)
	for selected: Array in [["cold"],["lightning"],["fire"],["cold","lightning"],["fire","cold"],["fire","lightning"],["fire","cold","lightning"]]:
		if not check(Fixture.select(game,path,selected).ok, "Actual mastery/refund selection: "+str(selected)): return
		var value := game.snapshot()
		check(Rules.reason(value).is_empty() and value.talents.normal_points == 3-selected.size(), "Selected choices exactly consume remaining earned points")
		for type: String in Fixture.MASTERIES:
			var stat := "physical_to_"+type+"_conversion"
			check(is_equal_approx(float(game.get_stats().get(stat,0.0)),0.4 if selected.has(type) else 0.0) and (selected.has(type) or not game.get_stats().has(stat)), "Optional forty-percent stat follows actual selection: "+type)
		for type: String in selected:
			var choice: Dictionary = Fixture.MASTERIES[type]
			var original_bytes := FileAccess.get_file_as_bytes(path)
			var saves := game.save_attempts
			check(not game.allocate_passive(choice.id,choice.effect,game.revision(),path).ok and game.snapshot() == value and FileAccess.get_file_as_bytes(path) == original_bytes and game.save_attempts == saves, "Repeated real mastery choice cannot spend or write: "+type)
		var reopened := Game.new()
		check(reopened.load_build(path) and reopened.snapshot() == value and reopened.get_stats() == game.get_stats() and reopened.save_attempts == 0, "Native48 round trip preserves each selected profile")
	var full := game.snapshot()
	write_json(ROOT+"fixtures/selected.json",full)
	var bytes := FileAccess.get_file_as_bytes(path)
	var attempts := game.save_attempts
	check(full.talents.allocated.size() == 28 and full.talents.normal_points == 0 and Source.analyze(full).spent == 27, "Union spends27:24 ordinary plus3 masteries")
	check(not game.allocate_passive("60170",4116,game.revision(),path).ok and game.snapshot() == full and FileAccess.get_file_as_bytes(path) == bytes and game.save_attempts == attempts, "Duplicate selected mastery is atomic and cannot spend twice")
	check(not game.refund_passive("8833",game.revision(),path).ok and game.snapshot() == full and FileAccess.get_file_as_bytes(path) == bytes, "Owned mastery prevents severing its only original notable")
	check(Fixture.select(game,path,[]).ok and var_to_bytes(game.get_stats()) == var_to_bytes(zero_stats) and game.talent_points == 3, "Refund restores exact zero-mastery stats and points")
	var before := game.snapshot()
	bytes = FileAccess.get_file_as_bytes(path)
	check(DirAccess.make_dir_absolute(path+".tmp") == OK, "Inject actual atomic write failure")
	check(not game.allocate_passive("60170",4116,game.revision(),path).ok and game.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes, "Failed real allocation leaves memory, disk and points unchanged")
	check(DirAccess.remove_absolute(path+".tmp") == OK and game.allocate_passive("60170",4116,game.revision(),path).ok, "Same allocation succeeds after filesystem fault removal")
	check(game.refund_passive("60170",game.revision(),path).ok, "Refund releases source choice after retry")

func duplicate_across_entrances() -> void:
	# Cold/Lightning currently each have one fully supported gateway. Preserve
	# those closed groups and exercise cross-entrance uniqueness with existing Fire.
	var graph := Source._context(3,123)
	var parents := {"54447":""}
	var queue: Array[String] = ["54447"]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for neighbor: String in graph.adjacency[id]:
			var node: Dictionary = graph.nodes[neighbor]
			if parents.has(neighbor) or node.type in ["start","proxy","mastery"] or node.blighted or Source.node_effect(neighbor).status != "full": continue
			parents[neighbor] = id
			queue.append(neighbor)
	for effect: int in [4116,53046,65020]:
		var entrances: Array = COLD_ENTRANCES if effect == 4116 else LIGHTNING_ENTRANCES if effect == 53046 else FIRE_ENTRANCES
		var gateways := {}
		for mastery: String in entrances:
			for id: String in parents:
				var node := Source.Data.node(id)
				if node.type == "notable" and node.group_id == Source.Data.node(mastery).group_id: gateways[mastery] = id; break
		if effect != 65020:
			check(gateways.size() == 1 and gateways.has("60170" if effect == 4116 else "58816"), "Only approved original Cold/Lightning group is fully reachable")
			report["reachable_"+str(effect)] = gateways.keys()
			continue
		if not check(gateways.size() >= 2, "Existing Fire groups exercise shared cross-entrance uniqueness"): continue
		var pair: Array = gateways.keys().slice(0,2)
		var route: Array[String] = ["54447"]
		for mastery: String in pair:
			var segment: Array[String] = []
			var cursor: String = gateways[mastery]
			while not cursor.is_empty(): segment.push_front(cursor); cursor = parents[cursor]
			for id: String in segment:
				if not route.has(id): route.append(id)
		var game := Game.new()
		var candidate := game.snapshot()
		candidate.progress = {"level":119,"xp":0}
		candidate.talents.class_id = 3
		candidate.talents.allocated = ["54447"]
		candidate.talents.masteries = {}
		candidate.talents.normal_points = 123
		game._accept_memory(candidate)
		var path := "user://unique48-%d.json" % effect
		if not check(game.save_build(path) == OK, "Create legal dual-group fixture"): continue
		for id: String in route.slice(1):
			if not check(game.allocate_passive(id,0,game.revision(),path).ok, "Real dual-group allocation: "+id): return
		check(game.available_passives().has(pair[0]) and game.available_passives().has(pair[1]), "Both original entrances are reachable before first choice")
		if not check(game.allocate_passive(pair[0],effect,game.revision(),path).ok, "First unique effect allocation"): return
		var before := game.snapshot()
		var disk := FileAccess.get_file_as_bytes(path)
		var attempts := game.save_attempts
		check(not game.allocate_passive(pair[1],effect,game.revision(),path).ok and game.snapshot() == before and FileAccess.get_file_as_bytes(path) == disk and game.save_attempts == attempts, "Second eligible group rejects duplicate effect before disk write")
		var injected := before.duplicate(true)
		injected.talents.allocated.append(pair[1]); injected.talents.masteries[pair[1]] = effect; injected.talents.normal_points -= 1
		check(not Rules.reason(injected).is_empty(), "Native schema also rejects duplicate across entrances")
		check(game.refund_passive(pair[0],game.revision(),path).ok and game.allocate_passive(pair[1],effect,game.revision(),path).ok, "Refund releases uniqueness for another eligible group")

func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v078-source") or not OS.get_user_data_dir().begins_with(isolation+"/"): quit(78); return
	DirAccess.make_dir_recursive_absolute(ROOT+"fixtures")
	parser_checks(); closure_checks(); transaction_checks(); duplicate_across_entrances()
	report.checks = checks; report.failures = failures
	write_json(ROOT+"source-report.json",report)
	print("Elemental conversion source: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
