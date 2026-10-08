extends SceneTree
## Real viewport wheel dispatch over transparent cards above a scrollable inventory.
const Card = preload("res://scripts/ui/item_hover_card.gd")
var checks := 0
var failures: Array[String] = []
var host: Control
var card: Control
var inventory: ScrollContainer

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func view(uid: String) -> Dictionary:
	var lines: Array[String] = []
	for index in 60: lines.append("长物品详情 %02d：测试词缀全文可以滚动阅读。" % index)
	lines.append("详情末行：已经到底")
	return {"uid":uid, "name":"长物品详情", "kind_label":"主动宝石", "rarity_label":"等级 1 · 品质 0",
		"tags":["法术", "投射物"], "function":"功能正文", "affix_lines":lines}
func point(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)
func wheel(at: Vector2, direction: int, factor: float = 1.0) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = at; motion.global_position = at
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN if direction > 0 else MOUSE_BUTTON_WHEEL_UP
	event.position = at; event.global_position = at; event.pressed = true; event.factor = factor
	root.push_input(event, true)
	await process_frame
func reset(scrolls: Array[ScrollContainer]) -> void:
	inventory.scroll_vertical = 0
	for scroll in scrolls: scroll.scroll_vertical = 0
func run() -> void:
	root.size = Vector2i(1280,720)
	host = Control.new(); host.size = Vector2(1280,720); root.add_child(host)
	inventory = ScrollContainer.new(); inventory.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(inventory)
	var fill := Control.new(); fill.custom_minimum_size = Vector2(1280,1800); inventory.add_child(fill)
	card = Card.new(); host.add_child(card)
	var input := view("source"); var input_before := input.duplicate(true)
	var source_anchor := Rect2(1140,650,40,40)
	card.present(input,[view("compare-one"),view("compare-two")],source_anchor,Rect2(0,0,1280,720),true)
	await process_frame; await process_frame
	var scrolls: Array[ScrollContainer] = []
	for column: Control in card._row.get_children():
		scrolls.append(column.find_child("ItemDetailsScroll",true,false))
	check(scrolls.size() == 3 and inventory.get_v_scroll_bar().max_value > inventory.get_v_scroll_bar().page,
		"Three real floating detail columns above a scrollable inventory")
	for index in scrolls.size():
		var column: Control = card._row.get_child(index)
		for name: String in ["ItemName", "ItemMetadata", "ItemTags", "ItemDetailsScroll"]:
			reset(scrolls)
			await wheel(point(column.find_child(name,true,false)),1)
			var isolated: bool = inventory.scroll_vertical == 0
			for other in scrolls.size():
				isolated = isolated and (scrolls[other].scroll_vertical > 0 if other == index else scrolls[other].scroll_vertical == 0)
			check(isolated,"Wheel over %s routes only to its detail column %d" % [name,index])
		reset(scrolls)
		var at := point(column.find_child("ItemName",true,false))
		for unused in 120: await wheel(at,1)
		var bar: VScrollBar = scrolls[index].get_v_scroll_bar()
		check(is_equal_approx(float(scrolls[index].scroll_vertical),bar.max_value-bar.page),"Long details reach exact bottom in column %d" % index)
		var last: Control = column.find_child("Text_额外词缀",true,false)
		var visible_bottom: Vector2 = last.get_global_transform_with_canvas()*Vector2(2,last.size.y-2)
		var local_bottom: Vector2 = scrolls[index].get_global_transform_with_canvas().affine_inverse()*visible_bottom
		check(Rect2(Vector2.ZERO,scrolls[index].size).has_point(local_bottom),"Final text line is visible at bottom in column %d" % index)
		await wheel(at,1)
		check(inventory.scroll_vertical == 0,"Wheel at detail bottom does not leak to inventory in column %d" % index)
		await wheel(at,-1)
		check(scrolls[index].scroll_vertical < bar.max_value-bar.page and inventory.scroll_vertical == 0,
			"Header wheel also scrolls upward within column %d" % index)
	reset(scrolls)
	await wheel(host.get_global_transform_with_canvas()*source_anchor.get_center(),1)
	check(scrolls[0].scroll_vertical > 0 and scrolls[1].scroll_vertical == 0 and scrolls[2].scroll_vertical == 0
		and inventory.scroll_vertical == 0,"Wheel on source item still routes to the main details")
	reset(scrolls)
	await wheel(Vector2(30,710),1)
	check(inventory.scroll_vertical > 0 and scrolls[0].scroll_vertical == 0,"Wheel outside card and source remains with the inventory")
	check(input == input_before and card._last_view == input_before,"Wheel routing preserves all source item presentation data")
	check(card.mouse_filter == Control.MOUSE_FILTER_IGNORE and scrolls[0].get_v_scroll_bar().mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Cards and native scrollbars remain pointer-transparent for source drag/drop")
	print("ITEM_HOVER_WHEEL_ROUTING checks=%d failures=%d" % [checks,failures.size()])
	host.queue_free(); await process_frame
	quit(1 if not failures.is_empty() else 0)
