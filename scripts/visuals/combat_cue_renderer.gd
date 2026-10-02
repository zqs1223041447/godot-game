class_name CombatCueRenderer
extends RefCounted
## Each spell has a silhouette, cadence, and hit language. No full-screen flashes.
## Low effects keeps complete beams, destinations, cast glyphs, and area boundaries.
const Palette = preload("res://scripts/visuals/fantasy_palette.gd")
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
	var color: Color = Palette.effect(str(cue.kind),str(cue.skill),Color(cue.color))
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
			# Separate wind-like rune wisps convey the shock front, without a clock-face ring.
			var wave: float=lerpf(6,r,sqrt(t))
			var wisps: int=6 if effects==0 else 8
			for i: int in range(wisps):
				var angle: float=i*TAU/wisps
				var v:=Vector2.RIGHT.rotated(angle)
				var normal:=v.orthogonal()
				var edge: float=wave*(0.92+0.06*sin(i*2.1))
				var curl:=PackedVector2Array([p+v*edge*0.76-normal*7,p+v*edge-normal*4,p+v*(edge+4)+normal*4,p+v*edge*0.9+normal*8])
				canvas.draw_polyline(curl,Color(0.27,0.24,0.31,color.a*0.45),2.8,true)
				canvas.draw_polyline(curl,Color(color,color.a*0.7),1.7,true)
				canvas.draw_line(p+v*(r-4),p+v*r,Color(0.37,0.29,0.42,color.a*0.24),1,true)
				if effects==2:
					canvas.draw_line(p+v*edge*0.55,p+v*edge*0.72,Color(color,color.a*0.2),1.2,true)
		"ward":
			var radius: float=lerpf(22,r,t*0.35)
			var shield:=PackedVector2Array([p+Vector2(-radius*0.65,-radius*0.6),p+Vector2(0,-radius*0.45),p+Vector2(radius*0.65,-radius*0.6),p+Vector2(radius*0.55,radius*0.25),p+Vector2(0,radius*0.75),p+Vector2(-radius*0.55,radius*0.25),p+Vector2(-radius*0.65,-radius*0.6)])
			canvas.draw_polyline(shield,Color(0.19,0.23,0.13,color.a*0.55),3,true)
			canvas.draw_polyline(shield,color,1.4,true)
			canvas.draw_line(p+Vector2(0,-radius*0.2),p+Vector2(0,radius*0.4),color,1.5,true)
			canvas.draw_line(p+Vector2(-radius*0.2,0),p+Vector2(radius*0.2,0),color,1.5,true)
		"meteor", "explosion":
			# Fire reads as a brief ragged burst, not overlapping clock-face rings.
			var meteor: bool=cue.kind=="meteor"
			var wave: float=lerpf(4,r*0.72,sqrt(t))
			var boundary: Color=Color(0.30,0.24,0.14,color.a*0.25)
			# Four discreet end marks retain the true effect extent even in low mode.
			for i: int in range(4):
				var v:=Vector2.RIGHT.rotated(PI/4+i*PI/2)
				canvas.draw_line(p+v*(r-4),p+v*r,boundary,1.1,true)
			var flames: int=4 if effects==0 else 6 if meteor else 5
			for i: int in range(flames):
				var angle: float=i*TAU/flames+float(cue.id%7)*0.23
				var v:=Vector2.RIGHT.rotated(angle)
				var normal:=v.orthogonal()
				var center:=p+v*wave*0.56+Vector2(0,-t*6)
				var length: float=maxf(2,r*(0.17 if meteor else 0.13)*fade)
				var flame:=PackedVector2Array([center-v*length*0.7,center+normal*length*0.4,center+v*length*0.4+normal*length*0.23,center+v*length*1.5,center+v*length*0.45-normal*length*0.28,center-normal*length*0.43])
				_polygon(canvas,flame,Color(color,color.a*0.55))
				canvas.draw_line(center-v*length*0.35,center+v*length*0.9,Color(0.88,0.71,0.40,color.a*0.65),1.3,true)
			if meteor:
				var core: float=lerpf(r*0.16,2,t)
				_polygon(canvas,_regular(p,core,7,-PI/2),Color(0.69,0.38,0.18,color.a*0.5))
				canvas.draw_line(p+Vector2(-core*0.45,-core*0.2),p+Vector2(core*0.35,core*0.15),Color(0.93,0.77,0.49,color.a*0.7),2,true)
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
				canvas.draw_polyline(_regular(p,r*(0.6+t*0.6),6),Color(0.65,0.76,0.79,color.a),1.6,true)
			else:
				for i: int in range(4):
					var v := Vector2.RIGHT.rotated(PI/4+i*PI/2)
					canvas.draw_line(p+v*r*0.25,p+v*r*(0.7+t*0.8),Color(0.99,0.92,0.75,color.a),2,true)
			if effects == 2:
				canvas.draw_circle(p,r*0.7,Color(color,color.a*0.08))
		"hurt":
			var hurt: Color = Color("a6c2c7") if bool(cue.shielded) else Color("d58162")
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
