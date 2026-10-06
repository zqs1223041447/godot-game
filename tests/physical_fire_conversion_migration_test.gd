extends SceneTree
## Strict43→44 mastery migration from independently captured genuine v068 serializer bytes.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/physical_fire_conversion_migration.gd")
const Prior = preload("res://scripts/save/inward_pull_gem_migration.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
const ROUTE := ["47175","31628","9511","23881","26523","6446","10221","54396","2550","48267"]
const ROOT := "res://docs/qa/v069-migration/"
var checks := 0
var failures := 0
var evidence := {}


class FaultStore extends Store:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)


class BackupFailIO extends Store.Legacy:
	func _backup_legacy_save(_path: String) -> Error:
		return ERR_CANT_CREATE


class ExternalIO extends Store.Legacy:
	func _backup_legacy_save(path: String) -> Error:
		var result := super._backup_legacy_save(path)
		if result == OK:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string("external writer")
			file.close()
		return result


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


func write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


func current(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result.version = 44
	return result


func reject_bytes(name: String, bytes: PackedByteArray, version: int = 43) -> void:
	var path := "user://" + name + ".json"
	write(path,bytes)
	var store := Store.new()
	var before := store.snapshot()
	var events := [0]
	store.changed.connect(func(): events[0] += 1)
	check(not store.load_build(path) and store.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes, "Rejected source leaves original bytes and live state unchanged: " + name)
	check(store.save_attempts == 0 and store.successful_saves == 0 and events[0] == 0 and not FileAccess.file_exists(path + ".v%d-backup.json" % version), "Invalid input causes no backup, write or event")
	check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Rejected source cannot be overwritten by a later save")


func strict_checks(source: Dictionary) -> void:
	var calls := [0]
	var permissive := func(_value: Dictionary) -> String: calls[0] += 1; return ""
	var injected := with_conversion(source)
	if not check(Rules.reason(current(injected)).is_empty(), "Injected original mastery65020 is otherwise legal in current44"): return
	calls[0] = 0
	check(not Rules.reason_v43(injected,permissive).is_empty() and Rules.decode_v43(injected).is_empty() and Migration.migrate_v43(injected,permissive).is_empty() and calls[0] == 0, "Frozen43 rejects source65020 before any optional permissive callback")
	reject_bytes("injected43-conversion",JSON.stringify(injected).to_utf8_buffer())
	var rating_items: Array = source.items.keys().filter(func(uid: String) -> bool:
		var item: Dictionary = source.items[uid]
		return item.kind == "equipment" and item.payload.get("base_id", "") == "emberhide_vest" and item.payload.get("affixes", []).any(func(affix: Dictionary) -> bool: return affix.id == "ironhide"))
	if not check(not rating_items.is_empty(), "Frozen fixture contains a defensive rating item"): return
	var gear_uid: String = rating_items[0]
	for mutation: String in ["fractional_revision", "bool_revision", "unknown_field", "missing_journey", "invalid_journey", "bad_uid", "unknown_node", "duplicate_node", "wrong_nodes_type", "unknown_stat", "over_budget", "bad_source", "nan_revision", "nan_mastery", "fractional_roll", "unknown_affix", "missing_location", "reused_serial", "bad_binding", "bad_ledger"]:
		var bad := source.duplicate(true)
		match mutation:
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"unknown_field": bad.physical_to_fire_conversion = 0.4
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.best_tiers.sunwell_terrace = true
			"bad_uid": bad.items[gear_uid].uid = "other"
			"unknown_node": bad.talents.allocated.append("unknown"); bad.talents.normal_points -= 1
			"duplicate_node": bad.talents.allocated.append(bad.talents.allocated[0]); bad.talents.normal_points -= 1
			"wrong_nodes_type": bad.talents.allocated = {"47175":true}
			"unknown_stat": bad.talents.physical_to_fire_conversion = 0.4
			"over_budget": bad.talents.normal_points += 1
			"bad_source": bad.talents.source_version = "3.29.2"
			"nan_revision": bad.revision = NAN
			"nan_mastery": bad.talents.masteries["123"] = NAN
			"fractional_roll": bad.items[gear_uid].payload.affixes[0].value = 9.5
			"unknown_affix": bad.items[gear_uid].payload.affixes[0].id = "unrecognized_affix"
			"missing_location": bad.locations.erase(gear_uid)
			"reused_serial": bad.next_item_serial -= 1
			"bad_binding": bad.bindings[0].keycode = KEY_C
			"bad_ledger": bad.migration_ledger.normal_budget_at_migration += 1
		calls[0] = 0
		check(not Rules.reason_v43(bad,permissive).is_empty() and Rules.decode_v43(bad).is_empty() and Migration.migrate_v43(bad,permissive).is_empty() and calls[0] == 0, "Complete native frozen43 rejects before callback: " + mutation)
		if mutation == "nan_revision": bad.revision = null
		if mutation == "nan_mastery": bad.talents.masteries["123"] = null
		reject_bytes("invalid43-" + mutation,JSON.stringify(bad).to_utf8_buffer())
	for value: Variant in [null,[],true,43,"43",NAN,INF]:
		check(not Rules.reason_v43(value).is_empty() and Rules.decode_v43(value).is_empty() and Migration.migrate_v43(value).is_empty(), "Wrong envelope types fail before migration")
	reject_bytes("broken-json","{ broken43\r\n".to_utf8_buffer())
	var future := current(source)
	future.version = 45
	reject_bytes("future45",JSON.stringify(future).to_utf8_buffer(),45)
	check(Rules.decode(source).is_empty() and not Rules.reason(source).is_empty() and Rules.decode_v43(current(source)).is_empty(), "Current decoder accepts exactly44; frozen decoder accepts exactly43")
	var reject := func(_value: Dictionary) -> String: return "additional restriction"
	check(Migration.migrate_v43(source,reject).is_empty(), "Optional callbacks may add a further restriction")


func failure_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	for failure: String in ["backup", "collision", "external", "atomic"]:
		var path := "user://failure-" + failure + ".json"
		write(path,bytes)
		var store := Store.new()
		var before := store.snapshot()
		var events := [0]
		store.changed.connect(func(): events[0] += 1)
		if failure == "collision": write(path + ".v43-backup.json","retained backup".to_utf8_buffer())
		if failure == "backup": store._io = BackupFailIO.new()
		if failure == "external": store._io = ExternalIO.new()
		if failure == "atomic" and not check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Inject actual temporary-file collision"): return
		check(not store.load_build(path) and store.snapshot() == before and store.successful_saves == 0 and events[0] == 0, "Failed migration publishes nothing: " + failure)
		check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes), "Failed migration preserves original or independent writer bytes")
		check(store.save_attempts == (1 if failure == "atomic" else 0), "Backup must succeed before first commit attempt")
		if failure == "collision": check(FileAccess.get_file_as_string(path + ".v43-backup.json") == "retained backup", "Conflicting backup remains verbatim")
		if failure in ["external","atomic"]: check(FileAccess.get_file_as_bytes(path + ".v43-backup.json") == bytes, "Failed commit retains exact raw backup")
		if failure == "atomic":
			check(DirAccess.remove_absolute(path + ".tmp") == OK and store.load_build(path) and store.snapshot() == current(source) and store.successful_saves == 1 and events[0] == 1, "Identical-backup retry commits once after fault removal")
		else: check(store.save_build(path) != OK, "Failed load protects the same target from a later save")
	var accepted := current(source)
	var accepted_bytes := JSON.stringify(accepted).to_utf8_buffer()
	var accepted_path := "user://accepted44.json"
	write(accepted_path,accepted_bytes)
	var retained := FaultStore.new()
	if not check(retained.load_build(accepted_path), "Establish current44 live state and disk receipt"): return
	var failed_path := "user://failed43-replacement.json"
	write(failed_path,bytes)
	retained.fail_save = true
	check(not retained.load_build(failed_path) and retained.snapshot() == accepted and retained._path == accepted_path and retained._disk_bytes == accepted_bytes and FileAccess.get_file_as_bytes(failed_path) == bytes, "Failed old43 commit preserves prior accepted live state and disk receipt")


func with_conversion(source: Dictionary) -> Dictionary:
	var value := source.duplicate(true)
	value.progress = {"level":37,"xp":9}
	value.talents.class_id = 1
	value.talents.allocated = ROUTE.duplicate()
	value.talents.masteries = {"48267":65020}
	value.talents.normal_points = 32
	return value


func literal_checks(label: String, source: Dictionary, bytes: PackedByteArray, oracle: Dictionary) -> void:
	var expected := current(source)
	var before := var_to_bytes(source)
	seed(674344)
	var next_rng := randi()
	seed(674344)
	var migrated := Migration.migrate_v43(source)
	if not check(randi() == next_rng and migrated == expected and var_to_bytes(source) == before, "Only version changes; native fixture and global RNG untouched: " + label): return
	for field: String in Rules.FIELDS:
		if field != "version": check(migrated[field] == source[field], "Preserve native " + label + " field: " + field)
	var migrated_stats := Game._stats_for(migrated)
	var source_stats := Game._stats_for(source)
	# The frozen oracle crossed JSON. Give current stats the identical boundary;
	# native source/current stats still compare exactly before serialization.
	var serialized_stats: Dictionary = JSON.parse_string(JSON.stringify(migrated_stats,"\t",true,true))
	check(migrated_stats == source_stats and serialized_stats == oracle.stats, "Exact native source/current stats and same-JSON-boundary old oracle: " + label)
	var old_ambush: Array = source.items.values().filter(func(item: Dictionary) -> bool: return item.definition_id == "support:ambush")
	check(digest(var_to_bytes(source_stats)) == oracle.stats_sha256 and digest(var_to_bytes(migrated_stats)) == oracle.stats_sha256, "Native stats match independent old43 byte digest: "+label)
	var old_game := Game.new()
	old_game._accept_memory(source)
	var new_game := Game.new()
	new_game._accept_memory(expected)
	check(digest(var_to_bytes(old_game.get_combat_snapshot())) == oracle.snapshot_sha256 and digest(var_to_bytes(new_game.get_combat_snapshot())) == oracle.snapshot_sha256, "Native combat snapshots match independent old43 byte digest: "+label)
	check(not migrated_stats.has("physical_to_fire_conversion") and not new_game.get_combat_snapshot().has("physical_to_fire_conversion"), "Migration carries no stat or snapshot conversion gift")
	var old_pull: Array = source.items.values().filter(func(item: Dictionary) -> bool: return item.definition_id == "support:inward_pull")
	check(old_pull.size() == 2 and old_pull.all(func(item:Dictionary)->bool:return migrated.items[item.uid] == item and source.locations[item.uid] == migrated.locations[item.uid]), "Existing native43 Inward Pull ownership and equipped link stay exact")
	check(old_ambush.size() == 2 and source.locations[old_ambush[0].uid] == migrated.locations[old_ambush[0].uid] and source.locations[old_ambush[1].uid] == migrated.locations[old_ambush[1].uid], "Both native43 Ambush ownership and equipped link are preserved")
	check(migrated.items.keys() == source.items.keys() and migrated.locations.keys() == source.locations.keys() and Store.Currency.total_quantity(migrated.items).quantity == 73, "No gift, UID reorder or currency change: " + label)
	check(Migration.migrate_v43(migrated).is_empty(), "Current envelope cannot be migrated twice")
	migrated.journey.best_tiers.sunwell_terrace = 3
	check(var_to_bytes(source) == before, "Migration deep-copies nested content")
	var path := "user://native43-" + label + ".json"
	write(path, bytes)
	var game := Game.new()
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	if not check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1, "Native43 migration commits and notifies exactly once: " + label): return
	check(FileAccess.get_file_as_bytes(path + ".v43-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Exact native43 byte backup precedes atomic replacement")
	check(game.migrated_from_legacy and game.migration_message.contains("40%物理转火") and game.migration_message.contains("原字节备份") and game.migration_message.contains("不额外赠物或赠点"), "Game reports exact latest conversion migration and backup semantics")
	var disk := FileAccess.get_file_as_bytes(path)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Repeat44 load performs no rewrite")
	var reopened := Store.new()
	if not check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v43-backup.json") == bytes, "Independent44 reopen preserves every field and original backup"): return
	var payload: Dictionary = source.items[oracle.rating_item].payload
	check(reopened.item(oracle.rating_item).payload == payload and Equipment.validate_instance_for_version(payload,39), "Vocabulary39 rolls remain unchanged")
	for version: int in [37,40,41,42,43,44]: check(not Equipment.validate_instance_for_version(payload,version), "No broadened or invented equipment vocabulary " + str(version))
	check(payload.affixes.any(func(a:Dictionary)->bool:return a.id=="ironhide") and payload.affixes.any(func(a:Dictionary)->bool:return a.id=="mistweave"), "Both vocabulary39 defensive rating affixes retained")
	evidence[label] = {"native43_sha256":digest(bytes), "bytes":bytes.size(), "items":source.items.size(), "native_stats":oracle.stats}


func chain_checks() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://docs/qa/v067-migration/fixtures/v42-ir-frozen-v066.json")
	var old42 := Rules.decode_v42(JSON.parse_string(bytes.get_string_from_utf8()))
	if not check(not old42.is_empty(), "Independent native42 fixture remains valid"): return
	var frozen43 := Prior.migrate_v42(old42)
	var expected43 := old42.duplicate(true)
	expected43.version = 43
	check(frozen43 == expected43 and Rules.reason_v43(frozen43).is_empty(), "Prior Inward Pull migration remains frozen at43 and changes only version")
	var injected42 := with_conversion(old42)
	check(not Rules.reason_v42(injected42).is_empty() and Rules.decode_v42(injected42).is_empty() and Prior.migrate_v42(injected42).is_empty(), "Earlier42 cannot smuggle65020 through prior43 migration")
	reject_bytes("injected42-conversion",JSON.stringify(injected42).to_utf8_buffer(),42)
	check(Migration.migrate_v43(frozen43) == current(old42), "Exact42 to43 to44 chain retains all nonversion fields")
	var path := "user://native42-chain.json"
	write(path,bytes)
	var store := Store.new()
	check(store.load_build(path) and store.snapshot() == current(old42) and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path+".v42-backup.json") == bytes and not FileAccess.file_exists(path+".v43-backup.json"), "Actual old42 chain commits once and backs up only original42 bytes")
	var fresh := Store.new().snapshot()
	check(fresh.version == 44 and Rules.reason(fresh).is_empty() and Store.Currency.total_quantity(fresh.items).quantity == 0 and fresh.talents.allocated == ["58833"] and fresh.talents.masteries == {} and fresh.talents.normal_points == 5 and not Game._stats_for(fresh).has("physical_to_fire_conversion"), "Complete default chain reaches44 without points, currency or conversion gifts")


func current_checks(source: Dictionary) -> void:
	var candidate := current(with_conversion(source))
	var game := Game.new()
	game._accept_memory(candidate)
	var path := "user://current44-conversion.json"
	if not check(Rules.reason(candidate).is_empty() and Rules.decode(JSON.parse_string(JSON.stringify(candidate))) == candidate and game.save_build(path) == OK, "Current44 source allocation serializes with no extra fields"): return
	var reopened := Game.new()
	check(reopened.load_build(path) and reopened.snapshot() == candidate and reopened.save_attempts == 0 and not FileAccess.file_exists(path+".v43-backup.json"), "Current44 mastery reopens without migration or gifts")
	check(is_equal_approx(reopened.get_stats().get("physical_to_fire_conversion",0.0),0.4), "Current44 reopened allocation activates source40% stat")
	for field: String in ["physical_to_fire_conversion","conversion_profile","converted_components"]:
		var bad := candidate.duplicate(true)
		bad[field] = 0.4
		check(not Rules.reason(bad).is_empty() and Rules.decode(bad).is_empty(), "Runtime conversion fields cannot leak into save: "+field)
	check(reopened.refund_passive("48267",reopened.revision(),path).ok and not reopened.get_stats().has("physical_to_fire_conversion"), "Actual refund removes converted source grant and saves correctly")


func catalog_reward_checks(oracle: Dictionary) -> void:
	check(Journey.GEM_DEFINITIONS == oracle.gem_definitions and Journey.GEM_DEFINITIONS.size() == 26, "Normal reward26 vocabulary unchanged")
	for index: int in oracle.gem_milestones.size(): check(Journey.gem_definition(index+1) == oracle.gem_milestones[index], "Native old reward ordinal remains exact: "+str(index+1))
	check(Gems.definitions().size() == oracle.minimum_save_versions.size(), "Conversion adds no gem or reward definition")
	for id: String in oracle.minimum_save_versions: check(Gems.minimum_save_version(id) == int(oracle.minimum_save_versions[id]), "Every existing gem minimum save version unchanged: "+id)
	for version: int in range(1,45): check(Rules.equipment_vocabulary_for_save_version(version) == (39 if version >= 39 else 37 if version >= 37 else 34 if version >= 34 else version), "Explicit historical save-to-equipment vocabulary: "+str(version))


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v069-migration-") or not OS.get_user_data_dir().begins_with(isolation+"/"): quit(78); return
	check(Rules.VERSION == 44 and Rules.V43_VERSION == 43 and Source.CURRENT_SAVE_VERSION == 44 and Equipment.CURRENT_VOCABULARY == 39, "Source/save44 retains equipment39")
	check(Source._execution_policy(40) == 40 and Source._execution_policy(41) == 41 and Source._execution_policy(42) == 41 and Source._execution_policy(43) == 41 and Source._execution_policy(44) == 44, "Only schema44 opens new source consumer")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"fixtures/manifest.json"))
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"fixtures/v43-oracle.json"))
	check(manifest.source_commit == "094c1d758f2b92ca27d42bb5207f1496b0c89768", "Fixture captured from genuine source094c1d7")
	var source := {}
	var bytes := PackedByteArray()
	for label: String in ["zo","ir"]:
		var filename := "v43-"+label+"-native-v068.json"
		bytes = FileAccess.get_file_as_bytes(ROOT+"fixtures/"+filename)
		check(digest(bytes) == manifest.files[filename].sha256 and bytes.size() == int(manifest.files[filename].bytes), "Native43 bytes match one-time capture digest: "+label)
		source = Rules.decode_v43(JSON.parse_string(bytes.get_string_from_utf8()))
		if not check(not source.is_empty() and Rules.reason_v43(source).is_empty(), "Native43 fully validates before migration: "+label): quit(1); return
		literal_checks(label,source,bytes,oracle.fixtures[label])
	strict_checks(source)
	failure_checks(source,bytes)
	chain_checks()
	current_checks(source)
	catalog_reward_checks(oracle)
	evidence.checks = checks
	evidence.failures = failures
	var output := OS.get_environment("V069_CONVERSION_REPORT")
	if not output.is_empty(): write(output,(JSON.stringify(evidence,"\t",true,true)+"\n").to_utf8_buffer())
	print("Physical-to-fire migration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
