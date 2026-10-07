extends Node2D
## Five fixed presentation-only feet, always below actors, drops and raised props.
## Raw approved PNGs are read once; camera/player motion does no construction.
const ROOT := "res://art-studies/v118/"
const MANIFEST := ROOT + "exports/manifest.json"
const LAYOUT := ROOT + "qa/example-layout.json"
const MODULE_IDS := ["fern_low", "pebble_trio"]
const WORLD_PER_SOURCE_PIXEL := 1.0 / 0.65
var _signature := PackedByteArray()
var _textures: Dictionary = {}
var _feet: Dictionary = {}
var _error := ""
var _image_loads := 0
var _builds := 0
var _instances: Array[Dictionary] = []

func _init() -> void:
	name = "RuinsGardenGroundDressing"
	z_index = -1
	z_as_relative = false
	y_sort_enabled = false
	set_process(false)
	set_physics_process(false)

func configure(geometry: Dictionary) -> bool:
	if geometry.get("id") != "ruins_garden" or geometry.get("source_map_id") != "ruins_garden":
		return _fail("Ground dressing requires the explicit ruins_garden map")
	var origin: Variant = geometry.get("study_origin")
	if not origin is Vector2 or not origin.is_finite(): return _fail("Ground dressing origin is invalid")
	var signature := var_to_bytes([geometry.id, origin])
	if not _signature.is_empty():
		return true if _signature == signature else _fail("Ground dressing cannot change its admitted origin")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if not manifest is Dictionary or manifest.get("schema") != "two-low-ground-decoration-modules-v1" \
		or not layout is Dictionary or layout.get("schema") != "sparse-ground-dressing-example-v1":
		return _fail("Ground dressing source metadata is unavailable")
	if manifest.get("new_collision_count") != 0 or manifest.projection.get("camera2d_zoom") != 0.65 \
		or not manifest.get("modules") is Array or manifest.modules.size() != 2 \
		or not layout.get("instances") is Array or layout.instances.size() != 5:
		return _fail("Ground dressing contract changed")
	var definitions: Dictionary = {}
	for module: Variant in manifest.modules:
		if not module is Dictionary or module.get("id") not in MODULE_IDS or definitions.has(module.id) \
			or module.get("collision") != null or module.get("blocks_movement") != false \
			or module.get("runtime_rotation_allowed") != false:
			return _fail("Ground dressing must stay fixed and nonblocking")
		definitions[module.id] = module
	var placements: Array[Dictionary] = []
	var ids: Dictionary = {}
	var counts := {"fern_low": 0, "pebble_trio": 0}
	for instance: Variant in layout.instances:
		if not instance is Dictionary or not instance.get("id") is String or instance.id.is_empty() \
			or instance.id.validate_node_name() != instance.id or ids.has(instance.id) \
			or instance.get("module") not in MODULE_IDS or not _pair(instance.get("foot_screen_pixel")):
			return _fail("Ground dressing placement is invalid")
		ids[instance.id] = true
		counts[instance.module] += 1
		# Same source-to-world transform as the admitted module assembly, once.
		var foot: Vector2 = origin + Vector2(instance.foot_screen_pixel[0], instance.foot_screen_pixel[1]) * WORLD_PER_SOURCE_PIXEL
		placements.append({"id": instance.id, "module": instance.module, "position": foot})
	if counts.fern_low != 3 or counts.pebble_trio != 2:
		return _fail("Ground dressing must keep three ferns and two pebble groups")
	# Validate all resources before creating a visible partial arrangement.
	for id: String in MODULE_IDS:
		for layer: String in ["shadow", "sprite"]:
			if not _load_layer(id, layer, definitions[id].get(layer)): return false
	var shadows := Node2D.new()
	shadows.name = "GroundShadows"
	shadows.y_sort_enabled = false
	add_child(shadows)
	var details := Node2D.new()
	details.name = "GroundDetails"
	details.y_sort_enabled = false
	add_child(details)
	for instance: Dictionary in placements:
		for layer: String in ["shadow", "sprite"]:
			var anchor := Node2D.new()
			anchor.name = instance.id
			anchor.position = instance.position
			var sprite := Sprite2D.new()
			var key: String = instance.module + "/" + layer
			sprite.name = layer
			sprite.centered = false
			sprite.texture = _textures[key]
			sprite.position = -Vector2(_feet[key]) * WORLD_PER_SOURCE_PIXEL
			sprite.scale = Vector2.ONE * WORLD_PER_SOURCE_PIXEL
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			anchor.add_child(sprite)
			(shadows if layer == "shadow" else details).add_child(anchor)
	_instances = placements.duplicate(true)
	_signature = signature
	_builds += 1
	_error = ""
	return true

func _load_layer(id: String, layer: String, value: Variant) -> bool:
	var key := id + "/" + layer
	if _textures.has(key): return true
	var filename := id + ("_shadow" if layer == "shadow" else "") + ".png"
	if not value is Dictionary or value.get("image") != "exports/" + filename \
		or value.get("sprite_centered") != false or not _pair(value.get("foot_local_pixel")) \
		or not value.get("source_pixel_rect") is Dictionary or not value.get("sha256") is String:
		return _fail("Ground dressing layer contract is invalid")
	var path := ROOT + "exports/" + filename
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != value.sha256:
		return _fail("Ground dressing PNG does not match its approved hash")
	var image := Image.load_from_file(path)
	if image == null or image.is_empty() or image.get_width() != value.source_pixel_rect.get("width") \
		or image.get_height() != value.source_pixel_rect.get("height") or image.get_format() != Image.FORMAT_RGBA8:
		return _fail("Ground dressing PNG size/format is invalid")
	if image.generate_mipmaps() != OK: return _fail("Ground dressing mipmaps could not be built")
	_textures[key] = ImageTexture.create_from_image(image)
	_feet[key] = Vector2(value.foot_local_pixel[0], value.foot_local_pixel[1])
	_image_loads += 1
	return true

func diagnostics() -> Dictionary:
	return {"ready": not _signature.is_empty(), "error": _error, "instances": _instances.duplicate(true),
		"instance_count": _instances.size(), "image_loads": _image_loads, "builds": _builds,
		"sprite_count": _instances.size() * 2, "source_to_world": WORLD_PER_SOURCE_PIXEL}

func _fail(reason: String) -> bool:
	_error = reason
	return false

static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) \
		and (value[1] is int or value[1] is float) and is_finite(float(value[0])) and is_finite(float(value[1]))
