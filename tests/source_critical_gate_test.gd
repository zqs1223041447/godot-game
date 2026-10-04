extends SceneTree
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
const Store=preload("res://scripts/save/canonical_build_store.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const EXPECTED_NEW=["1346","2225","4036","9469","10763","12794","14804","15228","15678","16380","16790","23439","25757","28658","28754","30455","30471","33903","34579","35283","35851","35894","36452","37501","38664","39023","40100","41119","44723","46842","47306","47484","47507","49929","53493","56355","56460","58831","59220","59494","60405","60592","61636","61981","63398","65502"]
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func digest(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
func _initialize()->void:
	var ids:=SourceTree.Data.standard_ids();ids.sort()
	var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v039_critical/old-source-gates.json"))
	for version:int in range(19,24):
		var records:Array=[]
		for id:String in ids:
			records.append([id,0,SourceTree.node_effect(id,0,version)])
			for effect:Dictionary in SourceTree.Data.node(id).mastery_effects:records.append([id,int(effect.effect),SourceTree.node_effect(id,int(effect.effect),version)])
		var frozen:Dictionary=baseline.policies[str(version)]
		check(records.size()==int(frozen.records) and digest(JSON.stringify(records,"",true,true).to_utf8_buffer())==frozen.sha256,"All4224 node/mastery records exactly preserve released vocabulary for policy"+str(version))
	var new_nodes:Array=[];var new_masteries:Dictionary={};var opened_nodes:Array=[];var all_full_masteries:Dictionary={}
	var counts:Dictionary={"full":0,"partial":0,"unsupported":0,"choice":0}
	for id:String in ids:
		var node:=SourceTree.Data.node(id)
		if node.type=="mastery":
			for effect:Dictionary in node.mastery_effects:
				var effect_id:int=int(effect.effect)
				if SourceTree.node_effect(id,effect_id,24).status=="full":
					all_full_masteries[effect_id]=true
					if SourceTree.node_effect(id,effect_id,23).status!="full":new_masteries[effect_id]=true
			continue
		var status:String=SourceTree.node_effect(id,0,24).status;counts[status]+=1
		if SourceTree.node_effect(id,0,23).status!="full" and status=="full":
			new_nodes.append(id);opened_nodes.append({"id":id,"name":node.name,"stats":node.stats})
	var sorted_expected:=EXPECTED_NEW.duplicate();sorted_expected.sort()
	check(new_nodes==sorted_expected,"Exactly46 newly complete ordinary standard nodes, counted apart from mastery entrances")
	check(new_masteries.is_empty(),"No critical mastery effect ID becomes fully supported")
	for id:String in ["5632","5875","9015","9788","12189"]:
		var effect:=SourceTree.node_effect(id,0,24)
		check(effect.status=="partial" and not effect.grants.is_empty() and not effect.unsupported.is_empty(),"Known critical grant cannot authorize other unsupported text on same node "+id)
	for effect:Dictionary in SourceTree.Data.node("9586").mastery_effects:
		check(SourceTree.node_effect("9586",int(effect.effect),24).status!="full","Critical mastery remains unavailable when its whole option is unsupported")
	var base:=Store.new().snapshot();var classes:Array=[];var unreachable:Array=[]
	for class_id:int in range(7):
		var start:=SourceTree.Data.start_for_class(class_id)
		var paths:Dictionary={start:[start]};var queue:Array=[start];var cursor:=0
		while cursor<queue.size():
			var current:String=queue[cursor];cursor+=1
			for neighbor:String in SourceTree.Data.adjacency(current):
				var node:=SourceTree.Data.node(neighbor)
				if paths.has(neighbor) or node.type in ["start","mastery","proxy"] or node.source.get("isProxy",false) or node.source.get("isBlighted",false) or SourceTree.node_effect(neighbor,0,24).status!="full" or paths[current].size()>123:continue
				paths[neighbor]=paths[current]+[neighbor];queue.append(neighbor)
		var reached:Array=[];var absent:Array=[];var maximum_spent:=0
		for id:String in new_nodes:
			if not paths.has(id):absent.append(id);continue
			var candidate:=base.duplicate(true);candidate.progress.level=119;candidate.progress.xp=0
			candidate.talents.class_id=class_id;candidate.talents.allocated=paths[id];candidate.talents.normal_points=124-paths[id].size()
			check(SourceTree.analyze(candidate).legal and Rules.reason(candidate).is_empty(),"Actual source path passes full allocation/budget contract from class%d to%s"%[class_id,id])
			for version:int in [23,19,24,23,24]:
				var gated:=candidate.duplicate(true);gated.version=version
				check(SourceTree.analyze(gated).legal==(version==24),"Warm analysis cannot cross schema gate for actual allocated node")
			reached.append(id);maximum_spent=maxi(maximum_spent,paths[id].size()-1)
		check(reached.size()==45 and paths.size()-1==656,"Class%d can genuinely reach45 new /656 non-start ordinary nodes"%class_id)
		if class_id==0:unreachable=absent
		check(absent==unreachable,"Same remaining critical node is blocked for every class")
		# Even a connected partial node is not admitted just because one line now works.
		var rejected_partial:=false
		for id:String in paths:
			for neighbor:String in SourceTree.Data.adjacency(id):
				var effect:=SourceTree.node_effect(neighbor,0,24)
				if effect.status!="partial" or not effect.supported.any(func(line:String)->bool:return line.contains("Critical")) or paths[id].size()>123:continue
				var candidate:=base.duplicate(true);candidate.progress.level=119;candidate.progress.xp=0
				candidate.talents.class_id=class_id;candidate.talents.allocated=paths[id]+[neighbor];candidate.talents.normal_points=124-candidate.talents.allocated.size()
				check(not SourceTree.analyze(candidate).legal,"Real connected partial critical node still cannot be allocated")
				rejected_partial=true;break
			if rejected_partial:break
		check(rejected_partial,"Reached a genuine partial-node boundary for class"+str(class_id))
		classes.append({"class_id":class_id,"start_id":start,"reachable_new_node_ids":reached,"reachable_new_count":reached.size(),"all_reachable_non_start_ordinary_count":paths.size()-1,"max_new_node_path_spent":maximum_spent,"unreachable_new_node_ids":absent,"example_path":paths[reached[0]]})
	var report:Dictionary={"source_version":"3.29.1","source_sha256":SourceTree.Data.SOURCE_SHA256,"old_schema":23,"new_schema":24,"new_full_standard_ordinary_nodes":opened_nodes,"new_full_standard_ordinary_count":new_nodes.size(),"new_full_mastery_distinct_effect_ids":new_masteries.keys(),"new_full_mastery_distinct_effect_count":new_masteries.size(),"existing_full_mastery_distinct_effect_count":all_full_masteries.size(),"standard_non_mastery_status_counts":counts,"classes":classes,"reachability_contract":"Shortest connected paths through fully supported standard nodes, excluding other class starts, proxies, blighted nodes and mastery transit; each new-node candidate validated with123 point budget and no disconnected-jewel shortcut.","unreachable_new_node_ids":unreachable}
	var report_path:=OS.get_environment("V039_CRITICAL_COVERAGE_REPORT")
	if not report_path.is_empty():FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("Coverage: 46 newly full ordinary nodes; 0 new mastery IDs; 45 reachable from each of7 starts; blocked ",unreachable)
	print("Source critical gates: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
