extends SceneTree
const Renderer=preload("res://scripts/visuals/telegraph_renderer.gd")
const Settings=preload("res://scripts/visuals/visual_settings.gd")
class Canvas extends Node2D:
	func _draw()->void:
		draw_rect(Rect2(0,0,900,540),Color("b5a487"))
		var font=ThemeDB.fallback_font
		for row:int in range(2):
			var settings=Settings.new()
			settings.effects_level=2 if row==0 else 0
			for col:int in range(2):
				var center=Vector2(230+col*440,155+row*250)
				var state={"source_id":1+row*2+col,"center":center,"phase":"windup","elapsed":0.65,"visual_pattern":"garden_slam" if col==0 else "ruins_mark","profile":{"radius":100.0 if col==0 else 75.0,"windup_seconds":0.9 if col==0 else 1.0,"recovery_seconds":1.7 if col==0 else 1.5}}
				Renderer.draw(self,[state],settings)
				draw_circle(center,12,Color("574c3f"))
				draw_string(font,center+Vector2(-80,-115),("Garden slam" if col==0 else "Ruins mark")+ (" / full" if row==0 else " / low"),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("35281f"))
func _initialize()->void:
	root.size=Vector2i(900,540)
	root.title="Map boss visual review"
	root.add_child(Canvas.new())
