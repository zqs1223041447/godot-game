class_name FantasyEnvironment
extends RefCounted
## Sunlit, weathered flagstone garden. Deterministic marks, never gameplay RNG.
static func draw(arena: Node2D) -> void:
	var bounds: Rect2=arena.ARENA
	arena.draw_rect(Rect2(0,0,1280,720),Color("4b5940"))
	# Irregular shrubs and grass beds beyond the playable stone edge.
	for i: int in range(11):
		var p:=Vector2(24+i*127+sin(i*2.1)*18,78+sin(i*2.4)*8)
		_shrub(arena,p,17+float(i%4)*3)
		_shrub(arena,p+Vector2(27,5),11+float(i%3)*2)
	for i: int in range(10):
		var p:=Vector2(35+i*136+cos(i*1.2)*23,595+cos(i*1.7)*7)
		_shrub(arena,p,15+float(i%3)*4)
		_shrub(arena,p+Vector2(-23,4),10+float(i%4))
	arena.draw_rect(bounds.grow(13),Color("424c38"))
	arena.draw_rect(bounds.grow(10),Color("b0a88c"))
	arena.draw_rect(bounds.grow(6),Color("74765e"))
	arena.draw_rect(bounds,Color("6f785e"))
	# Broad, irregular flagstones replace the old technical grid and circular reticle.
	var stone_y: float=bounds.position.y
	var courses: Array[float]=[72.0,82.0,69.0,86.0,77.0,76.0]
	for row: int in range(courses.size()):
		var stone_x: float=bounds.position.x-(43 if row%2 else 0)
		var col: int=0
		while stone_x<bounds.end.x:
			var width: float=87+float((col*23+row*19)%49)
			var cell:=Rect2(Vector2(stone_x+1.6,stone_y+1.6),Vector2(width-2.6,courses[row]-2.6)).intersection(bounds.grow(-1))
			stone_x+=width
			col+=1
			if cell.size.x<5 or cell.size.y<5:
				continue
			var shape:=_stone(cell,2+float((col*7+row*3)%6))
			var shade: float=float((col*11+row*7)%9)*0.008
			arena.draw_colored_polygon(shape,Color(0.54+shade,0.56+shade,0.47+shade))
			arena.draw_line(shape[0]+Vector2(1,1),shape[1]+Vector2(-1,1),Color(0.78,0.76,0.61,0.38),1.2,true)
			if (col+row*3)%5==0 and cell.size.x>55:
				var crack:=cell.position+Vector2(cell.size.x*0.65,0)
				arena.draw_polyline(PackedVector2Array([crack,crack+Vector2(-9,13),crack+Vector2(-5,22)]),Color(0.30,0.34,0.26,0.23),1,true)
			if (col*3+row)%7==0:
				var p:=cell.position+Vector2(cell.size.x*0.25,cell.size.y*0.7)
				arena.draw_line(p,p+Vector2(15,2),Color(0.78,0.76,0.64,0.13),1,true)
			if (col+row)%6==0:
				arena.draw_line(cell.position+Vector2(1,9),cell.position+Vector2(1,31),Color(0.28,0.37,0.18,0.27),2,true)
		stone_y+=courses[row]
	# Borders are physical worn blocks, with moss at joints rather than glowing lines.
	for x: int in range(42,1238,52):
		for y: float in [99.0,569.0]:
			var c:=Rect2(x,y,49,6)
			arena.draw_colored_polygon(_stone(c,2),Color("aaa286"))
			arena.draw_line(c.position,c.position+Vector2(47,0),Color("c3b99a"),0.8,true)
	for y: int in range(110,560,47):
		for x: float in [36.0,1240.0]:
			arena.draw_rect(Rect2(x,y,6,43),Color("a39d81"))
	for i: int in range(24):
		var x: float=65+i*48
		_tuft(arena,Vector2(x,560),float(i%4)*0.4)
		if i%3==0:
			_tuft(arena,Vector2(x+12,108),float(i%5)*0.35)
	for corner: Vector2 in [Vector2(54,116),Vector2(1226,116),Vector2(54,554),Vector2(1226,554)]:
		arena.draw_set_transform(corner+Vector2(6,7),0,Vector2(1,0.55))
		arena.draw_circle(Vector2.ZERO,16,Color(0.18,0.23,0.15,0.35))
		arena.draw_set_transform(Vector2.ZERO)
		arena.draw_colored_polygon(_stone(Rect2(corner-Vector2(12,10),Vector2(24,20)),4),Color("7f8068"))
		arena.draw_colored_polygon(_stone(Rect2(corner-Vector2(10,14),Vector2(20,18)),3),Color("bdb398"))
		arena.draw_line(corner+Vector2(-6,-11),corner+Vector2(5,-11),Color("e0ceb0"),1,true)
		arena.draw_polyline(PackedVector2Array([corner+Vector2(-2,-8),corner+Vector2(3,-4),corner+Vector2(-1,1)]),Color("746e57"),1.3,true)
	# Dappled daylight is a restrained tint, never an opaque object or gameplay hazard.
	arena.draw_colored_polygon(PackedVector2Array([Vector2(66,116),Vector2(344,116),Vector2(701,555),Vector2(531,555)]),Color(0.96,0.89,0.63,0.035))
	if arena._font:
		arena.draw_string(arena._font,Vector2(80,140),"灰烬庭院",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("4e573f"))
		arena.draw_string(arena._font,Vector2(1100,538),"试炼之地",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("586044"))

static func _stone(rect: Rect2, cut: float) -> PackedVector2Array:
	var a: Vector2=rect.position
	var b: Vector2=rect.end
	var c: float=minf(cut,minf(rect.size.x,rect.size.y)*0.25)
	return PackedVector2Array([a+Vector2(c,0),Vector2(b.x-c*0.7,a.y+0.7),Vector2(b.x,a.y+c),b-Vector2(0,c*1.3),b-Vector2(c,0),Vector2(a.x+c,b.y-0.5),Vector2(a.x,b.y-c),a+Vector2(0,c)])

static func _shrub(arena: Node2D, p: Vector2, radius: float) -> void:
	arena.draw_circle(p,radius,Color("405638"))
	arena.draw_circle(p+Vector2(-radius*0.28,-radius*0.22),radius*0.72,Color("5d7546"))
	arena.draw_circle(p+Vector2(radius*0.36,-radius*0.14),radius*0.52,Color("6d8150"))
	arena.draw_line(p+Vector2(-5,3),p+Vector2(3,-6),Color("849060"),1,true)

static func _tuft(arena: Node2D, p: Vector2, lean: float) -> void:
	for j: int in range(3):
		var tip:=p+Vector2((j-1)*3+lean,-4-float(j%2)*3)
		arena.draw_line(p,tip,Color("5b7047"),1.3,true)
