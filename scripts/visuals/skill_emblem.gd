class_name SkillEmblem
extends Control
## Crisp vector skill language; no raster scaling artifacts on a 2K monitor.
var skill_id: String = "arcane"
var accent := Color("78d9ce")
var subdued: bool = false
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	var center := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.44
	var color: Color = accent.darkened(0.4) if subdued else accent
	draw_circle(center, radius, Color(color, 0.07))
	draw_arc(center, radius, -PI*0.75, PI*0.75, 32, Color(color,0.36), 1, true)
	match skill_id:
		"tornado":
			for i: int in range(3):
				var y := center.y - radius*0.6 + i*radius*0.55
				draw_arc(Vector2(center.x,y), radius*(0.75-i*0.18), 0.2, PI+0.8, 18, color, 2, true)
		"frost":
			for i: int in range(6):
				var dir := Vector2.RIGHT.rotated(i*TAU/6)
				draw_line(center, center+dir*radius*0.85, color, 2,true)
				for side: float in [-1.0,1.0]:
					draw_line(center+dir*radius*0.5,center+dir*radius*0.7+dir.orthogonal()*side*radius*0.22,color,1.5,true)
		"nova":
			draw_arc(center, radius*0.62, 0,TAU,32,color,2,true)
			for i: int in range(8):
				var dir := Vector2.RIGHT.rotated(i*TAU/8)
				draw_line(center+dir*radius*0.77,center+dir*radius,color,1.5,true)
		"dash":
			for i: int in range(3):
				var p := center+Vector2((i-1)*radius*0.48,0)
				draw_polyline(PackedVector2Array([p+Vector2(-5,-9),p+Vector2(4,0),p+Vector2(-5,9)]),color,2,true)
		"ward":
			draw_polyline(PackedVector2Array([center+Vector2(-10,-9),center+Vector2(10,-9),center+Vector2(9,4),center+Vector2(0,12),center+Vector2(-9,4),center+Vector2(-10,-9)]),color,2,true)
			draw_line(center+Vector2(0,-6),center+Vector2(0,6),color,2,true)
		"meteor":
			draw_circle(center+Vector2(-3,4),radius*0.4,color)
			for i: int in range(3):
				draw_line(center+Vector2(i*4-5,1),center+Vector2(i*4+3,-radius*0.9),Color(color,0.85-i*0.18),2,true)
		"chain":
			draw_polyline(PackedVector2Array([center+Vector2(5,-13),center+Vector2(-5,-2),center+Vector2(4,-2),center+Vector2(-5,13)]),color,3,true)
		_:
			for i: int in range(3):
				var p := center+Vector2((i-1)*7,(i%2)*7-3)
				draw_line(p+Vector2(-2,6),p+Vector2(2,-5),Color(color,0.55),4,true)
				draw_circle(p+Vector2(2,-5),2.5,color)
