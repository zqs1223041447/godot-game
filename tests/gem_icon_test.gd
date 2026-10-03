extends SceneTree

const GemIconScript = preload("res://scripts/ui/gem_icon.gd")

class DragSlot extends Control:
	var drag_calls: int = 0

	func _get_drag_data(_at_position: Vector2) -> Variant:
		drag_calls += 1
		var preview := ColorRect.new()
		preview.color = Color("ba9148")
		preview.custom_minimum_size = Vector2(20, 20)
		set_drag_preview(preview)
		return {"type":"gem_icon_test"}


class DropTarget extends Control:
	var drop_calls: int = 0

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("type", "") == "gem_icon_test"

	func _drop_data(_at_position: Vector2, _data: Variant) -> void:
		drop_calls += 1


var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	root.size = Vector2i(1024, 600)
	var slot := DragSlot.new()
	slot.name = "GemIconDragSlot"
	slot.position = Vector2(32, 40)
	slot.size = Vector2(96, 96)
	root.add_child(slot)
	var icon := GemIconScript.new()
	icon.name = "GemIconUnderTest"
	icon.position = Vector2.ZERO
	icon.size = slot.size
	slot.add_child(icon)
	var target := DropTarget.new()
	target.name = "GemDropTarget"
	target.position = Vector2(720, 80)
	target.size = Vector2(128, 96)
	root.add_child(target)
	await process_frame

	icon.set_gem_icon(null, "中性测试宝石", "active")
	_expect(icon.texture == null and icon.visible, "null texture remains a visible configured icon")
	_expect(icon.mouse_filter == Control.MOUSE_FILTER_IGNORE, "GemIcon ignores pointer input")
	_expect(icon.accessibility_name == "中性测试宝石图标", "icon API supplies an accessible name")
	_expect(icon.gem_role == "active", "active skill gems use the crossed-rune marker role")
	_expect(icon.get_child_count() == 0, "drawing creates no mouse-blocking child controls")
	var placeholder_points: PackedVector2Array = GemIconScript.empty_gem_points(Rect2(10, 14, 60, 54))
	_expect(placeholder_points.size() == 4, "null texture has a four-point gemstone placeholder")
	for point: Vector2 in placeholder_points:
		_expect(Rect2(10, 14, 60, 54).has_point(point), "placeholder outline stays inside its inset")
	var empty_marker: Vector2 = GemIconScript.marker_center(Rect2(4, 6, 72, 72))
	_expect(Rect2(4, 6, 72, 72).has_point(empty_marker), "active rune marker stays inside the framed tile")
	icon.set_gem_icon(null, "疾咏辅助", "support")
	_expect(icon.gem_role == "support", "support gems select their linked-node marker role")

	var wide_fit: Rect2 = GemIconScript.aspect_fit_rect(Vector2(300, 100), Rect2(5, 9, 84, 60))
	_expect(is_equal_approx(wide_fit.size.x, 84.0) and is_equal_approx(wide_fit.size.y, 28.0), "wide source preserves its aspect ratio")
	_expect(is_equal_approx(wide_fit.position.y, 25.0), "wide source is vertically centered")
	var tall_fit: Rect2 = GemIconScript.aspect_fit_rect(Vector2(100, 200), Rect2(5, 9, 64, 80))
	_expect(is_equal_approx(tall_fit.size.x, 40.0) and is_equal_approx(tall_fit.size.y, 80.0), "tall source preserves its aspect ratio")
	_expect(is_equal_approx(tall_fit.position.x, 17.0), "tall source is horizontally centered")
	_expect(GemIconScript.aspect_fit_rect(Vector2.ZERO, Rect2(0, 0, 20, 20)).size == Vector2.ZERO, "invalid source has no stretched rectangle")
	var control_fit: Rect2 = GemIconScript.image_fit_rect(Vector2(120, 80), Vector2(320, 80))
	_expect(is_equal_approx(control_fit.size.x, 68.0) and is_equal_approx(control_fit.size.y, 17.0), "control render path uses its centered square tile and stable six-unit inset")
	_expect(GemIconScript.square_tile_rect(Vector2(120, 80)) == Rect2(20, 0, 80, 80), "non-square controls center a square framed tile")

	var start: Vector2 = slot.position + slot.size * 0.5
	var finish: Vector2 = target.position + target.size * 0.5
	_push_mouse_button(start, true)
	await process_frame
	_push_mouse_motion(start, finish)
	await process_frame
	_expect(root.gui_is_dragging(), "real viewport events start a drag from the icon surface")
	_expect(slot.drag_calls == 1, "ignored icon child lets its parent slot create drag data")
	_push_mouse_button(finish, false)
	await process_frame
	_expect(target.drop_calls == 1, "null-art icon does not block the parent slot's real drop path")
	_expect(not root.gui_is_dragging(), "drop ends the viewport drag state")

	var image := Image.create(320, 80, false, Image.FORMAT_RGBA8)
	image.fill(Color("52623b"))
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	icon.set_gem_icon(texture, "风暴宝石", "active")
	await process_frame
	var fitted: Rect2 = GemIconScript.image_fit_rect(icon.size, texture.get_size())
	_expect(icon.texture == texture and is_equal_approx(fitted.size.x / fitted.size.y, 4.0), "assigned art stays unwarped in the slot aspect")
	_expect(Rect2(icon.position, icon.size).encloses(Rect2(icon.position + fitted.position, fitted.size)), "texture rectangle remains clipped to the icon tile")
	_expect(icon.mouse_filter == Control.MOUSE_FILTER_IGNORE, "setting real art keeps pointer passthrough")

	print("gem_icon_test: %d checks, %d failures" % [checks, failures])
	slot.queue_free()
	target.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _push_mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	root.push_input(event, true)


func _push_mouse_motion(previous: Vector2, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - previous
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)
