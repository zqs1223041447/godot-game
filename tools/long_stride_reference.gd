extends SceneTree
## One bounded v98 export: read-only actual Main fixture, two dash previews, one support.
const Model = preload("res://scripts/canonical_game_state.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Town = preload("res://scripts/town/town_catalog.gd")
const OUTPUT := "res://docs/qa/v098-reference/long-stride-fragment.json"


static func evidence(path: String) -> Dictionary:
	assert(FileAccess.file_exists("res://" + path), "Missing reference input: " + path)
	return {"path":path, "sha256":FileAccess.get_sha256("res://" + path)}


static func preview(cast: Dictionary) -> Dictionary:
	assert(cast.ok and cast.skill_id == "dash" and cast.packets.is_empty())
	var policy: Dictionary = Supports.LongStride.POLICY
	var selected: bool = cast.support_ids.has("long_stride")
	return {"mana":cast.mana, "cooldown":cast.cooldown, "initial_count":cast.initial_count,
		"recipe":cast.recipe, "summary":Preview.summary(cast), "details":Preview.details(cast),
		"requested_distance":policy.requested_distance if selected else policy.base_distance,
		"immunity_grant":policy.immunity_grant if selected else policy.base_immunity_grant,
		"support_ids":cast.support_ids, "long_stride_profile":cast.get("long_stride_profile", {})}


static func build_snapshot() -> Dictionary:
	var fixture := evidence("docs/qa/v098-runtime/owned-fixture-after-runtime.json")
	var report := evidence("docs/qa/v098-runtime/main3-result.json")
	var log_source := evidence("docs/qa/v098-runtime/main3.log")
	var reuse_source := evidence("docs/qa/v098-runtime/reuse-fixture.json")
	var tested_source := evidence("docs/qa/v098-runtime/tested-inputs.json")
	var accepted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + report.path))
	var reuse: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + reuse_source.path))
	var tested: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + tested_source.path))
	assert(int(accepted.checks) == 265 and int(accepted.failures) == 0 and accepted.failures_detail.is_empty())
	assert(int(tested.runs[0].compiler_checks_passed) == 138 and int(tested.runs[2].exit_status) == 0)
	assert(FileAccess.get_file_as_string("res://" + log_source.path).contains("LONG_STRIDE_RUNTIME 265 checks, 0 failures"))
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + fixture.path))
	var candidate: Dictionary = Model.Rules.decode(raw)
	assert(not candidate.is_empty() and Model.Rules.reason(candidate, Source.reason).is_empty())
	assert(Model.Rules.VERSION == 53 and Source.CURRENT_SAVE_VERSION == 49 and Equipment.CURRENT_VOCABULARY == 51)
	assert(int(candidate.version) == 53 and fixture.sha256 == tested.reuse_fixture_sha256)
	var group: String = reuse.group_id
	assert(group == "group_000008" and reuse.active_uid == "item_000010")
	assert(candidate.items[reuse.active_uid].definition_id == "skill:dash")
	assert(candidate.locations[reuse.active_uid] == {"kind":"skill_main", "group_id":group})
	for support_id: String in reuse.support_uids:
		var uid: String = reuse.support_uids[support_id]
		assert(candidate.items[uid].definition_id == "support:" + support_id)
		assert(JSON.parse_string(JSON.stringify(candidate.locations[uid])) == reuse.final_support_locations[uid] and candidate.locations[uid].kind == "bag")
	var model := Model.new()
	model._accept_memory(candidate.duplicate(true))
	var snapshot: Dictionary = model.get_combat_snapshot()
	var plain: Dictionary = Compiler.compile_group("dash", snapshot, [])
	var stride: Dictionary = Compiler.compile_group("dash", snapshot, ["long_stride"])
	assert(plain.ok and stride.ok and stride.long_stride_profile == Supports.LongStride.POLICY)
	assert(not plain.has("long_stride_profile") and plain.mana == 12.0 and is_equal_approx(stride.mana, 14.4))
	assert(plain.cooldown == 3.0 and stride.cooldown == plain.cooldown)
	var before := preview(plain)
	var after := preview(stride)
	var quote: Dictionary = Model.GemTrade.quote("buy", "support:long_stride")
	var test_offer: Dictionary = Town.offer("support:long_stride")
	assert(quote.ok and quote.cost.calibration_shard == 4 and test_offer.available)
	var definition := Supports.get_definition("long_stride")
	var compatible := Supports.supports_for_skill("dash")
	assert(compatible == ["efficiency", "quickcast", "long_stride"] and definition.skills == ["dash"])
	assert(not Model.Journey.GEM_DEFINITIONS.has("support:long_stride"))
	var icon := Gems.definition("support:long_stride").icon as String
	assert(FileAccess.get_sha256(icon) == "13540b90703ae35a1c222229c12f27907c224663c94637f82a55ea708c2bc8e7")
	assert(model.save_attempts == 0 and model.snapshot() == candidate and snapshot == model.get_combat_snapshot())
	for item: Dictionary in [fixture, report, log_source, reuse_source, tested_source]:
		assert(FileAccess.get_sha256("res://" + item.path) == item.sha256)
	var rule := {"save_version":Model.Rules.VERSION, "source_policy":Source.CURRENT_SAVE_VERSION,
		"equipment_vocabulary":Equipment.CURRENT_VOCABULARY, "support_id":"long_stride", "skills":definition.skills,
		"policy":Supports.LongStride.POLICY, "maximum_supports":Supports.GROUP_MAX_SUPPORTS,
		"compatible_supports":compatible, "merchant_quote":quote, "test_offer":test_offer,
		"normal_reward_pool_includes_support":false,
		"icon_source":icon, "icon_file":"originals/long_stride.png", "icon_sha256":FileAccess.get_sha256(icon),
		"actual_main_fixture":fixture, "actual_main_report":report, "actual_main_log":log_source,
		"reuse_fixture":reuse_source, "runtime_tested_inputs":tested_source,
		"actual_main_checks":accepted.checks, "compiler_checks":138, "group_id":group,
		"active_uid":reuse.active_uid, "support_uids":reuse.support_uids, "final_support_locations":reuse.final_support_locations,
		"examples":{"before":before, "after":after},
		"scope":"Exact legal schema53 actual-Main final fixture rehydrated read-only; dash remains in group8 and all three owned supports remain in the bag. Two compile_group preview selections only; no item move, purchase, Main replay, maps, RNG, save writes, historical exporter, source coverage or art generation."}
	return {"game_version":ProjectSettings.get_setting("application/config/version"), "save_version":Model.Rules.VERSION,
		"support":definition, "dash_compatible_supports":compatible,
		"support_program_example":{"family":definition.family, "native_recipe_eligibility":true, "examples":{"dash":{"before":before,"after":after}}},
		"long_stride":rule}


func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	assert(isolated.begins_with("/tmp/godot-v098-reference-") and OS.get_user_data_dir().begins_with(isolated + "/"))
	assert(not FileAccess.file_exists(OUTPUT), "Keep the original bounded export evidence")
	var result := build_snapshot()
	if result.is_empty():
		quit(1)
		return
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(result, "\t", true, true) + "\n"); file.close()
	print("Longstride fragment: lawful Main265/0 fixture reused read-only; two previews, bag locations retained, no full export, Main, maps, RNG, save or art")
	quit(0)
