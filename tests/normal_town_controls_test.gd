extends SceneTree
const TownPanel = preload("res://scripts/ui/town_service_panel.gd")
class Fixture extends Node:
	var testing := false
	var can_claim := false
	var pending: Dictionary = {}
	var last_route := ""
	var revision := 7
	func world_context() -> Dictionary:
		return {"mode": "town", "test_mode": testing, "revision": revision, "pending_map_reward": pending, "pending_gems": 0, "pending_flasks": 0, "can_claim_normal_rewards": can_claim, "claim_reason": "背包空间不足"}
	func town_services() -> Array:
		var result: Array = []
		for id in ["skill_merchant", "equipment_merchant", "jewel_merchant", "passive_reset", "crafter", "map_device"]:
			result.append({"id": id, "name": id, "description": id})
		return result
	func town_stock(_id: String) -> Array: return []
	func map_options() -> Dictionary:
		return {"maps": [{"id": "a", "name": "旧庭"}, {"id": "b", "name": "断垣"}], "normal_modifiers": [], "special_modifiers": [], "tiers": [{"map_id": "a", "tier": 1, "label": "挑战 I", "unlocked": true}, {"map_id": "a", "tier": 2, "label": "挑战 II", "unlocked": false, "reason": "先完成挑战I"}, {"map_id": "b", "tier": 1, "label": "挑战 I", "unlocked": true}]}
	func map_draft() -> Dictionary:
		return {"map_id": "a", "tier": 1, "normal_ids": [], "special_ids": [], "summary": "地图", "valid": true, "can_start": true, "revision": revision, "cost": 4, "completion_reward": 8}
	func craft_normal_map(_map: String, tier: int, _normal: Array, _special: Array, rev: int) -> Dictionary:
		last_route = "normal:%d:%d" % [tier, rev]
		return {"ok": true}
	func craft_map(_map: String, _normal: Array, _special: Array, rev: int) -> Dictionary:
		last_route = "test:%d" % rev
		return {"ok": true}
	func claim_normal_rewards(rev: int) -> Dictionary:
		last_route = "claim:%d" % rev
		return {"ok": false, "reason": "背包空间不足"}
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var fixture := Fixture.new()
	root.add_child(fixture)
	var panel := TownPanel.new()
	root.add_child(panel)
	panel.setup(fixture)
	expect(panel._title.text == "城镇 · 远征", "Normal profile title")
	expect(panel._service == "map_device", "Normal default opens maps")
	expect(panel._leave.text == "竞技练习" and panel._test_enter.visible, "Explicit separate routes")
	expect(panel._service_buttons.skill_merchant.disabled and not panel._service_buttons.map_device.disabled, "Free stock disabled only in normal")
	expect(panel._tier_select.item_count == 2 and panel._tier_select.is_item_disabled(1), "Locked tier visible but unavailable")
	panel._craft_map()
	expect(fixture.last_route == "normal:1:7", "Normal route uses selected tier and current revision")
	panel._select("skill_merchant")
	expect(panel._service == "map_device", "Direct stale test selection cannot display stock")
	fixture.pending = {"run_id": 1, "shards": 4}
	panel.refresh_world()
	expect(panel._claim.visible and panel._claim.disabled, "Pending reward follows authoritative capacity result")
	fixture.can_claim = true
	panel.refresh_world()
	expect(not panel._claim.disabled, "Claim enables from model flag")
	panel._claim.pressed.emit()
	expect(fixture.last_route == "claim:7", "Claim forwards world revision")
	fixture.testing = true
	panel.open_service("map_device")
	expect(panel._title.text == "城镇 · 测试供应" and panel._leave.text == "返回正式游戏", "Test profile routes are labelled")
	expect(not panel._service_buttons.skill_merchant.disabled and not panel._test_enter.visible and not panel._claim.visible, "Test supplies available without normal rewards")
	expect(not panel._tier_select.visible, "Legacy fixed test tier remains hidden")
	panel._craft_map()
	expect(fixture.last_route == "test:7", "Test uses existing craft route")
	expect(TownPanel._has_pending_rewards({"pending_gems": 1}), "Milestone-only pending reward is visible")
	expect(not TownPanel._has_pending_rewards({"pending_map_reward": {}, "pending_gems": 0, "pending_flasks": 0}), "No empty claim button")
	panel.queue_free()
	fixture.queue_free()
	await process_frame
	print("Normal town controls: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
