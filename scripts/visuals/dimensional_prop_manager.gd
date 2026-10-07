class_name DimensionalPropManager
extends RefCounted
## Presentation-only objects attached directly to the common foot-sorted world.
## The authoritative geometry and collision are never edited.
const MANIFEST_PATH := "res://assets/environment/dimensional_manifest.json"
const STUDY_MANIFEST_PATH := "res://art-studies/v111/exports/manifest.json"
const STUDY_MODULE_IDS := ["short_wall", "walkable_arch", "moss_rock"]
var _source: Dictionary = {}
var _presentation: Dictionary = {}
var _depth: Node2D
var _nodes: Array[Node2D] = []
var _trees: Array[Dictionary] = []
var _definitions: Dictionary = {}
var _textures: Dictionary = {}
var _loaded := false
var _study_assets: Dictionary = {}
var _study_manifest_path := ""
var _study_error := ""
var _study_image_loads := 0
var _study_instances := 0
var _study_source_to_world := 0.0

func clear() -> void:
	for node: Node2D in _nodes:
		if is_instance_valid(node):
			if node.get_parent() != null: node.get_parent().remove_child(node)
			node.queue_free()
	_nodes.clear()
	_trees.clear()
	_source.clear()
	_presentation.clear()
	_study_manifest_path = ""
	_study_error = ""
	_study_instances = 0
	_study_source_to_world = 0.0

func configure(depth: Node2D, geometry: Dictionary) -> Dictionary:
	if geometry.get("id", "") in ["modular_study", "ruins_garden"]: return configure_modules(depth, geometry)
	if not is_instance_valid(depth): return geometry.duplicate(true)
	_load_assets()
	if _depth == depth and _source == geometry: return _presentation.duplicate(true)
	clear()
	_depth = depth
	_source = geometry.duplicate(true)
	_presentation = geometry.duplicate(true)
	var covered: Array[int] = []
	var walls: Array = geometry.get("walls", [])
	var style := str(geometry.get("obstacle_style", ""))
	for index: int in range(walls.size()):
		var wall: Rect2 = walls[index]
		if wall.size.x <= 0.0 or wall.size.y <= 0.0: continue
		if style == "ginkgo_planters":
			if wall.size.x <= 200.0 and wall.size.y <= 180.0:
				if _add_prop("planter", wall, "Planter_%d" % index): covered.append(index)
			else:
				# Preserve the large garden floor; its trees sit only in its blocked footprint.
				if _textures.has("tree"):
					for fraction: float in [0.25, 0.7]:
						var center := wall.position + wall.size * Vector2(fraction, 0.55)
						_add_tree(center, "GardenTree_%d_%d" % [index, int(fraction*100)])
		elif style != "spring_basin" and _textures.has("wall"):
			# Long walls are split, so actors beside their far end are not hidden by one giant sprite.
			var rows := maxi(1, ceili(wall.size.y / 96.0))
			var columns := maxi(1, ceili(wall.size.x / 128.0))
			var tile := wall.size / Vector2(columns, rows)
			for row: int in range(rows):
				for column: int in range(columns):
					_add_prop("wall", Rect2(wall.position + tile * Vector2(column,row), tile), "Wall_%d_%d_%d" % [index,row,column])
			covered.append(index)
	# Border trees add depth without pretending there is a new obstacle on walkable ground.
	var bounds: Rect2 = geometry.get("bounds", Rect2())
	if bounds.has_area() and str(geometry.get("id", "")) != "town" and _textures.has("tree"):
		var spacing := 520.0
		for column: int in range(maxi(1, floori(bounds.size.x / spacing))):
			var x := bounds.position.x + 180.0 + column * spacing
			_add_tree(Vector2(x, bounds.position.y - 80.0), "NorthTree_%d" % column)
			_add_tree(Vector2(x + 160.0, bounds.end.y + 80.0), "SouthTree_%d" % column)
	_presentation["dimensional_wall_indices"] = covered
	return _presentation.duplicate(true)

func configure_modules(depth: Node2D, geometry: Dictionary, manifest_path: String = STUDY_MANIFEST_PATH) -> Dictionary:
	# This opt-in path consumes authored module feet, never old obstacle rectangles.
	# Validate/load everything before clearing: failure cannot replace a live scene.
	_study_error = _validate_study_geometry(depth, geometry)
	if not _study_error.is_empty(): return geometry.duplicate(true)
	if not _study_safe_manifest_path(manifest_path):
		_study_error = "Study manifest must be a normalized res:// or user:// JSON path inside an exports directory"
		return geometry.duplicate(true)
	if _depth == depth and _source == geometry and _study_manifest_path == manifest_path:
		return _presentation.duplicate(true)
	var assets: Dictionary = _study_assets.get(manifest_path, {})
	if assets.is_empty():
		assets = _load_study_assets(manifest_path)
		if assets.is_empty(): return geometry.duplicate(true)
		_study_assets[manifest_path] = assets
	clear()
	_depth = depth
	_source = geometry.duplicate(true)
	_presentation = geometry.duplicate(true)
	_study_manifest_path = manifest_path
	_study_source_to_world = assets.source_to_world
	var shadows := _study_ground_batch("ModularStudyShadows")
	var details := _study_ground_batch("ModularStudyGroundDetails")
	for instance: Dictionary in geometry.module_instances:
		var definition: Dictionary = assets.modules[instance.module_id]
		var body := Node2D.new()
		body.name = "Module_" + instance.id
		body.position = instance.position
		body.z_index = 0
		body.set_meta("study_instance_id", instance.id)
		body.set_meta("study_module_id", instance.module_id)
		body.add_child(_study_sprite(definition.sprite, "Body", _study_source_to_world))
		_depth.add_child(body)
		_nodes.append(body)
		var shadow_foot := Node2D.new()
		shadow_foot.name = "Shadow_" + instance.id
		shadow_foot.position = instance.position
		shadow_foot.add_child(_study_sprite(definition.shadow, "Shadow", _study_source_to_world))
		shadows.add_child(shadow_foot)
		if definition.has("ground_detail"):
			var detail_foot := Node2D.new()
			detail_foot.name = "Sill_" + instance.id
			detail_foot.position = instance.position
			detail_foot.add_child(_study_sprite(definition.ground_detail, "Sill", _study_source_to_world))
			details.add_child(detail_foot)
		_study_instances += 1
	return _presentation.duplicate(true)

func _study_ground_batch(stable_name: String) -> Node2D:
	var batch := Node2D.new()
	batch.name = stable_name
	# The floor already has global z=-1 and precedes WorldDepth. Both batches
	# share that z and origin; unsorted subtrees retain shadow-before-sill order.
	# A z=-2 shadow would be underneath the opaque floor.
	batch.z_index = -1
	batch.z_as_relative = false
	batch.y_sort_enabled = false
	_depth.add_child(batch)
	_nodes.append(batch)
	return batch

func _study_sprite(layer: Dictionary, stable_name: String, source_to_world: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = stable_name
	sprite.texture = layer.texture
	sprite.centered = false
	sprite.position = -layer.foot * source_to_world
	sprite.scale = Vector2.ONE * source_to_world
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.set_meta("source_mipmap_count", layer.mipmap_count)
	return sprite

func _validate_study_geometry(depth: Node2D, geometry: Dictionary) -> String:
	if not is_instance_valid(depth) or depth.is_queued_for_deletion(): return "Study depth parent is unavailable"
	if geometry.get("id", "") not in ["modular_study", "ruins_garden"]: return "Modules require explicit modular_study geometry"
	var bounds: Variant = geometry.get("bounds")
	if not bounds is Rect2 or not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.end.is_finite() or not bounds.has_area():
		return "Study bounds must be a finite, positive Rect2"
	if not geometry.get("walls") is Array or not geometry.walls.is_empty(): return "Study geometry must have no legacy rectangle walls"
	var instances: Variant = geometry.get("module_instances")
	if not instances is Array or instances.is_empty() or instances.size() > 3: return "Study requires one to three module instances"
	var seen: Dictionary = {}
	for instance: Variant in instances:
		if not instance is Dictionary: return "Study module instance must be a dictionary"
		var id: Variant = instance.get("id")
		if not id is String or id.is_empty() or id.validate_node_name() != id or seen.has(id): return "Study instance IDs must be unique, nonempty node names"
		seen[id] = true
		if not instance.get("module_id") in STUDY_MODULE_IDS: return "Study module ID is not in the three authored modules"
		if not instance.get("position") is Vector2 or not instance.position.is_finite(): return "Study module foot must be a finite Vector2"
		for key: Variant in instance:
			if not key in ["id", "module_id", "position"]: return "Study instances support only id, module_id and translation; unsupported field: %s" % str(key)
	return ""

func _study_safe_manifest_path(path: String) -> bool:
	if not (path.begins_with("res://") or path.begins_with("user://")) or path.contains("\\") or not path.ends_with(".json"): return false
	var relative := path.substr(path.find("://") + 3)
	for part: String in relative.split("/"):
		if part.is_empty() or part == "." or part == ".." or part.contains(":"): return false
	return path.get_base_dir().get_file() == "exports"

func _study_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _study_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _study_number(value[0]) and _study_number(value[1])

func _load_study_assets(manifest_path: String) -> Dictionary:
	if not FileAccess.file_exists(manifest_path):
		_study_error = "Study manifest is missing: " + manifest_path
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(manifest_path)) != OK:
		_study_error = "Study manifest JSON is invalid at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary or parsed.get("schema") != "three-independent-environment-modules-v1":
		_study_error = "Study manifest has invalid JSON or schema"
		return {}
	var projection: Variant = parsed.get("projection")
	if not projection is Dictionary or not _study_number(projection.get("camera2d_zoom")) or float(projection.camera2d_zoom) <= 0.0:
		_study_error = "Study manifest requires a finite positive authored camera2d_zoom"
		return {}
	if float(projection.camera2d_zoom) != 0.65:
		_study_error = "Study manifest must retain the fixed authored camera2d_zoom of 0.65"
		return {}
	# This is the export's unit conversion, not the runtime Camera2D zoom.
	var source_to_world := 1.0 / float(projection.camera2d_zoom)
	var resolution: Variant = parsed.get("resolution")
	var source_foot: Variant = parsed.get("module_foot_source_pixel")
	if not is_finite(source_to_world) or not _study_pair(resolution) or float(resolution[0]) <= 0.0 or float(resolution[1]) <= 0.0 or not _study_pair(source_foot):
		_study_error = "Study manifest has invalid source dimensions or foot metadata"
		return {}
	var modules: Variant = parsed.get("modules")
	if not modules is Array or modules.size() != STUDY_MODULE_IDS.size():
		_study_error = "Study manifest must contain the three authored modules"
		return {}
	var prepared: Dictionary = {}
	var loaded_images := 0
	for module: Variant in modules:
		if not module is Dictionary or not module.get("id") in STUDY_MODULE_IDS or prepared.has(module.get("id")) or module.get("source_transform_baked") != true:
			_study_error = "Study manifest has an invalid, duplicate or unbaked module"
			return {}
		var layers: Dictionary = {}
		var required_layers: Array = ["sprite", "shadow"]
		if module.id == "walkable_arch": required_layers.append("ground_detail")
		for layer_name: String in required_layers:
			var suffix := "" if layer_name == "sprite" else ("_shadow" if layer_name == "shadow" else "_sill")
			var image_name: String = module.id + suffix + ".png"
			var layer := _load_study_layer(module.get(layer_name), image_name, manifest_path, resolution, source_foot)
			if layer.is_empty(): return {}
			layers[layer_name] = layer
			loaded_images += 1
		prepared[module.id] = layers
	_study_image_loads += loaded_images
	return {"modules": prepared, "source_to_world": source_to_world}

func _load_study_layer(value: Variant, image_name: String, manifest_path: String, resolution: Array, source_foot: Array) -> Dictionary:
	_study_error = "Study layer metadata is invalid: " + image_name
	if not value is Dictionary or value.get("image") != "exports/" + image_name or value.get("sprite_centered") != false: return {}
	var crop: Variant = value.get("source_pixel_rect")
	if not crop is Dictionary: return {}
	for key: String in ["x", "y", "width", "height"]:
		if not _study_number(crop.get(key)) or float(crop[key]) != floorf(float(crop[key])): return {}
	if float(crop.x) < 0.0 or float(crop.y) < 0.0 or float(crop.width) <= 0.0 or float(crop.height) <= 0.0: return {}
	if float(crop.x) + float(crop.width) > float(resolution[0]) or float(crop.y) + float(crop.height) > float(resolution[1]): return {}
	if not _study_pair(value.get("foot_local_pixel")) or not _study_pair(value.get("foot_source_pixel")): return {}
	var foot := Vector2(float(value.foot_local_pixel[0]), float(value.foot_local_pixel[1]))
	var expected_source := Vector2(float(source_foot[0]), float(source_foot[1]))
	if not (foot + Vector2(float(crop.x), float(crop.y))).is_equal_approx(expected_source): return {}
	if not Vector2(float(value.foot_source_pixel[0]), float(value.foot_source_pixel[1])).is_equal_approx(expected_source): return {}
	if foot.x < 0.0 or foot.y < 0.0 or foot.x > float(crop.width) or foot.y > float(crop.height): return {}
	var image_path := manifest_path.get_base_dir().path_join(image_name)
	if not FileAccess.file_exists(image_path):
		_study_error = "Study image is missing: " + image_path
		return {}
	var image := Image.new()
	# The archive is deliberately under .gdignore. Never ask the importer for it.
	var load_error := image.load(ProjectSettings.globalize_path(image_path))
	if load_error != OK or image.is_empty() or image.get_width() != int(crop.width) or image.get_height() != int(crop.height):
		_study_error = "Study image failed to load or disagrees with its source crop: " + image_path
		return {}
	if image.generate_mipmaps() != OK:
		_study_error = "Study image mipmaps failed: " + image_path
		return {}
	var mipmap_count := image.get_mipmap_count()
	if mipmap_count <= 0:
		_study_error = "Study image has no generated source mipmap chain: " + image_path
		return {}
	var texture := ImageTexture.create_from_image(image)
	if texture == null:
		_study_error = "Study image texture creation failed: " + image_path
		return {}
	_study_error = ""
	return {"texture": texture, "foot": foot, "image_path": image_path, "mipmap_count": mipmap_count}

func update_player(player_position: Vector2) -> void:
	for tree: Dictionary in _trees:
		var sprite: Sprite2D = tree.sprite
		if not is_instance_valid(sprite): continue
		var rect := Rect2(sprite.global_position, sprite.texture.get_size() * sprite.global_scale)
		var behind := player_position.y < float(tree.foot_y)
		var alpha := 0.42 if behind and rect.has_point(player_position) else 1.0
		if not is_equal_approx(sprite.self_modulate.a, alpha): sprite.self_modulate.a = alpha

func _load_assets() -> void:
	if _loaded: return
	_loaded = true
	if not FileAccess.file_exists(MANIFEST_PATH): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary: return
	for key: String in ["wall", "planter", "tree"]:
		var entry: Dictionary = parsed.get(key, {})
		var path := str(entry.get("texture", ""))
		if not path.begins_with("res://assets/environment/") or not ResourceLoader.exists(path): continue
		if entry.get("world_footprint", []).size() != 2 or entry.get("anchor_px", []).size() != 2: continue
		var size := Vector2(float(entry.world_footprint[0]),float(entry.world_footprint[1]))
		if size.x <= 0.0 or size.y <= 0.0 or float(entry.get("pixels_per_world",0.0)) <= 0.0: continue
		var texture := load(path) as Texture2D
		if texture == null: continue
		_definitions[key] = entry.duplicate(true)
		_textures[key] = texture

func _add_prop(key: String, footprint: Rect2, stable_name: String) -> bool:
	if not _textures.has(key): return false
	var definition: Dictionary = _definitions[key]
	var base_size := Vector2(float(definition.world_footprint[0]),float(definition.world_footprint[1]))
	var anchor := Vector2(float(definition.anchor_px[0]),float(definition.anchor_px[1]))
	var scale_value := footprint.size / base_size / float(definition.pixels_per_world)
	var node := Node2D.new()
	node.name = stable_name
	node.position = Vector2(footprint.get_center().x, footprint.end.y)
	node.z_index = 0
	var sprite := Sprite2D.new()
	sprite.texture = _textures[key]
	sprite.centered = false
	sprite.position = -anchor * scale_value
	sprite.scale = scale_value
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	node.add_child(sprite)
	_depth.add_child(node)
	_nodes.append(node)
	if key == "tree": _trees.append({"sprite":sprite,"foot_y":node.position.y})
	return true

func _add_tree(center: Vector2, stable_name: String) -> void:
	var size: Array = _definitions.tree.world_footprint
	var footprint := Vector2(float(size[0]),float(size[1]))
	_add_prop("tree", Rect2(center - footprint * 0.5, footprint), stable_name)

func diagnostics() -> Dictionary:
	var study_textures := 0
	for assets: Dictionary in _study_assets.values():
		for module: Dictionary in assets.modules.values(): study_textures += module.size()
	return {"props":_nodes.size(),"trees":_trees.size(),"shared_textures":_textures.size(),
		"study_error":_study_error,"study_instances":_study_instances,"study_shared_textures":study_textures,
		"study_image_loads":_study_image_loads,"study_source_to_world":_study_source_to_world}
