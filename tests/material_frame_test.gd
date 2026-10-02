extends SceneTree
const Design=preload("res://scripts/visuals/visual_theme.gd")
const Frame=preload("res://scripts/visuals/material_frame.gd")
var checks:int=0
var failures:int=0
func _initialize()->void:
	var theme:Theme=Design.create_theme()
	for state:String in ["normal","hover","pressed","disabled","focus"]:
		var original:StyleBox=theme.get_stylebox(state,"Button")
		var copied:StyleBox=original.duplicate()
		expect(original is Frame and copied is Frame,"material resource "+state)
		for field:String in ["bg_color","border_color","border_width","corner_cut","grain","book_cover","content_margin_left","content_margin_right","content_margin_top","content_margin_bottom"]:
			expect(original.get(field)==copied.get(field),"hotbar style duplicate preserves %s %s"%[state,field])
		expect(original.get_minimum_size()==copied.get_minimum_size(),"unchanged minimum size "+state)
	expect(theme.get_stylebox("focus","Button").bg_color.a==0,"focus remains transparent")
	expect(Design.panel(Color.RED,Color.RED,2,0,0) is StyleBoxFlat,"resource bars keep clean flat fill")
	for size:Vector2 in [Vector2(1,1),Vector2(5,3),Vector2(42,42),Vector2(1200,600)]:
		var frame:=Frame.new()
		for cut:float in [0.0,4.0,99.0]:
			var rect:=Rect2(Vector2(20,30),size)
			var shape:PackedVector2Array=frame._shape(rect,cut)
			for point:Vector2 in shape:
				expect(point.is_finite() and rect.grow(0.01).has_point(point),"material polygon remains inside supplied bounds")
	print("material_frame_test: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		printerr("FAIL: "+message)
