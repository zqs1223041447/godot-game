extends SceneTree
const Renderer = preload("res://scripts/visuals/combat_feedback_renderer.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr(label)
func _initialize() -> void:
	check(Renderer.amount_text(0.0) == "", "zero hidden")
	check(Renderer.amount_text(0.001) == "<0.01", "tiny positive visible")
	check(Renderer.amount_text(0.25) == "0.25", "fraction precision")
	check(Renderer.amount_text(2.5) == "2.5", "small precision")
	check(Renderer.amount_text(23.5) == "24", "large rounded display only")
	var base := {"amount":12.4,"age":0.0,"lifetime":0.75,"kind":"hit","target_kind":"monster"}
	var original := base.duplicate(true)
	var hit := Renderer.presentation(base)
	check(hit.text == "12" and hit.font_size == 16, "normal style")
	check(base == original, "input remains unchanged")
	base.kind = "critical"
	var critical := Renderer.presentation(base)
	check(critical.text == "12!" and critical.font_size > hit.font_size, "critical style")
	base.kind = "burn"
	var burn := Renderer.presentation(base)
	check(burn.text == "燃 12" and burn.offset.y < critical.offset.y, "burn separated")
	base.target_kind = "player"
	check(Renderer.presentation(base).text == "-燃 12", "player loss marked")
	base.age = 0.7
	check(Renderer.presentation(base).color.a < 1.0, "lifetime fade")
	base.age = 0.75
	check(Renderer.presentation(base).is_empty(), "expired hidden")
	print("presentation checks=",checks," failures=",failures)
	quit(1 if failures else 0)
