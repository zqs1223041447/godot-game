extends SceneTree
const Rules=preload("res://scripts/world/map_defense_rules.gd")
const Maps=preload("res://scripts/world/map_compiler.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	var profile:Dictionary=Maps.compile("old_garden",[],["elemental_aegis"]).profile
	var packet:Dictionary=Damage.packet({"physical":100.0,"fire":100.0,"cold":100.0,"lightning":100.0,"chaos":100.0},["hit"],"test")
	seed(30003);var next:=randi();seed(30003)
	for id:String in Monsters.TEMPLATES:
		var template:Dictionary=Monsters.TEMPLATES[id]
		var source:Dictionary=Monsters.make_enemy(1,id,5,Vector2(100,100),"map_boss" if template.rarity=="boss" else "ordinary")
		var before:Dictionary=source.duplicate(true);var result:Dictionary=Rules.apply_to_enemy(source,profile)
		check(result.ok and source==before,"Pure application returns candidate without changing actual template actor")
		if not result.ok:continue
		var after:Dictionary=result.enemy
		for field:String in source:
			if field not in ["defense_stats","resistances"]:check(source[field]==after[field],"All non-defense actor fields unchanged: "+field)
		for element:String in ["fire","cold","lightning"]:
			check(is_equal_approx(after.defense_stats[element+"_resistance"],float(source.defense_stats.get(element+"_resistance",0.0))+0.2),"Raw elemental resistance adds exactly20points")
			check(is_equal_approx(after.resistances[element],clampf(after.defense_stats[element+"_resistance"],0,0.75)),"Effective value uses shared cap")
		check(after.map_defense_source.modifier_id=="elemental_aegis" and after.map_defense_source.effective_resistances==Defense.source_profile(after.defense_stats,"monster").effective_resistances,"Provenance records actual effective shared result")
		var base:Dictionary=Damage.resolve(packet,[],source.resistances);var actual:Dictionary=Damage.resolve(packet,[],after.resistances)
		check(base.components.physical==actual.components.physical and base.components.chaos==actual.components.chaos,"Real damage resolver leaves physical and chaos components unchanged")
		for element:String in ["fire","cold","lightning"]:check(is_equal_approx(base.components[element]-actual.components[element],20.0),"Real elemental component reduced by correct raw20point grant")
		var frozen:Dictionary=after.duplicate(true)
		check(not Rules.apply_to_enemy(after,profile).ok and after==frozen,"Repeat application rejected atomically")
	check(randi()==next,"Catalog, defense application and settlement consume no global RNG")
	var source:Dictionary=Monsters.make_enemy(1,"ember_guard",5,Vector2(100,100),"ordinary")
	var applied:Dictionary=Rules.apply_to_enemy(source,profile).enemy
	check(is_equal_approx(applied.resistances.fire,0.45) and is_equal_approx(applied.resistances.cold,0.2) and is_equal_approx(applied.resistances.lightning,0.2),"Original25fire becomes45fire/20cold/20lightning")
	source.defense_stats={"fire_resistance":0.65,"cold_resistance":0.90,"lightning_resistance":-0.5};source.resistances=Defense.source_profile(source.defense_stats,"monster").effective_resistances
	applied=Rules.apply_to_enemy(source,profile).enemy
	check(applied.resistances=={"fire":0.75,"cold":0.75,"lightning":0.0},"Raw values clamp only after addition, using shared zero/75 bounds")
	check(is_equal_approx(applied.map_defense_source.raw_resistances.fire,0.85) and is_equal_approx(applied.map_defense_source.raw_resistances.cold,1.10),"Uncapped total retained separately from effective display/damage")
	var source_before:Dictionary=source.duplicate(true)
	check(not Rules.apply_to_enemy(source,{}).ok and source==source_before,"Malformed profile rejected without touching source")
	for value:Variant in [true,"0.2",NAN,INF]:
		var invalid:Dictionary=source.duplicate(true);invalid.defense_stats.fire_resistance=value
		check(not Rules.apply_to_enemy(invalid,profile).ok,"Nonfinite/non-numeric raw resistance rejected")
	var wrong:Dictionary=source.duplicate(true);wrong.resistances.fire=0.5
	check(not Rules.apply_to_enemy(wrong,profile).ok,"Forged effective resistance cannot be silently washed into a valid actor")
	wrong=source.duplicate(true);wrong.map_defense_source=null
	check(not Rules.apply_to_enemy(wrong,profile).ok,"Any existing application marker rejects, including null")
	var empty:Dictionary=Maps.compile("old_garden",[],[]).profile
	check(Rules.apply_to_enemy(source,empty).enemy==source,"No aegis selection preserves whole actor dictionary")
	check(not Maps.compile("old_garden",[],["elemental_aegis","frost_patrol"]).ok,"Special slot remains exclusive")
	check(Maps.special_template(profile,{"template":"brute","rarity":"normal","mechanisms":[]}).is_empty(),"Defense special does not become a species substitution")
	print("Map defense rules: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
