extends SceneTree
const Runtime=preload("res://scripts/combat/flask_runtime.gd")
const Rules=preload("res://scripts/combat/flask_modifier_rules.gd")
const Patterns=preload("res://scripts/passives/source_stat_patterns.gd")
const SourceTree=preload("res://scripts/passives/source_tree_runtime.gd")
const OWNED={"qa_life":"flask:life","qa_mana":"flask:mana"}
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func drain(runtime:RefCounted,uid:String)->void:
	for i:int in range(3):check(runtime.use(uid,0.0,100.0).ok,"Three ordinary uses consume the real initial30 charges");runtime.clear_effects()
func records()->Array:
	var runtime:=Runtime.new();var result:Array=[]
	result.append(runtime.reset(OWNED));result.append(runtime.snapshot());result.append(runtime.use("qa_life",100.0,100.0));result.append(runtime.snapshot())
	result.append(runtime.use("qa_life",10.0,100.0));result.append(runtime.snapshot());result.append(runtime.use("qa_life",10.0,100.0));result.append(runtime.snapshot())
	result.append(runtime.advance(0.7,{"health":10.0,"mana":10.0},{"health":100.0,"mana":140.0}));result.append(runtime.snapshot())
	result.append(runtime.use("qa_mana",15.0,140.0));result.append(runtime.snapshot());runtime.charge_rewarded_kill(["qa_life","qa_life","qa_mana"]);result.append(runtime.snapshot())
	result.append(runtime.advance(1.8,{"health":18.0,"mana":15.0},{"health":100.0,"mana":140.0}));result.append(runtime.snapshot())
	result.append(runtime.sync_owned({"qa_life":"flask:life"}));result.append(runtime.snapshot());result.append(runtime.advance(2.0,{"health":39.0,"mana":45.0},{"health":100.0,"mana":140.0}));result.append(runtime.snapshot())
	for i:int in range(35):runtime.charge_rewarded_kill(["qa_life"])
	result.append(runtime.snapshot());runtime.clear_effects();result.append(runtime.snapshot());result.append(runtime.reset(OWNED));result.append(runtime.snapshot());return result
func _initialize()->void:
	var file:=FileAccess.open("res://tests/fixtures/v035_flasks/zero-flask-v34.bin",FileAccess.READ);var prior:Array=file.get_var(false);var current:=records()
	check(prior.size()==23 and current.size()==23,"All23 frozen v34 trajectory records loaded")
	for i:int in range(23):check(var_to_bytes(prior[i])==var_to_bytes(current[i]),"Zero increment runtime bytes unchanged at step%d"%i)
	for id:String in ["flask:life","flask:mana"]:
		for bonus:float in [0.0,0.1,0.5]:
			var field:String="flask_life_recovery_increased" if id=="flask:life" else "flask_mana_recovery_increased"
			var profile:=Rules.profile(id,{field:bonus},100.0)
			check(profile.ok and is_equal_approx(profile.recovery_total,35.0*(1.0+bonus)) and profile.duration==3.0 and profile.cost==10 and profile.max_charges==30,"Recovery scales the one matching resource and keeps duration/cost")
	check(Rules.profile("flask:life",{"flask_mana_recovery_increased":1.0},100.0).recovery_total==35.0,"Mana recovery increase cannot affect life bottle")
	check(Rules.profile("flask:mana",{"flask_life_recovery_increased":1.0},100.0).recovery_total==35.0,"Life recovery increase cannot affect mana bottle")
	var runtime:=Runtime.new();runtime.reset(OWNED);var stats:Dictionary={"flask_life_recovery_increased":0.5}
	check(runtime.use("qa_life",0.0,100.0,stats).ok,"Boosted recovery admitted")
	stats.flask_life_recovery_increased=3.0
	check(is_equal_approx(runtime.advance(3.0,{"health":0.0,"mana":0.0},{"health":200.0,"mana":100.0}).health,52.5),"Use freezes multiplier and starting maximum despite later changes")
	runtime.reset(OWNED);runtime.use("qa_life",10.0,100.0,{"flask_life_recovery_increased":0.5})
	check(runtime.advance(3.0,{"health":10.0,"mana":0.0},{"health":40.0,"mana":100.0}).health==30.0 and runtime.snapshot().active_by_resource.is_empty(),"Current reduced cap still clamps and finishes recovery")
	for bonus:float in [0.05,0.1,0.15,0.25]:
		runtime.reset(OWNED);drain(runtime,"qa_life")
		var n:int=20 if bonus in [0.05,0.15] else 10 if bonus==0.1 else 4
		for i:int in range(n):runtime.charge_rewarded_kill(["qa_life"],{"flask_charges_gained_increased":bonus})
		check(runtime.snapshot().charges_by_uid.qa_life==roundi(n*(1.0+bonus)) and not runtime.snapshot().has("charge_remainders_micro"),"Exact source percentage accumulation crosses whole-charge boundary")
	runtime.reset(OWNED);drain(runtime,"qa_life");runtime.charge_rewarded_kill(["qa_life","qa_life"],{"flask_charges_gained_increased":0.15})
	check(runtime.snapshot().charges_by_uid.qa_life==1 and runtime.snapshot().charge_remainders_micro.qa_life==150000,"Duplicate equippedUID cannot multiply gain")
	var before:=runtime.snapshot();check(runtime.sync_owned(OWNED) and runtime.snapshot()==before,"Ownership-preserving slot/bag synchronization retains carry")
	var borrowed:=runtime.snapshot();borrowed.charge_remainders_micro.qa_life=0
	check(runtime.snapshot()==before,"Returned carry table is detached")
	runtime.charge_rewarded_kill(["qa_life"])
	check(runtime.snapshot().charges_by_uid.qa_life==2 and runtime.snapshot().charge_remainders_micro.qa_life==150000,"Removing gain modifier does not erase earned fraction")
	before=runtime.snapshot();check(not runtime.sync_owned({"qa_life":"flask:mana"}) and runtime.snapshot()==before,"UID type replacement rejected before carry mutation")
	runtime.sync_owned({"qa_mana":"flask:mana"});check(not runtime.snapshot().has("charge_remainders_micro"),"Lost ownership removes its carry")
	runtime.reset(OWNED);drain(runtime,"qa_life")
	for i:int in range(26):runtime.charge_rewarded_kill(["qa_life"],{"flask_charges_gained_increased":0.15})
	check(runtime.snapshot().charges_by_uid.qa_life==29 and runtime.snapshot().charge_remainders_micro.qa_life==900000,"Pre-cap fraction is exact")
	runtime.charge_rewarded_kill(["qa_life"],{"flask_charges_gained_increased":0.15})
	check(runtime.snapshot().charges_by_uid.qa_life==30 and not runtime.snapshot().has("charge_remainders_micro"),"Reaching cap discards all excess/fraction during that legal reward")
	runtime.charge_rewarded_kill(["qa_life"],{"flask_charges_gained_increased":0.15});runtime.use("qa_life",0.0,100.0);runtime.charge_rewarded_kill(["qa_life"])
	check(runtime.snapshot().charges_by_uid.qa_life==21 and not runtime.snapshot().has("charge_remainders_micro"),"Full bottles cannot bank surplus for later use")
	for field:String in Rules.STATS:
		for bad:Variant in [-0.1,true,NAN,INF,"0.1"]:
			runtime.reset(OWNED);before=runtime.snapshot()
			check(not runtime.use("qa_life",0.0,100.0,{field:bad}).ok and runtime.snapshot()==before,"Invalid modifier use preserves charges and recovery")
			runtime.charge_rewarded_kill(["qa_life"],{field:bad});check(runtime.snapshot()==before,"Invalid reward modifier is atomic")
	for line:String in ["10% increased Life Recovery from Flasks","15% increased Mana Recovery from Flasks","10% increased Flask Charges gained","20% increased Life and Mana Recovery from Flasks"]:
		check(Patterns.parse_line(line).supported and not Patterns.parse_line(line,true,true,true,false).supported,"New flask vocabulary stays behind23 gate")
		for bad:String in [line+" Recently",line+" during Effect",line+"\n5% increased Damage"]:check(not Patterns.parse_line(bad).supported,"Conditional and multiline flask text remains unsupported")
	var opened:=0
	for id:String in SourceTree.Data.standard_ids():
		if SourceTree.node_effect(id,0,22).status!="full" and SourceTree.node_effect(id,0,23).status=="full":opened+=1
	check(opened==10,"Only ten newly complete standard ordinary nodes open")
	print("Source flask rules: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
