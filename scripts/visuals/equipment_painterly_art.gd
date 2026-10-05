class_name EquipmentPainterlyArt
extends RefCounted
## Presentation-only equipment textures. File lookup and alpha measurement happen
## once per canonical ID; draws only reuse cached resources and bounded rectangles.

const ALPHA_LAYOUT_THRESHOLD: int = 20
const INSET: float = 1.0
const ART_PATHS: Dictionary = {
	"forgeblade": "res://assets/art/equipment/forgeblade.png",
	"cinder_reed": "res://assets/art/equipment/cinder_reed.png",
	"gale_spindle": "res://assets/art/equipment/gale_spindle.png",
	"woven_bastion": "res://assets/art/equipment/woven_bastion.png",
	"tidebound_coat": "res://assets/art/equipment/tidebound_coat.png",
	"wayglass_token": "res://assets/art/equipment/wayglass_token.png",
	"pulse_seed": "res://assets/art/equipment/pulse_seed.png",
	"runewood_focus": "res://assets/art/equipment/runewood_focus.png",
	"emberhide_vest": "res://assets/art/equipment/emberhide_vest.png",
	"prism_bow": "res://assets/art/equipment/prism_bow.png",
	"ashwood_bow": "res://assets/art/equipment/ashwood_bow.png",
	"return_mantle": "res://assets/art/equipment/return_mantle.png",
	"detonation_charm": "res://assets/art/equipment/detonation_charm.png",
	"ember_wand": "res://assets/art/equipment/ember_wand.png",
	"swift_blade": "res://assets/art/equipment/swift_blade.png",
	"guardian_robe": "res://assets/art/equipment/guardian_robe.png",
	"vitality_armor": "res://assets/art/equipment/vitality_armor.png",
	"azure_charm": "res://assets/art/equipment/azure_charm.png",
	"storm_charm": "res://assets/art/equipment/storm_charm.png",
	"emberheart": "res://assets/art/equipment/emberheart.png",
	"tideglass": "res://assets/art/equipment/tideglass.png",
	"windweave": "res://assets/art/equipment/windweave.png",
	"branchfinder": "res://assets/art/equipment/branchfinder.png",
	"nine_slot_etched_ring": "res://assets/art/equipment/nine_slot_etched_ring.png",
	"nine_slot_trail_boots": "res://assets/art/equipment/nine_slot_trail_boots.png",
	"nine_slot_folded_belt": "res://assets/art/equipment/nine_slot_folded_belt.png",
	"nine_slot_threaded_gloves": "res://assets/art/equipment/nine_slot_threaded_gloves.png",
	"nine_slot_slate_helmet": "res://assets/art/equipment/nine_slot_slate_helmet.png",
}
const JEWEL_IDS: Array[String] = ["emberheart", "tideglass", "windweave", "branchfinder"]

class CachedArt extends RefCounted:
	var texture: Texture2D
	var source: Rect2

static var _cache: Dictionary = {}


static func is_hint(entry: Dictionary) -> bool:
	return bool(entry.get("hint", false)) or bool(entry.get("empty", false)) or (
		entry.get("color", Color.WHITE) == Color("516477") and not entry.has("kind") and not entry.has("name"))


static func canonical_id(entry: Dictionary) -> String:
	if is_hint(entry):
		return ""
	# Jewel instances identify their visual by base, never their serialized serial.
	var jewel_base: String = str(entry.get("base", ""))
	if str(entry.get("kind", "")) == "jewel" or JEWEL_IDS.has(jewel_base):
		return jewel_base if JEWEL_IDS.has(jewel_base) else ""
	for key: String in ["base_id", "id"]:
		var candidate: String = str(entry.get(key, ""))
		if ART_PATHS.has(candidate) and not JEWEL_IDS.has(candidate):
			return candidate
	return ""


static func resource_path(entry: Dictionary) -> String:
	return str(ART_PATHS.get(canonical_id(entry), ""))


static func _art_for_id(id: String) -> CachedArt:
	if not ART_PATHS.has(id):
		return null
	if _cache.has(id):
		return _cache[id] as CachedArt
	# Cache absence too: incomplete art packs retain the procedural fallback without
	# checking the filesystem every frame. Newly installed art is found on restart.
	_cache[id] = null
	var path: String = str(ART_PATHS[id])
	if not ResourceLoader.exists(path, "Texture2D"):
		return null
	var texture: Texture2D = ResourceLoader.load(path, "Texture2D") as Texture2D
	if texture == null:
		return null
	var source: Rect2 = alpha_bounds(texture.get_image())
	if not source.has_area():
		return null
	var art := CachedArt.new()
	art.texture = texture
	art.source = source
	_cache[id] = art
	return art


static func texture_for_entry(entry: Dictionary) -> Texture2D:
	var art: CachedArt = _art_for_id(canonical_id(entry))
	return art.texture if art != null else null


static func source_rect(entry: Dictionary) -> Rect2:
	var art: CachedArt = _art_for_id(canonical_id(entry))
	return art.source if art != null else Rect2()


static func alpha_bounds(image: Image) -> Rect2:
	if image == null or image.is_empty():
		return Rect2()
	# Work on a detached CPU image. Threshold affects layout only, never PNG pixels.
	var rgba: Image = image.duplicate()
	if rgba.is_compressed() and rgba.decompress() != OK:
		return Rect2()
	rgba.convert(Image.FORMAT_RGBA8)
	var width: int = rgba.get_width()
	var height: int = rgba.get_height()
	var data: PackedByteArray = rgba.get_data()
	var left: int = width
	var top: int = height
	var right: int = -1
	var bottom: int = -1
	for y: int in range(height):
		var row_offset: int = y * width * 4 + 3
		for x: int in range(width):
			if data[row_offset + x * 4] > ALPHA_LAYOUT_THRESHOLD:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	if right < left or bottom < top:
		return Rect2()
	return Rect2(left, top, right - left + 1, bottom - top + 1)


static func fitted_rect(bounds: Rect2, source_size: Vector2) -> Rect2:
	if not bounds.position.is_finite() or not bounds.size.is_finite() or not source_size.is_finite():
		return Rect2()
	if bounds.size.x <= INSET * 2.0 or bounds.size.y <= INSET * 2.0 or source_size.x <= 0.0 or source_size.y <= 0.0:
		return Rect2()
	var available: Vector2 = bounds.size - Vector2.ONE * INSET * 2.0
	var scale: float = minf(available.x / source_size.x, available.y / source_size.y)
	var dimensions: Vector2 = source_size * scale
	return Rect2(bounds.position + (bounds.size - dimensions) * 0.5, dimensions)


static func draw_item(canvas: CanvasItem, entry: Dictionary, rect: Rect2) -> bool:
	if canvas == null or fitted_rect(rect, Vector2.ONE).size == Vector2.ZERO:
		return false
	var art: CachedArt = _art_for_id(canonical_id(entry))
	if art == null:
		return false
	var destination: Rect2 = fitted_rect(rect, art.source.size)
	canvas.draw_texture_rect_region(art.texture, destination, art.source, Color.WHITE, false, true)
	return true
