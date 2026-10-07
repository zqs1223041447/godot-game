class_name RetainedActorLayer
extends Node2D
## Shared WorldDepth. Actor roots and scenery roots use the same z and foot Y.
## clear() owns only actors; independently installed scenery is never removed.
const Actor = preload("res://scripts/visuals/actor_visual.gd")
const Catalog = preload("res://scripts/visuals/actor_sprite_catalog.gd")
const Visuals = preload("res://scripts/visuals/arena_visuals.gd")
var _actors: Dictionary = {}
var _hero: Node2D
var _visual_time := 0.0
var synchronization_count := 0
var measured_sync_usec := 0

func _init() -> void:
	y_sort_enabled = true
	z_index = 0

func advance(delta: float) -> void:
	if is_finite(delta) and delta > 0.0: _visual_time += delta

static func _visibility_frame(arena: Node2D) -> Dictionary:
	var viewport_rect: Rect2 = arena.get_viewport_rect()
	var canvas: Transform2D = arena.get_global_transform_with_canvas()
	if not viewport_rect.position.is_finite() or not viewport_rect.size.is_finite() or viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0:
		return {"ok": false}
	if not canvas.x.is_finite() or not canvas.y.is_finite() or not canvas.origin.is_finite() or is_zero_approx(canvas.determinant()):
		return {"ok": false}
	var inverse := canvas.affine_inverse()
	var rect := Rect2(inverse * viewport_rect.position, Vector2.ZERO)
	for corner: Vector2 in [Vector2(viewport_rect.end.x, viewport_rect.position.y), viewport_rect.end, Vector2(viewport_rect.position.x, viewport_rect.end.y)]:
		rect = rect.expand(inverse * corner)
	return {"ok": true, "rect": rect, "aa_margin": 2.0 * (inverse.x.length() + inverse.y.length())}

static func _bounds_visible(position_value: Vector2, bounds: Rect2, frame: Dictionary) -> bool:
	if not bool(frame.ok) or not position_value.is_finite() or not bounds.position.is_finite() or not bounds.size.is_finite(): return true
	return Rect2(position_value + bounds.position, bounds.size).grow(float(frame.aa_margin)).intersects(Rect2(frame.rect), true)

static func _actor_visible(enemy: Dictionary, frame: Dictionary) -> bool:
	if not is_finite(float(enemy.get("radius", 0.0))): return true
	return _bounds_visible(enemy.pos, Catalog.enemy_visual_bounds(enemy), frame)

func sync(arena: Node2D) -> void:
	var began: int = Time.get_ticks_usec() if Visuals.diagnostic_profile_enabled else 0
	var frame := _visibility_frame(arena)
	var retained_ids: Dictionary = {}
	var frozen_ids: Dictionary = {}
	if arena.has_method("freeze_statuses"):
		for status: Dictionary in arena.freeze_statuses():
			if float(status.get("remaining_seconds", 0.0)) > 0.0: frozen_ids[int(status.target_id)] = true
	var attacks: Dictionary = {}
	if arena.has_method("telegraph_visual_states"):
		for attack: Dictionary in arena.telegraph_visual_states(): attacks[int(attack.source_id)] = attack
	for enemy: Dictionary in arena.enemies:
		var id := int(enemy.id); retained_ids[id] = true
		if not _actors.has(id):
			var actor := Actor.new(); actor.name = "Enemy_%d" % id; add_child(actor); _actors[id] = actor
		var actor: Node2D = _actors[id]
		actor.visible = _actor_visible(enemy, frame)
		if actor.visible:
			actor.configure_enemy(enemy, arena.visual_settings, _visual_time, arena.player_pos, frozen_ids.has(id), attacks.get(id, {}))
	for id: int in _actors.keys():
		if not retained_ids.has(id):
			remove_child(_actors[id]); _actors[id].queue_free(); _actors.erase(id)
	# A minimal render-test fixture can omit player presentation; actual Main has it.
	if arena.get("player_facing") is Vector2:
		if not is_instance_valid(_hero):
			_hero = Actor.new(); _hero.name = "Hero"; add_child(_hero)
		_hero.visible = _bounds_visible(arena.player_pos, Catalog.hero_visual_bounds(), frame)
		if _hero.visible:
			var cue: Dictionary = {}
			var runtime: Variant = arena.get("visual_cues")
			if runtime != null:
				for candidate: Dictionary in runtime.cues:
					if str(candidate.kind) in ["cast", "cleave", "nova", "ward", "chain", "meteor"] and int(candidate.id) > int(cue.get("id", 0)): cue = candidate
			_hero.configure_hero(arena, _visual_time, cue)
	synchronization_count += 1
	if Visuals.diagnostic_profile_enabled: measured_sync_usec = Time.get_ticks_usec() - began

func clear() -> void:
	for actor: Node2D in _actors.values(): remove_child(actor); actor.queue_free()
	_actors.clear()
	if is_instance_valid(_hero): remove_child(_hero); _hero.queue_free()
	_hero = null
	_visual_time = 0.0

func diagnostics() -> Dictionary:
	var draws := 0; var requested := 0; var configurations := 0; var usec := 0
	var frame: int = Engine.get_process_frames()
	var measured: Array = _actors.values()
	if is_instance_valid(_hero): measured.append(_hero)
	for actor: Node2D in measured:
		for part: Node2D in [actor, actor.body, actor.limbs]:
			if part.measured_frame == frame: usec += part.measured_usec
	for actor: Node2D in _actors.values():
		draws += actor.body.draw_count; requested += actor.body.redraw_requests; configurations += actor.configure_count
	return {"actors": _actors.size(), "pieces": _actors.size() * 3, "body_count": _actors.size(), "body_draws": draws,
		"body_rebuild_requests": requested, "actor_configurations": configurations, "current_draw_usec": usec, "sync_usec": measured_sync_usec,
		"hero": int(is_instance_valid(_hero)), "world_depth_children": get_child_count()}
