extends SceneTree
const HUD = preload("res://scripts/game_hud.gd")
class ArenaProbe:
	extends Node
	var calls := 0
	var hint := {"kind":"target", "living_count":3, "pending_count":0, "target":{"direction":"northwest", "outpost_name":"西侧驻点", "is_boss":false}, "outposts":[]}
	func exploration_cleanup_hint() -> Dictionary:
		calls += 1
		return hint.duplicate(true)
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var arena := ArenaProbe.new()
	var hint := arena.hint.duplicate(true)
	var bytes := var_to_bytes(hint)
	var view := HUD.cleanup_hint_view(hint)
	expect(view.text == "余敌 3 · 西北", "Concise live direction")
	expect(view.tooltip.contains("西侧驻点") and view.tooltip.contains("绕开障碍"), "Ownership and relative-direction caveat in tooltip")
	expect(var_to_bytes(hint) == bytes, "Formatter is read only")
	var directions := {"east":"东", "southeast":"东南", "south":"南", "southwest":"西南", "west":"西", "northwest":"西北", "north":"北", "northeast":"东北", "here":"附近"}
	for direction: String in directions:
		hint.target.direction = direction
		expect(HUD.cleanup_hint_view(hint).text.ends_with(directions[direction]), "Direction " + direction)
	hint.target.is_boss = true
	expect(HUD.cleanup_hint_view(hint).tooltip.contains("首领"), "Boss named separately")
	expect(HUD.cleanup_hint_view({"kind":"inactive"}).text.is_empty(), "Inactive clears label")
	expect(HUD.cleanup_hint_view({"kind":"waiting", "pending_count":2}).text == "等待后续怪物", "Pending actors have no invented direction")
	expect(HUD.cleanup_hint_view({"kind":"complete"}).text == "清理完成", "Completed state clear")
	view = HUD.cleanup_hint_view({"kind":"overview", "outposts":[{"name":"东侧驻点", "living_count":8}], "pending_count":2})
	expect(view.text == "未清驻点 1" and view.tooltip.contains("余敌 8") and view.tooltip.contains("后续怪物 2"), "Details kept in hover")
	expect(HUD.cleanup_hint_view({"kind":"settlement"}).text == "结算待保存", "Failed settlement not reported as saved completion")
	var hud := HUD.new()
	var label := Label.new()
	var overview := HUD.ExplorationOverview.new()
	hud._exploration_overview = overview
	hud._arena = arena
	hud._cleanup_label = label
	hud._world_context_cache = {"mode":"map", "encounter_mode":"exploration"}
	for i in range(19): hud._tick_cleanup_hint(0.01)
	expect(arena.calls == 0, "No early scan")
	hud._tick_cleanup_hint(0.011)
	expect(arena.calls == 1 and label.visible and label.text == "余敌 3 · 西北", "One scan at cadence")
	expect(overview.cleanup_hint == arena.hint, "The same one query supplies overview and existing label")
	overview.cleanup_hint.target.direction = "tampered"
	expect(arena.hint.target.direction == "northwest" and hud._cleanup_hint_snapshot.target.direction == "northwest", "Overview receives a detached cached snapshot")
	hud._tick_cleanup_hint(2.0)
	expect(arena.calls == 2, "No catch-up burst after long frame")
	hud._world_context_cache = {"mode":"normal_town"}
	hud._tick_cleanup_hint(0.01)
	expect(arena.calls == 2 and not label.visible and label.text.is_empty() and label.tooltip_text.is_empty(), "Town removes stale hint without scanning")
	expect(overview.cleanup_hint.is_empty(), "Inactive tick removes overview target without another scan")
	overview.update_cleanup_hint({"kind":"complete"})
	expect(overview.cleanup_status() == "地图已清理", "Completed status has no target claim")
	overview.update_cleanup_hint({"kind":"settlement"})
	expect(overview.cleanup_status().contains("待保存"), "Failed settlement is distinguished from saved completion")
	hud.free()
	overview.free()
	label.free()
	arena.free()
	print("Cleanup hint HUD: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
