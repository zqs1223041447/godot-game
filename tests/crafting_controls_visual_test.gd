extends SceneTree
## Isolated native rendering QA. Never loads main.tscn, BuildState or a save.
## Set GODOT_CRAFTING_TEST_ROOT and isolated data/config/cache directories.
## Run without --headless: --script res://tests/crafting_controls_visual_test.gd -- --output DIR
const Controls = preload("res://scripts/ui/crafting_controls.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Presentation = preload("res://scripts/visuals/visual_theme.gd")
const Art = preload("res://scripts/visuals/equipment_painterly_art.gd")

var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var requests: Array[Dictionary] = []
var output: String = ""
var sheet: Control
var cards: Array[Controls] = []
var item: Dictionary
var normal_item: Dictionary
var salvage: Dictionary
var plan: Dictionary
var long_reason: String
var case_name: String
var case_filter: String = ""


class FixtureItemArt extends Control:
	var entry: Dictionary
	func _draw() -> void:
		Art.draw_item(self, entry, Rect2(Vector2.ZERO, size))


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(case_name + ": " + message)
		push_error("CRAFTING_VISUAL_FAIL " + failures.back())


func _settle() -> void:
	for unused: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	var isolated: String = OS.get_environment("GODOT_CRAFTING_TEST_ROOT").replace("\\", "/").trim_suffix("/")
	var user_dir: String = OS.get_user_data_dir().replace("\\", "/")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = args.find("--output")
	if index >= 0 and index + 1 < args.size():
		output = args[index + 1]
	index = args.find("--case")
	if index >= 0 and index + 1 < args.size():
		case_filter = args[index + 1]
	if isolated.is_empty() or not user_dir.begins_with(isolated + "/"):
		push_error("CRAFTING_VISUAL_BLOCKED user:// is not inside GODOT_CRAFTING_TEST_ROOT: " + user_dir)
		quit(2)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("CRAFTING_VISUAL_BLOCKED Native rendering is required; headless is not pixel evidence.")
		quit(2)
		return
	if not output.is_absolute_path() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("CRAFTING_VISUAL_BLOCKED Supply a writable absolute --output directory.")
		quit(2)
		return
	print("CRAFTING_VISUAL_ENV ", JSON.stringify({"godot": Engine.get_version_info().string,
		"os": OS.get_name(), "display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"device": RenderingServer.get_video_adapter_name(), "user_dir": user_dir}))
	# Preserve the project's 1280x720 canvas-items stretch at both physical resolutions.
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	# Native Godot TooltipPanel/TooltipLabel, embedded so the viewport PNG includes it.
	root.gui_embed_subwindows = true
	root.position = Vector2i.ZERO
	item = {"id": "gear_000123", "base_id": "ashwood_bow", "rarity": "magic", "item_level": 16,
		"affixes": [{"id": "farweave", "tier": 1, "value": Catalog.affix_definition("farweave").tiers[0].min}]}
	normal_item = item.duplicate(true)
	normal_item.rarity = "normal"
	normal_item.affixes = []
	salvage = Craft.salvage_quote(item)
	plan = Craft.recalibrate_plan(item, 20261002)
	_expect(Catalog.validate_instance(item) and salvage.ok and plan.ok, "Actual Craft quotes must be valid")
	if not salvage.ok or not plan.ok:
		_finish()
		return
	# Synthetic upper-layer aggregate: four copies of actual Craft refusal reasons.
	# No invented quote amounts or replacement tooltip widget; context API accepts this string.
	var actual_reasons: String = " ".join([Craft.salvage_quote(normal_item).reason,
		Craft.salvage_quote({}).reason, Craft.recalibrate_plan(item, "invalid_seed").reason])
	long_reason = " ".join([actual_reasons, actual_reasons, actual_reasons, actual_reasons])
	var executed: int = 0
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		root.size = dimensions
		await _settle()
		for width: int in [220, 280]:
			for font_scale: float in [1.0, 1.2]:
				case_name = "%dx%d-w%d-f%d" % [dimensions.x, dimensions.y, width, roundi(font_scale * 100)]
				if not case_filter.is_empty() and case_filter != case_name:
					continue
				executed += 1
				_build_sheet(width, font_scale)
				await _settle()
				_move(Vector2(1190, 650))
				_button(cards[0], "RecalibrateButton").grab_focus()
				await _settle()
				_check_layout(width, font_scale)
				await _capture("matrix", dimensions)
				await _check_mouse()
				# Inspect a real native popup in every matrix combination.
				await _tooltip(_button(cards[2], "RecalibrateButton"), "insufficient", dimensions,
					width == 220 and font_scale == 1.2)
				await _tooltip(_button(cards[4], "RecalibrateButton"), "long-error", dimensions, true)
				if width == 220 and font_scale == 1.2:
					await _tooltip(_button(cards[0], "RecalibrateButton"), "enabled-warning", dimensions, true)
					await _tooltip(_button(cards[1], "SalvageButton"), "disabled-equipped", dimensions, true)
					await _tooltip(_label(cards[5]), "full-balance", dimensions, true)
					# Same aggregate with explicit line breaks tests normal multiline native rendering.
					cards[4].set_context(item.id, item, 100, salvage, plan, actual_reasons.replace(" ", "\n"))
					await _tooltip(_button(cards[4], "RecalibrateButton"), "multiline-error", dimensions, true)
					var button: Button = _button(cards[0], "RecalibrateButton")
					_move(button.get_global_rect().get_center())
					await _settle()
					_click(button, true)
					await _capture("pressed", dimensions)
					_click(button, false)
				_move(Vector2(1190, 650))
				sheet.queue_free()
				await process_frame
	_expect(executed > 0, "Requested matrix case exists")
	_finish()


func _build_sheet(width: int, font_scale: float) -> void:
	cards.clear()
	sheet = Control.new()
	sheet.name = "IsolatedCraftingVisualFixture"
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.theme = Presentation.create_theme()
	sheet.theme.default_font_size = roundi(16 * font_scale)
	sheet.size = Vector2(1280, 720)
	root.add_child(sheet)
	var background := ColorRect.new()
	background.color = Color("30261e")
	background.size = sheet.size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(background)
	_text(sheet, "制作操作行 / 真实 Godot 渲染", Vector2(36, 20), 22, Presentation.PANEL)
	_text(sheet, case_name + "   canvas 1280x720", Vector2(36, 60), 16, Color("d8b577"))
	var headings: Array[String] = ["选中装备 / 可用", "穿戴中 / 禁用", "校准碎片不足",
		"普通无词缀 / 报价失败", "长原因 / 禁用", "极长余额 / 可用"]
	for slot: int in range(6):
		var origin := Vector2(36 + (slot % 2) * (width + 48), 110 + (slot / 2) * 180)
		var panel := Panel.new()
		panel.position = origin
		panel.size = Vector2(width + 24, 160)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", Presentation.panel(Color("f8ecd0"), Presentation.GOLD if slot == 0 else Presentation.BORDER, 6, 2 if slot == 0 else 1, 0))
		sheet.add_child(panel)
		_text(panel, headings[slot], Vector2(12, 9), 14, Presentation.TEXT)
		var art := FixtureItemArt.new()
		art.entry = Catalog.definition(item)
		art.position = Vector2(12, 38)
		art.size = Vector2(50, 66)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(art)
		_text(panel, "白蜡长弓", Vector2(78, 42), 18, Presentation.GOLD)
		_text(panel, "远织 T1 / 投射物伤害", Vector2(78, 76), 12, Presentation.MUTED)
		var controls := Controls.new()
		controls.position = Vector2(12, 120)
		controls.size = Vector2(width, 32)
		var source: Dictionary = normal_item if slot == 3 else item
		var balance: int = int(plan.cost.calibration_shard) - 1 if slot == 2 else 12345
		if slot == 5:
			balance = 9223372036854775807
		var reason: String = "请先卸下穿戴中的装备。" if slot == 1 else long_reason if slot == 4 else ""
		controls.set_context(source.id, source, balance, Craft.salvage_quote(source), Craft.recalibrate_plan(source, 20261002), reason)
		controls.craft_requested.connect(func(operation: String, id: String, snapshot: Dictionary) -> void:
			requests.append({"operation": operation, "id": id, "source": snapshot}))
		panel.add_child(controls)
		cards.append(controls)
	_text(sheet, "独立临时场景", Vector2(760, 120), 20, Color("d8b577"))
	_text(sheet, "未加载主游戏或存档\n报价来自 Craft\n原控件 / 原主题 / 指定字体\n鼠标悬停后显示原生提示", Vector2(760, 168), 16, Color("eee2c7"))
	_text(sheet, "selected / disabled / insufficient\nquote rejection / long reason / balance\nNative popup bounds are checked.", Vector2(760, 370), 15, Color("eee2c7"))
	Presentation.apply_font_scale(sheet, font_scale)


func _text(parent: Node, value: String, at: Vector2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _button(target: Controls, stable_name: String) -> Button:
	return target.get_node("CraftingRow/" + stable_name) as Button


func _label(target: Controls) -> Label:
	return target.get_node("CraftingRow/MaterialBalanceLabel") as Label


func _check_layout(width: int, font_scale: float) -> void:
	var sizes: Array[Dictionary] = []
	for target: Controls in cards:
		var row: HBoxContainer = target.get_node("CraftingRow")
		_expect(target.size.x <= width + 0.1 and row.size.x <= width + 0.1, "Row stays within requested width")
		var end: float = 0
		for child: Control in row.get_children():
			_expect(child.position.x >= end and child.get_rect().end.x <= width + 0.1, "No child overlap/overflow: " + child.name)
			_expect(child.get_theme_font_size("font_size") == roundi(13 * font_scale), "Font scale is applied: " + child.name)
			end = child.get_rect().end.x
		var label: Label = _label(target)
		var text_width: float = label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		if target != cards[5]:
			_expect(text_width <= label.size.x, "Five-digit balance is fully visible")
		sizes.append({"row": str(row.size), "label": str(label.size), "text_width": text_width,
			"font": label.get_theme_font_size("font_size")})
	var selected: Button = _button(cards[0], "RecalibrateButton")
	_expect(selected.has_focus(), "Selected item's button has visible focus")
	# Read the effective native focus color; inherited Godot defaults can differ from normal text.
	# The authored paper tint is a diagnostic baseline; inspect the actual textured PNG as well.
	var background: Color = selected.get_theme_stylebox("normal").get("bg_color")
	var focused: Color = selected.get_theme_color("font_focus_color")
	var regular: Color = selected.get_theme_color("font_color")
	var focus_contrast: float = _contrast(focused, background)
	_expect(_contrast(regular, background) >= 4.5, "Normal small button text has readable authored-color contrast")
	_expect(focus_contrast >= 4.5, "Focused small button text has readable authored-color contrast")
	_expect(_button(cards[1], "SalvageButton").disabled and _button(cards[1], "RecalibrateButton").disabled, "Equipped override disables both actions")
	_expect(not _button(cards[2], "SalvageButton").disabled and _button(cards[2], "RecalibrateButton").disabled, "Insufficient funds disables recalibration only")
	_expect(_button(cards[3], "SalvageButton").disabled and _button(cards[3], "RecalibrateButton").disabled, "Actual Craft rejection disables both actions")
	# Query the actual imported FontFile RID, so a system fallback cannot hide missing Chinese.
	var font: Font = _label(cards[0]).get_theme_font("font")
	var rid: RID = font.get_rids()[0]
	var server: TextServer = TextServerManager.get_primary_interface()
	var displayed: String = long_reason + _label(cards[0]).text + "回收校准" + _button(cards[0], "RecalibrateButton").tooltip_text
	for character: String in displayed:
		var code: int = character.unicode_at(0)
		if code >= 0x3400 and code <= 0x9fff:
			_expect(server.font_has_char(rid, code) and server.font_get_glyph_index(rid, 13, code, 0) != 0, "Chinese exists in native font: " + character)
	observations.append({"case": case_name, "layout": sizes, "focus_color": str(focused),
		"normal_color": str(regular), "paper_color": str(background), "focus_contrast": focus_contrast,
		"normal_contrast": _contrast(regular, background)})


func _contrast(foreground: Color, background: Color) -> float:
	var first: float = foreground.srgb_to_linear().get_luminance()
	var second: float = background.srgb_to_linear().get_luminance()
	return (maxf(first, second) + 0.05) / (minf(first, second) + 0.05)


func _move(point: Vector2, warp_cursor: bool = true) -> void:
	if warp_cursor:
		root.warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)


func _click(button: Button, pressed: bool, point: Vector2 = Vector2(-1, -1)) -> void:
	var at: Vector2 = button.get_global_rect().get_center() if point.x < 0 else point
	# The preceding hover has already warped the OS cursor. A second X11 warp
	# would send an asynchronous motion with no held buttons during the GUI press.
	_move(at, false)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	root.push_input(event, true)


func _check_mouse() -> void:
	for slot: int in [0, 1, 2, 3, 4, 5]:
		for stable_name: String in ["SalvageButton", "RecalibrateButton"]:
			var button: Button = _button(cards[slot], stable_name)
			var before: int = requests.size()
			_move(button.get_global_rect().get_center())
			await process_frame
			_expect(root.gui_get_hovered_control() == button, "Mouse target is unobstructed: %d/%s" % [slot, stable_name])
			_click(button, true)
			await process_frame
			_expect(button.is_pressed() == not button.disabled, "Native pressed state agrees with disabled state")
			_click(button, false)
			await process_frame
			_expect(requests.size() == before + (0 if button.disabled else 1), "One GUI click emits exactly the permitted request")
			if not button.disabled and requests.size() > before:
				_expect(requests.back().id == item.id and requests.back().source == item, "Actual mouse request contains selected original instance")
	# A press dragged off the row cancels; neighbouring content is not a click blocker.
	var enabled: Button = _button(cards[0], "RecalibrateButton")
	var count: int = requests.size()
	_click(enabled, true)
	_click(enabled, false, Vector2(1190, 650))
	await process_frame
	_expect(requests.size() == count, "Dragging release outside cancels activation")
	_move(Vector2(1190, 650))
	await _settle()


func _tooltip(target: Control, tag: String, dimensions: Vector2i, capture: bool) -> void:
	_move(Vector2(1190, 650))
	await process_frame
	_move(target.get_global_rect().get_center())
	await create_timer(float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5)) + 0.2).timeout
	await _settle()
	_expect(root.gui_get_hovered_control() == target, "Visible tooltip does not obstruct its mouse target: " + tag)
	var popup: PopupPanel = _find_popup(root)
	_expect(popup != null, "Real native tooltip becomes visible: " + tag)
	if popup != null:
		var label: Label = null
		# Tooltips are internal nodes; include them instead of assuming owned node names.
		for descendant: Node in popup.get_children(true):
			if descendant is Label:
				label = descendant as Label
				break
		_expect(label != null and label.text == target.tooltip_text, "Native tooltip preserves complete text: " + tag)
		var bounds := Rect2(Vector2(popup.position), Vector2(popup.size))
		var viewport := Rect2(Vector2.ZERO, root.get_visible_rect().size)
		_expect(viewport.encloses(bounds), "Native tooltip stays entirely inside visible canvas: " + tag)
		if label != null:
			var required: Vector2 = label.get_minimum_size()
			_expect(label.size.x + 0.1 >= required.x and label.size.y + 0.1 >= required.y, "Native tooltip does not clip its label: " + tag)
		observations.append({"case": case_name, "tooltip": tag, "bounds": str(bounds),
			"canvas": str(viewport), "characters": target.tooltip_text.length(),
			"label_size": str(label.size) if label != null else "missing",
			"font_size": label.get_theme_font_size("font_size") if label != null else -1,
			"inside_canvas": viewport.encloses(bounds)})
	if capture:
		await _capture(tag, dimensions)
	_move(Vector2(1190, 650))
	await process_frame


func _find_popup(node: Node) -> PopupPanel:
	# Godot attaches its internal tooltip to the hovered Control, not necessarily the root.
	for child: Node in node.get_children(true):
		if child is PopupPanel and child.visible:
			return child as PopupPanel
		var found: PopupPanel = _find_popup(child)
		if found != null:
			return found
	return null


func _capture(tag: String, dimensions: Vector2i) -> void:
	await _settle()
	if tag == "pressed":
		_expect(_button(cards[0], "RecalibrateButton").is_pressed(), "Pressed screenshot is captured while the button is actually down")
	var pixels: Image = root.get_texture().get_image()
	_expect(pixels != null and not pixels.is_empty() and pixels.get_size() == dimensions, "Actual rendered pixels have requested physical resolution: " + tag)
	if pixels != null and not pixels.is_empty():
		var path: String = output.path_join(case_name + "-" + tag + ".png")
		_expect(pixels.save_png(path) == OK, "Screenshot is written: " + tag)
		print("CRAFTING_VISUAL_CAPTURE ", path)


func _finish() -> void:
	var report: Dictionary = {"checks": checks, "failures": failures, "requests": requests.size(), "observations": observations}
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("observations.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
	print("CRAFTING_VISUAL_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "requests": requests.size()}))
	quit(0 if failures.is_empty() else 1)
