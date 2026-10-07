extends Node2D
## Frozen-layout environment experiment. All coordinates are original screen px.

const Player := preload("res://player.gd")
const DebugOverlay := preload("res://study_overlay.gd")
const GroundShadow := preload("res://character_ground_shadow.gd")
const MANIFEST_PATH := "res://assets/environment/runtime-manifest.json"
const ASSET_ROOT := "res://assets/environment/"
const SPAWN_POINT := Vector2(640.0, 427.768)

var manifest: Dictionary
var background_root: Node2D
var sorted_root: Node2D
var collision_root: Node2D
var player: CharacterBody2D
var overlay: Node2D
var ground_shadow: Node2D
var prop_nodes: Dictionary = {}
var collider_nodes: Dictionary = {}
var loaded_images := 0
var drawn_layers := 0
var debug_visible := false
var load_errors: Array[String] = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(MANIFEST_PATH)) != OK or not json.data is Dictionary:
		load_errors.append("Cannot read the frozen runtime manifest")
		push_error(load_errors[-1])
		return
	manifest = json.data
	if manifest.get("schema", "") != "sunlit-ruins-godot-static-layers-v1":
		load_errors.append("Unsupported runtime manifest schema")
		push_error(load_errors[-1])
		return
	background_root = Node2D.new()
	background_root.name = "GroundAndGroundDetail"
	background_root.z_index = -1
	add_child(background_root)
	sorted_root = Node2D.new()
	sorted_root.name = "SharedFootYSort"
	sorted_root.y_sort_enabled = true
	add_child(sorted_root)
	collision_root = Node2D.new()
	collision_root.name = "UnmodifiedScreenPixelCollision"
	add_child(collision_root)
	for entry in manifest.layers:
		_add_layer(entry)
	for entry in manifest.colliders:
		_add_collider(entry)
	player = Player.new()
	player.position = SPAWN_POINT
	sorted_root.add_child(player)
	# Same ground z as the background, but later in tree order. Every prop and
	# the character remain at z=0, so the shadow cannot paint over their pixels.
	ground_shadow = GroundShadow.new()
	ground_shadow.name = "CharacterGroundShadow"
	ground_shadow.z_index = -1
	ground_shadow.target = player
	add_child(ground_shadow)
	var ui := CanvasLayer.new()
	ui.name = "StudyDisclosureAndDiagnostics"
	ui.layer = 10
	add_child(ui)
	overlay = DebugOverlay.new()
	overlay.study = self
	ui.add_child(overlay)

func _add_layer(entry: Dictionary) -> void:
	var path: String = ASSET_ROOT + str(entry.image)
	if not ResourceLoader.exists(path):
		load_errors.append("Missing layer: " + path)
		push_error(load_errors[-1])
		return
	var texture: Texture2D = load(path)
	loaded_images += 1
	if texture.get_size() != point(entry.image_size_pixel):
		load_errors.append("Layer dimensions differ from manifest: " + str(entry.id))
	if not bool(entry.visible_in_original):
		return # Empty-alpha records remain in collision data.
	var layer := Node2D.new()
	layer.name = str(entry.id)
	layer.position = point(entry.foot_screen_pixel)
	layer.set_meta("source_layer_id", entry.id)
	layer.set_meta("foot_y", layer.position.y)
	var sprite := Sprite2D.new()
	sprite.name = "FrozenLayerPixels"
	sprite.texture = texture
	sprite.centered = false
	sprite.offset = point(entry.sprite_offset_pixel)
	layer.add_child(sprite)
	if str(entry.sort_mode) == "y_sort":
		sorted_root.add_child(layer)
		prop_nodes[str(entry.id)] = layer
	else:
		background_root.add_child(layer)
	drawn_layers += 1

func _add_collider(entry: Dictionary) -> void:
	var body := StaticBody2D.new()
	body.name = str(entry.id)
	body.collision_layer = 1
	body.collision_mask = 2
	body.set_meta("collider_id", entry.id)
	body.set_meta("source_layer_id", entry.layer_id)
	collision_root.add_child(body)
	# Deliberately no sprite scale, zoom conversion, simplification or hull union.
	for polygon_entry in entry.polygons:
		var polygon := CollisionPolygon2D.new()
		polygon.polygon = points(polygon_entry.screen_pixel)
		body.add_child(polygon)
	collider_nodes[str(entry.id)] = body

func reset_player() -> void:
	player.position = SPAWN_POINT
	player.velocity = Vector2.ZERO
	player.test_direction = Vector2.ZERO
	player.set_direction(2)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_F1:
		debug_visible = not debug_visible
		overlay.queue_redraw()
	elif event.physical_keycode == KEY_R:
		reset_player()
	elif event.physical_keycode == KEY_ESCAPE:
		get_tree().quit()

static func point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))

static func points(raw: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for value in raw:
		result.append(point(value))
	return result
