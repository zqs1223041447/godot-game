extends RefCounted
static var enabled:=false
static var calls:Array=[]
static func record(label:String,start:int,end:int)->void:
	if enabled:calls.append([label,start,end,Engine.get_process_frames()])
static func take()->Array:
	var result:=calls;calls=[];return result
