extends SceneTree
const Data=preload("res://scripts/game_data.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Recipes=preload("res://scripts/combat/combat_data.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
const Supports=preload("res://scripts/combat/support_registry.gd")
const Area=preload("res://scripts/combat/area_support_rules.gd")
var checks:=0
var failures:=0
var combinations:=0
func _initialize()->void:
	var snapshot:=Recipes.snapshot({"damage":10.0},[])
	var original:=var_to_bytes(snapshot)
	for skill:String in Data.NEW_SKILL_IDS:
		var available:=Supports.supports_for_skill(skill)
		check(available.size()==(5 if skill=="cleave" else 7),"Explicit real support capability set: "+skill)
		for mask:int in range(1<<available.size()):
			var links:Array=[]
			for bit:int in available.size():
				if mask & (1<<bit):links.append(available[bit])
			if links.size()>5:continue
			var cast:=Compiler.compile_group(skill,snapshot,links);combinations+=1
			check(cast.get("ok",false),"Every admitted new-skill support subset compiles")
			if not cast.get("ok",false):continue
			var reverse:=links.duplicate();reverse.reverse()
			check(cast==Compiler.compile_group(skill,snapshot,reverse),"Order-independent complete recipe and packets")
			check(var_to_bytes(snapshot)==original,"Compiler does not mutate base snapshot")
			check(cast.support_ids.size()==links.size() and cast.mana>0 and cast.cooldown>0,"No silently discarded support or resource cost")
			check(not Compiler.compile_group(skill,cast.snapshot,links).ok,"Frozen cast cannot be compiled a second time")
			var packet:Dictionary=cast.packets.direct if skill=="cleave" else cast.packets.projectile
			check(packet.tags==(["hit","attack","melee","area"] if skill=="cleave" else ["hit","projectile","spell"]),"Actual primary event tags")
			if skill=="cleave":check(is_equal_approx(cast.recipe.half_angle,PI/2),"Area supports preserve angular shape")
			else:check(cast.packets.secondary.tags==["hit","area","secondary","explosion"],"Optional existing explosion remains independent fire event")
		check(not Compiler.compile_group(skill,snapshot,[available[0],available[0]]).ok,"Duplicate support rejected")
		check(not Compiler.compile_group(skill,snapshot,["lingering_chill"]).ok,"Neither new skill pretends to apply frost slow")
	var base_cleave:=Compiler.compile_group("cleave",snapshot,[])
	var base_shade:=Compiler.compile_group("shade_bolt",snapshot,[])
	near(resolved(base_cleave),28.0,"Cleave coefficient consumes current base")
	near(resolved(base_shade),24.0,"Shade intrinsic base is chaos")
	check(base_shade.packets.projectile.base=={"chaos":24.0},"No poison or invented conversion component")
	for stat:String in ["melee_physical_increased","chaos_increased"]:
		var changed:=Recipes.snapshot({"damage":10.0,stat:0.12},[])
		near(resolved(Compiler.compile_group("cleave",changed,[])),28.0*(1.12 if stat=="melee_physical_increased" else 1.0),"Exact melee-only source grant")
		near(resolved(Compiler.compile_group("shade_bolt",changed,[])),24.0*(1.12 if stat=="chaos_increased" else 1.0),"Exact chaos-only source grant")
		for old:String in ["bolt","frost","nova","meteor","chain","tornado"]:
			near(resolved(Compiler.compile_group(old,changed,[])),resolved(Compiler.compile_group(old,snapshot,[])),"Old primary skill gets no unrelated gain")
	var combined:=Compiler.compile_group("cleave",snapshot,["breadth","concentrate","physical_focus","efficiency","quickcast"])
	near(combined.recipe.radius,91.2,"Both opposed area factors use one square root")
	near(resolved(combined),28.0*0.85*1.25*1.2,"Area more now applies to actual melee hit")
	near(combined.mana,12.0*1.2*1.2*1.15*0.8*1.4,"Full five-support mana product")
	near(combined.cooldown,1.4*1.15*0.8,"Resource cooldown product")
	check(not combined.packets.has("secondary"),"Melee does not invent projectile-ending explosions")
	check(not Compiler.compile_group("shade_bolt",snapshot,["physical_focus"]).ok,"Native chaos cannot use physical specialization")
	check(not Compiler.compile_group("cleave",snapshot,["volley"]).ok,"Melee cannot pretend to create projectiles")
	for fixture:Array in [[Vector2(100,0),true],[Vector2(100.01,0),false],[Vector2(0,100),true],[Vector2(-5,40),true],[Vector2(-5.01,40),false],[Vector2(-3,0),true],[Vector2(-40,0),false],[Vector2(105,105),false]]:
		check(Area.contains_sector_target(Vector2.ZERO,Vector2.RIGHT,fixture[0],95.0,PI/2,5.0)==fixture[1],"Exact sector circle/body boundary")
	check(not Area.contains_sector_target(Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,95.0,PI/2,5.0),"Invalid facing rejected")
	check(not Area.contains_sector_target(Vector2.ZERO,Vector2.RIGHT,Vector2.ZERO,NAN,PI/2,5.0),"Nonfinite geometry rejected")
	print("Offense skill batch: %d checks, %d failures, %d legal zero-to-five-support combinations"%[checks,failures,combinations])
	quit(1 if failures else 0)
func resolved(cast:Dictionary)->float:
	var packet:Dictionary=cast.packets.get("direct",cast.packets.get("projectile",cast.packets.get("parent",{})))
	if cast.skill_id=="chain":packet=cast.packets.bounces[0]
	return float(Damage.resolve(packet,cast.snapshot.modifiers).total)
func near(actual:float,expected:float,label:String)->void:check(is_equal_approx(actual,expected),label+" %.8f / %.8f"%[actual,expected])
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
