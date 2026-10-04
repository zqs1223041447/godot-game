extends SceneTree
const Catalog=preload("res://scripts/encounters/encounter_catalog.gd")
const Compiler=preload("res://scripts/encounters/encounter_compiler.gd")
const Maps=preload("res://scripts/world/map_compiler.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func selections()->Array:
	var ids:=Catalog.get_ids();var result:Array=[[]]
	for id:String in ids:result.append([id])
	for first:int in range(ids.size()):
		for second:int in range(first+1,ids.size()):result.append([ids[first],ids[second]])
	return result
func _initialize()->void:
	var combos:=selections();check(combos.size()==22 and Catalog.get_ids().size()==6,"Exactly22 legal zero/one/two ordinary selections")
	var map_count:=0
	for map_id:String in Maps.Catalog.MAPS:
		for ids:Array in combos:
			for special:Array in [[],["elemental_aegis"],["frost_patrol"],["storm_patrol"]]:
				var compiled:Dictionary=Maps.compile(map_id,ids,special)
				var expected:bool=not (map_id=="old_garden" and special==["storm_patrol"])
				check(compiled.ok==expected,"Actual map level/exclusive-slot rule governs legality")
				if compiled.ok:map_count+=1;check(Maps.profile_reason(compiled.profile).is_empty(),"All legal profile metadata self-validates")
	check(map_count==154,"154 actual legal map+ordinary+special choices, not a hard-coded approximation")
	seed(31031);var next:=randi();seed(31031)
	for ids:Array in combos:
		var compiled:Dictionary=Compiler.compile(ids);var reverse:=ids.duplicate();reverse.reverse()
		check(compiled.ok and compiled.profile==Compiler.compile(reverse).profile,"Selection input order does not affect complete recipe")
		for template:String in ["crawler","ember_guard","splitter","rift_warden"]:
			var source:Dictionary=Monsters.make_enemy(1,template,5,Vector2(100,100),"map_boss" if template=="rift_warden" else "ordinary")
			var before:=source.duplicate(true);var result:Dictionary=Compiler.apply_to_enemy(source,compiled.profile)
			check(result.ok and source==before,"Candidate preserves original source")
			if not result.ok:continue
			var after:Dictionary=result.enemy
			var hp:=1.2 if ids.has("enemy_max_health_120") else 1.0
			var speed:=1.1 if ids.has("enemy_move_speed_110") else 1.0
			var damage:=1.15 if ids.has("enemy_damage_115") else 1.0
			var attack:=1.1 if ids.has("enemy_attack_speed_110") else 1.0
			var shield:float=source.max_health*0.2 if ids.has("enemy_shield_from_health_20") else 0.0
			check(is_equal_approx(after.max_health,source.max_health*hp) and is_equal_approx(after.health,source.health*hp),"Health multiplier retains original formula")
			check(is_equal_approx(after.speed,source.speed*speed),"Move multiplier retains original formula")
			check(is_equal_approx(after.damage,source.damage*damage) and is_equal_approx(after.attack_speed,source.attack_speed*attack),"Damage and attack rate multiply their original values")
			check(is_equal_approx(after.max_shield,source.max_shield+shield) and is_equal_approx(after.shield,source.shield+shield),"Shield grant always uses unmodified canonical health")
			check(is_equal_approx(after.get("armour",0.0),80.0 if ids.has("enemy_armour_80") else 0.0),"Armour grant is80flat, not a percentage")
			for field:String in source:
				if field not in ["health","max_health","speed","damage","attack_speed","shield","max_shield","armour"]:check(source[field]==after[field],"No identity/template/reward or other-field mutation: "+field)
			check(not Compiler.apply_to_enemy(after,compiled.profile).ok,"One source marker prevents repeated application")
	check(randi()==next,"Whole compilation/application batch uses no global RNG")
	var shield_profile:Dictionary=Compiler.compile(["enemy_max_health_120","enemy_shield_from_health_20"]).profile
	var partial:Dictionary=Monsters.make_enemy(1,"crawler",5,Vector2.ZERO,"ordinary");partial.health*=0.5;partial.max_shield=20.0;partial.shield=5.0
	var bonus:float=partial.max_health*0.2;var after:Dictionary=Compiler.apply_to_enemy(partial,shield_profile).enemy
	check(is_equal_approx(after.max_shield-after.shield,15.0) and is_equal_approx(after.shield,5.0+bonus),"New shield capacity is filled but original missing shield amount remains")
	check(is_equal_approx(after.encounter_source.shield_bonus,partial.max_health*0.2) and not is_equal_approx(after.encounter_source.shield_bonus,after.max_health*0.2),"Strong cannot inflate shield baseline")
	var armour_profile:Dictionary=Compiler.compile(["enemy_armour_80"]).profile;partial.armour=40.0
	after=Compiler.apply_to_enemy(partial,armour_profile).enemy;check(after.armour==120.0,"Flat armour preserves an existing40 baseline")
	for value:Variant in [true,-1.0,NAN,INF]:
		var bad:=partial.duplicate(true);bad.armour=value
		check(not Compiler.apply_to_enemy(bad,armour_profile).ok,"Invalid baseline armour rejected before applying")
	for ids:Array in [["unknown"],["enemy_armour_80","enemy_armour_80"],["enemy_damage_115","enemy_attack_speed_110","enemy_armour_80"]]:check(not Compiler.compile(ids).ok,"Unknown, duplicate and more-than-two selections rejected")
	print("Map modifier batch rules: %d checks, %d failures; %d legal maps"%[checks,failures,map_count]);quit(1 if failures else 0)
