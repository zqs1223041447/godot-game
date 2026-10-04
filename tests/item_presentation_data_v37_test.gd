extends SceneTree
## Model/data contract only: no GUI geometry, input injection or production mutation.
const Model=preload("res://scripts/canonical_game_state.gd")
const Presenter=preload("res://scripts/ui/unified_item_presentation.gd")
const Gear=preload("res://scripts/items/equipment_catalog.gd")
const Data=preload("res://scripts/game_data.gd")
const Gems=preload("res://scripts/items/gem_catalog.gd")
const Supports=preload("res://scripts/combat/support_registry.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Text=preload("res://scripts/passive_data.gd")
var model:RefCounted
var checks:=0
var failures:=0
var signals:=0
var fixture_rng:=RandomNumberGenerator.new()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func uid_for(definition_id:String)->String:
	for uid:String in model.snapshot().items:
		if model.item(uid).definition_id==definition_id:return uid
	return ""
func make_gear(base_id:String,rarity:String)->Dictionary:
	var pool_id:=""
	for id:String in Gear.pool_profiles():
		if Gear.pool_profiles()[id].base_ids.has(base_id):pool_id=id;break
	var uid:="gear_%06d"%int(model.snapshot().next_item_serial)
	for i:int in range(500):
		var candidate:=Gear.generate_for_pool(fixture_rng,uid,30,rarity,pool_id)
		if candidate.get("base_id")==base_id:
			check(Gear.validate_instance(candidate) and model._admit_reward_item(model.Items.wrap_equipment(candidate)),"Valid actual catalog fixture admitted: "+base_id+"/"+rarity)
			return candidate
	check(false,"Actual pool could not produce requested fixture: "+base_id+"/"+rarity);return {}
func expected_base_lines(stats:Dictionary)->Array[String]:
	var result:Array[String]=[]
	for stat:String in stats:result.append(Text.describe_stats({stat:stats[stat]}))
	return result
func expected_affix_lines(instance:Dictionary)->Array[String]:
	var result:Array[String]=[]
	for affix:Dictionary in instance.affixes:
		var family:=Gear.affix_definition(affix.id)
		result.append("%s +%d%s"%[family.label,affix.value,"%" if family.unit=="percent" else ""])
	return result
func casts()->Dictionary:
	var result:Dictionary={};var snapshot:Dictionary=model.get_combat_snapshot()
	for skill:String in Data.SKILLS:
		result[skill+":none"]=Compiler.compile_group(skill,snapshot,[])
		for support:String in Supports.SUPPORTS:
			if Supports.compatibility_reason(skill,[support]).is_empty():result[skill+":"+support]=Compiler.compile_group(skill,snapshot,[support])
	result.basic=Compiler.compile_basic(snapshot)
	return result
func _initialize()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	model=Model.new();fixture_rng.seed=370037
	var random_items:Array[Dictionary]=[]
	check(Gear.all_base_ids().size()==14,"All fourteen real base items are covered")
	for base_id:String in Gear.all_base_ids():
		for rarity:String in ["normal","magic","rare"]:random_items.append(make_gear(base_id,rarity))
	# Explicit local prefix prevents a fixture set from accidentally omitting P/F separation.
	var edge:=Gear.affix_definition("whetstone_edge");var uid:="gear_%06d"%int(model.snapshot().next_item_serial)
	var local:Dictionary={"id":uid,"base_id":"ashwood_bow","rarity":"magic","item_level":30,"affixes":[{"id":"whetstone_edge","tier":1,"value":int(edge.tiers[0].min)}]}
	check(model._admit_reward_item(model.Items.wrap_equipment(local)),"Local weapon prefix fixture uses actual accepted instance")
	random_items.append(local)
	for definition_id:String in Gems.definitions():
		if uid_for(definition_id).is_empty():check(not model.award_gem(definition_id).is_empty(),"Missing actual gem admitted: "+definition_id)
	check(not model.award_special_jewel().is_empty(),"Special jewel included in shared item views")
	var shard_uid:="item_%06d"%int(model.snapshot().next_item_serial)
	check(model._admit_reward_item(model.Items.calibration_shard(shard_uid,100)),"Real stackable currency fixture admitted")
	check(model.save_build("user://v37-presentation.json")==OK,"Full fixture snapshot saves once before presentation")
	var before:PackedByteArray=var_to_bytes(model.snapshot());var disk_before:=FileAccess.get_file_as_bytes("user://v37-presentation.json");var saves_before:int=model.successful_saves
	var stats_before:Dictionary=model.get_stats();var casts_before:=casts();var rng_before:int=fixture_rng.state
	model.changed.connect(func()->void:signals+=1)
	seed(370037);var global_expected:float=randf();seed(370037)
	for instance:Dictionary in random_items:
		var view:=Presenter.view(model,instance.id);var base:=Gear.base_definition(instance.base_id);var expected:=expected_base_lines(base.stats)
		if instance.base_id=="ashwood_bow":expected.append("本武器基础物理伤害 4.00")
		check(view.rarity==instance.rarity,"Stable rarity is the actual instance value")
		check(view.base_lines==expected,"Only authored base stats belong in equipment base section")
		check(view.affix_lines==expected_affix_lines(instance),"Every actual affix roll appears separately with its own unit")
		check(view.function.is_empty() and view.description.is_empty(),"Equipment does not duplicate the old aggregate description")
		check(not JSON.stringify(view).contains("装备合计") and not JSON.stringify(view).contains("本武器物理：("),"Old summed totals and local formula do not leak into displayed sections")
		if instance.rarity=="normal":check(view.affix_lines.is_empty(),"White equipment has no invented extra affixes")
		var views:=Presenter.comparisons(model,instance.id)
		for comparison:Dictionary in views:check(comparison.uid!=instance.id and model.item(comparison.uid).kind=="equipment","Comparison refers to owned equipped equipment")
	var fixed_count:=0
	for id:String in Data.ITEMS:
		var fixed_uid:=uid_for("equipment:"+id);check(not fixed_uid.is_empty(),"Every actual fixed item is present")
		var view:=Presenter.view(model,fixed_uid);fixed_count+=1
		check(model.item(fixed_uid).payload.is_empty() and view.rarity=="unique","Fixed item uses canonical unique rarity without invented rolls")
		check(view.base_lines==expected_base_lines(Data.ITEMS[id].stats) and view.affix_lines.is_empty(),"Fixed item original stats remain intrinsic, not random affixes")
		check(view.effect_lines.size()==Data.ITEMS[id].get("effects",[]).size(),"Fixed return/explosion mechanics remain disclosed")
	check(fixed_count==9,"Nine fixed item definitions checked")
	var support_count:=0;var active_count:=0
	for definition_id:String in Gems.definitions():
		var gem_uid:=uid_for(definition_id);var view:=Presenter.view(model,gem_uid);var definition:=Gems.definition(definition_id)
		check(view.name==definition.name and view.uid==gem_uid,"All26 actual gems keep independent UID and correct name")
		if definition.kind=="support_gem":
			support_count+=1
			var names:PackedStringArray=[];var ids:Array=Data.SKILLS.keys();ids.sort()
			for skill:String in ids:
				if Supports.compatibility_reason(skill,[definition.support_id]).is_empty():names.append(Data.SKILLS[skill].name)
			check(view.requirements==["适用技能："+"、".join(names)],"Compatibility belongs in its own section and matches every real supported skill")
			for tag:String in view.tags:check(tag=="辅助" or tag in ["资源辅助","元素辅助","发射辅助","控制辅助","连锁辅助"],"Support tags contain only its own semantic family")
			for row:Dictionary in view.modifiers:check(not row.label.contains(definition.name),"Support modifier does not repeat its own name")
			check(view.base_stats.is_empty(),"Support level/quality is not repeated as effect data")
		else:
			active_count+=1
			if definition.skill_id in ["tornado","bolt","frost","shade_bolt"]:check(not view.tags.has("爆炸") and not view.tags.has("次级"),"Independent explosion does not leak into active skill tags")
	check(active_count==10 and support_count==16,"Current complete gem catalog is10 active plus16 supports")
	for item_uid:String in model.snapshot().items:
		var view:=Presenter.view(model,item_uid);var original:=view.duplicate(true)
		check(not view.is_empty() and view.has("rarity"),"Every owned kind receives a common structured view")
		view.name="mutated";view.base_lines.clear();view.affix_lines.clear();view.tags.clear();view.requirements.clear();view.modifiers.clear();view.preview_lines.clear()
		check(Presenter.view(model,item_uid)==original,"Caller mutation cannot change model/catalog or future views")
	check(randf()==global_expected and fixture_rng.state==rng_before,"Presentation reads consume neither global nor fixture RNG")
	check(var_to_bytes(model.snapshot())==before and model.get_stats()==stats_before and casts()==casts_before,"All repeated views/comparisons leave snapshot, stats and actual compiled combat outputs identical")
	check(FileAccess.get_file_as_bytes("user://v37-presentation.json")==disk_before and model.successful_saves==saves_before and signals==0,"Presentation causes no save write or changed notification")
	check(Presenter.view(model,"unknown_uid").is_empty(),"Unknown UID has no stale or guessed view")
	print("Item presentation data v37: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
