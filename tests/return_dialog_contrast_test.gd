extends SceneTree
## Resolved styles on the actual HUD dialog, not a standalone theme fixture.
const Design = preload("res://scripts/visuals/visual_theme.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func contrast(a: Color, b: Color) -> float:
	var first := a.srgb_to_linear().get_luminance()
	var second := b.srgb_to_linear().get_luminance()
	return (maxf(first, second) + 0.05) / (minf(first, second) + 0.05)

func run() -> void:
	if OS.get_name() != "Linux" or not OS.get_data_dir().begins_with("/tmp/godot-"):
		push_error("Return dialog UI requires isolated Linux XDG storage")
		quit(78)
		return
	root.size = Vector2i(1280, 720)
	var arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	var dialog: ConfirmationDialog = arena.hud._return_dialog
	var shared: Theme = arena.hud._root.theme
	var revision: int = arena.world_context().revision
	var title := dialog.title
	var wording := dialog.dialog_text
	for pass_index: int in range(2):
		dialog.popup_centered(Vector2i(380, 160))
		await process_frame
		check(dialog.visible, "Actual return dialog opens/reopens")
		for state: String in ["embedded_border", "embedded_unfocused_border"]:
			var frame := dialog.get_theme_stylebox(state, "Window") as StyleBoxFlat
			check(frame != null, state + " retains native window geometry")
			if frame != null:
				check(frame.bg_color == Color("60432f"), state + " matches existing warm confirmation frames")
				check(contrast(dialog.get_theme_color("title_color", "Window"), frame.bg_color) >= 4.5, state + " title has readable contrast")
		for button: Button in [dialog.get_ok_button(), dialog.get_cancel_button()]:
			for pair: Array in [["font_color", "normal"], ["font_hover_color", "hover"], ["font_pressed_color", "pressed"], ["font_hover_pressed_color", "pressed"], ["font_focus_color", "normal"]]:
				var ink := button.get_theme_color(pair[0])
				var paper: StyleBox = button.get_theme_stylebox(pair[1])
				check(ink == Design.TEXT, button.text + " " + pair[0] + " retains dark ink")
				check(contrast(ink, paper.bg_color) >= 4.5, button.text + " " + pair[0] + " contrasts with paper")
				check(paper == shared.get_stylebox(pair[1], "Button"), "Parchment material stays inherited")
			button.grab_focus()
			await process_frame
			check(button.has_focus(), button.text + " remains keyboard focusable")
			var focus: StyleBox = button.get_theme_stylebox("focus")
			check(focus.bg_color.a == 0.0 and focus.border_width >= 2.0, "Visible focus outline does not obscure button text")
			button.disabled = true
			check(button.get_theme_color("font_disabled_color") == shared.get_color("font_disabled_color", "Button"), "Disabled state retains the existing muted ink")
			check(button.get_theme_stylebox("disabled") == shared.get_stylebox("disabled", "Button"), "Disabled paper stays unchanged")
			button.disabled = false
		dialog.hide()
		await process_frame
	check(dialog.title == title and dialog.dialog_text == wording, "Styling does not rewrite dialog text")
	check(dialog.ok_button_text == "确认" and dialog.cancel_button_text == "取消", "Action labels are preserved")
	check(arena.world_context().revision == revision, "Opening/dismissing the style fixture cannot return or mutate the world")
	check(shared.get_color("title_color", "Window") == Design.TEXT, "Shared Window theme is not mutated")
	check(not shared.has_color("font_focus_color", "Button") and not shared.has_color("font_hover_pressed_color", "Button"), "Local button fixes do not change other controls")
	check(arena.hud._encounter_dialog.get_theme_color("title_color", "Window") == Color("f8ecd0"), "Existing encounter title remains unchanged")
	arena.queue_free()
	await process_frame
	print("Return dialog contrast: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
