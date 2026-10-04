extends SceneTree
const Patterns=preload("res://scripts/passives/source_stat_patterns.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
const FORMS=[
	["12.5% increased Critical Strike Chance","crit_chance_increased","increased"],
	["12.5% increased Spell Critical Strike Chance","spell_crit_chance_increased","increased"],
	["12.5% increased Melee Critical Strike Chance","melee_crit_chance_increased","increased"],
	["12.5% increased Critical Strike Chance for Attacks","attack_crit_chance_increased","increased"],
	["Projectile Attack Skills have 12.5% increased Critical Strike Chance","projectile_attack_crit_chance_increased","increased"],
	["+12.5% to Critical Strike Multiplier","crit_multiplier_add","flat"],
	["+12.5% to Critical Strike Multiplier for Spell Damage","spell_crit_multiplier_add","flat"],
	["+12.5% to Melee Critical Strike Multiplier","melee_crit_multiplier_add","flat"],
	["Projectile Attack Skills have +12.5% to Critical Strike Multiplier","projectile_attack_crit_multiplier_add","flat"],
]
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	check(Patterns.CRITICAL_PATTERNS.size()==9,"Exactly nine closed critical forms")
	for form:Array in FORMS:
		var line:String=form[0];var grant:Dictionary={"stat":form[1],"value":0.125,"mode":form[2]}
		check(Patterns.parse_line(line)=={"supported":true,"grants":[grant],"reason":""},"Exact scoped amount/mode: "+line)
		check(not Patterns.parse_line(line,true,true,true,true,false).supported,"Explicit parser critical gate closes: "+line)
		for gates:Array in [[false,true,true,true],[true,false,true,true],[true,true,false,true],[true,true,true,false]]:
			check(not Patterns.parse_line(line,gates[0],gates[1],gates[2],gates[3],true).supported,"Earlier vocabulary gate cannot be bypassed")
		for variant:String in [" "+line,line+" ","prefix "+line,line+".",line+" with Swords",line+" Recently",line+" while on Full Life",line+" if you've Killed Recently",line+"\n",line+"\r",line+"\n5% increased Damage",line.replace("12.5","-12.5"),line.replace("12.5","+12.5"),line.replace("12.5","1e2"),line.replace("12.5","NaN"),line.replace("12.5","Inf"),line.replace("12.5","9".repeat(400))]:
			check(not Patterns.parse_line(variant).supported,"Reject whole-line/conditional/nonfinite/negative variation: "+variant.substr(0,90))
		for version:int in [24,23,19,22,21,20,18,24,23,24]:
			check(SourceTree.line_effect(line,version).supported==(version==24),"Warm line cache preserves policy "+str(version))
		var borrowed:=SourceTree.line_effect(line,24);borrowed.grants[0].value=1000.0
		check(SourceTree.line_effect(line,24).grants==[grant],"Caller cannot mutate line cache")
	for line:String in ["+1% to Critical Strike Chance","1% additional Critical Strike Chance","10% more Critical Strike Chance","Critical Strike Chance is Lucky","Your Critical Strike Chance is Lucky","Minions have 25% increased Critical Strike Chance","25% increased Critical Strike Chance with Bows","+25% to Critical Strike Multiplier with Daggers","+25% to Critical Strike Multiplier for Attacks","Trigger a Spell on Critical Strike","25% reduced Critical Strike Chance","25% increased Global Critical Strike Chance","25% increased Attack Critical Strike Chance"]:
		check(not Patterns.parse_line(line).supported,"Out-of-scope critical mechanic stays rejected: "+line)
	for row:Array in [["10% increased Area of Effect",20],["10% increased Energy Shield Recharge Rate",21],["10% increased Mana Cost Efficiency",22],["10% increased Life Recovery from Flasks",23],["10% increased Life and Mana Recovery from Flasks",23]]:
		check(SourceTree.line_effect(row[0],row[1]).supported and not SourceTree.line_effect(row[0],row[1]-1).supported and SourceTree.line_effect(row[0],24).supported,"Prior vocabulary keeps its exact introduction gate")
	print("Source critical parser: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
