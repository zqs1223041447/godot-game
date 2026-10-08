class_name ActorSpriteCatalog
extends RefCounted
## Shared offline-rendered atlas contract. The catalog never reads game state.
## Frames are flattened direction-major: direction * 18 + clip offset + frame.
const FRAME_SIZE := Vector2i(128, 192)
const FOOT_ANCHOR := Vector2(64, 158)
const COLUMNS := 16
const DIRECTIONS := 8
const FRAMES_PER_DIRECTION := 18
const FPS := 12.0
const CLIPS := {"idle": Vector2i(0, 4), "walk": Vector2i(4, 8), "attack": Vector2i(12, 6)}
# Asset-relative anchors/bounds may be refined from the render manifest. Scales
# are presentation units only; they do not change collision radii or combat.
const DEFINITIONS := {
	"hero": {"path": "res://assets/actors/hero_atlas.png", "display_scale": 0.5, "foot_anchor": Vector2(64, 158)},
	"crawler": {"path": "res://assets/actors/crawler_atlas.png", "display_scale": 0.64, "foot_anchor": Vector2(64, 142)},
}
static var _resources: Dictionary = {}

static func direction_index(direction: Vector2, previous: int = 0) -> int:
	if not direction.is_finite() or direction.length_squared() < 0.000001:
		return posmod(previous, DIRECTIONS)
	return posmod(roundi(direction.angle() / (TAU / DIRECTIONS)), DIRECTIONS)

static func frame_index(direction: int, animation: String, seconds: float, motion: bool = true) -> int:
	var clip: Vector2i = CLIPS.get(animation, CLIPS.idle)
	var frame := maxi(0, floori(seconds * FPS)) if motion else 0
	frame = mini(frame, clip.y - 1) if animation == "attack" else posmod(frame, clip.y)
	return posmod(direction, DIRECTIONS) * FRAMES_PER_DIRECTION + clip.x + frame

static func frame_rect(index: int) -> Rect2:
	var safe := clampi(index, 0, DIRECTIONS * FRAMES_PER_DIRECTION - 1)
	return Rect2(Vector2((safe % COLUMNS) * FRAME_SIZE.x, (safe / COLUMNS) * FRAME_SIZE.y), Vector2(FRAME_SIZE))

static func enemy_key(enemy: Dictionary) -> String:
	return "crawler" if str(enemy.get("template_id", "")) == "crawler" else ""

static func resource(key: String) -> Dictionary:
	if _resources.has(key): return _resources[key]
	var result: Dictionary = {}
	if DEFINITIONS.has(key):
		var definition: Dictionary = DEFINITIONS[key]
		if ResourceLoader.exists(str(definition.path)):
			var foot_anchor: Vector2 = definition.get("foot_anchor", FOOT_ANCHOR)
			var manifest: Dictionary = _manifest(str(definition.path).get_basename() + ".json")
			if not manifest.is_empty():
				var anchor: Array = manifest.get("foot_anchor_px", manifest.get("foot_anchor", []))
				if anchor.size() == 2: foot_anchor = Vector2(float(anchor[0]), float(anchor[1]))
			var texture := load(str(definition.path)) as Texture2D
			if texture != null and texture.get_width() >= COLUMNS * FRAME_SIZE.x and texture.get_height() >= 9 * FRAME_SIZE.y:
				# Scan alpha once per shared texture, never once per actor or frame.
				var image: Image = texture.get_image()
				var bounds := Rect2(Vector2.ZERO, Vector2(FRAME_SIZE))
				if image != null and not image.is_empty():
					if image.is_compressed(): image.decompress()
					var used := Rect2i()
					for index: int in range(DIRECTIONS * FRAMES_PER_DIRECTION):
						var occupied: Rect2i = image.get_region(Rect2i(frame_rect(index))).get_used_rect()
						if occupied.has_area(): used = occupied if not used.has_area() else used.merge(occupied)
					if used.has_area(): bounds = Rect2(used)
				result = {"texture": texture, "display_scale": float(definition.display_scale), "foot_anchor": foot_anchor,
					"head_anchor": (Vector2(FOOT_ANCHOR.x, bounds.position.y) - foot_anchor) * float(definition.display_scale),
					"alpha_bounds_px": bounds, "manifest_verified": not manifest.is_empty(),
					"visual_bounds": Rect2((bounds.position - foot_anchor) * float(definition.display_scale), bounds.size * float(definition.display_scale))}
	_resources[key] = result
	return result

static func _manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return {}
	if int(parsed.get("frame_width", 0)) != FRAME_SIZE.x or int(parsed.get("frame_height", 0)) != FRAME_SIZE.y or int(parsed.get("columns", parsed.get("atlas_columns", 0))) != COLUMNS or int(parsed.get("frame_count", parsed.get("frames", []).size())) != DIRECTIONS * FRAMES_PER_DIRECTION: return {}
	var anchor: Variant = parsed.get("foot_anchor_px", parsed.get("foot_anchor", []))
	if not anchor is Array or anchor.size() != 2: return {}
	for component: Variant in anchor:
		if not (component is float or component is int) or not is_finite(float(component)): return {}
	return parsed

static func enemy_visual_bounds(enemy: Dictionary) -> Rect2:
	var entry := resource(enemy_key(enemy))
	if not entry.is_empty():
		return Rect2(entry.visual_bounds).merge(shadow_bounds(enemy))
	return fallback_enemy_visual_bounds(enemy)

static func fallback_enemy_visual_bounds(enemy: Dictionary) -> Rect2:
	# These are canvas-command bounds for the unrotated fallback, with a foot
	# offset. They include limb travel, all species' horns/wings, stroke and shadow.
	var radius := maxf(0.0, float(enemy.get("radius", 0.0)))
	var extent := 1.5 * radius + 11.0
	return Rect2(Vector2(-extent, -extent - radius * 0.56), Vector2.ONE * extent * 2.0).merge(shadow_bounds(enemy))

static func enemy_head_anchor(enemy: Dictionary) -> Vector2:
	var entry := resource(enemy_key(enemy))
	if not entry.is_empty(): return entry.head_anchor
	return Vector2(0, -float(enemy.get("radius", 0.0)) * 1.96 - 2.0)

static func hero_visual_bounds() -> Rect2:
	var entry := resource("hero")
	return Rect2(entry.visual_bounds).merge(Rect2(-24, -9, 48, 18)) if not entry.is_empty() else Rect2(-47, -62, 94, 78)

static func hero_head_anchor() -> Vector2:
	var entry := resource("hero")
	return entry.head_anchor if not entry.is_empty() else Vector2(0, -41)

static func shadow_bounds(enemy: Dictionary) -> Rect2:
	var radius := maxf(0.0, float(enemy.get("radius", 0.0)))
	var size := Vector2(radius + 4.0, radius * 0.36 + 3.0)
	return Rect2(-size, size * 2.0)

# Opt-in actor presentation data is normalized once by its owner. It is never
# inserted into _resources: resetting that owner releases its presentation.
const HERO_WARD_BOUNDS := Rect2(-26, -51, 52, 52)

static func prepare_presentation(definition: Dictionary) -> Dictionary:
	var allowed := ["schema_version", "coordinate_space", "texture_path", "world_units_per_source_pixel",
		"frames_per_direction", "fps", "frames", "clips", "contact_shadow_half_size_world", "provenance", "direction_count"]
	for key: Variant in definition:
		if not key is String or not allowed.has(key):
			return _presentation_error("unknown_field", "Presentation contains an unsupported field.")
	for key: String in allowed:
		if key not in ["provenance", "direction_count"] and not definition.has(key):
			return _presentation_error("missing_field", "Presentation requires '%s'." % key)
	if definition.has("provenance") and not definition.provenance is Dictionary:
		return _presentation_error("invalid_provenance", "Provenance must be a dictionary and is not interpreted.")
	if not _presentation_integer(definition.schema_version) or float(definition.schema_version) != 1.0:
		return _presentation_error("invalid_schema_version", "Presentation schema_version must be 1.")
	if not definition.coordinate_space is String or definition.coordinate_space != "world":
		return _presentation_error("invalid_coordinate_space", "Presentation coordinate_space must be 'world'.")
	if not definition.texture_path is String or not _presentation_texture_path(definition.texture_path):
		return _presentation_error("invalid_texture_path", "Texture must use a canonical res:// PNG path.")
	if not _presentation_number(definition.world_units_per_source_pixel) or float(definition.world_units_per_source_pixel) <= 0.0:
		return _presentation_error("invalid_scale", "World units per source pixel must be positive and finite.")
	if not _presentation_integer(definition.frames_per_direction) or float(definition.frames_per_direction) < 1.0 or float(definition.frames_per_direction) > 64.0:
		return _presentation_error("invalid_frame_count", "Frames per direction must be an integer from 1 to 64.")
	if not _presentation_number(definition.fps) or float(definition.fps) <= 0.0 or float(definition.fps) > 120.0:
		return _presentation_error("invalid_fps", "Presentation fps must be positive, finite, and at most 120.")
	var frames_per_direction := int(definition.frames_per_direction)
	var direction_count: Variant = definition.get("direction_count", DIRECTIONS)
	if not _presentation_integer(direction_count) or float(direction_count) not in [1.0, float(DIRECTIONS)]:
		return _presentation_error("invalid_direction_count", "Presentation direction_count must be 1 for a single-heading study or 8.")
	if not definition.frames is Array or definition.frames.size() != int(direction_count) * frames_per_direction:
		return _presentation_error("invalid_frames", "Frames must contain direction_count sets of frames_per_direction entries (default eight).")
	if not definition.clips is Dictionary or not definition.clips.has("idle"):
		return _presentation_error("invalid_clips", "Clips must be a dictionary containing idle.")
	var normalized_clips: Dictionary = {}
	for name: Variant in definition.clips:
		if not name is String or not ["idle", "walk", "attack"].has(name):
			return _presentation_error("invalid_clips", "Only idle, walk, and attack clips are supported.")
		var clip: Variant = definition.clips[name]
		if not clip is Array or clip.size() != 2 or not _presentation_integer(clip[0]) or not _presentation_integer(clip[1]):
			return _presentation_error("invalid_clips", "Each clip must be an integer [offset, count] pair.")
		if float(clip[0]) < 0.0 or float(clip[1]) < 1.0 or float(clip[0]) + float(clip[1]) > frames_per_direction:
			return _presentation_error("invalid_clips", "Each clip must fit within one direction's frames.")
		normalized_clips[name] = Vector2i(int(clip[0]), int(clip[1]))
	var shadow_data: Variant = definition.contact_shadow_half_size_world
	if not _presentation_pair(shadow_data):
		return _presentation_error("invalid_shadow", "Contact shadow half size must be a finite [x, y] pair.")
	if float(shadow_data[0]) < 0.0 or float(shadow_data[1]) < 0.0 or float(shadow_data[0]) > 256.0 or float(shadow_data[1]) > 256.0:
		return _presentation_error("invalid_shadow", "Contact shadow half size components must be between 0 and 256 world units.")
	var texture_path: String = definition.texture_path
	if not ResourceLoader.exists(texture_path, "Texture2D"):
		return _presentation_error("missing_texture", "Presentation PNG texture does not exist.")
	var texture := load(texture_path) as Texture2D
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return _presentation_error("invalid_texture", "Presentation PNG could not be loaded as a nonempty Texture2D.")
	var normalized_frames: Array[Dictionary] = []
	for index: int in range(definition.frames.size()):
		var frame: Variant = definition.frames[index]
		if not frame is Dictionary or not frame.has("region") or not frame.has("foot") or frame.size() != 2:
			return _presentation_error("invalid_frame", "Frame %d requires only region and foot fields." % index)
		var region_data: Variant = frame.region
		if not region_data is Array or region_data.size() != 4:
			return _presentation_error("invalid_region", "Frame %d region must be [x, y, width, height]." % index)
		for component: Variant in region_data:
			if not _presentation_integer(component):
				return _presentation_error("invalid_region", "Frame %d region components must be finite integers." % index)
		var x := float(region_data[0])
		var y := float(region_data[1])
		var width := float(region_data[2])
		var height := float(region_data[3])
		if x < 0.0 or y < 0.0 or width <= 0.0 or height <= 0.0 or x + width > texture.get_width() or y + height > texture.get_height():
			return _presentation_error("invalid_region", "Frame %d region must fit within the texture." % index)
		var foot_data: Variant = frame.foot
		if not _presentation_pair(foot_data):
			return _presentation_error("invalid_foot", "Frame %d foot must be a finite local [x, y] pair." % index)
		if float(foot_data[0]) < 0.0 or float(foot_data[1]) < 0.0 or float(foot_data[0]) > width or float(foot_data[1]) > height:
			return _presentation_error("invalid_foot", "Frame %d foot must lie within its local region, including its edges." % index)
		normalized_frames.append({"region": Rect2(x, y, width, height), "foot": Vector2(float(foot_data[0]), float(foot_data[1]))})
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return _presentation_error("invalid_texture_image", "Presentation texture must expose readable pixels.")
	if image.is_compressed() and image.decompress() != OK:
		return _presentation_error("invalid_texture_image", "Presentation texture pixels could not be decompressed.")
	if image.get_width() != texture.get_width() or image.get_height() != texture.get_height():
		return _presentation_error("invalid_texture_image", "Presentation texture pixel dimensions must match the texture.")
	var display_scale := float(definition.world_units_per_source_pixel)
	var occupied_bounds := Rect2()
	var has_occupied_bounds := false
	for frame: Dictionary in normalized_frames:
		if not _presentation_finite_rect(Rect2(-Vector2(frame.foot) * display_scale, Rect2(frame.region).size * display_scale)):
			return _presentation_error("invalid_scale", "Presentation scale produces a non-finite frame transform.")
		# Scan each frame once during preparation, never during draw or animation.
		var occupied := image.get_region(Rect2i(frame.region)).get_used_rect()
		if not occupied.has_area():
			continue
		var bounds := Rect2((Vector2(occupied.position) - Vector2(frame.foot)) * display_scale, Vector2(occupied.size) * display_scale)
		if not _presentation_finite_rect(bounds):
			return _presentation_error("invalid_scale", "Presentation scale produces non-finite world bounds.")
		occupied_bounds = occupied_bounds.merge(bounds) if has_occupied_bounds else bounds
		has_occupied_bounds = true
	var shadow_half_size := Vector2(float(shadow_data[0]), float(shadow_data[1]))
	var shadow := Rect2(-shadow_half_size, shadow_half_size * 2.0)
	var visual_bounds := occupied_bounds.merge(shadow) if has_occupied_bounds else shadow
	visual_bounds = visual_bounds.merge(HERO_WARD_BOUNDS)
	# Include one source-pixel filtering fringe (at least one world unit).
	# Rect2 stores float32 components; repeated unions can otherwise round an
	# inclusive shadow edge inward by a few millionths of a world unit.
	visual_bounds = visual_bounds.grow(maxf(1.0, display_scale))
	if not _presentation_finite_rect(visual_bounds):
		return _presentation_error("invalid_scale", "Presentation scale produces non-finite world bounds.")
	return {"ok": true, "error_code": "", "reason": "", "entry": {
		"custom_presentation": true, "texture": texture, "display_scale": display_scale,
		"frames": normalized_frames, "frames_per_direction": frames_per_direction,
		"direction_count": int(direction_count),
		"clips": normalized_clips, "fps": float(definition.fps),
		"contact_shadow_half_size": shadow_half_size, "visual_bounds": visual_bounds,
		"head_anchor": Vector2(0.0, occupied_bounds.position.y) if has_occupied_bounds else Vector2.ZERO}}

static func presentation_frame(entry: Dictionary, direction: int, animation: String, seconds: float, motion: bool = true) -> int:
	var safe_seconds := seconds if is_finite(seconds) and seconds >= 0.0 else 0.0
	if not entry.get("custom_presentation", false):
		return frame_index(direction, animation, safe_seconds, motion)
	var clips: Dictionary = entry.clips
	var frames_per_direction: int = entry.frames_per_direction
	var fps: float = entry.fps
	var selected := animation if motion and clips.has(animation) else "idle"
	var clip: Vector2i = clips[selected]
	var frame := 0
	if motion:
		var elapsed_frames := safe_seconds * fps
		if selected == "attack":
			frame = floori(minf(elapsed_frames, float(clip.y - 1)))
		else:
			# Modulo before integer conversion also handles very large finite time.
			if not is_finite(elapsed_frames):
				elapsed_frames = fposmod(safe_seconds, float(clip.y) / fps) * fps
			frame = floori(fposmod(elapsed_frames, float(clip.y)))
	return posmod(direction, int(entry.get("direction_count", DIRECTIONS))) * frames_per_direction + clip.x + frame

static func presentation_source_rect(entry: Dictionary, index: int) -> Rect2:
	if entry.get("custom_presentation", false):
		var frames: Array = entry.frames
		return frames[clampi(index, 0, frames.size() - 1)].region
	return frame_rect(index)

static func presentation_foot(entry: Dictionary, index: int) -> Vector2:
	if entry.get("custom_presentation", false):
		var frames: Array = entry.frames
		return frames[clampi(index, 0, frames.size() - 1)].foot
	return entry.get("foot_anchor", FOOT_ANCHOR)

static func _presentation_error(error_code: String, reason: String) -> Dictionary:
	return {"ok": false, "error_code": error_code, "reason": reason}

static func _presentation_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _presentation_integer(value: Variant) -> bool:
	return _presentation_number(value) and float(value) == floorf(float(value))

static func _presentation_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _presentation_number(value[0]) and _presentation_number(value[1])

static func _presentation_texture_path(path: String) -> bool:
	if not path.begins_with("res://") or not path.to_lower().ends_with(".png"):
		return false
	var relative := path.substr(6)
	if relative.contains("\\") or relative.contains(":") or relative.contains("?") or relative.contains("#"):
		return false
	for index: int in range(relative.length()):
		if relative.unicode_at(index) < 32:
			return false
	for segment: String in relative.split("/", true):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return true

static func _presentation_finite_rect(rect: Rect2) -> bool:
	return rect.position.is_finite() and rect.size.is_finite() and rect.end.is_finite()
