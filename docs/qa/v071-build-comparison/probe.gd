extends SceneTree
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Attack = preload("res://scripts/combat/attack_hit_rules.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const DIR = "/workspace/scratch/a51485f153de/v070-build-comparison/"
func fail(message: String) -> void:
 push_error(message)
 quit(1)
func one(cast: Dictionary, role: String) -> Dictionary:
 if not cast.get("ok", false):return {"error":cast.get("error", "unknown")}
 var packet: Dictionary = cast.packets[role]
 var crit: Dictionary = cast.critical.primary
 var raw: Dictionary = Damage.resolve(packet, cast.snapshot.modifiers)
 var rows := {}
 for species: String in ["crawler", "skitter", "ember_guard"]:
  var e: Dictionary = Monsters.make_enemy(1,species,6,Vector2.ZERO)
  for k: String in Attack.monster_profile(int(e.kind)):
   if not e.has(k): e[k] = Attack.monster_profile(int(e.kind))[k]
  var hit: float = 1.0
  if packet.tags.has("attack"):
   hit = float(Attack.resolve(float(cast.snapshot.accuracy),float(e.evasion),50.0,bool(cast.get("hit_policy",{}).get("hits_cannot_be_evaded",false))).chance)
  var normal: Dictionary = Defense.apply_armour(Damage.resolve(packet,cast.snapshot.modifiers,e.resistances),float(e.armour))
  var critical: Dictionary = Defense.apply_armour(Damage.resolve(packet,cast.snapshot.modifiers,e.resistances,float(crit.multiplier)),float(e.armour))
  rows[species] = {"evasion":e.evasion,"armour":e.armour,"resistances":e.resistances,"hit_chance":hit,"noncritical_hit":normal.total,"critical_hit":critical.total,"expected_one_attempt":hit*((1.0-float(crit.chance))*float(normal.total)+float(crit.chance)*float(critical.total))}
 return {"mana":cast.get("mana",0.0),"cooldown":cast.get("cooldown",0.0),"critical":crit,"raw_noncritical":raw.total,"components":raw.components,"targets":rows,"recipe":cast.recipe,"supports":cast.get("support_ids",[]),"trap":cast.get("trap_profile",{}),"tags":packet.tags}
func _initialize() -> void:
 var fixture: Dictionary = Rules.decode(JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v070-gameplay/fixtures/selected-above.json")))
 if fixture.is_empty():fail("Original fixture decode failed");return
 var original: PackedByteArray = var_to_bytes(fixture)
 var routes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR+"routes.json"))
 var result := {"level":19,"budget":23,"class_id":2,"scope":"Deterministic source/model/compiler control, no gameplay or persistence; same existing items; support purchase assumed separately4 fragments/1slot.","rows":{}}
 for label: String in routes:
  var candidate: Dictionary = fixture.duplicate(true)
  candidate.progress = {"level":19,"xp":0}
  candidate.talents.allocated = routes[label]
  candidate.talents.normal_points = 23-(routes[label].size()-1)
  var error: String = Rules.reason(candidate)
  if not error.is_empty():fail(label+":"+error);return
  var game := Game.new()
  game._accept_memory(candidate)
  var before: PackedByteArray = var_to_bytes(game.snapshot())
  var stats: Dictionary = game.get_stats()
  var snap: Dictionary = game.get_combat_snapshot()
  var row := {"paid_points":routes[label].size()-1,"unspent_points":candidate.talents.normal_points,"route":routes[label],"stats":stats,"basic_blade":one(game.get_basic_cast(),"direct"),"cleave_blade":one(Compiler.compile_group("cleave",snap,[]),"direct"),"nova_direct":one(Compiler.compile_group("nova",snap,[]),"direct"),"nova_ambush":one(Compiler.compile_group("nova",snap,["ambush"]),"direct"),"meteor_ambush":one(Compiler.compile_group("meteor",snap,["ambush"]),"direct")}
  if var_to_bytes(game.snapshot())!=before or game.save_attempts!=0:fail("Readonly model drift");return
  # Swap the two already-owned canonical weapon locations, without editing items.
  var bow: Dictionary = candidate.duplicate(true)
  var location: Dictionary = bow.locations.gear_000004.duplicate(true)
  bow.locations.gear_000004=bow.locations.gear_000005
  bow.locations.gear_000005=location
  error=Rules.reason(bow)
  if not error.is_empty():fail("Existing bow swap:"+error);return
  var bow_game := Game.new()
  bow_game._accept_memory(bow)
  row.tornado_bow=one(Compiler.compile_group("tornado",bow_game.get_combat_snapshot(),[]),"parent")
  result.rows[label]=row
 if var_to_bytes(fixture)!=original:fail("Input changed");return
 var f:=FileAccess.open(DIR+"result.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(result,"\t",true,true)+"\n")
 f.close()
 print("Static legal build comparison: 5 same-class/level/budget states; original ownership preserved, zero saves")
 quit(0)
