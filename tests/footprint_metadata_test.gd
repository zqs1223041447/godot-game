extends SceneTree
const Items=preload("res://scripts/items/unified_item_catalog.gd")
const Catalog=preload("res://scripts/items/equipment_catalog.gd")
const Data=preload("res://scripts/game_data.gd")
const Gems=preload("res://scripts/items/gem_catalog.gd")
const Jewels=preload("res://scripts/jewel_data.gd")
const Icons=preload("res://scripts/visuals/skill_emblem.gd")
var retained_icons:Dictionary=Icons.ICONS
var checks:=0
var failures:=0

func _initialize()->void:
	var rng:=RandomNumberGenerator.new();rng.seed=230023
	var seen:= {};var examples:Array[Dictionary]=[];var serial:=1
	for pool:String in Catalog.POOL_PROFILES:
		for level:int in [1,30]:
			for rarity:String in ["normal","magic","rare"]:
				for unused:int in range(40):
					var instance:Dictionary=Catalog.generate_for_pool(rng,"gear_%06d"%serial,level,rarity,pool);serial+=1
					var wrapped:Dictionary=Items.wrap_equipment(instance)
					check(not wrapped.is_empty(),"Generated fixture is valid")
					seen[instance.base_id]=true;compare(wrapped)
					if examples.size()<10 and rarity=="rare":examples.append(wrapped)
	check(seen.size()==Catalog.all_base_ids().size(),"Every real base footprint was exercised")
	for id:String in Data.ITEMS:compare(Items.fixed_equipment("fixed_"+id,id))
	for id:String in Gems.definitions():compare(Gems.create_instance("gem_"+id.replace(":","_"),id))
	for index:int in range(20):compare(Items.wrap_jewel(Jewels.generate(rng,"jewel_%06d"%(index+1))))
	compare(Items.wrap_jewel(Jewels.generate_special("jewel_000099")))
	for quantity:int in [1,1000000000]:compare(Items.calibration_shard("currency_"+str(quantity),quantity))
	for item:Dictionary in examples:
		for change:String in ["tier","value","base","identity","family","duplicate","rarity"]:
			var invalid:=item.duplicate(true)
			match change:
				"tier":invalid.payload.affixes[0].tier=99
				"value":invalid.payload.affixes[0].value=999999
				"base":invalid.payload.base_id="unknown"
				"identity":invalid.payload.id="gear_999998"
				"family":invalid.payload.affixes[0].id="unknown"
				"duplicate":invalid.payload.affixes.append(invalid.payload.affixes[0].duplicate(true))
				"rarity":invalid.payload.rarity="normal"
			reject(invalid,change)
	var whole:=examples[0].duplicate(true);whole.payload.item_level=float(whole.payload.item_level)
	for affix:Dictionary in whole.payload.affixes:affix.tier=float(affix.tier);affix.value=float(affix.value)
	check(Items.validate_instance(whole),"Existing bounded whole-numeric equipment contract remains valid");compare(whole)
	for kind:String in ["gem","currency"]:
		var item:=Gems.create_instance("payload_type","skill:bolt") if kind=="gem" else Items.calibration_shard("payload_type",1)
		for value:Variant in [1.0,true,"1",-1,null]:
			var invalid:=item.duplicate(true);invalid.payload["level" if kind=="gem" else "quantity"]=value;reject(invalid,"strict payload type")
	var valid:=Gems.create_instance("stable_uid","support:focus")
	for value:Variant in [null,{},[],true,42,"bad"]:reject(value,"wrapper type")
	for bad_uid:String in [" padded", "control\n", "x".repeat(129)]:
		var invalid:=valid.duplicate(true);invalid.uid=bad_uid;reject(invalid,"UID boundary")
	check(Items.metadata_for_items({"wrong_key":valid}).is_empty(),"Registry key must match exact UID")
	check(Items.metadata_for_items({3:valid}).is_empty(),"Registry keys cannot coerce integers")
	var bulk:Dictionary={valid.uid:valid,"stack":Items.calibration_shard("stack",42)}
	var before:=var_to_bytes(bulk);seed(230023);var next:=randi();seed(230023)
	var metadata:=Items.metadata_for_items(bulk)
	check(randi()==next and var_to_bytes(bulk)==before,"Metadata preserves RNG and all input bytes")
	metadata[valid.uid].size[0]=100;metadata[valid.uid].category="changed"
	check(Items.metadata_for_items(bulk)[valid.uid]=={"kind":"support_gem","category":"","size":[1,1]},"Output arrays/dictionaries are detached")
	bulk.bad={"uid":"bad"}
	check(Items.metadata_for_items(bulk).is_empty(),"One invalid payload clears the entire metadata result")
	print("Footprint metadata: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func compare(item:Dictionary)->void:
	var definition:Dictionary=Items.definition_for_instance(item)
	check(not definition.is_empty(),"Existing full definition accepts fixture")
	var size:Variant=definition.size
	var expected:Dictionary={"kind":item.kind,"category":str(definition.category),"size":[int(size.x),int(size.y)] if size is Vector2i else [int(size[0]),int(size[1])]}
	check(Items.metadata_for_instance(item)==expected,"Public footprint matches unchanged full definition")
	check(Items.metadata_for_items({item.uid:item})=={item.uid:expected},"Bulk footprint matches unchanged full definition")

func reject(value:Variant,label:String)->void:
	check(not Items.validate_instance(value),"Fixture rejected by original validator: "+label)
	check(Items.metadata_for_instance(value).is_empty(),"Malformed input has no usable footprint: "+label)
	if value is Dictionary and value.get("uid") is String:
		check(Items.metadata_for_items({value.uid:value}).is_empty(),"Malformed bulk input rejected: "+label)

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
