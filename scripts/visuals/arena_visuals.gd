class_name ArenaVisuals
extends RefCounted
## Original scalable vector artwork. This layer only reads the simulation.
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
const CueRenderer = preload("res://scripts/visuals/combat_cue_renderer.gd")
const EnvironmentArt = preload("res://scripts/visuals/fantasy_environment.gd")
const Palette = preload("res://scripts/visuals/fantasy_palette.gd")
const ActorArt = preload("res://scripts/visuals/fantasy_actors.gd")

static func polygon(canvas: CanvasItem, points: Array, color: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array(points), color)

static func regular(canvas: CanvasItem, center: Vector2, radius: float, sides: int, color: Color, angle: float = 0.0) -> void:
	var points := PackedVector2Array()
	for i: int in range(sides):
		points.append(center + Vector2.RIGHT.rotated(angle + i*TAU/sides)*radius)
	canvas.draw_colored_polygon(points, color)

static func shadow(canvas: CanvasItem, pos: Vector2, radius: float) -> void:
	canvas.draw_set_transform(pos, 0, Vector2(1,0.38))
	canvas.draw_circle(Vector2.ZERO, radius, Color(0.015,0.022,0.024,0.62))
	canvas.draw_set_transform(Vector2.ZERO)

static func draw_scene(arena: Node2D, preferences: Settings) -> void:
	draw_arena(arena)
	if not arena._ready_complete:
		return
	for pickup: Dictionary in arena.pickups:
		var p: Vector2 = pickup.pos
		shadow(arena,p+Vector2(0,7),10)
		arena.draw_circle(p, 13, Color(0.36,0.8,0.55,0.1))
		regular(arena,p,8,4,Color("37654e"),PI/4)
		regular(arena,p,5,4,Color("a3e8ac"),PI/4)
		arena.draw_line(p+Vector2(-3,0),p+Vector2(3,0),Color.WHITE,1.5,true)
		arena.draw_line(p+Vector2(0,-3),p+Vector2(0,3),Color.WHITE,1.5,true)
	for ring: Dictionary in arena.rings:
		draw_ring(arena,ring,preferences)
	var cue_runtime: Variant = arena.get("visual_cues")
	if cue_runtime != null:
		CueRenderer.render(arena,cue_runtime.cues,preferences.effects_level,true)
	# Stable ordering makes feet/shadows read as grounded figures.
	var ordered: Array = arena.enemies.duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.pos.y < b.pos.y)
	for enemy: Dictionary in ordered:
		draw_enemy(arena,enemy,preferences)
	for shot: Dictionary in arena.projectiles:
		draw_projectile(arena,shot,preferences)
	draw_player(arena,preferences)
	if cue_runtime != null:
		CueRenderer.render(arena,cue_runtime.cues,preferences.effects_level,false)
	if preferences.effects_level > 0:
		var index: int = 0
		for particle: Dictionary in arena.particles:
			index += 1
			if preferences.effects_level == 1 and index % 2 == 0:
				continue
			var color: Color = particle.color
			color.a = float(particle.life)/float(particle.max_life)*0.8
			var p: Vector2 = particle.pos
			var velocity: Vector2 = particle.velocity
			arena.draw_line(p-velocity.normalized()*4,p,color,maxf(1,float(particle.radius)*color.a),true)
	if arena._font and preferences.damage_numbers:
		for entry: Dictionary in arena.floating_text:
			var color: Color = entry.color
			color.a = minf(1,float(entry.life)*2)
			var p: Vector2 = entry.pos
			var font_size: int = roundi(17*preferences.font_scale)
			var width: float = arena._font.get_string_size(str(entry.text),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
			p.x -= width*0.5
			arena.draw_string_outline(arena._font,p,str(entry.text),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,4,Color(0.02,0.03,0.03,color.a))
			arena.draw_string(arena._font,p,str(entry.text),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

static func draw_arena(arena: Node2D) -> void:
	EnvironmentArt.draw(arena)

static func draw_player(arena: Node2D, preferences: Settings) -> void:
	ActorArt.draw_player(arena,preferences)

static func draw_enemy(arena: Node2D, enemy: Dictionary, preferences: Settings) -> void:
	ActorArt.draw_enemy(arena,enemy,preferences)

static func draw_projectile(arena: Node2D, shot: Dictionary, preferences: Settings) -> void:
	var p: Vector2 = shot.pos
	var velocity: Vector2 = shot.velocity
	var color: Color = Color("b3a0bd") if shot.state == "returning" else Palette.skill(str(shot.get("skill_id","basic")),Color(shot.color))
	if shot.state != "returning" and str(shot.get("role","")) == "child":
		color = Color("cdb58a")
	var dir: Vector2 = velocity.normalized()
	var side: Vector2 = dir.orthogonal()
	var role: String = str(shot.get("role",""))
	var tail: float = 30 if role == "parent" else 19
	if preferences.effects_level > 0:
		arena.draw_line(p-dir*tail,p,Color(color,0.07),6,true)
		arena.draw_line(p-dir*tail*0.8,p,Color(color,0.35),2.4,true)
	arena.draw_line(p-dir*tail*0.55,p,Color("3b4230"),3.5,true)
	arena.draw_line(p-dir*tail*0.55,p,Color("eee2bb"),1.4,true)
	var skill: String = str(shot.get("skill_id","basic"))
	if skill == "frost":
		polygon(arena,[p+dir*8,p+side*4,p-dir*7,p-side*4],color)
		arena.draw_line(p-dir*5,p+dir*6,Color("ecfbff"),1.5,true)
	elif skill == "bolt":
		arena.draw_circle(p,4,color)
		arena.draw_arc(p,7,float(shot.get("age",0))*10,float(shot.get("age",0))*10+PI*1.4,20,Color(color,0.8),1.5,true)
	else:
		polygon(arena,[p+dir*5,p-dir*5+side*3,p-dir*2,p-dir*5-side*3],color)
	if shot.state == "returning":
		arena.draw_polyline(PackedVector2Array([p-dir*9+side*4,p-dir*5,p-dir*9-side*4]),color,1.5,true)
	if role == "parent":
		arena.draw_arc(p,7,-0.5,PI+0.5,16,Color(color,0.9),1.5,true)
	arena.draw_circle(p,1.8,Color("f3fff0"))

static func draw_ring(arena: Node2D, ring: Dictionary, preferences: Settings) -> void:
	# Legacy non-damage notifications become short leaf/rune motes, never a neon reticle.
	var progress: float = 1-float(ring.life)/float(ring.max_life)
	var radius: float = lerpf(4,minf(42,float(ring.radius)),progress)
	var color: Color = Color(ring.color).lerp(Color("bcba91"),0.55)
	color.a = (1-progress)*0.6
	var p: Vector2 = ring.pos
	var count: int = 3 if preferences.effects_level==0 else 5
	for i: int in range(count):
		var v:=Vector2.RIGHT.rotated(i*TAU/count+0.35)
		var at:=p+v*radius+Vector2(0,-progress*6)
		arena.draw_line(at-v*3,at+v*3,color,1.4,true)
		if preferences.effects_level>0:
			arena.draw_line(at,at+v.rotated(0.7)*3,color,1,true)
