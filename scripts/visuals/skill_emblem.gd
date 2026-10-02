class_name SkillEmblem
extends Control
## Original carved spell tokens on stone and old bronze; no luminous UI rings.
var skill_id: String = "bolt"
var accent := Color("d5bc83")
var subdued: bool = false
const COLORS: Dictionary={"tornado":Color("b6c38d"),"bolt":Color("d6c394"),"frost":Color("a9cbd0"),"nova":Color("bdacd0"),"dash":Color("d0b17a"),"ward":Color("b7c6a0"),"meteor":Color("d89358"),"chain":Color("d9c18b")}
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func _line(a: Vector2,b: Vector2,color: Color,width: float=1.7) -> void:
	draw_line(a+Vector2(0,1),b+Vector2(0,1),Color("171b15"),width+1.4,true)
	draw_line(a,b,color,width,true)
func _path(points: PackedVector2Array,color: Color,width: float=1.7) -> void:
	draw_polyline(points,Color("171b15"),width+1.8,true)
	draw_polyline(points,color,width,true)
func _draw() -> void:
	var c:=size*0.5
	var r: float=minf(size.x,size.y)*0.43
	var color: Color=COLORS.get(skill_id,accent)
	if subdued: color=color.darkened(0.38)
	var tile:=PackedVector2Array([c+Vector2(-r+3,-r),c+Vector2(r-2,-r),c+Vector2(r,-r+3),c+Vector2(r,r-3),c+Vector2(r-3,r),c+Vector2(-r+2,r),c+Vector2(-r,r-2),c+Vector2(-r,-r+3)])
	draw_colored_polygon(tile,Color("252c24"))
	var outline: PackedVector2Array=tile.duplicate()
	outline.append(tile[0])
	draw_polyline(outline,Color("897956").darkened(0.25 if subdued else 0),1,true)
	draw_line(c+Vector2(-r+4,-r+2),c+Vector2(r-4,-r+2),Color("af9870"),0.7,true)
	match skill_id:
		"tornado":
			for i: int in range(3):
				var y:=c.y-r*0.5+i*r*0.5
				var points:=PackedVector2Array()
				for j: int in range(13):
					var a: float=lerpf(-0.45,PI+0.7,j/12.0)
					points.append(Vector2(c.x,y)+Vector2(cos(a),sin(a)*0.55)*r*(0.7-i*0.18))
				_path(points,color,1.6)
		"frost":
			var crystal:=PackedVector2Array([c+Vector2(0,-r*0.8),c+Vector2(r*0.4,0),c+Vector2(0,r*0.8),c+Vector2(-r*0.4,0)])
			draw_colored_polygon(crystal,color.darkened(0.28))
			_line(c+Vector2(0,-r*0.8),c+Vector2(0,r*0.8),color,1.4)
			_line(c+Vector2(-r*0.65,-r*0.37),c+Vector2(r*0.65,r*0.37),color,1.4)
			_line(c+Vector2(-r*0.65,r*0.37),c+Vector2(r*0.65,-r*0.37),color,1.4)
			for side: int in [-1,1]:
				_line(c+Vector2(side*r*0.65,-r*0.37),c+Vector2(side*r*0.65,-r*0.65),color,1)
		"nova":
			for i: int in range(8):
				var v:=Vector2.RIGHT.rotated(i*TAU/8)
				_line(c+v*r*0.25,c+v*r*0.75,color,1.7)
			draw_colored_polygon(PackedVector2Array([c+Vector2(0,-5),c+Vector2(4,0),c+Vector2(0,5),c+Vector2(-4,0)]),color)
		"dash":
			var tip:=c+Vector2(r*0.7,-r*0.65)
			_line(c+Vector2(-r*0.6,r*0.6),tip,color,1.6)
			for i: int in range(4):
				var p:=c+Vector2((i-1.5)*3,(-i+1.5)*3)
				_line(p,p+Vector2(-5,-2),color,1.4)
				_line(p,p+Vector2(2,5),color,1.4)
		"ward":
			var shield:=PackedVector2Array([c+Vector2(-9,-9),c+Vector2(0,-7),c+Vector2(9,-9),c+Vector2(8,3),c+Vector2(0,11),c+Vector2(-8,3),c+Vector2(-9,-9)])
			draw_colored_polygon(shield,Color("62694b").darkened(0.2 if subdued else 0))
			_path(shield,color,1.5)
			_line(c+Vector2(0,-4),c+Vector2(0,6),color,1.5)
			_line(c+Vector2(-4,0),c+Vector2(4,0),color,1.3)
		"meteor":
			var center:=c+Vector2(-3,3)
			var flame:=PackedVector2Array([center+Vector2(-4,-1),c+Vector2(1,-10),c+Vector2(2,-3),c+Vector2(9,-12),c+Vector2(5,3),center+Vector2(3,6)])
			draw_colored_polygon(flame,color.darkened(0.15))
			var rock:=PackedVector2Array([center+Vector2(-5,-2),center+Vector2(0,-5),center+Vector2(5,-1),center+Vector2(3,5),center+Vector2(-3,6)])
			draw_colored_polygon(rock,Color("8b7760"))
			_line(rock[0],rock[1],Color("dcc391").darkened(0.3 if subdued else 0),1.2)
		"chain":
			_path(PackedVector2Array([c+Vector2(6,-11),c+Vector2(-4,-1),c+Vector2(3,-1),c+Vector2(-6,11)]),color,2)
			_line(c+Vector2(-3,0),c+Vector2(-9,-4),color,1.1)
		_:
			for i: int in range(3):
				var p:=c+Vector2((i-1)*7,(i%2)*7-3)
				_line(p+Vector2(-1,6),p+Vector2(2,-3),color.darkened(0.25),1.2)
				draw_colored_polygon(PackedVector2Array([p+Vector2(2,-7),p+Vector2(5,-3),p+Vector2(2,0),p+Vector2(-1,-3)]),color)
