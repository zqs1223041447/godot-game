extends "res://tests/attack_elemental_passive_migration_test.gd"
## Reuse existing IO fault/assert helpers; execute only the complete59→60 boundary.
const Purity = preload("res://scripts/save/purity_of_flesh_migration.gd")
const PreviousStep = preload("res://scripts/save/chaos_inoculation_migration.gd")
const CAPTURE := "res://docs/qa/purity-of-flesh/"
var evidence: Array[Dictionary] = []
func check(ok: bool, label: String) -> void:
	evidence.append({"label":label,"ok":ok}); super.check(ok,label)
func expected(source: Dictionary, version: int = Rules.VERSION) -> Dictionary:
	var copy: Dictionary = source.duplicate(true); copy.version = version; return copy
func success_case(source: Dictionary, version: int) -> void:
	var path := "user://purity-upgrade-%d-%s.json" % [version,"town" if source.journey.active_run.is_empty() else "active"]
	var bytes := (JSON.stringify(source,"  ",false,true)+"\n").to_utf8_buffer(); write(path,bytes)
	var game := Game.new(); var events := [0]; game.changed.connect(func():events[0] += 1)
	var source59: Dictionary = source if version == 59 else PreviousStep.migrate_v58(source)
	var wanted: Dictionary = expected(source59)
	check(game.load_build(path) and game.snapshot() == wanted,"Actual%d load publishes only version change to current, including active journey" % version)
	check(game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1,"Complete chain saves and publishes once")
	check(FileAccess.get_file_as_bytes(path+".v%d-backup.json" % version) == bytes,"Exact original-version backup bytes")
	if version == 58: check(not FileAccess.file_exists(path+".v59-backup.json"),"58→59→60 creates no intermediate59 backup")
	if version == 59: check(game.migrated_from_legacy and game.migration_message.contains("纯净的血肉") and game.migration_message.contains("不额外赠物或赠点"),"59 notice names full new mechanism and preservation")
	var saved := FileAccess.get_file_as_bytes(path)
	var reopened := Game.new()
	check(reopened.load_build(path) and reopened.snapshot() == wanted and reopened.save_attempts == 0 and not reopened.migrated_from_legacy,"Current save reopens with no migration/write")
	check(game.load_build(path) and game.save_attempts == 1 and events[0] == 2 and FileAccess.get_file_as_bytes(path) == saved,"Repeated current load preserves committed bytes")
func failure_case(source: Dictionary, failure: String) -> void:
	var path := "user://purity-failure-"+failure+".json"
	var bytes := JSON.stringify(source,"\t",true,true).to_utf8_buffer(); write(path,bytes)
	var store := Store.new(); var before: Dictionary = store.snapshot(); var events := [0]
	store.changed.connect(func():events[0] += 1)
	if failure == "backup": store._io = BackupFailIO.new()
	if failure == "external": store._io = ExternalIO.new()
	if failure == "collision": write(path+".v59-backup.json","existing backup".to_utf8_buffer())
	if failure == "atomic": check(DirAccess.make_dir_absolute(path+".tmp") == OK,"Inject final atomic migration write fault")
	check(not store.load_build(path) and store.snapshot() == before and events[0] == 0 and store.successful_saves == 0,"Failed59 upgrade preserves unpublished memory: "+failure)
	check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes),"Preserve original/concurrent file: "+failure)
	check(store.save_attempts == (1 if failure == "atomic" else 0),"Backup/conflict checks precede final write: "+failure)
	if failure in ["external","atomic"]: check(FileAccess.get_file_as_bytes(path+".v59-backup.json") == bytes,"Final-write failure retains exact backup")
	if failure == "collision": check(FileAccess.get_file_as_string(path+".v59-backup.json") == "existing backup","Backup conflict never overwrites prior bytes")
	if failure == "atomic":
		check(DirAccess.remove_absolute(path+".tmp") == OK and store.load_build(path) and store.snapshot() == expected(source) and events[0] == 1 and store.successful_saves == 1,"Healthy retry reuses exact backup and commits once")
func invalid_case(source: Dictionary, bad: String) -> void:
	var invalid: Dictionary = source.duplicate(true)
	match bad:
		"target": invalid.talents.allocated.append("58218"); invalid.talents.normal_points -= 1
		"points": invalid.talents.normal_points += 1
		"items": invalid.items.clear()
		"journey": invalid.journey.best_tiers.erase("ruins_garden")
		"future": invalid.version = Rules.VERSION+1
	check(Purity.migrate_v59(invalid,func(_v):return "").is_empty(),"Callback cannot bypass complete frozen59 validator: "+bad)
	var path := "user://purity-invalid-"+bad+".json"
	var bytes := JSON.stringify(invalid).to_utf8_buffer(); write(path,bytes)
	var store := Store.new(); var before: Dictionary = store.snapshot()
	check(not store.load_build(path) and store.snapshot() == before and store.save_attempts == 0 and FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(path+".v59-backup.json"),"Illegal old/future file protected before backup/write/publish: "+bad)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-purity-"): quit(78); return
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CAPTURE+"schema59-oracle.json"))
	for name: String in ["town","active"]:
		var path := CAPTURE+"schema59-"+name+".json"
		check(FileAccess.get_sha256(path) == oracle[name+"_sha256"],"Immutable pre-edit59 production sample: "+name)
		var source: Dictionary = Rules.decode_v59(JSON.parse_string(FileAccess.get_file_as_string(path)))
		check(not source.is_empty() and Rules.reason_v59(source).is_empty(),"Complete frozen59 native validation and decode: "+name)
		var original := var_to_bytes(source)
		seed(6059); var control := randi(); seed(6059)
		var migrated: Dictionary = Purity.migrate_v59(source)
		check(migrated == expected(source,60) and var_to_bytes(source) == original and randi() == control,"Pure migration changes only version, preserving source/RNG: "+name)
		for field: String in Rules.FIELDS:
			if field != "version": check(migrated[field] == source[field],"Exact canonical field preserved %s/%s" % [name,field])
		check(JSON.parse_string(JSON.stringify(Game._stats_for(source),"",true,true)) == oracle.stats and JSON.parse_string(JSON.stringify(Game._stats_for(migrated),"",true,true)) == oracle.stats,"Inactive old/current stats exactly match captured59 oracle: "+name)
		success_case(source,59)
		if name == "active":
			for failure: String in ["backup","collision","external","atomic"]: failure_case(source,failure)
			for bad: String in ["target","points","items","journey","future"]: invalid_case(source,bad)
	var old58: Dictionary = Rules.decode_v58(JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/chaos-inoculation/schema58-town.json")))
	var intermediate: Dictionary = PreviousStep.migrate_v58(old58)
	check(intermediate.version == 59 and Rules.reason_v59(intermediate).is_empty() and intermediate == expected(old58,59),"Existing58→59 step remains frozen59, never jumps to60")
	success_case(old58,58)
	check(Rules.equipment_vocabulary_for_save_version(59) == 51 and Rules.equipment_vocabulary_for_save_version(60) == 51,"No equipment vocabulary change")
	var output := FileAccess.open(OS.get_environment("PURITY_MIGRATION_REPORT"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"failed_labels":failures,"evidence":evidence},"\t")+"\n")
	print("PURITY_MIGRATION checks=%d failures=%d" % [checks,failures.size()]); quit(1 if not failures.is_empty() else 0)
