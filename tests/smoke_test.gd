extends SceneTree
## Deterministic combat + UI integration checks; user:// is isolated by validate.sh.

var failures: int = 0
var checks: int = 0
var arena: Node


func _initialize() -> void:
	call_deferred("_run_checks")


func _run_checks() -> void:
	_expect(ProjectSettings.get_setting("application/config/name") == "godot游戏仓", "Project title")
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_expect(packed != null, "Main scene loads")
	if packed == null:
		_finish()
		return
	arena = packed.instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	_expect(arena is Node2D and arena.alive, "Playable arena initializes")
	_expect(arena.hud.get_node_or_null("HUDRoot") != null, "HUD root exists")
	_expect(arena.enemies.size() == 3, "Initial enemy encounter")
	_expect(arena.state.skill_slots.size() == 5, "Five populated skill slots")
	_expect(arena.health == arena.get_stats().max_health, "Life initializes full")
	_expect(arena.mana == arena.get_stats().max_mana, "Mana initializes full")
	_expect(arena.shield == arena.get_stats().max_shield, "Energy shield initializes full")

	arena.invulnerable = 0.0
	arena.shield = 10.0
	var hp: float = arena.health
	arena.hit_player(15.0)
	_expect(arena.shield == 0.0 and arena.health == hp - 5.0, "Shield absorbs damage before life")
	arena.hit_player(15.0)
	_expect(arena.health == hp - 5.0, "Brief hit immunity prevents stacked contact damage")
	arena.enemies.clear()
	arena.auto_fire = false
	arena.spawn_timer = 9999.0
	arena.shield = 0.0
	arena.mana = 0.0
	arena.tick(1.0)
	_expect(arena.mana > 0.0 and arena.shield == 0.0, "Mana regenerates while shield waits after damage")
	arena.damage_delay = 0.0
	arena.tick(1.0)
	_expect(arena.shield > 0.0, "Shield regenerates after delay")

	var original: Vector2 = arena.player_pos
	Input.action_press("move_right")
	arena.tick(0.1)
	Input.action_release("move_right")
	_expect(arena.player_pos.x > original.x, "Movement uses build move speed")
	arena.player_pos = Vector2(1236, 565)
	Input.action_press("move_right")
	Input.action_press("move_down")
	arena.tick(1.0)
	Input.action_release("move_right")
	Input.action_release("move_down")
	_expect(arena.player_pos.x <= 1223.0 and arena.player_pos.y <= 551.0, "Arena boundaries clamp player")
	arena.player_pos = Vector2(640, 335)
	var enemy: Dictionary = arena._spawn_enemy(Vector2(840, 335), 0)
	enemy.spawn = 0.0
	var enemy_x: float = enemy.pos.x
	arena._update_enemies(0.1)
	_expect(enemy.pos.x < enemy_x, "Enemy actively approaches player")
	arena.auto_fire = true
	arena.attack_timer = 0.0
	arena._update_auto_attack()
	_expect(arena.projectiles.size() > 0, "Auto attack launches real projectile")
	for i: int in range(30):
		arena._update_projectiles(0.02)
	_expect(float(enemy.health) < float(enemy.max_health), "Projectile collision damages enemy")

	arena.enemies.clear()
	arena.projectiles.clear()
	arena.mana = float(arena.get_stats().max_mana)
	_expect(arena.cast_skill(0), "Slot 1 launches ability")
	_expect(arena.projectiles.size() == 3, "Arcane ability fires three piercing projectiles")
	_expect(not arena.cast_skill(0), "Cooldown prevents ability spam")
	arena.mana = 0.0
	_expect(not arena.cast_skill(1), "Insufficient mana prevents cast")
	arena.mana = float(arena.get_stats().max_mana)
	_expect(arena.cast_skill(1), "Frost ability casts")
	_expect(arena.projectiles.back().slow == 3.0, "Frost projectiles carry slow effect")
	var nova_target: Dictionary = arena._spawn_enemy(arena.player_pos + Vector2(70, 0), 0)
	nova_target.spawn = 0.0
	var kills_before: int = arena.kills
	_expect(arena.cast_skill(2), "Nova casts")
	_expect(arena.kills > kills_before, "Nova damages nearby enemies and awards kills")
	var dash_start: Vector2 = arena.player_pos
	_expect(arena.cast_skill(3), "Dash casts")
	_expect(arena.player_pos.distance_to(dash_start) > 100.0 and arena.invulnerable > 0.0, "Dash moves player and grants immunity")
	arena.shield = 0.0
	arena.mana = 100.0
	_expect(arena.cast_skill(4) and arena.shield > 0.0, "Ward restores shield")

	arena.state.slot_skill(0, "meteor")
	arena.mana = 100.0
	var meteor_target: Dictionary = arena._spawn_enemy(arena.player_pos + Vector2(100, 0), 0)
	meteor_target.spawn = 0.0
	_expect(arena.cast_skill(0) and meteor_target.health <= 0.0, "Slotted meteor affects combat")
	arena.state.slot_skill(0, "chain")
	arena.mana = 100.0
	var chain_target: Dictionary = arena._spawn_enemy(arena.player_pos + Vector2(100, 0), 0)
	chain_target.spawn = 0.0
	_expect(arena.cast_skill(0) and chain_target.health <= 0.0, "Chain lightning affects combat")

	arena.hud.open_panel("inventory")
	_expect(arena.hud.is_blocking(), "Inventory pauses combat")
	var time_before: float = arena.elapsed
	arena._process(1.0)
	_expect(arena.elapsed == time_before, "Paused menu freezes combat clock")
	_expect(not arena.cast_skill(1), "Menus block ability casts")
	var equip_button: Button = arena.hud.find_child("Equip_swift_blade", true, false) as Button
	_expect(equip_button != null, "Equipment action exists")
	if equip_button:
		equip_button.pressed.emit()
	_expect(arena.state.equipped.weapon == "swift_blade", "Inventory button equips selected weapon")
	_expect(arena.get_stats().attack_speed > 1.7, "Equipment changes live derived stats")
	await process_frame
	arena.hud.open_panel("talents")
	var talent_button: Button = arena.hud.find_child("Allocate_power", true, false) as Button
	_expect(talent_button != null, "Talent allocation button exists")
	if talent_button:
		talent_button.pressed.emit()
	_expect(arena.state.talents.power == 1, "Talent UI spends point and raises rank")
	await process_frame
	arena.hud.open_panel("skills")
	var skill_button: Button = arena.hud.find_child("SelectSkill_bolt", true, false) as Button
	_expect(skill_button != null, "Skill library action exists")
	if skill_button:
		skill_button.pressed.emit()
	_expect(arena.state.skill_slots[0] == "bolt", "Skill UI changes target hotbar slot")
	await process_frame
	arena.hud.close_panel()
	_expect(not arena.hud.is_blocking(), "Closing menu resumes gameplay")
	arena.invulnerable = 0.0
	arena.shield = 0.0
	arena.hit_player(9999.0)
	_expect(not arena.alive and arena.hud.is_blocking(), "Death shows blocking retry screen")
	var old_level: int = arena.state.level
	arena.restart_run()
	_expect(arena.alive and arena.kills == 0 and arena.state.level == old_level, "Restart resets run and retains build")
	_expect(arena.health == arena.get_stats().max_health and not arena.hud.is_blocking(), "Restart restores vitals and closes overlay")
	_expect(arena.save_build(), "Build persists successfully")

	var preset := ConfigFile.new()
	_expect(preset.load("res://export_presets.cfg") == OK, "Export preset parses")
	_expect(preset.get_value("preset.0", "platform", "") == "Windows Desktop", "Windows export target")
	_expect(preset.get_value("preset.0.options", "binary_format/architecture", "") == "x86_64", "64-bit export architecture")
	arena.free()
	_finish()


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _finish() -> void:
	print("Combat/UI integration: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
