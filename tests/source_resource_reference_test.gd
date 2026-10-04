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
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/catalog.json"));var resource:Dictionary=catalog.source_mana_cost
	check(catalog.game_version=="0.34.0" and catalog.save_version==22 and resource.minimum_save_version==22,"Reference uses current version and source vocabulary gate")
	check(resource.fields==Compiler.ResourceCost.STATS and resource.skills.size()==10 and resource.free_basic_attack and resource.float_payment,"Reference describes actual cost scope and unchanged free basic")
	for example:Dictionary in resource.examples:
		var cast:=Compiler.compile_group("nova",Combat.snapshot(example.input,[]),["efficiency","quickcast"])
		# JSON number decoding can differ by one double ULP (observed29.568).
		# Typed binary equality is covered separately by the frozen412 cast test.
		var factors_equal:bool=cast.cost_factors.size()==example.source_factors.size()
		for key:String in cast.cost_factors:factors_equal=factors_equal and example.source_factors.has(key) and absf(float(cast.cost_factors[key])-float(example.source_factors.get(key,INF)))<=1e-12
		check(cast.ok and absf(float(cast.mana)-float(example.compiled.mana))<=1e-12 and factors_equal,"Cost worked example equals production within JSON double round-trip precision")
		for node:Dictionary in example.source_nodes:check(SourceTree.node_effect(node.node_id).status=="full" and catalog.source_tree.nodes[node.node_id].execution.status=="full","Every cited ordinary node has actual complete execution")
	check(resource.mastery.effect_id==12119 and resource.mastery.entrances.size()==12 and is_equal_approx(resource.mastery.increased_efficiency,0.15),"Twelve entrances are one unique15percent effect")
	var coverage:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/source-tree-coverage.json"))
	check(coverage.inventory.node_records==3390 and coverage.inventory.standard_graph_nodes==2387 and coverage.inventory.standard_graph_edges==2697 and coverage.class_reachability[0].reachable_count_including_start==598,"Coverage records unchanged source topology and current ordinary reachability")
	var html:=FileAccess.get_file_as_string("res://docs/reference/index.html")
	check(html.contains("rules-source_mana_cost") and html.contains("魔力成本相乘再除效率") and html.contains("12处入口共享同一个15%效率精通"),"Reference includes actual formula diagram and uninflated mastery count")
	print("Source resource reference: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
