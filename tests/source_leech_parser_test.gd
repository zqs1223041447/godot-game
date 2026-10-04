extends SceneTree
const Patterns=preload("res://scripts/passives/source_stat_patterns.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
const CASES=[
 ["0.4% of Attack Damage Leeched as Life","attack_life_leech",0.004,"flat"],
 ["0.8% of Attack Damage Leeched as Mana","attack_mana_leech",0.008,"flat"],
 ["0.6% of Physical Attack Damage Leeched as Life","physical_attack_life_leech",0.006,"flat"],
 ["0.2% of Physical Attack Damage Leeched as Mana","physical_attack_mana_leech",0.002,"flat"],
 ["20% increased total Recovery per second from Life Leech","life_leech_rate_increased",0.2,"increased"],
 ["40% increased total Recovery per second from Mana Leech","mana_leech_rate_increased",0.4,"increased"],
 ["10% increased Maximum total Life Recovery per second from Leech","life_leech_max_rate_increased",0.1,"increased"],
 ["30% increased Maximum total Mana Recovery per second from Leech","mana_leech_max_rate_increased",0.3,"increased"],
]
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:
 check(Patterns.LEECH_PATTERNS.size()==8,"Exactly eight approved closed forms")
 for row:Array in CASES:
  var line:String=row[0];var expected:Dictionary={"supported":true,"grants":[{"stat":row[1],"value":row[2],"mode":row[3]}],"reason":""}
  check(Patterns.parse_line(line)==expected,"Exact decimal source percent, scope and mode: "+line)
  check(not Patterns.parse_line(line,true,true,true,true,true,false).supported,"Explicit leech gate closes: "+line)
  for index:int in range(5):
   var gates:Array=[true,true,true,true,true];gates[index]=false
   check(not Patterns.parse_line(line,gates[0],gates[1],gates[2],gates[3],gates[4],true).supported,"Older vocabulary gate cannot be bypassed")
  for version:int in [25,24,19,23,25,20,21,22,24,25]:check(SourceTree.line_effect(line,version).supported==(version==25),"Warm cache keeps exact schema boundary")
  for changed:String in [" "+line,line+" ",line+".",line+" while on Full Life",line+" while Leeching",line+" with Swords",line+" for Minions",line+" instantly",line+"\n",line+"\r\n",line.to_lower(),"-"+line,"+"+line,"prefix "+line,"Inf"+line.substr(line.find("%")),"NaN"+line.substr(line.find("%")),"9".repeat(400)+line.substr(line.find("%"))]:
   check(not Patterns.parse_line(changed).supported,"Reject complete-line and nonfinite mutation: "+changed.substr(0,100))
 for line:String in ["1% of Damage Leeched as Life","1% of Spell Damage Leeched as Life","1% of Fire Damage Leeched as Life","1% of Attack Damage Leeched as Energy Shield","1% of Physical Attack Damage Leeched as Energy Shield","1% of Attack Damage Leeched as Life and Mana","1% of Attack Damage Leeched as Life with Axes","10% of Leech is Instant","Leech is not removed at Full Life","20% increased Life Recovery rate","20% increased Maximum Recovery per Life Leech","Minions Leech 1% of Damage as Life","20% reduced total Recovery per second from Life Leech","20% more total Recovery per second from Life Leech","20% increased maximum total Life Recovery per second from Leech"]:
  check(not Patterns.parse_line(line).supported,"Unsupported leech extension remains locked: "+line)
 for raw:Variant in [null,0,[],{},"","\t"]:check(not Patterns.parse_line(raw).supported,"Reject malformed source value")
 var original:=SourceTree.line_effect(CASES[0][0],25);original.grants[0].value=9.0
 check(SourceTree.line_effect(CASES[0][0],25).grants[0].value==0.004,"Returned cached grants cannot mutate authoritative parser state")
 print("Source leech parser: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
