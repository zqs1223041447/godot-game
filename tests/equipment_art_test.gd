extends SceneTree
## Pure geometry + actual draw-call regression test. Optional native contact sheet:
## godot --path . --script res://tests/equipment_art_test.gd -- --capture /tmp/equipment-art.png
## --capture requires a real display/rendering backend; the regular test is headless-safe.
const Art = preload("res://scripts/visuals/equipment_art.gd")
const Data = preload("res://scripts/game_data.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
var failures: Array[String] = []
var entries: Array[Dictionary] = []
var passed_draw: bool = false

class Recorder extends Art.Pen:
	var commands: Array[Dictionary] = []
	func _init(rect: Rect2, design: Vector2, hint: bool = false) -> void:
		super(null, rect, design, hint)
	func poly(values: Array, color: Color, outlined: bool = false, edge: Color = Art.INK, width: float = 1.6) -> void:
		var stroke: float = width * scale if outlined else 0.0
		commands.append({"points": mapped(values, stroke), "color": tint(color), "edge": tint(edge), "width": stroke, "closed": true})
	func line(values: Array, color: Color, width: float = 1.2) -> void:
		commands.append({"points": mapped(values, width * scale), "color": tint(color), "width": width * scale, "closed": false})

class DrawingSurface extends Node2D:
	var owner_test: SceneTree
	func _draw() -> void:
		var sizes: Array[Vector2] = [Vector2(28, 91), Vector2(70, 91), Vector2(28, 28), Vector2(188, 240), Vector2(51, 57), Vector2(3, 3), Vector2(2, 2), Vector2.ZERO, Vector2(-4, 5)]
		seed(91717)
		var expected: int = randi()
		seed(91717)
		for entry: Dictionary in owner_test.entries:
			var before: Dictionary = entry.duplicate(true)
			for dimensions: Vector2 in sizes:
				Art.draw_item(self, entry, Rect2(Vector2(7, 11), dimensions))
			owner_test.check(before == entry, "draw_item mutated entry")
		Art.draw_item(self, {}, Rect2(0, 0, 28, 28))
		Art.draw_item(self, {"slot": "weapon", "base_name": "未知杖"}, Rect2(0, 0, 28, 91))
		Art.draw_item(self, {"slot": "weapon", "base_name": "符木法器"}, Rect2(0, 0, 28, 91))
		Art.draw_item(self, {"slot": "armor", "base_name": "未知袍"}, Rect2(0, 0, 70, 91))
		Art.draw_item(self, {"kind": "jewel", "base": "unknown"}, Rect2(0, 0, 28, 28))
		Art.draw_item(self, {}, Rect2(Vector2(INF, 0), Vector2(10, 10)))
		owner_test.check(expected == randi(), "drawing consumed global RNG")
		owner_test.passed_draw = true

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

func fixture(id: String, rect: Rect2, hint: bool = false) -> Recorder:
	var design := Vector2(84, 94)
	if id in ["ember_wand", "cinder_reed"]:
		design = Vector2(46, 154)
	elif id == "runewood_focus":
		design = Vector2(48, 144)
	elif id == "prism_bow":
		design = Vector2(58, 154)
	elif id in ["swift_blade", "gale_spindle"]:
		design = Vector2(54, 154)
	elif id == "return_mantle":
		design = Vector2(114, 146)
	elif id in ["guardian_robe", "tidebound_coat"]:
		design = Vector2(116, 150)
	elif id in ["vitality_armor", "woven_bastion"]:
		design = Vector2(114, 130)
	elif Jewels.BASES.has(id):
		design = Vector2(80, 88)
	var pen := Recorder.new(rect, design, hint)
	if id in ["ember_wand", "cinder_reed"]:
		Art._draw_staff(pen, id == "cinder_reed")
	elif id == "runewood_focus":
		Art._draw_runewood_focus(pen)
	elif id == "prism_bow":
		Art._draw_bow(pen)
	elif id in ["swift_blade", "gale_spindle"]:
		Art._draw_sword(pen, id == "gale_spindle")
	elif id == "return_mantle":
		Art._draw_mantle(pen)
	elif id in ["guardian_robe", "tidebound_coat"]:
		Art._draw_robe(pen, id == "tidebound_coat")
	elif id in ["vitality_armor", "woven_bastion"]:
		Art._draw_leather(pen, id == "woven_bastion")
	elif Jewels.BASES.has(id):
		Art._draw_jewel(pen, id)
	else:
		Art._draw_charm(pen, id)
	return pen

func run() -> void:
	var ids: Array[String] = []
	for id: String in Data.ITEMS:
		var entry: Dictionary = Data.ITEMS[id].duplicate(true)
		entry["id"] = id
		entries.append(entry)
		ids.append(id)
	for id: String in Gear.BASES.keys() + Gear.EXPANSION_BASES.keys():
		var entry: Dictionary = Gear.base_definition(id)
		entry["id"] = "gear_000100"
		entry["base_id"] = id
		entries.append(entry)
		# Also test raw base-only records used by previews/tools.
		entries.append({"base_id": id})
		ids.append(id)
	for id: String in Jewels.BASES:
		entries.append({"kind": "jewel", "base": id, "id": "jewel_000100"})
		ids.append(id)
	for slot: String in ["weapon", "armor", "charm"]:
		entries.append({"slot": slot, "id": "ember_wand" if slot == "weapon" else "guardian_robe" if slot == "armor" else "azure_charm", "color": Color("516477")})
	var calls: int = 0
	for id: String in ids:
		for dimensions: Vector2 in [Vector2(28, 91), Vector2(70, 91), Vector2(28, 28), Vector2(188, 240), Vector2(3, 3)]:
			var rect := Rect2(Vector2(13, 17), dimensions)
			var pen := fixture(id, rect)
			var duplicate := fixture(id, rect)
			check(pen.commands == duplicate.commands, "non-deterministic geometry: " + id)
			check(pen.commands.size() >= 8, "missing material detail: " + id)
			for command: Dictionary in pen.commands:
				calls += 1
				var stroke: float = float(command.width) * 0.5
				for point: Vector2 in command.points:
					check(point.is_finite(), "non-finite vertex: " + id)
					check(point.x - stroke >= rect.position.x and point.y - stroke >= rect.position.y and point.x + stroke <= rect.end.x and point.y + stroke <= rect.end.y, "stroke escaped supplied rect: " + id)
	check(fixture("runewood_focus", Rect2(0, 0, 28, 91)).commands != fixture("gale_spindle", Rect2(0, 0, 28, 91)).commands, "runewood focus incorrectly uses sword geometry")
	# Color/material changes survive subdued slot rendering; rendering itself is pure.
	var hint := fixture("ember_wand", Rect2(0, 0, 51, 57), true)
	check(hint.commands != fixture("ember_wand", Rect2(0, 0, 51, 57)).commands, "hint is not subdued")
	Art.draw_item(null, {}, Rect2(0, 0, 28, 28))
	var surface := DrawingSurface.new()
	surface.owner_test = self
	root.add_child(surface)
	for i: int in range(4):
		await process_frame
	check(passed_draw, "native CanvasItem draw callback did not execute")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var capture_index: int = args.find("--capture")
	if capture_index >= 0 and capture_index + 1 < args.size():
		if DisplayServer.get_name() == "headless":
			check(false, "--capture requires a real rendering backend")
		else:
			await capture_sheet(ids, args[capture_index + 1])
	surface.queue_free()
	if failures.is_empty():
		print("EQUIPMENT_ART_TEST_PASS: ", ids.size(), " silhouettes; ", entries.size(), " entry records; 9 target sizes; ", calls, " bounded primitives; deterministic geometry; inputs/global RNG unchanged. Actual pixels not verified by headless test.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)

class ContactSheet extends Node2D:
	var ids: Array[String] = []
	func _draw() -> void:
		var sheet_height: int = 84 + ceili(float(ids.size()) / 6.0) * 332
		draw_rect(Rect2(0, 0, 1800, sheet_height), Color("25251f"))
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(24, 32), "Original equipment art / v0.7", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("eee1c1"))
		draw_string(font, Vector2(24, 56), "Enlarged inspector + unscaled 42px inventory cells. Wood / forged metal / cloth / leather / cut stone.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b8ad91"))
		for index: int in range(ids.size()):
			var id: String = ids[index]
			var x: int = 12 + (index % 6) * 298
			var y: int = 74 + (index / 6) * 332
			draw_rect(Rect2(x, y, 286, 320), Color("34342a"))
			draw_rect(Rect2(x, y, 286, 320), Color("796c4c"), false, 1.0)
			draw_string(font, Vector2(x + 10, y + 23), id, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("d7c7a4"))
			var entry: Dictionary = {"id": id}
			var footprint := Vector2(42, 42)
			if Data.ITEMS.has(id):
				entry = Data.ITEMS[id].duplicate(true)
				entry["id"] = id
				footprint = Vector2(entry.size) * 42.0
			elif Gear.BASES.has(id) or Gear.EXPANSION_BASES.has(id):
				entry = Gear.base_definition(id)
				entry["id"] = "gear_000100"
				entry["base_id"] = id
				footprint = Vector2(entry.size) * 42.0
			else:
				entry = {"kind": "jewel", "base": id, "id": "jewel_000100"}
			Art.draw_item(self, entry, Rect2(x + 13, y + 42, 158, 238))
			var grid_box := Rect2(Vector2(x + 188, y + 99), footprint)
			for gy: int in range(int(footprint.y / 42.0)):
				for gx: int in range(int(footprint.x / 42.0)):
					var cell := Rect2(grid_box.position + Vector2(gx, gy) * 42.0, Vector2(42, 42))
					draw_rect(cell, Color("272b22"))
					draw_rect(cell, Color("6a6247"), false, 1.0)
			var icon_rect: Rect2 = grid_box.grow(-7.0)
			if footprint.y > 42.0:
				icon_rect.size.y -= 21.0
			Art.draw_item(self, entry, icon_rect)
			draw_string(font, Vector2(x + 186, y + 254), "42px cells", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("b8ad91"))
			draw_string(font, Vector2(x + 18, y + 302), "inspector", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("b8ad91"))

func capture_sheet(ids: Array[String], path: String) -> void:
	# Offscreen viewport makes the proof independent of the desktop window size.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1800, 84 + ceili(float(ids.size()) / 6.0) * 332)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sheet := ContactSheet.new()
	sheet.ids = ids
	viewport.add_child(sheet)
	for i: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	check(image != null and not image.is_empty(), "native capture returned no pixels")
	if image != null and not image.is_empty():
		check(image.save_png(path) == OK, "could not save native capture")
		print("EQUIPMENT_ART_NATIVE_CAPTURE ", path)
	viewport.queue_free()
