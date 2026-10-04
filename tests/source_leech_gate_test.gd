extends SceneTree
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
const Store=preload("res://scripts/save/canonical_build_store.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const EXPECTED_NEW=["1382","22356","28311","29547","35507","3634","36704","37800","39530","41819","4378","50038","51420","54872","61039","62094","62108","63422","65053","8001","9171"]
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func digest(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
func _initialize()->void:
	var ids:=SourceTree.Data.standard_ids();ids.sort()
	var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v040_leech/old-source-gates.json"))
	for version:int in range(19,25):
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
				if SourceTree.node_effect(id,effect_id,25).status=="full":
					all_full_masteries[effect_id]=true
					if SourceTree.node_effect(id,effect_id,24).status!="full":new_masteries[effect_id]=true
			continue
		var status:String=SourceTree.node_effect(id,0,25).status;counts[status]+=1
		if SourceTree.node_effect(id,0,24).status!="full" and status=="full":
			new_nodes.append(id);opened_nodes.append({"id":id,"name":node.name,"stats":node.stats})

	check(new_nodes==EXPECTED_NEW,"Exactly21 newly complete ordinary nodes, separate from mastery entrances")
	check(new_masteries.keys()==[15133],"Exactly one newly full unique mastery effect ID15133")
	var partial_nodes:Array=[]
	for id:String in ids:
		var node:=SourceTree.Data.node(id)
		if node.type=="mastery":continue
		var effect:=SourceTree.node_effect(id,0,25)
		if effect.status=="partial" and effect.supported.any(func(line:String)->bool:return line.contains("Leech")):
			check(not effect.grants.is_empty() and not effect.unsupported.is_empty(),"Known leech grants never authorize unsupported lines on node "+id)
			partial_nodes.append({"id":id,"name":node.name,"supported":effect.supported,"unsupported":effect.unsupported})
	check(partial_nodes.size()==11,"Exactly11 ordinary nodes retain unsupported companion lines")
	check(SourceTree.node_effect("27422",0,25).status=="partial","Physical-mana source node stays locked behind unsupported attack-cost efficiency")
	var mastery_entrances:Array=[]
	for id:String in ids:
		if SourceTree.node_effect(id,15133,25).status=="full" and SourceTree.Data.node(id).type=="mastery":mastery_entrances.append(id)
	check(mastery_entrances==["35038","48411","53828","56128"],"One effect ID appears on exactly four Wand Mastery entrances")
	var base:=Store.new().snapshot();var classes:Array=[];var unreachable:Array=[]
	for class_id:int in range(7):
		var start:=SourceTree.Data.start_for_class(class_id)
		var paths:Dictionary={start:[start]};var queue:Array=[start];var cursor:=0
		while cursor<queue.size():
			var current:String=queue[cursor];cursor+=1
			for neighbor:String in SourceTree.Data.adjacency(current):
				var node:=SourceTree.Data.node(neighbor)
				if paths.has(neighbor) or node.type in ["start","mastery","proxy"] or node.source.get("isProxy",false) or node.source.get("isBlighted",false) or SourceTree.node_effect(neighbor,0,25).status!="full" or paths[current].size()>123:continue
				paths[neighbor]=paths[current]+[neighbor];queue.append(neighbor)
		var reached:Array=[];var absent:Array=[];var maximum_spent:=0
		for id:String in new_nodes:
			if not paths.has(id):absent.append(id);continue
			var candidate:=base.duplicate(true);candidate.progress.level=119;candidate.progress.xp=0
			candidate.talents.class_id=class_id;candidate.talents.allocated=paths[id];candidate.talents.normal_points=124-paths[id].size()
			check(SourceTree.analyze(candidate).legal and Rules.reason(candidate).is_empty(),"Actual source path passes full allocation/budget contract from class%d to%s"%[class_id,id])
			for version:int in [24,19,25,24,25]:
				var gated:=candidate.duplicate(true);gated.version=version
				check(SourceTree.analyze(gated).legal==(version==25),"Warm analysis cannot cross schema gate for actual allocated node")
			reached.append(id);maximum_spent=maxi(maximum_spent,paths[id].size()-1)
		check(reached.size()==20 and paths.size()-1==676,"Class%d reaches exactly20 new/676 total ordinary nodes"%class_id)
		if class_id==0:unreachable=absent
		check(absent==["8001"] and absent==unreachable,"Clever Thief8001 alone remains blocked for every class")
		# Even a connected partial node is not admitted just because one line now works.
		var rejected_partial:=false
		for id:String in paths:
			for neighbor:String in SourceTree.Data.adjacency(id):
				var effect:=SourceTree.node_effect(neighbor,0,25)
				if effect.status!="partial" or not effect.supported.any(func(line:String)->bool:return line.contains("Leech")) or paths[id].size()>123:continue
				var candidate:=base.duplicate(true);candidate.progress.level=119;candidate.progress.xp=0
				candidate.talents.class_id=class_id;candidate.talents.allocated=paths[id]+[neighbor];candidate.talents.normal_points=124-candidate.talents.allocated.size()
				check(not SourceTree.analyze(candidate).legal,"Real connected partial leech node still cannot be allocated")
				rejected_partial=true;break
			if rejected_partial:break
		check(rejected_partial,"Reached a genuine partial-node boundary for class"+str(class_id))
		var reachable_mastery_entrances:Array=[]
		for entrance:String in mastery_entrances:
			var group:String=SourceTree.Data.node(entrance).group_id
			for id:String in paths:
				var node:=SourceTree.Data.node(id)
				if node.type=="notable" and node.group_id==group:reachable_mastery_entrances.append(entrance)
		check(reachable_mastery_entrances.is_empty(),"No class can unlock Wand Mastery15133 through a fully supported notable")
		var capability_paths:Dictionary={}
		for id:String in reached:capability_paths[id]=paths[id]
		classes.append({"reachable_new_mastery_entrances":reachable_mastery_entrances,"paths_to_new_nodes":capability_paths,"class_id":class_id,"start_id":start,"reachable_new_node_ids":reached,"reachable_new_count":reached.size(),"all_reachable_non_start_ordinary_count":paths.size()-1,"max_new_node_path_spent":maximum_spent,"unreachable_new_node_ids":absent,"example_path":paths[reached[0]]})
	var report:Dictionary={"source_version":"3.29.1","source_sha256":SourceTree.Data.SOURCE_SHA256,"old_schema":24,"new_schema":25,"new_full_standard_ordinary_nodes":opened_nodes,"new_full_standard_ordinary_count":new_nodes.size(),"new_mastery_entrances":mastery_entrances,"new_reachable_mastery_effect_count":0,"partial_leech_nodes":partial_nodes,"new_full_mastery_distinct_effect_ids":new_masteries.keys(),"new_full_mastery_distinct_effect_count":new_masteries.size(),"all_full_mastery_distinct_effect_count":all_full_masteries.size(),"standard_non_mastery_status_counts":counts,"classes":classes,"reachability_contract":"Shortest connected paths through fully supported standard nodes, excluding other class starts, proxies, blighted nodes and mastery transit; each new-node candidate validated with123 point budget and no disconnected-jewel shortcut.","unreachable_new_node_ids":unreachable}
	var report_path:=OS.get_environment("V040_LEECH_COVERAGE_REPORT")
	if not report_path.is_empty():FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("Coverage: ",new_nodes.size()," newly full ordinary nodes; ",new_masteries.size()," unique mastery effects; blocked ",unreachable)
	print("Source leech gates: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
