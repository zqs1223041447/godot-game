extends SceneTree
## Historical non-shipped gem candidate. Its checks are not final v51 acceptance.
## Differential public-boundary checks against frozen v051 pre-change catalogs.
## No arena, user state, persistence, inventory mutation, or rendering.
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const BeforeGems = preload("res://tests/fixtures/v051/gem_catalog_before.gd")
const BeforeItems = preload("res://tests/fixtures/v051/unified_item_catalog_before.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Flasks = preload("res://scripts/items/flask_catalog.gd")
const Data = preload("res://scripts/game_data.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")

var checks := 0
var cases := 0
var failures: Array[String] = []
var held_definitions: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: return
	failures.append(label)
	push_error("GEM_PROJECTION_REUSE_FAIL " + label)

func typed(value: Variant) -> Variant:
	if value is Resource:
		return [typeof(value), value.get_class(), value.resource_path]
	if value is Dictionary:
		var rows: Array = []
		for key: Variant in value: rows.append([typed(key),typed(value[key])])
		return [TYPE_DICTIONARY,rows]
	if value is Array:
		var rows: Array = []
		for entry: Variant in value: rows.append(typed(entry))
		return [TYPE_ARRAY,rows]
	return [typeof(value),value]

func same(actual: Variant, expected: Variant, label: String) -> void:
	check(var_to_bytes(typed(actual)) == var_to_bytes(typed(expected)),label)

func compare_case(value: Variant, label: String, valid_item := false) -> void:
	cases += 1
	var before := var_to_bytes(typed(value))
	check(Gems.validate_instance(value) == BeforeGems.validate_instance(value),label+" Gem validation")
	same(Gems.metadata_for_instance(value),BeforeGems.metadata_for_instance(value),label+" Gem metadata typed output")
	check(Items.validate_instance(value) == BeforeItems.validate_instance(value),label+" Item validation")
	var expected := BeforeItems.definition_for_instance(value)
	var actual := Items.definition_for_instance(value)
	same(actual,expected,label+" Item definition typed output")
	if valid_item: check(not actual.is_empty(),label+" fixture is valid")
	if actual.has("icon_texture"):
		check(actual.icon_texture is Texture2D and expected.icon_texture is Texture2D,label+" Texture2D retained")
		check(actual.icon_texture == expected.icon_texture,label+" resource references retain loader identity")
		check(actual.icon_texture.resource_path == actual.icon,label+" actual texture uses original icon path")
	if valid_item:
		mutate_containers(actual)
		same(Items.definition_for_instance(value),expected,label+" all returned containers detached")
	check(var_to_bytes(typed(value)) == before,label+" input unchanged")

func mutate_containers(value: Variant) -> void:
	if value is Dictionary:
		for child: Variant in value.values(): mutate_containers(child)
		value.clear()
	elif value is Array:
		for child: Variant in value: mutate_containers(child)
		value.clear()

func changed(base: Dictionary, field: String, value: Variant) -> Dictionary:
	var result := base.duplicate(true)
	result[field] = value
	return result

func _malformed_cases(base: Dictionary) -> void:
	for value: Variant in [null,true,false,0,1.0,"gem",&"gem",[],{},Vector2i.ONE]:
		compare_case(value,"outer "+str(value))
	for field: String in ["uid","kind","definition_id","payload"]:
		var missing := base.duplicate(true)
		missing.erase(field)
		compare_case(missing,"missing "+field)
		for value: Variant in [null,true,0,1.0,[],{}]:
			compare_case(changed(base,field,value),"wrong type "+field+" "+str(value))
	compare_case(changed(base,"extra",1),"extra wrapper field")
	for uid: Variant in [""," "," leading","trailing ","inner\ttab","line\nfeed","bad"+String.chr(127),"x".repeat(129),&"string_name_uid"]:
		compare_case(changed(base,"uid",uid),"invalid UID "+str(uid))
	for uid: String in ["x","x".repeat(128),"gem:宝石-01","inside space"]:
		compare_case(changed(base,"uid",uid),"valid UID "+uid,true)
	for kind: Variant in ["support_gem","equipment","jewel","currency","flask","unknown",&"skill_gem"]:
		compare_case(changed(base,"kind",kind),"kind "+str(kind))
	for id: Variant in ["bolt","skill:unknown","support:unknown","skill:","support:",&"skill:bolt"]:
		compare_case(changed(base,"definition_id",id),"definition "+str(id))
	for field: String in ["level","quality"]:
		for value: Variant in [null,true,false,0.0,1.0,1.5,-1,2,"1",&"1",[],{},INF,NAN]:
			var instance := base.duplicate(true)
			instance.payload[field] = value
			compare_case(instance,"payload "+field+" "+str(value))
		var missing := base.duplicate(true)
		missing.payload.erase(field)
		compare_case(missing,"missing payload "+field)
	var extra := base.duplicate(true)
	extra.payload.extra = 0
	compare_case(extra,"extra payload field")
	var string_name_wrapper := {}
	for key: String in base: string_name_wrapper[StringName(key)] = base[key]
	compare_case(string_name_wrapper,"StringName wrapper keys")
	check(not Items.validate_instance(string_name_wrapper) and Items.definition_for_instance(string_name_wrapper).is_empty(),"strict Item wrapper String keys retained")
	var string_name_payload := base.duplicate(true)
	string_name_payload.payload = {&"level":1,&"quality":0}
	compare_case(string_name_payload,"StringName payload keys retain previous Gem semantics")
	var numeric_key := base.duplicate(true)
	numeric_key.erase("kind")
	numeric_key[42] = "skill_gem"
	compare_case(numeric_key,"numeric wrapper key")

func _copies_and_live_membership() -> void:
	for id: String in held_definitions:
		var instance := Gems.create_instance("copy:"+id,id)
		var gem_before := BeforeGems.metadata_for_instance(instance)
		var item_before := BeforeItems.definition_for_instance(instance)
		var gem := Gems.metadata_for_instance(instance)
		var item := Items.definition_for_instance(instance)
		for field: String in ["capabilities","requires","skills","size"]:
			gem[field].append("mutated gem")
			item[field].append("mutated item")
		gem.uid = "mutated"
		item.category = "mutated"
		gem.extra = {"nested":[1]}
		item.extra = {"nested":[2]}
		same(Gems.metadata_for_instance(instance),gem_before,id+" Gem returned arrays/dictionary detached")
		same(Items.definition_for_instance(instance),item_before,id+" Item returned arrays/dictionary detached")
		if id.begins_with("support:"):
			var support_id := id.trim_prefix("support:")
			var source: Variant = Supports.SUPPORTS[support_id]
			Supports.SUPPORTS.erase(support_id)
			compare_case(instance,id+" source removed")
			var removed_rejected := not Gems.validate_instance(instance) and Gems.metadata_for_instance(instance).is_empty() \
				and not Items.validate_instance(instance) and Items.definition_for_instance(instance).is_empty()
			Supports.SUPPORTS[support_id] = source
			check(removed_rejected,id+" deletion immediately invalidates all boundaries")
			compare_case(instance,id+" source restored",true)
			same(Items.definition_for_instance(instance),item_before,id+" restoration immediately restores metadata")
	Supports.SUPPORTS["qa_unknown_source"] = {"name":"not a provider"}
	var unknown := {"uid":"unknown","kind":"support_gem","definition_id":"support:qa_unknown_source","payload":{"level":1,"quality":0}}
	compare_case(unknown,"registry member without source provider")
	var rejected := Items.definition_for_instance(unknown).is_empty()
	Supports.SUPPORTS.erase("qa_unknown_source")
	check(rejected,"registry membership alone cannot invent source metadata")

func _non_gem_paths() -> void:
	for id: String in Data.ITEMS:
		compare_case(Items.fixed_equipment(id,id),"fixed equipment "+id,true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 51037
	for pool: String in Gear.pool_profiles():
		for rarity: String in ["normal","magic","rare"]:
			var instance := Items.wrap_equipment(Gear.generate_for_pool(rng,"gear_000051",30,rarity,pool))
			compare_case(instance,"rolled equipment "+pool+" "+rarity,true)
			compare_case(changed(instance,"uid","forged"),"mismatched equipment UID")
	for jewel: Dictionary in Jewels.starter_jewels().values():
		var instance := Items.wrap_jewel(jewel)
		compare_case(instance,"jewel "+jewel.id,true)
		compare_case(changed(instance,"uid","forged"),"mismatched jewel UID")
	compare_case(Items.wrap_jewel(Jewels.generate_special("jewel_000051")),"special jewel",true)
	for id: String in Flasks.DEFINITIONS:
		var instance := Flasks.create_instance("flask_test",id)
		compare_case(instance,id,true)
		compare_case(changed(instance,"payload",{"extra":1}),id+" malformed payload")
	for amount: int in [1,17,999]:
		var instance := Items.calibration_shard("currency_test",amount)
		compare_case(instance,"currency "+str(amount),true)
		compare_case(changed(instance,"payload",{"quantity":float(amount)}),"currency float")

func run() -> void:
	var data_root := OS.get_environment("XDG_DATA_HOME")
	if not data_root.begins_with("/tmp/godot-m1-v051-") or not OS.get_user_data_dir().begins_with(data_root+"/"):
		push_error("Fresh isolated v051 XDG directory required")
		quit(78)
		return
	# Pin only this test's source textures, avoiding repeated test-only decoding.
	# Production deliberately receives no persistent cache or resource owner.
	held_definitions = BeforeGems.definitions()
	seed(510051)
	var expected_rng := randi()
	seed(510051)
	for id: String in held_definitions:
		same(Gems.definition(id),BeforeGems.definition(id),id+" direct definition")
		same(Gems.create_instance("item:"+id,id),BeforeGems.create_instance("item:"+id,id),id+" instance construction")
		compare_case(Gems.create_instance("item:"+id,id),id,true)
	_malformed_cases(BeforeGems.create_instance("valid","skill:bolt"))
	_copies_and_live_membership()
	_non_gem_paths()
	check(randi() == expected_rng,"catalog projections consume no global RNG")
	same(Gems.definitions(),BeforeGems.definitions(),"complete catalog still equals frozen after mutation tests")
	var report := {"checks":checks,"cases":cases,"failures":failures,"engine":Engine.get_version_info().string,
		"scope":"Pure frozen-source differential public-boundary checks. Containers compared with recursive exact Variant types; textures compared by actual resource identity and source path. No game, save, combat, UI or render claim.",
		"exit_code":0 if failures.is_empty() else 1}
	var output := OS.get_environment("GEM_PROJECTION_REUSE_OUT")
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file == null: push_error("Cannot write test report"); quit(73); return
		file.store_string(JSON.stringify(report,"\t",true,true)); file.close()
	print("GEM_PROJECTION_REUSE_RESULT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
