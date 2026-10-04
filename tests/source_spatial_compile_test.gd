extends SceneTree
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const Preview=preload("res://scripts/combat/damage_preview.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func digest_bytes(bytes:PackedByteArray)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes);return context.finish().hex_encode()
func snapshot(values:Dictionary={})->Dictionary:
	var stats:Dictionary={"damage":20.0};stats.merge(values,true)
	return Combat.snapshot(stats,["return_on_range","explode_on_flight_end"])
func _initialize()->void:
	var file:=FileAccess.open("res://tests/fixtures/v032_spatial/zero-spatial-v31.bin",FileAccess.READ)
	var records:Array=file.get_var(false);var baseline_casts:=0
	for record:Dictionary in records:
		for row:Dictionary in record.casts:
			var result:Dictionary=Compiler.compile_group(row.skill,record.snapshot,row.supports)
			baseline_casts+=1;check(result.ok and digest_bytes(var_to_bytes(result))==row.hash,"Frozen v31 zero-increment cast bytes unchanged: "+row.skill)
		var basic:Dictionary=Compiler.compile_basic(record.snapshot)
		check(basic.ok and digest_bytes(var_to_bytes(basic.snapshot))==record.basic_snapshot_hash and basic.recipe.speed==record.basic_speed,"Basic compilation keeps original v31 snapshot bytes and640speed")
	check(baseline_casts==412,"All frozen baseline cases consumed")
	var original:Dictionary=snapshot({"area_size_increased":1.0});var before:=original.duplicate(true)
	for id:String in ["nova","meteor","cleave"]:
		var base:Dictionary=Compiler.compile_skill(id,snapshot(),["breadth","concentrate"])
		var result:Dictionary=Compiler.compile_skill(id,original,["breadth","concentrate"])
		var reverse:Dictionary=Compiler.compile_skill(id,original,["concentrate","breadth"])
		check(result==reverse,"Area support order remains independent")
		check(is_equal_approx(result.recipe.radius,base.recipe.radius*sqrt(2.0)) and is_equal_approx(result.recipe.area_multiplier,2.0*1.44*0.64),"Area increases combine with more-area factors before square root")
		check(result.packets==base.packets and result.mana==base.mana and result.cooldown==base.cooldown,"Geometry never changes damage/mana/cooldown")
		check(result.recipe.source_area_multiplier==2.0 and original==before,"Source marker describes actual multiplier without mutating source")
	for field:String in ["spell_area_size_increased","melee_area_size_increased"]:
		for id:String in ["nova","meteor","cleave"]:
			var result:Dictionary=Compiler.compile_skill(id,snapshot({field:0.25}),[])
			var base:Dictionary=Compiler.compile_skill(id,snapshot(),[])
			var allowed:bool=(field=="melee_area_size_increased")==(id=="cleave")
			check(is_equal_approx(result.recipe.radius,base.recipe.radius*(sqrt(1.25) if allowed else 1.0)),"Area scope uses actual spell/melee role")
	var area_damage:Dictionary=Compiler.compile_skill("nova",snapshot({"area_increased":0.5}),[])
	check(area_damage.recipe==Compiler.compile_skill("nova",snapshot(),[]).recipe,"Old area_increased is still damage, not radius")
	for id:String in ["bolt","frost","shade_bolt"]:
		var base:Dictionary=Compiler.compile_skill(id,snapshot(),["swift_projectiles","heavy_projectiles"])
		var result:Dictionary=Compiler.compile_skill(id,snapshot({"projectile_speed_increased":0.35}),["heavy_projectiles","swift_projectiles"])
		check(is_equal_approx(result.recipe.speed,base.recipe.speed*1.35),"Source speed multiplies the actual existing support product")
		check(result.packets==base.packets and result.initial_count==base.initial_count and result.recipe.slow==base.recipe.slow,"Speed does not change hit packet, count or slow")
		check(Preview.details(result).contains("%.2f"%result.recipe.speed),"Tooltip consumes actual final speed")
	var tornado:Dictionary=Compiler.compile_skill("tornado",snapshot({"projectile_speed_increased":0.5,"area_size_increased":1.0}),[])
	check(tornado.recipe.parent.speed==630.0 and tornado.recipe.child.speed==390.0 and tornado.snapshot.tornado_recipe==tornado.recipe,"Mother and child recipes freeze final velocities once")
	check(tornado.recipe.parent.range==150.0 and tornado.recipe.child.range==150.0 and tornado.recipe.parent.lifetime==0.9 and tornado.recipe.child.lifetime==1.7,"Speed keeps original range and lifetime ceilings")
	check(is_equal_approx(tornado.snapshot.explosion_recipe.radius,76.0*sqrt(2.0)),"Global area changes actual secondary radius")
	check(Preview.details(tornado).contains("630") and Preview.details(tornado).contains("390") and Preview.details(tornado).contains("%.2f"%tornado.snapshot.explosion_recipe.radius),"Tooltip shows actual mother/child and explosion values")
	var only_spell:Dictionary=Compiler.compile_skill("bolt",snapshot({"spell_area_size_increased":0.5}),[])
	check(only_spell.snapshot.explosion_recipe.radius==76.0,"Secondary explosion does not invent a spell tag")
	var basic:Dictionary=Compiler.compile_basic(snapshot({"projectile_speed_increased":-0.2,"area_size_increased":0.44}))
	check(basic.ok and basic.recipe.speed==512.0 and is_equal_approx(basic.snapshot.explosion_recipe.radius,91.2),"Basic attack consumes source reduced-speed and global area")
	check(not Compiler.compile_basic(basic.snapshot).ok and not Compiler.compile_skill("tornado",tornado.snapshot,[]).ok,"Compiled snapshots cannot re-enter source scaling")
	for bad:Variant in [true,NAN,INF,"1.0"]:
		check(not Compiler.compile_skill("bolt",snapshot({"projectile_speed_increased":bad}),[]).ok,"Invalid spatial scalar rejected")
	check(not Compiler.compile_skill("bolt",snapshot({"projectile_speed_increased":-1.0}),[]).ok,"Nonpositive source speed factor rejected")
	check(not Compiler.compile_skill("nova",snapshot({"area_size_increased":1000.0}),[]).ok,"Current radius safety bound remains effective")
	check(not Compiler.compile_skill("bolt",snapshot({"projectile_speed_increased":1000.0}),[]).ok,"Current speed safety bound remains effective")
	print("Source spatial compile: %d checks, %d failures; %d frozen casts"%[checks,failures,baseline_casts]);quit(1 if failures else 0)
