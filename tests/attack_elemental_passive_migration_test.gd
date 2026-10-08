extends SceneTree
## Narrow54→55 boundary plus the existing53→54 chain; no changed save fields.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Migration = preload("res://scripts/save/attack_elemental_passive_migration.gd")
const Prior = preload("res://scripts/save/ruins_garden_migration.gd")
const FIXTURE := "res://docs/qa/v115-native-map-entry/earned-v114-save.json"
var checks := 0
var failures: Array[String] = []
class BackupFailIO extends Store.Legacy:
	func _backup_legacy_save(_path: String) -> Error: return ERR_CANT_CREATE
class ExternalIO extends Store.Legacy:
	func _backup_legacy_save(path: String) -> Error:
		var result := super._backup_legacy_save(path)
		if result == OK:
			var file := FileAccess.open(path,FileAccess.WRITE)
			file.store_string("external writer")
		return result
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes)
func expected(source: Dictionary, version: int = 55) -> Dictionary:
	var copy: Dictionary = source.duplicate(true)
	copy.version = version
	return copy
func success_case(source: Dictionary, version: int) -> void:
	var path := "user://upgrade-%d.json" % version
	var bytes: PackedByteArray = (JSON.stringify(source,"  ",false,true)+"\n").to_utf8_buffer()
	write(path,bytes)
	var game := Game.new()
	var events := [0]
	game.changed.connect(func():events[0] += 1)
	var wanted: Dictionary = expected(source if version == 54 else Prior.migrate_v53(source),Rules.VERSION)
	check(game.load_build(path) and game.snapshot() == wanted,"Actual%d load publishes exact current state" % version)
	check(game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1,"Migration commits exactly once")
	check(FileAccess.get_file_as_bytes(path+".v%d-backup.json" % version) == bytes,"Original bytes backed up before mutation")
	check(game.migrated_from_legacy,"Explicit migration notice")
	if version == 54: check(game.migration_message.contains("攻击技能造成的元素伤害提高12%") and game.migration_message.contains("不额外赠物或赠点"),"Migration notice names the actual narrow effect")
	if version == 53: check(not FileAccess.file_exists(path+".v54-backup.json"),"Chained53 upgrade creates no intermediate54 backup")
	var saved: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var reopened := Game.new()
	check(reopened.load_build(path) and reopened.snapshot() == wanted and reopened.save_attempts == 0 and not reopened.migrated_from_legacy,"Independent55 reopen performs no migration/write")
	check(game.load_build(path) and game.save_attempts == 1 and events[0] == 2 and FileAccess.get_file_as_bytes(path) == saved,"Repeat load keeps exact committed bytes")
func failure_case(source: Dictionary, failure: String) -> void:
	var path := "user://failure-"+failure+".json"
	var bytes: PackedByteArray = JSON.stringify(source,"\t",true,true).to_utf8_buffer()
	write(path,bytes)
	var store := Store.new()
	var before: Dictionary = store.snapshot()
	var events := [0]
	store.changed.connect(func(): events[0] += 1)
	if failure == "backup": store._io = BackupFailIO.new()
	if failure == "external": store._io = ExternalIO.new()
	if failure == "collision": write(path+".v54-backup.json","existing backup".to_utf8_buffer())
	if failure == "atomic": check(DirAccess.make_dir_absolute(path+".tmp") == OK,"Inject atomic migration failure")
	check(not store.load_build(path) and store.snapshot() == before and events[0] == 0 and store.successful_saves == 0,"Failed upgrade leaves live state unchanged: "+failure)
	check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes),"Upgrade preserves original or concurrent writer bytes: "+failure)
	check(store.save_attempts == (1 if failure == "atomic" else 0),"Backup/concurrency precede final write: "+failure)
	if failure in ["external","atomic"]: check(FileAccess.get_file_as_bytes(path+".v54-backup.json") == bytes,"Failed final commit retains original backup")
	if failure == "collision": check(FileAccess.get_file_as_string(path+".v54-backup.json") == "existing backup","Existing backup never overwritten")
	if failure == "atomic":
		check(DirAccess.remove_absolute(path+".tmp") == OK and store.load_build(path) and store.snapshot() == expected(source,Rules.VERSION) and events[0] == 1,"Fault removal permits one successful retry")
func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-attack-elemental-"): quit(78); return
	var source53: Dictionary = Rules.decode_v53(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)))
	var source: Dictionary = Prior.migrate_v53(source53)
	check(not source53.is_empty() and not source.is_empty() and source.version == 54,"Released earned53 fixture migrates to frozen54")
	check(Rules.reason_v54(source).is_empty() and Rules.decode_v54(JSON.parse_string(JSON.stringify(source))) == source,"Full frozen54 native validation and decode")
	var before: PackedByteArray = var_to_bytes(source)
	seed(5554)
	var control := randi()
	seed(5554)
	var migrated: Dictionary = Migration.migrate_v54(source)
	check(migrated == expected(source) and var_to_bytes(source) == before and randi() == control,"Pure migration changes only version, preserving source and RNG")
	check(Rules.equipment_vocabulary_for_save_version(54) == 51 and Rules.equipment_vocabulary_for_save_version(55) == 51,"Existing equipment vocabulary remains51")
	for field: String in Rules.FIELDS:
		if field != "version": check(migrated[field] == source[field],"Exact saved field retained: "+field)
	for bad: String in ["version","points","progress","items"]:
		var invalid: Dictionary = source.duplicate(true)
		match bad:
			"version": invalid.version = 55
			"points": invalid.talents.normal_points += 1
			"progress": invalid.journey.best_tiers.erase("ruins_garden")
			"items": invalid.items.clear()
		check(Migration.migrate_v54(invalid,func(_v):return "").is_empty(),"Optional callback cannot bypass frozen native validation: "+bad)
	success_case(source,54)
	success_case(source53,53)
	for failure: String in ["backup","collision","external","atomic"]: failure_case(source,failure)
	print("ATTACK_ELEMENTAL_MIGRATION checks=%d failures=%d" % [checks,failures.size()])
	quit(1 if not failures.is_empty() else 0)
