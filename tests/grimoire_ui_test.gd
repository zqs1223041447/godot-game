extends SceneTree
## Style-only contract. Run with isolated XDG data/config/cache roots.
const Design=preload("res://scripts/visuals/visual_theme.gd")
const Frame=preload("res://scripts/visuals/material_frame.gd")
const Emblem=preload("res://scripts/visuals/skill_emblem.gd")
var checks:int=0
var failures:int=0
func _initialize()->void: call_deferred("run")
func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func channel_linear(value:float)->float:
	return value/12.92 if value<=0.04045 else pow((value+0.055)/1.055,2.4)
func luminance(color:Color)->float:
	return channel_linear(color.r)*0.2126+channel_linear(color.g)*0.7152+channel_linear(color.b)*0.0722
func contrast(a:Color,b:Color)->float:
	return (maxf(luminance(a),luminance(b))+0.05)/(minf(luminance(a),luminance(b))+0.05)
func run()->void:
	expect(contrast(Design.TEXT,Design.PANEL)>=7.0,"Body brown ink on parchment is high contrast")
	expect(contrast(Design.MUTED,Design.PANEL)>=4.5,"Secondary ink is readable")
	expect(contrast(Color("f8ecd0"),Color("38261d"))>=7.0,"Leather uses ivory text")
	expect(contrast(Color("f8ecd0"),Color("7a2f29"))>=7.0,"Burgundy bookmark uses ivory")
	var theme:Theme=Design.create_theme()
	expect(contrast(theme.get_color("font_placeholder_color","LineEdit"),Design.PANEL)>=3.0,"Search placeholder has visible ink")
	expect(contrast(theme.get_color("font_hover_color","PopupMenu"),theme.get_stylebox("hover","PopupMenu").bg_color)>=4.5,"Popup selection retains contrast")
	var book:StyleBox=Design.panel()
	book.book_cover=true
	var copied:StyleBox=book.duplicate()
	expect(copied.book_cover,"Book-cover storage survives duplication")
	for id:String in GameData.SKILLS:
		expect(Emblem.ICONS.has(id),"Actual skill has specific painted art: "+id)
	for id:String in preload("res://scripts/combat/support_registry.gd").SUPPORTS:
		expect(Emblem.ICONS.has(id),"Actual support has specific painted art: "+id)
	for id:String in Emblem.ICONS:
		var texture:Texture2D=Emblem.ICONS[id]
		expect(texture!=null and texture.get_width()>=256 and texture.get_height()>=256,"Imported image is production sized: "+id)
	var arena:Node=load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	expect(arena.hud._root.texture_filter==CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,"Painted UI uses mipmap filtering at small sizes")
	await process_frame
	var state:Dictionary=arena.state._snapshot()
	for page:String in ["inventory","talents","skills","combat","monsters","settings","pause"]:
		arena.hud.open_panel(page)
		await process_frame
		expect(arena.hud.is_blocking(),"UI retains modal pause: "+page)
		expect(arena.state._snapshot()==state,"Opening style-only UI never changes build: "+page)
		var frame:Control=arena.hud._modal.find_child("BuildPanel",true,false)
		expect(frame.get_theme_stylebox("panel").book_cover,"Same book frame across panels: "+page)
	arena.hud.open_panel("inventory")
	var summary:Label=arena.hud.find_child("DerivedStatsLabel",true,false)
	expect(summary.mouse_filter==Control.MOUSE_FILTER_PASS and "火焰抗性" in summary.tooltip_text,"Inventory defense tooltip can receive hover")
	var health:ProgressBar=arena.hud.find_child("HealthBar",true,false)
	expect(health.mouse_filter==Control.MOUSE_FILTER_PASS and "火抗" in health.tooltip_text,"Health defense tooltip can receive hover")
	arena.hud.open_panel("skills")
	var support:Control=arena.hud.find_child("SkillSupportPanel",true,false)
	for id:String in GameData.SKILLS:
		support.select_skill(id)
		expect(support._selected_art.skill_id==id,"Illustration follows stable model identity: "+id)
		expect(support.find_child("SupportSlots",true,false).get_child_count()==2,"Exactly two existing supports: "+id)
	arena.hud.close_panel()
	expect(not arena.hud.is_blocking(),"Closing book restores gameplay input")
	for id:String in ["HealthValue","ManaValue","ShieldValue"]:
		var label:Label=arena.hud.find_child(id,true,false)
		expect(label.get_theme_color("font_color")==Color("f8ecd0"),"Resource numbers stay ivory on filled bars: "+id)
	arena.queue_free()
	await process_frame
	print("grimoire_ui_test: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
