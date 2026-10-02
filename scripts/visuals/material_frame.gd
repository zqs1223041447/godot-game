class_name MaterialFrame
extends StyleBox
## Handworked leather/wood panel with an aged metal edge. Geometry preserves layout.
@export_storage var bg_color: Color = Color("302c24")
@export_storage var border_color: Color = Color("897958")
@export_storage var border_width: float = 1.0
@export_storage var corner_cut: float = 4.0
@export_storage var grain: bool = true

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
	var border: float=minf(border_width,minf(rect.size.x,rect.size.y)*0.2)
	RenderingServer.canvas_item_add_polygon(canvas,_shape(rect,corner_cut),PackedColorArray([border_color.darkened(0.32)]))
	var face: Rect2=rect.grow(-border)
	RenderingServer.canvas_item_add_polygon(canvas,_shape(face,maxf(0,corner_cut-border)),PackedColorArray([bg_color]))
	if rect.size.x<12 or rect.size.y<12:
		return
	# Fine hand-cut grain is bounded independent of panel size.
	if grain and face.size.y>22 and face.size.x>35 and bg_color.a>0.1:
		for i: int in range(7):
			var y: float=face.position.y+face.size.y*(i+1)/8.0
			var left: float=face.position.x+5+float((i*17)%29)*0.2
			var right: float=face.end.x-6-float((i*11)%23)*0.3
			RenderingServer.canvas_item_add_line(canvas,Vector2(left,y),Vector2(right,y+sin(i*2.3)*1.0),Color(0.77,0.68,0.45,0.022),0.6,true)
	var warm: Color=border_color.lightened(0.1)
	warm.a=border_color.a*0.70
	var shadow: Color=Color(0.055,0.043,0.027,border_color.a*0.7)
	RenderingServer.canvas_item_add_line(canvas,rect.position+Vector2(corner_cut+2,2),Vector2(rect.end.x-corner_cut-2,rect.position.y+2),warm,1,true)
	RenderingServer.canvas_item_add_line(canvas,Vector2(rect.position.x+corner_cut+2,rect.end.y-2),rect.end-Vector2(corner_cut+2,2),shadow,1.5,true)
	if rect.size.x>90 and rect.size.y>34 and bg_color.a>0.1:
		for point: Vector2 in [rect.position+Vector2(5,5),Vector2(rect.end.x-5,rect.position.y+5),rect.end-Vector2(5,5),Vector2(rect.position.x+5,rect.end.y-5)]:
			RenderingServer.canvas_item_add_circle(canvas,point,1.3,Color(border_color,border_color.a*0.8),true)
			RenderingServer.canvas_item_add_circle(canvas,point+Vector2(-0.3,-0.3),0.45,Color("c6af7b"),true)
