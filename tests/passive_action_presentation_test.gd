extends SceneTree
const PassiveView = preload("res://scripts/ui/canonical_passive_panel.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var panel := PassiveView.new()
	panel._allocate = Button.new()
	panel._refund = Button.new()
	panel._detail = Label.new()
	panel._detail.text = "节点详情"
	var denied := {"allocate":{"allowed":false,"error_code":"no_points","reason":"天赋点不足"},"refund":{"allowed":false,"error_code":"not_allocated","reason":"节点尚未分配"}}
	var bytes := var_to_bytes(denied)
	panel._apply_action_preview(denied,false)
	expect(panel._allocate.disabled and panel._refund.disabled, "Authoritative actions disable both controls")
	expect(panel._allocate.tooltip_text == "天赋点不足", "Exact allocation reason shown")
	expect(panel._detail.text.contains("无法分配：天赋点不足") and not panel._detail.text.contains("尚未分配"), "Only relevant action reason appears in details")
	expect(var_to_bytes(denied) == bytes, "Read-only presentation")
	panel._detail.text = "另一节点"
	panel._apply_action_preview({"allocate":{"allowed":false,"reason":"已经分配"},"refund":{"allowed":false,"reason":"退还会使其他节点断开连接"}},true)
	expect(panel._refund.tooltip_text == "退还会使其他节点断开连接", "Refund dependency explained")
	expect(panel._detail.text.contains("无法退还") and not panel._detail.text.contains("天赋点不足"), "Selection change uses current reason")
	panel._detail.text = "可退节点"
	panel._apply_action_preview({"allocate":{"allowed":false,"reason":"已经分配"},"refund":{"allowed":true,"reason":""}},true)
	expect(not panel._refund.disabled and not panel._detail.text.contains("无法"), "Allowed refund clears old blocked reason")
	expect(panel._refund.tooltip_text.contains("获得 1 点"), "Allowed refund tooltip useful")
	panel._detail.text = "可分配节点"
	panel._apply_action_preview({"allocate":{"allowed":true,"reason":""},"refund":{"allowed":false,"reason":"节点尚未分配"}},false)
	expect(not panel._allocate.disabled and panel._allocate.tooltip_text.contains("消耗 1 点"), "Allowed allocation uses preview")
	var changes := {"max_health":{"before":130.0,"after":156.0},"max_mana":{"before":140.0,"after":145.5}}
	var original := var_to_bytes(changes)
	panel._detail.text = "生命与魔力节点"
	panel._apply_action_preview({"allocate":{"allowed":true,"resource_changes":changes},"refund":{"allowed":false}},false)
	expect(panel._detail.text.contains("分配后资源上限") and panel._detail.text.contains("生命 130.0 → 156.0（+26.0）") and panel._detail.text.contains("魔力 140.0 → 145.5（+5.5）"), "Actual resource transitions and signed deltas have explicit scope")
	expect(var_to_bytes(changes)==original, "Capacity presentation cannot edit supplied prediction")
	expect(PassiveView.resource_preview_text({"max_health":{"before":156.0,"after":130.0}},true).contains("退还后资源上限\n生命 156.0 → 130.0（-26.0）"), "Refund format describes its own inverse action")
	expect(PassiveView.resource_preview_text({},false).is_empty(), "Unchanged capacities add no spurious lines")
	panel._allocate.free()
	panel._refund.free()
	panel._detail.free()
	panel.free()
	print("Passive action presentation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
