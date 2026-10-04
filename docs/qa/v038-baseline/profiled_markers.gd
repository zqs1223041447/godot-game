extends RefCounted
## Screen-sized readable cues, separated from the widened physical world.
const View=preload("res://scripts/visuals/world_view.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const MAX_FULL_NAMES: int=8

static func name_ids(arena: Node2D, enemies: Array, preferences: VisualSettings) -> Dictionary:
	var result: Dictionary={}
	var transform: Transform2D=arena.get_global_transform_with_canvas()
	var zoom: float=View.zoom_for(arena)
	var mouse_world: Vector2=arena.get_global_mouse_position()
	var pointer_inside: bool=View.SCREEN_PLAYFIELD.has_point(transform*mouse_world)
	var hover_id: int=-1
	var hover_distance: float=INF
	if pointer_inside:
		for enemy: Dictionary in enemies:
			if float(enemy.health)<=0: continue
			var distance: float=Vector2(enemy.pos).distance_squared_to(mouse_world)
			if distance<pow(float(enemy.radius)+7.0/zoom,2) and distance<hover_distance:
				hover_id=int(enemy.id)
				hover_distance=distance
	var examples: bool=arena.demo_mode and enemies.size()<=MAX_FULL_NAMES
	var candidates: Array[Dictionary]=[]
	for enemy: Dictionary in enemies:
		if float(enemy.health)<=0: continue
		var at: Vector2=transform*Vector2(enemy.pos)
		if not View.SCREEN_PLAYFIELD.grow(8).has_point(at): continue
		var rarity: String=str(enemy.get("rarity","normal"))
		var priority: int=100 if int(enemy.id)==hover_id else 80 if rarity=="boss" else 50 if rarity=="rare" else 10 if examples else 0
		if priority==0: continue
		candidates.append({"id":int(enemy.id),"enemy":enemy,"priority":priority,"distance":Vector2(enemy.pos).distance_squared_to(arena.player_pos)})
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if int(a.priority)!=int(b.priority): return int(a.priority)>int(b.priority)
		if not is_equal_approx(float(a.distance),float(b.distance)): return float(a.distance)<float(b.distance)
		return int(a.id)<int(b.id))
	var occupied:Array[Rect2]=[]
	for candidate:Dictionary in candidates:
		if result.size()>=MAX_FULL_NAMES: break
		var bounds:Rect2=name_rect(arena,candidate.enemy,preferences)
		var overlaps:bool=false
		for other:Rect2 in occupied:
			if other.grow(2).intersects(bounds):
				overlaps=true
				break
		if overlaps: continue
		result[candidate.id]=true
		occupied.append(bounds)
	return result

static func caption(enemy:Dictionary)->String:
	var rarity:String=str(enemy.get("rarity","normal"))
	var text:String=str(enemy.get("name","怪物"))+" · "+str(Monsters.RARITIES.get(rarity,Monsters.RARITIES.normal).name).split(" · ")[-1]
	var resistances: String = Monsters.resistance_text(enemy,true)
	if not resistances.is_empty(): text += " · " + resistances
	return text

static func name_origin(arena:Node2D,enemy:Dictionary,preferences:VisualSettings)->Vector2:
	var anchor:Vector2=View.world_to_screen(arena,enemy.pos)
	var font_size:int=roundi(12*preferences.font_scale)
	var width:float=_measured_string_size(arena._font, caption(enemy),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var radius:float=float(enemy.radius)*View.zoom_for(arena)
	var origin:=Vector2(-width*0.5,-ceilf(radius*1.4)-21)
	origin.x=clampf(anchor.x+origin.x,View.SCREEN_PLAYFIELD.position.x+3,View.SCREEN_PLAYFIELD.end.x-width-3)-anchor.x
	origin.y=maxf(View.SCREEN_PLAYFIELD.position.y+font_size+3,anchor.y+origin.y)-anchor.y
	return origin

static func name_rect(arena:Node2D,enemy:Dictionary,preferences:VisualSettings)->Rect2:
	var font_size:int=roundi(12*preferences.font_scale)
	var width:float=_measured_string_size(arena._font, caption(enemy),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var anchor:Vector2=View.world_to_screen(arena,enemy.pos)
	return Rect2(anchor+name_origin(arena,enemy,preferences)-Vector2(3,font_size+3),Vector2(width+6,font_size+7))

static func draw_enemy(arena: Node2D, enemy: Dictionary, preferences: VisualSettings, show_name: bool) -> void:
	var zoom: float=View.zoom_for(arena)
	var p: Vector2=enemy.pos
	var radius: float=float(enemy.radius)*zoom
	var rarity: String=str(enemy.get("rarity","normal"))
	var tier: Color=Monsters.RARITIES.get(rarity,Monsters.RARITIES.normal).color
	# Cancel only the camera scale for annotations. Actor geometry and physics stay world-sized.
	arena.draw_set_transform(p,0,Vector2.ONE/zoom)
	var badge:=Vector2(0,-radius*1.25-5)
	if rarity=="magic":
		arena.draw_colored_polygon(PackedVector2Array([badge+Vector2(0,-3),badge+Vector2(2.5,0),badge+Vector2(0,3),badge+Vector2(-2.5,0)]),tier)
	elif rarity in ["rare","boss"]:
		var crown:=PackedVector2Array([badge+Vector2(-5,-3),badge+Vector2(-2,0),badge+Vector2(0,-4),badge+Vector2(2,0),badge+Vector2(5,-3),badge+Vector2(3,3),badge+Vector2(-3,3)])
		arena.draw_colored_polygon(crown,tier)
		if rarity=="boss": arena.draw_line(badge+Vector2(0,-1),badge+Vector2(0,2),Color("4b3925"),1,true)
	if float(enemy.get("slow",0))>0:
		var center:=Vector2(-radius*1.35-5,0)
		arena.draw_circle(center,4.1,Color("353c36"))
		for i:int in range(6):
			var v:=Vector2.RIGHT.rotated(i*TAU/6)
			arena.draw_line(center,center+v*3.3,Color("d0ded8"),1,true)
	if float(enemy.get("resistances",{}).get("fire",0.0))>0.0:
		var center:=Vector2(radius*1.15+5,1)
		var ward:=PackedVector2Array([center+Vector2(-3.5,-4),center+Vector2(3.5,-4),center+Vector2(3,1),center+Vector2(0,4),center+Vector2(-3,1)])
		arena.draw_colored_polygon(ward,Color("494034"))
		ward.append(ward[0])
		arena.draw_polyline(ward,Color("c79d65"),1,true)
		arena.draw_colored_polygon(PackedVector2Array([center+Vector2(0,-2.5),center+Vector2(1.7,0),center+Vector2(1,1.8),center+Vector2(-1.5,1.5),center+Vector2(-1.8,-0.6)]),Color("d8ad74"))
	if not enemy.get("death_spawns",[]).is_empty():
		for i:int in range(3):
			var at:=Vector2((i-1)*4,radius+5)
			arena.draw_colored_polygon(PackedVector2Array([at+Vector2(0,-1.8),at+Vector2(1.2,0),at+Vector2(0,1.8),at+Vector2(-1.2,0)]),Color("c9b990"))
	var bar_width:float=maxf(16,radius*2)
	var header:float=ceilf(radius*1.4)+12
	var health_ratio:float=clampf(float(enemy.health)/maxf(1,float(enemy.max_health)),0,1)
	if health_ratio<1:
		var bar:=Rect2(Vector2(-bar_width*0.5,-header),Vector2(bar_width,3))
		arena.draw_rect(bar.grow(1),Color("302e24"))
		arena.draw_rect(bar,Color("5a5140"))
		arena.draw_rect(Rect2(bar.position,Vector2(bar_width*health_ratio,3)),Color("b3b783"))
	if float(enemy.get("max_shield",0))>0:
		var ratio:float=clampf(float(enemy.get("shield",0))/float(enemy.max_shield),0,1)
		var bar:=Rect2(Vector2(-bar_width*0.5,-header-4),Vector2(bar_width,2))
		arena.draw_rect(bar.grow(1),Color("302e24"))
		arena.draw_rect(bar,Color("57534c"))
		arena.draw_rect(Rect2(bar.position,Vector2(bar_width*ratio,2)),Color("b9b6cd"))
	if show_name and arena._font:
		var text:String=caption(enemy)
		var font_size:int=roundi(12*preferences.font_scale)
		var origin:Vector2=name_origin(arena,enemy,preferences)
		arena.draw_string_outline(arena._font,origin,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,3,Color("302d23"))
		arena.draw_string(arena._font,origin,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,tier)
	arena.draw_set_transform(Vector2.ZERO)

static var width_calls:=0
static var width_us:=0
static func _measured_string_size(font:Font,text:String,alignment:HorizontalAlignment=HORIZONTAL_ALIGNMENT_LEFT,width:float=-1,font_size:int=16)->Vector2:
	var t:=Time.get_ticks_usec();var v:=font.get_string_size(text,alignment,width,font_size);width_us+=Time.get_ticks_usec()-t;width_calls+=1;return v
