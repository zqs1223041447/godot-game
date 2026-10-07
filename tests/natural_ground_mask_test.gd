extends SceneTree
const Session = preload("res://scripts/studies/modular_study_session.gd")
const Geometry = preload("res://scripts/studies/modular_study_geometry.gd")
const Ground = preload("res://scripts/visuals/study_ground_layer.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var bounds:=Rect2(42,104,3600,2400)
	var layout:Dictionary=Session.layout(bounds)
	var geometry=Geometry.new()
	var installed:Dictionary=geometry.install(bounds,layout.polygons,bounds.position+Vector2(320,2080),layout.presentation)
	if not installed.ok:push_error(str(installed));quit(1);return
	await physics_frame;await physics_frame
	check(geometry.physics_ready(),"Current original contours ready")
	var profile:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/studies/natural_ground/profile.json"))
	check(profile.paint_half_width_world==32.0 and profile.paint_half_width_world<=24.0*1.4 and profile.paint_validation_radius_world==57.0,"Width is1.33x within approved maximum with full filter/body clearance")
	check(profile.wear_seed==1137 and profile.wear_scale_world==140.0,"Fixed broad wear without highfrequency runtime noise")
	check(profile.route_segments.size()==10,"Same ten accepted presentation routes remain")
	for route:Dictionary in profile.route_segments:
		var start:=Vector2(route["from"][0],route["from"][1]);var end:=Vector2(route["to"][0],route["to"][1])
		check(geometry.is_clear(start,57.0) and geometry.is_clear(end,57.0) and not geometry.sweep(start,end,57.0).hit,"Full widened stone/feather/body envelope clears native geometry")
	check(FileAccess.get_sha256(profile.mask_path)==profile.mask_sha256,"Final worn mask SHA matches profile")
	var ground:=Ground.new()
	check(ground.configure(geometry.snapshot()) and ground.diagnostics().ready and ground.diagnostics().build_count==1,"Final resources activate unchanged ground shader")
	var image:=Image.load_from_file(ProjectSettings.globalize_path(profile.mask_path))
	var pixels:=image.get_data();var opaque:=true
	for index in range(3,pixels.size(),4):opaque=opaque and pixels[index]==255
	check(image.get_size()==Vector2i(512,384) and opaque,"All196608 blend-mask pixels remain opaque data")
	ground.free()
	print("NATURAL_GROUND_MASK: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
