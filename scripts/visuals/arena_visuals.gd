class_name ArenaVisuals
extends RefCounted
## Original scalable vector artwork. This layer only reads the simulation.
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
const CueRenderer = preload("res://scripts/visuals/combat_cue_renderer.gd")

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
	var bounds: Rect2 = arena.ARENA
	arena.draw_rect(Rect2(0,0,1280,720),Color("0b1315"))
	# Recessed masonry foundation with a restrained brass inlay.
	arena.draw_rect(bounds.grow(13),Color("101d20"))
	arena.draw_rect(bounds.grow(10),Color("3d514c"),false,2)
	arena.draw_rect(bounds.grow(6),Color("253732"),false,3)
	arena.draw_rect(bounds,Color("1b292a"))
	for y: int in range(0,10):
		for x: int in range(0,25):
			var rect := Rect2(bounds.position+Vector2(x*48+(24 if y%2 else 0),y*48),Vector2(47,47)).intersection(bounds)
			if rect.size.x <= 0 or rect.size.y <= 0:
				continue
			var shade: float = float((x*19+y*7)%5)*0.003
			arena.draw_rect(rect,Color(0.101+shade,0.148+shade,0.15+shade))
			arena.draw_line(rect.position+Vector2(2,2),rect.position+Vector2(rect.size.x-2,2),Color(0.24,0.31,0.28,0.16),1)
	var c: Vector2 = bounds.get_center()
	for r: float in [72.0,126.0,134.0,201.0]:
		arena.draw_arc(c,r,0,TAU,100,Color("314541"),1,true)
	for i: int in range(16):
		var v := Vector2.RIGHT.rotated(i*TAU/16)
		arena.draw_line(c+v*130,c+v*(143 if i%2 else 150),Color("657161"),1.5,true)
		if i%2 == 0:
			regular(arena,c+v*190,4,4,Color("43584e"),PI/4)
	regular(arena,c,61,4,Color("233a38"),PI/4)
	regular(arena,c,47,4,Color("1b2d2e"),PI/4)
	arena.draw_arc(c,20,0,TAU,32,Color("516357"),1,true)
	for side: int in [-1,1]:
		for offset: float in [-25.0,25.0]:
			arena.draw_line(c+Vector2(side*80,offset),c+Vector2(side*107,offset),Color("4a5d53"),1,true)
	arena.draw_rect(bounds.grow(-9),Color("4d6055"),false,1)
	for p: Vector2 in [bounds.position+Vector2(14,14),Vector2(bounds.end.x-14,bounds.position.y+14),bounds.end-Vector2(14,14),Vector2(bounds.position.x+14,bounds.end.y-14)]:
		shadow(arena,p+Vector2(0,5),18)
		regular(arena,p,14,4,Color("566354"),PI/4)
		regular(arena,p,10,4,Color("9e8c61"),PI/4)
		regular(arena,p,6,4,Color("243f3b"),PI/4)
		arena.draw_circle(p,2.5,Color("b8e1c0"))
	if arena._font:
		arena.draw_string(arena._font,Vector2(78,139),"灰烬庭院   /   裂隙 01",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("869484"))
		arena.draw_string(arena._font,Vector2(1058,540),"试炼之环",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("627d70"))

static func draw_player(arena: Node2D, preferences: Settings) -> void:
	var p: Vector2 = arena.player_pos
	var phase: float = arena.elapsed if preferences.motion else 0.0
	var stride: float = sin(phase*8)*1.4 if preferences.motion else 0.0
	shadow(arena,p+Vector2(0,16),22)
	var ratio: float = arena.shield/maxf(1,float(arena._stats.get("max_shield",1)))
	if ratio > 0:
		arena.draw_arc(p,25,-PI/2,-PI/2+TAU*ratio,64,Color("83ccc8"),1.5,true)
		for i: int in range(4):
			var dir := Vector2.RIGHT.rotated(PI/4+i*PI/2)
			arena.draw_line(p+dir*24,p+dir*28,Color("badfd3"),1,true)
	if arena.invulnerable > 0:
		arena.draw_arc(p,29,phase*2,phase*2+PI*1.5,48,Color("e4deb5"),1.5,true)
	# Split cloak, armored boots, shoulder plates, hood and a faceted focus.
	polygon(arena,[p+Vector2(-10,-5),p+Vector2(-19,16+stride),p+Vector2(-3,12),p+Vector2(0,17),p+Vector2(18,17-stride),p+Vector2(10,-5)],Color("0e191c"))
	polygon(arena,[p+Vector2(-9,-4),p+Vector2(-16,14+stride),p+Vector2(-3,10),p+Vector2(-1,-4)],Color("376d69"))
	polygon(arena,[p+Vector2(1,-4),p+Vector2(3,10),p+Vector2(15,14-stride),p+Vector2(9,-4)],Color("274d50"))
	arena.draw_line(p+Vector2(-13,10+stride),p+Vector2(-5,8),Color("b89b63"),1.5,true)
	arena.draw_line(p+Vector2(5,8),p+Vector2(12,11-stride),Color("b89b63"),1.5,true)
	for side: int in [-1,1]:
		arena.draw_line(p+Vector2(side*6,8),p+Vector2(side*7,17+stride*side),Color("293333"),5,true)
		arena.draw_line(p+Vector2(side*7,15+stride*side),p+Vector2(side*9,17+stride*side),Color("b5b6a3"),3,true)
	polygon(arena,[p+Vector2(-10,-4),p+Vector2(0,-11),p+Vector2(10,-4),p+Vector2(7,9),p+Vector2(-7,9)],Color("bbc2ab") if arena.hurt_flash>0 else Color("567e78"))
	arena.draw_line(p+Vector2(-6,0),p+Vector2(6,0),Color("d4bb78"),2,true)
	arena.draw_line(p+Vector2(0,-7),p+Vector2(0,7),Color("a2b7a4"),1.5,true)
	for side: int in [-1,1]:
		regular(arena,p+Vector2(side*11,-3),6,5,Color("c0b48e"),-PI/2)
	polygon(arena,[p+Vector2(-8,-9),p+Vector2(-6,-19),p+Vector2(0,-24),p+Vector2(7,-18),p+Vector2(8,-9)],Color("54726e"))
	polygon(arena,[p+Vector2(-5,-15),p+Vector2(0,-19),p+Vector2(5,-15),p+Vector2(4,-9),p+Vector2(-4,-9)],Color("101e23"))
	arena.draw_line(p+Vector2(-3,-13),p+Vector2(3,-13),Color("b4e8d6"),1.5,true)
	var dir: Vector2 = arena.player_facing
	var focus: Vector2 = p+dir*24
	var weapon_id: String = str(arena.state.equipped.get("weapon",""))
	var weapon: Dictionary = arena.state.get_item_definition(weapon_id)
	var side: Vector2 = dir.orthogonal()
	if weapon_id == "prism_bow":
		var points := PackedVector2Array()
		for i: int in range(17):
			var a: float = lerpf(-PI/2,PI/2,i/16.0)
			points.append(focus+dir*cos(a)*8+side*sin(a)*15)
		arena.draw_polyline(points,Color("c8b887"),3,true)
		arena.draw_line(points[0],points[-1],Color("cce4d7"),1,true)
		arena.draw_line(focus-dir*8,focus+dir*10,Color("d8e6cf"),1.5,true)
	elif weapon_id in ["swift_blade","heavy_blade"] or str(weapon.get("base_name","")).ends_with("刃"):
		polygon(arena,[focus+dir*16,focus-dir*4+side*4,focus-dir*7,focus-dir*4-side*4],Color("b7d1cf"))
		arena.draw_line(focus-dir*5-side*7,focus-dir*5+side*7,Color("d4b875"),3,true)
		arena.draw_line(focus-dir*5,focus-dir*12,Color("99744e"),4,true)
	else:
		arena.draw_line(p+dir*10,focus+dir*8,Color("1b2827"),6,true)
		arena.draw_line(p+dir*10,focus+dir*8,Color("b99b6a"),3,true)
		regular(arena,focus,8,4,Color("d9c290"),dir.angle())
		regular(arena,focus,5,4,Color("9ce4cc"),dir.angle())
		arena.draw_circle(focus,1.8,Color("f2ffee"))
	if not arena.alive:
		arena.draw_arc(p,24,0,TAU,32,Color("bd6666"),3,true)

static func draw_enemy(arena: Node2D, enemy: Dictionary, preferences: Settings) -> void:
	var p: Vector2 = enemy.pos
	var r: float = enemy.radius
	var rarity: String = enemy.get("rarity","normal")
	var tier: Color = Monsters.RARITIES[rarity].color
	var body: Color = Color("86928d") if rarity == "normal" else tier.darkened(0.15)
	if float(enemy.slow)>0:
		body = Color("89bbce")
	if float(enemy.flash)>0:
		body = Color("ebe9cc")
	var direction: float = (arena.player_pos-p).angle()
	var phase: float = arena.elapsed*7+float(enemy.get("id",0)) if preferences.motion else 0.0
	shadow(arena,p+Vector2(0,r*0.7),r+5)
	arena.draw_set_transform(p,direction)
	var gait: float = sin(phase)*1.7
	match int(enemy.kind):
		0:
			# Six-legged plated scavenger with curved mandibles.
			for i: int in range(3):
				for side: int in [-1,1]:
					var root := Vector2((i-1)*r*0.62,side*r*0.42)
					var joint := root+Vector2(-4+gait*(i-1),side*r*0.55)
					arena.draw_polyline(PackedVector2Array([root,joint,joint+Vector2(-5,side*2)]),Color("344e4e"),3,true)
			regular(arena,Vector2(-3,0),r*0.9,6,Color("293d40"))
			polygon(arena,[Vector2(-r,0),Vector2(-r*0.45,-r*0.7),Vector2(r*0.55,-r*0.55),Vector2(r*0.8,0),Vector2(r*0.55,r*0.55),Vector2(-r*0.45,r*0.7)],body)
			arena.draw_line(Vector2(-r*0.7,0),Vector2(r*0.5,0),body.darkened(0.4),2,true)
			for side: int in [-1,1]:
				arena.draw_polyline(PackedVector2Array([Vector2(r*0.5,side*4),Vector2(r+4,side*6),Vector2(r+2,side*1)]),Color("b3ac88"),2,true)
		1:
			# Lean wing-blade silhouette and twin tail vanes.
			polygon(arena,[Vector2(-r-7,-r),Vector2(2,-r*0.5),Vector2(r+6,0),Vector2(2,r*0.5),Vector2(-r-7,r),Vector2(-r*0.45,0)],body.darkened(0.32))
			polygon(arena,[Vector2(-r*0.7,-r*0.35),Vector2(r+2,0),Vector2(-r*0.7,r*0.35),Vector2(-r*0.3,0)],body)
			for side: int in [-1,1]:
				arena.draw_line(Vector2(-r-4,side*r),Vector2(0,side*r*0.47),tier,1.5,true)
		2:
			# Heavy armored beetle, four squared legs and a crown-ridge shell.
			for side: int in [-1,1]:
				for front: int in [-1,1]:
					var at := Vector2(front*r*0.5,side*r*0.62)
					polygon(arena,[at,at+Vector2(front*5,side*9+gait),at+Vector2(front*11,side*9+gait),at+Vector2(front*5,side*1)],Color("526365"))
			regular(arena,Vector2.ZERO,r,8,Color("293b3d"),PI/8)
			regular(arena,Vector2(-2,0),r*0.86,6,body.darkened(0.25))
			polygon(arena,[Vector2(-r*0.8,0),Vector2(-r*0.25,-r*0.7),Vector2(r*0.5,-r*0.55),Vector2(r*0.76,0),Vector2(r*0.5,r*0.55),Vector2(-r*0.25,r*0.7)],body)
			arena.draw_line(Vector2(-r*0.6,0),Vector2(r*0.48,0),Color("e3cf94"),2,true)
			for side: int in [-1,1]:
				polygon(arena,[Vector2(r*0.35,side*r*0.56),Vector2(r+7,side*r*0.65),Vector2(r*0.85,side*r*0.2)],body.lightened(0.1))
	for side: int in [-1,1]:
		arena.draw_circle(Vector2(r*0.5,side*3),2 if int(enemy.kind)!=2 else 2.8,Color("ffd5a0"))
	arena.draw_set_transform(Vector2.ZERO)
	if float(enemy.spawn)>0:
		arena.draw_arc(p,r+8,0,TAU,32,Color(tier,clampf(float(enemy.spawn),0,1)),1.5,true)
	# A unique glyph and explicit text supplement color at every special tier.
	if rarity != "normal":
		arena.draw_arc(p,r+5,0.25,PI-0.25,24,Color(tier,0.75),1.5,true)
		arena.draw_arc(p,r+5,PI+0.25,TAU-0.25,24,Color(tier,0.75),1.5,true)
		var badge := p+Vector2(0,-r-12)
		if rarity == "magic":
			regular(arena,badge,4,4,tier)
		elif rarity == "rare":
			polygon(arena,[badge+Vector2(-7,-3),badge+Vector2(-3,0),badge+Vector2(0,-6),badge+Vector2(3,0),badge+Vector2(7,-3),badge+Vector2(5,4),badge+Vector2(-5,4)],tier)
		elif rarity == "boss":
			regular(arena,badge,8,3,tier,-PI/2)
			regular(arena,badge,3,3,Color("171b1c"),-PI/2)
	if float(enemy.slow)>0:
		# Slow is an explicit six-arm glyph rather than a rarity-color replacement alone.
		var status := p+Vector2(-r-7,0)
		arena.draw_circle(status,6,Color("0e222b"))
		for i: int in range(6):
			var v := Vector2.RIGHT.rotated(i*TAU/6)
			arena.draw_line(status,status+v*4.5,Color("a9e0ec"),1.2,true)
	if not enemy.get("death_spawns",[]).is_empty():
		for i: int in range(3):
			regular(arena,p+Vector2((i-1)*6,r+9),2.5,4,tier,PI/4)
	if float(enemy.health)<float(enemy.max_health):
		var bar := Rect2(p+Vector2(-r,-r-22),Vector2(r*2,4))
		arena.draw_rect(bar.grow(1),Color("091516"))
		arena.draw_rect(Rect2(bar.position,Vector2(bar.size.x*maxf(0,float(enemy.health)/float(enemy.max_health)),4)),tier)
	if float(enemy.get("max_shield",0))>0:
		arena.draw_arc(p,r+9,-PI/2,-PI/2+TAU*float(enemy.get("shield",0))/float(enemy.max_shield),32,Color("aaa3de"),1.5,true)
	if (rarity != "normal" or arena.demo_mode) and arena._font:
		var label: String = str(enemy.get("name","怪物"))+" · "+str(Monsters.RARITIES[rarity].name).split(" · ")[1]
		var width: float = arena._font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
		var baseline := p+Vector2(-width*0.5,-r-28)
		baseline.x = clampf(baseline.x,arena.ARENA.position.x+3,arena.ARENA.end.x-width-3)
		baseline.y = maxf(arena.ARENA.position.y+15,baseline.y)
		arena.draw_string_outline(arena._font,baseline,label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,4,Color("0c1718"))
		arena.draw_string(arena._font,baseline,label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,tier)

static func draw_projectile(arena: Node2D, shot: Dictionary, preferences: Settings) -> void:
	var p: Vector2 = shot.pos
	var velocity: Vector2 = shot.velocity
	var color: Color = Color("c5a1ec") if shot.state == "returning" else Color(shot.color)
	var dir: Vector2 = velocity.normalized()
	var side: Vector2 = dir.orthogonal()
	var role: String = str(shot.get("role",""))
	var tail: float = 30 if role == "parent" else 19
	if preferences.effects_level > 0:
		arena.draw_line(p-dir*tail,p,Color(color,0.14),9,true)
		arena.draw_line(p-dir*tail*0.8,p,Color(color,0.45),3,true)
	arena.draw_line(p-dir*tail*0.55,p,Color("d6ede0"),1.5,true)
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
	var progress: float = 1-float(ring.life)/float(ring.max_life)
	var radius: float = lerpf(8,float(ring.radius),progress)
	var color: Color = ring.color
	var p: Vector2 = ring.pos
	color.a = (1-progress)*0.8
	# Boundary survives reduced-effects mode; decorative bloom is optional.
	arena.draw_arc(p,radius,0,TAU,64,color,2,true)
	if preferences.effects_level == 0:
		return
	arena.draw_arc(p,maxf(1,radius-5),0,TAU,64,Color(color,color.a*0.3),5,true)
	if preferences.effects_level == 2:
		arena.draw_circle(p,radius,Color(color,color.a*0.035))
		for i: int in range(8):
			var dir := Vector2.RIGHT.rotated(i*TAU/8+progress*0.25)
			arena.draw_line(p+dir*radius*0.86,p+dir*(radius+5),Color(color,color.a*0.7),1.5,true)
