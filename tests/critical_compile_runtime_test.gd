extends SceneTree
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Runtime=preload("res://scripts/combat/critical_strike_runtime.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func digest(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
func _initialize()->void:
	var file:=FileAccess.open("res://tests/fixtures/v034_cost/zero-cost-v33.bin",FileAccess.READ)
	var records:Array=file.get_var(false);var total:=0
	for record:Dictionary in records:
		for row:Dictionary in record.casts:
			var old:=Compiler.compile_group(row.skill,record.snapshot,row.supports);total+=1
			check(old.ok and digest(var_to_bytes(old))==row.hash,"Absent critical preserves frozen compiled bytes: "+row.skill)
			var raw:Dictionary=record.snapshot.duplicate(true)
			raw.critical_modifiers={"base_chance":0.05,"base_multiplier":1.5,"crit_chance_increased":0.2,"crit_multiplier_add":0.1,"spell_crit_chance_increased":0.3,"spell_crit_multiplier_add":0.2,"attack_crit_chance_increased":0.4,"melee_crit_chance_increased":0.6,"melee_crit_multiplier_add":0.4,"projectile_attack_crit_chance_increased":0.8,"projectile_attack_crit_multiplier_add":0.6}
			var before:=var_to_bytes(raw);var cast:=Compiler.compile_group(row.skill,raw,row.supports)
			check(cast.ok and cast.packets==old.packets and cast.recipe==old.recipe and cast.mana==old.mana and cast.cooldown==old.cooldown,"Critical profiles do not alter base packets/cost/cooldown/geometry")
			check(var_to_bytes(raw)==before,"Compiler leaves caller snapshot unchanged")
			var reversed:Array=row.supports.duplicate();reversed.reverse()
			check(cast==Compiler.compile_group(row.skill,raw,reversed),"Support order retains critical profile and complete cast")
			if row.skill in ["dash","ward"]:
				check(not cast.has("critical") and not cast.snapshot.has("critical"),"Utility has no critical profile")
			else:
				var expected_chance:=0.075;var expected_multiplier:=1.8
				if row.skill=="tornado":expected_chance=0.12;expected_multiplier=2.2
				elif row.skill=="cleave":expected_chance=0.11;expected_multiplier=2.0
				check(is_equal_approx(cast.critical.primary.chance,expected_chance) and is_equal_approx(cast.critical.primary.multiplier,expected_multiplier),"Global and matching skill scopes combine once")
				check(cast.snapshot.critical==cast.critical,"Actual execution snapshot owns the same final profile")
				if cast.critical.has("secondary"):
					check(is_equal_approx(cast.critical.secondary.chance,0.06) and is_equal_approx(cast.critical.secondary.multiplier,1.6),"Independent explosion excludes attack/spell/melee/projectile scopes")
				check(not Compiler.compile_group(row.skill,cast.snapshot,row.supports).ok,"Frozen cast cannot double-apply critical compilation")
		check(digest(var_to_bytes(Compiler.compile_basic(record.snapshot)))==record.basic_cast_hash,"Old basic remains byte-identical")
	check(total==412,"All 412 frozen legal zero/single/double support combinations covered")
	var rt:=Runtime.new();rt.reset(771)
	var legacy:=Combat.snapshot({"damage":20.0},[]);var start:=rt.checkpoint()
	check(rt.freeze(legacy).snapshot==legacy and rt.checkpoint()==start,"Old raw snapshot consumes no critical state")
	var zero:=Compiler.compile_basic(Combat.snapshot({"damage":20.0,"crit_base_chance":0.0,"crit_base_multiplier":1.5},[]))
	var zr:=rt.freeze(zero.snapshot)
	check(zr.ok and not zr.snapshot.has("critical_roll") and rt.checkpoint()==start,"Explicit zero probability consumes no RNG or roll fields")
	var all:=Compiler.compile_basic(Combat.snapshot({"damage":20.0,"crit_base_chance":1.0,"crit_base_multiplier":1.5},[]))
	var rolled:=rt.freeze(all.snapshot)
	check(rolled.snapshot.critical_roll.critical and rolled.snapshot.critical_roll.multiplier==1.5 and rt.draws==0 and rt.events==1,"Guaranteed critical uses no needless random draw")
	var no_secondary:Dictionary=rolled.snapshot.duplicate(true);no_secondary.critical.secondary.chance=0.0
	var ns:=rt.freeze(no_secondary,"secondary")
	check(not ns.snapshot.has("critical_roll") and no_secondary.critical_roll.critical,"Zero secondary cannot inherit a critical parent, and original snapshot stays frozen")
	var sample:=Compiler.compile_basic(Combat.snapshot({"damage":20.0,"crit_base_chance":0.5,"crit_base_multiplier":1.5},[]))
	var twin:=Runtime.new();rt.reset(345);twin.reset(345);var positives:=0
	for i:int in range(128):
		var a:=rt.freeze(sample.snapshot);var b:=twin.freeze(sample.snapshot)
		check(a==b and rt.checkpoint()==twin.checkpoint(),"Dedicated same-seed stream deterministic")
		if a.snapshot.critical_roll.critical:positives+=1
	check(positives>0 and positives<128 and rt.draws==128,"Nontrivial seeded sequence covers both outcomes, one draw per event")
	var checkpoint:=rt.checkpoint();var saved:=rt.freeze(sample.snapshot)
	rt.restore(checkpoint);check(rt.freeze(sample.snapshot)==saved,"Rollback reproduces next authoritative result exactly")
	var malformed:Dictionary=sample.snapshot.duplicate(true);malformed.critical.primary.chance=true;checkpoint=rt.checkpoint()
	check(not rt.freeze(malformed).ok and rt.checkpoint()==checkpoint,"Invalid compiled profile fails before a draw")
	var packet:=Damage.packet({"physical":100.0,"fire":50.0},["hit","attack"],"basic")
	var normal:=Damage.resolve(packet,[],{"fire":0.5})
	var critical:=Damage.resolve(packet,[],{"fire":0.5},1.5)
	check(critical.components.physical==150.0 and critical.components.fire==37.5,"Critical multiplies each original component before resistance")
	var armoured:=Defense.apply_armour(critical,500.0)
	check(is_equal_approx(armoured.components.physical,90.0),"Armour consumes 150 damage hit, rather than multiplying already mitigated 100 hit")
	var settled:=Defense.settle_resolved(armoured,40.0,200.0)
	check(settled.ok and settled.shield_spent==40.0 and is_equal_approx(settled.health_lost,87.5),"Shared shield then health settlement receives critical hit")
	check(Damage.resolve(packet,[],{"fire":0.5},1.0)==normal,"Zero-increment damage arithmetic remains exact")
	check(Damage.resolve(packet,[],{},NAN).has("error"),"Malformed critical damage argument fails closed")
	print("Critical compile/runtime: %d checks, %d failures; %d frozen casts"%[checks,failures,total]);quit(1 if failures else 0)
