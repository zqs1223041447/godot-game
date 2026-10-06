extends SceneTree
## Strict38→39 migration from independent frozen-v061 serializer bytes.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/defense_rating_affix_migration.gd")
const Prior = preload("res://scripts/save/resolute_technique_migration.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const ROOT := "res://docs/qa/v062-migration/"
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


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


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
	result.version = 39
	return result


func reject_bytes(name: String, bytes: PackedByteArray, version: int = 38) -> void:
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
	for family: String in ["ironhide", "mistweave"]:
		var injected := with_rating_gear(source, [family])
		check(Rules.reason(current(injected)).is_empty(), "New gear family is otherwise legal in schema39: " + family)
		Store.Items.metadata_for_items(injected.items)
		calls[0] = 0
		check(not Rules.reason_v38(injected,permissive).is_empty() and Rules.decode_v38(injected).is_empty() and Migration.migrate_v38(injected,permissive).is_empty() and calls[0] == 0, "Frozen38 rejects new gear before callback, including a warmed current metadata cache")
		reject_bytes("injected38-" + family,JSON.stringify(injected).to_utf8_buffer())
	var gear_uid := "gear_%06d" % (int(source.next_item_serial)-1)
	for mutation: String in ["fractional_revision", "bool_revision", "unknown_field", "missing_journey", "invalid_journey", "bad_uid", "unknown_node", "duplicate_node", "wrong_nodes_type", "unknown_stat", "over_budget", "bad_source", "nan_revision", "nan_mastery", "fractional_roll", "unknown_affix", "missing_location", "reused_serial", "bad_binding", "bad_ledger"]:
		var bad := source.duplicate(true)
		match mutation:
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"unknown_field": bad.resolute_technique = 1.0
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.best_tiers.sunwell_terrace = true
			"bad_uid": bad.items[gear_uid].uid = "other"
			"unknown_node": bad.talents.allocated.append("unknown"); bad.talents.normal_points -= 1
			"duplicate_node": bad.talents.allocated.append(bad.talents.allocated[0]); bad.talents.normal_points -= 1
			"wrong_nodes_type": bad.talents.allocated = {"47175":true}
			"unknown_stat": bad.talents.resolute_technique = 1.0
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
		check(not Rules.reason_v38(bad,permissive).is_empty() and Rules.decode_v38(bad).is_empty() and Migration.migrate_v38(bad,permissive).is_empty() and calls[0] == 0, "Complete native frozen38 rejects before callback: " + mutation)
		if mutation == "nan_revision": bad.revision = null
		if mutation == "nan_mastery": bad.talents.masteries["123"] = null
		reject_bytes("invalid38-" + mutation,JSON.stringify(bad).to_utf8_buffer())
	for value: Variant in [null,[],true,38,"38",NAN,INF]:
		check(not Rules.reason_v38(value).is_empty() and Rules.decode_v38(value).is_empty() and Migration.migrate_v38(value).is_empty(), "Wrong envelope types fail before migration")
	reject_bytes("broken-json","{ broken38\r\n".to_utf8_buffer())
	var future := current(source)
	future.version = 40
	reject_bytes("future40",JSON.stringify(future).to_utf8_buffer(),40)
	check(Rules.decode(source).is_empty() and not Rules.reason(source).is_empty() and Rules.decode_v38(current(source)).is_empty(), "Current decoder accepts exactly39; frozen decoder accepts exactly38")
	var reject := func(_value: Dictionary) -> String: return "additional restriction"
	check(Migration.migrate_v38(source,reject).is_empty(), "Optional callbacks may add a further restriction")


func literal_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	var expected := current(source)
	var before := var_to_bytes(source)
	seed(613839)
	var next_rng := randi()
	seed(613839)
	var migrated := Migration.migrate_v38(source)
	check(randi() == next_rng and migrated == expected and var_to_bytes(source) == before, "Migration changes only version; source and global RNG stay untouched")
	for field: String in Rules.FIELDS:
		if field != "version": check(migrated[field] == source[field], "Every nonversion field retains identity and content: " + field)
	check(Game._stats_for(migrated) == Game._stats_for(source) and Game._stats_for(migrated).resolute_technique == 1.0, "Existing allocated Resolute Technique and full stats survive unchanged")
	check(migrated.items.keys() == source.items.keys() and migrated.locations.keys() == source.locations.keys() and Store.Currency.total_quantity(migrated.items) == Store.Currency.total_quantity(source.items), "Items, UID order, locations and currency are preserved")
	check(Migration.migrate_v38(migrated).is_empty(), "Already migrated envelope is not migrated twice")
	migrated.journey.best_tiers.sunwell_terrace = 3
	check(var_to_bytes(source) == before, "Migrated nested journey is deeply detached")
	var path := "user://frozen-v061-native38.json"
	write(path,bytes)
	var game := Game.new()
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1, "Native old38 loads with one atomic commit and notification")
	check(FileAccess.get_file_as_bytes(path + ".v38-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Old38 bytes are backed up verbatim before atomic replacement")
	check(game.migrated_from_legacy and game.migration_message.contains("护甲") and game.migration_message.contains("闪避值"), "Migration message names the newly available defense prefixes")
	var disk := FileAccess.get_file_as_bytes(path)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Repeated39 load performs no migration or rewrite")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v38-backup.json") == bytes, "Independent39 reopen preserves migrated fields and original-byte backup")
	var dual_uid := "gear_%06d" % (int(source.next_item_serial)-1)
	var payload: Dictionary = source.items[dual_uid].payload
	check(payload.affixes.any(func(affix:Dictionary)->bool:return affix.id=="rimeward") and payload.affixes.any(func(affix:Dictionary)->bool:return affix.id=="stormward") and reopened.item(dual_uid).payload == payload, "Both vocabulary37 elemental suffixes survive39 without reroll or vocabulary regression")
	check(Equipment.validate_instance_for_version(payload,37) and not Equipment.validate_instance_for_version(payload,34), "Fixture genuinely includes equipment unavailable to vocabulary34")
	evidence.schema38_sha256 = digest(bytes)
	evidence.schema38_bytes = bytes.size()
	evidence.preserved_items = source.items.size()
	evidence.preserved_dual_suffix_item = payload


func failure_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	for failure: String in ["backup", "collision", "external", "atomic"]:
		var path := "user://failure-" + failure + ".json"
		write(path,bytes)
		var store := Store.new()
		var before := store.snapshot()
		var events := [0]
		store.changed.connect(func(): events[0] += 1)
		if failure == "collision": write(path + ".v38-backup.json","retained backup".to_utf8_buffer())
		if failure == "backup": store._io = BackupFailIO.new()
		if failure == "external": store._io = ExternalIO.new()
		if failure == "atomic": check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Inject actual temporary-file collision")
		check(not store.load_build(path) and store.snapshot() == before and store.successful_saves == 0 and events[0] == 0, "Failed migration publishes nothing: " + failure)
		check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes), "Failed migration preserves original or independent writer bytes")
		check(store.save_attempts == (1 if failure == "atomic" else 0), "Backup must succeed before first commit attempt")
		if failure == "collision": check(FileAccess.get_file_as_string(path + ".v38-backup.json") == "retained backup", "Conflicting backup remains verbatim")
		if failure in ["external","atomic"]: check(FileAccess.get_file_as_bytes(path + ".v38-backup.json") == bytes, "Failed commit retains exact raw backup")
		if failure == "atomic":
			check(DirAccess.remove_absolute(path + ".tmp") == OK and store.load_build(path) and store.snapshot() == current(source) and store.successful_saves == 1 and events[0] == 1, "Identical-backup retry commits once after fault removal")
		else: check(store.save_build(path) != OK, "Failed load protects the same target from a later save")
	var accepted := current(source)
	var accepted_bytes := JSON.stringify(accepted).to_utf8_buffer()
	var accepted_path := "user://accepted39.json"
	write(accepted_path,accepted_bytes)
	var retained := FaultStore.new()
	check(retained.load_build(accepted_path), "Establish current39 live state and disk receipt")
	var failed_path := "user://failed38-replacement.json"
	write(failed_path,bytes)
	retained.fail_save = true
	check(not retained.load_build(failed_path) and retained.snapshot() == accepted and retained._path == accepted_path and retained._disk_bytes == accepted_bytes and FileAccess.get_file_as_bytes(failed_path) == bytes, "Failed old38 commit preserves prior accepted live state and disk receipt")


func chain_checks() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://docs/qa/v061-source/fixtures/v37-frozen-v060.json")
	var old37 := Rules.decode_v37(JSON.parse_string(bytes.get_string_from_utf8()))
	var frozen38 := Prior.migrate_v37(old37)
	var expected38 := old37.duplicate(true)
	expected38.version = 38
	check(not old37.is_empty() and frozen38 == expected38 and Rules.reason_v38(frozen38).is_empty(), "Prior37 to38 still stops at frozen38 and changes only version")
	check(Migration.migrate_v38(frozen38) == current(old37), "Frozen37 to38 to39 preserves every nonversion field")
	for version: int in [34,35,36,37]:
		var fixtures := {34:"res://docs/qa/v056/fixtures/v34-default.json",35:"res://docs/qa/v059-source/fixtures/v35-released.json",36:"res://docs/qa/v060-migration/fixtures/v36-released.json",37:"res://docs/qa/v061-source/fixtures/v37-frozen-v060.json"}
		var old_bytes := FileAccess.get_file_as_bytes(fixtures[version])
		var decoded := Rules._decode(JSON.parse_string(old_bytes.get_string_from_utf8()),true,version,true)
		var path := "user://released%d-chain.json" % version
		write(path,old_bytes)
		var previous := Store.new()
		check(previous.load_build(path) and previous.snapshot() == current(decoded) and previous.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v%d-backup.json" % version) == old_bytes and not FileAccess.file_exists(path + ".v38-backup.json"), "Released earlier schema reaches39 with exact original fields and one original-byte backup: %d" % version)
	var legacy := Store.Legacy.new()._snapshot()
	var legacy_bytes := JSON.stringify(legacy).to_utf8_buffer()
	var path := "user://legacy-complete-chain.json"
	write(path,legacy_bytes)
	var full := Store.new()
	check(full.load_build(path) and full.snapshot().version == 39 and Rules.reason(full.snapshot()).is_empty() and full.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v%d-backup.json" % int(legacy.version)) == legacy_bytes, "Built-in legacy chain reaches39 with one atomic save and original backup")
	var fresh := Store.new().snapshot()
	check(fresh.version == 39 and Rules.reason(fresh).is_empty() and Store.Currency.total_quantity(fresh.items).quantity == 0 and Game._stats_for(fresh).resolute_technique == 0.0, "Fresh default chain reaches39 without currency or keystone gifts")
	for gear: Dictionary in old37.items.values():
		if gear.kind != "equipment" or gear.payload.is_empty(): continue
		check(Equipment.validate_instance_for_version(gear.payload,37) and not Equipment.validate_instance_for_version(gear.payload,38), "Direct equipment vocabulary38 remains historically invalid")
	check(Rules.reason_v37(old37).is_empty() and Rules.decode_v37(JSON.parse_string(JSON.stringify(old37))) == old37 and Rules.decode_v38(JSON.parse_string(JSON.stringify(frozen38))) == frozen38, "Schemas37 and38 both retain vocabulary37 across mixed released pools")
	for family: String in ["ironhide", "mistweave"]:
		var bad37 := with_rating_gear(old37,[family])
		var permissive := func(_value: Dictionary) -> String: return ""
		check(not Rules.reason_v37(bad37,permissive).is_empty() and Rules.decode_v37(bad37).is_empty() and Prior.migrate_v37(bad37,permissive).is_empty(), "Frozen37 rejects new rating gear despite permissive callbacks")
		reject_bytes("injected37-"+family,JSON.stringify(bad37).to_utf8_buffer(),37)


func with_rating_gear(source: Dictionary, families: Array) -> Dictionary:
	var result := source.duplicate(true)
	var affixes := []
	for family: String in families:
		var tier: Dictionary = Equipment._affix_record(family).tiers[2]
		affixes.append({"id":family,"tier":3,"value":int(tier.max)})
	var gear := {"id":"gear_%06d" % int(result.next_item_serial),"base_id":"emberhide_vest","rarity":"magic" if families.size()==1 else "rare","item_level":16,"affixes":affixes}
	var index := 0
	for location: Dictionary in result.locations.values():
		if location.kind == "recovery": index += 1
	result.items[gear.id] = Store.Items.wrap_equipment(gear)
	result.locations[gear.id] = {"kind":"recovery","index":index}
	result.next_item_serial += 1
	return result


func current_checks(source: Dictionary) -> void:
	var candidate := current(with_rating_gear(source,["ironhide","mistweave","rimeward","stormward"]))
	var uid := "gear_%06d" % (int(candidate.next_item_serial)-1)
	var store := Store.new()
	store._accept_memory(candidate)
	var path := "user://current39-dual-ratings.json"
	check(Rules.reason(candidate).is_empty() and Rules.decode(JSON.parse_string(JSON.stringify(candidate))) == candidate and store.save_build(path) == OK, "Current39 new rating prefixes serialize under the full canonical envelope")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == candidate and reopened.save_attempts == 0 and not FileAccess.file_exists(path+".v38-backup.json"), "Current39 reopens without migration or reroll")
	var destination := reopened.first_bag_position(uid)
	check(not destination.is_empty(), "New rating item has a real bag destination")
	var bytes := FileAccess.get_file_as_bytes(path)
	var events := [0]
	reopened.changed.connect(func(): events[0] += 1)
	check(DirAccess.make_dir_absolute(path+".tmp") == OK, "Inject actual transaction save fault")
	check(not reopened.move_item(uid,destination,reopened.revision(),path).ok and reopened.snapshot() == candidate and reopened._disk_bytes == bytes and FileAccess.get_file_as_bytes(path) == bytes and events[0] == 0, "Failed new-item transaction preserves rolls, IDs, points, currency, locations and receipt")
	check(DirAccess.remove_absolute(path+".tmp") == OK and reopened.move_item(uid,destination,reopened.revision(),path).ok and reopened.revision() == candidate.revision+1 and events[0] == 1, "New-item transaction commits once after fault removal")
	var committed := reopened.snapshot()
	bytes = FileAccess.get_file_as_bytes(path)
	write(path,"external after commit".to_utf8_buffer())
	check(reopened.save_build(path) == ERR_FILE_ALREADY_IN_USE and reopened.snapshot() == committed and reopened._disk_bytes == bytes and FileAccess.get_file_as_string(path) == "external after commit", "New-item save receipt protects subsequent external edits")
	evidence.current39_payload = candidate.items[uid].payload


func source_checks() -> void:
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"fixtures/v38-vocabulary-oracle.json"))
	var full_nodes := {}
	var full_masteries := {}
	for id: String in Source.Data.standard_ids():
		var effect := Source.node_effect(id,0,39)
		check(effect == Source.node_effect(id,0,38), "Every source node retains the exact released38 policy: "+id)
		if effect.status == "full": full_nodes[id] = effect.grants
		for mastery: Dictionary in Source.Data.node(id).mastery_effects:
			var selected := Source.node_effect(id,int(mastery.effect),39)
			check(selected == Source.node_effect(id,int(mastery.effect),38), "Every mastery retains the exact released38 policy")
			if selected.status == "full": full_masteries[id+":"+str(int(mastery.effect))] = selected.grants
	check(full_nodes == oracle.full_nodes and full_masteries == oracle.full_masteries, "Full executable source vocabulary and grants match independently captured released v61 oracle")
	check(Source.CURRENT_SAVE_VERSION == 38 and Source._execution_policy(38) == 38 and Source._execution_policy(39) == 38, "Equipment schema39 does not open another source policy")
	evidence.source_policy = 38
	evidence.full_source_nodes = full_nodes.size()
	evidence.full_source_masteries = full_masteries.size()


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v062-migration-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	check(Rules.VERSION == 39 and Rules.V38_VERSION == 38 and Source.CURRENT_SAVE_VERSION == 38 and Equipment.CURRENT_VOCABULARY == 39, "Save39 opens equipment39 while source policy remains38")
	for version: int in range(1,40):
		check(Rules.equipment_vocabulary_for_save_version(version) == (39 if version >= 39 else 37 if version >= 37 else 34 if version >= 34 else version), "Explicit save-to-equipment vocabulary mapping has no38 regression")
	var bytes := FileAccess.get_file_as_bytes(ROOT + "fixtures/v38-frozen-v061.json")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "fixtures/manifest.json"))
	check(digest(bytes) == manifest.sha256 and bytes.size() == int(manifest.bytes), "Independent frozen-v061 native serializer fixture matches recorded bytes")
	var source := Rules.decode_v38(JSON.parse_string(bytes.get_string_from_utf8()))
	check(not source.is_empty() and Rules.reason_v38(source).is_empty(), "Full schema38 fixture validates before any migration")
	if source.is_empty():
		quit(1)
		return
	strict_checks(source)
	literal_checks(source,bytes)
	failure_checks(source,bytes)
	chain_checks()
	current_checks(source)
	source_checks()
	evidence.checks = checks
	evidence.failures = failures
	var output := OS.get_environment("V062_MIGRATION_REPORT")
	if not output.is_empty(): write(output,(JSON.stringify(evidence,"\t",true,true)+"\n").to_utf8_buffer())
	print("Defense rating migration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
