class_name MaterialFrame
extends StyleBox
## Original painted paper/leather, nine-sliced with small fixed screen borders.
## Saved properties and margins survive duplicate() for hotbar state overrides.
@export_storage var bg_color: Color = Color("f1deb3")
@export_storage var border_color: Color = Color("8c6b42")
@export_storage var border_width: float = 1.0
@export_storage var corner_cut: float = 4.0
@export_storage var grain: bool = true
@export_storage var book_cover: bool = false
const PAPER: Texture2D = preload("res://assets/ui/grimoire/parchment.png")
const LEATHER: Texture2D = preload("res://assets/ui/grimoire/leather.png")

func _get_minimum_size() -> Vector2:
	return Vector2.ONE*border_width*2

func _shape(rect: Rect2, cut: float) -> PackedVector2Array:
	var a: Vector2=rect.position
	var b: Vector2=rect.end
	var c: float=minf(cut,minf(rect.size.x,rect.size.y)*0.25)
	return PackedVector2Array([a+Vector2(c,0),Vector2(b.x-c,a.y),Vector2(b.x,a.y+c),b-Vector2(0,c),b-Vector2(c,0),Vector2(a.x+c,b.y),Vector2(a.x,b.y-c),a+Vector2(0,c)])

func _draw(canvas: RID, rect: Rect2) -> void:
	if rect.size.x<=0 or rect.size.y<=0:
		return
	if bg_color.a<=0.001:
		var outline: PackedVector2Array=_shape(rect.grow(-1),corner_cut)
		outline.append(outline[0])
		RenderingServer.canvas_item_add_polyline(canvas,outline,PackedColorArray([border_color]),border_width,true)
		return
	var face: Rect2=rect
	if book_cover and minf(rect.size.x,rect.size.y)>40:
		_paint(canvas,rect,LEATHER,Color.WHITE)
		face=rect.grow(-7)
	var paper: bool=bg_color.get_luminance()>0.45
	var texture: Texture2D=PAPER if paper else LEATHER
	var tint: Color=Color.WHITE
	if not paper:
		if bg_color.r>bg_color.g*1.65: tint=Color(1.18,0.64,0.60,bg_color.a)
		else: tint=Color(0.92,0.89,0.82,bg_color.a)
	else:
		tint=Color(clampf(bg_color.r/0.95,0.86,1.06),clampf(bg_color.g/0.88,0.84,1.06),clampf(bg_color.b/0.72,0.82,1.06),bg_color.a)
	_paint(canvas,face,texture,tint)
	if border_width>1.0:
		var outline: PackedVector2Array=_shape(rect.grow(-2),corner_cut)
		outline.append(outline[0])
		RenderingServer.canvas_item_add_polyline(canvas,outline,PackedColorArray([border_color]),border_width,true)

func _paint(canvas: RID, rect: Rect2, texture: Texture2D, tint: Color) -> void:
	var target_edge: float=minf(18.0,minf(rect.size.x,rect.size.y)*0.22)
	var source_edge: float=texture.get_width()*0.16
	var source_size: Vector2=texture.get_size()
	var xs: Array[float]=[0.0,target_edge,rect.size.x-target_edge,rect.size.x]
	var ys: Array[float]=[0.0,target_edge,rect.size.y-target_edge,rect.size.y]
	var us: Array[float]=[0.0,source_edge,source_size.x-source_edge,source_size.x]
	var vs: Array[float]=[0.0,source_edge,source_size.y-source_edge,source_size.y]
	for y: int in range(3):
		for x: int in range(3):
			var to: Rect2=Rect2(rect.position+Vector2(xs[x],ys[y]),Vector2(xs[x+1]-xs[x],ys[y+1]-ys[y]))
			var source: Rect2=Rect2(Vector2(us[x],vs[y]),Vector2(us[x+1]-us[x],vs[y+1]-vs[y]))
			RenderingServer.canvas_item_add_texture_rect_region(canvas,to,texture.get_rid(),source,tint,false,true)
