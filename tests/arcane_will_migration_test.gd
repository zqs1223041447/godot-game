extends "res://tests/attack_elemental_passive_migration_test.gd"
## Reuse existing IO fault/assert helpers; execute only the complete60→61 boundary.
const Arcane = preload("res://scripts/save/arcane_will_migration.gd")
const PreviousStep = preload("res://scripts/save/purity_of_flesh_migration.gd")
const CAPTURE := "res://docs/qa/arcane-will/"
var evidence: Array[Dictionary] = []
func check(ok: bool, label: String) -> void:
	evidence.append({"label":label,"ok":ok}); super.check(ok,label)
func expected(source: Dictionary, version: int = 61) -> Dictionary:
	var copy: Dictionary = source.duplicate(true); copy.version = version; return copy
func success_case(source: Dictionary, version: int) -> void:
	var path := "user://arcane-upgrade-%d-%s.json" % [version,"town" if source.journey.active_run.is_empty() else "active"]
	var bytes := (JSON.stringify(source,"  ",false,true)+"\n").to_utf8_buffer(); write(path,bytes)
	var game := Game.new(); var events := [0]; game.changed.connect(func():events[0] += 1)
	var source60: Dictionary = source if version == 60 else PreviousStep.migrate_v59(source)
	var wanted: Dictionary = expected(source60)
	check(game.load_build(path) and game.snapshot() == wanted,"Actual%d load publishes only version change to61, including active journey" % version)
	check(game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1,"Complete chain saves and publishes once")
	check(FileAccess.get_file_as_bytes(path+".v%d-backup.json" % version) == bytes,"Exact original-version backup bytes")
	if version == 59: check(not FileAccess.file_exists(path+".v60-backup.json"),"59→60→61 creates no intermediate60 backup")
	if version == 60: check(game.migrated_from_legacy and game.migration_message.contains("奥术意志") and game.migration_message.contains("不额外赠物或赠点"),"60 notice names full new mechanism and preservation")
	var saved := FileAccess.get_file_as_bytes(path)
	var reopened := Game.new()
	check(reopened.load_build(path) and reopened.snapshot() == wanted and reopened.save_attempts == 0 and not reopened.migrated_from_legacy,"61 reopens with no migration/write")
	check(game.load_build(path) and game.save_attempts == 1 and events[0] == 2 and FileAccess.get_file_as_bytes(path) == saved,"Repeated current load preserves committed bytes")
func failure_case(source: Dictionary, failure: String) -> void:
	var path := "user://arcane-failure-"+failure+".json"
	var bytes := JSON.stringify(source,"\t",true,true).to_utf8_buffer(); write(path,bytes)
	var store := Store.new(); var before: Dictionary = store.snapshot(); var events := [0]
	store.changed.connect(func():events[0] += 1)
	if failure == "backup": store._io = BackupFailIO.new()
	if failure == "external": store._io = ExternalIO.new()
	if failure == "collision": write(path+".v60-backup.json","existing backup".to_utf8_buffer())
	if failure == "atomic": check(DirAccess.make_dir_absolute(path+".tmp") == OK,"Inject final atomic migration write fault")
	check(not store.load_build(path) and store.snapshot() == before and events[0] == 0 and store.successful_saves == 0,"Failed60 upgrade preserves unpublished memory: "+failure)
	check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes),"Preserve original/concurrent file: "+failure)
	check(store.save_attempts == (1 if failure == "atomic" else 0),"Backup/conflict checks precede final write: "+failure)
	if failure in ["external","atomic"]: check(FileAccess.get_file_as_bytes(path+".v60-backup.json") == bytes,"Final-write failure retains exact backup")
	if failure == "collision": check(FileAccess.get_file_as_string(path+".v60-backup.json") == "existing backup","Backup conflict never overwrites prior bytes")
	if failure == "atomic":
		check(DirAccess.remove_absolute(path+".tmp") == OK and store.load_build(path) and store.snapshot() == expected(source) and events[0] == 1 and store.successful_saves == 1,"Healthy retry reuses exact backup and commits once")
func invalid_case(source: Dictionary, bad: String) -> void:
	var invalid: Dictionary = source.duplicate(true)
	match bad:
		"target": invalid.talents.allocated.append("59218"); invalid.talents.normal_points -= 1
		"points": invalid.talents.normal_points += 1
		"items": invalid.items.clear()
		"journey": invalid.journey.best_tiers.erase("ruins_garden")
		"future": invalid.version = 62
	check(Arcane.migrate_v60(invalid,func(_v):return "").is_empty(),"Callback cannot bypass complete frozen60 validator: "+bad)
	var path := "user://arcane-invalid-"+bad+".json"
	var bytes := JSON.stringify(invalid).to_utf8_buffer(); write(path,bytes)
	var store := Store.new(); var before: Dictionary = store.snapshot()
	check(not store.load_build(path) and store.snapshot() == before and store.save_attempts == 0 and FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(path+".v60-backup.json"),"Illegal old/future file protected before backup/write/publish: "+bad)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-arcane-"): quit(78); return
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CAPTURE+"schema60-oracle.json"))
	for name: String in ["town","active"]:
		var path := CAPTURE+"schema60-"+name+".json"
		check(FileAccess.get_sha256(path) == oracle[name+"_sha256"],"Immutable pre-edit60 production sample: "+name)
		var source: Dictionary = Rules.decode_v60(JSON.parse_string(FileAccess.get_file_as_string(path)))
		check(not source.is_empty() and Rules.reason_v60(source).is_empty(),"Complete frozen60 native validation and decode: "+name)
		var original := var_to_bytes(source)
		seed(6160); var control := randi(); seed(6160)
		var migrated: Dictionary = Arcane.migrate_v60(source)
		check(migrated == expected(source) and var_to_bytes(source) == original and randi() == control,"Pure migration changes only version, preserving source/RNG: "+name)
		for field: String in Rules.FIELDS:
			if field != "version": check(migrated[field] == source[field],"Exact canonical field preserved %s/%s" % [name,field])
		check(JSON.parse_string(JSON.stringify(Game._stats_for(source),"",true,true)) == oracle.stats and JSON.parse_string(JSON.stringify(Game._stats_for(migrated),"",true,true)) == oracle.stats,"Inactive old/current stats exactly match captured60 oracle: "+name)
		success_case(source,60)
		if name == "active":
			for failure: String in ["backup","collision","external","atomic"]: failure_case(source,failure)
			for bad: String in ["target","points","items","journey","future"]: invalid_case(source,bad)
	var old59: Dictionary = Rules.decode_v59(JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/purity-of-flesh/schema59-town.json")))
	var intermediate: Dictionary = PreviousStep.migrate_v59(old59)
	check(intermediate.version == 60 and Rules.reason_v60(intermediate).is_empty() and intermediate == expected(old59,60),"Existing59→60 step remains frozen60, never jumps to61")
	success_case(old59,59)
	check(Rules.equipment_vocabulary_for_save_version(60) == 51 and Rules.equipment_vocabulary_for_save_version(61) == 51,"No equipment vocabulary change")
	var output := FileAccess.open(OS.get_environment("ARCANE_MIGRATION_REPORT"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"failed_labels":failures,"evidence":evidence},"\t")+"\n")
	print("ARCANE_MIGRATION checks=%d failures=%d" % [checks,failures.size()]); quit(1 if not failures.is_empty() else 0)
