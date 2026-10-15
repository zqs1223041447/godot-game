extends SceneTree
## Focused scalar model of the candidate; full production equivalence is checked separately.
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Burn=preload("res://scripts/combat/burn_runtime.gd")
var cache:Dictionary={}
var hits:=0
var misses:=0
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func predicted(raw:Variant, resistance:Variant)->Dictionary:
	var key:=var_to_bytes([float(raw),resistance]).hex_encode()
	if cache.has(key):hits+=1;return {"ok":true,"damage_total":cache[key]}
	misses+=1
	var rate:=Defense.incoming_burn(float(raw),resistance,0.0,1.0,"monster")
	if rate.ok and is_finite(float(rate.damage_total)) and cache.size()<Burn.MAX_TARGETS:cache[key]=float(rate.damage_total)
	return rate
func compare(raw:Variant,resistance:Variant)->void:
	var expected:=Defense.incoming_burn(float(raw),resistance,0.0,1.0,"monster")
	var actual:=predicted(raw,resistance)
	check(actual.ok==expected.ok,"Success validation preserved")
	if expected.ok:check(var_to_bytes(float(actual.damage_total))==var_to_bytes(float(expected.damage_total)),"Exact scalar")
	else:check(var_to_bytes(actual)==var_to_bytes(expected),"Uncached failure receipt")
func _initialize()->void:
	for pair:Array in [[5,0],[5.0,0],[5.0,0.0],[5.0,-0.0],[0.0,0.0],[-0.0,0.0],[10.0,-0.5],[5.0,0.75],[5.0,0.9]]:
		compare(pair[0],pair[1]);compare(pair[0],pair[1])
	check(hits>0,"Repeated predictions hit")
	check(var_to_bytes([5.0,0])!=var_to_bytes([5.0,0.0]),"Integer resistance distinct")
	check(var_to_bytes([5.0,0.0])==var_to_bytes([5.0,-0.0]),"Serializer canonicalizes signed zero; both predictions must still match")
	var old_size:=cache.size()
	for pair:Array in [[NAN,0.0],[INF,0.0],[-1.0,0.0],[5.0,NAN],[5.0,INF],[5.0,true],[5.0,"0"]]:
		compare(pair[0],pair[1]);compare(pair[0],pair[1])
	check(cache.size()==old_size,"Invalid and nonfinite never cached")
	compare(1.7976931348623157e308,-1.7976931348623157e308) # Resistance clamp keeps result finite.
	for index:int in range(Burn.MAX_TARGETS*2):compare(float(index)+0.125,0.25)
	check(cache.size()==Burn.MAX_TARGETS,"Bounded capacity")
	var old_misses:=misses;compare(99999.0,0.25);compare(99999.0,0.25)
	check(misses==old_misses+2,"At-capacity uncached bypass")
	cache.clear()
	for pair:Array in [[5.0,0.0],[8.0,0.0],[8.0,0.5],[5.0,0.0]]:compare(pair[0],pair[1])
	for start:float in [0.0,1.0,1000000.0]:
		for health:float in [1.0e-300,1.0,50.0]:
			var raw:=1.0e100
			var exact:float=Defense.incoming_burn(raw,0.0,0.0,1.0,"monster").damage_total
			var cached:float=predicted(raw,0.0).damage_total
			check(var_to_bytes(start+health/exact)==var_to_bytes(start+health/cached),"Death boundary ULP arithmetic identical")
	print("CACHE20261015_EDGES checks=",checks," hits=",hits," misses=",misses," capacity=",Burn.MAX_TARGETS," failures=",failures)
	quit(1 if failures else 0)
