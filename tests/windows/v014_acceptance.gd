extends SceneTree
## Windows schema10 acceptance. Production scripts load only after this gate.
const Sandbox = preload("res://tests/windows/v014_sandbox.gd")
const LEGACY: Dictionary = {
	8: "res://tests/fixtures/local_weapon_v8_scene.json",
	9: "res://tests/fixtures/pierce_v9_build.json",
}
var model_script: Variant
var damage_script: Variant
var checks: int = 0
var failures: int = 0
var completed: bool = false
var cases: Array[String] = []
var formula_evidence: Array[Dictionary] = []
var migration_encodings: int = 0
var font_evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("V014_QA_FAIL: " + label)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(absf(actual - expected) < 0.0001,
		"%s: actual %.7f, expected %.7f" % [label, actual, expected])


func _write(path: String, bytes: PackedByteArray) -> bool:
	_expect(path.begins_with("user://"), "Fixture writer accepts only verified user:// paths")
	if not path.begins_with("user://"):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Fixture opens: " + path)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	_expect(ok, "Fixture bytes flush: " + path)
	return ok


func _equivalent(left: Dictionary, right: Dictionary) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _encoded(text: String, bom: bool, crlf: bool) -> PackedByteArray:
	var normalized: String = text.replace("\r\n", "\n").strip_edges()
	var bytes: PackedByteArray = PackedByteArray([239, 187, 191]) if bom else PackedByteArray()
	bytes.append_array(("\n  " + normalized + "\n\n").replace("\n", "\r\n" if crlf else "\n").to_utf8_buffer())
	return bytes


func _alias(path: String, dotted: bool = false) -> String:
	if dotted:
		path = path.get_base_dir().path_join("子目录/.././" + path.get_file())
	return ProjectSettings.globalize_path(path).to_upper()


func _expected_current(legacy: Dictionary) -> Dictionary:
	var expected: Dictionary = legacy.duplicate(true)
	expected.version = 10
	for skill: String in expected.skill_supports:
		expected.skill_supports[skill].sort()
	return expected


func _run() -> void:
	if not Sandbox.verify():
		quit(78)
		return
	if OS.get_cmdline_user_args().has("--font-only"):
		_font_runtime()
		_expect(completed, "Native font-only acceptance completes without script exception")
		print("V014_QA_RESULT " + JSON.stringify({"checks": checks, "failures": failures,
			"completed": completed, "cases": ["_font_runtime"], "font": font_evidence}))
		quit(0 if failures == 0 else 1)
		return
	model_script = load("res://scripts/build_state.gd")
	damage_script = load("res://scripts/combat/damage_resolver.gd")
	if model_script == null or damage_script == null:
		quit(1)
		return
	_expect(model_script.SAVE_VERSION == 10, "v0.14 uses schema10")
	_expect(ProjectSettings.get_setting("application/config/version", "") == "0.14.0", "Exact source identifies v0.14.0")
	_expect(DirAccess.make_dir_recursive_absolute("user://中文 存档/子目录") == OK, "Alias fixture directory stays in verified userdata")
	for test: Callable in [_migrations, _version_guards, _backup_conflicts, _font_runtime]:
		completed = false
		test.call()
		_expect(completed, "Case completes without script exception: " + test.get_method())
		cases.append(test.get_method())
	completed = false
	await _roundtrip_and_casts()
	_expect(completed, "Saved pierce builds complete real scene casts")
	cases.append("_roundtrip_and_casts")
	completed = false
	await _scene_migration()
	_expect(completed, "Real startup/migration/autosave completes")
	cases.append("_scene_migration")
	print("V014_QA_RESULT " + JSON.stringify({"checks": checks, "failures": failures,
		"completed": completed and cases.size() == 6, "cases": cases,
		"migration_encodings": migration_encodings, "formulas": formula_evidence,
		"font": font_evidence, "save_version": model_script.SAVE_VERSION}))
	quit(0 if failures == 0 else 1)


func _migrations() -> void:
	for version: int in [8, 9]:
		var literal: String = FileAccess.get_file_as_string(LEGACY[version])
		var historical: Dictionary = JSON.parse_string(literal)
		_expect(int(historical.version) == version, "Literal fixture carries its historical version")
		for bom: bool in [false, true]:
			for crlf: bool in [false, true]:
				for dotted: bool in [false, true]:
					var source: PackedByteArray = _encoded(literal, bom, crlf)
					var path: String = "user://中文 存档/Legacy v%d bom%d crlf%d dot%d.json" % [version, int(bom), int(crlf), int(dotted)]
					var backup: String = path + ".v%d-backup.json" % version
					if not _write(path, source):
						return
					var state: Variant = model_script.new()
					_expect(state.load_build(path), "Historical fixture loads into schema10")
					_expect(_equivalent(state._snapshot(), _expected_current(historical)), "Migration retains all authored equipment, supports, nodes, jewels and positions")
					_expect(FileAccess.get_file_as_bytes(path) == source and not FileAccess.file_exists(backup), "Load makes no disk changes or premature backup")
					var copy_path: String = path + ".save-as.json"
					_expect(state.save_build(copy_path) == OK and FileAccess.get_file_as_bytes(path) == source and not FileAccess.file_exists(backup), "Save As retains pending original-source protection")
					var alias: String = _alias(path, dotted)
					_expect(FileAccess.get_file_as_bytes(alias) == source, "Windows uppercase/dotted alias names the original file")
					_expect(state.save_build(alias) == OK, "Migration overwrite accepts proven Windows alias")
					_expect(FileAccess.get_file_as_bytes(backup) == source, "Migration backup preserves exact BOM/LF/CRLF original bytes")
					var reloaded: Variant = model_script.new()
					_expect(reloaded.load_build(path) and _equivalent(reloaded._snapshot(), _expected_current(historical)), "Current schema10 roundtrip retains the complete historical build")
					_expect(not reloaded.migrated_from_v8 and not reloaded.migrated_from_v9, "Current schema10 reload does not migrate again")
					_expect(reloaded.save_build(path) == OK and FileAccess.get_file_as_bytes(backup) == source, "Later save preserves the first exact-byte backup")
					migration_encodings += 1
	completed = true


func _version_guards() -> void:
	for version: int in [8, 9, 11]:
		var fresh: Variant = model_script.new()
		var record: Dictionary = fresh._snapshot() if version == 11 else JSON.parse_string(FileAccess.get_file_as_string(LEGACY[version]))
		if version == 11:
			record.version = 11
		else:
			record.skill_supports.bolt = ["pierce"]
		var source: PackedByteArray = _encoded(JSON.stringify(record, "\t"), true, true)
		var path: String = "user://中文 存档/Protected v%d.json" % version
		if not _write(path, source):
			return
		var before: Dictionary = fresh._snapshot()
		_expect(not fresh.load_build(path) and fresh._snapshot() == before, "Future v11 / old-schema pierce injection rejects without state mutation")
		_expect(not fresh.last_load_error.is_empty(), "Protected load explains its error")
		for alias: String in [path, ProjectSettings.globalize_path(path), _alias(path), _alias(path, true), _alias(path).replace("/", "\\")]:
			_expect(FileAccess.get_file_as_bytes(alias) == source, "Every tested alias resolves the protected fixture")
			_expect(not fresh.save_block_reason(alias).is_empty(), "Rejected source remains blocked through alias")
			_expect(fresh.save_build(alias) == ERR_INVALID_DATA and FileAccess.get_file_as_bytes(path) == source, "Alias save cannot overwrite protected bytes")
		_expect(not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path + ".v%d-backup.json" % version), "Rejection creates no replacement or migration backup")
		_expect(fresh.save_build(path + ".safe-copy.json") == OK and not fresh.save_block_reason(path).is_empty(), "Saving elsewhere does not remove the original guard")
		if not _write(path, JSON.stringify(before).to_utf8_buffer()):
			return
		_expect(fresh.load_build(_alias(path)) and fresh.save_block_reason(path).is_empty(), "Successful alias load of an externally restored valid save clears its guard")
		_expect(fresh.save_build(path) == OK, "Restored source accepts normal saving")
	completed = true


func _backup_conflicts() -> void:
	var literal: String = FileAccess.get_file_as_string(LEGACY[9])
	var source: PackedByteArray = _encoded(literal, true, true)
	var replacement: PackedByteArray = _encoded(literal, false, false)
	for stale: bool in [false, true]:
		var path: String = "user://中文 存档/Conflict stale%d.json" % int(stale)
		var backup: String = path + ".v9-backup.json"
		if not _write(path, source):
			return
		var state: Variant = model_script.new()
		_expect(state.load_build(path), "Conflict fixture migrates in memory")
		if not _write(path if stale else backup, replacement):
			return
		_expect(state.save_build(_alias(path, true)) == (ERR_FILE_ALREADY_IN_USE if stale else ERR_ALREADY_EXISTS), "Alias cannot bypass stale source / conflicting backup")
		_expect(FileAccess.get_file_as_bytes(path) == (replacement if stale else source), "Refused migration preserves current source bytes")
		_expect(not FileAccess.file_exists(backup) if stale else FileAccess.get_file_as_bytes(backup) == replacement, "Refused migration preserves backup ownership")
	completed = true


func _font_runtime() -> void:
	var required: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/windows/v014_required_han.json"))
	var required_han: String = required.get("characters", "")
	var characters: String = required.get("mapped_characters", "")
	var mapped_han: String = required.get("mapped_han", "")
	_expect(required_han.length() >= 700 and characters.length() == int(required.get("mapped_count", 0)), "Native font probe receives independently collected coverage and all mapped characters")
	var font: FontFile = load("res://assets/fonts/arena_sans.otf")
	_expect(font != null, "Bundled font imports and loads")
	if font == null:
		return
	font.allow_system_fallback = false
	font.fallbacks = []
	var rids: Array[RID] = font.get_rids()
	_expect(rids.size() == 1 and not font.allow_system_fallback and font.fallbacks.is_empty(), "Bundled font is checked without fallback fonts")
	if rids.size() != 1:
		return
	_expect(font.get_supported_chars().length() == characters.length(), "Godot's actual supported character count agrees with fontTools")
	var text_server: TextServer = TextServerManager.get_primary_interface()
	var mappings: int = 0
	for size: int in [16, 19]:
		for index: int in range(characters.length()):
			var codepoint: int = characters.unicode_at(index)
			_expect(font.has_char(codepoint), "Bundled font has U+%04X" % codepoint)
			_expect(text_server.font_get_glyph_index(rids[0], size, codepoint, 0) > 0, "Native glyph mapping exists at %dpx: U+%04X" % [size, codepoint])
			if mapped_han.contains(characters.substr(index, 1)):
				_expect(font.get_char_size(codepoint, size).x > 0.0, "Native Han glyph advance exists at %dpx: U+%04X" % [size, codepoint])
			mappings += 1
	font_evidence = {"han": mapped_han.length(), "required_han": required_han.length(),
		"supported_chars": characters.length(), "native_mappings": mappings,
		"sizes": [16, 19], "fallback": false, "visual_rendering_verified": false}
	completed = true


func _start_scene() -> Node:
	var arena: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	return arena


func _roundtrip_and_casts() -> void:
	for skill: String in ["bolt", "frost"]:
		for links: Array in [[], ["pierce"], ["pierce", "volley"], ["volley", "pierce"], ["pierce", "focus"], ["focus", "pierce"]]:
			var state: Variant = model_script.new()
			for slot: String in ["weapon", "armor", "charm"]:
				state.unequip(slot)
			_expect(state.skill_slots[0] == skill or state.slot_skill(0, skill), "Fixture slots the real spell")
			if not links.is_empty():
				_expect(state.set_skill_supports(skill, links), "Fixture attaches supports through real state transaction")
			var path: String = "user://中文 存档/Roundtrip %s %d.json" % [skill, formula_evidence.size()]
			_expect(state.save_build(path) == OK, "Supported build saves schema10")
			var reloaded: Variant = model_script.new()
			_expect(reloaded.load_build(_alias(path)) and reloaded._snapshot() == state._snapshot(), "Saved pierce and legacy combinations reload the complete build")
			_expect(reloaded.save_build() == OK, "Scene receives the just-reloaded current save")
			var arena: Node = _start_scene()
			_expect(arena.state._snapshot() == reloaded._snapshot(), "Actual scene startup restores the saved supported build")
			arena.enemies.clear()
			arena.monster_runtime.reset()
			arena.spawn_timer = 99999.0
			arena.player_pos = Vector2(500, 300)
			arena.player_facing = Vector2.RIGHT
			arena.rng.seed = 614100
			arena.mana = 100.0
			arena.cooldowns[skill] = 0.0
			var target: Dictionary = arena._spawn_monster("crawler", Vector2(620, 300), "ordinary", "normal", [])
			target.spawn = 0.0
			target.radius = 0.0
			target.health = 100000.0
			target.max_health = 100000.0
			target.shield = 0.0
			target.resistances = {}
			target.speed = 0.0
			var factor: float = (0.85 if links.has("pierce") else 1.0) * (0.8 if links.has("volley") else 1.0) * (1.25 if links.has("focus") else 1.0)
			var mana_factor: float = (1.2 if links.has("pierce") else 1.0) * (1.3 if links.has("volley") else 1.0) * (1.2 if links.has("focus") else 1.0)
			var cost: float = (7.0 if skill == "bolt" else 16.0) * mana_factor
			var damage: float = 18.0 * (1.6 if skill == "bolt" else 0.85) * factor
			var count: int = (3 if skill == "bolt" else 5) + (2 if links.has("volley") else 0)
			var pierce: int = (1 if skill == "bolt" else 2) + (2 if links.has("pierce") else 0)
			_expect(arena.cast_skill(0), "Real scene admits the restored supported cast")
			_near(arena.mana, 100.0 - cost, "Actual mana multiplies each support cost once")
			_near(arena.cooldowns[skill], 0.8 if skill == "bolt" else 4.0, "Actual cooldown is unchanged")
			_expect(arena.projectiles.size() == count and arena.total_shots == count, "Pierce adds no initial carriers; volley adds exactly two")
			for shot: Dictionary in arena.projectiles:
				_expect(shot.pierce == pierce, "Real carrier receives finite +2 pierce")
				_near(shot.damage, damage, "Carrier applies independent literal support damage algebra")
			var cast: Dictionary = arena.state.get_skill_cast(skill)
			_near(damage_script.resolve(cast.packets.secondary, cast.snapshot.modifiers).total, 18.0 * 0.9, "Independent secondary packet retains damage")
			arena._update_projectiles(0.3)
			var health_loss: float = 100000.0 - float(target.health)
			_expect(arena.damage_trace.size() == 1, "Exactly one real center-carrier hit settles")
			_near(health_loss, damage, "Actual target health settles the independent formula")
			var serial_contacts: int = _serial_contacts(arena, skill, damage) if links == ["pierce"] else 0
			formula_evidence.append({"skill": skill, "links": links.duplicate(), "mana_cost": cost,
				"initial_count": count, "pierce": pierce, "expected_hit": damage, "actual_hit": health_loss,
				"serial_contacts": serial_contacts})
			arena.queue_free()
			await process_frame
	completed = true


func _serial_contacts(arena: Node, skill: String, damage: float) -> int:
	# Continue from the same saved/restored support build, through real scene code.
	arena.restart_run()
	arena.auto_fire = false
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.spawn_timer = 99999.0
	arena.player_pos = Vector2(500, 300)
	arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 614100
	arena.mana = 100.0
	arena.cooldowns[skill] = 0.0
	var targets: Array[Dictionary] = []
	for index: int in range(6):
		var target: Dictionary = arena._spawn_monster("crawler", Vector2(580 + 70 * index, 300), "ordinary", "normal", [])
		target.spawn = 0.0
		target.radius = 0.0
		target.health = 100000.0
		target.max_health = 100000.0
		target.shield = 0.0
		target.resistances = {}
		target.speed = 0.0
		targets.append(target)
	_expect(arena.cast_skill(0), "Restored pierce build casts against six real ordered targets")
	var center: Dictionary = arena.projectiles[arena.projectiles.size() / 2]
	arena._update_projectiles(0.15)
	arena._update_projectiles(0.85)
	var hits: int = 0
	for event: Dictionary in arena.combat_trace:
		if event.type == "hit" and int(event.projectile_id) == int(center.id):
			hits += 1
	var capacity: int = 4 if skill == "bolt" else 5
	_expect(hits == capacity and arena.damage_trace.size() == capacity, "Restored bolt/frost carrier settles exactly four/five contacts")
	_expect(center.end_reason == "hit_consumed" and center.pierce == 0, "Last permitted hit consumes the finite carrier")
	for index: int in range(targets.size()):
		_near(100000.0 - float(targets[index].health), damage if index < capacity else 0.0, "Actual ordered health loss proves the saved pierce budget")
	return hits


func _scene_migration() -> void:
	var literal: String = FileAccess.get_file_as_string(LEGACY[9])
	var source: PackedByteArray = _encoded(literal, true, true)
	if not _write("user://build_save.json", source):
		return
	var arena: Node = _start_scene()
	_expect(arena.state.migrated_from_v9 and _equivalent(arena.state._snapshot(), _expected_current(JSON.parse_string(literal))), "Actual scene startup migrates the whole literal v9 build")
	_expect(FileAccess.get_file_as_bytes("user://build_save.json") == source and not FileAccess.file_exists("user://build_save.json.v9-backup.json"), "Actual startup keeps original BOM/CRLF bytes untouched")
	_expect(arena.state.add_skill_support("frost", "pierce"), "Real scene transaction adds pierce to legacy frost volley")
	_expect(FileAccess.get_file_as_bytes("user://build_save.json.v9-backup.json") == source, "Real scene autosave makes the exact-byte legacy backup")
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://build_save.json"))
	_expect(disk is Dictionary and disk.version == 10, "Actual autosave writes schema10")
	var reloaded: Variant = model_script.new()
	_expect(reloaded.load_build() and reloaded.get_skill_supports("frost") == ["pierce", "volley"] and reloaded._snapshot() == arena.state._snapshot(), "Actual autosave reload retains pierce, weapon rolls and special jewel")
	arena.queue_free()
	await process_frame
	completed = true
