extends SceneTree
## Exact schema49 source scope, old48 differential, and real eight-point transactions.
const Patterns = preload("res://scripts/passives/source_stat_patterns.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Frozen = preload("res://tests/fixtures/v082/source_tree_runtime_v081.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Locale = preload("res://scripts/passives/source_tree_localization.gd")
const Grants = preload("res://scripts/mechanics/source_monster_grants.gd")
const Fixture = preload("res://tests/fixtures/v082/cold_ailment_duration_fixture.gd")
const ROOT := "res://docs/qa/v082-source/"
const LINE := "20% increased Duration of Cold Ailments"
const STAT := "cold_ailment_duration_increased"
const GRANT := {"stat":STAT,"value":0.20,"mode":"increased"}
var checks := 0
var failures := 0
var report := {"source_version":"3.29.1","source_sha256":Source.Data.SOURCE_SHA256,"old_schema":48,"new_schema":49,"new_full_nodes":[],"changed_old48_nodes":[],"routes":[],"source_monster_metadata":[]}


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok


func write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func parser_checks() -> void:
	check(Source.CURRENT_SAVE_VERSION == 49 and Source._execution_policy(48) == 48 and Source._execution_policy(49) == 49, "Current source policy49 is separate from frozen48")
	check(Source.Data.node("14209").stats == [LINE] and Patterns.parse_line(LINE).grants == [GRANT], "Node14209 has only the exact original typed20% increased entry")
	for version: int in range(14,49):
		check(not Source.line_effect(LINE,version).supported and Source.line_effect(LINE,version) == Frozen.line_effect(LINE,version), "Explicit old%d still rejects the new entry" % version)
		check(Source.line_effect(LINE,49).grants == [GRANT] and not Source.line_effect(LINE,version).supported, "Interleaved old/current cache remains separate")
	for input: Variant in [null,{},[],true,20,NAN,INF,"0% increased Duration of Cold Ailments","20.0% increased Duration of Cold Ailments","50% increased Duration of Cold Ailments","-20% increased Duration of Cold Ailments","+20% increased Duration of Cold Ailments","20% increased duration of Cold Ailments","20% increased Duration of Cold Ailments."," "+LINE,LINE+" ",LINE+"\n",LINE+"\r",LINE+" while Chilled",LINE+" with Attacks","20% chance to Freeze","20% increased Duration of Ailments","20% increased Duration of Chill","20% increased Effect of Cold Ailments","20% increased Duration of Brittle"]:
		var parsed := Patterns.parse_line(input)
		check(not parsed.supported and parsed.grants.is_empty(), "Unapproved amount/chance/condition/type/text rejected: "+str(input))
	var detached := Source.line_effect(LINE)
	detached.grants[0].value = 0.50
	check(Source.line_effect(LINE).grants == [GRANT], "Parser cache output is detached")


func scope_checks() -> void:
	var occurrences: Array[String] = []
	var newly_full: Array[String] = []
	var changed_old: Array[String] = []
	for id: String in Source.Data.nodes():
		var node := Source.Data.node(id)
		for line: String in node.stats:
			if line == LINE: occurrences.append(id)
		var old := Frozen.node_effect(id,0,48)
		var explicit_old := Source.node_effect(id,0,48)
		var current := Source.node_effect(id,0,49)
		check(explicit_old == old, "Frozen48 whole-node effect unchanged: "+id)
		if explicit_old != old: changed_old.append(id)
		if old.status != "full" and current.status == "full": newly_full.append(id)
		if id != "14209": check(current == old, "No other node or mixed line gains support: "+id)
		for choice: Dictionary in node.mastery_effects:
			var effect := int(choice.effect)
			check(Source.node_effect(id,effect,48) == Frozen.node_effect(id,effect,48) and Source.node_effect(id,effect,49) == Frozen.node_effect(id,effect,48), "Mastery remains identical: %s:%d" % [id,effect])
	occurrences.sort(); newly_full.sort()
	check(occurrences == ["14209"] and newly_full == ["14209"] and changed_old.is_empty(), "Only node14209 newly opens across the entire pinned source graph")
	check(Source.node_effect("21460",0,49) == Frozen.node_effect("21460",0,48) and Source.node_effect("21460",0,49).status != "full", "Node21460 and its50% duration remain blocked")
	check(Source.node_effect("14209",0,49).grants == [GRANT], "Whole eligible node exposes one typed stat")
	check(Locale.ready() and Locale.line_status(LINE).implemented and not Locale.display_line(LINE).contains(Locale.NOT_IMPLEMENTED), "Exact20% line is marked implemented with its consumer evidence")
	check(Locale.display_line("50% increased Duration of Cold Ailments").contains(Locale.NOT_IMPLEMENTED), "Unapproved50% line retains the unimplemented marker")
	for probe: Dictionary in Locale.STAT_CONSUMER_GROUPS.cold_ailment_duration.code_checks:
		check(FileAccess.get_file_as_string("res://"+probe.path).contains(probe.contains), "Consumer evidence names a real production anchor: "+probe.path)
	report.new_full_nodes = newly_full
	report.changed_old48_nodes = changed_old
	report.exact_line_occurrences = occurrences


func route_checks() -> void:
	for class_id: int in [3,6]:
		var game := Game.new()
		var path := "user://cold-duration-route%d.json" % class_id
		var items_before: Dictionary = game.snapshot().items
		if not check(Fixture.prepare(game,path,false,class_id).ok, "Prepare lawful seven-node prefix through real commands for class%d" % class_id): continue
		var route: Array = Fixture.WITCH_ROUTE if class_id == 3 else Fixture.SHADOW_ROUTE
		check(game.snapshot().talents.allocated == route.slice(0,8) and game.snapshot().talents.normal_points == 1 and Rules.reason(game.snapshot()).is_empty(), "Level4 lawful prefix has exactly one point remaining")
		check(game.available_passives().has(Fixture.TARGET) and game.get_stats()[STAT] == 0.0, "UI availability exposes20% node with zero grant before allocation")
		var before := game.snapshot()
		var disk := FileAccess.get_file_as_bytes(path)
		check(not game.allocate_passive(Fixture.TARGET,0,NAN,path).ok and game.snapshot() == before and FileAccess.get_file_as_bytes(path) == disk, "Malformed revision cannot mutate memory or disk")
		check(DirAccess.make_dir_absolute(path+".tmp") == OK, "Inject allocation atomic-write failure")
		check(not game.allocate_passive(Fixture.TARGET,0,game.revision(),path).ok and game.snapshot() == before and FileAccess.get_file_as_bytes(path) == disk and game.get_stats()[STAT] == 0.0, "Failed allocation publishes neither grant nor spend")
		check(DirAccess.remove_absolute(path+".tmp") == OK and game.allocate_passive(Fixture.TARGET,0,game.revision(),path).ok, "Retry allocates actual eighth paid node")
		var selected := game.snapshot()
		check(selected.talents.allocated == route and selected.talents.normal_points == 0 and selected.items == items_before and is_equal_approx(game.get_stats()[STAT],0.20), "Actual eight-point route applies exact20% without items or points gifts")
		check(Rules.reason(selected).is_empty(), "Selected route remains canonical-valid")
		var old := selected.duplicate(true)
		old.version = 48
		check(not Rules.reason_v48(old).is_empty() and Rules.decode_v48(JSON.parse_string(JSON.stringify(old))).is_empty(), "Same selected route cannot enter schema48")
		var reopened := Game.new()
		check(reopened.load_build(path) and reopened.snapshot() == selected and is_equal_approx(reopened.get_stats()[STAT],0.20) and reopened.save_attempts == 0, "Actual selected save reopens with the same increased grant and no migration")
		check(not game.refund_passive("27415",game.revision(),path).ok and game.snapshot() == selected, "Disconnecting prerequisite refund is rejected")
		disk = FileAccess.get_file_as_bytes(path)
		check(DirAccess.make_dir_absolute(path+".tmp") == OK and not game.refund_passive(Fixture.TARGET,game.revision(),path).ok and game.snapshot() == selected and FileAccess.get_file_as_bytes(path) == disk, "Failed refund retains grant and spent point")
		check(DirAccess.remove_absolute(path+".tmp") == OK and game.refund_passive(Fixture.TARGET,game.revision(),path).ok and game.snapshot().talents.normal_points == 1 and game.get_stats()[STAT] == 0.0, "Actual refund removes exactly the grant and returns one point")
		var refunded := Game.new()
		check(refunded.load_build(path) and refunded.get_stats()[STAT] == 0.0 and refunded.snapshot() == game.snapshot(), "Refund survives native49 reload")
		if class_id == 3:
			write(ROOT+"fixtures/witch-selected.json",JSON.stringify(selected,"\t",true,true).to_utf8_buffer())
			write(ROOT+"fixtures/witch-refunded.json",JSON.stringify(game.snapshot(),"\t",true,true).to_utf8_buffer())
		report.routes.append({"class_id":class_id,"path":route,"paid_points":8,"selected_stat":0.20,"refunded_stat":0.0,"transactions":"allocate/reload/failed allocation/failed refund/disconnect/refund/reload"})


func source_monster_checks() -> void:
	Grants._runtime = Frozen
	Grants._cache_keys.clear(); Grants._cached_definitions.clear()
	var old := {}
	for id: String in Grants.IDS: old[id] = Grants.resolve(id)
	Grants._runtime = Source
	Grants._cache_keys.clear(); Grants._cached_definitions.clear()
	for id: String in Grants.IDS:
		var current := Grants.resolve(id)
		if not check(old[id].ok and current.ok, "Existing source monster grant resolves in both policies: "+id): continue
		var previous: Dictionary = old[id].definition.duplicate(true)
		var actual: Dictionary = current.definition
		check(previous.source_policy == 48 and previous.source_save_version == 48 and actual.source_policy == 49 and actual.source_save_version == 49, "Source monster provenance follows current49: "+id)
		previous.source_policy = 49
		previous.source_save_version = 49
		previous.policy_version = "source-tree:%s:policy:49" % previous.source_entry.source_version
		check(previous == actual and current.stats == old[id].stats and current.get("capacity_increased",{}) == old[id].get("capacity_increased",{}), "Existing source monster numeric grants and raw entries are identical after explicit metadata normalization: "+id)
		report.source_monster_metadata.append({"id":id,"changed_fields":["source_policy","source_save_version","policy_version"],"old_policy":48,"new_policy":49,"numeric_grants_unchanged":current.stats == old[id].stats})


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v082-source") or not OS.get_user_data_dir().begins_with(isolation+"/"): quit(78); return
	DirAccess.make_dir_recursive_absolute(ROOT+"fixtures")
	parser_checks(); scope_checks(); route_checks(); source_monster_checks()
	report.checks = checks; report.failures = failures
	write(ROOT+"source-report.json",(JSON.stringify(report,"\t",true,true)+"\n").to_utf8_buffer())
	print("Cold ailment duration source: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
