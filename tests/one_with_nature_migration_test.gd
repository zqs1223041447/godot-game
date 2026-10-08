extends "res://tests/attack_elemental_passive_migration_test.gd"
## Reuse failure IO/write/assert helpers; only this55→56 entry runs.
const Nature = preload("res://scripts/save/one_with_nature_migration.gd")
const CAPTURE := "res://docs/qa/one-with-nature/"
var evidence: Array[Dictionary] = []
func check(ok: bool, label: String) -> void:
	evidence.append({"label":label,"ok":ok})
	super.check(ok,label)
func expected(source: Dictionary, version: int = 56) -> Dictionary:
	var copy: Dictionary = source.duplicate(true); copy.version = version
	return copy
func success_case(source: Dictionary, version: int) -> void:
	var path := "user://nature-upgrade-%d-%s.json" % [version,"town" if source.journey.active_run.is_empty() else "active"]
	var bytes: PackedByteArray = (JSON.stringify(source,"  ",false,true)+"\n").to_utf8_buffer()
	write(path,bytes)
	var game := Game.new(); var events := [0]
	game.changed.connect(func():events[0] += 1)
	var source55: Dictionary = source if version == 55 else Migration.migrate_v54(source if version == 54 else Prior.migrate_v53(source))
	var wanted: Dictionary = expected(source55)
	check(game.load_build(path) and game.snapshot() == wanted,"Actual%d load publishes exact56 state including active journey" % version)
	check(game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1,"Chained migration persists and publishes once")
	check(FileAccess.get_file_as_bytes(path+".v%d-backup.json" % version) == bytes,"Original version%d bytes backed up" % version)
	for intermediate: int in [54,55]:
		if intermediate > version: check(not FileAccess.file_exists(path+".v%d-backup.json" % intermediate),"No intermediate backup: %d" % intermediate)
	check(game.migrated_from_legacy,"Explicit migration notice")
	if version == 55: check(game.migration_message.contains("与自然合一") and game.migration_message.contains("24%") and game.migration_message.contains("不额外赠物或赠点"),"Notice names exact new effect and preservation")
	var saved := FileAccess.get_file_as_bytes(path)
	var reopened := Game.new()
	check(reopened.load_build(path) and reopened.snapshot() == wanted and reopened.save_attempts == 0 and not reopened.migrated_from_legacy,"Independent56 reopen performs no rewrite")
	check(game.load_build(path) and game.save_attempts == 1 and events[0] == 2 and FileAccess.get_file_as_bytes(path) == saved,"Repeat load retains committed bytes")
func failure_case(source: Dictionary, failure: String) -> void:
	var path := "user://nature-failure-"+failure+".json"
	var bytes := JSON.stringify(source,"\t",true,true).to_utf8_buffer(); write(path,bytes)
	var store := Store.new(); var before: Dictionary = store.snapshot(); var events := [0]
	store.changed.connect(func():events[0] += 1)
	if failure == "backup": store._io = BackupFailIO.new()
	if failure == "external": store._io = ExternalIO.new()
	if failure == "collision": write(path+".v55-backup.json","existing backup".to_utf8_buffer())
	if failure == "atomic": check(DirAccess.make_dir_absolute(path+".tmp") == OK,"Inject final atomic migration failure")
	check(not store.load_build(path) and store.snapshot() == before and events[0] == 0 and store.successful_saves == 0,"Failed55 upgrade leaves memory unpublished: "+failure)
	check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes),"Original/concurrent source bytes preserved: "+failure)
	check(store.save_attempts == (1 if failure == "atomic" else 0),"Backup and conflict checks precede final write: "+failure)
	if failure in ["external","atomic"]: check(FileAccess.get_file_as_bytes(path+".v55-backup.json") == bytes,"Failed final commit retains exact original backup")
	if failure == "collision": check(FileAccess.get_file_as_string(path+".v55-backup.json") == "existing backup","Never overwrite a conflicting backup")
	if failure == "atomic":
		check(DirAccess.remove_absolute(path+".tmp") == OK and store.load_build(path) and store.snapshot() == expected(source) and events[0] == 1 and store.successful_saves == 1,"After fault removal same source/backup migrates exactly once")
func invalid_case(source: Dictionary, bad: String) -> void:
	var invalid: Dictionary = source.duplicate(true)
	match bad:
		"target": invalid.talents.allocated.append("15842"); invalid.talents.normal_points -= 1
		"points": invalid.talents.normal_points += 1
		"items": invalid.items.clear()
		"progress": invalid.journey.best_tiers.erase("ruins_garden")
		"future": invalid.version = 57
	check(Nature.migrate_v55(invalid,func(_v):return "").is_empty(),"Optional callback cannot bypass frozen native validation: "+bad)
	var path := "user://nature-invalid-"+bad+".json"
	var bytes := JSON.stringify(invalid).to_utf8_buffer(); write(path,bytes)
	var store := Store.new(); var before: Dictionary = store.snapshot()
	check(not store.load_build(path) and store.snapshot() == before and store.save_attempts == 0 and FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(path+".v55-backup.json"),"Invalid historical/future file protected before backup or publish: "+bad)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-one-with-nature-"): quit(78); return
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CAPTURE+"schema55-oracle.json"))
	for name: String in ["town","active"]:
		var path := CAPTURE+"schema55-"+name+".json"
		check(FileAccess.get_sha256(path) == oracle[name+"_sha256"],"Immutable baseline55 fixture: "+name)
		var source: Dictionary = Rules.decode_v55(JSON.parse_string(FileAccess.get_file_as_string(path)))
		check(not source.is_empty() and Rules.reason_v55(source).is_empty(),"Full frozen55 validation and decode: "+name)
		var before := var_to_bytes(source)
		seed(5655); var control := randi(); seed(5655)
		var migrated: Dictionary = Nature.migrate_v55(source)
		check(migrated == expected(source) and var_to_bytes(source) == before and randi() == control,"Pure55→56 changes only version and leaves source/RNG intact: "+name)
		for field: String in Rules.FIELDS:
			if field != "version": check(migrated[field] == source[field],"Exact saved field retained %s/%s" % [name,field])
		check(Game._stats_for(migrated) == Game._stats_for(source),"All existing build stats unchanged before new allocation: "+name)
		if name == "active": check(Game._stats_for(source) == oracle.active_stats,"Frozen55 stats match pre-edit captured production oracle")
		success_case(source,55)
		if name == "active":
			for failure: String in ["backup","collision","external","atomic"]: failure_case(source,failure)
			for bad: String in ["target","points","items","progress","future"]: invalid_case(source,bad)
	var old53: Dictionary = Rules.decode_v53(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)))
	var old54: Dictionary = Prior.migrate_v53(old53)
	var old55: Dictionary = Migration.migrate_v54(old54)
	check(old55.version == 55 and Rules.reason_v55(old55).is_empty(),"Existing54→55 step still targets frozen55 rather than56")
	success_case(old54,54); success_case(old53,53)
	check(Rules.equipment_vocabulary_for_save_version(55) == 51 and Rules.equipment_vocabulary_for_save_version(56) == 51,"No new equipment vocabulary")
	var report_path := OS.get_environment("ONE_WITH_NATURE_REPORT")
	if not report_path.is_empty():
		var output := FileAccess.open(report_path,FileAccess.WRITE)
		output.store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"failed_labels":failures,"evidence":evidence},"\t")+"\n")
	print("ONE_WITH_NATURE_MIGRATION checks=%d failures=%d" % [checks,failures.size()])
	quit(1 if not failures.is_empty() else 0)
