extends SceneTree
## Focused v64 pure-rule/source proof. No scenes, saves, simulation or imports.
const Iron = preload("res://scripts/mechanics/iron_reflexes_rules.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Patterns = preload("res://scripts/passives/source_stat_patterns.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Old = preload("res://docs/qa/v064-source/frozen/scripts/passives/source_tree_runtime.gd")
const ROOT := "res://docs/qa/v064-source/"
const ENTRY := "Converts all Evasion Rating to Armour. Dexterity provides no bonus to Evasion Rating"
const GRANTS := [{"stat":"iron_reflexes", "value":1.0, "mode":"flat"}]
const ROUTE := ["50986", "39725", "63649", "49806", "6580", "19711", "20010", "23471", "5237", "6363", "29937", "8544", "10661"]
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
	return {"max_health":100.0, "max_mana":50.0, "max_shield":20.0, "strength":0.0, "dexterity":0.0,
		"intelligence":0.0, "armour":100.0, "evasion":200.0, "accuracy":100.0,
		"armour_increased":0.0, "evasion_increased":0.0, "accuracy_increased":0.0,
		"life_regen":0.0, "life_regen_percent":0.0, "melee_physical_increased":0.0,
		"damage":12.0, "attack_speed":1.0, "attack_speed_increased":0.0,
		"move_speed":200.0, "mana_regen":4.0, "shield_regen":2.0,
		"fire_resistance":0.0, "cold_resistance":0.0, "lightning_resistance":0.0,
		"resolute_technique":0.0}


func candidate(ids: Array, version: int = 40, class_id: int = 4) -> Dictionary:
	return {"version":version, "progress":{"level":119,"xp":0}, "items":{}, "locations":{},
		"talents":{"source_version":"3.29.1", "class_id":class_id, "allocated":ids.duplicate(),
			"masteries":{}, "ascendancy":"", "ascendancy_allocated":[], "normal_points":124-ids.size(), "ascendancy_points":0}}


func oracle_integrity() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	check(manifest.source_commit == "76e2abccf533cd31c20daea92c0e05b02c0980af" and manifest.entries.size() == 9 and manifest.source_bytes == 97517, "Independent v63 oracle is the pinned nine-script 97.5KB closure")
	for row: Dictionary in manifest.entries:
		check(FileAccess.get_sha256(ROOT + "frozen/" + row.path) == row.frozen_sha256, "Frozen script digest: " + row.path)
	for row: Dictionary in manifest.shared_inputs:
		check(FileAccess.get_sha256("res://" + row.path) == row.sha256, "Shared JSON exactly matches v63: " + row.path)
	check(Old.CURRENT_SAVE_VERSION == 38 and Old._execution_policy(39) == 38, "v63 save39 uses the frozen source38 policy")
	completed = true


func pure_rules() -> void:
	for row: Array in [
		[0.0,0.0,0.0,0.0,0.0,0.0,0.0],
		[100.0,200.0,0.0,0.0,0.0,300.0,200.0],
		[100.0,200.0,0.06,0.06,0.06,318.0,212.0],
		[100.0,200.0,0.06,0.06,0.0,330.0,224.0],
		[100.0,200.0,0.20,0.20,0.12,376.0,256.0],
		[0.0,200.0,0.25,0.5,0.0,350.0,350.0],
		[100.0,0.0,0.25,0.5,0.0,125.0,0.0],
		[1.5,2.25,0.25,0.5,0.25,5.25,3.375]]:
		var result := Iron.profile(row[0], row[1], row[2], row[3], row[4])
		check(result.ok and result.reason == "" and is_equal_approx(result.armour,row[5]) and is_equal_approx(result.converted_armour,row[6]) and result.evasion == 0.0, "Finite conversion oracle " + str(row))
		for field: String in ["armour", "evasion", "converted_armour"]:
			check(result[field] is float and is_finite(result[field]) and result[field] >= 0.0, "Successful profile has finite nonnegative float " + field)
	for index: int in range(5):
		for invalid: float in [-0.001, -1.0, NAN, INF, -INF]:
			var args := [100.0,200.0,0.3,0.4,0.1]
			args[index] = invalid
			var rejected := Iron.profile(args[0],args[1],args[2],args[3],args[4])
			check(not rejected.ok and not rejected.reason.is_empty(), "Reject invalid parameter%d: %s" % [index,str(invalid)])
	for args: Array in [[100.0,200.0,0.05,0.2,0.1], [100.0,200.0,0.2,0.05,0.1], [1.0e308,1.0e308,1.0,1.0,0.0], [1.0,1.0e308,2.0,2.0,1.0]]:
		var rejected := Iron.profile(args[0],args[1],args[2],args[3],args[4])
		check(not rejected.ok and not rejected.reason.is_empty(), "Reject impossible shared provenance or finite-input overflow")
	var large := Iron.profile(1.0e100,2.0e100,1.0,1.0,1.0)
	check(large.ok and is_finite(large.armour), "Large representable finite results remain legal")
	completed = true


func parser_and_source() -> void:
	check(Source.CURRENT_SAVE_VERSION == 40 and Source._execution_policy(39) == 38 and Source._execution_policy(40) == 40, "New source40 gate retains save39/source38")
	same(Patterns.parse_line(ENTRY).grants, GRANTS, "Complete exact source grants one indivisible flag")
	check(not Patterns.parse_line(ENTRY,true,true,true,true,true,true,true,true,true,true,true,false).supported, "Explicit allow_iron_reflexes=false rejects the entry")
	check(not Patterns.parse_line(ENTRY,false).supported, "Older prerequisite gate rejects the new entry")
	for version: int in range(14,40):
		check(not Source.line_effect(ENTRY,version).supported and Source.line_effect(ENTRY,40).grants == GRANTS and not Source.line_effect(ENTRY,version).supported, "Interleaved old/current caches isolate version%d" % version)
	for bad: Variant in [null,[],{},true,1,NAN,INF,
		"Converts all Evasion Rating to Armour", "Dexterity provides no bonus to Evasion Rating",
		ENTRY + ".", " " + ENTRY, ENTRY + " ", ENTRY + "\n", ENTRY + "\r\n",
		ENTRY.replace(". ","\n"), ENTRY.replace("Evasion Rating","Evasion rating"), ENTRY.replace("all","50% of"),
		ENTRY + " while on Full Life", ENTRY.replace("Armour.","Energy Shield."),
		"Cannot Evade enemy Attacks\nCannot be Stunned", "6% increased Armour\n6% increased Evasion Rating"]:
		var parsed := Patterns.parse_line(bad)
		check(not parsed.supported and parsed.grants.is_empty(), "Reject split, near-match, conditional and unrelated entry: " + str(bad).left(90))
	var detached := Source.line_effect(ENTRY)
	detached.grants[0].value = 99.0
	same(Source.line_effect(ENTRY).grants, GRANTS, "Caller mutation cannot change cached keystone flag")
	var opened: Array[String] = []
	var old_full := 0
	var current_full := 0
	for id: String in Source.Data.standard_ids():
		var old := Old.node_effect(id,0,39)
		var current := Source.node_effect(id,0,40)
		if old.status == "full": old_full += 1
		if current.status == "full": current_full += 1
		if old.status != "full" and current.status == "full": opened.append(id)
		if id != "10661": same(current,old,"Every other standard node preserves exact effect bytes: " + id)
		same(Source.node_effect(id,0,39),old,"Frozen39 node effect bytes: " + id)
		evidence.source_nodes_compared += 1
		for choice: Dictionary in Source.Data.node(id).mastery_effects:
			var effect_id := int(choice.effect)
			same(Source.node_effect(id,effect_id,40),Old.node_effect(id,effect_id,39),"No mastery vocabulary expansion: %s:%d" % [id,effect_id])
			evidence.source_masteries_compared += 1
	check(opened == ["10661"] and old_full == 770 and current_full == 771,"Exactly10661 becomes fully implemented,770 to771 standard nodes")
	var raw_owners: Array[String] = []
	for id: String in Source.Data.nodes():
		if Source.Data.node(id).stats.has(ENTRY): raw_owners.append(id)
	check(raw_owners == ["10661"],"The exact newly supported entry belongs only to raw source10661")
	var node := Source.Data.node("10661")
	check(node.name == "Iron Reflexes" and node.type == "keystone" and node.stats == [ENTRY] and Source.node_effect("10661").grants == GRANTS, "Raw10661 identity and complete source entry are unchanged")
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
	var expected := [17,15,13,27,12,22,19]
	for class_id: int in range(7):
		var before := paths(class_id,39)
		var after := paths(class_id,40)
		check(not before.has("10661") and after.has("10661") and after["10661"].size()-1 == expected[class_id], "Verified minimum reachable points for class%d" % class_id)
		check(after.size() == before.size()+1, "Opening10661 exposes no extra downstream nodes for class%d" % class_id)
		check(Source.analyze(candidate(after["10661"],40,class_id)).legal, "Every minimal witness passes complete allocation legality")
		evidence.class_paths.append({"class_id":class_id,"name":Source.Data.class_definition(class_id).name,"points":expected[class_id],"minimum_level":maxi(1,expected[class_id]-4),"path":after["10661"]})
	var current := candidate(ROUTE)
	check(Source.analyze(current).legal, "Pinned12-point Duelist route is legal")
	check(not Source.analyze(candidate(ROUTE,39)).legal, "Frozen39 rejects an otherwise connected new-keystone allocation")
	var before := candidate(ROUTE.slice(0,-1))
	check(Source.available(before).has("10661"), "Current availability admits the adjacent complete keystone")
	before.version = 39
	check(not Source.available(before).has("10661"), "Old availability does not admit10661")
	for id: String in ["25111","35185","41433","43725","4944","6982"]:
		var effect := Source.node_effect(id)
		check(effect.status == "partial" and not effect.supported.is_empty() and not effect.unsupported.is_empty(), "Mixed supported/unsupported node stays partial: " + id)
		var locked := current.duplicate(true)
		locked.talents.allocated.append(id)
		locked.talents.normal_points -= 1
		check(not Source.analyze(locked).legal, "Partial nodes remain unallocatable: " + id)
	var mixed_route := ["50986","39725","63649","49806","6580","19711","20010","23471","53002"]
	var mixed := candidate(mixed_route)
	var shape := Source.Allocation.analyze(Source._context(4,123),{"allocated":mixed_route,"masteries":{}},{})
	check(shape.legal and Source.node_effect("53002").status == "partial", "Real mixed10% hybrid/Onslaught node is ordinarily connected and fits the budget")
	check(not Source.analyze(mixed).legal and Source.reason(mixed).contains("未实现"), "Complete-node admission rejects actual connected mixed source specifically for its missing effect")
	check(not Source.available(candidate(mixed_route.slice(0,-1))).has("53002"), "Available nodes omit the reachable partial mixed-defense node")
	completed = true


func composition() -> void:
	# These are pure source-composition vectors; legality is tested separately above.
	# Repeated source text across distinct real nodes must accumulate, never dedupe.
	var specs := [
		{"name":"plain", "ids":[], "armour":300.0, "converted":200.0, "life":111.0},
		{"name":"one_hybrid6", "ids":["35568"], "armour":318.0, "converted":212.0, "life":115.44},
		{"name":"two_hybrid6", "ids":["35568","50306"], "armour":336.0, "converted":224.0, "life":119.88},
		{"name":"three_hybrid6", "ids":["35568","50306","59718"], "armour":354.0, "converted":236.0, "life":124.32},
		{"name":"independent_armour8_evasion8", "ids":["26712","40132"], "armour":340.0, "converted":232.0, "life":111.0},
		{"name":"two_independent_armour8", "ids":["26712","35288"], "armour":348.0, "converted":232.0, "life":111.0},
		{"name":"two_independent_evasion8", "ids":["40132","58854"], "armour":332.0, "converted":232.0, "life":111.0},
		{"name":"hybrid_and_independent", "ids":["35568","50306","26712","40132"], "armour":376.0, "converted":256.0, "life":119.88},
		{"name":"single_armour14", "ids":["31928"], "armour":342.0, "converted":228.0, "life":111.0},
		{"name":"single_evasion14", "ids":["60803"], "armour":328.0, "converted":228.0, "life":111.0}]
	for spec: Dictionary in specs:
		var stats := base_stats()
		var state := candidate(["50986"] + spec.ids + ["10661"])
		var bytes := var_to_bytes([stats,state])
		var result := Source.apply_stats(stats,state)
		check(result.iron_reflexes == 1.0 and result.evasion == 0.0 and is_equal_approx(result.armour,spec.armour) and is_equal_approx(result.evasion_converted_to_armour,spec.converted), "Real source composition: " + spec.name)
		check(is_equal_approx(result.max_health,spec.life), "Other lines on the hybrid source preserve life increases: " + spec.name)
		same(var_to_bytes([stats,state]),bytes,"Composition leaves both input dictionaries unchanged")
		var reordered := state.duplicate(true)
		reordered.talents.allocated.reverse()
		var reverse := Source.apply_stats(stats,reordered)
		check(is_equal_approx(reverse.armour,result.armour) and is_equal_approx(reverse.evasion_converted_to_armour,result.evasion_converted_to_armour), "Source order cannot change conversion: " + spec.name)
		evidence.composition_cases.append({"name":spec.name,"nodes":spec.ids,"armour":result.armour,"converted":result.evasion_converted_to_armour})
	for id: String in ["35568","50306","59718"]:
		check(Source.lines_for(id) == ["6% increased Evasion Rating and Armour","4% increased maximum Life"] and Source.node_effect(id).status == "full", "Witness uses real complete6% hybrid source: " + id)
	for line: String in ["6% increased Evasion Rating and Armour","6% increased Armour and Evasion Rating"]:
		var parsed := Source.line_effect(line)
		check(parsed.supported and parsed.grants.size() == 2 and parsed.grants[0].mode == "increased" and parsed.grants[1].mode == "increased", "Both existing global hybrid word orders retain two increased grants")
	for bad: String in ["6% increased Armour and Evasion Rating while Fortified","6% increased Evasion Rating and Armour during Onslaught","+6 to Armour and Evasion Rating"]:
		check(not Source.line_effect(bad).supported, "No conditional or flat hybrid vocabulary expansion")
	completed = true


func equipment_and_dexterity() -> void:
	var item := {"id":"gear_000621","base_id":"emberhide_vest","rarity":"rare","item_level":16,
		"affixes":[{"id":"ironhide","tier":3,"value":120},{"id":"mistweave","tier":3,"value":450}]}
	for id: String in ["rimeward","stormward"]:
		item.affixes.append({"id":id,"tier":3,"value":int(Catalog.affix_definition(id).tiers[2].max)})
	check(Catalog.validate_instance(item), "Real dual-rating rare vest is legal current equipment")
	var gear := Catalog.get_stats(item)
	check(gear.armour == 120.0 and gear.evasion == 450.0, "Real item yields unscaled flat120 armour/450 evasion")
	var stats := base_stats()
	stats.armour = 0.0
	stats.evasion = 15.0
	for stat: String in gear:
		if stats.has(stat): stats[stat] += float(gear[stat])
	var active := Source.apply_stats(stats,candidate(ROUTE))
	var inactive := Source.apply_stats(stats,candidate(ROUTE.slice(0,-1)))
	check(active.armour == 585.0 and active.evasion_converted_to_armour == 465.0 and active.evasion == 0.0, "Gear plus authored15 evasion converts from the pre-Dex base exactly once")
	check(active.dexterity == 123.0 and active.accuracy == 371.0 and inactive.dexterity == active.dexterity and inactive.accuracy == active.accuracy, "Ten actual Dexterity nodes and class Dexterity retain attributes and accuracy")
	check(is_equal_approx(inactive.evasion,576.6) and inactive.armour == 120.0, "Unallocated source keeps24% Dexterity evasion and ordinary armour")
	var extra_dex := stats.duplicate(true)
	extra_dex.dexterity = 52.0
	var dex_active := Source.apply_stats(extra_dex,candidate(ROUTE))
	check(dex_active.dexterity == 175.0 and dex_active.accuracy == 475.0 and dex_active.armour == active.armour and dex_active.evasion == 0.0, "Extra raw Dexterity still grants accuracy while conversion ignores its evasion bonus")
	var sentinel := active.duplicate(true)
	sentinel.erase("iron_reflexes")
	sentinel.erase("evasion_converted_to_armour")
	var plain := inactive.duplicate(true)
	sentinel.erase("armour"); sentinel.erase("evasion")
	plain.erase("armour"); plain.erase("evasion")
	same(sentinel,plain,"Enabling10661 changes only defense ratings and the two explicit active fields")
	evidence.equipment = {"item":item,"flat_gear":gear,"active_armour":active.armour,"converted":active.evasion_converted_to_armour,"inactive_evasion":inactive.evasion,"dexterity":active.dexterity,"accuracy":active.accuracy}
	completed = true


func unchanged_stats() -> void:
	for class_id: int in range(7):
		var route: Array = evidence.class_paths[class_id].path
		route = route.slice(0,-1)
		for ids: Array in [[Source.Data.start_for_class(class_id)],route,route + ["35568","50306","26712","40132"]]:
			for gear_case: int in range(3):
				var stats := base_stats()
				stats.armour = [0.0,120.0,177.25][gear_case]
				stats.evasion = [15.0,465.0,703.5][gear_case]
				stats.dexterity = [0.0,52.0,3.7][gear_case]
				var state := candidate(ids,40,class_id)
				var input_bytes := var_to_bytes([stats,state])
				var baseline := Old.apply_stats(stats,state)
				var current := Source.apply_stats(stats,state)
				same(current,baseline,"No10661 full typed output matches frozen v63 class%d/gear%d" % [class_id,gear_case])
				check(not current.has("iron_reflexes") and not current.has("evasion_converted_to_armour"), "Unallocated results add no conversion keys")
				same(var_to_bytes([stats,state]),input_bytes,"Frozen and current paths leave all inputs unchanged")
				evidence.unchanged_stats_vectors += 1
	# Exercise the frozen/current jewel accumulation branch without a model or save.
	var jewel_state := candidate(ROUTE.slice(0,-1))
	jewel_state.items.jewel_000003 = {"kind":"jewel","payload":Old.Jewels.starter_jewels().jewel_000003}
	jewel_state.locations.jewel_000003 = {"kind":"passive_socket","node_id":"28475"}
	same(Source.apply_stats(base_stats(),jewel_state),Old.apply_stats(base_stats(),jewel_state),"Existing flat jewel aggregation preserves full output bytes")
	evidence.unchanged_stats_vectors += 1
	completed = true


func chinese_status() -> void:
	check(Localization.node_name("10661") == "铁反射", "Existing Chinese node identity is preserved")
	check(Localization.line_status(ENTRY).implemented and Localization.line_status(ENTRY).parser_supported and Localization.line_status(ENTRY).missing_consumers.is_empty(), "Exact source dynamically reports implemented with its consumer manifest")
	check(Localization.display_line(ENTRY) == "将全部闪避值转化为护甲；敏捷不再提供闪避值加成", "Full two-part Chinese rule loses the unsupported marker together")
	for row: Dictionary in Localization.STAT_CONSUMER_GROUPS.iron_reflexes.code_checks:
		check(FileAccess.get_file_as_string("res://" + row.path).contains(row.contains), "Consumer manifest names executable code: " + row.path)
	var lines := Source.lines_for("25111")
	check(not Localization.display_line(lines[0]).ends_with(Localization.NOT_IMPLEMENTED) and Localization.display_line(lines[1]).ends_with(Localization.NOT_IMPLEMENTED), "Mixed source retains support on hybrid defense and marker on unimplemented aura line")
	for id: String in ["35185","41433","4944","6982"]:
		for line: String in Source.node_effect(id).unsupported:
			check(Localization.display_line(line).ends_with(Localization.NOT_IMPLEMENTED), "Other unsupported effects retain their dynamic Chinese marker")
	completed = true


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v064-source-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	for test: Callable in [oracle_integrity,pure_rules,parser_and_source,graph_and_admission,composition,equipment_and_dexterity,unchanged_stats,chinese_status]:
		completed = false
		test.call()
		check(completed,"Section completes without script exceptions: " + test.get_method())
	evidence.checks = checks
	evidence.failures = failures
	var output := OS.get_environment("V064_SOURCE_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		check(file != null,"Report destination writable")
		if file != null:
			evidence.checks = checks
			evidence.failures = failures
			file.store_string(JSON.stringify(evidence,"\t",true,true) + "\n")
			file.close()
	print("Iron Reflexes source: %d checks, %d failures; %d unchanged v63 stats vectors" % [checks,failures,evidence.unchanged_stats_vectors])
	quit(1 if failures else 0)
