extends SceneTree
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
const Patterns=preload("res://scripts/passives/source_stat_patterns.gd")
const Preview=preload("res://scripts/combat/damage_preview.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func digest(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
func _initialize()->void:
	var file:=FileAccess.open("res://tests/fixtures/v034_cost/zero-cost-v33.bin",FileAccess.READ);var records:Array=file.get_var(false);var total:=0
	for record:Dictionary in records:
		for row:Dictionary in record.casts:
			var base:=Compiler.compile_group(row.skill,record.snapshot,row.supports);total+=1
			check(base.ok and digest(var_to_bytes(base))==row.hash,"Frozen no-cost source cast byte-equivalent: "+row.skill)
			var snapshot:Dictionary=record.snapshot.duplicate(true);snapshot.resource_modifiers={"mana_cost_efficiency_increased":0.25,"mana_cost_increased":0.15};var source:=snapshot.duplicate(true)
			var cast:=Compiler.compile_group(row.skill,snapshot,row.supports);var reverse:Array=row.supports.duplicate();reverse.reverse()
			check(cast.ok and is_equal_approx(cast.mana,float(base.mana)*1.15/1.25),"Every legal support combination uses the same final cost expression")
			check(cast==Compiler.compile_group(row.skill,snapshot,reverse),"Input support order cannot change cost or compiled content")
			check(cast.packets==base.packets and cast.recipe==base.recipe and cast.cooldown==base.cooldown and cast.initial_count==base.initial_count,"Cost never changes damage, geometry, delivery or cooldown")
			check(snapshot==source and cast.cost_factors.support_mana==base.mana and cast.cost_factors.final_mana==cast.mana,"Cost trace preserves authoritative support-stage cost and input")
		check(digest(var_to_bytes(Compiler.compile_basic(record.snapshot)))==record.basic_cast_hash,"Frozen basic cast remains byte-identical")
	check(total==412,"All frozen legal zero/single/double-support casts consumed")
	for stat:String in Compiler.ResourceCost.STATS:
		for bad:Variant in [-0.1,-1.0,true,NAN,INF,"0.2"]:
			var snapshot:=Combat.snapshot({"damage":20.0,stat:bad},[])
			check(not Compiler.compile_skill("nova",snapshot,[]).ok,"Negative, zero-denominator, bool and nonfinite resource inputs reject")
	var raw:=Combat.snapshot({"damage":20.0},[])
	for bad:Variant in [true,[],{"unknown":0.1},{StringName("mana_cost_increased"):0.1}]:
		var malformed:=raw.duplicate(true);malformed.resource_modifiers=bad;check(not Compiler.compile_skill("ward",malformed,[]).ok,"Malformed resource table rejects even for utility skill")
	check(not Compiler.compile_skill("nova",Combat.snapshot({"damage":20.0,"mana_cost_increased":1e308},[]),[]).ok,"Intermediate cost overflow rejects")
	var high:=Compiler.compile_skill("nova",Combat.snapshot({"damage":20.0,"mana_cost_efficiency_increased":1.0},[]),[])
	check(high.ok and high.mana==12.0,"100percent efficiency halves cost, never linear free casting")
	var free:=Compiler.compile_basic(Combat.snapshot({"damage":20.0,"mana_cost_efficiency_increased":0.5,"mana_cost_increased":0.25},[]))
	check(free.ok and not free.has("mana") and not free.has("cost_factors"),"Basic attack remains cost-free with source attributes")
	check(not Compiler.compile_skill("nova",high.snapshot,[]).ok,"Compiled snapshots cannot multiply resource cost again")
	for line:String in ["8% increased Mana Cost Efficiency","5% increased Mana Cost of Skills"]:
		check(Patterns.parse_line(line).supported and not Patterns.parse_line(line,true,true,false).supported,"New source grammar gated from21")
		for bad:String in [line+" of Spells",line+" Recently"," "+line,line+"\n10% increased Damage"]:check(not Patterns.parse_line(bad).supported,"No unsupported scope/condition/whitespace/multiline wash")
	var opened:=0
	for id:String in SourceTree.Data.standard_ids():
		if SourceTree.node_effect(id,0,21).status!="full" and SourceTree.node_effect(id,0,22).status=="full":opened+=1
	check(opened==9,"Exactly nine newly complete standard nodes")
	print("Source resource compile: %d checks, %d failures; %d frozen casts"%[checks,failures,total]);quit(1 if failures else 0)
