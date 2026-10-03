extends SceneTree
const Data=preload("res://scripts/game_data.gd")
const Build=preload("res://scripts/build_state.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Supports=preload("res://scripts/combat/support_registry.gd")
func _initialize()->void:
	var output:=OS.get_environment("SKILL_MATRIX_OUT")
	if output.is_empty():quit(78);return
	var state:=Build.new()
	for id:String in ["prism_bow","return_mantle","detonation_charm"]:state.equip(id)
	var snapshot:=state.get_combat_snapshot();var records:Dictionary={}
	for skill:String in Data.SKILLS:
		var available:=Supports.supports_for_skill(skill);available.sort()
		for mask:int in range(1<<available.size()):
			var links:Array=[]
			for bit:int in available.size():
				if mask & (1<<bit):links.append(available[bit])
			if links.size()>5:continue
			var compiled:=Compiler.compile_group(skill,snapshot,links)
			if not compiled.get("ok",false):push_error(skill+str(links)+str(compiled));quit(1);return
			records[skill+"|"+",".join(links)]=compiled
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"version":ProjectSettings.get_setting("application/config/version"),"skills":Data.SKILLS.size(),"records":records},"\t",true,true))
	print("SKILL_RECIPE_MATRIX_COMPLETE ",Data.SKILLS.size()," skills, ",records.size()," compiled recipes");quit()
