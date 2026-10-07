extends SceneTree
## Read current policy and already-recorded Main evidence. No scene or battle replay.
const Bosses = preload("res://scripts/monsters/map_boss_profiles.gd")
const Layout = preload("res://scripts/world/exploration_map_layout.gd")
const Arena = preload("res://scripts/main.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Profiles = preload("res://scripts/monsters/telegraph_profiles.gd")
const INPUT := "res://docs/qa/v101-reference/input-paths.json"
const OUTPUT := "res://docs/qa/v101-reference/ginkgo-inner-outer-fragment.json"


static func evidence(path: String) -> Dictionary:
	assert(FileAccess.file_exists("res://" + path), "Missing recorded evidence: " + path)
	return {"path":path, "sha256":FileAccess.get_sha256("res://" + path)}


static func read_record(item: Dictionary) -> Dictionary:
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://" + item.path))
	assert(result is Dictionary and not result.is_empty())
	return result


static func build_fragment() -> Dictionary:
	var paths: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INPUT))
	var sources: Dictionary = {}
	for key: String in ["actual_main_report", "actual_main_log", "actual_main_fixture", "runtime_tested_inputs", "current_runtime_report", "current_runtime_log"]:
		sources[key] = evidence(paths[key])
	var report := read_record(sources.actual_main_report)
	assert(int(report.failures) == 0 and int(report.checks) > 0 and report.failed_labels.is_empty())
	assert(FileAccess.get_file_as_string("res://" + sources.actual_main_log.path).contains("GINKGO_RING_MAIN checks=%d failures=0" % int(report.checks)))
	var pure := read_record(sources.current_runtime_report)
	assert(int(pure.checks) == 779 and int(pure.failures) == 0 and int(pure.exit_code) == 0)
	assert(pure.production_and_evidence_sha256["scripts/combat/telegraphed_area_runtime.gd"] == FileAccess.get_sha256("res://scripts/combat/telegraphed_area_runtime.gd"))
	var fixture := read_record(sources.actual_main_fixture)
	var decoded: Dictionary = Rules.decode(fixture)
	assert(not decoded.is_empty() and Rules.reason(decoded, Source.reason).is_empty())
	assert(int(fixture.version) == Rules.VERSION and Rules.VERSION == 53)
	assert(Source.CURRENT_SAVE_VERSION == 49 and Equipment.CURRENT_VOCABULARY == 51)
	var boss := Bosses.definition("ginkgo_shelter_slam")
	assert(boss.profile.radius == 130.0 and boss.profile.windup_seconds == 1.4 and boss.profile.damage_multiplier == 0.6)
	assert(boss.second_pulse.inner_radius == 130.0 and boss.second_pulse.radius == 240.0 and boss.second_pulse.windup_seconds == 1.0)
	assert(boss.profile.recovery_seconds == 1.9 and boss.trigger_distance == 240.0 and boss.pulse_count == 2)
	assert(boss.profile_id == "ginkgo_inner_outer" and boss.balance_version == "original-ginkgo-inner-outer-v1")
	assert(Arena.PLAYER_RADIUS == 15.0)
	var entry: Dictionary = report.entries[0]
	var source_enemy: Dictionary = entry.boss
	var example: Dictionary = report.groups.held_input_leave_reenter
	var first: Dictionary = example.trace[0]
	var second: Dictionary = example.trace[1]
	assert(example.trace.size() == 2 and first.shape == "circle" and second.shape == "annulus")
	assert(first.center == second.center and first.source_id == second.source_id and first.attack_id == second.attack_id)
	assert(first.source_id == source_enemy.id and first.attack_age == 1.4 and is_equal_approx(second.attack_age, 2.4))
	assert(first.radius == boss.profile.radius and second.radius == boss.second_pulse.radius and second.inner_radius == boss.second_pulse.inner_radius)
	var contact: Dictionary = Monsters.contact_components(source_enemy)
	for item: Dictionary in [first, second]:
		assert(item.profile_id == boss.profile_id and item.packet.skill_id == boss.profile_id and item.balance_version == boss.balance_version)
		assert(int(item.schema_version) == Profiles.SCHEMA_VERSION)
		assert(is_equal_approx(item.profile.recovery_seconds, entry.policy.profile.recovery_seconds))
		for component: String in contact:
			assert(is_equal_approx(float(item.packet.base.get(component, 0.0)), float(contact[component]) * boss.profile.damage_multiplier))
	assert(first.packet == second.packet and not first.applied and not second.applied)
	assert(example.initial_attack.packet == first.packet and example.initial_attack.center == first.center)
	assert(Layout.BOSS_CENTER == Vector2(3180, 320) and Layout.ENTRY_CLEARANCE == 850.0)
	var rule := {"profile_id":boss.profile_id, "balance_version":boss.balance_version,
		"event_schema_version":Profiles.SCHEMA_VERSION, "player_radius":Arena.PLAYER_RADIUS,
		"combined_damage_multiplier":boss.profile.damage_multiplier * int(boss.pulse_count),
		"safe_inner_distance":boss.second_pulse.inner_radius - Arena.PLAYER_RADIUS,
		"safe_outer_distance":boss.second_pulse.radius + Arena.PLAYER_RADIUS,
		"save_version":Rules.VERSION, "source_policy":Source.CURRENT_SAVE_VERSION,
		"equipment_vocabulary":Equipment.CURRENT_VOCABULARY, "actual_main_checks":int(report.checks),
		"actual_main_method":report.method, "current_runtime_checks":int(pure.checks),
		"main_source_boundary":"Main453在最后的非法内半径0拒绝检查之前运行；合法内半径130与既有路径不变。最终源文件由纯运行态779项检查覆盖；不宣称Main输入SHA与最终运行态源文件相同。", "example_group":"held_input_leave_reenter",
		"example_source":source_enemy, "example_policy":entry.policy, "example_events":example.trace,
		"example_initial_attack":example.initial_attack, "example_outer_snapshot":example.outer_snapshot,
		"scope":"实际Main报告复用：合法新角色与自然入图首领，实际按键退圈再进内心；其他边界、资源、冻结与死亡情形为明确控制的集成探针，不是自然战斗录像。参考导出只读取既有夹具、事件和政策；不重放Main，不另造构筑，不重跑地图或战斗矩阵。"}
	rule.merge(sources)
	for item: Dictionary in sources.values():
		assert(FileAccess.get_sha256("res://" + item.path) == item.sha256)
	return {"game_version":ProjectSettings.get_setting("application/config/version"), "save_version":Rules.VERSION,
		"boss_definition":boss, "description":Layout.description("ginkgo_arcade"), "ginkgo_inner_outer":rule}


func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	assert(isolated.begins_with("/tmp/godot-v101-reference-") and OS.get_user_data_dir().begins_with(isolated + "/"))
	assert(not FileAccess.file_exists(OUTPUT), "Preserve the original bounded export evidence")
	var result := build_fragment()
	if result.is_empty():
		quit(1)
		return
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify(result, "\t", true, true) + "\n"); output.close()
	print("Ginkgo bounded reference: read-only lawful fixture, existing Main events and current policy; no scene, scheduler, battle, map, save or art replay")
	quit(0)
