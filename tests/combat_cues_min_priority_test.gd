extends SceneTree
## Differential pool semantics against the exact pre-change source, not a rewritten oracle.
const Current=preload("res://scripts/visuals/combat_cues.gd")
const BASELINE="res://docs/qa/combat-cues-min-priority/baseline.gd.txt"
var checks:=0
var failures:Array[String]=[]
var old_script:GDScript
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func state(pool:RefCounted)->PackedByteArray:
	return var_to_bytes([pool.cues,pool.next_id,pool.dropped])
func emit_pair(a:RefCounted,b:RefCounted,kind:String,origin:Vector2,data:Dictionary,label:String)->void:
	var old_id:int=b.next_id
	var left:int=a.emit_cue(kind,origin,data)
	var right:int=b.emit_cue(kind,origin,data)
	check(left==right and state(a)==state(b),label+": ordered cues, returned ID, next_id and dropped match baseline")
	check(b.next_id==old_id+int(right!=0),label+": rejection never consumes an ID")
func _initialize()->void:
	old_script=GDScript.new()
	old_script.source_code=FileAccess.get_file_as_string(BASELINE).replace("class_name CombatCues\n","")
	if old_script.reload()!=OK:quit(1);return
	check(Current.PRIORITY.values().min()==Current.MIN_PRIORITY,"Catalog lower bound equals shortcut floor")
	for kind:String in Current.LIFETIMES:
		check(Current.PRIORITY.has(kind) and int(Current.PRIORITY[kind])>=Current.MIN_PRIORITY,"Declared kind obeys floor: "+kind)
	var layouts:Array=[
		["impact"],["death"],["cast"],["nova"],
		["nova","cast","impact","death"],
		["cast","nova","impact"],["nova","impact","cast"]]
	for layout:Array in layouts:
		for kind:String in Current.LIFETIMES:
			var a:RefCounted=old_script.new();var b:=Current.new()
			for i:int in range(Current.MAX_CUES):
				var initial:String=layout[i%layout.size()]
				a.emit_cue(initial,Vector2(i,0));b.emit_cue(initial,Vector2(i,0))
			check(state(a)==state(b),"Identical full pool fixture")
			emit_pair(a,b,kind,Vector2(99,2),{"half_angle":PI/2},"Full %s incoming %s" % [layout,kind])
			for delta:float in [-1.0,NAN,0.0,0.1,0.1,0.2,0.3]:
				a.advance(delta);b.advance(delta)
				check(state(a)==state(b),"Stable survivor order and expiry, delta=%s" % delta)
			check(b.cues.is_empty(),"All finite lifetime cues expire")
	# Equal-priority earlier entries must not beat a later strictly-lower entry.
	var a:RefCounted=old_script.new();var b:=Current.new()
	for i:int in range(Current.MAX_CUES):
		var kind:String="impact" if i in [7,19] else "nova"
		a.emit_cue(kind,Vector2.ZERO);b.emit_cue(kind,Vector2.ZERO)
	emit_pair(a,b,"nova",Vector2.ZERO,{},"High-priority selection")
	var ids:Array=[]
	for cue:Dictionary in b.cues:ids.append(cue.id)
	check(ids[0]==1 and not ids.has(8) and ids.has(20),"First strictly-lower entry wins over earlier equal and later lower entries")
	# Invalid requests must leave IDs, drop counters and every existing cue untouched.
	var invalid:Array=[
		["unknown",Vector2.ZERO,{}],["impact",Vector2(INF,0),{}],
		["impact",Vector2.ZERO,{"radius":NAN}],["impact",Vector2.ZERO,{"destination":Vector2(NAN,0)}],
		["impact",Vector2.ZERO,{"direction":Vector2(INF,0)}],["impact",Vector2.ZERO,{"color":Color(NAN,0,0)}],
		["cleave",Vector2.ZERO,{}],["cleave",Vector2.ZERO,{"half_angle":0.0}]]
	for row:Array in invalid:
		var before:=state(b)
		emit_pair(a,b,row[0],row[1],row[2],"Invalid input")
		check(state(b)==before,"Invalid input does not mutate full pool")
	a.reset();b.reset();check(state(a)==state(b),"Reset remains exact")
	for i:int in range(Current.MAX_CUES+1):
		emit_pair(a,b,"impact",Vector2(i,0),{},"Below cap, at cap and first overflow")
	var report:={"checks":checks,"failures":failures.size(),"failed_labels":failures,"full_pool_layouts":layouts.size(),"kinds":Current.LIFETIMES.size()}
	var out:=OS.get_environment("CUES_TEST_OUT")
	if not out.is_empty():FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("CUES_MIN_PRIORITY_TEST ",JSON.stringify(report));quit(1 if not failures.is_empty() else 0)
