extends SceneTree
## Static direction/scale study, not a gameplay or animation acceptance scene.
class ArtStudy extends Node2D:
	var floor_texture: Texture2D
	var hero_texture: Texture2D
	var font_resource: Font
	func _ready() -> void:
		floor_texture = load("res://assets/environment-final.png")
		hero_texture = load("res://assets/hero_direction_study.png")
		font_resource = load("res://assets/arena_sans.otf")
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		queue_redraw()
	func _draw() -> void:
		if floor_texture == null or hero_texture == null: return
		draw_texture_rect(floor_texture,Rect2(0,0,1280,720),false)
		var foot := Vector2(640,427.768)
		var scale_value := 0.115
		var frame_size := Vector2(384,512)
		var anchor := Vector2(192,448)
		draw_set_transform(foot,0.0,Vector2(1.0,0.3))
		draw_circle(Vector2.ZERO,10.0,Color(0.09,0.12,0.09,0.22))
		draw_set_transform(Vector2.ZERO)
		draw_texture_rect_region(hero_texture,Rect2(foot-anchor*scale_value,frame_size*scale_value),Rect2(384,0,384,512))
		draw_rect(Rect2(16,675,520,29),Color(0.10,0.13,0.11,0.8))
		draw_string(font_resource,Vector2(28,695),"美术方向样板 · 静态人物 · 动作尚未接入",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("e8e2cf"))
func _initialize() -> void:
	root.title = "Static art direction study"
	root.add_child.call_deferred(ArtStudy.new())
