class_name WorldView
extends RefCounted
## Wide world camera. HUD remains an independent CanvasLayer at its current scale.
const REFERENCE_SIZE := Vector2(1280,720)
const SCREEN_PLAYFIELD := Rect2(42,104,1196,462)
const DEFAULT_ZOOM: float = 0.65
const WORLD_ARENA := Rect2(Vector2(42,104),Vector2(1196,462)/DEFAULT_ZOOM)

static func default_arena() -> Rect2:
	return WORLD_ARENA

static func from_reference(point: Vector2) -> Vector2:
	return WORLD_ARENA.position+(point-SCREEN_PLAYFIELD.position)/DEFAULT_ZOOM

static func reference_to_world_size(value: Vector2) -> Vector2:
	return value/DEFAULT_ZOOM

static func setup_camera(owner: Node2D, bounds: Rect2 = WORLD_ARENA) -> Camera2D:
	var camera := Camera2D.new()
	camera.name="WorldCamera"
	camera.zoom=Vector2.ONE*DEFAULT_ZOOM
	camera.position=bounds.get_center()
	camera.offset=(REFERENCE_SIZE*0.5-SCREEN_PLAYFIELD.get_center())/DEFAULT_ZOOM
	camera.position_smoothing_enabled=false
	camera.enabled=true
	owner.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	return camera

static func zoom_for(arena: Node2D) -> float:
	if arena.has_method("visual_camera_zoom"):return float(arena.visual_camera_zoom())
	var camera: Camera2D=arena.get_node_or_null("WorldCamera") as Camera2D
	return camera.zoom.x if camera!=null else 1.0

static func world_to_screen(arena: Node2D, point: Vector2) -> Vector2:
	return arena.get_global_transform_with_canvas()*point

static func screen_to_world(arena: Node2D, point: Vector2) -> Vector2:
	return arena.get_global_transform_with_canvas().affine_inverse()*point

static func visible_world_rect(arena: Node2D) -> Rect2:
	var size: Vector2=arena.get_viewport().get_visible_rect().size
	var first: Vector2=screen_to_world(arena,Vector2.ZERO)
	var last: Vector2=screen_to_world(arena,size)
	return Rect2(first,last-first)
