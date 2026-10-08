extends SceneTree
## Main's real trace consumer, with downstream effects isolated for alias checks.
class NotifyStub extends CanvasLayer:
	func notify(_message:String)->void:pass
class Arena extends "res://scripts/main.gd":
	var inputs:Array=[]
	func _apply_damage_packet(_enemy:Dictionary,packet:Dictionary,snapshot:Dictionary,_color:Color,_slow:float=0.0,provenance:Dictionary={})->void:
		inputs.append([packet,snapshot,provenance])
	func _flush_monster_spawns()->void:pass
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	var arena:=Arena.new();arena.hud=NotifyStub.new()
	arena.enemies.assign([{"id":1,"health":10.0,"pos":Vector2.ZERO,"radius":12.0,"knockback":Vector2.ZERO}])
	var kinds:Array=["hit","explosion","terrain_hit","return_started","split","terminated","spawn_rejected","evaded"]
	for kind:String in kinds:
		var event:Dictionary={"type":kind,"time":0.0,"sequence":checks,"projectile_id":1,"target_id":1,"pos":Vector2.ZERO,"radius":20.0,"snapshot":{"custom":{"deep":[1,2]}},"payload":{"deep":[3,4]},"color":Color.WHITE,"slow":0.0,"direction":Vector2.RIGHT,"retained":{"list":[{"value":7}],"snapshot":{"keep":true},"payload":["keep"]},"array":[[9]],"packed":PackedInt32Array([2,3])}
		var original:=var_to_bytes(event);var old:Dictionary=event.duplicate(true);old.erase("snapshot");old.erase("payload")
		var events:Array[Dictionary]=[event]
		check(arena._settle_projectile_events(events),kind+" accepted")
		var brief:Dictionary=arena.combat_trace.back()
		check(var_to_bytes(event)==original,kind+" leaves complete input event unchanged")
		check(var_to_bytes(brief)==var_to_bytes(old) and brief.keys()==old.keys(),kind+" exact old record and key order")
		check(not brief.has("snapshot") and not brief.has("payload"),kind+" excludes only top-level fields")
		check(brief.retained.snapshot.keep and brief.retained.payload==["keep"],kind+" preserves nested fields with same names")
		if kind=="hit":
			check(is_same(arena.inputs.back()[0],event.payload) and is_same(arena.inputs.back()[1],event.snapshot) and is_same(arena.inputs.back()[2],event),"Actual hit receives original payload, snapshot and event identities")
		event.retained.list[0].value=99;event.array[0][0]=88;event.packed[0]=44
		check(brief.retained.list[0].value==7 and brief.array[0][0]==9 and brief.packed[0]==2,kind+" nested record isolated from input mutations")
		brief.retained.list[0].value=11;brief.array[0][0]=22;brief.packed[0]=33
		check(event.retained.list[0].value==99 and event.array[0][0]==88 and event.packed[0]==44,kind+" record mutations isolated from input")
	# Missing either/both omitted fields must retain the old silent erase behavior.
	for absent:Array in [["snapshot"],["payload"],["snapshot","payload"]]:
		var event:Dictionary={"type":"terminated","snapshot":{},"payload":{},"retained":[{"value":7}]}
		for key:String in absent:event.erase(key)
		var original:=var_to_bytes(event);var old:=event.duplicate(true);old.erase("snapshot");old.erase("payload")
		var events:Array[Dictionary]=[event]
		check(arena._settle_projectile_events(events) and var_to_bytes(arena.combat_trace.back())==var_to_bytes(old) and var_to_bytes(event)==original,"Missing omitted fields preserve old behavior: "+str(absent))
	arena.combat_trace.clear();arena.event_counts.clear()
	var batch:Array[Dictionary]=[]
	for index:int in range(110):batch.append({"type":"terminated","sequence":index,"snapshot":{},"payload":{},"nested":{"value":index}})
	var before:=var_to_bytes(batch)
	check(arena._settle_projectile_events(batch),"Oversized trace batch accepted")
	check(arena.combat_trace.size()==96 and arena.event_counts.terminated==110,"Original 96-record limit and event counts")
	for index:int in range(96):check(arena.combat_trace[index].sequence==index+14,"Oldest-first trimming preserves event order")
	check(var_to_bytes(batch)==before,"Large input batch remains unchanged")
	arena.hud.free();arena.free()
	print("PROJECTILE_TRACE_COPY: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
