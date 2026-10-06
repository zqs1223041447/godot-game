extends SceneTree
const Frozen=preload("res://docs/qa/v063-settlement-rules/frozen/scripts/mechanics/defense_rules.gd")
func _initialize()->void:
	var cases:Array=[
		[20.0,0.25,5.0,9.0,"monster"],
		[-0.0,-0.0,-0.0,-0.0,"monster",NAN,-0.0,0],
		[0.4,0.75,0.2,100.0,"monster"],
		[100.0,0.25,NAN,NAN,"monster",0.0,0.0,NAN],
		[100.0,0.25,5.0,20.0,"player"],
		[100.0,0.25,5.0,20.0,"monster",10.0,0.4,0.08],
		[1.0,true,-1.0,2.0,"monster"]]
	var old:=Frozen.new();var vectors:Array=[]
	for args:Array in cases:vectors.append({"args":args,"expected":old.callv("incoming_burn",args)})
	var file:=FileAccess.open("res://docs/qa/v063-integration/packed-golden.bin",FileAccess.WRITE);file.store_buffer(var_to_bytes(vectors));file.close()
	print("Exported ",vectors.size()," frozen-v62 typed return vectors; no current gameplay executed");quit(0)
