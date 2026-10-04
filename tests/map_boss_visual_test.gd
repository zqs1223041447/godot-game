extends SceneTree
const Renderer=preload("res://scripts/visuals/telegraph_renderer.gd")
const Settings=preload("res://scripts/visuals/visual_settings.gd")
func _initialize()->void:
	var checks:Array[bool]=[]
	var raw:Dictionary={"source_id":1,"center":Vector2(200,200),"phase":"windup","elapsed":0.45,"profile":{"radius":130.0,"windup_seconds":0.9,"recovery_seconds":1.7}}
	var original:PackedByteArray=var_to_bytes(raw)
	var legacy:Array=Renderer.primitives([raw])
	raw.visual_pattern="unknown"
	checks.append(var_to_bytes(Renderer.primitives([raw]))==var_to_bytes(legacy))
	var patterns:Array=[]
	for pattern:String in ["garden_slam","ruins_mark"]:
		raw.visual_pattern=pattern
		for level:int in [0,1,2]:
			var settings=Settings.new()
			settings.effects_level=level
			var before:PackedByteArray=var_to_bytes(raw)
			var primitives:Array=Renderer.primitives([raw],settings)
			checks.append(primitives.size()<=8)
			checks.append(var_to_bytes(raw)==before)
			var boundaries:=0
			for p:Dictionary in primitives:
				if p.role=="danger_boundary":
					boundaries+=1
					checks.append(p.center==raw.center and p.radius==raw.profile.radius)
				if p.kind=="polyline":
					checks.append(p.points.size()<=6)
					for point:Vector2 in p.points: checks.append(point.distance_to(raw.center)<raw.profile.radius)
			checks.append(boundaries==2)
			if level==0: patterns.append(var_to_bytes(primitives))
	checks.append(patterns[0]!=patterns[1])
	raw.erase("visual_pattern")
	checks.append(var_to_bytes(raw)==original)
	print("Map boss visual: %d checks, %d failures"%[checks.size(),checks.count(false)])
	quit(1 if checks.count(false)>0 else 0)
