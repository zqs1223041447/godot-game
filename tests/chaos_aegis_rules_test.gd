extends SceneTree
const Rules=preload("res://scripts/world/map_defense_rules.gd")
const Maps=preload("res://scripts/world/map_compiler.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
const Admission=preload("res://scripts/world/map_admission.gd")
const Runtime=preload("res://scripts/monsters/monster_runtime.gd")
const Encounter=preload("res://scripts/encounters/encounter_admission.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:
	var profile:Dictionary=Maps.compile("old_garden",[],["chaos_aegis"]).profile
	var plain:Dictionary=Maps.compile("old_garden",[],[]).profile
	var elemental:Dictionary=Maps.compile("old_garden",[],["elemental_aegis"]).profile
	var packet:Dictionary=Damage.packet({"physical":100.0,"fire":100.0,"cold":100.0,"lightning":100.0,"chaos":100.0},["hit"],"chaos_aegis_check")
	seed(831);var next:=randi();seed(831)
	for id:String in Monsters.TEMPLATES:
		var source:Dictionary=Monsters.make_enemy(1,id,5,Vector2.ZERO,"map_boss" if id=="rift_warden" else "ordinary")
		var before:=var_to_bytes(source)
		var result:Dictionary=Rules.apply_to_enemy(source,profile)
		check(result.ok and var_to_bytes(source)==before,"Pure valid enemy application: "+id)
		if not result.ok:continue
		var after:Dictionary=result.enemy
		var expected:Dictionary=source.duplicate(true)
		expected.defense_stats.chaos_resistance=float(source.defense_stats.get("chaos_resistance",0.0))+0.2
		expected.resistances.chaos=Defense.chaos_resistance_profile(expected.defense_stats,"monster").effective
		expected.map_defense_source=after.map_defense_source
		check(after==expected and after.map_defense_source.modifier_id=="chaos_aegis","Only chaos defense changes; all actor fields retained: "+id)
		var base:Dictionary=Damage.resolve(packet,[],source.resistances)
		var actual:Dictionary=Damage.resolve(packet,[],after.resistances)
		var expected_hit:Dictionary=base.components.duplicate(true);expected_hit.chaos-=20.0
		var same:=true
		for type:String in expected_hit:same=same and is_equal_approx(actual.components[type],expected_hit[type])
		check(same,"Five-type real damage resolver changes chaos alone: "+id)
		check(not Rules.apply_to_enemy(after,profile).ok and Rules.apply_to_enemy(source,plain).enemy==source,"No repeat stacking or unselected mutation: "+id)
		var old:Dictionary=Rules.apply_to_enemy(source,elemental)
		check(old.ok and old.enemy.resistances.get("chaos",0.0)==source.resistances.get("chaos",0.0),"Existing three-element selection preserves chaos: "+id)
	check(randi()==next,"Defense application consumes no RNG")
	for raw:float in [-0.5,0.0,0.25,0.65,0.9]:
		var source:Dictionary=Monsters.make_enemy(1,"brute",5,Vector2.ZERO,"ordinary")
		source.defense_stats={"chaos_resistance":raw,"fire_resistance":0.9,"maximum_fire_resistance_add":0.10}
		source.resistances=Defense.source_profile(source.defense_stats,"monster").effective_resistances
		var result:Dictionary=Rules.apply_to_enemy(source,profile)
		check(result.ok and is_equal_approx(result.enemy.resistances.chaos,clampf(raw+0.2,0.0,0.75)) and is_equal_approx(result.enemy.resistances.fire,0.83),"Chaos clamps after raw addition independently of raised elemental cap: "+str(raw))
		check(is_equal_approx(result.enemy.map_defense_source.raw_resistances.chaos,raw+0.2),"Provenance retains uncapped raw chaos: "+str(raw))
	var source:Dictionary=Monsters.make_enemy(1,"chaos_guard",5,Vector2.ZERO,"ordinary")
	for value:Variant in [true,"0.25",NAN,INF]:
		var bad:Dictionary=source.duplicate(true);bad.defense_stats.chaos_resistance=value
		check(not Rules.apply_to_enemy(bad,profile).ok,"Reject malformed raw chaos")
		bad=source.duplicate(true);bad.resistances.chaos=value
		check(not Rules.apply_to_enemy(bad,profile).ok,"Reject malformed effective chaos")
	var bad:Dictionary=source.duplicate(true);bad.resistances.erase("chaos")
	check(not Rules.apply_to_enemy(bad,profile).ok,"Cannot erase effective base25 chaos to wash an invalid actor")
	bad=source.duplicate(true);bad.map_defense_source=null
	check(not Rules.apply_to_enemy(bad,profile).ok,"Any existing provenance marker blocks double application")
	check(not Rules.apply_to_enemy(source,{}).ok and not Maps.compile("old_garden",[],["chaos_aegis","elemental_aegis"]).ok,"Invalid profile and two specials rejected")
	check(not Maps.compile_normal("old_garden",1,[],["chaos_aegis"]).ok and Maps.compile_normal("old_garden",2,[],["chaos_aegis"]).ok,"Existing wave gate: I rejected, II allowed")
	var paid:Dictionary=Maps.compile_normal("old_garden",2,[],["chaos_aegis"]).profile
	check(paid.fee==4 and paid.completion_reward==10 and Maps.special_template(profile,{"template":"brute"}).is_empty(),"Existing fee4/reward10; no species replacement")
	var runtime:=Runtime.new()
	var parent:Dictionary=Admission.create_root(runtime,profile,"splitter",4,Vector2(500,500),"ordinary","",[],true).enemy
	parent.health=0.0;var death:Dictionary=runtime.process_death(parent)
	var children:Dictionary=Admission.drain(runtime,profile,100,Rect2(0,0,2000,2000))
	check(children.ok and children.enemies.size()==death.queued,"Existing staged admission drains all death children")
	for child:Dictionary in children.enemies:
		check(child.resistances.chaos==0.2 and not child.reward_eligible and child.xp_reward==0 and child.root_id==parent.root_id,"Child starts from its own base, receives20 once, preserves lineage/no reward")
	var corrupt:=BadChaosRuntime.new();var snapshot:Dictionary=Encounter._snapshot(corrupt)
	check(not Admission.create_root(corrupt,profile,"brute",4,Vector2.ZERO,"ordinary","",[],true).ok and Encounter._snapshot(corrupt)==snapshot,"Post-factory chaos validation rolls back root identity")
	var report:={"checks":checks,"failures":failures.size(),"failed_labels":failures}
	FileAccess.open(OS.get_environment("CHAOS_AEGIS_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("CHAOS_AEGIS_RULES ",JSON.stringify(report));quit(1 if not failures.is_empty() else 0)
class BadChaosRuntime extends Runtime:
	func create_root(template_id:String,wave:int,position:Vector2,context:String="ordinary",rarity:String="",mechanisms:Array=[],rewards:bool=true)->Dictionary:
		var enemy:Dictionary=super.create_root(template_id,wave,position,context,rarity,mechanisms,rewards)
		if not enemy.is_empty():enemy.resistances.chaos=0.99
		return enemy
