extends SceneTree
## Native 720p mouse/key stage, then explicitly programmatic 720p/2K captures.
## Dedicated QA userdata, frozen simulation, catalog target bodies/defenses unchanged.
const Model=preload("res://scripts/build_state.gd")
var arena: Node
var output: String
var stage: int=0
var busy: bool=false
var records: Array[Dictionary]=[]
class CueSurface extends Node2D:
	const Renderer=preload("res://scripts/visuals/combat_cue_renderer.gd")
	var cues: Array[Dictionary]=[]
	var effects: int=0
	func _draw() -> void: Renderer.render(self,cues,effects,true)

func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i: int in range(5): await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	arena.queue_redraw()
	await settle()
	var err: Error=root.get_texture().get_image().save_png(output.path_join(name+".png"))
	assert(err==OK)
func panel() -> Control: return arena.hud.find_child("SkillSupportPanel",true,false)
func select_skill(skill: String) -> void:
	var index: int=arena.state.skill_slots.find(skill)
	var button: Button=arena.hud.find_child("SlotButton%d" % (index+1) if index>=0 else "SelectSkill_"+skill,true,false)
	button.pressed.emit()
func run() -> void:
	if DisplayServer.get_name()=="headless" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-v018-native/"):
		quit(78)
		return
	output=OS.get_environment("GODOT_AREA_QA_DIR")
	assert(not output.is_empty())
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720)
	var fresh:=Model.new()
	fresh.slot_skill(0,"nova")
	assert(fresh.save_build()==OK)
	arena=load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire=false
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.spawn_timer=9999
	arena.player_pos=Vector2(700,350)
	add_targets()
	arena.hud.open_panel("skills")
	await settle()
	select_skill("nova")
	arena.hud._panel_scroll.ensure_control_visible(arena.hud.find_child("AddSupport_breadth",true,false))
	await settle()
	if OS.get_cmdline_user_args().has("--matrix-only"):
		busy=true
		await matrix()
		await pixel_bounds()
		write_report("render-report.json")
		print("AREA_RENDER_COMPLETE")
		quit(0)
		return
	stage=1
	print("AREA_NATIVE_READY: actual mouse add breadth, Escape, then physical key 1")
func add_targets() -> void:
	for offset: Vector2 in [Vector2.ZERO,Vector2(190,0),Vector2(-190,0),Vector2(0,190),Vector2(0,-190)]:
		var enemy: Dictionary=arena._spawn_monster("crawler",arena.player_pos+offset,"ordinary","normal",[])
		enemy.spawn=0.0
func _process(_delta: float) -> bool:
	if arena==null or busy: return false
	arena.queue_redraw()
	if stage==1 and arena.state.get_skill_supports("nova")==["breadth"]:
		busy=true
		call_deferred("accepted_link")
	if stage==2 and float(arena.cooldowns.get("nova",0))>0:
		busy=true
		call_deferred("accepted_cast")
	return false
func accepted_link() -> void:
	await capture("native-720-breadth-added")
	assert(arena.state.get_skill_cast("nova").recipe.radius==186.0)
	print("AREA_NATIVE_LINK_PASS")
	stage=2
	busy=false
func accepted_cast() -> void:
	await capture("native-720-nova-hit")
	var cues: Array=arena.visual_cues.cues.filter(func(cue: Dictionary) -> bool: return cue.kind=="nova")
	assert(cues.size()==1 and cues[0].radius==186.0)
	assert(arena.kills==5)
	var restored:=Model.new()
	assert(restored.load_build() and restored.get_skill_supports("nova")==["breadth"])
	records.append({"stage":"native_mouse_key_720", "skill":"nova", "radius":cues[0].radius,"kills":arena.kills,"mana":arena.mana,"cooldown":arena.cooldowns.nova,"save_matches":restored._snapshot()==arena.state._snapshot()})
	assert(records.back().save_matches)
	print("AREA_NATIVE_INPUT_PASS "+JSON.stringify(records.back()))
	stage=3
	await matrix()
	await pixel_bounds()
	write_report("native-report.json")
	print("AREA_NATIVE_COMPLETE")
	quit(0)
func write_report(name: String) -> void:
	var file:=FileAccess.open(output.path_join(name),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t",true,true)+"\n")
	file.close()
func matrix() -> void:
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		for scale: float in [1.0,1.2]:
			root.size=dimensions
			arena.visual_settings.ui_scale=1.1 if scale>1 else 1.0
			arena.visual_settings.font_scale=scale
			arena.hud._apply_presentation()
			for skill: String in ["nova","meteor"]:
				arena.state.set_skill_supports(skill,["breadth"])
				arena.hud.open_panel("skills")
				await settle()
				select_skill(skill)
				arena.hud._panel_scroll.scroll_vertical=0
				var stem: String="%s-%d-font%d" % [skill,dimensions.x,roundi(scale*100)]
				await capture(stem+"-preview")
				arena.hud._panel_scroll.ensure_control_visible(arena.hud.find_child("AddSupport_breadth",true,false))
				await capture(stem+"-card")
	root.size=Vector2i(2560,1440)
	for effects: int in [0,2]:
		arena.visual_settings.effects_level=effects
		for skill: String in ["nova","meteor"]:
			arena.hud.close_panel()
			arena.enemies.clear()
			arena.monster_runtime.reset()
			arena.visual_cues.reset()
			arena.particles.clear()
			arena.floating_text.clear()
			add_targets()
			arena.state.slot_skill(0,skill)
			arena.mana=100
			arena.cooldowns[skill]=0
			assert(arena.cast_skill(0))
			arena._update_effects(0.12)
			await capture("spell-%s-effects%d-2k" % [skill,effects])
			records.append({"stage":"programmatic_native_render_2k","skill":skill,"effects":effects,"radius":arena.state.get_skill_cast(skill).recipe.radius})

func pixel_bounds() -> void:
	const Cues=preload("res://scripts/visuals/combat_cues.gd")
	for skill: String in ["nova","meteor"]:
		for wide: bool in [false,true]:
			arena.state.set_skill_supports(skill,["breadth"] if wide else [])
			var cast: Dictionary=arena.state.get_skill_cast(skill)
			for effects: int in [0,2]:
				var viewport:=SubViewport.new()
				viewport.size=Vector2i(512,512)
				viewport.transparent_bg=true
				viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
				root.add_child(viewport)
				var surface:=CueSurface.new()
				var pool:=Cues.new()
				pool.emit_cue(skill,Vector2(256,256),{"radius":cast.recipe.radius,"color":GameData.SKILLS[skill].color})
				pool.advance(0.12)
				surface.cues=pool.cues
				surface.effects=effects
				viewport.add_child(surface)
				await settle()
				var pixels: Image=viewport.get_texture().get_image()
				var count: int=0
				for y: int in range(512):
					for x: int in range(512):
						if pixels.get_pixel(x,y).a>0.03:
							count+=1
							assert(Vector2(x,y).distance_to(Vector2(256,256))<=float(cast.recipe.radius)+3.0,"Rendered pulse must stay bounded")
				var directions: int=(6 if effects==0 else 8) if skill=="nova" else 4
				for i: int in range(directions):
					var angle: float=i*TAU/directions+(0.0 if skill=="nova" else PI/4)
					var target: Vector2=Vector2(256,256)+Vector2.RIGHT.rotated(angle)*(float(cast.recipe.radius)-2.0)
					var seen: bool=false
					for dy: int in range(-3,4):
						for dx: int in range(-3,4):
							seen=seen or pixels.get_pixel(roundi(target.x)+dx,roundi(target.y)+dy).a>0.03
					assert(seen,"Low/high mode retains true-radius boundary pixels")
				assert(count>20)
				assert(pixels.save_png(output.path_join("boundary-%s-%s-effects%d.png" % [skill,"wide" if wide else "base",effects]))==OK)
				records.append({"stage":"native_transparent_pixel_bounds","skill":skill,"wide":wide,"effects":effects,"radius":cast.recipe.radius,"visible_pixels":count,"boundary_directions":directions,"bounds_pass":true})
				viewport.queue_free()
				await process_frame
