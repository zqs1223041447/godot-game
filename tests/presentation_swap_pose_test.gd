extends SceneTree
const Catalog = preload("res://scripts/visuals/actor_sprite_catalog.gd")
const Actor = preload("res://scripts/visuals/actor_visual.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func _initialize() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/actors/studies/hero_direction_study.json"))
	var prepared: Dictionary = Catalog.prepare_presentation(raw)
	if not prepared.ok: push_error(str(prepared)); quit(1); return
	var actor := Actor.new()
	actor.is_hero = true
	actor.preferences = Settings.new()
	actor.direction = 5; actor.facing = Vector2(-1,-1).normalized()
	actor._last_attack_timer = 2.0; actor._last_cue_id = 64
	var observed := var_to_bytes([actor.direction, actor.facing, actor._last_attack_timer, actor._last_cue_id])
	for use_study: bool in [true, false]:
		actor.preferences.motion = use_study # Clearing while paused/motion-off must also select idle.
		actor.animation = "attack"; actor.animation_time = 0.3; actor.pose_time = 0.25; actor._attack_left = 0.2
		actor._body_key = ["old"]; actor._shadow_key = ["old"]
		var redraws: int = actor.body.redraw_requests
		actor.set_hero_presentation(prepared.entry if use_study else {}, 1 if use_study else 2)
		check(actor.animation == "idle" and actor.animation_time == 0.0 and actor.pose_time == 0.0 and actor._attack_left == 0.0, "New resource cannot inherit old clip countdown")
		check(actor.frame == (5 if use_study else 90), "New idle frame matches preserved facing")
		check(actor._body_key.is_empty() and actor._shadow_key.is_empty() and actor.body.redraw_requests == redraws+1, "Both presentation command caches invalidate")
		check(var_to_bytes([actor.direction, actor.facing, actor._last_attack_timer, actor._last_cue_id]) == observed, "Facing and observed attack identities are not reset or replayed")
	check(actor._hero_presentation.is_empty() and actor.atlas == Catalog.resource("hero"), "Reset releases custom entry and returns original catalog")
	actor.free()
	print("PRESENTATION_SWAP_POSE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
