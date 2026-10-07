extends SceneTree
## Production atlas pixels and import settings; not a graphical/raster acceptance.
const Sprites = preload("res://scripts/visuals/actor_sprite_catalog.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for key: String in ["hero", "crawler"]:
		var path: String = Sprites.DEFINITIONS[key].path
		var entry := Sprites.resource(key)
		check(not entry.is_empty() and bool(entry.get("manifest_verified", false)), "Production texture and its actual manifest schema are admitted: " + key)
		if entry.is_empty(): continue
		var manifest := Sprites._manifest(path.get_basename() + ".json")
		check(FileAccess.get_sha256(path) == manifest.atlas_sha256, "Delivered PNG matches recorded render SHA-256: " + key)
		var texture: Texture2D = entry.texture
		check(texture.get_size() == Vector2(2048, 1728), "Full production atlas is sixteen columns and nine rows: " + key)
		check(Sprites.resource(key).texture == texture, "Repeated catalog lookup reuses the exact texture resource: " + key)
		var image: Image = texture.get_image()
		check(image != null and not image.is_empty() and image.has_mipmaps(), "Imported production texture has actual mipmap data: " + key)
		if image == null or image.is_empty(): continue
		if image.is_compressed(): image.decompress()
		var used := Rect2i()
		var frames: Array = manifest.frames
		check(frames.size() == 144, "Manifest records all eight directions and three clips: " + key)
		for index: int in range(144):
			var frame: Dictionary = frames[index]
			var local: Image = image.get_region(Rect2i(Sprites.frame_rect(index)))
			var bounds := local.get_used_rect()
			var declared: Array = frame.get("alpha_bounds_px", frame.get("alpha_bounds", []))
			check(int(frame.index) == index and int(frame.direction) == index / 18, "Manifest direction-major index is exact: %s/%d" % [key, index])
			check(bounds.has_area() and bounds.position.x > 0 and bounds.position.y > 0 and bounds.end.x < 128 and bounds.end.y < 192, "Production frame is nonempty and has transparent edge padding: %s/%d" % [key, index])
			var declared_rect := Rect2i(int(declared[0]), int(declared[1]), int(declared[2]) - int(declared[0]), int(declared[3]) - int(declared[1])) if declared.size() == 4 else Rect2i()
			check(declared_rect == bounds, "Imported alpha bounds match the offline render record: %s/%d expected=%s actual=%s" % [key, index, declared_rect, bounds])
			used = bounds if not used.has_area() else used.merge(bounds)
		check(Rect2(used) == entry.alpha_bounds_px, "Catalog culling uses the measured union of all real frames: " + key)
		check(entry.head_anchor == (Vector2(64, used.position.y) - Vector2(entry.foot_anchor)) * float(entry.display_scale), "Visual labels stay above the highest real silhouette: " + key)
		print("%s atlas: alpha=%s foot=%s display_scale=%s head=%s" % [key, used, entry.foot_anchor, entry.display_scale, entry.head_anchor])
	for path: String in ["res://assets/actors/hero_atlas.png", "res://assets/actors/crawler_atlas.png", "res://assets/environment/garden_ground.png", "res://assets/environment/ruin_wall.png", "res://assets/environment/stone_planter.png", "res://assets/environment/ginkgo_tree.png"]:
		var config := ConfigFile.new()
		check(config.load(path + ".import") == OK and config.get_value("params", "mipmaps/generate", false) and config.get_value("params", "process/fix_alpha_border", false), "Atlas/scenery import retains mipmaps and fixed alpha border: " + path)
	print("Production atlas resources: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
