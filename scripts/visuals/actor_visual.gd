class_name ActorVisual
extends Node2D
## One foot-root per runtime identity. All children form one Y-sorted unit.
## Shared textures, no AnimationPlayer/SubViewport/3D node and no gameplay writes.
const Catalog = preload("res://scripts/visuals/actor_sprite_catalog.gd")
const Visuals = preload("res://scripts/visuals/arena_visuals.gd")
const Art = preload("res://scripts/visuals/fantasy_actors.gd")

class Part extends Node2D:
	var actor: Node2D
	var limbs := false
	var redraw_requests := 0
	var draw_count := 0
	var measured_frame := -1
	var measured_usec := 0
	func invalidate() -> void:
		redraw_requests += 1
		queue_redraw()
	func _get(property: StringName) -> Variant:
		# The old hero is a read-through fallback, translated to a foot origin.
		if property == &"player_pos": return Vector2(0, -14)
		if property == &"player_facing": return actor.facing
		if property == &"elapsed": return actor.animation_time
		return actor.source.get(property) if is_instance_valid(actor.source) else null
	func _draw() -> void:
		if actor.preferences == null: return
		var began: int = Time.get_ticks_usec() if Visuals.diagnostic_profile_enabled else 0
		draw_count += 1
		if limbs:
			if not actor.is_hero and actor.atlas.is_empty():
				draw_set_transform(Vector2(0, -float(actor.enemy.radius) * 0.56))
				Art.draw_enemy_limbs(self, actor.enemy, actor.preferences, actor.pose_time)
		elif not actor.atlas.is_empty():
			var scale_value: float = actor.atlas.display_scale
			var destination := Rect2(-Vector2(actor.atlas.foot_anchor) * scale_value, Vector2(Catalog.FRAME_SIZE) * scale_value)
			var tint := Color(1.22, 1.13, 1.02) if actor.hurt else Color.WHITE
			draw_texture_rect_region(actor.atlas.texture, destination, Catalog.frame_rect(actor.frame), tint)
			if actor.is_hero: _draw_hero_wards()
		elif actor.is_hero:
			Art.draw_player(self, actor.preferences)
		else:
			draw_set_transform(Vector2(0, -float(actor.enemy.radius) * 0.56))
			Art.draw_enemy_body(self, actor.enemy)
		draw_set_transform(Vector2.ZERO)
		if Visuals.diagnostic_profile_enabled:
			measured_frame = Engine.get_process_frames(); measured_usec = Time.get_ticks_usec() - began
	func _draw_hero_wards() -> void:
		if not is_instance_valid(actor.source): return
		var ratio := clampf(float(actor.source.shield) / maxf(1.0, float(actor.source._stats.get("max_shield", 1.0))), 0.0, 1.0)
		if ratio > 0.0 or float(actor.source.invulnerable) > 0.0:
			draw_set_transform(Vector2(0, -25))
			Art._draw_player_ward(self, ratio, float(actor.source.invulnerable) > 0.0)

var is_hero := false
var source: Node2D
var enemy: Dictionary = {}
var preferences: VisualSettings
var atlas: Dictionary = {}
var direction := 0
var facing := Vector2.RIGHT
var animation := "idle"
var animation_time := 0.0
var pose_time := 0.0
var frame := 0
var hurt := false
var frozen := false
var configure_count := 0
var shadow_redraw_requests := 0
var measured_frame := -1
var measured_usec := 0
var body: Part
var limbs: Part
var _configured := false
var _last_time := 0.0
var _last_attack_timer := 0.0
var _last_attack_id := -1
var _last_cue_id := 0
var _attack_left := 0.0
var _body_key: Array = []
var _limb_key: Array = []
var _shadow_key: Array = []

func _init() -> void:
	y_sort_enabled = false
	z_index = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	limbs = Part.new(); limbs.name = "Limbs"; limbs.actor = self; limbs.limbs = true; add_child(limbs)
	body = Part.new(); body.name = "Body"; body.actor = self; add_child(body)

func configure_enemy(value: Dictionary, settings: VisualSettings, time: float, player: Vector2, is_frozen: bool, attack: Dictionary = {}) -> void:
	var next_position: Vector2 = value.pos
	var displacement := next_position - position if _configured else Vector2.ZERO
	var timer := float(value.get("attack_timer", 0.0))
	var attacking := _configured and timer > _last_attack_timer + 0.00001
	var attack_direction := player - next_position
	if not attack.is_empty():
		var attack_id := int(attack.get("attack_id", 0))
		if attack_id != _last_attack_id:
			attacking = true
			attack_direction = Vector2(attack.get("center", player)) - next_position
		_last_attack_id = attack_id
	_last_attack_timer = timer
	enemy = value; preferences = settings; frozen = is_frozen
	atlas = Catalog.resource(Catalog.enemy_key(value))
	hurt = float(value.get("flash", 0.0)) > 0.0
	_update_pose(next_position, displacement, time, attacking, attack_direction)
	_refresh_commands()

func configure_hero(arena: Node2D, time: float, attack_cue: Dictionary = {}) -> void:
	is_hero = true; source = arena; preferences = arena.visual_settings; frozen = false
	atlas = Catalog.resource("hero")
	var next_position: Vector2 = arena.player_pos
	var displacement := next_position - position if _configured else Vector2.ZERO
	var timer := float(arena.get("attack_timer")) if arena.get("attack_timer") != null else 0.0
	var attacking := _configured and timer > _last_attack_timer + 0.00001
	var attack_direction: Vector2 = arena.player_facing
	if not attack_cue.is_empty() and int(attack_cue.id) > _last_cue_id:
		attacking = true; _last_cue_id = int(attack_cue.id)
		attack_direction = attack_cue.direction
	_last_attack_timer = timer
	if not _configured:
		facing = attack_direction.normalized() if not attack_direction.is_zero_approx() else Vector2.RIGHT
		direction = Catalog.direction_index(facing)
	hurt = float(arena.hurt_flash) > 0.0
	_update_pose(next_position, displacement, time, attacking, attack_direction)
	_refresh_commands()

func _update_pose(next_position: Vector2, displacement: Vector2, time: float, attacking: bool, attack_direction: Vector2) -> void:
	# Re-entry from offscreen does not fast-forward a frozen pose or manufacture
	# an unbounded animation catch-up. This clock also runs while walking in town.
	var delta := clampf(time - _last_time, 0.0, 0.1) if _configured else 0.0
	_last_time = time
	position = next_position
	configure_count += 1
	if not frozen:
		if not displacement.is_zero_approx(): facing = displacement.normalized()
		if attacking:
			_attack_left = 6.0 / Catalog.FPS
			if not attack_direction.is_zero_approx(): facing = attack_direction.normalized()
		direction = Catalog.direction_index(facing, direction)
		var next_animation := "attack" if _attack_left > 0.0 else "walk" if displacement.length_squared() > 0.00001 else "idle"
		if next_animation != animation or attacking:
			animation = next_animation; animation_time = 0.0
		elif preferences.motion: animation_time += delta
		_attack_left = maxf(0.0, _attack_left - delta)
	if not preferences.motion:
		frame = Catalog.frame_index(direction, "idle", 0.0, false)
		pose_time = 0.0
	elif not frozen or not _configured:
		frame = Catalog.frame_index(direction, animation, animation_time)
		pose_time = floorf(animation_time * Catalog.FPS) / Catalog.FPS
	_configured = true

func _refresh_commands() -> void:
	var radius := float(enemy.get("radius", 14.0))
	var shadow_key: Array = [radius, is_hero, atlas.is_empty()]
	if shadow_key != _shadow_key:
		_shadow_key = shadow_key; shadow_redraw_requests += 1; queue_redraw()
	var body_key: Array = [is_hero, atlas.is_empty(), radius, int(enemy.get("kind", -1)), str(enemy.get("template_id", "")), str(enemy.get("rarity", "")), hurt]
	if not atlas.is_empty(): body_key.append(frame)
	if is_hero:
		body_key.append_array([source.shield, source.invulnerable > 0.0, source.alive])
		if atlas.is_empty(): body_key.append_array([direction, pose_time, source.state.equipped.duplicate()])
	if body_key != _body_key:
		_body_key = body_key; body.invalidate()
	var limb_key: Array = [radius, int(enemy.get("kind", -1)), str(enemy.get("template_id", "")), str(enemy.get("rarity", "")), hurt, pose_time, preferences.motion]
	limbs.visible = not is_hero and atlas.is_empty()
	if limbs.visible and limb_key != _limb_key:
		_limb_key = limb_key; limbs.invalidate()

func head_anchor() -> Vector2:
	return Catalog.hero_head_anchor() if is_hero else Catalog.enemy_head_anchor(enemy)

func visual_bounds() -> Rect2:
	return Catalog.hero_visual_bounds() if is_hero else Catalog.enemy_visual_bounds(enemy)

func _draw() -> void:
	if preferences == null or (is_hero and atlas.is_empty()): return
	var began: int = Time.get_ticks_usec() if Visuals.diagnostic_profile_enabled else 0
	var size := Vector2(21, 7) if is_hero else Catalog.shadow_bounds(enemy).size * 0.5
	# Soft concentric ellipses are static commands, shared in shape and palette.
	Art._shadow(self, Vector2.ZERO, size)
	Art._shadow(self, Vector2.ZERO, size * 0.72)
	if Visuals.diagnostic_profile_enabled:
		measured_frame = Engine.get_process_frames(); measured_usec = Time.get_ticks_usec() - began
