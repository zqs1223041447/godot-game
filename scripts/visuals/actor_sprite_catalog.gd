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
