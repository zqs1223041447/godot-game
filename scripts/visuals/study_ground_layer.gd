class_name StudyGroundLayer
extends Node2D
## One retained, opaque study-ground quad. Geometry and resources are captured
## during configure(); camera motion never changes its commands or material.
const ASSET_DIR := "res://assets/environment/studies/natural_ground/"
const PROFILE_PATH := ASSET_DIR + "profile.json"
const SHADER_PATH := "res://shaders/study_natural_ground.gdshader"
const EXPECTED_BOUNDS := Rect2(42, 104, 3600, 2400)
const EXPECTED_MASK_SIZE := Vector2i(512, 384)
const DIFFUSE_SIZE := Vector2i(1024, 1024)
const TEXTURE_PATHS := {
	"soil": ASSET_DIR + "forest_ground_04_diff_1k.jpg",
	"grass": ASSET_DIR + "aerial_grass_rock_diff_1k.jpg",
	"stone": ASSET_DIR + "medieval_blocks_05_diff_1k.jpg",
}
const REPEAT_KEYS := ["soil", "grass", "grass_secondary", "stone"]

var draw_count: int = 0
var build_count: int = 0
var _ground_ready := false
var _error := ""
var _resources_attempted := false
var _resource_error := ""
var _profile: Dictionary = {}
var _textures: Dictionary = {}
var _shader: Shader
var _ground_material: ShaderMaterial
var _geometry: Dictionary = {}
var _polygon_hash := ""


func _init() -> void:
	use_parent_material = false
	set_process(false)
	set_physics_process(false)


func configure(geometry: Dictionary) -> bool:
	if geometry.get("id") not in ["modular_study", "ruins_garden"]:
		return _fail("Natural ground requires modular_study geometry")
	if not geometry.get("bounds") is Rect2 or geometry.get("bounds") != EXPECTED_BOUNDS:
		return _fail("Natural ground bounds differ from the authored study")
	var source: Variant = geometry.get("module_polygons")
	if not source is Array or source.is_empty() or source.size() > 4:
		return _fail("Natural ground requires the authored module polygons")
	# Preserve the typed array encoding used by the offline mask generator.
	# Copy every packed array so later caller mutations cannot alter our snapshot.
	var polygons: Array[PackedVector2Array] = []
	var vertex_count := 0
	for polygon: Variant in source:
		if not polygon is PackedVector2Array or polygon.size() < 3:
			return _fail("Natural ground has an invalid module polygon")
		vertex_count += polygon.size()
		if vertex_count > 99:
			return _fail("Natural ground exceeds the study polygon budget")
		for point: Vector2 in polygon:
			if not point.is_finite():
				return _fail("Natural ground polygon coordinates must be finite")
		polygons.append(polygon.duplicate())
	var hash_context := HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256) != OK or hash_context.update(var_to_bytes(polygons)) != OK:
		return _fail("Natural ground polygon hash could not be computed")
	var polygon_hash := hash_context.finish().hex_encode()
	if not _ensure_resources():
		return _fail(_resource_error)
	if polygon_hash != _profile.module_polygons_sha256:
		return _fail("Natural ground mask does not match the module polygons")
	if _ground_ready and _polygon_hash == polygon_hash:
		return true
	_geometry = {"id": geometry.id, "bounds": EXPECTED_BOUNDS, "module_polygons": polygons}
	_polygon_hash = polygon_hash
	if _ground_material == null:
		_build_material()
	material = _ground_material
	_ground_ready = true
	_error = ""
	visible = true
	queue_redraw()
	return true


func diagnostics() -> Dictionary:
	return {"ready": _ground_ready, "error": _error, "draw_count": draw_count,
		"build_count": build_count, "texture_count": _textures.size()}


func get_diagnostics() -> Dictionary:
	return diagnostics()


func _draw() -> void:
	if not _ground_ready:
		return
	draw_rect(_geometry.bounds, Color.WHITE)
	draw_count += 1


func _fail(reason: String) -> bool:
	_ground_ready = false
	_error = reason
	# Also fail closed if the caller has not removed this child yet. Keep the
	# resource cache intact; a failed load is retried only with a new instance.
	visible = false
	return false


func _ensure_resources() -> bool:
	if _resources_attempted:
		return _resource_error.is_empty()
	_resources_attempted = true
	if not FileAccess.file_exists(PROFILE_PATH):
		return _resource_failure("Natural ground profile is missing")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not parsed is Dictionary or parsed.get("schema") != "study_natural_ground_v1":
		return _resource_failure("Natural ground profile schema is invalid")
	var profile: Dictionary = parsed
	if not _number_array(profile.get("bounds"), 4):
		return _resource_failure("Natural ground profile bounds are invalid")
	var bounds_data: Array = profile.bounds
	var bounds := Rect2(float(bounds_data[0]), float(bounds_data[1]), float(bounds_data[2]), float(bounds_data[3]))
	if bounds != EXPECTED_BOUNDS:
		return _resource_failure("Natural ground profile bounds do not match the study")
	if not profile.get("module_polygons_sha256") is String or str(profile.module_polygons_sha256).length() != 64:
		return _resource_failure("Natural ground profile polygon hash is invalid")
	if not _number_array(profile.get("world_units_per_ground_metre"), 2):
		return _resource_failure("Natural ground metre scale is invalid")
	var scale_data: Array = profile.world_units_per_ground_metre
	var metre_scale := Vector2(float(scale_data[0]), float(scale_data[1]))
	if not metre_scale.is_finite() or metre_scale.x < 0.01 or metre_scale.y < 0.01:
		return _resource_failure("Natural ground metre scale must be finite and positive")
	var repeats: Variant = profile.get("tile_repeats_per_ground_metre")
	if not repeats is Dictionary:
		return _resource_failure("Natural ground texture repeat rates are missing")
	for key: String in REPEAT_KEYS:
		var rate: Variant = repeats.get(key)
		if not _finite_number(rate) or float(rate) <= 0.0 or float(rate) > 16.0:
			return _resource_failure("Natural ground texture repeat rate is invalid: " + key)
	if not _number_array(profile.get("mask_size"), 2):
		return _resource_failure("Natural ground mask size is invalid")
	var mask_data: Array = profile.mask_size
	if float(mask_data[0]) != EXPECTED_MASK_SIZE.x or float(mask_data[1]) != EXPECTED_MASK_SIZE.y:
		return _resource_failure("Natural ground mask size differs from the authored mask")
	if profile.get("mask_path") != ASSET_DIR + "mix_mask.png":
		return _resource_failure("Natural ground mask path is invalid")
	var paths: Variant = profile.get("textures")
	if not paths is Dictionary:
		return _resource_failure("Natural ground texture paths are missing")
	var prepared: Dictionary = {}
	for key: String in TEXTURE_PATHS:
		if paths.get(key) != TEXTURE_PATHS[key]:
			return _resource_failure("Natural ground texture path is invalid: " + key)
		var texture := _load_texture(str(paths[key]), DIFFUSE_SIZE)
		if texture == null:
			return false
		prepared[key] = texture
	var mask := _load_texture(str(profile.mask_path), EXPECTED_MASK_SIZE)
	if mask == null:
		return false
	prepared["mask"] = mask
	if not ResourceLoader.exists(SHADER_PATH, "Shader"):
		return _resource_failure("Natural ground shader is missing")
	var shader_resource := ResourceLoader.load(SHADER_PATH, "Shader") as Shader
	if shader_resource == null:
		return _resource_failure("Natural ground shader could not be loaded")
	_profile = profile.duplicate(true)
	_textures = prepared
	_shader = shader_resource
	return true


func _load_texture(path: String, expected_size: Vector2i) -> Texture2D:
	if not ResourceLoader.exists(path, "Texture2D"):
		_resource_failure("Natural ground texture is unavailable: " + path)
		return null
	var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
	if texture == null or texture.get_size() != Vector2(expected_size):
		_resource_failure("Natural ground texture dimensions are invalid: " + path)
		return null
	return texture


func _build_material() -> void:
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = _shader
	_ground_material.set_shader_parameter("soil_texture", _textures.soil)
	_ground_material.set_shader_parameter("grass_texture", _textures.grass)
	_ground_material.set_shader_parameter("stone_texture", _textures.stone)
	_ground_material.set_shader_parameter("mix_mask", _textures.mask)
	_ground_material.set_shader_parameter("ground_origin_world", EXPECTED_BOUNDS.position)
	_ground_material.set_shader_parameter("ground_bounds_size", EXPECTED_BOUNDS.size)
	var scale_data: Array = _profile.world_units_per_ground_metre
	# The authored metre scale already includes the 0.65 source projection.
	# Do not multiply by camera zoom or apply projection a second time.
	_ground_material.set_shader_parameter("world_units_per_ground_metre", Vector2(float(scale_data[0]), float(scale_data[1])))
	for key: String in REPEAT_KEYS:
		_ground_material.set_shader_parameter(key + "_repeats_per_ground_metre", float(_profile.tile_repeats_per_ground_metre[key]))
	build_count += 1


func _resource_failure(reason: String) -> bool:
	_resource_error = reason
	return false


func _number_array(value: Variant, length: int) -> bool:
	if not value is Array or value.size() != length:
		return false
	for number: Variant in value:
		if not _finite_number(number):
			return false
	return true


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
