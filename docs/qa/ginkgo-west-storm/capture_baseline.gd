extends SceneTree
const State=preload("res://scripts/world/map_camp_state.gd")
const Maps=preload("res://scripts/world/map_compiler.gd")
const Catalog=preload("res://scripts/world/map_catalog.gd")
const Layout=preload("res://scripts/world/exploration_map_layout.gd")
const View=preload("res://scripts/visuals/world_view.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
static func cases()->Array:
	var result:Array=[]
	for map_id:String in Catalog.MAPS:
		for tier:int in range(4):
			for special:String in ["","frost_patrol","storm_patrol","chaos_patrol","elemental_aegis","chaos_aegis"]:
				var ids:Array=[] if special.is_empty() else [special]
				var compiled:Dictionary=Maps.compile(map_id,[],ids) if tier==0 else Maps.compile_normal(map_id,tier,[],ids)
				if not compiled.ok:continue
				for seed_value:int in [0,7,861073]:result.append({"key":"%s/%d/%s/%d"%[map_id,tier,special,seed_value],"map_id":map_id,"tier":tier,"special":special,"seed":seed_value})
	return result
static func profile(row:Dictionary)->Dictionary:
	var ids:Array=[] if row.special.is_empty() else [row.special]
	return (Maps.compile(row.map_id,[],ids) if int(row.tier)==0 else Maps.compile_normal(row.map_id,int(row.tier),[],ids)).profile
func _initialize()->void:
	if FileAccess.get_sha256("res://scripts/world/map_camp_state.gd")!="bb780e7ad0a3cd59130271e30a2ca9099e075d72181361da938e0b4f3e818a4a":
		printerr("Baseline capture requires unmodified 8ed6961 production sources");quit(1);return
	if FileAccess.get_sha256("res://scripts/world/ginkgo_roster_rules.gd")!="4b7e1804a1407051f1a00392d0255aacfd7f8a6fe6a80cf9add72ba9702de5b0":
		printerr("Baseline capture requires unmodified 8ed6961 production sources");quit(1);return
	var result:Dictionary={"baseline":"8ed6961ccc8a87793cbd1ae76c9afe8ae4d9b95a","cases":[]}
	for row:Dictionary in cases():
		var state:=State.new();var p:=profile(row);var layout:=Layout.layout(row.map_id,Layout.WORLD_BOUNDS)
		var opened:=state.begin(p,layout.landmarks,row.seed,Monsters.CURRENT_ROLL_POLICY)
		if not opened.ok:
			printerr(row.key,": ",opened);quit(1);return
		var record:=row.duplicate();record.hashes={}
		for camp:String in State.CAMP_IDS:record.hashes[camp]=var_to_bytes(state.entries(camp)).hex_encode().sha256_text()
		record.slot3=var_to_bytes(state.entries("camp_west")[2]).hex_encode()
		result.cases.append(record)
	FileAccess.open("res://docs/qa/ginkgo-west-storm/baseline.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("WEST_STORM baseline rosters=",result.cases.size());quit()
