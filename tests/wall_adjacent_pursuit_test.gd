extends SceneTree
const Geometry = preload("res://scripts/world/map_geometry.gd")
class MeasuredGeometry:
	extends "res://scripts/world/map_geometry.gd"
	var clearance_checks := 0
	var projections := 0
	var goal_updates := 0
	func is_clear(point: Vector2, radius: float = 0.0) -> bool:
		clearance_checks += 1
		return super.is_clear(point, radius)
	func _project_pursuit_goal(goal: Vector2, radius: float) -> Vector2:
		projections += 1
		return super._project_pursuit_goal(goal, radius)
	func _update_goal(route: Dictionary, goal: Vector2, radius: float) -> void:
		goal_updates += 1
		super._update_goal(route, goal, radius)

class NativeProjectionProbe:
	extends MeasuredGeometry
	func legal_point(_point: Vector2, _radius: float) -> Vector2:
		return Vector2(1110, 1110)

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func fixture(walls: Array[Rect2]):
	var geometry = MeasuredGeometry.new()
	geometry.configure("normal", Rect2(0, 0, 3000, 2400))
	geometry._walls.assign(walls)
	return geometry

func pursue(geometry, start: Vector2, goal: Vector2, radius: float, limit: int = 250) -> Vector2:
	var position := start
	for unused: int in range(limit):
		var heading: Vector2 = geometry.direction(position, goal, radius, 5.0)
		var next: Vector2 = geometry.move(position, position + heading * 5.0, radius)
		check(geometry.is_clear(next, radius), "Pursuit preserves the full body footprint")
		check(geometry.visible(position, next, radius), "Pursuit never crosses a wall")
		if next.distance_to(position) < 0.001: break
		position = next
	return position

func _initialize() -> void:
	var goal := Vector2(1146, 1100)
	for radius: float in [22.0, 27.5]:
		var geometry = fixture([Rect2(1162, 604, 100, 1260)])
		check(geometry.is_clear(goal, 15.0) and not geometry.is_clear(goal, radius), "Player fits beside wall while brute does not")
		var heading: Vector2 = geometry.direction(Vector2(900, 1100), goal, radius, 5.0)
		check(heading.x > 0.99, "Wall-adjacent player remains a pursuit target")
		var end := pursue(geometry, Vector2(900, 1100), goal, radius)
		check(end.distance_to(goal) < radius - 15.0 + 0.1, "Brute reaches the nearest legal attack approach")
		check(not geometry.visible(Vector2(900, 1100), Vector2(1400, 1100)), "Attack LOS remains blocked through the wall")
	var corner = fixture([Rect2(700, 200, 100, 500), Rect2(750, 650, 500, 100)])
	goal = Vector2(816, 634)
	check(corner.is_clear(goal, 15.0), "Player is legal at the overlapping L corner")
	var end := pursue(corner, Vector2(900, 550), goal, 27.5)
	check(end.distance_to(Vector2(828, 622)) < 1.0, "L corner uses the nearby exposed intersection instead of the far wall face")
	# Shared cache is independent of actor start; direct legal goals add no scans.
	var measured = fixture([Rect2(1162, 604, 100, 1260)])
	for actor: int in range(40):
		measured.direction(Vector2(900, 1000 + actor), Vector2(1000, 1100), 27.5)
	check(measured.clearance_checks == 0 and measured.projections == 0 and measured._routes.is_empty(), "Ordinary visible goals retain the zero-scan/no-graph fast path")
	measured.direction(Vector2(900, 1100), Vector2(1146, 1100), 27.5)
	var scanned: int = measured.clearance_checks
	for actor: int in range(40):
		measured.direction(Vector2(900, 1000 + actor), Vector2(1146, 1100), 27.5)
	check(measured.projections == 1 and measured.clearance_checks == scanned, "All same-radius pursuers share one invalid-goal projection")
	check(measured._routes.is_empty(), "Projected direct pursuit needs no corner graph")
	measured.direction(Vector2(900, 1100), Vector2(1146, 1101), 27.5)
	check(measured.projections == 2, "Player movement refreshes the projected target")
	measured.direction(Vector2(900, 1100), Vector2(1146, 1101), 22.0)
	check(measured.projections == 3 and measured._pursuit_goals.size() == 2, "Different body radii never reuse each other's projection")
	measured.direction(Vector2(1400, 1100), Vector2(900, 1100), 27.5)
	scanned = measured.clearance_checks
	for actor: int in range(10):
		measured.direction(Vector2(1400, 1050 + actor), Vector2(900, 1100), 27.5)
	check(measured.clearance_checks == scanned and measured.goal_updates == 1, "Blocked legal goals share clearance and route-distance work")
	var across := pursue(measured, Vector2(1400, 1100), Vector2(1146, 1100), 27.5, 650)
	check(across.distance_to(Vector2(1146, 1100)) < 12.0, "Opposite-side brute routes around the wall to the projected goal")
	check(measured.configure("broken_ruins", Rect2(0, 0, 3000, 2400)) and measured._pursuit_goals.is_empty(), "Legacy geometry changes clear target caches")
	measured.direction(Vector2(400, 300), Vector2(570, 300), 27.5)
	check(measured.configure_exploration("broken_ruins", Rect2(0, 0, 3600, 2400)) and measured._pursuit_goals.is_empty(), "Exploration geometry changes clear target caches")
	var native = NativeProjectionProbe.new()
	native.configure("normal", Rect2(0, 0, 3000, 2400))
	native._encounter_mode = "modular_study"
	native._walls.assign([Rect2(1162, 604, 100, 1260)])
	check(native._pursuit_goal(Vector2(1146, 1100), 27.5) == Vector2(1110, 1110), "Native adapters retain their own legal-point authority")
	native._revision += 1
	native._pursuit_goal(Vector2(1146, 1100), 27.5)
	check(native.projections == 2, "Adapter revision changes invalidate cached projections")
	print("Wall-adjacent pursuit: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
