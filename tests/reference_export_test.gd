extends SceneTree
## Content drift tests compare the exported artifact to the live authorities.
const Exporter = preload("res://tools/export_reference.gd")
const Data = preload("res://scripts/game_data.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Passives = preload("res://scripts/passive_data.gd")
const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Rules = preload("res://scripts/passives/allocation_rules.gd")
const Supports = preload("res://scripts/combat/support_catalog.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	var current: Dictionary = Exporter.clean(Exporter.collect())
	var existing: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/catalog.json"))
	_expect(existing is Dictionary, "export parses")
	if not existing is Dictionary:
		quit(1)
		return
	# Stringify after parsing canonicalizes JSON's int/float representation.
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(current, "", true, true))
	_expect(JSON.stringify(existing, "", true) == JSON.stringify(roundtrip, "", true), "committed JSON exactly matches live export")
	_ids(current.skills, Data.SKILLS.keys(), "all active skills")
	_ids(current.supports, Supports.SUPPORTS.keys(), "all support skills")
	_ids(current.equipment, Equipment.BASES.keys() + Equipment.EXPANSION_BASES.keys(), "legacy and expansion bases")
	_ids(current.affixes, Equipment.AFFIXES.keys() + Equipment.EXPANSION_AFFIXES.keys(), "legacy and expansion affix families")
	_ids(current.jewels, Jewels.BASES.keys() + Jewels.SPECIAL_BASES.keys(), "ordinary and special jewels")
	_ids(current.passives, Passives.get_nodes().keys(), "all original nodes")
	_ids(current.mechanisms, Registry.get_ids(), "all shared mechanisms")
	_ids(current.monsters, Monsters.TEMPLATES.keys(), "all monster templates")
	_expect(current.skills.size() == 8 and current.supports.size() == 2, "bounded skill inventory")
	_expect(current.equipment.size() == 7 and current.affixes.size() == 16, "bounded equipment inventory")
	_expect(current.passives.size() == 181 and current.special_coverage.size() == 12, "complete tree and socket coverage")
	for skill_id: String in current.skills:
		var skill: Dictionary = current.skills[skill_id]
		_expect(skill.compatible_supports == Supports.supports_for_skill(skill_id), "runtime compatibility " + skill_id)
		for config: String in ["fresh", "full_tornado"]:
			_expect(skill.examples[config].size() == (4 if skill_id in ["tornado", "bolt", "frost"] else 1), "all support combinations " + skill_id + "/" + config)
	_expect(current.configurations.fresh.equipped.weapon == "ember_wand", "fresh build does not assume mechanism bow")
	_expect(current.configurations.full_tornado.equipped.weapon == "prism_bow", "full example explicitly equips mechanism bow")
	_expect(current.sources.passive.version == "3.29.1", "passive source preserved")
	_expect(current.sources.affix.source_version == "3.29.3.3", "affix source preserved")
	_expect(current.sources.affix.export_commit == "a77305840b4cc8555eeeea144eac3eeddeff134b", "research commit preserved")
	for socket_id: String in current.special_coverage:
		var sample: Dictionary = current.special_coverage[socket_id]
		var jewel: Dictionary = Jewels.generate_special("jewel_000004")
		var analysis: Dictionary = Rules.analyze(sample.path, {socket_id: jewel.id}, {jewel.id: jewel})
		_expect(Exporter.clean(analysis) == sample.connected, "coverage uses shared analyzer " + socket_id)
		_expect(sample.connected.legal and sample.connected.active_sources.has(socket_id), "connected source activates " + socket_id)
		_expect(not sample.disconnected.legal and sample.disconnected.active_sources.is_empty(), "disconnected source cannot activate " + socket_id)
		_expect(sample.with_remote.legal and sample.with_remote.remote_nodes.has(sample.remote_example), "remote example is legal " + socket_id)
		for node_id: String in sample.connected.granted_by:
			_expect(current.passives[node_id].type in ["small", "notable"], "coverage excludes sockets and origin")
	print("Reference export: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _ids(actual: Dictionary, expected: Array, label: String) -> void:
	var keys: Array = actual.keys()
	keys.sort()
	expected.sort()
	_expect(keys == expected, label)

func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
