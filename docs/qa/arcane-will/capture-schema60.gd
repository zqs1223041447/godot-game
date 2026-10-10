extends SceneTree
const Game=preload("res://scripts/canonical_game_state.gd")
const Source=preload("res://scripts/passives/source_tree_runtime.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const QA="res://docs/qa/arcane-will/"
func write(name:String,value:Variant)->void:
 FileAccess.open(QA+name,FileAccess.WRITE).store_string(JSON.stringify(value,"\t",true,true)+"\n")
func _initialize()->void:
 assert(Rules.VERSION==60)
 var game=Game.new();var town=game.snapshot()
 town.progress={"level":4,"xp":0};town.talents.class_id=3;town.talents.allocated=["54447","57226","21678","32210","8948","27929","7503","65203"];town.talents.normal_points=1
 assert(Rules.reason(town).is_empty(),Rules.reason(town))
 var active=town.duplicate(true);active.journey=JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/iron-will/schema57-active.json")).journey
 active=Rules.decode(JSON.parse_string(JSON.stringify(active)))
 assert(Rules.reason(active).is_empty(),Rules.reason(active))
 write("schema60-town.json",town);write("schema60-active.json",active)
 var effects={}
 for id:String in Source.Data.nodes():
  var node=Source.Data.node(id)
  if node.type=="mastery":
   for effect:Dictionary in node.mastery_effects:effects[id+":"+str(effect.effect)]=Source.node_effect(id,int(effect.effect),60)
  else:effects[id+":0"]=Source.node_effect(id,0,60)
 var normalized=JSON.parse_string(JSON.stringify(effects,"",true,true))
 var stats=Game._stats_for(town)
 var hits=[]
 for packet:Dictionary in [{"chaos":100.0},{"chaos":100.0,"physical":50.0,"fire":30.0},{"physical":50.0,"cold":30.0}]:hits.append(Defense.incoming_source_hit(packet,stats,40.0,50.0))
 write("schema60-oracle.json",{"base_commit":"cdaee678322da0298e7b3e774a92ba62e2327c4d","fixture":"Explicit legal level4 Witch seven-point prefix, one unspent point; existing owned starter items; active journey reused from prior valid fixture. Not natural progression evidence.","effects_count":effects.size(),"effects_policy60_sha256":JSON.stringify(normalized,"",true,true).sha256_text(),"stats":stats,"hits":hits,"town_sha256":FileAccess.get_sha256(QA+"schema60-town.json"),"active_sha256":FileAccess.get_sha256(QA+"schema60-active.json")})
 print("ARCANE60_BASELINE_CAPTURE_OK");quit()
