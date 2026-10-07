extends SceneTree
## One bounded v94 export: read-only actual Main fixture, two cast previews, one support.
const Model = preload("res://scripts/canonical_game_state.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Town = preload("res://scripts/town/town_catalog.gd")
const OUTPUT := "res://docs/qa/v094-reference/encircling-cleave-fragment.json"


static func evidence(path: String) -> Dictionary:
	assert(FileAccess.file_exists("res://" + path), "Missing reference input: " + path)
	return {"path":path, "sha256":FileAccess.get_sha256("res://" + path)}


static func preview(cast: Dictionary) -> Dictionary:
	assert(cast.ok and cast.skill_id == "cleave" and cast.packets.keys() == ["direct"])
	var resolved: Dictionary = Damage.resolve(cast.packets.direct, cast.snapshot.modifiers)
	return {"mana":cast.mana, "cooldown":cast.cooldown, "initial_count":cast.initial_count,
		"recipe":cast.recipe, "summary":Preview.summary(cast), "details":Preview.details(cast),
		"resolved":resolved, "base_coefficient":cast.packets.direct.assembly.base_coefficient,
		"added_effectiveness":cast.packets.direct.assembly.added_effectiveness}


static func build_snapshot() -> Dictionary:
	var fixture := evidence("docs/qa/v094-integration/owned-fixture.json")
	var report := evidence("docs/qa/v094-integration/main-result.json")
	var run_source := evidence("docs/qa/v094-integration/main-run.json")
	var accepted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + report.path))
	var run: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + run_source.path))
	assert(int(accepted.checks) == 121 and int(accepted.failures) == 0 and accepted.labels.is_empty())
	assert(int(run.exit_code) == 0)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + fixture.path))
	var candidate: Dictionary = Model.Rules.decode(raw)
	assert(not candidate.is_empty() and Model.Rules.reason(candidate, Source.reason).is_empty())
	assert(Model.Rules.VERSION == 52 and Source.CURRENT_SAVE_VERSION == 49 and Equipment.CURRENT_VOCABULARY == 51)
	var group: String = accepted.group_id
	assert(candidate.items[accepted.active_uid].definition_id == "skill:cleave")
	assert(candidate.items[accepted.support_uid].definition_id == "support:encircling_cleave")
	assert(candidate.locations[accepted.active_uid] == {"kind":"skill_main", "group_id":group})
	assert(candidate.locations[accepted.support_uid] == {"kind":"skill_support", "group_id":group, "index":0})
	var model := Model.new()
	model._accept_memory(candidate.duplicate(true))
	var ring: Dictionary = model.get_group_cast(group)
	assert(ring.ok and JSON.parse_string(JSON.stringify(ring, "", true, true)) == accepted.ring, "Actual Main ring snapshot must match lawful fixture")
	var plain: Dictionary = Compiler.compile_group("cleave", model.get_combat_snapshot(), [])
	for field: String in plain:
		assert(JSON.parse_string(JSON.stringify(plain[field], "", true, true)) == accepted.plain[field], "Plain snapshot must match actual Main: " + field)
	var before := preview(plain)
	var after := preview(ring)
	assert(is_equal_approx(after.resolved.total, before.resolved.total * 0.75))
	assert(ring.recipe.radius == plain.recipe.radius and ring.cooldown == plain.cooldown)
	assert(ring.recipe.half_angle == PI and plain.recipe.half_angle == PI / 2.0)
	var quote: Dictionary = Model.GemTrade.quote("buy", "support:encircling_cleave")
	var test_offer: Dictionary = Town.offer("support:encircling_cleave")
	assert(quote.ok and quote.cost.calibration_shard == 4 and test_offer.available)
	var definition := Supports.get_definition("encircling_cleave")
	var compatible := Supports.supports_for_skill("cleave")
	assert(compatible.size() == 6 and compatible.has("encircling_cleave"))
	var icon := Gems.definition("support:encircling_cleave").icon as String
	assert(FileAccess.get_sha256(icon) == "029dd3e73ca913cd91505f2d986f946d2b73b250caa63450b2f23d94bfe4dc51")
	assert(model.save_attempts == 0 and model.snapshot() == candidate)
	for item: Dictionary in [fixture, report, run_source]:
		assert(FileAccess.get_sha256("res://" + item.path) == item.sha256)
	var rule := {"save_version":Model.Rules.VERSION, "source_policy":Source.CURRENT_SAVE_VERSION,
		"equipment_vocabulary":Equipment.CURRENT_VOCABULARY, "support_id":"encircling_cleave", "skills":definition.skills,
		"policy":Supports.EncirclingCleave.POLICY, "maximum_supports":Supports.GROUP_MAX_SUPPORTS,
		"compatible_supports":compatible, "merchant_quote":quote, "test_offer":test_offer,
		"normal_reward_pool_includes_support":Model.Journey.GEM_DEFINITIONS.has("support:encircling_cleave"),
		"icon_source":icon, "icon_file":"originals/encircling_cleave.png", "icon_sha256":FileAccess.get_sha256(icon),
		"actual_main_fixture":fixture, "actual_main_report":report, "actual_main_run":run_source,
		"actual_main_checks":accepted.checks, "group_id":group, "active_uid":accepted.active_uid, "support_uid":accepted.support_uid,
		"examples":{"before":before, "after":after},
		"scope":"Lawful purchased and installed actual-Main group9 fixture rehydrated read-only; two cast previews only. No Main, maps, combat matrices, RNG, save writes, historical exporter, source coverage or art generation."}
	return {"game_version":ProjectSettings.get_setting("application/config/version"), "save_version":Model.Rules.VERSION,
		"support":definition, "cleave_compatible_supports":compatible,
		"support_program_example":{"family":definition.family, "native_recipe_eligibility":true, "examples":{"cleave":{"before":before,"after":after}}},
		"encircling_cleave":rule}


func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	assert(isolated.begins_with("/tmp/godot-v094-reference-") and OS.get_user_data_dir().begins_with(isolated + "/"))
	assert(not FileAccess.file_exists(OUTPUT), "Keep the original bounded export evidence")
	var result := build_snapshot()
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(result, "\t", true, true) + "\n"); file.close()
	print("Encircling cleave fragment: lawful Main121/0 and purchased group9 reused read-only; two previews, no full export, Main, maps, RNG, save or art")
	quit(0)
