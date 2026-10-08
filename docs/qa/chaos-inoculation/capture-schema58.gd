extends SceneTree
const Game=preload("res://scripts/canonical_game_state.gd")
const Source=preload("res://scripts/passives/source_tree_runtime.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const QA="res://docs/qa/chaos-inoculation/"
func write(name:String,value:Variant)->void:
 FileAccess.open(QA+name,FileAccess.WRITE).store_string(JSON.stringify(value,"\t",true,true)+"\n")
func _initialize()->void:
 assert(Rules.VERSION==58)
 var game=Game.new();var town=game.snapshot()
 town.progress={"level":7,"xp":0};town.talents.class_id=3;town.talents.allocated=["54447","57226","21678","32210","8948","27659","37671","27415","32710","49605","60440"];town.talents.normal_points=1
 assert(Rules.reason(town).is_empty(),Rules.reason(town))
 var active=town.duplicate(true);active.journey=JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/iron-will/schema57-active.json")).journey
 active=Rules.decode(JSON.parse_string(JSON.stringify(active)))
 assert(Rules.reason(active).is_empty(),Rules.reason(active))
 write("schema58-town.json",town);write("schema58-active.json",active)
 var effects={}
 for id:String in Source.Data.nodes():
  var node=Source.Data.node(id)
  if node.type=="mastery":
   for effect:Dictionary in node.mastery_effects:effects[id+":"+str(effect.effect)]=Source.node_effect(id,int(effect.effect),58)
  else:effects[id+":0"]=Source.node_effect(id,0,58)
 var normalized=JSON.parse_string(JSON.stringify(effects,"",true,true))
 var stats=Game._stats_for(town)
 var hits=[]
 for packet:Dictionary in [{"chaos":100.0},{"chaos":100.0,"physical":50.0,"fire":30.0},{"physical":50.0,"cold":30.0}]:hits.append(Defense.incoming_source_hit(packet,stats,40.0,50.0))
 write("schema58-oracle.json",{"base_commit":"c74596e5a268000a4988d779c5517f712b55afe2","fixture":"Explicit legal level7 Witch ten-point prefix, one unspent point; existing owned starter items; active journey reused from prior valid fixture. Not natural progression evidence.","effects_count":effects.size(),"effects_policy58_sha256":JSON.stringify(normalized,"",true,true).sha256_text(),"stats":stats,"hits":hits,"town_sha256":FileAccess.get_sha256(QA+"schema58-town.json"),"active_sha256":FileAccess.get_sha256(QA+"schema58-active.json")})
 print("CI58_BASELINE_CAPTURE_OK");quit()
