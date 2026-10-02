class_name EquipmentArt
extends RefCounted
## Original, material-led equipment art. Pure drawing: no gameplay/RNG/CanvasItem
## property changes. Coordinates are fitted per silhouette and bounded to rect.

const PainterlyArt = preload("res://scripts/visuals/equipment_painterly_art.gd")

const INK := Color("241f1b")
const BRASS := Color("b38a47")
const GOLD_LIGHT := Color("e0c58b")
const STEEL := Color("899497")
const STEEL_LIGHT := Color("d5d6c7")
const WOOD := Color("775032")
const WOOD_LIGHT := Color("be8c50")
const LEATHER := Color("784a31")
const THREAD := Color("bba27a")
const JEWEL_COLORS: Dictionary = {
	"emberheart": Color("bd654e"), "tideglass": Color("769ab8"), "windweave": Color("74a186"),
	"branchfinder": Color("c79853"),
}

## Mapping/stroke helpers deliberately do not use draw_set_transform or clipping
## state. Every vertex and stroke is contained in the supplied positive rectangle.
class Pen extends RefCounted:
	var canvas: CanvasItem
	var bounds: Rect2
	var center: Vector2
	var scale: float
	var subdued: bool

	func _init(target: CanvasItem, rect: Rect2, design: Vector2, is_hint: bool) -> void:
		canvas = target
		bounds = rect
		center = rect.get_center()
		scale = minf((rect.size.x - 2.0) / design.x, (rect.size.y - 2.0) / design.y)
		subdued = is_hint

	func tint(color: Color) -> Color:
		if not subdued:
			return color
		var gray: float = color.get_luminance()
		return Color("686052").lerp(Color(gray, gray, gray), 0.20).darkened(0.26)

	func mapped(values: Array, stroke: float = 0.0) -> PackedVector2Array:
		var result := PackedVector2Array()
		# Keep AA coverage inside rect too, without affecting neighboring grid cells.
		var margin: float = minf(stroke * 0.5 + 0.75, minf(bounds.size.x, bounds.size.y) * 0.48)
		var safe: Rect2 = bounds.grow(-margin)
		for i: int in range(0, values.size(), 2):
			var point := center + Vector2(float(values[i]), float(values[i + 1])) * scale
			result.append(Vector2(clampf(point.x, safe.position.x, safe.end.x), clampf(point.y, safe.position.y, safe.end.y)))
		return result

	func poly(values: Array, color: Color, outlined: bool = false, edge: Color = INK, width: float = 1.6) -> void:
		var stroke: float = width * scale if outlined else 0.0
		var points: PackedVector2Array = mapped(values, stroke)
		canvas.draw_colored_polygon(points, tint(color))
		if outlined:
			points.append(points[0])
			canvas.draw_polyline(points, tint(edge), stroke, true)

	func line(values: Array, color: Color, width: float = 1.2) -> void:
		var stroke: float = width * scale
		canvas.draw_polyline(mapped(values, stroke), tint(color), stroke, true)

	func oval(x: float, y: float, rx: float, ry: float, color: Color, outlined: bool = false) -> void:
		var values: Array = []
		for i: int in range(24):
			var angle: float = TAU * float(i) / 24.0
			values.append(x + cos(angle) * rx)
			values.append(y + sin(angle) * ry)
		poly(values, color, outlined)


static func draw_item(canvas: CanvasItem, entry: Dictionary, rect: Rect2) -> void:
	if canvas == null or not rect.has_area() or rect.size.x <= 2.0 or rect.size.y <= 2.0:
		return
	if not rect.position.is_finite() or not rect.size.is_finite():
		return
	if PainterlyArt.draw_item(canvas, entry, rect):
		return
	var id: String = str(entry.get("base_id", entry.get("id", "")))
	var slot: String = str(entry.get("slot", ""))
	if slot.is_empty():
		if id in ["ember_wand", "cinder_reed", "prism_bow", "swift_blade", "gale_spindle", "runewood_focus"]:
			slot = "weapon"
		elif id in ["guardian_robe", "tidebound_coat", "return_mantle", "vitality_armor", "woven_bastion", "emberhide_vest"]:
			slot = "armor"
		elif id in ["azure_charm", "storm_charm", "detonation_charm", "wayglass_token", "pulse_seed"]:
			slot = "charm"
	# Legacy empty equipment-slot records intentionally have no kind/name.
	var hint: bool = bool(entry.get("hint", false)) or bool(entry.get("empty", false))
	if entry.get("color", Color.WHITE) == Color("516477") and not entry.has("kind") and not entry.has("name"):
		hint = true
	if entry.get("kind", "") == "jewel" or JEWEL_COLORS.has(str(entry.get("base", ""))):
		_draw_jewel(Pen.new(canvas, rect, Vector2(80, 88), hint), str(entry.get("base", "")))
		return
	match slot:
		"weapon":
			if id == "prism_bow":
				_draw_bow(Pen.new(canvas, rect, Vector2(58, 154), hint))
			elif id == "runewood_focus" or str(entry.get("base_name", "")) == "符木法器":
				_draw_runewood_focus(Pen.new(canvas, rect, Vector2(48, 144), hint))
			elif id in ["ember_wand", "cinder_reed"] or str(entry.get("base_name", "")).ends_with("杖"):
				_draw_staff(Pen.new(canvas, rect, Vector2(46, 154), hint), id == "cinder_reed")
			else:
				_draw_sword(Pen.new(canvas, rect, Vector2(54, 154), hint), id == "gale_spindle")
		"armor":
			if id == "emberhide_vest":
				_draw_emberhide(Pen.new(canvas, rect, Vector2(114,130), hint))
			elif id == "return_mantle":
				_draw_mantle(Pen.new(canvas, rect, Vector2(114, 146), hint))
			elif id in ["guardian_robe", "tidebound_coat"] or str(entry.get("base_name", "")).ends_with("袍"):
				_draw_robe(Pen.new(canvas, rect, Vector2(116, 150), hint), id == "tidebound_coat")
			else:
				_draw_leather(Pen.new(canvas, rect, Vector2(114, 130), hint), id == "woven_bastion")
		"charm":
			_draw_charm(Pen.new(canvas, rect, Vector2(84, 94), hint), id)
		_:
			_draw_charm(Pen.new(canvas, rect, Vector2(84, 94), hint), "wayglass_token")


static func _draw_staff(p: Pen, reed: bool) -> void:
	# A crooked carved haft with ferrule, leather wrap, and a physically held stone.
	p.poly([-9, 70, -5, 28, -3, -12, 2, -41, 9, -43, 5, -9, 2, 28, -2, 71], WOOD, true)
	p.poly([-8, 66, -5, 28, -3, -10, 2, -37, 4, -33, 0, -4, -2, 30, -5, 68], WOOD_LIGHT)
	p.line([-3, 59, -1, 25, 1, 3, 2, -15], Color("4b3225"), 1.2)
	p.poly([-10, 64, -2, 65, -2, 71, -8, 73, -11, 70], STEEL, true)
	p.line([-9, 66, -3, 67], STEEL_LIGHT)
	p.poly([-6, 12, 2, 13, 1, 33, -7, 32], LEATHER, true)
	for y: int in range(14, 33, 4):
		p.line([-6, y, 1, y + 2], THREAD, 1.0)
	if reed:
		p.poly([-4, -37, -16, -48, -18, -63, -12, -70, -11, -55, -2, -47, 7, -48, 13, -62, 18, -68, 18, -53, 11, -40, 4, -35], WOOD, true)
		p.line([-12, -65, -12, -54, -3, -43, 7, -43, 14, -54], WOOD_LIGHT, 2.0)
		p.poly([-8, -60, -2, -73, 6, -69, 10, -57, 3, -46, -5, -47], Color("b16a43"), true)
		p.poly([-8, -60, -2, -73, 0, -59, -5, -47], Color("e0ae70"))
		p.poly([0, -59, 6, -69, 10, -57, 3, -46], Color("874d3e"))
		p.line([-5, -40, 8, -38, 7, -34, -5, -35], THREAD, 2.2)
	else:
		p.poly([-3, -35, -17, -46, -18, -60, -13, -62, -10, -48, 0, -42, 12, -50, 15, -64, 19, -59, 17, -43, 5, -34], BRASS, true)
		p.poly([-10, -62, -1, -74, 10, -66, 10, -53, 0, -43, -11, -54], Color("b66146"), true)
		p.poly([-10, -62, -1, -74, 1, -58, -11, -54], Color("ecc18a"))
		p.poly([-1, -74, 10, -66, 1, -58], Color("d7965b"))
		p.poly([1, -58, 10, -66, 10, -53, 0, -43], Color("854433"))
		p.poly([-11, -54, 1, -58, 0, -43], Color("d18250"))
		p.line([-15, -57, -12, -46, -2, -39], GOLD_LIGHT, 1.5)
		p.poly([-4, -35, 8, -35, 7, -29, -4, -29], BRASS, true)
		p.line([-2, -32, 6, -32], GOLD_LIGHT)
	# Small cut marks read as wood grain in an enlarged inspector, not sparkles.
	p.line([-4, 44, -2, 40, -3, 37], Color("ddba7b"), 0.9)


static func _draw_runewood_focus(p: Pen) -> void:
	# A modest carved branch focus: broad wooden head, incised rune and dark
	# stone pin. Its material silhouette is distinct from both gem staves/blades.
	p.poly([-7, 66, -9, 34, -5, 4, -8, -29, -3, -37, 5, -34, 7, 0, 3, 36, 5, 64, 0, 69], WOOD, true)
	p.poly([-7, 62, -6, 32, -2, 3, -5, -27, -1, -31, 2, 1, 0, 35, 1, 65], WOOD_LIGHT)
	p.line([3, -22, 4, 1, 0, 25, 2, 51], Color("4f3829"), 1.2)
	p.poly([-7, -25, -17, -35, -20, -51, -14, -65, -3, -70, 11, -66, 18, -55, 19, -41, 11, -29, 4, -23], Color("87603b"), true)
	p.poly([-14, -62, -5, -67, -9, -52, -7, -36, -1, -26, -10, -32, -17, -48], Color("bc9258"))
	p.poly([-5, -64, 7, -61, 13, -52, 13, -42, 5, -32, -5, -35, -9, -47], Color("a77b46"), true, Color("5d422b"), 1.3)
	p.line([-15, -46, -13, -37, -7, -30], Color("d4b277"), 1.2)
	p.line([12, -60, 15, -50, 14, -41, 8, -34], Color("563e2b"), 1.5)
	# The restrained fork-like mark is carved into the wood, without emitted light.
	p.line([0, -57, 0, -40, 6, -44], Color("533d2c"), 3.1)
	p.line([-6, -51, 0, -47, 7, -53], Color("533d2c"), 3.1)
	p.line([-1, -57, -1, -40, 5, -44], Color("cfad73"), 1.0)
	p.line([-6, -52, -1, -48, 6, -54], Color("cfad73"), 1.0)
	p.poly([-7, -29, 6, -28, 7, -21, -6, -22], BRASS, true)
	p.line([-5, -27, 5, -26], GOLD_LIGHT, 1.1)
	p.oval(0, -25, 2.0, 2.0, Color("527261"), true)
	p.poly([-6, 12, 5, 13, 3, 35, -8, 34], Color("4f382a"), true)
	for y: int in range(14, 34, 4):
		p.line([-6, y, 4, y + 2], Color("aa8659"), 1.4)
	p.line([-4, 40, -2, 51, -3, 57], Color("d3ac70"), 1.0)
	p.poly([-6, 61, 4, 60, 5, 65, 0, 70, -6, 66], Color("796b50"), true)
	p.line([-5, 63, 3, 63], Color("bab291"), 1.4)


static func _draw_bow(p: Pen) -> void:
	# Recurve profile: asymmetric antler nocks, laminated wooden limbs and taut string.
	# No crossbow-like crossbar/arrow: the silhouette remains a true vertical bow.
	p.line([-12, -71, -20, 0, -12, 71], Color("e2d4ac"), 1.25)
	p.poly([-13, -73, -5, -67, -5, -54, 6, -41, 18, -26, 23, -9, 24, 7, 20, 25, 8, 42, -5, 56, -5, 66, -13, 73, -9, 62, -11, 54, 0, 36, 10, 21, 14, 6, 13, -8, 9, -23, -2, -39, -11, -54, -9, -64], WOOD, true)
	p.line([-10, -69, -7, -57, 0, -44, 12, -27, 18, -9, 19, 7, 14, 25, 3, 42, -7, 57, -9, 68], WOOD_LIGHT, 2.6)
	p.line([-6, -53, 5, -37, 13, -25, 17, -11], Color("dbb97d"), 1.0)
	p.line([17, 12, 11, 29, 0, 45], Color("553b2b"), 1.4)
	p.poly([13, -12, 24, -10, 24, 11, 13, 13, 15, 0], Color("4f3929"), true)
	for y: int in range(-9, 13, 4):
		p.line([14, y + 1, 23, y - 1], Color("a98255"), 1.35)
	p.poly([-13, -74, -6, -69, -5, -60, -9, -59, -10, -67], Color("b9b299"), true)
	p.poly([-8, 60, -4, 62, -5, 69, -13, 74, -10, 66], Color("b9b299"), true)
	p.poly([3, -39, 9, -34, 13, -28, 9, -26, 3, -33], BRASS, true)
	p.poly([11, 29, 7, 36, 2, 42, -1, 37, 6, 28], BRASS, true)
	p.poly([7, -35, 10, -31, 8, -28, 5, -32], Color("749584"))
	p.line([-11, -70, -14, -67], THREAD, 1.6)
	p.line([-12, 70, -15, 66], THREAD, 1.6)


static func _draw_sword(p: Pen, spindle: bool) -> void:
	# A forged blade with a central ridge, nicked cutting edge and wrapped tang.
	if spindle:
		p.poly([7, -73, 17, -54, 12, -31, 7, -7, 4, 32, -8, 33, -8, 8, -4, -20, 0, -48], STEEL, true)
		p.poly([7, -73, 8, -45, 1, -5, -1, 31, -8, 33, -8, 8, -4, -20, 0, -48], STEEL_LIGHT)
		p.poly([8, -45, 17, -54, 12, -31, 7, -7, 4, 32, -1, 31, 1, -5], Color("657777"))
		p.line([7, -62, 4, -28, 0, -5, -2, 25], Color("eee9cd"), 1.1)
	else:
		p.poly([8, -74, 17, -51, 10, 22, 4, 33, -8, 31, -9, 18, -5, -48], STEEL, true)
		p.poly([8, -74, 5, -44, 0, 29, -8, 31, -9, 18, -5, -48], STEEL_LIGHT)
		p.poly([8, -74, 17, -51, 10, 22, 4, 33, 0, 29, 5, -44], Color("748386"))
		p.line([7, -63, 3, -20, 0, 23], Color("f0ead6"), 1.2)
		p.line([12, -22, 8, -19, 12, -18], Color("4d6064"), 1.2)
	p.poly([-23, 29, -11, 27, -2, 31, 9, 29, 24, 26, 22, 34, 8, 37, -4, 36, -16, 34, -23, 36], BRASS, true)
	p.line([-21, 30, -12, 29, -3, 33, 9, 31, 22, 28], GOLD_LIGHT, 1.3)
	p.poly([-7, 37, 4, 38, 2, 62, -8, 62], Color("54362a"), true)
	for y: int in range(39, 61, 4):
		p.line([-7, y, 3, y + 2], Color("a17448"), 1.6)
	p.poly([-9, 62, 2, 62, 6, 67, -2, 74, -12, 68], BRASS, true)
	p.poly([-9, 63, -2, 64, -2, 71, -9, 68], GOLD_LIGHT)
	p.oval(-2, 33, 4, 3, Color("537667"), true)


static func _draw_robe(p: Pen, tide: bool) -> void:
	var cloth := Color("557291") if not tide else Color("667c76")
	var light := Color("859ab0") if not tide else Color("99aba0")
	var shade := Color("35465e") if not tide else Color("43584f")
	# Long sleeves, turned collar, belted waist, weighted skirt and stitched hem.
	p.poly([-15, -68, -35, -59, -54, -23, -39, -15, -29, -34, -26, -7, -38, 64, -22, 70, -5, 68, 7, 72, 33, 64, 25, -7, 28, -34, 40, -15, 54, -23, 36, -59, 16, -68], cloth, true)
	p.poly([-35, -57, -52, -24, -41, -19, -29, -39, -25, -49], shade)
	p.poly([34, -55, 50, -24, 42, -20, 29, -42, 26, -48], light)
	p.poly([-20, -5, -34, 63, -23, 67, -12, 17, -10, -5], shade)
	p.poly([8, -5, 6, 69, 20, 66, 17, 20, 15, -5], light)
	p.poly([20, 3, 30, 61, 23, 63, 16, 20], shade)
	p.poly([-14, -67, 0, -52, 15, -67, 12, -45, 1, -33, -12, -45], Color("c9bea0"), true)
	p.poly([-8, -59, 0, -52, 8, -60, 4, -47, 0, -42, -4, -47], Color("282e32"))
	p.line([-12, -65, -13, -49, 0, -34, 13, -49, 14, -65], GOLD_LIGHT, 1.3)
	p.line([0, -33, -1, -6, -6, 63], Color("c3b186"), 2.5)
	p.line([-5, 11, -10, 49, -13, 62], light, 1.4)
	p.line([-26, -38, -22, -13], light, 1.0)
	p.poly([-25, -9, 24, -9, 25, -1, -26, -1], Color("614832"), true)
	p.poly([-6, -10, 5, -10, 5, 0, -6, 0], BRASS, true)
	p.poly([-3, -7, 2, -7, 2, -3, -3, -3], Color("3f3326"))
	p.poly([7, 0, 14, 0, 16, 21, 11, 26, 8, 20], Color("80603b"), true)
	p.line([-37, 62, -22, 67, -5, 65, 7, 69, 31, 62], Color("bda778"), 2.5)
	for x: int in range(-27, 29, 8):
		p.line([x, 62, x + 1, 65], THREAD, 0.9)
	p.line([-52, -25, -40, -19], GOLD_LIGHT, 2.0)
	p.line([42, -20, 51, -25], GOLD_LIGHT, 2.0)
	if tide:
		p.line([13, 43, 18, 39, 22, 44, 26, 40], Color("c1c7ad"), 1.8)
	else:
		p.poly([10, -32, 16, -35, 20, -31, 18, -23, 14, -20, 10, -25], BRASS, true)
		p.line([14, -32, 14, -24, 18, -29], GOLD_LIGHT, 1.0)


static func _draw_mantle(p: Pen) -> void:
	# A hooded travelling cloak: open split front, linen lining and a clasp.
	p.poly([-16, -51, -34, -44, -45, -8, -53, 39, -45, 66, -25, 62, -8, 69, 6, 65, 23, 69, 49, 59, 52, 38, 40, -15, 29, -45, 15, -52], Color("586e58"), true)
	p.poly([-12, -44, -6, 12, -14, 63, -25, 59, -30, 31, -21, -20], Color("8f9c75"))
	p.poly([6, -43, 23, -16, 29, 34, 22, 64, 7, 61, -2, 13], Color("344b3a"))
	p.poly([-8, -38, -3, 15, -8, 62, 5, 59, 12, 20, 8, -35], Color("b6a27d"), true)
	p.line([-6, -28, 2, 19, -2, 51], Color("e0cda3"), 2.0)
	p.poly([-16, -51, -18, -61, -8, -71, 8, -71, 20, -60, 19, -45, 8, -34, -6, -35], Color("78906f"), true)
	p.poly([-11, -56, -4, -65, 6, -64, 12, -55, 9, -41, -5, -41], Color("263b30"), true)
	p.poly([-11, -56, -4, -65, -6, -46, -5, -41, -13, -47], Color("afab80"))
	p.line([8, -66, 16, -58, 16, -48, 8, -38], Color("a9b38b"), 1.7)
	p.poly([-31, -43, -17, -46, -10, -38, -24, -28, -40, -27], Color("849574"), true)
	p.poly([17, -45, 30, -39, 37, -24, 21, -28, 9, -37], Color("6d805e"), true)
	p.line([-24, -34, -9, -30, 8, -30, 23, -34], BRASS, 2.7)
	p.oval(0, -30, 6, 5, BRASS, true)
	p.poly([0, -34, 3, -30, 0, -26, -3, -30], Color("ac6950"))
	p.line([-34, -17, -40, 23, -36, 48], Color("a0ae88"), 2.0)
	p.line([-24, -5, -29, 30, -25, 52], Color("344b3a"), 2.7)
	p.line([28, -11, 39, 24, 41, 48], Color("9aa57f"), 1.6)
	p.line([17, 10, 24, 39, 22, 56], Color("a7ad83"), 1.4)
	p.line([-45, 60, -25, 57, -10, 64], THREAD, 1.5)
	p.line([24, 63, 44, 55, 47, 40], THREAD, 1.5)
	# Quiet embroidered returning-wing motif, an object detail rather than an effect.
	p.line([30, 40, 34, 33, 30, 28, 31, 34, 25, 32], Color("c4b987"), 1.5)


static func _draw_leather(p: Pen, woven: bool) -> void:
	var hide := Color("8a6141") if not woven else Color("7e7151")
	var shade := Color("503b2b") if not woven else Color("4d4938")
	var light := Color("b58d5c") if not woven else Color("a7976c")
	# Fitted cuirass with actual armholes, overlapping skirt, straps and fasteners.
	p.poly([-16, -58, -34, -51, -47, -35, -40, -18, -30, -20, -25, 7, -31, 47, -17, 57, 0, 53, 17, 57, 32, 47, 25, 6, 31, -20, 41, -18, 48, -35, 34, -51, 16, -58, 11, -46, -10, -46], hide, true)
	p.poly([-32, -50, -43, -35, -37, -23, -30, -25, -22, -43], shade)
	p.poly([32, -50, 43, -35, 37, -23, 29, -25, 21, -44], shade)
	p.poly([-16, -49, -24, -38, -20, -3, -3, 5, -4, -40], light, true)
	p.poly([5, -41, 17, -50, 25, -38, 20, -4, 4, 5], hide, true)
	p.poly([-21, 12, -27, 43, -15, 51, -4, 44, -4, 15], hide, true)
	p.poly([3, 15, 5, 44, 16, 52, 28, 44, 22, 12], shade, true)
	p.poly([-2, 19, 10, 15, 17, 44, 4, 51, -7, 44], hide, true)
	p.line([-19, 19, -22, 41, -14, 46], light, 1.4)
	p.line([12, 20, 19, 41], light, 1.5)
	p.poly([-26, 3, 25, 3, 27, 13, -27, 13], Color("4f3526"), true)
	p.poly([-6, 2, 7, 2, 7, 14, -6, 14], BRASS, true)
	p.poly([-3, 5, 4, 5, 4, 11, -3, 11], Color("413527"))
	p.line([-1, 5, -1, 11, 5, 8], GOLD_LIGHT, 1.2)
	p.poly([-23, -55, -14, -56, 17, -6, 10, -3], Color("5b3c2b"), true)
	p.line([-18, -50, 12, -5], Color("c3a171"), 1.2)
	p.poly([-39, -43, -30, -51, -21, -48, -25, -32, -40, -29, -47, -34], STEEL, true)
	p.poly([24, -49, 33, -49, 46, -36, 40, -29, 27, -32], Color("65716b"), true)
	p.line([-43, -35, -28, -38, -24, -46], STEEL_LIGHT, 1.5)
	p.line([27, -46, 30, -36, 40, -33], Color("adb4a3"), 1.2)
	for y: int in range(-31, -3, 6):
		p.line([-22, y, -19, y - 1], THREAD, 1.0)
		p.line([19, y, 22, y - 1], THREAD, 1.0)
	for x: int in [-35, -27, 30, 38]:
		p.oval(float(x), -36.0, 1.4, 1.4, GOLD_LIGHT)
	if woven:
		for y: int in range(-27, -8, 6):
			p.line([-14, y, -10, y + 3, -6, y], THREAD, 1.8)
		p.line([10, -27, 15, -24, 12, -19], THREAD, 1.8)
	else:
		p.line([-12, -23, -8, -27, -8, -19], Color("ddbd82"), 1.5)
		p.line([9, -30, 14, -28], light, 1.2)


static func _draw_emberhide(p: Pen) -> void:
	# Sleeveless warm hide, overlapping skirts, ash-stone shoulders and a sewn ward.
	p.poly([-16,-58,-35,-51,-45,-31,-32,-16,-24,-21,-22,5,-30,46,-16,58,0,50,17,58,30,46,22,5,25,-21,32,-16,46,-32,34,-51,16,-58,10,-45,-10,-45],Color("995f3f"),true)
	p.poly([-15,-43,-23,-24,-18,-2,-4,5,-3,-42],Color("c68c58"),true)
	p.poly([4,-42,16,-43,23,-23,18,-3,5,5],Color("805036"),true)
	p.poly([-26,14,-29,44,-16,53,-5,43,-4,17],Color("b87949"),true)
	p.poly([4,17,7,44,16,53,29,43,24,13],Color("775039"),true)
	p.line([-20,21,-22,42,-15,47],THREAD,1.5)
	p.line([17,23,21,43],THREAD,1.5)
	for side: int in [-1,1]:
		p.poly([side*21,-51,side*34,-49,side*45,-33,side*38,-24,side*26,-29,side*18,-40],Color("7d8172"),true)
		p.line([side*23,-43,side*29,-33,side*38,-30],Color("b4b7a0"),1.5)
		p.line([side*20,-26,side*17,-7],Color("d1a36d"),1.3)
	p.poly([-27,3,27,3,26,14,-27,14],Color("503827"),true)
	p.poly([-6,3,7,3,7,14,-6,14],BRASS,true)
	p.poly([-3,6,4,6,4,11,-3,11],INK)
	p.poly([-11,-35,11,-35,10,-14,0,-7,-10,-14],Color("554e3d"),true,BRASS,1.8)
	p.poly([0,-31,6,-22,5,-16,0,-12,-6,-16,-7,-23,-2,-20],Color("d5a365"),true,Color("8b5936"),1.1)
	p.line([-14,-40,-16,-30],THREAD,1.1)
	p.line([15,-39,18,-30],THREAD,1.1)

static func _draw_charm(p: Pen, id: String) -> void:
	# Closed leather thong is attached to a metal bail, not a floating UI ring.
	p.line([-4, -6, -15, -18, -17, -30, -11, -40, 0, -44, 12, -39, 17, -28, 13, -16, 5, -5], Color("34271f"), 4.6)
	p.line([-4, -7, -14, -19, -15, -30, -10, -38, 0, -41, 11, -37, 15, -28, 11, -17, 5, -6], Color("b08c57"), 1.8)
	p.oval(0, -7, 5, 7, BRASS, true)
	p.oval(0, -8, 2.4, 3.8, INK)
	match id:
		"pulse_seed":
			p.poly([0, -4, 16, 2, 23, 18, 17, 34, 2, 44, -17, 34, -22, 19, -15, 4], Color("6c724a"), true)
			p.poly([-1, 1, 10, 9, 12, 26, 0, 38, -11, 25, -10, 10], Color("b38d56"), true)
			p.poly([-1, 1, -3, 23, 0, 38, -11, 25, -10, 10], Color("e1c38b"))
			p.line([-16, 9, -16, 24, -7, 34], Color("a6b184"), 1.7)
			p.line([17, 13, 9, 20, 17, 26], Color("c4c29a"), 1.3)
		"detonation_charm":
			p.poly([-6, -4, 6, -4, 9, 2, 23, 8, 26, 24, 14, 38, 0, 45, -16, 36, -25, 20, -21, 7, -9, 2], BRASS, true)
			p.poly([0, 2, 16, 11, 17, 26, 0, 38, -16, 25, -17, 11], Color("a75238"), true)
			p.poly([0, 2, 1, 19, -16, 25, -17, 11], Color("e1a065"))
			p.poly([0, 2, 16, 11, 1, 19], Color("f0c68c"))
			p.poly([1, 19, 17, 26, 0, 38], Color("783a2d"))
			p.line([-19, 10, -20, 20, -11, 33], GOLD_LIGHT, 1.7)
			p.poly([-3, -1, 4, -1, 4, 7, -3, 7], BRASS, true)
			p.poly([-4, 33, 4, 33, 4, 41, -4, 41], BRASS, true)
		"storm_charm":
			p.poly([0, -5, 24, 7, 22, 28, 0, 44, -22, 28, -24, 7], Color("857660"), true)
			p.poly([0, 2, 16, 10, 15, 25, 0, 35, -16, 24, -17, 10], Color("b6a464"), true)
			p.poly([0, 2, -2, 18, -16, 24, -17, 10], Color("e3d5a0"))
			p.poly([-2, 18, 16, 10, 15, 25, 0, 35], Color("80724f"))
			p.line([6, 8, -5, 19, 4, 18, -5, 30], Color("efe4bd"), 2.5)
			p.line([-19, 10, -18, 26, -3, 38], STEEL_LIGHT, 1.5)
		"wayglass_token":
			p.poly([-14, -3, 14, -3, 24, 7, 24, 31, 14, 42, -14, 42, -24, 31, -24, 7], BRASS, true)
			p.poly([-11, 4, 11, 4, 17, 11, 17, 27, 9, 34, -9, 34, -17, 27, -17, 11], Color("5f8271"), true)
			p.poly([-11, 4, 11, 4, -5, 17, -17, 27, -17, 11], Color("acc7ac"))
			p.poly([-5, 17, 17, 11, 17, 27, 9, 34, -9, 34], Color("496654"))
			p.line([-12, 7, -14, 14], Color("e3e1bf"), 1.6)
			p.line([-20, 7, -20, 30, -13, 37], GOLD_LIGHT, 1.7)
			p.line([17, 4, 20, 9], Color("77583a"), 1.3)
		_:
			p.poly([0, -5, 14, 4, 24, 20, 17, 33, 0, 45, -17, 33, -24, 20, -14, 4], BRASS, true)
			p.poly([0, 2, 15, 19, 10, 31, 0, 37, -12, 29, -16, 18], Color("547a9b"), true)
			p.poly([0, 2, 0, 18, -12, 29, -16, 18], Color("b0c9ca"))
			p.poly([0, 18, 15, 19, 10, 31, 0, 37], Color("39526e"))
			p.poly([0, 2, 15, 19, 0, 18], Color("8eaebc"))
			p.line([-17, 12, -20, 21, -12, 33], GOLD_LIGHT, 1.6)
			p.poly([-4, -1, 4, -1, 3, 7, -3, 7], BRASS, true)
			p.poly([-3, 36, 3, 36, 3, 42, -3, 42], BRASS, true)


static func _draw_jewel(p: Pen, base: String) -> void:
	var color: Color = JEWEL_COLORS.get(base, Color("927b9e"))
	# The three catalog bases have different cuts, not only a rarity tint.
	match base:
		"branchfinder":
			_draw_branchfinder(p)
		"emberheart":
			p.poly([-15, -33, 12, -34, 32, -13, 29, 13, 0, 40, -29, 15, -33, -11], color.darkened(0.18), true)
			p.poly([-15, -33, 12, -34, 16, -10, -14, -10], color.lightened(0.36))
			p.poly([-33, -11, -15, -33, -14, -10, -15, 11, -29, 15], color.lightened(0.08))
			p.poly([12, -34, 32, -13, 29, 13, 15, 11, 16, -10], color.darkened(0.24))
			p.poly([-14, -10, 16, -10, 15, 11, 0, 22, -15, 11], color)
			p.poly([-29, 15, -15, 11, 0, 22, 0, 40], color.lightened(0.20))
			p.poly([15, 11, 29, 13, 0, 40, 0, 22], color.darkened(0.38))
			p.line([-14, -10, 16, -10, 15, 11, 0, 22, -15, 11, -14, -10], color.lightened(0.42), 1.0)
			p.line([-14, -28, 4, -29], Color("f0d2a8"), 1.5)
		"windweave":
			p.poly([0, -41, 18, -28, 31, 0, 17, 28, 0, 41, -19, 27, -32, 0, -18, -28], color.darkened(0.10), true)
			p.poly([0, -41, 0, -23, -15, 0, -32, 0, -18, -28], color.lightened(0.29))
			p.poly([0, -41, 18, -28, 31, 0, 13, 0, 0, -23], color.lightened(0.09))
			p.poly([-15, 0, 0, -23, 13, 0, 0, 25], color)
			p.poly([-32, 0, -15, 0, 0, 25, 0, 41, -19, 27], color.darkened(0.18))
			p.poly([13, 0, 31, 0, 17, 28, 0, 41, 0, 25], color.darkened(0.39))
			p.line([0, -23, -15, 0, 0, 25, 13, 0, 0, -23], color.lightened(0.38), 1.2)
			p.line([-14, -22, -23, -3], Color("dbe3bc"), 1.6)
		_:
			# Tideglass is an eight-sided step cut with a broad reflective table.
			p.poly([-18, -34, 18, -34, 32, -20, 32, 20, 18, 34, -18, 34, -32, 20, -32, -20], color, true)
			p.poly([-18, -34, 18, -34, 12, -23, -12, -23, -22, -13, -32, -20], color.lightened(0.44))
			p.poly([-32, -20, -22, -13, -22, 13, -12, 23, -18, 34, -32, 20], color.lightened(0.15))
			p.poly([18, -34, 32, -20, 32, 20, 18, 34, 12, 23, 22, 13, 22, -13, 12, -23], color.darkened(0.23))
			p.poly([-18, 34, -12, 23, 12, 23, 18, 34], color.darkened(0.36))
			p.poly([-12, -23, 12, -23, 22, -13, 22, 13, 12, 23, -12, 23, -22, 13, -22, -13], color.darkened(0.05))
			p.poly([-12, -23, 12, -23, -22, 13, -22, -13], color.lightened(0.20))
			p.line([-12, -23, 12, -23, 22, -13, 22, 13, 12, 23, -12, 23, -22, 13, -22, -13, -12, -23], color.lightened(0.41), 1.1)
			p.line([-16, -29, 7, -29], Color("e3e7d5"), 1.6)


static func _draw_branchfinder(p: Pen) -> void:
	# A rooted amber prism with two green branches. Broad facets and the forked
	# silhouette remain readable at a 28px inventory size without emitted glow.
	p.poly([-15, 28, -22, 14, -31, 8, -36, -10, -30, -13, -26, 2, -16, 10, -8, 24, 1, 34, 15, 25, 25, 8, 32, 5, 29, 19, 20, 32, 3, 41, -8, 39], WOOD, true)
	p.line([-31, -8, -28, 5, -18, 13, -12, 28, 1, 38, 18, 29, 28, 14], WOOD_LIGHT, 2.3)
	p.line([-15, 21, -9, 31, 2, 37, 13, 31], Color("4d3828"), 1.6)
	# Two unequal crystal shoots separate the special base from round-cut gems.
	p.poly([-9, 13, -26, -2, -31, -25, -24, -35, -10, -25, -1, -4], Color("557663"), true)
	p.poly([-31, -25, -24, -35, -22, -15, -9, 13, -26, -2], Color("a2b98a"))
	p.poly([-24, -35, -10, -25, -9, -12, -22, -15], Color("749665"))
	p.poly([-22, -15, -9, -12, -1, -4, -9, 13], Color("355749"))
	p.line([-26, -27, -23, -16, -16, -5], Color("d7d7a5"), 1.4)
	p.poly([2, 12, 6, -10, 23, -30, 33, -25, 31, -7, 20, 10], Color("75955f"), true)
	p.poly([6, -10, 23, -30, 22, -11, 2, 12], Color("c0c591"))
	p.poly([23, -30, 33, -25, 22, -11], Color("e0d29a"))
	p.poly([22, -11, 33, -25, 31, -7, 20, 10, 2, 12], Color("4d714f"))
	p.line([25, -22, 25, -11, 18, 0], Color("99b779"), 1.2)
	# Central amber table: the warm fork visible within the stone is an inclusion.
	p.poly([-9, -32, 0, -41, 12, -30, 17, 2, 8, 28, -2, 35, -14, 18, -15, -5], Color("b87d3d"), true)
	p.poly([-9, -32, 0, -41, 0, -18, -7, 5, -14, 18, -15, -5], Color("e2bd75"))
	p.poly([0, -41, 12, -30, 7, -15, 0, -18], Color("f0dba0"))
	p.poly([12, -30, 17, 2, 8, 28, 4, 9, 7, -15], Color("88602e"))
	p.poly([0, -18, 7, -15, 4, 9, -2, 24, -7, 5], Color("cf9e50"))
	p.poly([-14, 18, -7, 5, -2, 24, -2, 35], Color("efc578"))
	p.poly([4, 9, 8, 28, -2, 35, -2, 24], Color("755830"))
	p.line([-2, 17, 0, 1, -5, -7], Color("737143"), 2.0)
	p.line([0, 2, 5, -5], Color("737143"), 1.8)
	p.line([-9, -25, -11, -8], Color("fff0bc"), 1.8)
	# Bronze root clasp is physical, restrained and distinct from a rarity frame.
	p.poly([-15, 17, -10, 13, -5, 24, 4, 28, 13, 18, 17, 21, 8, 34, -2, 38, -10, 29], BRASS, true)
	p.line([-11, 18, -6, 27, 1, 33, 8, 30, 13, 24], GOLD_LIGHT, 1.8)
	p.oval(0, 32, 2.4, 2.4, Color("51705b"), true)
