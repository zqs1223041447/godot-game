extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Supports=preload("res://scripts/combat/support_registry.gd")
const Data=preload("res://scripts/game_data.gd")
func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:quit(64);return
	var model:=Model.new();var snapshot:=model.get_combat_snapshot();var result:Array=[]
	for id:String in Data.SKILLS:
		var eligible:=Supports.supports_for_skill(id);eligible.sort()
		var selections:Array=[[]]
		for support:String in eligible:selections.append([support])
		for i:int in range(eligible.size()):
			for j:int in range(i+1,eligible.size()):
				if Supports.compatibility_reason(id,[eligible[i],eligible[j]]).is_empty():selections.append([eligible[i],eligible[j]])
		for ids:Array in selections:
			result.append({"skill":id,"supports":ids,"compiled":Compiler.compile_group(id,snapshot,ids)})
	result.append({"skill":"$basic","supports":[],"compiled":Compiler.compile_basic(snapshot)})
	var output:=FileAccess.open(args[0],FileAccess.WRITE)
	if output==null:quit(1);return
	output.store_buffer(var_to_bytes(result));output.close()
	print("Captured %d zero-leech v39 compiled recipes"%result.size());quit()
