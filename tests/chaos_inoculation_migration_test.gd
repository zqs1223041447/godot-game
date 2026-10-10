extends "res://tests/attack_elemental_passive_migration_test.gd"
## Reuse existing IO fault/assert helpers; execute only the complete58→59 boundary.
const Inoculation = preload("res://scripts/save/chaos_inoculation_migration.gd")
const WillStep = preload("res://scripts/save/iron_will_migration.gd")
const CAPTURE := "res://docs/qa/chaos-inoculation/"
var evidence: Array[Dictionary] = []
func check(ok: bool, label: String) -> void:
	evidence.append({"label":label,"ok":ok}); super.check(ok,label)
func expected(source: Dictionary, version: int = Rules.VERSION) -> Dictionary:
	var copy: Dictionary = source.duplicate(true); copy.version = version; return copy
func success_case(source: Dictionary, version: int) -> void:
	var path := "user://ci-upgrade-%d-%s.json" % [version,"town" if source.journey.active_run.is_empty() else "active"]
	var bytes := (JSON.stringify(source,"  ",false,true)+"\n").to_utf8_buffer(); write(path,bytes)
	var game := Game.new(); var events := [0]; game.changed.connect(func():events[0] += 1)
	var source58: Dictionary = source if version == 58 else WillStep.migrate_v57(source)
	var wanted: Dictionary = expected(source58)
	check(game.load_build(path) and game.snapshot() == wanted,"Actual%d load publishes only version change to current, including active journey" % version)
	check(game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1,"Complete chain through current version saves and publishes once")
	check(FileAccess.get_file_as_bytes(path+".v%d-backup.json" % version) == bytes,"Exact original-version backup bytes")
	if version == 57: check(not FileAccess.file_exists(path+".v58-backup.json"),"57→58→59 creates no intermediate58 backup")
	if version == 58: check(game.migrated_from_legacy and game.migration_message.contains("混沌防护") and game.migration_message.contains("不额外赠物或赠点"),"58 notice names full new mechanism and preservation")
	var saved := FileAccess.get_file_as_bytes(path)
	var reopened := Game.new()
	check(reopened.load_build(path) and reopened.snapshot() == wanted and reopened.save_attempts == 0 and not reopened.migrated_from_legacy,"Current save reopens with no migration/write")
	check(game.load_build(path) and game.save_attempts == 1 and events[0] == 2 and FileAccess.get_file_as_bytes(path) == saved,"Repeated current load preserves committed bytes")
func failure_case(source: Dictionary, failure: String) -> void:
	var path := "user://ci-failure-"+failure+".json"
	var bytes := JSON.stringify(source,"\t",true,true).to_utf8_buffer(); write(path,bytes)
	var store := Store.new(); var before: Dictionary = store.snapshot(); var events := [0]
	store.changed.connect(func():events[0] += 1)
	if failure == "backup": store._io = BackupFailIO.new()
	if failure == "external": store._io = ExternalIO.new()
	if failure == "collision": write(path+".v58-backup.json","existing backup".to_utf8_buffer())
	if failure == "atomic": check(DirAccess.make_dir_absolute(path+".tmp") == OK,"Inject final atomic migration write fault")
	check(not store.load_build(path) and store.snapshot() == before and events[0] == 0 and store.successful_saves == 0,"Failed58 upgrade preserves unpublished memory: "+failure)
	check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes),"Preserve original/concurrent file: "+failure)
	check(store.save_attempts == (1 if failure == "atomic" else 0),"Backup/conflict checks precede final write: "+failure)
	if failure in ["external","atomic"]: check(FileAccess.get_file_as_bytes(path+".v58-backup.json") == bytes,"Final-write failure retains exact backup")
	if failure == "collision": check(FileAccess.get_file_as_string(path+".v58-backup.json") == "existing backup","Backup conflict never overwrites prior bytes")
	if failure == "atomic":
		check(DirAccess.remove_absolute(path+".tmp") == OK and store.load_build(path) and store.snapshot() == expected(source) and events[0] == 1 and store.successful_saves == 1,"Healthy retry reuses exact backup and commits once")
func invalid_case(source: Dictionary, bad: String) -> void:
	var invalid: Dictionary = source.duplicate(true)
	match bad:
		"target": invalid.talents.allocated.append("11455"); invalid.talents.normal_points -= 1
		"points": invalid.talents.normal_points += 1
		"items": invalid.items.clear()
		"journey": invalid.journey.best_tiers.erase("ruins_garden")
		"future": invalid.version = Rules.VERSION+1
	check(Inoculation.migrate_v58(invalid,func(_v):return "").is_empty(),"Callback cannot bypass complete frozen58 validator: "+bad)
	var path := "user://ci-invalid-"+bad+".json"
	var bytes := JSON.stringify(invalid).to_utf8_buffer(); write(path,bytes)
	var store := Store.new(); var before: Dictionary = store.snapshot()
	check(not store.load_build(path) and store.snapshot() == before and store.save_attempts == 0 and FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(path+".v58-backup.json"),"Illegal old/future file protected before backup/write/publish: "+bad)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-ci-"): quit(78); return
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CAPTURE+"schema58-oracle.json"))
	for name: String in ["town","active"]:
		var path := CAPTURE+"schema58-"+name+".json"
		check(FileAccess.get_sha256(path) == oracle[name+"_sha256"],"Immutable pre-edit58 production sample: "+name)
		var source: Dictionary = Rules.decode_v58(JSON.parse_string(FileAccess.get_file_as_string(path)))
		check(not source.is_empty() and Rules.reason_v58(source).is_empty(),"Complete frozen58 native validation and decode: "+name)
		var original := var_to_bytes(source)
		seed(5958); var control := randi(); seed(5958)
		var migrated: Dictionary = Inoculation.migrate_v58(source)
		check(migrated == expected(source,59) and var_to_bytes(source) == original and randi() == control,"Pure migration changes only version, preserving source/RNG: "+name)
		for field: String in Rules.FIELDS:
			if field != "version": check(migrated[field] == source[field],"Exact canonical field preserved %s/%s" % [name,field])
		check(JSON.parse_string(JSON.stringify(Game._stats_for(source),"",true,true)) == oracle.stats and JSON.parse_string(JSON.stringify(Game._stats_for(migrated),"",true,true)) == oracle.stats,"Inactive old/current stats exactly match captured58 oracle: "+name)
		success_case(source,58)
		if name == "active":
			for failure: String in ["backup","collision","external","atomic"]: failure_case(source,failure)
			for bad: String in ["target","points","items","journey","future"]: invalid_case(source,bad)
	var old57: Dictionary = Rules.decode_v57(JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/iron-will/schema57-town.json")))
	var intermediate: Dictionary = WillStep.migrate_v57(old57)
	check(intermediate.version == 58 and Rules.reason_v58(intermediate).is_empty() and intermediate == expected(old57,58),"Existing57→58 step remains frozen58, never jumps to59")
	success_case(old57,57)
	check(Rules.equipment_vocabulary_for_save_version(58) == 51 and Rules.equipment_vocabulary_for_save_version(59) == 51,"No equipment vocabulary change")
	var output := FileAccess.open(OS.get_environment("CI_REPORT"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"failed_labels":failures,"evidence":evidence},"\t")+"\n")
	print("CHAOS_INOCULATION_MIGRATION checks=%d failures=%d" % [checks,failures.size()]); quit(1 if not failures.is_empty() else 0)
