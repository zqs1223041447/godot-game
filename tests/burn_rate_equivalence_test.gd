extends SceneTree
## Archived candidate test: production was restored after the performance experiment.
## Run only at46dc450 or6f93733, where the evaluated burn_rate API exists.
const Old=preload("res://tests/fixtures/v052/defense_rules_before.gd")
const New=preload("res://scripts/mechanics/defense_rules.gd")
var checks:=0
var failures:=0
var cases:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func compare(raw:Variant,resistance:Variant,shield:Variant,health:Variant,actor:String)->void:
	cases+=1
	var input:=var_to_bytes([raw,resistance,shield,health,actor])
	var old:Dictionary=Old.incoming_burn(raw,resistance,shield,health,actor)
	var fresh:Dictionary=New.incoming_burn(raw,resistance,shield,health,actor)
	check(var_to_bytes(old)==var_to_bytes(fresh),"Complete settlement/error byte equality case%d"%cases)
	check(input==var_to_bytes([raw,resistance,shield,health,actor]),"Inputs unchanged")
	var reference:Dictionary=Old.incoming_burn(raw,resistance,0.0,1.0,actor)
	var rate:Dictionary=New.burn_rate(raw,resistance,actor)
	check(rate.ok==reference.ok,"Rate admission equality")
	if rate.ok:
		check(var_to_bytes(rate.damage_total)==var_to_bytes(reference.damage_total),"Exact effective rate including signed-zero rounding")
		var again:=var_to_bytes(New.burn_rate(raw,resistance,actor))
		rate.effective_resistances.fire=-99.0;rate.raw_resistances.clear();rate.damage_total=-3.0
		check(var_to_bytes(New.burn_rate(raw,resistance,actor))==again,"Returned rate profile detached")
	else:check(var_to_bytes(rate)==var_to_bytes(reference),"Exact validation priority/reason")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v052-"):quit(78);return
	var bits:=PackedByteArray();bits.resize(8);bits.encode_u64(0,1);var smallest:=bits.decode_double(0)
	bits.encode_u64(0,0x7fefffffffffffff);var largest:=bits.decode_double(0)
	for raw:float in [0.0,-0.0,smallest,1e-300,0.1,100.0,largest]:
		for resistance:float in [-1.0,0.0,0.75,2.0]:
			for actor:String in ["player","monster"]:
				compare(raw,resistance,0.0,1.0,actor)
				compare(raw,resistance,3.25,100.0,actor)
	for bad:Variant in [null,true,"1",-1.0,NAN,INF,-INF,{}]:
		compare(bad,0.0,0.0,1.0,"monster")
		compare(1.0,bad,0.0,1.0,"monster")
		compare(1.0,0.0,bad,1.0,"monster")
		compare(1.0,0.0,0.0,bad,"player")
		compare(bad,true,-1.0,NAN,"unknown")
		compare(1.0,bad,-1.0,NAN,"unknown")
	compare(1,0,0,1,"monster")
	compare(1.0,0.2,0.0,1.0,"unknown")
	compare(1.0,true,-1.0,-1.0,"monster")
	seed(52117);var expected: Array=[randi(),randi(),randi()];seed(52117)
	New.burn_rate(12.0,0.25,"monster");New.incoming_burn(12.0,0.25,2.0,30.0,"player");New.burn_rate(true,0.0,"unknown")
	check([randi(),randi(),randi()]==expected,"No global RNG use")
	var result:Dictionary={"checks":checks,"cases":cases,"failures":failures,"pure_byte_equivalence":true,"scope":"Frozen original DefenseRules, rate vs original dummy settlement, full real settlement/error priority, exact doubles and detached profile; no gameplay performance claim"}
	var path:=OS.get_environment("V052_RULE_RESULT");if not path.is_empty():FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print(JSON.stringify(result));quit(1 if failures else 0)
