extends SceneTree
const Runtime=preload("res://scripts/combat/leech_runtime.gd")
const Rules=preload("res://scripts/combat/leech_rules.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
var checks:=0
var failures:=0
const MAXIMA={"health":100.0,"mana":100.0}
const EMPTY={"health":0.0,"mana":0.0}
const CAPS={"health":20.0,"mana":20.0}
const PACKET={"tags":["attack","hit"]}

func _init()->void:
	call_deferred("_run")

func _run()->void:
	var frozen:=_profile()
	var runtime=Runtime.new()
	var gain:Dictionary=runtime.admit(PACKET,frozen,_hit(100.0),EMPTY,MAXIMA)
	_check(gain.ok and gain.health==10.0 and gain.mana==10.0,"actual hit creates capped dual budget")
	_check(runtime.snapshot().health.rate==2.0,"frozen individual rate")
	_check(runtime.advance(0.0,EMPTY,MAXIMA,CAPS).health==0.0,"no instant recovery")
	gain=runtime.advance(0.5,EMPTY,MAXIMA,CAPS)
	_near(gain.health,1.0,"partial tick")
	_near(gain.mana,1.0,"independent mana partial tick")
	gain=runtime.advance(7.0,{"health":1.0,"mana":1.0},MAXIMA,CAPS)
	_near(gain.health,9.0,"expiry only remaining duration, no whole-frame overshoot")
	_check(runtime.is_empty(),"expiry removes both ledgers")
	_check(runtime.advance(20.0,EMPTY,MAXIMA,CAPS).health==0.0,"expired budget cannot return")
	# 20 simultaneous instances have 200 budget but a 10/s cap yields only 50.
	runtime.clear()
	for i:int in range(20):_check(runtime.admit(PACKET,frozen,_hit(100.0),EMPTY,MAXIMA).ok,"crowd admission")
	gain=runtime.advance(5.0,EMPTY,MAXIMA,{"health":10.0,"mana":10.0})
	_near(gain.health,50.0,"capped portion discarded while expiry continues")
	_check(runtime.is_empty() and runtime.advance(1.0,EMPTY,MAXIMA,CAPS).mana==0.0,"no delayed capped reservoir")
	# Expiries inside a frame: 2/s + 2/s under 3/s for first second, then 2/s.
	var one=Runtime.new();var split=Runtime.new()
	for ledger in [one,split]:
		ledger.admit(PACKET,frozen,_hit(20.0),EMPTY,MAXIMA)
		ledger.admit(PACKET,frozen,_hit(60.0),EMPTY,MAXIMA)
	var limited={"health":3.0,"mana":3.0}
	var whole:Dictionary=one.advance(3.0,EMPTY,MAXIMA,limited)
	var first:Dictionary=split.advance(1.5,EMPTY,MAXIMA,limited)
	var second:Dictionary=split.advance(1.5,{"health":first.health,"mana":first.mana},MAXIMA,limited)
	_near(whole.health,7.0,"piecewise capped expiry integral")
	_near(first.health+second.health,whole.health,"frame partition invariance")
	_near(first.mana+second.mana,whole.mana,"mana frame partition invariance")
	# Fullness invalidates only that resource, including at admission.
	runtime.clear();runtime.admit(PACKET,frozen,_hit(100.0),EMPTY,MAXIMA)
	_check(runtime.clear_full({"health":100.0,"mana":0.0},MAXIMA),"full clear accepted")
	_check(runtime.snapshot().health.expiries.is_empty() and not runtime.snapshot().mana.expiries.is_empty(),"one resource does not clear the other")
	gain=runtime.admit(PACKET,frozen,_hit(100.0),{"health":100.0,"mana":0.0},MAXIMA)
	_check(gain.health==0.0 and gain.mana==10.0,"full resource cannot prebank new hit")
	gain=runtime.advance(1.0,{"health":99.0,"mana":0.0},MAXIMA,CAPS)
	_check(gain.health==0.0 and gain.mana==4.0,"spending after full cannot revive old budget")
	runtime.clear();runtime.admit(PACKET,frozen,_hit(100.0),EMPTY,MAXIMA)
	gain=runtime.advance(1.0,{"health":99.0,"mana":0.0},MAXIMA,CAPS)
	_check(gain.health==1.0 and runtime.snapshot().health.expiries.is_empty(),"reaching full during interval clears residual")
	_near(gain.mana,2.0,"other resource still advances full interval")
	# Frozen rate/budget survive a cap change; only the shared current cap changes.
	runtime.clear();runtime.admit(PACKET,frozen,_hit(100.0),EMPTY,MAXIMA)
	frozen.leech.health.instance_rate=200.0
	gain=runtime.advance(1.0,EMPTY,MAXIMA,{"health":1.0,"mana":1.0})
	_near(gain.health,1.0,"caller mutation cannot change admitted rate")
	gain=runtime.advance(1.0,{"health":1.0,"mana":1.0},MAXIMA,CAPS)
	_near(gain.health,2.0,"current cap changes without resetting frozen duration")
	# Invalid operations are atomic, even if current health would otherwise clear.
	var before:=var_to_bytes(runtime.snapshot())
	var bad:=_profile();bad.leech.health.instance_rate=0.0
	_check(not runtime.admit(PACKET,bad,_hit(100.0),{"health":100.0,"mana":0.0},MAXIMA).ok,"zero rate rejected")
	_check(before==var_to_bytes(runtime.snapshot()),"failed admission leaves both resources exact")
	for invalid:Dictionary in [{"health":NAN,"mana":20.0},{"health":-1.0,"mana":20.0},{"health":true,"mana":20.0},{"health":20.0,"mana":20.0,"extra":1}]:
		_check(not runtime.advance(1.0,{"health":100.0,"mana":0.0},MAXIMA,invalid).ok,"invalid cap rejected")
		_check(before==var_to_bytes(runtime.snapshot()),"invalid cap doesn't clear full resource")
	_check(not runtime.advance(NAN,EMPTY,MAXIMA,CAPS).ok,"NaN delta rejected")
	_check(not runtime.clear_full({"health":101.0,"mana":0.0},MAXIMA),"invalid current resource rejected")
	_check(before==var_to_bytes(runtime.snapshot()),"invalid resource state is atomic")
	# No RNG consumed, no mutation of any argument, including nested profile.
	var inputs: Array=[PACKET,_profile(),_hit(100.0),EMPTY,MAXIMA]
	var input_bytes:=var_to_bytes(inputs)
	seed(40040);var expected:=randi();seed(40040)
	runtime.clear();runtime.admit(inputs[0],inputs[1],inputs[2],inputs[3],inputs[4]);runtime.advance(0.1,EMPTY,MAXIMA,CAPS)
	_check(randi()==expected,"independent of global RNG")
	_check(var_to_bytes(inputs)==input_bytes,"all input dictionaries preserved")
	# Heap stresses mixed expiry order without scanning live instances per frame.
	runtime.clear()
	var budget:=0.0
	for i:int in range(1000):
		var damage:float=1.0+float((i*37)%90)
		budget+=damage*0.1
		runtime.admit(PACKET,_profile(),_hit(damage),EMPTY,MAXIMA)
	gain=runtime.advance(6.0,EMPTY,{"health":100000.0,"mana":100000.0},{"health":100000.0,"mana":100000.0})
	_near(gain.health,budget,"heap adversarial insertion/expiry exact budget")
	_check(runtime.is_empty(),"all crowded expiries reclaimed")
	runtime.admit(PACKET,_profile(),_hit(50.0),EMPTY,MAXIMA);runtime.clear()
	_check(runtime.snapshot()==Runtime.new().snapshot(),"run reset returns canonical empty state")
	print("Leech runtime: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func _profile()->Dictionary:
	var current:=Rules.profile({"max_health":100.0,"max_mana":100.0,"attack_life_leech":0.1,"attack_mana_leech":0.1})
	return {"leech":{"health":current.health,"mana":current.mana}}

func _hit(amount:float)->Dictionary:
	return Defense.incoming_hit({"physical":amount},{},0.0,100000.0,"monster")

func _near(actual:float,expected:float,label:String)->void:
	_check(absf(actual-expected)<=maxf(0.00000001,absf(expected)*0.000000001),label+" got %s expected %s"%[actual,expected])

func _check(condition:bool,label:String)->void:
	checks+=1
	if not condition:failures+=1;push_error(label)
