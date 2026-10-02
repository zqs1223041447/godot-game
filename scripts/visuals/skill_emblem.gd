class_name SkillEmblem
extends Control
## Original painted illustrations; stable IDs select art, never game rules.
var skill_id: String = "bolt"
var accent := Color("ba9148")
var subdued: bool = false
const ICONS: Dictionary = {
	"tornado":preload("res://assets/ui/grimoire/tornado.png"),
	"bolt":preload("res://assets/ui/grimoire/bolt.png"),
	"frost":preload("res://assets/ui/grimoire/frost.png"),
	"nova":preload("res://assets/ui/grimoire/nova.png"),
	"dash":preload("res://assets/ui/grimoire/dash.png"),
	"ward":preload("res://assets/ui/grimoire/ward.png"),
	"meteor":preload("res://assets/ui/grimoire/meteor.png"),
	"chain":preload("res://assets/ui/grimoire/chain.png"),
	"volley":preload("res://assets/ui/grimoire/volley.png"),
	"focus":preload("res://assets/ui/grimoire/focus.png"),
}
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
func _draw() -> void:
	var side: float=minf(size.x,size.y)
	var rect:=Rect2((size-Vector2.ONE*side)*0.5,Vector2.ONE*side)
	draw_rect(rect,Color("3b281b"))
	if ICONS.has(skill_id):
		draw_texture_rect(ICONS[skill_id],rect.grow(-2),false,Color(0.55,0.52,0.47) if subdued else Color.WHITE)
	else:
		# Missing art is visibly a vacant setting, never a different spell.
		draw_line(rect.position+rect.size*0.30,rect.end-rect.size*0.30,Color("ba9148"),2,true)
		draw_line(rect.position+Vector2(rect.size.x*0.7,rect.size.y*0.3),rect.position+Vector2(rect.size.x*0.3,rect.size.y*0.7),Color("ba9148"),2,true)
	draw_rect(rect.grow(-0.5),Color("ba9148").darkened(0.3 if subdued else 0),false,1.3)
	for point: Vector2 in [rect.position+Vector2(2,2),rect.end-Vector2(3,3)]:
		draw_circle(point,1.2,Color("e7c77f"))
