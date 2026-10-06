class_name WorldView
extends RefCounted
## Wide world camera. HUD remains an independent CanvasLayer at its current scale.
const REFERENCE_SIZE := Vector2(1280,720)
const SCREEN_PLAYFIELD := Rect2(42,104,1196,462)
const DEFAULT_ZOOM: float = 0.65
const WORLD_ARENA := Rect2(Vector2(42,104),Vector2(1196,462)/DEFAULT_ZOOM)
const EXPLORATION_SIZE := Vector2(3600,2400)

const FOLLOW_META := &"world_view_follow"
const BOUNDS_META := &"world_view_bounds"

static func default_arena() -> Rect2:
	return WORLD_ARENA

static func exploration_arena() -> Rect2:
	return Rect2(WORLD_ARENA.position,EXPLORATION_SIZE)

static func from_reference(point: Vector2) -> Vector2:
	return WORLD_ARENA.position+(point-SCREEN_PLAYFIELD.position)/DEFAULT_ZOOM

static func reference_to_world_size(value: Vector2) -> Vector2:
	return value/DEFAULT_ZOOM

static func setup_camera(owner: Node2D, bounds: Rect2 = WORLD_ARENA) -> Camera2D:
	return configure_camera(owner,bounds,false,bounds.get_center())

static func configure_camera(arena: Node2D, bounds: Rect2, follow: bool, player_position: Vector2) -> Camera2D:
	var camera: Camera2D=arena.get_node_or_null("WorldCamera") as Camera2D
	if camera==null:
		camera=Camera2D.new()
		camera.name="WorldCamera"
		arena.add_child(camera)
	camera.zoom=Vector2.ONE*DEFAULT_ZOOM
	camera.offset=(REFERENCE_SIZE*0.5-SCREEN_PLAYFIELD.get_center())/DEFAULT_ZOOM
	camera.position_smoothing_enabled=false
	camera.drag_horizontal_enabled=false
	camera.drag_vertical_enabled=false
	camera.set_meta(FOLLOW_META,follow)
	camera.set_meta(BOUNDS_META,bounds)
	camera.position=follow_position(player_position,bounds) if follow else bounds.get_center()
	camera.enabled=true
	if camera.is_inside_tree():
		camera.make_current()
		camera.force_update_scroll()
	return camera

static func follow_position(player_position: Vector2, bounds: Rect2, zoom: float = DEFAULT_ZOOM) -> Vector2:
	# Clamp the combat viewport, not the whole window. The existing camera offset
	# places this position at SCREEN_PLAYFIELD's center, including its HUD inset.
	# Native camera limits stay unused so they cannot apply a second offset clamp.
	var half_view: Vector2=SCREEN_PLAYFIELD.size/(2.0*maxf(zoom,0.001))
	var center: Vector2=bounds.get_center()
	return Vector2(
		clampf(player_position.x,bounds.position.x+half_view.x,bounds.end.x-half_view.x) if bounds.size.x>half_view.x*2.0 else center.x,
		clampf(player_position.y,bounds.position.y+half_view.y,bounds.end.y-half_view.y) if bounds.size.y>half_view.y*2.0 else center.y
	)

static func update_follow_camera(arena: Node2D, player_position: Vector2, bounds: Rect2) -> void:
	var camera: Camera2D=arena.get_node_or_null("WorldCamera") as Camera2D
	if camera==null or not bool(camera.get_meta(FOLLOW_META,false)):
		return
	camera.set_meta(BOUNDS_META,bounds)
	camera.position=follow_position(player_position,bounds,camera.zoom.x)
	# Movement, including a dash, must update mouse aim in this same frame.
	if camera.is_inside_tree():
		camera.force_update_scroll()

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
