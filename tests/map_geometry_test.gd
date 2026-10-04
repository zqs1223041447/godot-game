extends SceneTree
const Geometry=preload("res://scripts/world/map_geometry.gd")
const View=preload("res://scripts/visuals/world_view.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	var geometry=Geometry.new()
	check(geometry.configure("broken_ruins",View.WORLD_ARENA),"Known map configured")
	var original:Dictionary=geometry.snapshot();var external:Dictionary=geometry.snapshot();external.walls.clear()
	check(geometry.snapshot()==original,"Visual snapshot cannot mutate authority")
	check(not geometry.configure("unknown",View.WORLD_ARENA) and geometry.snapshot()==original,"Unknown layout rejected without revision change")
	check(geometry.configure("broken_ruins",View.WORLD_ARENA) and geometry.snapshot()==original,"Same layout keeps revision/cache")
	var wall:Rect2=original.walls[0]
	for radius:float in [0.0,4.5,6.0,10.0,14.0,15.0,17.5,22.0,27.5]:
		var left:=Vector2(wall.position.x-radius-60,wall.get_center().y)
		var right:=Vector2(wall.end.x+radius+60,wall.get_center().y)
		var hit:Dictionary=geometry.sweep(left,right,radius)
		check(hit.hit and absf(hit.point.x-(wall.position.x-radius))<0.001,"Swept body stops at exact expanded wall plane")
		check(not geometry.visible(left,right,radius),"Wall occludes a crossing ray")
		check(geometry.move(left,right,radius).x<wall.position.x-radius,"Long displacement cannot tunnel")
		var reverse:Dictionary=geometry.sweep(right,left,radius)
		check(reverse.hit and reverse.normal==Vector2.RIGHT,"Opposite face normal correct")
		var at:=Vector2(wall.position.x-radius,wall.get_center().y)
		check(not geometry.sweep(at,at+Vector2(0,30),radius).hit,"Exactly tangent travel is allowed")
		check(not geometry.sweep(at,at+Vector2(-30,0),radius).hit,"Moving away from face is allowed")
		check(geometry.sweep(at,at+Vector2(30,0),radius).hit,"Moving into face at t0 is blocked")
		var moved:Vector2=geometry.move(left,right+Vector2(0,35),radius)
		check(geometry.is_clear(moved,radius) and moved.y>left.y+25,"Diagonal travel slides along wall")
		var inside:Vector2=geometry.legal_point(wall.get_center(),radius)
		check(geometry.is_clear(inside,radius),"Inside-wall birth moves to legal footprint")
		check(geometry.legal_point(wall.get_center(),radius)==inside,"Birth projection is deterministic")
		for side:float in [-1.0,1.0]:
			var point:=Vector2(wall.position.x-radius-30,wall.position.y-radius-30) if side<0 else Vector2(wall.end.x+radius+30,wall.end.y+radius+30)
			var destination:=wall.get_center()
			check(geometry.is_clear(geometry.move(point,destination,radius),radius),"Corner sweep does not enter wall")
	# All extant body radii can traverse both staggered obstacles, not only the player.
	var points:Array[Vector2]=[View.WORLD_ARENA.position+Vector2(80,350),View.WORLD_ARENA.position+Vector2(1740,350),View.WORLD_ARENA.get_center()]
	for radius:float in [10.0,14.0,15.0,17.5,22.0,27.5]:
		for start:Vector2 in points:
			for goal:Vector2 in points:
				var point:=start;var valid:=true;var steps:=0
				while point.distance_to(goal)>0.05 and steps<1200:
					var direction:Vector2=geometry.direction(point,goal,radius,5.0)
					point=geometry.move(point,point+direction*5.0,radius)
					valid=valid and geometry.is_clear(point,radius);steps+=1
				check(valid and point.distance_to(goal)<=0.05,"Every body can navigate both ways without crossing or corner oscillation")
	var random:=RandomNumberGenerator.new();random.seed=290029
	for unused:int in range(250):
		var point:=View.WORLD_ARENA.position+Vector2(random.randf_range(-50,1890),random.randf_range(-50,760))
		for radius:float in [6.0,15.0,27.5]:check(geometry.is_clear(geometry.legal_point(point,radius),radius),"All sampled births have legal deterministic positions")
	check(geometry.configure("old_garden",View.WORLD_ARENA) and geometry.snapshot().walls.is_empty(),"Old Garden removes every obstacle")
	check(geometry.snapshot().revision>original.revision,"Switching layout invalidates drawing cache")
	print("Map geometry: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
