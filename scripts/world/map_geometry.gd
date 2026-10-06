class_name MapGeometry
extends RefCounted
## Deterministic static world geometry. No RNG, actor mutation or damage rules.
const EPS := 0.000001
const SKIN := 0.02
const CORNER_CLEARANCE := 0.5
var _id := "normal"
var _bounds := Rect2()
var _walls: Array[Rect2] = []
var _revision := 0
var _routes: Dictionary = {}

func configure(id: String, bounds: Rect2) -> bool:
	if id not in ["normal", "town", "old_garden", "broken_ruins", "sunwell_terrace", "ginkgo_arcade"] or not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x < 1500.0 or bounds.size.y < 710.0:
		return false
	if id == _id and bounds == _bounds: return true
	_id = id; _bounds = bounds; _walls.clear(); _routes.clear(); _revision += 1
	if id == "broken_ruins":
		_walls.assign([Rect2(bounds.position + Vector2(580,100),Vector2(56,400)), Rect2(bounds.position + Vector2(1180,210),Vector2(56,400))])
	elif id == "sunwell_terrace":
		_walls.assign([Rect2(bounds.position + Vector2(520,140),Vector2(240,140)), Rect2(bounds.position + Vector2(1080,140),Vector2(240,140)), Rect2(bounds.position + Vector2(520,430),Vector2(240,140)), Rect2(bounds.position + Vector2(1080,430),Vector2(240,140))])
	elif id == "ginkgo_arcade":
		_walls.assign([Rect2(bounds.position + Vector2(660,230),Vector2(520,250)), Rect2(bounds.position + Vector2(420,310),Vector2(90,90)), Rect2(bounds.position + Vector2(1330,310),Vector2(90,90))])
	return true

func snapshot() -> Dictionary:
	var result := {"id":_id,"bounds":_bounds,"walls":_walls.duplicate(),"spawn":_bounds.get_center(),"revision":_revision}
	if _id == "sunwell_terrace": result.obstacle_style = "spring_basin"
	if _id == "ginkgo_arcade": result.obstacle_style = "ginkgo_planters"
	return result

func has_walls() -> bool: return not _walls.is_empty()

func _clamp(point: Vector2, radius: float) -> Vector2:
	return Vector2(clampf(point.x,_bounds.position.x+radius,_bounds.end.x-radius),clampf(point.y,_bounds.position.y+radius,_bounds.end.y-radius))

func is_clear(point: Vector2, radius: float = 0.0) -> bool:
	if not point.is_finite() or not is_finite(radius) or radius < 0.0 or _clamp(point,radius) != point: return false
	for wall: Rect2 in _walls:
		var expanded := wall.grow(radius)
		if point.x > expanded.position.x + EPS and point.x < expanded.end.x - EPS and point.y > expanded.position.y + EPS and point.y < expanded.end.y - EPS: return false
	return true

func legal_point(point: Vector2, radius: float) -> Vector2:
	var desired := _clamp(point,radius)
	if is_clear(desired,radius): return desired
	var candidates: Array[Vector2] = []
	for wall: Rect2 in _walls:
		var box := wall.grow(radius+SKIN)
		candidates.append_array([Vector2(box.position.x,desired.y),Vector2(box.end.x,desired.y),Vector2(desired.x,box.position.y),Vector2(desired.x,box.end.y),box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)])
	var best := _bounds.get_center()
	var distance := INF
	for candidate: Vector2 in candidates:
		candidate = _clamp(candidate,radius)
		if is_clear(candidate,radius) and desired.distance_squared_to(candidate) < distance:
			best = candidate; distance = desired.distance_squared_to(candidate)
	return best

## Each actor uses its unchanged radius. Expanded wall corners are conservative;
## both movement and projectile sweeps use this same blocking footprint.
func sweep(start: Vector2, end: Vector2, radius: float = 0.0) -> Dictionary:
	var result := {"hit":false,"fraction":1.0,"point":end,"normal":Vector2.ZERO,"wall":-1}
	if not start.is_finite() or not end.is_finite() or not is_finite(radius) or radius < 0.0:
		return {"hit":true,"fraction":0.0,"point":start,"normal":Vector2.ZERO,"wall":-1}
	for index: int in range(_walls.size()):
		var contact := _box_contact(start,end,_walls[index].grow(radius))
		if contact.hit and (not result.hit or float(contact.fraction) < float(result.fraction)):
			result = contact; result.wall = index
	return result

static func _box_contact(start: Vector2, end: Vector2, box: Rect2) -> Dictionary:
	var miss := {"hit":false,"fraction":1.0,"point":end,"normal":Vector2.ZERO}
	var delta := end-start
	var enter := -INF
	var leave := INF
	var normal := Vector2.ZERO
	for axis: int in range(2):
		if absf(delta[axis]) <= EPS:
			# An exactly tangent segment has no interior in this axis.
			if start[axis] <= box.position[axis]+EPS or start[axis] >= box.end[axis]-EPS: return miss
			continue
		var first: float = (box.position[axis]-start[axis])/delta[axis]
		var last: float = (box.end[axis]-start[axis])/delta[axis]
		var face := Vector2.ZERO; face[axis] = -signf(delta[axis])
		if first > last:
			var temporary := first; first = last; last = temporary
		if first > enter: enter = first; normal = face
		leave = minf(leave,last)
		if enter > leave: return miss
	if leave <= maxf(enter,0.0)+EPS or enter > 1.0+EPS: return miss
	var fraction := clampf(enter,0.0,1.0)
	return {"hit":true,"fraction":fraction,"point":start.lerp(end,fraction),"normal":normal}

func visible(start: Vector2, end: Vector2, radius: float = 0.0) -> bool:
	return not sweep(start,end,radius).hit

func move(start: Vector2, desired: Vector2, radius: float, traversed: Variant = null) -> Vector2:
	var position := legal_point(start,radius)
	var destination := _clamp(position+(desired-start),radius)
	for unused: int in range(3):
		var hit := sweep(position,destination,radius)
		if not hit.hit:
			if traversed is Array: traversed.append([position,destination])
			return destination
		var remaining := (destination-position)*(1.0-float(hit.fraction))
		var normal: Vector2 = hit.normal
		var next_position: Vector2 = Vector2(hit.point)+normal*SKIN
		if traversed is Array: traversed.append([position,next_position])
		position = next_position
		remaining -= normal*minf(remaining.dot(normal),0.0)
		destination = _clamp(position+remaining,radius)
		if remaining.length_squared() <= EPS: break
	return legal_point(position,radius)

## Expanded obstacle corners, cached by the exact body radius. Goal
## distances are shared by all actors of that radius until the player moves.
func direction(start: Vector2, goal: Vector2, radius: float, max_step: float = 0.0) -> Vector2:
	if not has_walls() or visible(start,goal,radius): return _step_direction(goal-start,max_step)
	if not _routes.has(radius): _routes[radius] = _make_route_graph(radius)
	var route: Dictionary = _routes[radius]
	if route.goal != goal: _update_goal(route,goal,radius)
	var best := -1
	var cost := INF
	for index: int in range(route.points.size()):
		var point: Vector2 = route.points[index]
		if start.distance_squared_to(point) <= SKIN*SKIN: continue
		var candidate: float = start.distance_to(point)+float(route.distances[index])
		if candidate < cost and visible(start,point,radius): best=index; cost=candidate
	return Vector2.ZERO if best < 0 else _step_direction(Vector2(route.points[best])-start,max_step)

static func _step_direction(offset: Vector2, max_step: float) -> Vector2:
	return offset.normalized() * (minf(1.0,offset.length()/max_step) if max_step > EPS else 1.0)

func _make_route_graph(radius: float) -> Dictionary:
	var points: Array[Vector2] = []
	for wall: Rect2 in _walls:
		var box := wall.grow(radius+CORNER_CLEARANCE)
		for point: Vector2 in [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]:
			if is_clear(point,radius): points.append(point)
	var edges: Array = []
	for from: Vector2 in points:
		var row: Array[float] = []
		for to: Vector2 in points: row.append(from.distance_to(to) if visible(from,to,radius) else INF)
		edges.append(row)
	return {"points":points,"edges":edges,"goal":Vector2(INF,INF),"distances":[]}

func _update_goal(route: Dictionary, goal: Vector2, radius: float) -> void:
	route.goal=goal; route.distances.clear()
	var visited: Array[bool] = []
	for point: Vector2 in route.points:
		route.distances.append(point.distance_to(goal) if visible(point,goal,radius) else INF); visited.append(false)
	for unused: int in range(route.points.size()):
		var best := -1; var cost := INF
		for index: int in range(visited.size()):
			if not visited[index] and float(route.distances[index]) < cost: best=index; cost=float(route.distances[index])
		if best < 0: break
		visited[best]=true
		for index: int in range(visited.size()):
			route.distances[index]=minf(float(route.distances[index]),cost+float(route.edges[best][index]))
