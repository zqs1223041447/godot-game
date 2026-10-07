extends SceneTree
## Narrow v106 delta: new atlases, all template mappings, and mixed-family retention.
## Existing v105 depth/culling acceptance is reused, not rerun as an aggregate gate.
const Sprites = preload("res://scripts/visuals/actor_sprite_catalog.gd")
const Layer = preload("res://scripts/visuals/retained_actor_layer.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
const EXPECTED := {
	"crawler": "crawler", "splitter": "crawler",
	"skitter": "skitter", "mist_skitter": "skitter", "storm_skitter": "skitter",
	"brute": "brute", "brood_host": "brute", "frost_guard": "brute", "chaos_guard": "brute", "ember_guard": "brute",
	"rift_warden": "rift_warden",
}
const NEW_FAMILIES := ["skitter", "brute", "rift_warden"]
class Fixture extends Node2D:
	var enemies: Array[Dictionary] = []
	var visual_settings = Settings.new()
	var elapsed := 0.0
	var player_pos := Vector2(640, 360)
	var frozen: Array[Dictionary] = []
	var attacks: Array[Dictionary] = []
	func freeze_statuses() -> Array[Dictionary]: return frozen
	func telegraph_visual_states() -> Array[Dictionary]: return attacks
var checks := 0
var failures := 0
var first_failure := ""
var resources: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if first_failure.is_empty(): first_failure = label
		push_error(label)
func snapshot(host: Fixture) -> PackedByteArray:
	return var_to_bytes([host.enemies, host.frozen, host.attacks, host.elapsed, host.player_pos])
func run() -> void:
	check(Monsters.TEMPLATES.size() == 11 and EXPECTED.size() == Monsters.TEMPLATES.size(), "All eleven authored templates are accounted for")
	for template: String in Monsters.TEMPLATES:
		check(EXPECTED.has(template) and Sprites.enemy_key({"template_id": template}) == EXPECTED.get(template), "Exact family mapping: " + template)
		var tint: Color = Sprites.enemy_tint({"template_id": template})
		check(tint.a == 1.0 and minf(tint.r, minf(tint.g, tint.b)) >= 0.65 - 0.00001 and maxf(tint.r, maxf(tint.g, tint.b)) <= 1.0, "Variant tint stays opaque, bounded and non-emissive: " + template)
	for unknown: Dictionary in [{}, {"template_id": "future_species"}, {"template_id": ""}, {"template_id": 9}]:
		check(Sprites.enemy_key(unknown).is_empty() and Sprites.resource(Sprites.enemy_key(unknown)).is_empty() and Sprites.enemy_tint(unknown) == Color.WHITE, "Unknown templates select safe unmodified fallback")
	seed(106006); var resource_rng := randi(); seed(106006)
	for family: String in ["crawler", "skitter", "brute", "rift_warden"]:
		_verify_resource(family, family in NEW_FAMILIES)
	check(randi() == resource_rng, "Loading shared family resources and alpha bounds consumes zero global RNG")
	if failures == 0: await _verify_runtime()
	var report := {"checks": checks, "failures": failures, "first_failure": first_failure, "resources": resources,
		"new_resource_frames": 432, "mixed_monster_count": 100, "retained_sync_steps": 120,
		"scope": "Production import, template mapping, bounds and strict read-only retained runtime; not native graphical or frame-rate acceptance"}
	var report_path := OS.get_environment("V106_QA_REPORT")
	if not report_path.is_empty():
		var output := FileAccess.open(report_path, FileAccess.WRITE)
		if output != null: output.store_string(JSON.stringify(report, "\t") + "\n"); output.close()
	print("Monster family v106: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func _verify_resource(family: String, verify_pixels: bool) -> void:
	var entry: Dictionary = Sprites.resource(family)
	check(not entry.is_empty() and bool(entry.get("manifest_verified", false)), "Family has its real production texture and admitted manifest: " + family)
	if entry.is_empty(): return
	var path: String = Sprites.DEFINITIONS[family].path
	var manifest: Dictionary = Sprites._manifest(path.get_basename() + ".json")
	if manifest.is_empty(): return
	var anchor: Array = manifest.get("foot_anchor_px", manifest.get("foot_anchor", []))
	check(entry.foot_anchor == Vector2(float(anchor[0]), float(anchor[1])), "Per-family foot comes from render metadata: " + family)
	check(entry.display_scale == Sprites.DEFINITIONS[family].display_scale, "Presentation scale follows its explicit family definition: " + family)
	var texture: Texture2D = entry.texture
	check(texture.get_size() == Vector2(2048, 1728) and Sprites.resource(family).texture == texture, "Family shares one sixteen-column texture: " + family)
	var frames: Array = manifest.get("frames", [])
	check(frames.size() == 144, "Eight directions retain eighteen frames each: " + family)
	if verify_pixels:
		check(FileAccess.get_sha256(path) == str(manifest.get("atlas_sha256", "")), "Source PNG matches the render SHA256: " + family)
		var config := ConfigFile.new()
		check(config.load(path + ".import") == OK and config.get_value("params", "mipmaps/generate", false) and config.get_value("params", "process/fix_alpha_border", false), "Mipmaps and alpha-border fixing are enabled: " + family)
		var image: Image = texture.get_image()
		check(image != null and not image.is_empty() and image.has_mipmaps(), "Imported texture contains actual mipmap data: " + family)
		if image == null or image.is_empty(): return
		if image.is_compressed(): image.decompress()
		var used := Rect2i()
		for index: int in range(mini(frames.size(), 144)):
			var frame: Dictionary = frames[index]
			var phase := index % 18
			var clip := "idle" if phase < 4 else "walk" if phase < 12 else "attack"
			var local_frame := phase if phase < 4 else phase - 4 if phase < 12 else phase - 12
			var expected_index := Sprites.frame_index(index / 18, clip, local_frame / 12.0 + 0.00001)
			check(int(frame.index) == index and int(frame.direction) == index / 18 and str(frame.animation) == clip and int(frame.get("frame", frame.get("animation_frame", -1))) == local_frame and expected_index == index, "Manifest and animation select exactly the same frame: %s/%d" % [family, index])
			var local: Image = image.get_region(Rect2i(Sprites.frame_rect(index)))
			var bounds := local.get_used_rect()
			check(bounds.has_area() and bounds.position.x > 0 and bounds.position.y > 0 and bounds.end.x < 128 and bounds.end.y < 192, "Frame has real transparent padding on all four edges: %s/%d" % [family, index])
			var declared: Array = frame.get("alpha_bounds_px", frame.get("alpha_bounds", []))
			var declared_rect := Rect2i(int(declared[0]), int(declared[1]), int(declared[2]) - int(declared[0]), int(declared[3]) - int(declared[1])) if declared.size() == 4 else Rect2i()
			check(bounds == declared_rect, "Imported pixels agree with normalized manifest bounds: %s/%d" % [family, index])
			used = bounds if not used.has_area() else used.merge(bounds)
		check(Rect2(used) == entry.alpha_bounds_px, "Family culling union uses all measured frame pixels: " + family)
	var alpha_bounds: Rect2 = entry.alpha_bounds_px
	var scale_value: float = entry.display_scale
	var foot: Vector2 = entry.foot_anchor
	check(entry.head_anchor == (Vector2(64, alpha_bounds.position.y) - foot) * scale_value, "Name anchor tracks the family's highest real silhouette: " + family)
	check(entry.visual_bounds == Rect2((alpha_bounds.position - foot) * scale_value, alpha_bounds.size * scale_value), "Culling bounds use the family's exact pixel union and foot: " + family)
	var enemy := {"template_id": family, "radius": 1.0, "pos": Vector2.ZERO}
	var total_bounds: Rect2 = Sprites.enemy_visual_bounds(enemy)
	check(total_bounds == Rect2(entry.visual_bounds).merge(Sprites.shadow_bounds(enemy)), "Foot shadow is included without enlarging body geometry: " + family)
	var view := {"ok": true, "rect": Rect2(0, 0, 1280, 720), "aa_margin": 0.0}
	enemy.pos = Vector2(640, 720 - total_bounds.position.y - 0.5)
	check(Layer._actor_visible(enemy, view), "Body remains visible while foot is offscreen: " + family)
	enemy.pos.y += 1.0
	check(not Layer._actor_visible(enemy, view), "Body is culled only after its actual silhouette exits: " + family)
	resources[family] = {"sha256": FileAccess.get_sha256(path), "foot_anchor": [foot.x, foot.y], "display_scale": scale_value,
		"alpha_bounds": [alpha_bounds.position.x, alpha_bounds.position.y, alpha_bounds.end.x, alpha_bounds.end.y],
		"head_anchor": [entry.head_anchor.x, entry.head_anchor.y], "texture_instance_id": texture.get_instance_id(), "new_pixels_checked": verify_pixels}
	print("%s: foot=%s alpha=%s scale=%s head=%s" % [family, foot, alpha_bounds, scale_value, entry.head_anchor])
func _verify_runtime() -> void:
	var host := Fixture.new(); root.add_child(host)
	var layer := Layer.new(); host.add_child(layer)
	var templates: Array = EXPECTED.keys()
	for index: int in range(100):
		var template: String = templates[index % templates.size()]
		var enemy: Dictionary = Monsters.make_enemy(index + 1, template, 5, Vector2(120 + (index % 10) * 85, 140 + (index / 10) * 47), "map_boss" if template == "rift_warden" else "ordinary")
		check(not enemy.is_empty(), "Real runtime fixture constructs template " + template)
		host.enemies.append(enemy)
	var initial := snapshot(host)
	seed(106106); var expected_rng := randi(); seed(106106)
	layer.sync(host)
	check(snapshot(host) == initial, "Initial admission preserves exact typed authoritative bytes")
	check(layer._actors.size() == 100 and layer.get_child_count() == 100, "Mixed hundred-monster fixture has one retained root per identity")
	var identities: Dictionary = {}
	var family_textures: Dictionary = {}
	for id: int in layer._actors:
		var actor: Node2D = layer._actors[id]
		var family: String = EXPECTED[str(actor.enemy.template_id)]
		check(not actor.atlas.is_empty() and actor.atlas.texture == Sprites.resource(family).texture and not actor.limbs.visible, "Each runtime template selects its exact shared family atlas")
		check(actor.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS and actor.rotation == 0.0, "Family texture uses filtered foot-root rendering")
		identities[id] = [actor.get_instance_id(), actor.body.get_instance_id(), actor.limbs.get_instance_id(), actor.atlas.texture.get_instance_id()]
		family_textures[family] = actor.atlas.texture.get_instance_id()
	check(family_textures.size() == 4 and family_textures.values().size() == 4, "Hundred monsters use precisely four family textures")
	var unique_textures: Dictionary = {}
	for texture_id: int in family_textures.values(): unique_textures[texture_id] = true
	check(unique_textures.size() == 4, "Four silhouettes are distinct assets rather than aliases")
	for step: int in range(120):
		for enemy: Dictionary in host.enemies: enemy.pos += Vector2(0.13, 0.02)
		if step == 60: host.enemies.reverse()
		var before := snapshot(host)
		layer.advance(1.0 / 60.0); layer.sync(host)
		check(snapshot(host) == before, "Animation/order sync preserves exact typed bytes at step %d" % step)
	for id: int in identities:
		var actor: Node2D = layer._actors[id]
		check(identities[id] == [actor.get_instance_id(), actor.body.get_instance_id(), actor.limbs.get_instance_id(), actor.atlas.texture.get_instance_id()], "Mixed animation preserves root, parts and shared texture identity")
		check(actor.head_anchor() == Sprites.resource(EXPECTED[str(actor.enemy.template_id)]).head_anchor, "Each actor exposes its own family's real head position")
	for enemy: Dictionary in host.enemies: enemy.flash = 0.1
	var before_flash := snapshot(host); layer.sync(host)
	check(snapshot(host) == before_flash, "Hurt feedback reads existing combat bytes without writing them")
	var hurt_counts: Dictionary = {}
	for id: int in layer._actors:
		var actor: Node2D = layer._actors[id]
		check(actor.hurt and bool(actor._body_key[-2]), "Existing hurt feedback still enters the atlas tint key")
		hurt_counts[id] = actor.body.redraw_requests
	for enemy: Dictionary in host.enemies: enemy.flash = 0.05
	var during_flash := snapshot(host); layer.sync(host)
	check(snapshot(host) == during_flash, "Hurt countdown sync remains strictly read-only")
	for id: int in hurt_counts: check(layer._actors[id].body.redraw_requests == hurt_counts[id], "Positive hurt countdown retains the identical draw tint")
	for enemy: Dictionary in host.enemies: enemy.flash = 0.0
	var after_flash := snapshot(host); layer.sync(host)
	check(snapshot(host) == after_flash, "Hurt exit sync remains strictly read-only")
	for actor: Node2D in layer._actors.values(): check(not actor.hurt, "Hurt tint clears when existing combat flash expires")
	check(randi() == expected_rng, "Family selection, bounds, retention and tint consume zero global RNG")
	var unknown: Dictionary = host.enemies[0].duplicate(true)
	unknown.id = 1001; unknown.template_id = "future_species"; unknown.pos = Vector2(400, 320)
	host.enemies.append(unknown)
	var before_unknown := snapshot(host); layer.sync(host)
	check(snapshot(host) == before_unknown and layer._actors[1001].atlas.is_empty() and layer._actors[1001].limbs.visible, "Unknown template retains safe vector fallback with exact authoritative bytes")
	check(layer._actors[1001].visual_bounds() == Sprites.fallback_enemy_visual_bounds(unknown), "Unknown fallback preserves its explicit canvas bounds")
	layer.clear(); check(layer.get_child_count() == 0 and layer._actors.is_empty(), "Family lifecycle clears all retained roots")
	host.queue_free(); await process_frame; await process_frame
