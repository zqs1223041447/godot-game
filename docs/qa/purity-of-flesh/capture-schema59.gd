extends SceneTree
const Game=preload("res://scripts/canonical_game_state.gd")
const Source=preload("res://scripts/passives/source_tree_runtime.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const QA="res://docs/qa/purity-of-flesh/"
func write(name:String,value:Variant)->void:
 FileAccess.open(QA+name,FileAccess.WRITE).store_string(JSON.stringify(value,"\t",true,true)+"\n")
func _initialize()->void:
 assert(Rules.VERSION==59)
 var game=Game.new();var town=game.snapshot()
 town.progress={"level":6,"xp":0};town.talents.class_id=5;town.talents.allocated=["61525","63965","14151","27564","17735","58402","6764","14057","9386","5743"];town.talents.normal_points=1
 assert(Rules.reason(town).is_empty(),Rules.reason(town))
 var active=town.duplicate(true);active.journey=JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/iron-will/schema57-active.json")).journey
 active=Rules.decode(JSON.parse_string(JSON.stringify(active)))
 assert(Rules.reason(active).is_empty(),Rules.reason(active))
 write("schema59-town.json",town);write("schema59-active.json",active)
 var effects={}
 for id:String in Source.Data.nodes():
  var node=Source.Data.node(id)
  if node.type=="mastery":
   for effect:Dictionary in node.mastery_effects:effects[id+":"+str(effect.effect)]=Source.node_effect(id,int(effect.effect),59)
  else:effects[id+":0"]=Source.node_effect(id,0,59)
 var normalized=JSON.parse_string(JSON.stringify(effects,"",true,true))
 var stats=Game._stats_for(town)
 var hits=[]
 for packet:Dictionary in [{"chaos":100.0},{"chaos":100.0,"physical":50.0,"fire":30.0},{"physical":50.0,"cold":30.0}]:hits.append(Defense.incoming_source_hit(packet,stats,40.0,50.0))
 write("schema59-oracle.json",{"base_commit":"9b6d28d1831cf9b34ea469e439e88807f4598227","fixture":"Explicit legal level6 Templar nine-point prefix, one unspent point; existing owned starter items; active journey reused from prior valid fixture. Not natural progression evidence.","effects_count":effects.size(),"effects_policy59_sha256":JSON.stringify(normalized,"",true,true).sha256_text(),"stats":stats,"hits":hits,"town_sha256":FileAccess.get_sha256(QA+"schema59-town.json"),"active_sha256":FileAccess.get_sha256(QA+"schema59-active.json")})
 print("PURITY59_BASELINE_CAPTURE_OK");quit()
