class_name FantasyEnvironment
extends RefCounted
const CampSigns = preload("res://scripts/visuals/map_camp_signs.gd")
## Sunlit, weathered flagstone garden. Deterministic marks, never gameplay RNG.
static func draw(arena: Node2D) -> void:
	var geometry: Dictionary = arena.world_geometry() if arena.has_method("world_geometry") else {}
	var broken: bool = not geometry.get("walls",[]).is_empty()
	var spring: bool = geometry.get("obstacle_style", "") == "spring_basin"
	var bounds: Rect2=arena.ARENA
	arena.draw_rect(bounds.grow(600),Color("68704d") if spring else Color("4b5940"))
	# Irregular shrubs and grass beds beyond the playable stone edge.
	for i: int in range(ceili(bounds.size.x/127)+1):
		var p:=Vector2(bounds.position.x-18+i*127+sin(i*2.1)*18,bounds.position.y-26+sin(i*2.4)*8)
		_shrub(arena,p,17+float(i%4)*3)
		_shrub(arena,p+Vector2(27,5),11+float(i%3)*2)
	for i: int in range(ceili(bounds.size.x/136)+1):
		var p:=Vector2(bounds.position.x-7+i*136+cos(i*1.2)*23,bounds.end.y+29+cos(i*1.7)*7)
		_shrub(arena,p,15+float(i%3)*4)
		_shrub(arena,p+Vector2(-23,4),10+float(i%4))
	arena.draw_rect(bounds.grow(13),Color("424c38"))
	arena.draw_rect(bounds.grow(10),Color("b0a88c"))
	arena.draw_rect(bounds.grow(6),Color("74765e"))
	arena.draw_rect(bounds,Color("6f785e"))
	# Broad, irregular flagstones replace the old technical grid and circular reticle.
	var stone_y: float=bounds.position.y
	var courses: Array[float]=[72.0,82.0,69.0,86.0,77.0,76.0]
	var row:int=0
	while stone_y<bounds.end.y:
		var stone_x: float=bounds.position.x-(43 if row%2 else 0)
		var col: int=0
		while stone_x<bounds.end.x:
			var width: float=87+float((col*23+row*19)%49)
			var cell:=Rect2(Vector2(stone_x+1.6,stone_y+1.6),Vector2(width-2.6,courses[row%courses.size()]-2.6)).intersection(bounds.grow(-1))
			stone_x+=width
			col+=1
			if cell.size.x<5 or cell.size.y<5:
				continue
			var shape:=_stone(cell,2+float((col*7+row*3)%6))
			var shade: float=float((col*11+row*7)%9)*0.008
			arena.draw_colored_polygon(shape,Color(0.70+shade,0.64+shade,0.49+shade) if spring else Color(0.62+shade,0.56+shade,0.43+shade) if broken else Color(0.54+shade,0.56+shade,0.47+shade))
			arena.draw_line(shape[0]+Vector2(1,1),shape[1]+Vector2(-1,1),Color(0.78,0.76,0.61,0.38),1.2,true)
			if (col+row*3)%5==0 and cell.size.x>55:
				var crack:=cell.position+Vector2(cell.size.x*0.65,0)
				arena.draw_polyline(PackedVector2Array([crack,crack+Vector2(-9,13),crack+Vector2(-5,22)]),Color(0.30,0.34,0.26,0.23),1,true)
			if (col*3+row)%7==0:
				var p:=cell.position+Vector2(cell.size.x*0.25,cell.size.y*0.7)
				arena.draw_line(p,p+Vector2(15,2),Color(0.78,0.76,0.64,0.13),1,true)
			if (col+row)%6==0:
				arena.draw_line(cell.position+Vector2(1,9),cell.position+Vector2(1,31),Color(0.28,0.37,0.18,0.27),2,true)
		stone_y+=courses[row%courses.size()]
		row+=1
	# Borders are physical worn blocks, with moss at joints rather than glowing lines.
	for x: int in range(floori(bounds.position.x),ceili(bounds.end.x),52):
		for y: float in [bounds.position.y-5,bounds.end.y+3]:
			var c:=Rect2(x,y,minf(49,bounds.end.x-x),6)
			arena.draw_colored_polygon(_stone(c,2),Color("aaa286"))
			arena.draw_line(c.position,c.position+Vector2(47,0),Color("c3b99a"),0.8,true)
	for y: int in range(floori(bounds.position.y+6),ceili(bounds.end.y-6),47):
		for x: float in [bounds.position.x-6,bounds.end.x+2]:
			arena.draw_rect(Rect2(x,y,6,43),Color("a39d81"))
	for i: int in range(floori(bounds.size.x/48)):
		var x: float=bounds.position.x+23+i*48
		_tuft(arena,Vector2(x,bounds.end.y-6),float(i%4)*0.4)
		if i%3==0:
			_tuft(arena,Vector2(x+12,bounds.position.y+4),float(i%5)*0.35)
	for corner: Vector2 in [bounds.position+Vector2(12,12),Vector2(bounds.end.x-12,bounds.position.y+12),Vector2(bounds.position.x+12,bounds.end.y-12),bounds.end-Vector2(12,12)]:
		arena.draw_set_transform(corner+Vector2(6,7),0,Vector2(1,0.55))
		arena.draw_circle(Vector2.ZERO,16,Color(0.18,0.23,0.15,0.35))
		arena.draw_set_transform(Vector2.ZERO)
		arena.draw_colored_polygon(_stone(Rect2(corner-Vector2(12,10),Vector2(24,20)),4),Color("7f8068"))
		arena.draw_colored_polygon(_stone(Rect2(corner-Vector2(10,14),Vector2(20,18)),3),Color("bdb398"))
		arena.draw_line(corner+Vector2(-6,-11),corner+Vector2(5,-11),Color("e0ceb0"),1,true)
		arena.draw_polyline(PackedVector2Array([corner+Vector2(-2,-8),corner+Vector2(3,-4),corner+Vector2(-1,1)]),Color("746e57"),1.3,true)
	# Dappled daylight is a restrained tint, never an opaque object or gameplay hazard.
	arena.draw_colored_polygon(PackedVector2Array([bounds.position+Vector2(24,12),bounds.position+Vector2(bounds.size.x*0.25,12),Vector2(bounds.position.x+bounds.size.x*0.55,bounds.end.y-11),Vector2(bounds.position.x+bounds.size.x*0.4,bounds.end.y-11)]),Color(0.96,0.89,0.63,0.035))
	if broken:
		for wall: Rect2 in geometry.walls:
			if spring: _draw_spring_basin(arena, wall)
			else: _draw_ruin_wall(arena,wall)
	CampSigns.draw_ground(arena, geometry.get("landmarks", {}))
	if arena._font:
		arena.draw_string(arena._font,bounds.position+Vector2(38,36),"晴泉台地" if spring else "断垣试炼" if broken else "灰烬庭院",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("4e573f"))
		arena.draw_string(arena._font,bounds.end-Vector2(138,28),"试炼之地",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("586044"))

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


static func _draw_ruin_wall(arena: Node2D, wall: Rect2) -> void:
	# The opaque footprint is exactly the collision rectangle. No oversized
	# decoration suggests that the routes around either end are blocked.
	arena.draw_rect(wall,Color("544b3b"))
	var inner: Rect2 = wall.grow(-3)
	arena.draw_rect(inner,Color("a69775"))
	var y: float = inner.position.y
	var course := 0
	while y < inner.end.y:
		var height: float = minf(37.0+float(course%3)*4.0,inner.end.y-y)
		var block := Rect2(inner.position.x+2,y+1,inner.size.x-4,maxf(1,height-3))
		var shade: float = float(course%4)*0.024
		arena.draw_colored_polygon(_stone(block,3),Color(0.68+shade,0.62+shade,0.48+shade))
		arena.draw_line(block.position+Vector2(3,2),Vector2(block.end.x-3,block.position.y+2),Color("e0cfaa"),2,true)
		arena.draw_line(Vector2(block.end.x-2,block.position.y+4),block.end-Vector2(2,3),Color("827459"),2,true)
		if course%3 == 1:
			var crack := block.position+Vector2(block.size.x*0.58,3)
			arena.draw_polyline(PackedVector2Array([crack,crack+Vector2(-5,11),crack+Vector2(1,19)]),Color("887959"),1.4,true)
		if course%4 == 2:
			arena.draw_line(block.position+Vector2(3,8),block.position+Vector2(3,20),Color("788151"),3,true)
		y += height
		course += 1
	arena.draw_rect(wall,Color("544b3b"),false,1.5)


static func basin_geometry(wall: Rect2) -> Dictionary:
	# Every opaque piece stays within the actual blocked footprint.
	if wall.size.x < 48.0 or wall.size.y < 48.0: return {}
	return {"footprint":wall, "rim":wall.grow(-4), "water":wall.grow(-18)}


static func _draw_spring_basin(arena: Node2D, wall: Rect2) -> void:
	var parts := basin_geometry(wall)
	if parts.is_empty():
		_draw_ruin_wall(arena, wall)
		return
	var rim: Rect2 = parts.rim
	var water: Rect2 = parts.water
	arena.draw_rect(wall, Color("62563f"))
	arena.draw_colored_polygon(_stone(rim, 7.0), Color("c4b38a"))
	arena.draw_line(rim.position + Vector2(8,3), Vector2(rim.end.x-8,rim.position.y+3), Color("e3d5ae"), 3.0, true)
	arena.draw_line(Vector2(rim.position.x+5,rim.end.y-4), rim.end-Vector2(5,4), Color("96855e"), 4.0, true)
	arena.draw_rect(water.grow(3), Color("756e51"))
	arena.draw_rect(water, Color("668575"))
	# Still water, small sunlit strokes; no clock-face rings or pulsing bloom.
	for i: int in range(4):
		var y := water.position.y + water.size.y * (float(i)+1.0) / 5.0
		var x := water.position.x + 13.0 + float(i%2)*17.0
		var right := minf(water.end.x-10.0, x+water.size.x*0.57)
		arena.draw_polyline(PackedVector2Array([Vector2(x,y),Vector2(lerpf(x,right,0.3),y-2),Vector2(lerpf(x,right,0.7),y+1),Vector2(right,y-1)]),Color(0.84,0.87,0.69,0.27),1.4,true)
	for i: int in range(1,4):
		var x := wall.position.x + wall.size.x * float(i) / 4.0
		arena.draw_line(Vector2(x,wall.position.y+5),Vector2(x,water.position.y-4),Color("958560"),1.3,true)
		arena.draw_line(Vector2(x,water.end.y+4),Vector2(x,wall.end.y-5),Color("958560"),1.3,true)
	arena.draw_rect(wall.grow(-0.8), Color("655b43"), false, 1.6)
