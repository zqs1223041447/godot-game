extends SceneTree
const Store=preload("res://scripts/save/canonical_build_store.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const STAT_KEYS=["attack_life_leech","attack_mana_leech","physical_attack_life_leech","physical_attack_mana_leech","life_leech_rate_increased","mana_leech_rate_increased","life_leech_max_rate_increased","mana_leech_max_rate_increased"]
const SCENARIOS=[
 {"id":"attack_life_and_mana","targets":["36704"],"expected":[0.004,0.004,0.0,0.0,0.0,0.0,0.0,0.0]},
 {"id":"dual_rates_and_caps","targets":["39530","1382"],"expected":[0.014,0.014,0.0,0.0,0.6,0.6,0.4,0.4]},
 {"id":"physical_life_rate_and_cap","targets":["22356"],"expected":[0.0,0.0,0.006,0.0,1.6,0.0,0.4,0.0]},
 {"id":"dual_plus_physical_rates_and_caps","targets":["39530","1382","22356"],"expected":[0.014,0.014,0.006,0.0,2.2,0.6,0.8,0.4]},
]
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:
 var coverage:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v040/source-leech-coverage.json"))
 var paths:Dictionary=coverage.classes[4].paths_to_new_nodes;var base:=Store.new().snapshot();var examples:Array=[]
 for scenario:Dictionary in SCENARIOS:
  var allocation:Array=[]
  for target:String in scenario.targets:
   for id:String in paths[target]:
    if not allocation.has(id):allocation.append(id)
  var candidate:=base.duplicate(true);candidate.talents.class_id=4;candidate.talents.allocated=["50986"];candidate.progress.level=119;candidate.progress.xp=0;candidate.talents.normal_points=123
  check(Rules.reason(candidate).is_empty(),"Unallocated Duelist is a valid start")
  for index:int in range(1,allocation.size()):
   var id:String=allocation[index]
   check(SourceTree.available(candidate).has(id),"Real source UI can allocate each next path step "+scenario.id+":"+id)
   candidate.talents.allocated.append(id);candidate.talents.normal_points-=1
   check(Rules.reason(candidate).is_empty(),"Every source allocation stays legal "+scenario.id+":"+id)
  var grants:Dictionary={}
  for key:String in STAT_KEYS:grants[key]=0.0
  for id:String in allocation:
   for grant:Dictionary in SourceTree.node_effect(id,0,25).grants:
    if grants.has(grant.stat):grants[grant.stat]+=float(grant.value)
  for index:int in range(STAT_KEYS.size()):check(is_equal_approx(grants[STAT_KEYS[index]],scenario.expected[index]),"Real source amount "+scenario.id+":"+STAT_KEYS[index])
  var minimal:=candidate.duplicate(true);minimal.progress.level=maxi(1,allocation.size()-5);minimal.talents.normal_points=mini(minimal.progress.level+4,123)-(allocation.size()-1)
  check(Rules.reason(minimal).is_empty(),"Published minimum level affords this exact route "+scenario.id)
  var old:=candidate.duplicate(true);old.version=24
  check(not Rules.reason_v24(old).is_empty(),"Concrete leech route cannot be injected into old schema24")
  examples.append({"id":scenario.id,"class_id":4,"start_id":"50986","required_level":maxi(1,allocation.size()-5),"verification_level":119,"points_spent":allocation.size()-1,"allocated":allocation,"masteries":{},"normal_points_at_verification_level":candidate.talents.normal_points,"source_grants":grants,"source_node_targets":scenario.targets})
 var report:Dictionary={"schema":25,"source_version":"3.29.1","source_sha256":SourceTree.Data.SOURCE_SHA256,"examples":examples,"physical_mana_source":{"id":"27422","status":"partial","blocked_by":"25% increased Cost Efficiency of Attacks","allocatable":false},"new_mastery":{"effect_id":15133,"full_entrances":["35038","48411","53828","56128"],"reachable_entrances":[],"reason":"Each entrance requires an unsupported wand-scoped notable"}}
 var output:=OS.get_environment("V040_LEECH_PATHS_REPORT")
 if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
 print("Source leech paths: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
