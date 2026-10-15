extends SceneTree
const Current=preload("res://scripts/combat/burn_runtime.gd")
const Before=preload("res://docs/qa/burn-state-copy-20261015/frozen/burn_runtime.gd")
var current:=Current.new()
var before:=Before.new()
var checks:=0
var failures:=0
func _initialize()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v050-"):quit(78);return
	run();ownership();print("Burn state copy equivalence: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func observe(label:String)->void:
	check(var_to_bytes(current._states)==var_to_bytes(before._states),label+": internal semantic state bytes")
	check(var_to_bytes(current.statuses())==var_to_bytes(before.statuses()),label+": detached sorted status bytes")
	var latest:float=-1.0
	for state:Dictionary in before.statuses():
		if state.target_kind=="monster":latest=maxf(latest,float(state.last_time))
	check(current.latest_monster_time()==latest,label+": scalar clock equals copied baseline")
func pair(method:String,args:Array)->void:
	var a:Variant=current.callv(method,args);var b:Variant=before.callv(method,args)
	check(var_to_bytes(a)==var_to_bytes(b),method+": exact result including typed empty arrays")
	observe(method)
func provenance(at:float,duration:float)->Dictionary:return {"ember_generation":0,"ember_expiry":at+duration,"skill_id":"meteor","cast_id":1}
func run()->void:
	observe("empty")
	pair("apply",["player",0,3,10.0,3.0,1.0])
	pair("apply",["monster",10,0,2.0,0.3,0.1])
	pair("apply",["monster",2,0,2.0,0.3,0.1,provenance(0.1,0.3)])
	pair("advance_target",["monster",2,0.1]);pair("advance_target",["monster",10,0.1])
	check(current.status_for("monster",2).remaining==0.3,"Zero-width retains original literal remaining exactly")
	var shifted:=provenance(0.1,0.3);shifted.ember_expiry+=0.0000000001
	pair("apply",["monster",2,0,3.0,0.3,0.1,shifted]);pair("advance_target",["monster",2,0.1])
	pair("apply",["monster",2,0,4.0,0.3,0.1]);pair("apply",["monster",2,0,1.0,0.3,0.1])
	var state_bytes:=var_to_bytes(current._states);var detached:=current.statuses();detached[0].raw_dps=999.0;detached[0].provenance["skill_id"]="changed";detached.reverse();detached.clear()
	check(var_to_bytes(current._states)==state_bytes,"Public array, state and provenance cannot mutate cached/internal data")
	pair("remove",["monster",2]);pair("remove",["monster",2]);pair("apply",["monster",2,0,5.0,0.1,0.2])
	pair("advance_target",["monster",2,0.3]);pair("advance_target",["monster",2,0.3000000000000001])
	pair("advance_all",[0.4]) # Player at1 rejects atomically after earlier target plans.
	pair("advance_all",[4.0]);pair("reset",[])
	for id:int in range(100,0,-1):pair("apply",["monster",id,0,1.0,1.0,0.0])
	pair("apply",["player",0,0,1.0,1.0,0.0]);pair("apply",["monster",101,0,1.0,1.0,0.0])
	pair("apply",["monster",2,0,2.0,1.0,0.0]);pair("advance_all",[1.0]);pair("reset",[])
	pair("apply",["monster",1,0,1.0,1.0,0.0]);pair("apply",["monster",2,0,1e-300,1.0,0.0])
	pair("advance_all",[1e-30]);pair("advance_target",["monster",2,0.0]);pair("reset",[])
	for args:Array in [["monster",0,0.0],["monster",1,-1.0],["monster",1,true],["monster",1,NAN],["bad",1,0.0]]:pair("advance_target",args)
	for at:float in [0.0,0.1,1000000.0]:
		pair("reset",[]);pair("apply",["monster",10,0,8.0,3.0,at,provenance(at,3.0)])
		for index:int in range(16):pair("advance_target",["monster",10,at])
		pair("advance_target",["monster",10,at+0.2]);pair("apply",["monster",10,0,7.0,3.0,at+0.2,provenance(at+0.2,3.0)])
		pair("advance_target",["monster",10,at+0.1]);pair("advance_target",["monster",10,at+3.0])

func ownership()->void:
	pair("reset",[])
	var p:Dictionary=provenance(0.0,3.0)
	pair("apply",["monster",1,7,8.0,3.0,0.0,p])
	var stable:PackedByteArray=var_to_bytes(current._states)
	p.skill_id="caller mutation"
	check(var_to_bytes(current._states)==stable,"Caller provenance detached")
	var retained:Dictionary=current.status_for("monster",1)
	var retained_bytes:PackedByteArray=var_to_bytes(retained)
	var segments:Dictionary=current.advance_target("monster",1,0.5)
	var reference:Dictionary=before.advance_target("monster",1,0.5)
	check(var_to_bytes(segments)==var_to_bytes(reference),"Owned segments exact")
	stable=var_to_bytes(current._states)
	segments.segments[0].provenance.skill_id="segment mutation"
	check(var_to_bytes(current._states)==stable,"Segment provenance detached")
	for rate:float in [7.0,8.0,9.0]:pair("apply",["monster",1,9,rate,3.0,0.5,provenance(0.5,3.0)])
	pair("advance_target",["monster",1,1.0])
	check(var_to_bytes(retained)==retained_bytes,"Retained public snapshot survives advance and replacement")
	stable=var_to_bytes(current._states)
	retained.provenance.skill_id="snapshot mutation"
	check(var_to_bytes(current._states)==stable,"status_for provenance detached")
	for at:float in [NAN,INF,-INF,0.9]:
		stable=var_to_bytes(current._states);pair("advance_target",["monster",1,at]);check(var_to_bytes(current._states)==stable,"Invalid target advance atomic")
	pair("apply",["monster",2,0,1.0,3.0,2.0])
	stable=var_to_bytes(current._states);pair("advance_all",[1.5]);check(var_to_bytes(current._states)==stable,"Later reverse-clock batch failure atomic")
	pair("advance_all",[5.0]);pair("remove",["monster",1]);pair("reset",[])
	pair("apply",["monster",1,0,1.0,1.0,-0.0]);pair("advance_target",["monster",1,0.0]);pair("reset",[])
	pair("apply",["monster",1,0,1.0,1.0,0.0]);pair("apply",["monster",2,0,1e-300,1.0,0.0])
	stable=var_to_bytes(current._states);pair("advance_all",[1e-30]);check(var_to_bytes(current._states)==stable,"Later underflow batch failure atomic")
