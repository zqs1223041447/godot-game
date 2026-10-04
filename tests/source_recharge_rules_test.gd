extends SceneTree
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Patterns=preload("res://scripts/passives/source_stat_patterns.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func digest(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
func _initialize()->void:
	for actor:String in ["player","monster"]:
		for base:float in [0.0,8.0,12.5]:
			for rate:float in [0.0,0.1,0.3]:
				for faster:float in [0.0,0.1,0.15,0.2]:
					var input:Dictionary={"shield_regen":base,"shield_recharge_rate_increased":rate,"shield_recharge_start_faster":faster};var before:=input.duplicate(true)
					var result:=Defense.recharge_profile(input,actor)
					check(result.ok and result.base_rate==base and is_equal_approx(result.rate,base*(1.0+rate)) and is_equal_approx(result.delay,4.0/(1.0+faster)),"Both actors use additive rate and inverse faster-start formula")
					check(input==before,"Shared calculator never mutates source")
		for field:String in ["shield_regen","shield_recharge_rate_increased","shield_recharge_start_faster"]:
			for bad:Variant in [true,-0.1,NAN,INF,"0.1"]:check(not Defense.recharge_profile({field:bad},actor).ok,"Bad recharge source rejects atomically")
	check(not Defense.recharge_profile({},"ally").ok,"Unknown actor rejected")
	check(not Defense.recharge_profile({"shield_regen":1e308,"shield_recharge_rate_increased":1e308}).ok,"Computed rate overflow rejected")
	var file:=FileAccess.open("res://tests/fixtures/v033_recharge/zero-recharge-v32.bin",FileAccess.READ);var baseline:Array=file.get_var(false)
	for entry:Dictionary in baseline:
		var actual:=Monsters.make_enemy(23,entry.template,entry.wave,Vector2(105,217),entry.context,entry.rarity,entry.mechanisms)
		check(digest(var_to_bytes(actual))==entry.hash,"Zero increment enemy dictionary exactly equals frozen v32: "+entry.template)
	check(baseline.size()==20,"All frozen default-template and shield-mechanism records consumed")
	for line:String in ["10% increased Energy Shield Recharge Rate","15% faster start of Energy Shield Recharge"]:
		check(Patterns.parse_line(line).supported and not Patterns.parse_line(line,true,false).supported and not Patterns.parse_line(line,false).supported,"New grammar is gated separately from v19 and v20")
		for bad:String in [line+" Recently"," "+line,line+" while on Full Life",line+"\n10% increased Damage",line.replace("10%","-10%").replace("15%","-15%")]:check(not Patterns.parse_line(bad).supported,"Conditional, whitespace, multiline and negative syntax remain locked")
	var opened:=0
	for id:String in SourceTree.Data.standard_ids():
		if SourceTree.node_effect(id,0,20).status!="full" and SourceTree.node_effect(id,0,21).status=="full":opened+=1
	check(opened==10,"Only ten newly fully supported standard nodes unlock")
	for id:String in ["49515","50029","9769"]:check(SourceTree.node_effect(id).status!="full","Remaining suppression/max-resistance effect keeps whole node locked")
	print("Source recharge rules: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
