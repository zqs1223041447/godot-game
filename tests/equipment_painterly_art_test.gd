extends SceneTree
## Headless-safe renderer contract; --require-all requires the complete 22 PNGs.
## Native pixel/readability QA is separate from these resource and geometry checks.
const Art = preload("res://scripts/visuals/equipment_art.gd")
const Painterly = preload("res://scripts/visuals/equipment_painterly_art.gd")
const Data = preload("res://scripts/game_data.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
var failures: Array[String] = []
var checks: int = 0
var entries: Array[Dictionary] = []
var available: int = 0
var drew: bool = false

class DrawingSurface extends Node2D:
	var suite: SceneTree
	func _draw() -> void:
		var original_transform: Transform2D = transform
		var original_modulate: Color = modulate
		var original_clip: int = clip_children
		seed(82647)
		var expected_random: int = randi()
		seed(82647)
		for entry: Dictionary in suite.entries:
			var original: Dictionary = entry.duplicate(true)
			for dimensions: Vector2 in [Vector2(28,91), Vector2(70,91), Vector2(28,28), Vector2(42,42), Vector2(108,108), Vector2(3,3)]:
				var bounds := Rect2(Vector2(13,17), dimensions)
				var rendered: bool = Painterly.draw_item(self, entry, bounds)
				suite.expect(rendered == (Painterly.texture_for_entry(entry) != null), "texture dispatch: " + str(entry))
				Art.draw_item(self, entry, bounds)
			suite.expect(original == entry, "drawing mutated entry")
		for entry: Dictionary in [{}, {"id":"missing"}, {"kind":"jewel", "base":"missing"}, {"id":"prism_bow", "hint":true}, {"id":"guardian_robe", "empty":true}, {"slot":"weapon", "id":"ember_wand", "color":Color("516477")}]:
			suite.expect(not Painterly.draw_item(self, entry, Rect2(0,0,42,42)), "fallback must not draw a texture")
			Art.draw_item(self, entry, Rect2(0,0,42,42))
		for bounds: Rect2 in [Rect2(), Rect2(0,0,-4,5), Rect2(0,0,2,2), Rect2(Vector2(INF,0),Vector2(42,42)), Rect2(Vector2.ZERO,Vector2(NAN,42))]:
			suite.expect(not Painterly.draw_item(self, {"id":"prism_bow"}, bounds), "invalid bounds accepted")
			Art.draw_item(self, {"id":"prism_bow"}, bounds)
		suite.expect(randi() == expected_random, "renderer consumed global RNG")
		suite.expect(transform == original_transform and modulate == original_modulate and clip_children == original_clip, "renderer changed CanvasItem state")
		suite.drew = true

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func test_alpha_bounds() -> void:
	var image := Image.create(20,30,false,Image.FORMAT_RGBA8)
	image.fill(Color(1,1,1,20.0/255.0))
	image.fill_rect(Rect2i(5,7,8,16), Color(0.7,0.4,0.2,1))
	var before: PackedByteArray = image.get_data()
	expect(Painterly.alpha_bounds(image) == Rect2(5,7,8,16), "faint alpha fringe must not shrink the object")
	expect(image.get_data() == before, "alpha measurement mutated image pixels")
	image.set_pixel(2,3,Color(1,1,1,21.0/255.0))
	expect(Painterly.alpha_bounds(image) == Rect2(2,3,11,20), "alpha threshold must preserve visible outer pixels")
	image.fill(Color.TRANSPARENT)
	expect(not Painterly.alpha_bounds(image).has_area(), "transparent image must fall back")
	expect(not Painterly.alpha_bounds(null).has_area(), "null image must fall back")
	var rgb := Image.create(6,9,false,Image.FORMAT_RGB8)
	rgb.fill(Color.WHITE)
	expect(Painterly.alpha_bounds(rgb) == Rect2(0,0,6,9), "RGB source conversion")
	expect(rgb.get_format() == Image.FORMAT_RGB8, "alpha measurement mutated source format")

func test_identity() -> void:
	expect(Painterly.canonical_id({"id":"gear_000522", "base_id":"ashwood_bow"}) == "ashwood_bow", "ashwood bow instance must use canonical base_id")
	expect(Painterly.resource_path({"id":"ashwood_bow"}) == "res://assets/art/equipment/ashwood_bow.png", "ashwood bow raw base must use its own art")
	expect(Painterly.canonical_id({"id":"gear_000521", "base_id":"runewood_focus"}) == "runewood_focus", "generated gear must use base_id")
	expect(Painterly.canonical_id({"id":"prism_bow", "base_id":"cinder_reed"}) == "cinder_reed", "base_id takes precedence")
	expect(Painterly.canonical_id({"id":"prism_bow", "base_id":""}) == "prism_bow", "empty base_id falls back to static id")
	expect(Painterly.canonical_id({"id":"prism_bow", "base_id":"unknown"}) == "prism_bow", "unrecognized base_id falls back to static id")
	expect(Painterly.canonical_id({"id":"jewel_000521", "base":"branchfinder"}) == "branchfinder", "raw jewel uses base")
	expect(Painterly.canonical_id({"kind":"jewel", "base":"tideglass", "id":"prism_bow"}) == "tideglass", "jewel identity takes precedence")
	for entry: Dictionary in [{}, {"id":"../prism_bow"}, {"id":"gear_000521"}, {"base_id":"unknown"}, {"kind":"jewel", "base":"unknown", "id":"prism_bow"}, {"base":"emberheart", "empty":true}, {"id":"prism_bow", "hint":true}, {"id":"prism_bow", "color":Color("516477")}]:
		expect(Painterly.resource_path(entry).is_empty(), "unknown/hint entry may not resolve a resource: " + str(entry))
		expect(Painterly.texture_for_entry(entry) == null, "unknown/hint entry may not load art")
	expect(Painterly.canonical_id({"id":"prism_bow", "color":Color("516477"), "name":"棱光长弓"}) == "prism_bow", "named real item must not be an empty-slot hint")

func test_fit(source_size: Vector2, label: String) -> void:
	for dimensions: Vector2 in [Vector2(28,91),Vector2(70,91),Vector2(28,28),Vector2(42,42),Vector2(108,108),Vector2(51,59),Vector2(158,238),Vector2(3,3)]:
		var bounds := Rect2(Vector2(-17,13),dimensions)
		var fitted: Rect2 = Painterly.fitted_rect(bounds,source_size)
		expect(fitted.has_area() and fitted.position.is_finite() and fitted.size.is_finite(), "finite nonempty fitted art: " + label)
		expect(fitted.position.x >= bounds.position.x + 0.999 and fitted.position.y >= bounds.position.y + 0.999 and fitted.end.x <= bounds.end.x - 0.999 and fitted.end.y <= bounds.end.y - 0.999, "texture escaped supplied rect/inset: " + label)
		expect(fitted.get_center().is_equal_approx(bounds.get_center()), "art must remain centered: " + label)
		expect(is_equal_approx(fitted.size.x / fitted.size.y,source_size.x / source_size.y), "source aspect ratio changed: " + label)
		expect(is_equal_approx(fitted.size.x,dimensions.x - 2) or is_equal_approx(fitted.size.y,dimensions.y - 2), "art does not fill available space: " + label)

func run() -> void:
	var frozen_data: Dictionary = Data.ITEMS.duplicate(true)
	var frozen_bases: Dictionary = Gear.BASES.duplicate(true)
	var frozen_profiles: Dictionary = Gear.POOL_PROFILES.duplicate(true)
	var frozen_jewels: Dictionary = Jewels.BASES.duplicate(true)
	var frozen_special: Dictionary = Jewels.SPECIAL_BASES.duplicate(true)
	var expected_ids: Array[String] = []
	for id: String in Data.ITEMS:
		var entry: Dictionary = Data.ITEMS[id].duplicate(true)
		entry["id"] = id
		entries.append(entry)
		expected_ids.append(id)
	for id: String in Gear.all_base_ids():
		entries.append({"id":"gear_000123", "base_id":id, "affixes":[{"id":"rootwell", "value":8}], "rarity":"magic"})
		expected_ids.append(id)
	for id: String in Jewels.BASES.keys() + Jewels.SPECIAL_BASES.keys():
		entries.append({"id":"jewel_000123", "base":id, "kind":"jewel", "affixes":[{"id":"force", "value":4}]})
		expected_ids.append(id)
	expect(expected_ids.size() == 22, "catalog count changed; review painterly manifest")
	expect(Painterly.ART_PATHS.size() == expected_ids.size(), "manifest must cover exactly current gear and jewel catalogs")
	for entry: Dictionary in entries:
		var id: String = Painterly.canonical_id(entry)
		expect(expected_ids.has(id), "entry failed canonical resolution")
		expect(Painterly.resource_path(entry) == "res://assets/art/equipment/" + id + ".png", "canonical resource mapping: " + id)
		var texture: Texture2D = Painterly.texture_for_entry(entry)
		expect(texture == Painterly.texture_for_entry(entry), "texture resource not cached: " + id)
		if texture == null:
			expect(not Painterly.source_rect(entry).has_area(), "missing art retains source bounds: " + id)
			continue
		available += 1
		var runtime_image: Image = texture.get_image()
		expect(runtime_image.get_width() <= 512 and runtime_image.get_height() <= 512, "runtime texture exceeds import memory cap: " + id)
		expect(texture.get_size() == Vector2(runtime_image.get_size()), "texture region must use imported pixel coordinates: " + id)
		var source: Rect2 = Painterly.source_rect(entry)
		expect(source == Painterly.source_rect(entry), "source alpha bounds not stable: " + id)
		expect(Rect2(Vector2.ZERO,texture.get_size()).encloses(source), "alpha crop outside texture: " + id)
		test_fit(source.size,id)
	if OS.get_cmdline_user_args().has("--require-all"):
		expect(available == 22, "complete art pack required; only %d/22 resources loaded" % available)
	test_identity()
	test_alpha_bounds()
	for dimensions: Vector2 in [Vector2(1024,1536),Vector2(1536,1024),Vector2(1024,1024),Vector2(200,1450),Vector2(1,1)]:
		test_fit(dimensions,"synthetic dimensions")
	for dimensions: Vector2 in [Vector2.ZERO,Vector2(-1,3),Vector2(INF,1),Vector2(NAN,1)]:
		expect(not Painterly.fitted_rect(Rect2(0,0,42,42),dimensions).has_area(), "invalid source dimensions")
	expect(not Painterly.draw_item(null, {"id":"prism_bow"}, Rect2(0,0,42,42)), "null CanvasItem must fall back")
	var surface := DrawingSurface.new()
	surface.suite = self
	root.add_child(surface)
	for unused: int in range(4):
		await process_frame
	expect(drew, "native draw callback did not run")
	expect(Data.ITEMS == frozen_data and Gear.BASES == frozen_bases and Gear.POOL_PROFILES == frozen_profiles and Jewels.BASES == frozen_jewels and Jewels.SPECIAL_BASES == frozen_special, "rendering changed gameplay catalogs")
	surface.queue_free()
	if failures.is_empty():
		print("EQUIPMENT_PAINTERLY_ART_TEST_PASS: %d checks; %d/22 textures available; bounded aspect fit, identity, fallback, alpha threshold, cache, immutable inputs and RNG. Native pixels require separate QA." % [checks,available])
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)
