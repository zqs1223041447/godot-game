class_name CombatCueRenderer
extends RefCounted
## Each spell has a silhouette, cadence, and hit language. No full-screen flashes.
## Low effects keeps complete beams, destinations, cast glyphs, and area boundaries.
const GROUND: Array[String] = ["nova","ward","meteor","explosion","dash","death"]

static func render(canvas: CanvasItem, cues: Array[Dictionary], effects: int, ground: bool) -> void:
	for cue: Dictionary in cues:
		if GROUND.has(str(cue.kind)) != ground:
			continue
		_draw_cue(canvas,cue,effects)

static func _polygon(canvas: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	canvas.draw_colored_polygon(points,color)

static func _regular(center: Vector2, radius: float, sides: int, angle: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in range(sides+1):
		points.append(center+Vector2.RIGHT.rotated(angle+i*TAU/sides)*radius)
	return points

static func _draw_cue(canvas: CanvasItem, cue: Dictionary, effects: int) -> void:
	var p: Vector2 = cue.origin
	var t: float = clampf(float(cue.age)/float(cue.duration),0,1)
	var fade: float = 1-t
	var color: Color = cue.color
	color.a *= minf(1,fade*2)
	var r: float = cue.radius
	var dir: Vector2 = cue.direction
	var side: Vector2 = dir.orthogonal()
	match str(cue.kind):
		"cast":
			var center := p+dir*25
			var radius := lerpf(7,19,t)
			var skill: String = cue.skill
			if skill == "frost":
				for i: int in range(6):
					var v := Vector2.RIGHT.rotated(i*TAU/6)
					canvas.draw_line(center+v*radius*0.4,center+v*radius,color,1.7,true)
			elif skill == "tornado":
				for i: int in range(2):
					canvas.draw_arc(center,radius-i*4,t*PI+i*PI,t*PI+i*PI+PI*0.75,18,color,1.5,true)
			else:
				canvas.draw_polyline(_regular(center,radius,4,dir.angle()+PI/4),color,1.7,true)
			if effects > 0:
				canvas.draw_circle(center,radius,Color(color,color.a*0.06))
		"nova":
			# Immediate thin boundary tells the actual damage footprint; pulse expands inside it.
			canvas.draw_arc(p,r,0,TAU,64,Color(color,color.a*0.45),1.3,true)
			var wave := lerpf(6,r,sqrt(t))
			canvas.draw_arc(p,wave,0,TAU,64,color,2.5,true)
			var spokes: int = 6 if effects == 0 else 12
			for i: int in range(spokes):
				var v := Vector2.RIGHT.rotated(i*TAU/spokes)
				canvas.draw_polyline(PackedVector2Array([p+v*wave*0.7,p+v*wave+v.orthogonal()*5,p+v*(wave+8)]),Color(color,color.a*0.7),1.5,true)
			if effects == 2:
				canvas.draw_arc(p,maxf(2,wave-9),0,TAU,64,Color(color,color.a*0.15),5,true)
		"ward":
			var radius := lerpf(24,r,t*0.5)
			var shield := _regular(p,radius,6,-PI/2)
			canvas.draw_polyline(shield,color,2,true)
			canvas.draw_arc(p,radius+5,0,TAU,48,Color(color,color.a*0.45),1,true)
			for i: int in range(6):
				var v: Vector2 = (shield[i]-p).normalized()
				canvas.draw_line(p+v*(radius-5),p+v*(radius+4),color,2,true)
			if effects > 0:
				_polygon(canvas,shield,Color(color,color.a*0.06))
		"meteor", "explosion":
			var meteor: bool = cue.kind == "meteor"
			var wave: float = lerpf(8,r,sqrt(t))
			canvas.draw_arc(p,r,0,TAU,64,Color(color,color.a*0.35),1,true)
			canvas.draw_arc(p,wave,0,TAU,64,color,2.5 if meteor else 1.8,true)
			var spokes: int = 10 if meteor else 6
			for i: int in range(spokes):
				var v := Vector2.RIGHT.rotated(i*TAU/spokes+float(cue.id%5)*0.17)
				canvas.draw_line(p+v*wave*0.6,p+v*wave,color,2 if meteor else 1.2,true)
			if meteor:
				var core: float = (1-t)*r*0.28
				_polygon(canvas,_regular(p,core,7,-PI/2),Color("ffd69a")*Color(1,1,1,fade))
			if effects > 0:
				canvas.draw_circle(p,wave,Color(color,color.a*0.04))
			if effects == 2:
				canvas.draw_arc(p,maxf(1,wave-7),0,TAU,64,Color(color,color.a*0.2),6,true)
		"chain":
			var end: Vector2 = cue.destination
			var axis := end-p
			var normal := axis.normalized().orthogonal()
			var points := PackedVector2Array([p])
			var pieces: int = clampi(ceili(axis.length()/30),3,18)
			for i: int in range(1,pieces):
				var offset: float = sin(i*2.73+float(cue.id)*0.7)*minf(10,axis.length()*0.05)
				points.append(p.lerp(end,float(i)/pieces)+normal*offset)
			points.append(end)
			canvas.draw_polyline(points,Color(0.025,0.04,0.05,color.a*0.9),5,true)
			canvas.draw_polyline(points,color,2.5,true)
			canvas.draw_polyline(points,Color(0.92,0.98,1,color.a),1,true)
			canvas.draw_arc(end,6+8*t,0,TAU,24,color,1.8,true)
			if effects == 2:
				for i: int in range(2,points.size()-1,3):
					canvas.draw_line(points[i],points[i]+normal*(8 if i%2 else -8),Color(color,color.a*0.6),1,true)
		"dash":
			var end: Vector2 = cue.destination
			var axis := (end-p).normalized()
			var normal := axis.orthogonal()*7*fade
			_polygon(canvas,PackedVector2Array([p,p+normal,end+normal*0.3,end,end-normal*0.3,p-normal]),Color(color,color.a*0.20))
			canvas.draw_line(p,end,Color(color,color.a*0.8),1.5,true)
			for center: Vector2 in [p,end]:
				canvas.draw_polyline(PackedVector2Array([center-axis*5+axis.orthogonal()*9,center+axis*4,center-axis*5-axis.orthogonal()*9]),color,2,true)
		"impact":
			if bool(cue.shielded):
				canvas.draw_polyline(_regular(p,r*(0.6+t*0.6),6),Color(0.64,0.83,0.98,color.a),1.6,true)
			else:
				for i: int in range(4):
					var v := Vector2.RIGHT.rotated(PI/4+i*PI/2)
					canvas.draw_line(p+v*r*0.25,p+v*r*(0.7+t*0.8),Color(0.99,0.92,0.75,color.a),2,true)
			if effects == 2:
				canvas.draw_circle(p,r*0.7,Color(color,color.a*0.08))
		"hurt":
			var hurt: Color = Color("98d3ef") if bool(cue.shielded) else Color("f49b86")
			hurt.a = color.a
			var radius: float = 22+6*t
			for i: int in range(4):
				var corner := Vector2(1,1).rotated(i*PI/2)*radius*0.7
				var center := p+corner
				canvas.draw_polyline(PackedVector2Array([center-corner.normalized().rotated(PI/4)*7,center,center-corner.normalized().rotated(-PI/4)*7]),hurt,2.5,true)
		"death":
			var radius: float = r*(0.7+t*0.6)
			for i: int in range(4):
				var angle: float = i*PI/2
				canvas.draw_arc(p,radius,angle+0.15,angle+0.8,10,Color(color,color.a*0.7),1.5,true)
		"split":
			for i: int in range(3):
				var v := Vector2.RIGHT.rotated(i*TAU/3)
				canvas.draw_line(p+v*4,p+v*r*t,color,2,true)
		"return":
			var radius: float = lerpf(r,5,t)
			canvas.draw_arc(p,radius,PI*0.2,PI*1.8,24,color,1.7,true)
			canvas.draw_polyline(PackedVector2Array([p+Vector2(radius,-5),p+Vector2(radius+3,0),p+Vector2(radius-3,0)]),color,1.5,true)
