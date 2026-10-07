extends CharacterBody2D
## Eight static direction illustrations. There is deliberately no animation player.

const RADIUS_PIXEL := 14.2222222222 # 0.3 metres * 47.4074074074 px/metre.
const SPEED_PIXEL := 155.0
const ART_SCALE := 0.115
const ATLAS_PATH := "res://assets/hero_direction_study.png"
const DIRECTION_NAMES := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
# Original rows overlap the nominal 512px grid. Rectangles only select the
# existing source; they do not rewrite, resample or invent character artwork.
const REGIONS := [
	Rect2(0, 0, 384, 480), Rect2(384, 0, 384, 480),
	Rect2(768, 0, 384, 480), Rect2(1152, 0, 384, 480),
	Rect2(0, 488, 384, 512), Rect2(384, 488, 384, 512),
	Rect2(768, 488, 384, 512), Rect2(1152, 488, 384, 512),
]
# Contact baseline at the lowest boot; x is the stance centre, not the staff.
const FEET := [
	Vector2(206, 470), Vector2(205, 470), Vector2(210, 467), Vector2(211, 471),
	Vector2(174, 479), Vector2(172, 473), Vector2(191, 479), Vector2(190, 484),
]

var sprite: Sprite2D
var footprint: CollisionShape2D
var direction_index := 2
var accept_input := true
var test_direction := Vector2.ZERO
var contact_count := 0
var last_contact_id := ""

func _ready() -> void:
	name = "StaticDirectionCharacter"
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1
	safe_margin = 0.02
	max_slides = 4
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	footprint = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS_PIXEL
	footprint.shape = circle
	add_child(footprint)
	sprite = Sprite2D.new()
	sprite.name = "StaticIdleIllustration"
	sprite.texture = load(ATLAS_PATH)
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_filter_clip_enabled = true
	sprite.scale = Vector2.ONE * ART_SCALE
	add_child(sprite)
	set_direction(direction_index)

func set_direction(index: int) -> void:
	direction_index = posmod(index, 8)
	if sprite == null:
		return
	sprite.region_rect = REGIONS[direction_index]
	sprite.offset = -FEET[direction_index]

func direction_from_vector(movement: Vector2) -> int:
	return posmod(roundi(movement.angle() / (PI / 4.0)), 8)

func _physics_process(_delta: float) -> void:
	var movement := test_direction
	if accept_input:
		movement = Vector2(
			float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		)
	if movement.length_squared() > 0.0:
		movement = movement.normalized()
		set_direction(direction_from_vector(movement))
	velocity = movement * SPEED_PIXEL
	move_and_slide()
	for index in get_slide_collision_count():
		contact_count += 1
		var collider := get_slide_collision(index).get_collider()
		if collider != null:
			last_contact_id = str(collider.get_meta("collider_id", "screen_edge"))
	# A finite single-screen test, not a world or camera controller.
	position = position.clamp(Vector2(RADIUS_PIXEL, 52.0), Vector2(1280.0 - RADIUS_PIXEL, 653.0))

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 11.5, Color(0.09, 0.12, 0.09, 0.22))
