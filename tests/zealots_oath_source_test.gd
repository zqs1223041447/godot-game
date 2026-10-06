extends SceneTree
## Focused v65 pure/source proof. No scene, save, simulation or imports.
const Oath = preload("res://scripts/mechanics/zealots_oath_rules.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Patterns = preload("res://scripts/passives/source_stat_patterns.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const Old = preload("res://docs/qa/v065-source/frozen/scripts/passives/source_tree_runtime.gd")
const ROOT := "res://docs/qa/v065-source/"
const ENTRY := "Life Regeneration is applied to Energy Shield instead"
const GRANTS := [{"stat":"zealots_oath", "value":1.0, "mode":"flat"}]
const ROUTE := ["54447","57264","37569","36542","4397","7938","14021","55332","42760","36678","7444","63425"]
var checks := 0
var failures := 0
var completed := false
var evidence := {"class_paths":[], "composition_cases":[], "unchanged_stats_vectors":0, "source_nodes_compared":0, "source_masteries_compared":0}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func same(actual: Variant, expected: Variant, label: String) -> void:
	check(var_to_bytes(actual) == var_to_bytes(expected), label)


func base_stats() -> Dictionary:
	return {"max_health":1000.0, "max_mana":50.0, "max_shield":200.0, "strength":0.0, "dexterity":0.0,
		"intelligence":0.0, "armour":100.0, "evasion":200.0, "accuracy":100.0,
		"armour_increased":0.0, "evasion_increased":0.0, "accuracy_increased":0.0,
		"life_regen":0.0, "life_regen_percent":0.0, "melee_physical_increased":0.0,
		"damage":12.0, "attack_speed":1.0, "attack_speed_increased":0.0,
		"move_speed":200.0, "mana_regen":4.0, "shield_regen":2.0,
		"shield_recharge_rate_increased":0.15, "shield_recharge_start_faster":0.10,
		"flask_life_recovery_increased":0.20, "flask_mana_recovery_increased":0.30,
		"attack_life_leech":0.01, "life_leech_rate_increased":0.25, "life_leech_max_rate_increased":0.10,
		"fire_resistance":0.0, "cold_resistance":0.0, "lightning_resistance":0.0,
		"resolute_technique":0.0}


func candidate(ids: Array, version: int = 41, class_id: int = 3) -> Dictionary:
	return {"version":version, "progress":{"level":119,"xp":0}, "items":{}, "locations":{},
		"talents":{"source_version":"3.29.1", "class_id":class_id, "allocated":ids.duplicate(),
			"masteries":{}, "ascendancy":"", "ascendancy_allocated":[], "normal_points":124-ids.size(), "ascendancy_points":0}}


func oracle_integrity() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	check(manifest.source_commit == "23983fe8138e591d2b1af6892b7df13a918dd19d" and manifest.entries.size() == 10 and manifest.source_bytes == 101050, "Independent v64 oracle is the pinned ten-script SourceTree closure")
	for row: Dictionary in manifest.entries:
		check(FileAccess.get_sha256(ROOT + "frozen/" + row.path) == row.frozen_sha256, "Frozen script digest: " + row.path)
	for row: Dictionary in manifest.shared_inputs:
		check(FileAccess.get_sha256("res://" + row.path) == row.sha256, "Shared JSON exactly matches v64: " + row.path)
	check(Old.CURRENT_SAVE_VERSION == 40 and Old._execution_policy(39) == 38 and Old._execution_policy(40) == 40, "Frozen v64 distinguishes save39/source38 from save40/source40")
	completed = true


func pure_rules() -> void:
	for row: Array in [
		[0.0,0.0,0.0,0.0], [10.0,0.0,0.0,10.0], [0.0,0.01,0.0,0.0],
		[10.0,0.0,200.0,10.0], [0.0,0.012,200.0,2.4], [10.0,0.012,200.0,12.4],
		[10.0,0.018,214.0,13.852], [1.25,0.0035,22.5,1.32875],
		[0.0,2.0,200.0,400.0], [1.0e100,0.5,2.0e100,2.0e100]]:
		var result := Oath.profile(row[0],row[1],row[2])
		check(result.ok and result.reason == "" and result.life_rate == 0.0 and is_equal_approx(result.shield_rate,row[3]), "Finite raw flat plus final-shield fraction: " + str(row))
		for field: String in ["life_rate","shield_rate"]:
			check(result[field] is float and is_finite(result[field]) and result[field] >= 0.0, "Successful profile has finite nonnegative float " + field)
	for index: int in range(3):
		for invalid: float in [-0.001,-1.0,NAN,INF,-INF]:
			var args := [10.0,0.012,200.0]
			args[index] = invalid
			var rejected := Oath.profile(args[0],args[1],args[2])
			check(not rejected.ok and not rejected.reason.is_empty(), "Reject invalid parameter%d: %s" % [index,str(invalid)])
	for args: Array in [[0.0,1.0e308,2.0],[1.0e308,1.0,1.0e308]]:
		var rejected := Oath.profile(args[0],args[1],args[2])
		check(not rejected.ok and not rejected.reason.is_empty(), "Reject multiplication or addition overflow from finite inputs")
	completed = true


func parser_and_source() -> void:
	check(Source.CURRENT_SAVE_VERSION == 41 and Source._execution_policy(39) == 38 and Source._execution_policy(40) == 40 and Source._execution_policy(41) == 41, "Only source41 admits the new complete keystone")
	same(Patterns.parse_line(ENTRY).grants,GRANTS,"Complete exact source grants one indivisible flag")
	check(not Patterns.parse_line(ENTRY,true,true,true,true,true,true,true,true,true,true,true,true,false).supported, "Explicit allow_zealots_oath=false rejects the entry")
	check(not Patterns.parse_line(ENTRY,false).supported, "Older prerequisite gate rejects the entry")
	for version: int in range(14,41):
		check(not Source.line_effect(ENTRY,version).supported and Source.line_effect(ENTRY,41).grants == GRANTS and not Source.line_effect(ENTRY,version).supported, "Interleaved old/current caches isolate version%d" % version)
	for bad: Variant in [null,[],{},true,1,NAN,INF,
		"Life Regeneration", "Life Regeneration is applied to Energy Shield", "Regeneration is applied to Energy Shield instead",
		ENTRY + ".", " " + ENTRY, ENTRY + " ", ENTRY + "\n", ENTRY + "\r\n",
		ENTRY.replace("Life Regeneration","Life regeneration"), ENTRY.replace("instead","instead while on Full Life"),
		ENTRY.replace("Energy Shield","Mana"), ENTRY + "\nRegenerate 10 Life per second"]:
		var parsed := Patterns.parse_line(bad)
		check(not parsed.supported and parsed.grants.is_empty(), "Reject split, near-match, conditional and malformed entry: " + str(bad).left(95))
	var detached := Source.line_effect(ENTRY)
	detached.grants[0].value = 99.0
	same(Source.line_effect(ENTRY).grants,GRANTS,"Caller mutation cannot change cached keystone flag")
	var opened: Array[String] = []
	var old_full := 0
	var current_full := 0
	for id: String in Source.Data.standard_ids():
		var old := Old.node_effect(id,0,40)
		var current := Source.node_effect(id,0,41)
		if old.status == "full": old_full += 1
		if current.status == "full": current_full += 1
		if old.status != "full" and current.status == "full": opened.append(id)
		if id != "63425": same(current,old,"Every other standard node preserves exact v64 effect bytes: " + id)
		for version: int in [39,40]: same(Source.node_effect(id,0,version),Old.node_effect(id,0,version),"Frozen%d node bytes: %s" % [version,id])
		evidence.source_nodes_compared += 1
		for choice: Dictionary in Source.Data.node(id).mastery_effects:
			var effect_id := int(choice.effect)
			same(Source.node_effect(id,effect_id,41),Old.node_effect(id,effect_id,40),"No mastery vocabulary expansion: %s:%d" % [id,effect_id])
			evidence.source_masteries_compared += 1
	check(opened == ["63425"] and old_full == 771 and current_full == 772,"Exactly63425 becomes fully implemented,771 to772 standard nodes")
	var raw_owners: Array[String] = []
	for id: String in Source.Data.nodes():
		if Source.Data.node(id).stats.has(ENTRY): raw_owners.append(id)
	check(raw_owners == ["63425"],"Only raw source63425 owns the newly supported exact entry")
	var node := Source.Data.node("63425")
	check(node.name == "Zealot's Oath" and node.type == "keystone" and node.stats == [ENTRY] and Source.node_effect("63425").grants == GRANTS, "Raw63425 identity and full English source remain unchanged")
	evidence.newly_full = opened
	evidence.standard_full_before = old_full
	evidence.standard_full_after = current_full
	completed = true


func paths(class_id: int, version: int) -> Dictionary:
	var start := Source.Data.start_for_class(class_id)
	var result := {start:[start]}
	var queue: Array[String] = [start]
	var offset := 0
	while offset < queue.size():
		var id := queue[offset]
		offset += 1
		for next: String in Source.Data.adjacency(id):
			var node := Source.Data.node(next)
			if result.has(next) or node.type in ["mastery","start"] or node.source.get("isProxy",false) or node.source.get("isBlighted",false): continue
			if Source.node_effect(next,0,version).status != "full": continue
			result[next] = result[id] + [next]
			queue.append(next)
	return result


func graph_and_admission() -> void:
	var expected := [15,16,26,11,22,11,19]
	for class_id: int in range(7):
		var before := paths(class_id,40)
		var after := paths(class_id,41)
		check(not before.has("63425") and after.has("63425") and after["63425"].size()-1 == expected[class_id], "Verified minimum reachable points for class%d" % class_id)
		check(after.size() == before.size()+1, "Opening63425 exposes no extra downstream nodes for class%d" % class_id)
		check(Source.analyze(candidate(after["63425"],41,class_id)).legal, "Every minimal witness passes complete allocation legality")
		evidence.class_paths.append({"class_id":class_id,"name":Source.Data.class_definition(class_id).name,"points":expected[class_id],"minimum_level":maxi(1,expected[class_id]-4),"path":after["63425"]})
	check(Source.analyze(candidate(ROUTE)).legal,"Pinned11-point Witch route is legal")
	for version: int in [39,40]:
		check(not Source.analyze(candidate(ROUTE,version)).legal,"Old%d rejects connected new-keystone allocation" % version)
		check(not Source.available(candidate(ROUTE.slice(0,-1),version)).has("63425"),"Old%d availability rejects63425" % version)
	check(Source.available(candidate(ROUTE.slice(0,-1))).has("63425"),"Current availability admits adjacent complete63425")
	for id: String in ["11513","16246","20050","32176","52544"]:
		var effect := Source.node_effect(id)
		check(effect.status == "partial" and not effect.supported.is_empty() and not effect.unsupported.is_empty(),"Mixed shield/recovery sources stay partial: " + id)
		var locked := candidate(ROUTE + [id])
		check(not Source.analyze(locked).legal,"Partial nodes remain unallocatable: " + id)
	var mixed_route := ["61525","63965","14151","27564","17735","13009","60398","7388","47251","10490","22473","3452","60090","46092","51923","48778","37671","21301","20546","3656","58244","11018","32176"]
	var mixed := candidate(mixed_route,41,5)
	var shape := Source.Allocation.analyze(Source._context(5,123),{"allocated":mixed_route,"masteries":{}},{})
	check(shape.legal and Source.node_effect("32176").status == "partial","Real mixed shield/on-kill node passes ordinary graph and budget legality")
	check(not Source.analyze(mixed).legal and Source.reason(mixed).contains("未实现"),"Connected mixed node is specifically rejected for its unimplemented recovery effect")
	check(not Source.available(candidate(mixed_route.slice(0,-1),41,5)).has("32176"),"Availability omits the reachable partial recovery node")
	completed = true


func composition() -> void:
	# Pure source aggregation vectors use real nodes; graph legality is separate.
	# Witch base Intelligence32 yields3% increased capacity before source increases.
	var specs := [
		{"name":"no_regeneration", "ids":[], "flat":0.0,"fraction":0.0,"shield":206.0,"rate":0.0},
		{"name":"raw_flat_only", "ids":[], "flat":7.5,"fraction":0.0,"shield":206.0,"rate":7.5},
		{"name":"raw_percent_only", "ids":[], "flat":0.0,"fraction":0.01,"shield":206.0,"rate":2.06},
		{"name":"raw_flat_and_percent", "ids":[], "flat":7.5,"fraction":0.01,"shield":206.0,"rate":9.56},
		{"name":"real_robust_flat10_percent1_2", "ids":["31033"], "flat":0.0,"fraction":0.0,"shield":206.0,"rate":12.472},
		{"name":"real_percent0_6", "ids":["32482"], "flat":0.0,"fraction":0.0,"shield":206.0,"rate":1.236},
		{"name":"real_robust_and_percent", "ids":["31033","32482"], "flat":0.0,"fraction":0.0,"shield":206.0,"rate":13.708},
		{"name":"real_robust_percent_shield4", "ids":["31033","32482","38906"], "flat":0.0,"fraction":0.0,"shield":214.0,"rate":13.852},
		{"name":"raw_and_all_source_components", "ids":["31033","32482","38906"], "flat":2.5,"fraction":0.002,"shield":214.0,"rate":16.78},
		{"name":"extra_flat_and_percent_capacity", "ids":["31033","32482","38906","19374"], "flat":0.0,"fraction":0.0,"shield":233.1,"rate":14.1958}]
	for spec: Dictionary in specs:
		var stats := base_stats()
		stats.life_regen = spec.flat
		stats.life_regen_percent = spec.fraction
		var without := candidate(["54447"] + spec.ids)
		var with_oath := candidate(["54447"] + spec.ids + ["63425"])
		var input_bytes := var_to_bytes([stats,without,with_oath])
		var active := Source.apply_stats(stats,with_oath)
		var inactive := Source.apply_stats(stats,without)
		check(active.zealots_oath == 1.0 and active.life_regen == 0.0 and active.life_regen is float and is_equal_approx(active.max_shield,spec.shield) and is_equal_approx(active.shield_regeneration_rate,spec.rate),"Real source composition: " + spec.name)
		var sentinel := active.duplicate(true)
		sentinel.erase("zealots_oath")
		sentinel.erase("shield_regeneration_rate")
		sentinel.life_regen = inactive.life_regen
		same(sentinel,inactive,"Active source changes only life regeneration and its two explicit keys: " + spec.name)
		same(var_to_bytes([stats,without,with_oath]),input_bytes,"Composition leaves all inputs unchanged")
		var reordered := with_oath.duplicate(true)
		reordered.talents.allocated.reverse()
		var reverse := Source.apply_stats(stats,reordered)
		check(is_equal_approx(reverse.shield_regeneration_rate,active.shield_regeneration_rate),"Source order preserves conversion: " + spec.name)
		evidence.composition_cases.append({"name":spec.name,"nodes":spec.ids,"max_shield":active.max_shield,"life_without_oath":inactive.life_regen,"life_with_oath":active.life_regen,"shield_rate":active.shield_regeneration_rate})
	check(Source.lines_for("31033") == ["Regenerate 10 Life per second","Regenerate 1.2% of Life per second"] and Source.node_effect("31033").status == "full","Robust is a real complete flat/percent source")
	check(Source.lines_for("32482") == ["Regenerate 0.6% of Life per second"] and Source.node_effect("32482").status == "full","Independent percent source is real and complete")
	check(Source.lines_for("38906") == ["10% increased Armour","4% increased maximum Energy Shield"] and Source.node_effect("38906").status == "full","Capacity source is real and complete")
	completed = true


func final_capacity_basis() -> void:
	var stats := base_stats()
	var state := candidate(["54447","31033","32482","38906","63425"])
	var ordinary := Source.apply_stats(stats,state)
	var changed_life := stats.duplicate(true)
	changed_life.max_health = 9000.0
	changed_life.strength = 280.0
	var life_result := Source.apply_stats(changed_life,state)
	check(life_result.max_health > ordinary.max_health * 9.0 and life_result.shield_regeneration_rate == ordinary.shield_regeneration_rate,"Life capacity and Strength cannot scale transferred percent regeneration")
	var changed_int := stats.duplicate(true)
	changed_int.intelligence = 78.4
	var int_result := Source.apply_stats(changed_int,state)
	check(int_result.intelligence == 110.0 and is_equal_approx(int_result.max_shield,230.0) and is_equal_approx(int_result.shield_regeneration_rate,14.14),"Rounded aggregate Intelligence and source capacity apply once before percentage conversion")
	var changed_shield := stats.duplicate(true)
	changed_shield.max_shield = 400.0
	var shield_result := Source.apply_stats(changed_shield,state)
	check(is_equal_approx(shield_result.max_shield,428.0) and is_equal_approx(shield_result.shield_regeneration_rate,17.704),"Changing raw capacity preserves flat10 and scales only the percent portion")
	var no_shield := stats.duplicate(true)
	no_shield.max_shield = 0.0
	var zero_capacity := Source.apply_stats(no_shield,state)
	check(zero_capacity.max_shield == 0.0 and zero_capacity.life_regen == 0.0 and zero_capacity.shield_regeneration_rate == 10.0,"Zero shield capacity still compiles flat regeneration; gameplay clamps actual recovery")
	var inactive_state := state.duplicate(true)
	inactive_state.talents.allocated.erase("63425")
	var inactive := Source.apply_stats(stats,inactive_state)
	check(is_equal_approx(inactive.life_regen,28.126) and not is_equal_approx(ordinary.shield_regeneration_rate,inactive.life_regen),"Converted result never reuses already life-scaled total")
	for bad: String in ["10% increased Life Regeneration Rate", "10% increased Energy Shield Regeneration Rate", "10% increased Regeneration Rate", "10% increased Life Recovery Rate", "Regenerate 100 Energy Shield per second", "Regenerate 2% of Energy Shield per second", "Regenerate 1% of Life per second if you have Stunned an Enemy Recently"]:
		check(not Source.line_effect(bad).supported,"No regeneration-rate/recovery/direct-shield/conditional vocabulary expansion: " + bad)
	completed = true


func unchanged_stats() -> void:
	for class_id: int in range(7):
		var route: Array = evidence.class_paths[class_id].path
		route = route.slice(0,-1)
		for ids: Array in [[Source.Data.start_for_class(class_id)],route,route + ["31033","32482","38906"]]:
			for input_case: int in range(3):
				var stats := base_stats()
				stats.max_health = [100.0,850.5,5000.0][input_case]
				stats.max_shield = [0.0,230.5,750.0][input_case]
				stats.life_regen = [0.0,3.5,11.75][input_case]
				stats.life_regen_percent = [0.0,0.012,0.025][input_case]
				stats.intelligence = [0.0,88.6,315.0][input_case]
				var state := candidate(ids,41,class_id)
				var input_bytes := var_to_bytes([stats,state])
				var baseline := Old.apply_stats(stats,state)
				var current := Source.apply_stats(stats,state)
				same(current,baseline,"No63425 full typed output matches frozen v64 class%d/case%d" % [class_id,input_case])
				check(not current.has("zealots_oath") and not current.has("shield_regeneration_rate"),"Unallocated output adds no regeneration keys")
				same(var_to_bytes([stats,state]),input_bytes,"Frozen/current paths leave all inputs unchanged")
				evidence.unchanged_stats_vectors += 1
	for version: int in [39,40]:
		var old_state := candidate(ROUTE,version)
		same(Source.apply_stats(base_stats(),old_state),Old.apply_stats(base_stats(),old_state),"Old%d cannot execute63425 even through direct aggregation" % version)
		evidence.unchanged_stats_vectors += 1
	var iron_state := candidate(["54447","35568","50306","26712","40132","10661"])
	same(Source.apply_stats(base_stats(),iron_state),Old.apply_stats(base_stats(),iron_state),"Existing active Iron Reflexes path retains exact typed bytes")
	evidence.unchanged_stats_vectors += 1
	var jewel_state := candidate(ROUTE.slice(0,-1))
	jewel_state.items.jewel_000003 = {"kind":"jewel","payload":Old.Jewels.starter_jewels().jewel_000003}
	jewel_state.locations.jewel_000003 = {"kind":"passive_socket","node_id":"28475"}
	same(Source.apply_stats(base_stats(),jewel_state),Old.apply_stats(base_stats(),jewel_state),"Existing jewel aggregation retains full output bytes")
	evidence.unchanged_stats_vectors += 1
	completed = true


func chinese_status() -> void:
	check(Localization.node_name("63425") == "狂信者的誓约","Chinese source node identity is preserved")
	var status := Localization.line_status(ENTRY)
	check(status.implemented and status.parser_supported and status.missing_consumers.is_empty(),"Exact source dynamically reports implemented with its consumer manifest")
	var text := Localization.display_line(ENTRY)
	check(not text.ends_with(Localization.NOT_IMPLEMENTED) and text.contains("再生") and text.contains("能量护盾"),"Chinese regeneration rule loses the unsupported marker")
	for row: Dictionary in Localization.STAT_CONSUMER_GROUPS.zealots_oath.code_checks:
		check(FileAccess.get_file_as_string("res://" + row.path).contains(row.contains),"Consumer manifest names executable code: " + row.path)
	for id: String in ["11513","16246","20050","32176","52544"]:
		var effect := Source.node_effect(id)
		for line: String in effect.supported: check(not Localization.display_line(line).ends_with(Localization.NOT_IMPLEMENTED),"Mixed source supported line keeps its marker absent")
		for line: String in effect.unsupported: check(Localization.display_line(line).ends_with(Localization.NOT_IMPLEMENTED),"Mixed source unsupported line retains its marker")
	completed = true


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v065-source-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	for test: Callable in [oracle_integrity,pure_rules,parser_and_source,graph_and_admission,composition,final_capacity_basis,unchanged_stats,chinese_status]:
		completed = false
		test.call()
		check(completed,"Section completes without script exceptions: " + test.get_method())
	evidence.checks = checks
	evidence.failures = failures
	var output := OS.get_environment("V065_SOURCE_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		check(file != null,"Report destination writable")
		if file != null:
			evidence.checks = checks
			evidence.failures = failures
			file.store_string(JSON.stringify(evidence,"\t",true,true) + "\n")
			file.close()
	print("Zealot's Oath source: %d checks, %d failures; %d unchanged v64 stats vectors" % [checks,failures,evidence.unchanged_stats_vectors])
	quit(1 if failures else 0)
