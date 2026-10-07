class_name DimensionalPropManager
extends RefCounted
## Presentation-only objects attached directly to the common foot-sorted world.
## The authoritative geometry and collision are never edited.
const MANIFEST_PATH := "res://assets/environment/dimensional_manifest.json"
var _source: Dictionary = {}
var _presentation: Dictionary = {}
var _depth: Node2D
var _nodes: Array[Node2D] = []
var _trees: Array[Dictionary] = []
var _definitions: Dictionary = {}
var _textures: Dictionary = {}
var _loaded := false

func clear() -> void:
	for node: Node2D in _nodes:
		if is_instance_valid(node):
			if node.get_parent() != null: node.get_parent().remove_child(node)
			node.queue_free()
	_nodes.clear()
	_trees.clear()
	_source.clear()
	_presentation.clear()

func configure(depth: Node2D, geometry: Dictionary) -> Dictionary:
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
	return {"props":_nodes.size(),"trees":_trees.size(),"shared_textures":_textures.size()}
