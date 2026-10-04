extends SceneTree
const Patterns=preload("res://scripts/passives/source_stat_patterns.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	var formats:Dictionary={"12% increased Area of Effect":["area_size_increased",0.12],"Spell Skills have 10% increased Area of Effect":["spell_area_size_increased",0.1],"Melee Skills have 10% increased Area of Effect":["melee_area_size_increased",0.1],"10% increased Projectile Speed":["projectile_speed_increased",0.1],"10% reduced Projectile Speed":["projectile_speed_increased",-0.1]}
	for line:String in formats:
		var result:=Patterns.parse_line(line)
		check(result.supported and result.grants==[{"stat":formats[line][0],"mode":"increased","value":formats[line][1]}],"Exact format preserves source value: "+line)
		check(not Patterns.parse_line(line,false).supported,"Old parser policy still rejects new vocabulary")
		for bad:String in [" "+line,line+" ",line+" while holding a Shield",line+"\n10% increased Damage",line.replace("10%","-10%").replace("12%","-12%")]:
			check(not Patterns.parse_line(bad).supported and Patterns.parse_line(bad).grants.is_empty(),"No conditions, trimming, negative syntax or multiline acceptance")
	for old:String in ["12% increased Area Damage","10% increased Projectile Damage","10% increased maximum Life","+10 to Strength"]:
		check(Patterns.parse_line(old)==Patterns.parse_line(old,false),"Original semantics and format remain identical")
	var source_count:Dictionary={}
	for id:String in SourceTree.Data.standard_ids():
		for line:String in SourceTree.lines_for(id):
			var parsed:=Patterns.parse_line(line)
			for grant:Dictionary in parsed.grants:
				if grant.stat in ["area_size_increased","spell_area_size_increased","melee_area_size_increased","projectile_speed_increased"]:
					source_count[grant.stat]=int(source_count.get(grant.stat,0))+1
					check(not Patterns.parse_line(line,false).supported and is_finite(grant.value),"Actual pinned standard-source line is new and finite")
	for stat:String in ["area_size_increased","spell_area_size_increased","melee_area_size_increased","projectile_speed_increased"]:check(source_count.get(stat,0)>0,"Actual standard source contains "+stat)
	print("Source spatial parser: %d checks, %d failures; source lines %s"%[checks,failures,JSON.stringify(source_count)]);quit(1 if failures else 0)
