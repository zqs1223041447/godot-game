extends SceneTree
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/catalog.json"))
	var spatial:Dictionary=catalog.source_spatial
	check(catalog.game_version=="0.32.0" and catalog.save_version==20 and spatial.minimum_save_version==20,"Reference publishes actual game and save versions")
	check(spatial.fields==Compiler.Spatial.STATS and spatial.area_damage_is_separate,"Reference field vocabulary matches production consumer")
	for example:Dictionary in spatial.examples:
		var input:Dictionary=example.input;var stats:Dictionary={"damage":20.0};stats[input.field]=input.value
		var cast:=Compiler.compile_skill(input.skill,Combat.snapshot(stats,["return_on_range","explode_on_flight_end"]),[])
		check(cast.ok and str(example.source_node.id)==input.node_id and SourceTree.node_effect(input.node_id).status=="full","Each source example names a real executable node")
		if cast.recipe.has("radius"):
			check(is_equal_approx(cast.recipe.radius,example.after.recipe.radius) and is_equal_approx(cast.recipe.area_multiplier,example.after.recipe.area_multiplier),"Reference radius and area are compiled values")
		else:
			check(is_equal_approx(cast.recipe.parent.speed,example.after.recipe.parent.speed) and is_equal_approx(cast.recipe.child.speed,example.after.recipe.child.speed),"Reference mother/child velocities are compiled values")
		check(cast.mana==example.after.mana and cast.cooldown==example.after.cooldown,"Reference does not invent resource or cooldown benefit")
	check(catalog.source_tree.nodes["5560"].execution.status=="full","Browseable source node coverage reflects new execution")
	var coverage:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/source-tree-coverage.json"))
	check(coverage.inventory.node_records==3390 and coverage.inventory.standard_graph_nodes==2387 and coverage.inventory.standard_graph_edges==2697,"Source topology remains the pinned complete graph")
	check(coverage.class_reachability[0].reachable_count_including_start==577 and coverage.class_reachability[0].reachable_count_including_start>555,"Export records actual increased default reachability")
	var html:=FileAccess.get_file_as_string("res://docs/reference/index.html")
	check(html.contains("rules-source_spatial") and html.contains("面积增加与半径平方根") and html.contains("旧版本注入新节点拒绝"),"Offline reference has mechanism diagram and migration boundary")
	print("Source spatial reference: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
