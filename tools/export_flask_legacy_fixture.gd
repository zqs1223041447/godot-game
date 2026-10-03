extends SceneTree
func _initialize()->void:
	var out:=OS.get_environment("V026_LEGACY_FIXTURE_DIR")
	var Model=load("res://scripts/canonical_game_state.gd")
	var Gems=load("res://scripts/items/gem_catalog.gd")
	var model=Model.new()
	if out.is_empty() or model.snapshot().version!=17 or str(ProjectSettings.get_setting("application/config/version"))!="0.25.0":quit(78);return
	DirAccess.make_dir_recursive_absolute(out)
	model.award_gem("skill:cleave");model.award_gem("skill:shade_bolt")
	var current:Dictionary=model.snapshot();assert(Model.Rules.reason(current).is_empty())
	FileAccess.open(out+"/released-v17-two-offense.json",FileAccess.WRITE).store_string("  \n"+JSON.stringify(current,"  ",true,true)+"\n\n")
	var maximum:Dictionary=current.duplicate(true);var count:=0
	while maximum.items.size()<Model.Rules.MAX_ITEMS:
		var uid:String="migration_flask_%06d"%(count+1) if count<2 else "legacy_overflow_%06d"%count
		maximum.items[uid]=Gems.create_instance(uid,"skill:bolt")
		maximum.locations[uid]={"kind":"recovery","index":count};count+=1
	maximum.next_item_serial=Model.Rules.MAX_SERIAL
	assert(Model.Rules.reason(maximum).is_empty())
	FileAccess.open(out+"/released-v17-maximum-registry.json",FileAccess.WRITE).store_string("\t\n"+JSON.stringify(maximum,"\t",true,true)+"\n")
	print("V17_LITERAL_FIXTURES_EXPORTED ",current.items.size()," / ",maximum.items.size());quit()
