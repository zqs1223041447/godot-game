extends SceneTree
const Modifiers=preload("res://scripts/combat/flask_modifier_rules.gd")
const Runtime=preload("res://scripts/combat/flask_runtime.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/catalog.json"));var flasks:Dictionary=catalog.source_flasks
	check(catalog.game_version=="0.35.0" and catalog.save_version==23 and flasks.minimum_save_version==23,"Reference and vocabulary version match current candidate")
	check(flasks.fields==Modifiers.STATS and not flasks.runtime_persisted and flasks.new_complete_ordinary_nodes.size()==10,"Reference states the actual three fields and runtime-only charge ownership")
	for example:Dictionary in flasks.examples:
		check(SourceTree.node_effect(example.node_id).status=="full" and catalog.source_tree.nodes[example.node_id].execution.status=="full","Referenced source node has complete current execution")
		for id:String in example.profiles:
			var profile:=Modifiers.profile(id,example.input,100.0);var recorded:Dictionary=example.profiles[id]
			check(profile.ok and is_equal_approx(profile.recovery_total,recorded.recovery_total) and is_equal_approx(profile.charges_per_root,recorded.charges_per_root) and profile.cost==recorded.cost and profile.duration==recorded.duration,"Worked profile is derived from the production rules")
	var runtime:=Runtime.new();var uid:="reference_charge";runtime.reset({uid:"flask:life"})
	for i:int in range(3):runtime.use(uid,0.0,100.0);runtime.clear_effects()
	for row:Dictionary in flasks.charge_rows:
		runtime.charge_rewarded_kill([uid],{"flask_charges_gained_increased":0.15})
		var snapshot:=runtime.snapshot()
		check(snapshot.charges_by_uid[uid]==int(row.whole_charges) and snapshot.get("charge_remainders_micro",{}).get(uid,0)==int(row.remainder_micro),"Reference charge staircase equals actual UID accumulator")
	var coverage:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/source-tree-coverage.json"))
	check(coverage.inventory.node_records==3390 and coverage.inventory.standard_graph_nodes==2387 and coverage.inventory.standard_graph_edges==2697 and coverage.class_reachability[0].reachable_count_including_start==608,"Coverage keeps source topology and records current reachable ordinary set")
	var html:=FileAccess.get_file_as_string("res://docs/reference/index.html")
	check(html.contains("rules-source_flasks") and html.contains("药剂使用冻结回复与根怪小数充能") and html.contains("20个有效根怪累计23点"),"Reference includes truthful frozen recovery and fractional charge illustration")
	print("Source flask reference: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
