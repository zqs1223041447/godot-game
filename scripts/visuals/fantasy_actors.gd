class_name FantasyActors
extends RefCounted
## Original, deterministic top-down storybook-fantasy actors.
## Presentation only: no simulation, equipment, preference, or RNG writes.
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const INK := Color("29281f")
const IVORY := Color("e7d4a3")
const LEATHER := Color("69452e")
const SKIN := Color("dca675")

static func draw_player(arena: Node2D, preferences: VisualSettings) -> void:
	var p: Vector2 = arena.player_pos
	var facing: Vector2 = arena.player_facing.normalized()
	if facing.is_zero_approx():
		facing = Vector2.RIGHT
	var phase: float = float(arena.elapsed) if preferences.motion else 0.0
	var sway: float = sin(phase * 3.1) * 1.0 if preferences.motion else 0.0
	var stride: float = sin(phase * 7.0) * 0.75 if preferences.motion else 0.0
	var weapon_id: String = str(arena.state.equipped.get("weapon", ""))
	var weapon: Dictionary = arena.state.get_item_definition(weapon_id)
	var armor_id: String = str(arena.state.equipped.get("body_armour", arena.state.equipped.get("armor", "")))
	var armor: Dictionary = arena.state.get_item_definition(armor_id)
	var emberhide: bool = str(armor.get("base_id", armor_id)) == "emberhide_vest"
	var cloak := Color("60754c")
	if emberhide:
		cloak = Color("936546")
	elif armor_id == "return_mantle":
		cloak = Color("926045")
	elif armor_id == "guardian_robe":
		cloak = Color("79768c")
	elif armor_id == "vitality_armor":
		cloak = Color("727052")
	var hurt: bool = float(arena.hurt_flash) > 0.0
	if hurt:
		cloak = cloak.lerp(Color("f0d8b0"), 0.35)
	_shadow(arena, p + Vector2(0, 14), Vector2(21, 7))
	arena.draw_set_transform(p)
	# A pair of soft, leaf-shaped wards; no target-obscuring orbit or ring.
	var shield_ratio: float = clampf(float(arena.shield) / maxf(1.0, float(arena._stats.get("max_shield", 1.0))), 0.0, 1.0)
	if shield_ratio > 0.0:
		_draw_player_ward(arena, shield_ratio, float(arena.invulnerable) > 0.0)
	elif float(arena.invulnerable) > 0.0:
		_draw_player_ward(arena, 0.0, true)
	# The held weapon goes behind the shoulders when aiming north.
	if facing.y < -0.25:
		_draw_weapon(arena, facing, weapon_id, weapon)
	# Traveling boots under a weighted, asymmetrical wool cloak.
	for side: int in [-1, 1]:
		var foot := Vector2(side * 6.5, 14 + stride * side)
		_path(arena, [Vector2(side * 5, 6), foot], Color("36322b"), 6.0)
		_blob(arena, [foot + Vector2(-3, -2), foot + Vector2(2, -3), foot + Vector2(5, 3), foot + Vector2(-4, 4)], LEATHER, INK)
		arena.draw_line(foot + Vector2(-1, 0), foot + Vector2(3, 1), Color("a17b4e"), 1.2, true)
	_blob(arena, [Vector2(-9, -8), Vector2(-15, 2), Vector2(-18 + sway, 17), Vector2(-9, 15), Vector2(-3, 18), Vector2(4, 14), Vector2(14 + sway, 17), Vector2(12, 1), Vector2(8, -8)], cloak.darkened(0.22), INK, 2.0)
	_blob(arena, [Vector2(-10, -6), Vector2(-14, 5), Vector2(-16 + sway, 14), Vector2(-9, 12), Vector2(-5, 14), Vector2(-3, -2)], cloak)
	_blob(arena, [Vector2(4, -6), Vector2(10, -5), Vector2(12, 9), Vector2(12 + sway, 13), Vector2(6, 11)], cloak.lightened(0.07))
	_path(arena, [Vector2(-11, 2), Vector2(-12, 9), Vector2(-13 + sway, 13)], cloak.lightened(0.2), 1.0)
	_path(arena, [Vector2(7, 2), Vector2(8, 8), Vector2(10 + sway, 12)], cloak.darkened(0.32), 1.2)
	_path(arena, [Vector2(-15 + sway, 14), Vector2(-8, 12), Vector2(-5, 14)], Color("b9a577"), 1.1)
	# A russet cloth tunic, leather belt and diagonal satchel strap.
	_blob(arena, [Vector2(-7, -7), Vector2(6, -7), Vector2(8, 5), Vector2(5, 11), Vector2(-5, 11), Vector2(-8, 3)], Color("967557"), INK)
	_blob(arena, [Vector2(-4, -6), Vector2(4, -5), Vector2(5, 7), Vector2(-3, 7)], Color("b19a70"))
	_path(arena, [Vector2(-5, -7), Vector2(-1, 0), Vector2(5, 8)], LEATHER, 3.0)
	_path(arena, [Vector2(-7, 7), Vector2(0, 8), Vector2(7, 6)], Color("573c28"), 3.0)
	_poly(arena, [Vector2(-1, 6), Vector2(2, 6), Vector2(2, 9), Vector2(-1, 9)], Color("b59b62"))
	arena.draw_line(Vector2(0, 7), Vector2(1, 8), Color("433e2b"), 1.0, true)
	_blob(arena, [Vector2(-8, 6), Vector2(-3, 7), Vector2(-3, 12), Vector2(-8, 12)], Color("876341"), INK)
	arena.draw_line(Vector2(-7, 8), Vector2(-4, 8), Color("c09964"), 1.0, true)
	# One small weathered shoulder guard, never chrome armor.
	_blob(arena, [Vector2(-10, -5), Vector2(-5, -8), Vector2(-3, -3), Vector2(-9, 0)], Color("a29168"), Color("514a35"))
	arena.draw_line(Vector2(-9, -4), Vector2(-5, -6), Color("cec098"), 1.0, true)
	if emberhide:
		_blob(arena, [Vector2(-10,-5),Vector2(-5,-8),Vector2(-3,-3),Vector2(-9,0)],Color("858678"),INK)
		_draw_fire_ward(arena,Vector2(1,1),2.8)
	# Cloth sleeves lead toward the real aiming direction, ending in warm hands.
	var hand: Vector2 = facing * 15.0 + Vector2(0, 2)
	var arm_side: float = 1.0 if facing.x >= 0.0 else -1.0
	_path(arena, [Vector2(arm_side * 7, -3), Vector2(arm_side * 11, 3), hand], cloak.darkened(0.06), 6.0)
	arena.draw_circle(hand, 3.0, INK)
	arena.draw_circle(hand + Vector2(0, -0.3), 2.2, SKIN)
	var free_hand := Vector2(-arm_side * 10, 5)
	_path(arena, [Vector2(-arm_side * 7, -4), free_hand], cloak, 5.0)
	arena.draw_circle(free_hand, 2.0, SKIN.darkened(0.1))
	# Soft pointed hood, visible linen lining, cheek, nose and individual dark eyes.
	var head := Vector2(facing.x * 1.0, -11.5 + facing.y * 0.7)
	_blob(arena, [head + Vector2(-9, 1), head + Vector2(-9, -5), head + Vector2(-4, -12), head + Vector2(1, -14), head + Vector2(7, -8), head + Vector2(9, 1), head + Vector2(6, 5), head + Vector2(-5, 5)], cloak.darkened(0.08), INK, 1.8)
	_blob(arena, [head + Vector2(-8, -3), head + Vector2(-3, -10), head + Vector2(0, -11), head + Vector2(-1, -5), head + Vector2(-5, 4)], cloak.lightened(0.16))
	_blob(arena, [head + Vector2(-6, -4), head + Vector2(0, -8), head + Vector2(6, -4), head + Vector2(6, 2), head + Vector2(0, 6), head + Vector2(-6, 2)], Color("c3ae7d"), cloak.darkened(0.45), 1.2)
	var face: Vector2 = head + Vector2(facing.x * 1.4, 0.0)
	_blob(arena, [face + Vector2(-4, -4), face + Vector2(3, -4), face + Vector2(4, 1), face + Vector2(1, 4), face + Vector2(-3, 3)], SKIN)
	_blob(arena, [face + Vector2(-4, -4), face + Vector2(-1, -5), face + Vector2(-2, 3), face + Vector2(-4, 1)], Color("b88054"))
	_path(arena, [face + Vector2(-4, -3), face + Vector2(-1, -5), face + Vector2(3, -4)], Color("594333"), 1.5)
	arena.draw_circle(face + Vector2(-2 + facing.x * 0.4, -1.5), 0.7, Color("302b27"))
	arena.draw_circle(face + Vector2(2 + facing.x * 0.4, -1.5), 0.7, Color("302b27"))
	arena.draw_line(face + Vector2(facing.x, -0.3), face + Vector2(facing.x + 0.5, 1.3), Color("f0c296"), 1.0, true)
	arena.draw_line(face + Vector2(-1, 2.6), face + Vector2(1, 2.6), Color("97583f"), 1.0, true)
	# Folded collar and a single amber clasp make the face read as human.
	_blob(arena, [head + Vector2(-7, 2), head + Vector2(-1, 6), head + Vector2(6, 2), head + Vector2(4, 8), head + Vector2(-5, 8)], cloak.lightened(0.08))
	arena.draw_circle(head + Vector2(0, 6), 1.5, Color("d8b866"))
	if facing.y >= -0.25:
		_draw_weapon(arena, facing, weapon_id, weapon)
	if not arena.alive:
		_path(arena, [Vector2(-6, 20), Vector2(-1, 24), Vector2(6, 19)], Color("c89781"), 2.0)
	arena.draw_set_transform(Vector2.ZERO)

static func _weapon_form(weapon_id: String, definition: Dictionary) -> String:
	var name: String = str(definition.get("base_name", definition.get("name", "")))
	# Stable base identity takes priority over any decorated display name.
	if str(definition.get("base_id", "")) == "runewood_focus" or name == "符木法器":
		return "staff"
	if weapon_id == "prism_bow" or name.ends_with("弓"):
		return "bow"
	if weapon_id in ["swift_blade", "heavy_blade"] or name.ends_with("刃") or name.ends_with("剑"):
		return "blade"
	return "staff"

static func _draw_weapon(arena: CanvasItem, facing: Vector2, weapon_id: String, definition: Dictionary) -> void:
	if definition.is_empty() or weapon_id.is_empty():
		return
	var form: String = _weapon_form(weapon_id, definition)
	var side: Vector2 = facing.orthogonal()
	var focus: Vector2 = facing * 22.0 + Vector2(0, 2)
	if form == "bow":
		var bow := PackedVector2Array()
		for i: int in range(19):
			var a: float = lerpf(-PI * 0.5, PI * 0.5, i / 18.0)
			bow.append(focus + facing * cos(a) * 7.0 + side * sin(a) * 15.0)
		arena.draw_polyline(bow, INK, 4.4, true)
		arena.draw_polyline(bow, Color("b4864f"), 2.6, true)
		arena.draw_line(bow[0], focus - facing * 3.0, Color("e7daba"), 1.0, true)
		arena.draw_line(focus - facing * 3.0, bow[-1], Color("e7daba"), 1.0, true)
		arena.draw_line(focus - facing * 11.0, focus + facing * 12.0, Color("d0b987"), 1.6, true)
		_poly(arena, [focus + facing * 14.0, focus + facing * 8.0 + side * 2.4, focus + facing * 9.0 - side * 2.4], Color("d4d2b9"))
		for s: int in [-1, 1]:
			arena.draw_line(focus - facing * 8.0, focus - facing * 11.0 + side * s * 3.0, Color("94795f"), 1.7, true)
		arena.draw_circle(focus + facing * 7.0, 1.7, Color("cbbb7c"))
	elif form == "blade":
		_poly(arena, [focus + facing * 16.0, focus + facing * 4.0 + side * 3.5, focus - facing * 4.0 + side * 3.0, focus - facing * 5.0 - side * 3.0, focus + facing * 5.0 - side * 3.0], INK)
		_poly(arena, [focus + facing * 14.0, focus + facing * 4.0 + side * 2.2, focus - facing * 4.0 + side * 1.7, focus - facing * 4.0 - side * 1.8], Color("c9c8b0"))
		_poly(arena, [focus + facing * 14.0, focus - facing * 4.0, focus - facing * 4.0 - side * 1.8, focus + facing * 4.0 - side * 2.0], Color("81877a"))
		arena.draw_line(focus - facing * 4.0 - side * 5.2, focus - facing * 4.0 + side * 5.2, Color("ad8c51"), 2.7, true)
		arena.draw_line(focus - facing * 5.0, focus - facing * 12.0, INK, 4.2, true)
		arena.draw_line(focus - facing * 5.0, focus - facing * 12.0, Color("8d5639"), 2.3, true)
		arena.draw_circle(focus - facing * 12.0, 2.1, Color("b59a65"))
	else:
		# Gnarled wood, linen grip and a tiny ember held in a forked branch.
		var shaft: Array = [focus - facing * 15.0, focus - facing * 3.0 + side * 1.0, focus + facing * 10.0]
		_path(arena, shaft, INK, 5.0)
		_path(arena, shaft, Color("987147"), 3.0)
		arena.draw_line(focus - facing * 10.0, focus - facing * 5.0, Color("c5b28a"), 3.4, true)
		for s: int in [-1, 1]:
			_path(arena, [focus + facing * 5.0, focus + facing * 10.0 + side * s * 4.0, focus + facing * 15.0 + side * s * 3.0], Color("795735"), 2.2)
		_poly(arena, [focus + facing * 15.0, focus + facing * 12.0 + side * 2.7, focus + facing * 8.0, focus + facing * 12.0 - side * 2.7], Color("c78645"))
		arena.draw_line(focus + facing * 11.0, focus + facing * 13.0, Color("f2d89b"), 1.8, true)

static func _draw_player_ward(arena: CanvasItem, ratio: float, invulnerable: bool) -> void:
	var ward := Color(Color("c8c6a0"), 0.32 + ratio * 0.48)
	for side: int in [-1, 1]:
		if ratio > 0.0:
			_path(arena, [Vector2(side * 22, 3), Vector2(side * 24, -3), Vector2(side * 21, -11)], ward, 1.6)
			arena.draw_line(Vector2(side * 22, -5), Vector2(side * 19, -8), ward, 1.0, true)
		if invulnerable:
			_path(arena, [Vector2(side * 15, -20), Vector2(side * 18, -24), Vector2(side * 19, -19)], Color(Color("e1c58c"), 0.85), 1.5)
	if ratio > 0.0:
		# Four little stitches are proportional shield capacity feedback.
		for i: int in range(4):
			var filled: bool = ratio >= (i + 0.5) / 4.0
			arena.draw_line(Vector2(-6 + i * 4, 21), Vector2(-5 + i * 4, 23), Color("cbd0b1") if filled else Color("615e49"), 1.7, true)

static func draw_enemy(arena: Node2D, enemy: Dictionary, preferences: VisualSettings, draw_marks: bool = true) -> void:
	var p: Vector2 = enemy.pos
	var r: float = float(enemy.radius)
	var rarity: String = str(enemy.get("rarity", "normal"))
	var tier: Color = Monsters.RARITIES.get(rarity, Monsters.RARITIES.normal).color
	var phase: float = float(arena.elapsed) * 7.0 + float(enemy.get("id", 0)) if preferences.motion else 0.0
	var gait: float = sin(phase) * 1.2 if preferences.motion else 0.0
	var direction: float = (Vector2(arena.player_pos) - p).angle()
	var hurt: bool = float(enemy.get("flash", 0.0)) > 0.0
	var boss: bool = rarity == "boss"
	_shadow(arena, p + Vector2(0, r * 0.56), Vector2(r + 4.0, r * 0.36 + 3.0))
	arena.draw_set_transform(p, direction)
	match int(enemy.kind):
		0:
			_draw_scavenger(arena, r, gait, hurt)
		1:
			_draw_skitter(arena, r, gait, hurt)
		2:
			if str(enemy.get("template_id", "")) == "ember_guard":
				_draw_ember_guard(arena, r, gait, hurt)
			else:
				_draw_brute(arena, r, gait, hurt, boss)
	arena.draw_set_transform(Vector2.ZERO)
	if draw_marks:
		_draw_enemy_marks(arena, enemy, preferences, tier, r, p)

static func _draw_fire_ward(arena: CanvasItem, center: Vector2, radius: float) -> void:
	var shield: Array=[center+Vector2(-radius,-radius),center+Vector2(radius,-radius),center+Vector2(radius*0.82,radius*0.35),center+Vector2(0,radius*1.22),center+Vector2(-radius*0.82,radius*0.35)]
	_blob(arena,shield,Color("51473a"),Color("c49a62"),0.9)
	_poly(arena,[center+Vector2(0,-radius*0.72),center+Vector2(radius*0.35,-radius*0.08),center+Vector2(radius*0.28,radius*0.5),center+Vector2(-radius*0.38,radius*0.5),center+Vector2(-radius*0.46,-radius*0.12),center+Vector2(-radius*0.15,radius*0.05)],Color("d1a169"))

static func _draw_ember_guard(arena: CanvasItem, r: float, gait: float, hurt: bool) -> void:
	# An ash-stone plated quadruped, with a tied leather mantle and a carved ward.
	# All parts stay inside the existing brute's footprint; nothing burns over the field.
	var stone: Color=Color("797b6c").lerp(Color("dfcba7"),0.36 if hurt else 0.0)
	var hide: Color=Color("9a6241").lerp(Color("dfb687"),0.35 if hurt else 0.0)
	for x: float in [-0.55,0.45]:
		for side: int in [-1,1]:
			var root:=Vector2(x*r,side*r*0.40)
			var knee:=root+Vector2(gait*side,side*r*0.32)
			var foot:=knee+Vector2(-r*0.13,side*r*0.21)
			_path(arena,[root,knee,foot],INK,6.0)
			_path(arena,[root,knee,foot],hide.darkened(0.24),3.5)
			_blob(arena,[foot+Vector2(-3,-2),foot+Vector2(3,-2),foot+Vector2(4,2),foot+Vector2(-3,3)],stone.darkened(0.12),INK,1)
	_blob(arena,[Vector2(-r*1.0,-r*0.52),Vector2(-r*0.53,-r*0.69),Vector2(r*0.25,-r*0.46),Vector2(r*0.28,r*0.50),Vector2(-r*0.40,r*0.73),Vector2(-r*0.98,r*0.53),Vector2(-r*0.80,r*0.14),Vector2(-r*1.05,-r*0.12)],hide,INK,1.8)
	_path(arena,[Vector2(-r*0.92,-r*0.43),Vector2(-r*0.64,-r*0.15),Vector2(-r*0.88,r*0.44)],Color("cb9e67"),1.0)
	_blob(arena,[Vector2(-r*0.62,-r*0.48),Vector2(-r*0.30,-r*0.69),Vector2(r*0.40,-r*0.57),Vector2(r*0.59,-r*0.10),Vector2(r*0.40,r*0.55),Vector2(-r*0.30,r*0.63),Vector2(-r*0.64,r*0.32)],stone,INK,1.8)
	for side: int in [-1,1]:
		_blob(arena,[Vector2(-r*0.43,side*r*0.37),Vector2(-r*0.30,side*r*0.78),Vector2(r*0.12,side*r*0.92),Vector2(r*0.44,side*r*0.64),Vector2(r*0.36,side*r*0.30)],stone.lightened(0.06 if side<0 else -0.07),INK,1.5)
		_path(arena,[Vector2(-r*0.28,side*r*0.65),Vector2(r*0.06,side*r*0.77),Vector2(r*0.31,side*r*0.59)],Color("b5b29b"),1.0)
		arena.draw_line(Vector2(-r*0.41,side*r*0.26),Vector2(r*0.25,side*r*0.34),Color("69452e"),2.5,true)
	_blob(arena,[Vector2(r*0.39,-r*0.32),Vector2(r*0.79,-r*0.42),Vector2(r*1.10,-r*0.18),Vector2(r*1.10,r*0.18),Vector2(r*0.78,r*0.40),Vector2(r*0.38,r*0.31)],hide.darkened(0.2),INK,1.5)
	_blob(arena,[Vector2(r*0.45,-r*0.31),Vector2(r*0.81,-r*0.30),Vector2(r*0.90,0),Vector2(r*0.80,r*0.29),Vector2(r*0.47,r*0.28),Vector2(r*0.59,0)],stone.lightened(0.05),INK,1)
	for side: int in [-1,1]:
		arena.draw_line(Vector2(r*0.75,side*r*0.19),Vector2(r*0.91,side*r*0.17),Color("372a21"),3.0,true)
		arena.draw_line(Vector2(r*0.77,side*r*0.19),Vector2(r*0.87,side*r*0.18),Color("dfab68"),1.0,true)
		_poly(arena,[Vector2(r*0.56,side*r*0.36),Vector2(r*0.73,side*r*0.57),Vector2(r*0.84,side*r*0.40)],Color("b9a582"))
	_draw_fire_ward(arena,Vector2(-r*0.12,0),r*0.24)

static func _draw_scavenger(arena: CanvasItem, r: float, gait: float, hurt: bool) -> void:
	var hide := Color("a48a58").lerp(Color("e5c59b"), 0.4 if hurt else 0.0)
	var shell := Color("777b48").lerp(Color("dfd0a0"), 0.45 if hurt else 0.0)
	# Six jointed organic legs, with light horn tips and alternating gait.
	for i: int in range(3):
		for side: int in [-1, 1]:
			var root := Vector2((i - 1) * r * 0.55, side * r * 0.30)
			var joint := root + Vector2((i - 1) * r * 0.2 + gait * side, side * r * 0.49)
			var toe := joint + Vector2(-r * 0.28, side * r * 0.20)
			_path(arena, [root, joint, toe], INK, 3.8)
			_path(arena, [root, joint, toe], Color("977348"), 2.1)
			arena.draw_line(toe, toe + Vector2(-2, side), IVORY.darkened(0.22), 1.0, true)
	_blob(arena, [Vector2(-r * 0.98, 0), Vector2(-r * 0.79, -r * 0.56), Vector2(-r * 0.1, -r * 0.68), Vector2(r * 0.38, -r * 0.39), Vector2(r * 0.51, r * 0.31), Vector2(-r * 0.23, r * 0.66), Vector2(-r * 0.85, r * 0.44)], hide, INK, 1.6)
	# Overlapping, curved mossy segments replace the metal polygon carapace.
	for i: int in range(3):
		var x: float = -r * 0.64 + i * r * 0.33
		_blob(arena, [Vector2(x - r * 0.22, -r * 0.29), Vector2(x, -r * 0.57), Vector2(x + r * 0.27, -r * 0.36), Vector2(x + r * 0.32, r * 0.31), Vector2(x, r * 0.52), Vector2(x - r * 0.19, r * 0.28)], shell.lightened(i * 0.04), Color("595d36"), 1.0)
		_path(arena, [Vector2(x - r * 0.1, -r * 0.3), Vector2(x + r * 0.02, -r * 0.42), Vector2(x + r * 0.15, -r * 0.30)], Color("b3ac6b"), 1.0)
	_blob(arena, [Vector2(r * 0.23, -r * 0.37), Vector2(r * 0.67, -r * 0.38), Vector2(r * 0.94, -r * 0.15), Vector2(r * 0.92, r * 0.18), Vector2(r * 0.56, r * 0.37), Vector2(r * 0.26, r * 0.29)], Color("826344"), INK, 1.2)
	for side: int in [-1, 1]:
		_path(arena, [Vector2(r * 0.64, side * r * 0.2), Vector2(r * 1.06, side * r * 0.31), Vector2(r * 1.13, side * r * 0.13)], Color("d7c18a"), 2.0)
		_path(arena, [Vector2(r * 0.64, side * r * 0.3), Vector2(r * 0.83, side * r * 0.58), Vector2(r * 1.1, side * r * 0.62)], Color("6d542f"), 1.1)
		arena.draw_circle(Vector2(r * 0.65, side * r * 0.21), 1.8, Color("302720"))
		arena.draw_circle(Vector2(r * 0.68, side * r * 0.22), 0.8, Color("edb06a"))
	arena.draw_circle(Vector2(-r * 0.45, -r * 0.12), 1.0, Color("d7c68d"))
	arena.draw_circle(Vector2(-r * 0.58, r * 0.2), 0.8, Color("595d36"))

static func _draw_skitter(arena: CanvasItem, r: float, gait: float, hurt: bool) -> void:
	var membrane := Color("bd9872").lerp(Color("e7cda7"), 0.35 if hurt else 0.0)
	var hide := Color("9b5944").lerp(Color("dfb49a"), 0.4 if hurt else 0.0)
	# Scalloped parchment wings and forward hooked claws, not an aircraft shape.
	for side: int in [-1, 1]:
		var lift: float = gait * 0.75 * side
		_blob(arena, [Vector2(r * 0.23, side * r * 0.20), Vector2(-r * 0.17, side * (r * 1.30 + lift)), Vector2(-r * 0.80, side * (r * 1.50 + lift)), Vector2(-r * 0.71, side * r * 0.88), Vector2(-r * 1.22, side * r * 0.87), Vector2(-r * 0.9, side * r * 0.43), Vector2(-r * 1.02, side * r * 0.23), Vector2(-r * 0.18, side * r * 0.07)], membrane, Color("674b36"), 1.3)
		_path(arena, [Vector2(r * 0.1, side * r * 0.2), Vector2(-r * 0.4, side * r * 0.6), Vector2(-r * 0.75, side * (r * 1.31 + lift))], Color("8e6647"), 1.0)
		arena.draw_line(Vector2(-r * 0.34, side * r * 0.53), Vector2(-r * 1.02, side * r * 0.79), Color("9d7552"), 0.9, true)
		_path(arena, [Vector2(r * 0.18, side * r * 0.30), Vector2(r * 0.70 + gait * 0.3, side * r * 0.79), Vector2(r * 1.08, side * r * 0.54)], Color("6d4433"), 3.0)
		arena.draw_line(Vector2(r * 1.06, side * r * 0.55), Vector2(r * 1.14, side * r * 0.26), IVORY, 1.5, true)
	# Curved tapering tail and a narrow, segmented abdomen.
	_path(arena, [Vector2(-r * 0.28, 0), Vector2(-r * 0.95, r * 0.10), Vector2(-r * 1.32, -r * 0.15)], Color("5b3a2c"), 3.0)
	_blob(arena, [Vector2(-r * 0.90, 0), Vector2(-r * 0.38, -r * 0.37), Vector2(r * 0.48, -r * 0.32), Vector2(r * 0.80, 0), Vector2(r * 0.46, r * 0.31), Vector2(-r * 0.33, r * 0.37)], hide, INK, 1.3)
	_path(arena, [Vector2(-r * 0.6, -r * 0.03), Vector2(-r * 0.15, -r * 0.18), Vector2(r * 0.42, -r * 0.12)], Color("c4875d"), 1.3)
	for i: int in range(2):
		var x: float = -r * 0.48 + i * r * 0.27
		arena.draw_line(Vector2(x, -r * 0.18), Vector2(x - 0.6, r * 0.21), Color("784832"), 1.0, true)
	for side: int in [-1, 1]:
		arena.draw_circle(Vector2(r * 0.54, side * r * 0.16), 1.4, Color("38291d"))
		arena.draw_circle(Vector2(r * 0.57, side * r * 0.17), 0.65, Color("edd69c"))
		_path(arena, [Vector2(r * 0.63, side * r * 0.19), Vector2(r * 1.05, side * r * 0.30), Vector2(r * 1.22, side * r * 0.08)], Color("dbc18a"), 1.2)

static func _draw_brute(arena: CanvasItem, r: float, gait: float, hurt: bool, boss: bool) -> void:
	var hide := Color("6a7651").lerp(Color("d6c69b"), 0.4 if hurt else 0.0)
	var ridge := Color("9d9761").lerp(Color("ede0b5"), 0.4 if hurt else 0.0)
	if boss:
		hide = Color("736c59").lerp(Color("d6c69b"), 0.4 if hurt else 0.0)
		ridge = Color("aaa079").lerp(Color("ede0b5"), 0.4 if hurt else 0.0)
	# Six heavy fleshy limbs, planted claws and a rounded, uneven shell.
	for i: int in range(3):
		for side: int in [-1, 1]:
			var root := Vector2((i - 1) * r * 0.52, side * r * 0.48)
			var joint := root + Vector2((i - 1) * r * 0.20 + gait * side, side * r * 0.39)
			var foot := joint + Vector2(r * 0.17, side * r * 0.15)
			_path(arena, [root, joint, foot], INK, 6.0)
			_path(arena, [root, joint, foot], Color("776444"), 3.9)
			arena.draw_line(foot, foot + Vector2(r * 0.15, side * r * 0.04), Color("d7c394"), 1.6, true)
	_blob(arena, [Vector2(-r * 1.01, -r * 0.1), Vector2(-r * 0.81, -r * 0.72), Vector2(-r * 0.14, -r * 0.91), Vector2(r * 0.61, -r * 0.66), Vector2(r * 0.86, -r * 0.15), Vector2(r * 0.78, r * 0.52), Vector2(r * 0.04, r * 0.85), Vector2(-r * 0.75, r * 0.67)], hide.darkened(0.2), INK, 2.0)
	for side: int in [-1, 1]:
		_blob(arena, [Vector2(-r * 0.87, side * r * 0.03), Vector2(-r * 0.61, side * r * 0.63), Vector2(-r * 0.10, side * r * 0.79), Vector2(r * 0.49, side * r * 0.55), Vector2(r * 0.6, side * r * 0.17), Vector2(r * 0.2, side * r * 0.04)], hide.lightened(0.07 if side < 0 else 0.0), Color("475237"), 1.3)
		_path(arena, [Vector2(-r * 0.73, side * r * 0.18), Vector2(-r * 0.42, side * r * 0.58), Vector2(r * 0.04, side * r * 0.63), Vector2(r * 0.37, side * r * 0.45)], ridge.darkened(0.12), 1.5)
		for i: int in range(3):
			var x: float = -r * 0.45 + i * r * 0.3
			arena.draw_line(Vector2(x, side * r * 0.16), Vector2(x + r * 0.09, side * r * 0.47), hide.darkened(0.2), 1.1, true)
	# Horn ridge is deliberately irregular and bone-colored, not a metal crown.
	for i: int in range(4):
		var x: float = -r * 0.62 + i * r * 0.31
		_poly(arena, [Vector2(x - r * 0.13, -r * 0.07), Vector2(x - r * 0.04, -r * 0.22), Vector2(x + r * 0.20, 0), Vector2(x - r * 0.06, r * 0.13)], ridge)
	_blob(arena, [Vector2(r * 0.42, -r * 0.42), Vector2(r * 0.89, -r * 0.4), Vector2(r * 1.03, -r * 0.11), Vector2(r * 0.99, r * 0.23), Vector2(r * 0.76, r * 0.44), Vector2(r * 0.44, r * 0.36)], Color("766349"), INK, 1.5)
	for side: int in [-1, 1]:
		_blob(arena, [Vector2(r * 0.63, side * r * 0.29), Vector2(r * 0.87, side * r * 0.48), Vector2(r * 1.18, side * r * 0.45), Vector2(r * 1.23, side * r * 0.19), Vector2(r * 1.10, side * r * 0.31), Vector2(r * 0.91, side * r * 0.27)], Color("dbca99"), Color("82704d"), 1.0)
		arena.draw_circle(Vector2(r * 0.81, side * r * 0.23), 2.2, Color("382b21"))
		arena.draw_circle(Vector2(r * 0.84, side * r * 0.23), 1.0, Color("e4b678"))
	if boss:
		# Ancient antler-like horns and a healed scar identify the warden even in gray.
		for side: int in [-1, 1]:
			var horn: Array = [Vector2(r * 0.18, side * r * 0.60), Vector2(r * 0.34, side * r * 0.95), Vector2(r * 0.66, side * r * 1.10), Vector2(r * 0.79, side * r * 0.96)]
			_path(arena, horn, Color("564b34"), 4.8)
			_path(arena, horn, Color("d6c69c"), 2.8)
			arena.draw_line(Vector2(r * 0.36, side * r * 0.95), Vector2(r * 0.23, side * r * 1.19), Color("d6c69c"), 2.0, true)
			arena.draw_line(Vector2(r * 0.55, side * r * 1.05), Vector2(r * 0.63, side * r * 1.24), Color("d6c69c"), 1.6, true)
		_path(arena, [Vector2(-r * 0.51, -r * 0.32), Vector2(-r * 0.20, -r * 0.17), Vector2(-r * 0.05, r * 0.05), Vector2(r * 0.16, r * 0.13)], Color("b88764"), 2.2)
		for i: int in range(3):
			var mark := Vector2(-r * 0.37 + i * r * 0.2, -r * 0.25 + i * r * 0.14)
			arena.draw_line(mark + Vector2(-1, 2), mark + Vector2(1, -2), Color("dcc197"), 1.0, true)

static func _draw_enemy_marks(arena: Node2D, enemy: Dictionary, preferences: VisualSettings, tier: Color, r: float, p: Vector2) -> void:
	var rarity: String = str(enemy.get("rarity", "normal"))
	var badge := p + Vector2(0, -r - 10)
	# Rarity is a small symbol and readable name; hides keep their species colors.
	if rarity != "normal" or arena.demo_mode:
		if rarity == "normal":
			arena.draw_circle(badge, 2.2, tier)
		elif rarity == "magic":
			_poly(arena, [badge + Vector2(0, -4), badge + Vector2(3, 0), badge + Vector2(0, 4), badge + Vector2(-3, 0)], tier)
		elif rarity == "rare":
			_poly(arena, [badge + Vector2(-6, -3), badge + Vector2(-2, 0), badge + Vector2(0, -5), badge + Vector2(2, 0), badge + Vector2(6, -3), badge + Vector2(4, 3), badge + Vector2(-4, 3)], tier)
		elif rarity == "boss":
			_poly(arena, [badge + Vector2(-6, -4), badge + Vector2(-4, 3), badge + Vector2(0, 6), badge + Vector2(4, 3), badge + Vector2(6, -4), badge + Vector2(2, -2), badge + Vector2(0, -6), badge + Vector2(-2, -2)], tier)
			arena.draw_line(badge + Vector2(0, -1), badge + Vector2(0, 3), Color("4b3925"), 1.4, true)
	if float(enemy.get("slow", 0.0)) > 0.0:
		# Explicit frost/snowflake sign, distinct from blue-rarity diamond.
		var status := p + Vector2(-r - 6, 0)
		arena.draw_circle(status, 5.7, Color("353c36"))
		for i: int in range(6):
			var v := Vector2.RIGHT.rotated(i * TAU / 6.0)
			arena.draw_line(status, status + v * 4.4, Color("cfdfdd"), 1.2, true)
			arena.draw_line(status + v * 3.0, status + v * 2.5 + v.orthogonal() * 1.4, Color("cfdfdd"), 0.8, true)
	if float(enemy.get("spawn", 0.0)) > 0.0 and preferences.effects_level > 0:
		var alpha: float = clampf(float(enemy.spawn), 0.0, 0.6)
		for side: int in [-1, 1]:
			_path(arena, [p + Vector2(side * (r + 1), r * 0.6), p + Vector2(side * (r + 4), r * 0.4), p + Vector2(side * (r + 3), r * 0.15)], Color(Color("c7af7f"), alpha), 1.1)
	if not enemy.get("death_spawns", []).is_empty():
		# Three seed-shaped beads describe brood-bearing creatures.
		for i: int in range(3):
			var seed := p + Vector2((i - 1) * 5, r + 6)
			_poly(arena, [seed + Vector2(0, -2.5), seed + Vector2(1.6, 0), seed + Vector2(0, 2.0), seed + Vector2(-1.6, 0)], Color("c9b990"))
	var health_ratio: float = clampf(float(enemy.health) / maxf(1.0, float(enemy.max_health)), 0.0, 1.0)
	if health_ratio < 1.0:
		var bar := Rect2(p + Vector2(-r, -r - 20), Vector2(r * 2.0, 3.0))
		arena.draw_rect(bar.grow(1), Color("302e24"))
		arena.draw_rect(bar, Color("5a5140"))
		arena.draw_rect(Rect2(bar.position, Vector2(bar.size.x * health_ratio, 3)), Color("b3b783"))
	var maximum_shield: float = float(enemy.get("max_shield", 0.0))
	if maximum_shield > 0.0:
		var shield_ratio: float = clampf(float(enemy.get("shield", 0.0)) / maximum_shield, 0.0, 1.0)
		# Separate narrow shield bar plus shield emblem; depleted remains visible.
		var bar := Rect2(p + Vector2(-r, -r - 24), Vector2(r * 2.0, 2.0))
		arena.draw_rect(bar.grow(1), Color("302e24"))
		arena.draw_rect(bar, Color("57534c"))
		arena.draw_rect(Rect2(bar.position, Vector2(bar.size.x * shield_ratio, 2)), Color("b9b6cd"))
		var sigil := p + Vector2(r + 6, -r - 21)
		_path(arena, [sigil + Vector2(-3, -3), sigil + Vector2(3, -3), sigil + Vector2(2, 1), sigil + Vector2(0, 3), sigil + Vector2(-2, 1), sigil + Vector2(-3, -3)], Color("c5c1d5"), 1.0)
	if (rarity != "normal" or arena.demo_mode) and arena._font:
		var rarity_name: String = str(Monsters.RARITIES.get(rarity, Monsters.RARITIES.normal).name).split(" · ")[-1]
		var label: String = str(enemy.get("name", "怪物")) + " · " + rarity_name
		var font_size: int = roundi(12.0 * preferences.font_scale)
		var width: float = arena._font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := p + Vector2(-width * 0.5, -r - 30)
		baseline.x = clampf(baseline.x, arena.ARENA.position.x + 3.0, arena.ARENA.end.x - width - 3.0)
		baseline.y = maxf(arena.ARENA.position.y + font_size + 2.0, baseline.y)
		arena.draw_string_outline(arena._font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color("292b23"))
		arena.draw_string(arena._font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tier)

static func _poly(canvas: CanvasItem, points: Array, color: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array(points), color)

static func _path(canvas: CanvasItem, points: Array, color: Color, width: float = 1.0) -> void:
	canvas.draw_polyline(PackedVector2Array(points), color, width, true)

static func _blob(canvas: CanvasItem, points: Array, color: Color, outline: Color = Color.TRANSPARENT, width: float = 1.0) -> void:
	# Quadratic corner rounding keeps painted silhouettes organic at small sizes.
	var contour := PackedVector2Array()
	for i: int in range(points.size()):
		var previous: Vector2 = points[(i - 1 + points.size()) % points.size()]
		var current: Vector2 = points[i]
		var next: Vector2 = points[(i + 1) % points.size()]
		var start: Vector2 = (previous + current) * 0.5
		var finish: Vector2 = (current + next) * 0.5
		for j: int in range(4):
			var t: float = j / 4.0
			contour.append(start.lerp(current, t).lerp(current.lerp(finish, t), t))
	canvas.draw_colored_polygon(contour, color)
	if outline.a > 0.0:
		contour.append(contour[0])
		canvas.draw_polyline(contour, outline, width, true)

static func _shadow(canvas: CanvasItem, position: Vector2, size: Vector2) -> void:
	var points := PackedVector2Array()
	for i: int in range(24):
		var angle: float = i * TAU / 24.0
		points.append(position + Vector2(cos(angle) * size.x, sin(angle) * size.y))
	canvas.draw_colored_polygon(points, Color(Color("22251c"), 0.38))
