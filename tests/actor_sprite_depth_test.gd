extends SceneTree
## Atlas/frame contract, actor facing/pose clock, shared depth and hero integration.
const Layer = preload("res://scripts/visuals/retained_actor_layer.gd")
const Sprites = preload("res://scripts/visuals/actor_sprite_catalog.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
const Cues = preload("res://scripts/visuals/combat_cues.gd")
const Markers = preload("res://scripts/visuals/world_markers.gd")
class BuildFixture extends RefCounted:
	var equipped: Dictionary = {}
	func get_item_definition(_id: String) -> Dictionary: return {}
class Fixture extends Node2D:
	var enemies: Array[Dictionary] = []
	var visual_settings = Settings.new()
	var elapsed := 0.0
	var player_pos := Vector2(400, 320)
	var player_facing := Vector2.RIGHT
	var attack_timer := 0.0
	var hurt_flash := 0.0
	var shield := 0.0
	var invulnerable := 0.0
	var alive := true
	var _stats := {"max_shield": 1.0}
	var state := BuildFixture.new()
	var visual_cues := Cues.new()
	var frozen: Array[Dictionary] = []
	var attacks: Array[Dictionary] = []
	var _font: Font
	func freeze_statuses() -> Array[Dictionary]: return frozen
	func telegraph_visual_states() -> Array[Dictionary]: return attacks
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for direction: int in range(8):
		check(Sprites.direction_index(Vector2.RIGHT.rotated(direction * TAU / 8.0)) == direction, "Eight directions follow east through southeast to northeast")
		check(Sprites.direction_index(Vector2.ZERO, direction) == direction, "Stationary facing is retained")
		for animation: String in Sprites.CLIPS:
			var clip: Vector2i = Sprites.CLIPS[animation]
			for frame: int in range(clip.y):
				var index := Sprites.frame_index(direction, animation, frame / 12.0 + 0.00001)
				check(index == direction * 18 + clip.x + frame, "Direction-major offset is exact")
				var rect := Sprites.frame_rect(index)
				check(rect.size == Vector2(128, 192) and rect.position == Vector2((index % 16) * 128, (index / 16) * 192), "Source region never uses padded rows")
	check(Sprites.frame_rect(15).position == Vector2(1920, 0) and Sprites.frame_rect(16).position == Vector2(0, 192) and Sprites.frame_rect(143).position == Vector2(1920, 1536), "Atlas rows wrap at exactly sixteen columns")
	check(Sprites.frame_index(3, "attack", 100.0) == 3 * 18 + 17, "Attack clamps its last frame and does not loop damage-looking swings")
	check(Sprites.frame_index(4, "idle", 1.0) == 4 * 18, "Idle loops four frames")
	check(Sprites.frame_index(0, "walk", 100.0, false) == 4, "Disabled motion has a single frame")
	check(Sprites.DEFINITIONS.hero.foot_anchor == Vector2(64, 158) and Sprites.DEFINITIONS.crawler.foot_anchor == Vector2(64, 142), "Each atlas has its own true grounded foot anchor")
	# Synthetic shared texture keeps this test independent of final production art.
	var saved_resources: Dictionary = Sprites._resources.duplicate()
	var image := Image.create(2048, 1728, false, Image.FORMAT_RGBA8); image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	Sprites._resources["hero"] = {"texture": texture, "display_scale": 0.625, "foot_anchor": Vector2(64, 158), "head_anchor": Vector2(0, -80), "visual_bounds": Rect2(-35, -80, 70, 83)}
	Sprites._resources["crawler"] = {"texture": texture, "display_scale": 0.43, "foot_anchor": Vector2(64, 142), "head_anchor": Vector2(0, -55), "visual_bounds": Rect2(-27, -55, 54, 59)}
	var host := Fixture.new(); root.add_child(host); host._font = load("res://assets/fonts/arena_sans.otf")
	var layer := Layer.new(); host.add_child(layer)
	var prop := Node2D.new(); prop.position = Vector2(400, 310); layer.add_child(prop)
	host.enemies.append(Monsters.make_enemy(1, "crawler", 1, Vector2(400, 300)))
	layer.sync(host)
	var hero: Node2D = layer._hero; var actor: Node2D = layer._actors[1]
	check(hero.get_parent() == prop.get_parent() and actor.get_parent() == prop.get_parent() and hero.z_index == actor.z_index and hero.z_index == prop.z_index and layer.y_sort_enabled, "Hero monster and prop participate in exactly one foot sort")
	check(hero.position.y > prop.position.y and actor.position.y < prop.position.y, "Feet rather than art tops establish initial behind/front ordering")
	host.player_pos.y = 290; host.enemies[0].pos.y = 330; layer.advance(1.0 / 60.0); layer.sync(host)
	check(hero.position.y < prop.position.y and actor.position.y > prop.position.y, "Crossing a prop swaps the player and monster foot order")
	check(hero.atlas.texture == actor.atlas.texture and actor.rotation == 0.0 and hero.rotation == 0.0, "Atlas resources are shared and bodies never rotate as a flat card")
	var expected_direction := 2
	check(actor.direction == expected_direction and actor.animation == "walk", "Actual displacement chooses walking direction")
	for index: int in range(8):
		host.enemies[0].pos += Vector2(0, 1); host.player_pos += Vector2(1, 0); layer.advance(1.0 / 60.0); layer.sync(host)
	check(host.elapsed == 0.0 and hero.animation == "walk" and hero.frame != 4, "Town movement advances frames without advancing combat elapsed")
	var position_before: Vector2 = host.enemies[0].pos
	host.player_pos = Vector2(50, 40); layer.advance(1.0 / 60.0); layer.sync(host)
	check(actor.direction == expected_direction and host.enemies[0].pos == position_before and actor.animation == "idle", "Idle monsters retain their heading instead of turning to chase the player")
	host.enemies[0].attack_timer = 0.0; layer.sync(host)
	host.enemies[0].attack_timer = 0.85; host.player_pos = host.enemies[0].pos + Vector2(-50, 0); layer.advance(1.0 / 60.0); layer.sync(host)
	check(actor.direction == 4 and actor.animation == "attack", "A real contact timer reset supplies an actual attack heading")
	var frozen_frame: int = actor.frame; var frozen_direction: int = actor.direction
	host.frozen = [{"target_kind": "monster", "target_id": 1, "remaining_seconds": 2.0, "position": host.enemies[0].pos}]
	for index: int in range(20):
		host.enemies[0].pos += Vector2(1, 0); layer.advance(1.0 / 60.0); layer.sync(host)
	check(actor.frame == frozen_frame and actor.direction == frozen_direction and actor.position == host.enemies[0].pos, "Freeze stops pose and heading while preserving authoritative knockback position")
	host.frozen.clear(); layer.advance(0.1); layer.sync(host)
	check(actor.frame != frozen_frame, "Thaw resumes the retained pose")
	host.visual_settings.motion = false
	layer.sync(host); var still_frame: int = actor.frame
	for index: int in range(20): layer.advance(0.1); layer.sync(host)
	check(actor.frame == still_frame and still_frame % 18 == 0 and hero.frame % 18 == 0, "Motion preference uses static directional idle frames for both actors")
	host.visual_settings.motion = true
	host.attacks = [{"source_id": 1, "attack_id": 45, "center": host.enemies[0].pos + Vector2(0, -100), "phase": "windup"}]
	layer.advance(1.0 / 60.0); layer.sync(host)
	check(actor.direction == 6 and actor.animation == "attack", "Locked telegraph target determines attack direction without affecting its resolution")
	var locked_direction: int = actor.direction; host.player_pos += Vector2(100, 400); layer.sync(host)
	check(actor.direction == locked_direction, "An ongoing windup does not track a new player position")
	var cue_id := host.visual_cues.emit_cue("cast", host.player_pos, {"direction": Vector2.UP})
	layer.advance(1.0 / 60.0); layer.sync(host)
	check(cue_id > 0 and hero.direction == 6 and hero.animation == "attack", "Existing player cast cue drives only the visual attack clip")
	check(actor.head_anchor() == Vector2(0, -55) and hero.head_anchor() == Vector2(0, -80), "Head labels have visual rather than collision-radius anchors")
	var name_y: float = Markers.name_origin(host, host.enemies[0], host.visual_settings).y
	host.enemies[0].radius *= 3.0
	check(Markers.name_origin(host, host.enemies[0], host.visual_settings).y == name_y, "Atlas name position is independent of collision radius")
	# Grounded head bounds allow the foot below the screen without dropping its body.
	var frame := {"ok": true, "rect": Rect2(0, 0, 640, 360), "aa_margin": 0.0}
	host.enemies[0].radius = 1.0; host.enemies[0].pos = Vector2(320, 400)
	check(Layer._actor_visible(host.enemies[0], frame), "Tall atlas body remains visible with its tiny collision circle offscreen")
	host.enemies[0].pos.y = 416
	check(not Layer._actor_visible(host.enemies[0], frame), "Alpha bounds reject an atlas only after the full visual silhouette leaves")
	var before := var_to_bytes([host.enemies, host.frozen, host.attacks, host.elapsed, host.player_pos, host.attack_timer, host.visual_cues.cues])
	seed(105001); var expected_rng := randi(); seed(105001)
	layer.advance(0.1); layer.sync(host)
	check(var_to_bytes([host.enemies, host.frozen, host.attacks, host.elapsed, host.player_pos, host.attack_timer, host.visual_cues.cues]) == before and randi() == expected_rng, "Presentation consumes no RNG and mutates no simulation or cue bytes")
	layer.clear(); check(prop.get_parent() == layer and layer._hero == null, "Clear removes the hero but leaves scene-owned props")
	Sprites._resources = saved_resources
	host.queue_free(); await process_frame; await process_frame
	print("Actor atlas and depth: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
