extends SceneTree
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/catalog.json"));var recharge:Dictionary=catalog.source_recharge
	check(catalog.game_version=="0.33.0" and catalog.save_version==21 and recharge.minimum_save_version==21,"Reference records new game and vocabulary version")
	check(recharge.base_delay==Defense.RECHARGE_BASE_DELAY and recharge.rate_stat=="shield_recharge_rate_increased" and recharge.start_stat=="shield_recharge_start_faster","Reference reads shared fields and base delay")
	for example:Dictionary in recharge.examples:
		var profile:=Defense.recharge_profile(example.input)
		check(profile==example.after and profile==example.monster_after,"Both reference actor values exactly equal shared calculation")
		check(SourceTree.node_effect(example.node_id).status=="full" and SourceTree.node_effect(example.node_id,0,20).status!="full","Reference uses actual newly complete source nodes")
		check(catalog.source_tree.nodes[example.node_id].execution.status=="full","Individual source card carries same execution coverage")
	var coverage:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/source-tree-coverage.json"))
	check(coverage.inventory.node_records==3390 and coverage.inventory.standard_graph_nodes==2387 and coverage.inventory.standard_graph_edges==2697,"Pinned source topology is unchanged")
	check(coverage.class_reachability[0].reachable_count_including_start==589,"Current default connected coverage includes actual twelve newly reachable nodes")
	var html:=FileAccess.get_file_as_string("res://docs/reference/index.html")
	check(html.contains("rules-source_recharge") and html.contains("有效损伤后等待再充能") and html.contains("已开始等待不改"),"Reference includes timing diagram and swap timing boundary")
	print("Source recharge reference: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
