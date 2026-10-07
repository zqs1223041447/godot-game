class_name RetainedActorLayer
extends Node2D
## One ordered shadow/animated-limb/static-body triplet per live runtime identity.
## This owns drawing commands only. No simulation, RNG, or item state writes.
const Art=preload("res://scripts/visuals/fantasy_actors.gd")
const Visuals=preload("res://scripts/visuals/arena_visuals.gd")

class Piece extends Node2D:
	var enemy:Dictionary={}
	var part:StringName=&"shadow"
	var preferences:VisualSettings
	var elapsed:=0.0
	var _body_key:Array=[]
	var redraw_requests:=0
	var draw_count:=0
	var measured_frame:=-1
	var measured_usec:=0
	func configure(value:Dictionary,settings:VisualSettings,time:float,player:Vector2)->void:
		enemy=value;preferences=settings;elapsed=time
		if part!=&"shadow":transform=Transform2D((player-Vector2(enemy.pos)).angle(),enemy.pos)
		var dirty:=part!=&"body"
		if not dirty:
			var key:Array=[int(enemy.kind),str(enemy.get("template_id","")),float(enemy.radius),str(enemy.get("rarity","normal"))=="boss",float(enemy.get("flash",0.0))>0.0]
			if key!=_body_key:_body_key=key;dirty=true
		if dirty:redraw_requests+=1;queue_redraw()
	func _draw()->void:
		var began:int=Time.get_ticks_usec() if Visuals.diagnostic_profile_enabled else 0
		draw_count+=1
		var r:float=float(enemy.radius)
		match part:
			&"shadow":Art._shadow(self,Vector2(enemy.pos)+Vector2(0,r*0.56),Vector2(r+4.0,r*0.36+3.0))
			&"limbs":Art.draw_enemy_limbs(self,enemy,preferences,elapsed)
			&"body":Art.draw_enemy_body(self,enemy)
		if Visuals.diagnostic_profile_enabled:measured_frame=Engine.get_process_frames();measured_usec=Time.get_ticks_usec()-began

var _pieces:Dictionary={}
var synchronization_count:=0
var measured_sync_usec:=0

static func _body_extent(radius:float,aa_margin:float)->float:
	# Current Art local geometry fits |x|,|y| <= 1.5*r+8: wings reach
	# 1.5*r+0.9, gait is bounded by 1.2 and toes add at most 4 units.
	# sqrt(2) covers arbitrary facing; 3 covers the widest 6-unit stroke.
	# Shadow offset/ellipse, horns and elemental/mist crests fit this bound.
	return sqrt(2.0)*(1.5*maxf(radius,0.0)+8.0)+3.0+aa_margin

static func _visibility_frame(arena:Node2D)->Dictionary:
	var viewport_rect:Rect2=arena.get_viewport_rect()
	var canvas:Transform2D=arena.get_global_transform_with_canvas()
	if not viewport_rect.position.is_finite() or not viewport_rect.size.is_finite() or viewport_rect.size.x<=0.0 or viewport_rect.size.y<=0.0:
		return {"ok":false}
	if not canvas.x.is_finite() or not canvas.y.is_finite() or not canvas.origin.is_finite() or is_zero_approx(canvas.determinant()):
		return {"ok":false}
	var inverse:Transform2D=canvas.affine_inverse()
	var first:Vector2=inverse*viewport_rect.position
	var rect:=Rect2(first,Vector2.ZERO)
	for corner:Vector2 in [Vector2(viewport_rect.end.x,viewport_rect.position.y),viewport_rect.end,Vector2(viewport_rect.position.x,viewport_rect.end.y)]:
		rect=rect.expand(inverse*corner)
	# Conservatively include two screen pixels on each axis for antialiasing.
	return {"ok":true,"rect":rect,"aa_margin":2.0*(inverse.x.length()+inverse.y.length())}

static func _actor_visible(enemy:Dictionary,frame:Dictionary)->bool:
	if not bool(frame.ok):return true
	var radius:float=float(enemy.radius)
	var position:Vector2=enemy.pos
	if not is_finite(radius) or not position.is_finite():return true
	var padded:Rect2=Rect2(frame.rect).grow(_body_extent(radius,float(frame.aa_margin)))
	return position.x>=padded.position.x and position.x<=padded.end.x and position.y>=padded.position.y and position.y<=padded.end.y

func sync(arena:Node2D)->void:
	var began:int=Time.get_ticks_usec() if Visuals.diagnostic_profile_enabled else 0
	var frame:Dictionary=_visibility_frame(arena)
	var ordered:Array=arena.enemies.duplicate()
	ordered.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.pos.y<b.pos.y)
	var retained_ids:Dictionary={};var order:=0
	for enemy:Dictionary in ordered:
		var id:int=int(enemy.id);retained_ids[id]=true
		if not _pieces.has(id):
			var group:Array[Piece]=[]
			for part:StringName in [&"shadow",&"limbs",&"body"]:
				var piece:=Piece.new();piece.part=part;add_child(piece);group.append(piece)
			_pieces[id]=group
		var on_screen:bool=_actor_visible(enemy,frame)
		for piece:Piece in _pieces[id]:
			if piece.get_index()!=order:move_child(piece,order)
			order+=1
			piece.visible=on_screen
			if on_screen:piece.configure(enemy,arena.visual_settings,float(arena.elapsed),arena.player_pos)
	for id:int in _pieces.keys():
		if not retained_ids.has(id):
			for piece:Piece in _pieces[id]:remove_child(piece);piece.queue_free()
			_pieces.erase(id)
	synchronization_count+=1
	if Visuals.diagnostic_profile_enabled:measured_sync_usec=Time.get_ticks_usec()-began

func clear()->void:
	for group:Array in _pieces.values():
		for piece:Piece in group:remove_child(piece);piece.queue_free()
	_pieces.clear()

func diagnostics()->Dictionary:
	var bodies:=0;var draws:=0;var requested:=0;var usec:=0;var frame:int=Engine.get_process_frames()
	for group:Array in _pieces.values():
		for piece:Piece in group:
			if piece.part==&"body":bodies+=1;draws+=piece.draw_count;requested+=piece.redraw_requests
			if piece.measured_frame==frame:usec+=piece.measured_usec
	return {"actors":_pieces.size(),"pieces":get_child_count(),"body_count":bodies,"body_draws":draws,"body_rebuild_requests":requested,"current_draw_usec":usec,"sync_usec":measured_sync_usec}
