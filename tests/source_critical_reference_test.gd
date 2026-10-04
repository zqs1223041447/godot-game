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
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/catalog.json"));var critical:Dictionary=catalog.source_critical
	check(catalog.game_version=="0.39.0" and catalog.save_version==24 and critical.minimum_save_version==24,"Reference version and vocabulary gate match")
	check(critical.fields==Compiler.Critical.STAT_KEYS and critical.base_chance==0.05 and critical.base_multiplier==1.5 and critical.natural_monster_base_chance==0.0,"Reference declares actual player balance and unchanged monster baseline")
	check(critical.new_complete_ordinary_nodes.size()==46 and critical.new_mastery_effect_ids==[],"New ordinary count not confused with mastery entrances")
	for id:String in critical.new_complete_ordinary_nodes:
		check(SourceTree.node_effect(id,0,23).status!="full" and SourceTree.node_effect(id,0,24).status=="full","Published new node count comes from exact source policy delta")
	for example:Dictionary in critical.examples:
		for source:Dictionary in example.source_nodes:check(SourceTree.node_effect(source.id).status=="full" and SourceTree.Data.node(source.id).stats==source.lines,"Example cites real source text and complete node")
		for id:String in example.profiles:
			var cast:=Compiler.compile_group(id,Combat.snapshot(example.input,["explode_on_flight_end"]),[])
			check(cast.ok and cast.critical==example.profiles[id],"Reference profiles equal production compiler across active scopes")
	var coverage:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/source-tree-coverage.json"))
	check(coverage.inventory.node_records==3390 and coverage.inventory.standard_graph_nodes==2387 and coverage.inventory.standard_graph_edges==2697,"Original graph inventory unchanged")
	for row:Dictionary in coverage.class_reachability:check(row.reachable_count_including_start==657,"Actual seven-class supported reachability includes start, not simultaneous budget")
	var html:=FileAccess.get_file_as_string("res://docs/reference/index.html")
	check(html.contains("rules-source_critical") and html.contains("独立战斗随机流") and html.contains("原字节备份") and html.contains("非暴击命中"),"Rendered reference describes roll sharing, RNG, migration and noncritical preview")
	check(not html.contains("施法动作时长/施法速度、暴击、格挡") and not html.contains("未发行四工艺研究独立保留"),"Obsolete blanket-critical and unreleased-crafting claims removed")
	print("Source critical reference: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
