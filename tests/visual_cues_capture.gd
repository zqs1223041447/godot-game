extends SceneTree
## Development-only native renderer QA for every bounded cue in high and low modes.
const Runtime = preload("res://scripts/visuals/combat_cues.gd")
const Renderer = preload("res://scripts/visuals/combat_cue_renderer.gd")
class Sheet extends Node2D:
	var pool = Runtime.new()
	var effects: int = 2
	var font: Font = load("res://assets/fonts/arena_sans.otf")
	var labels: Array[String] = ["龙卷施放","飞弹施放","冰霜施放","新星边界","护盾充能","陨星命中","闪电连锁","冲刺路径","生命 / 护盾命中","角色受击","分裂 / 返回","死亡消散"]
	func _draw() -> void:
		draw_rect(Rect2(0,0,1280,720),Color("0c181b"))
		draw_string(font,Vector2(28,44),"战斗特效验收  /  %s"%("低特效" if effects==0 else "完整特效"),HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color("e9e4d4"))
		draw_string(font,Vector2(28,76),"每种技能保留独立形状、目标连线与范围边界",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("abc3b9"))
		for i: int in range(12):
			var origin := Vector2(20+(i%4)*315,98+(i/4)*201)
			draw_rect(Rect2(origin,Vector2(300,185)),Color("162a2b"))
			draw_rect(Rect2(origin,Vector2(300,185)),Color("39534b"),false,1)
			draw_string(font,origin+Vector2(12,27),labels[i],HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("d7bb7d"))
			var center := origin+Vector2(135,109)
			draw_circle(center,10,Color("749c90"))
		Renderer.render(self,pool.cues,effects,true)
		Renderer.render(self,pool.cues,effects,false)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var destination: String = OS.get_environment("GODOT_VISUAL_QA_DIR")
	if destination.is_empty():
		destination="user://visual-qa"
	DirAccess.make_dir_recursive_absolute(destination)
	root.size=Vector2i(2560,1440)
	root.position=Vector2i.ZERO
	var sheet := Sheet.new()
	root.add_child(sheet)
	var kinds: Array[String] = ["cast","cast","cast","nova","ward","meteor","chain","dash","impact","hurt","split","death"]
	for i: int in range(12):
		var point := Vector2(155+(i%4)*315,207+(i/4)*201)
		var color: Color = Color("bc98ed") if i==3 else Color("e7aa6d") if i==5 else Color("95dce9")
		var data := {"radius":56.0,"color":color,"direction":Vector2.RIGHT,"skill":["tornado","bolt","frost"][i] if i<3 else ""}
		if i in [6,7]:
			point-=Vector2(67,0)
			data.destination=point+Vector2(138,0)
		if i==8:
			data.radius=14.0
			sheet.pool.emit_cue("impact",point+Vector2(65,0),{"radius":14.0,"shielded":true})
		if i==10:
			point-=Vector2(35,0)
			data.radius=25.0
			sheet.pool.emit_cue("return",point+Vector2(90,0),{"radius":22.0,"color":Color("c6a3e9")})
		sheet.pool.emit_cue(kinds[i],point,data)
	sheet.pool.advance(0.1)
	for level: int in [2,0]:
		sheet.effects=level
		sheet.queue_redraw()
		for i: int in range(16):
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image=root.get_texture().get_image()
		var path: String=destination.path_join("v06-cue-sheet-%s.png"%("high" if level==2 else "low"))
		image.save_png(path)
		print("CUE_CAPTURE ",path," ",image.get_size())
	print("CUE_SHEET_DONE")
	quit()
