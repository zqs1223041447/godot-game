extends SceneTree
const Art = preload("res://scripts/visuals/equipment_painterly_art.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
var checks := 0
var failures := 0
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var entry := {"base_id":"forgeblade","kind":"equipment"}
	expect(Art.canonical_id(entry) == "forgeblade", "Stable base selects original short blade art")
	expect(Art.resource_path(entry) == "res://assets/art/equipment/forgeblade.png", "Correct asset mapping")
	var texture := Art.texture_for_entry(entry)
	expect(texture != null, "Imported artwork resolves")
	var source := Art.source_rect(entry)
	expect(source.has_area() and source.size.y > source.size.x, "Vertical nonempty alpha bounds")
	var bounds := Rect2(3,5,32,96)
	var fitted := Art.fitted_rect(bounds,source.size)
	expect(bounds.encloses(fitted), "One by three bag footprint contains art")
	expect(is_equal_approx(fitted.size.x/fitted.size.y,source.size.x/source.size.y), "Aspect ratio preserved")
	var cast := Compiler.compile_skill("cleave",Combat.snapshot({"damage":18.0},[]),[])
	expect(cast.get("ok",false), "Actual cleave preview available")
	var before := var_to_bytes(cast)
	var text := Preview.details(cast)
	expect(text.contains("锻纹短刃") and text.contains("白蜡长弓不参与"), "Correct local weapon scope stated")
	expect(var_to_bytes(cast) == before, "Preview does not mutate cast")
	var packet := {"assembly":{"weapon":{"contribution":{"physical":36.4},"coefficient":2.8,"profile":{"base":{"physical":4.0},"flat":{"physical":6.0},"increased":{"physical":0.3}}}}}
	var line := Preview.assembly_line(packet)
	expect(line.contains("36.40") and line.contains("技能倍率 2.80"), "Actual contribution and coefficient displayed once")
	print("Forgeblade presentation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
