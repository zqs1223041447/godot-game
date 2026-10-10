extends SceneTree
const ORACLE="res://docs/qa/ruins-corridor-frost/map_camp_state_8740385.gd.txt"
const Maps=preload("res://scripts/world/map_compiler.gd")
const Layout=preload("res://scripts/world/exploration_map_layout.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
func _initialize()->void:
	if FileAccess.get_sha256(ORACLE)!="5b49600164356fa94fdbb10115d3b07b7d9193aa9212db6d85dbb0a79e86174b":quit(1);return
	var State:=GDScript.new();State.source_code=FileAccess.get_file_as_string(ORACLE).replace("class_name MapCampState\n","")
	if State.reload()!=OK:quit(1);return
	var layout:=Layout.layout("broken_ruins",Layout.WORLD_BOUNDS)
	print("OUTPOST ",layout.landmarks.outposts[3])
	for tier:int in [2,3]:
		for seed_value:int in [0,7,861073]:
			var state:RefCounted=State.new()
			var result:Dictionary=state.begin(Maps.compile_normal("broken_ruins",tier,[],[]).profile,layout.landmarks,seed_value,Monsters.CURRENT_ROLL_POLICY)
			if not result.ok:printerr(result);quit(1);return
			var rows:Array=[]
			for i:int in range(4,12):
				var entry:Dictionary=state.entries("camp_north")[i]
				rows.append({"ordinal":i+1,"template":entry.template_id,"rarity":entry.rarity})
			print("ROSTER ",tier," ",seed_value," ",JSON.stringify(rows))
	quit()
