extends SceneTree

const State = preload("res://scripts/ui/docked_menu_state.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_parallel_and_exclusive_docks()
	_test_talents_preserves_docks()
	_test_debug_overlays()
	_test_escape_priority()
	_test_key_echo_unknown_and_copy_boundaries()
	_test_death_boundary()
	print("Docked menu state: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


func _test_parallel_and_exclusive_docks() -> void:
	var state = State.new()
	state.handle_key("K")
	state.handle_key("B")
	var both: Dictionary = state.snapshot()
	_expect(both.left == "skills" and both.right_inventory and both.paused, "Skills and inventory docks can be open together and pause combat")
	state.request("character")
	var character: Dictionary = state.snapshot()
	_expect(character.left == "character" and character.right_inventory, "Character attributes replace skills in the shared left dock")
	state.request("character")
	var closed_left: Dictionary = state.snapshot()
	_expect(closed_left.left.is_empty() and closed_left.right_inventory and closed_left.paused, "Toggling the active left view closes only the left dock")
	state.handle_key("B")
	_expect(not state.snapshot().paused, "Closing the remaining dock unpauses the presentation state")
	state.request("skills")
	state.request("skills")
	_expect(state.snapshot().left.is_empty(), "Requesting the same left view twice explicitly toggles it closed")


func _test_talents_preserves_docks() -> void:
	var state = State.new()
	state.request("skills")
	state.request("inventory")
	var before: Dictionary = state.snapshot()
	var opened: Dictionary = state.handle_key("T")
	_expect(opened.accepted and opened.state.overlay == "talents", "T opens the full-screen talents overlay")
	_expect(opened.state.left == before.left and opened.state.right_inventory == before.right_inventory and opened.state.open_order == before.open_order, "Talents overlay retains both dock states and their Escape order")
	var closed: Dictionary = state.handle_key("t")
	_expect(closed.state.overlay.is_empty(), "T closes the talents overlay")
	_expect(closed.state.left == "skills" and closed.state.right_inventory, "Closing talents restores both previously open docks")
	var order: Array = closed.state.open_order
	_expect(order == ["left", "inventory"], "Talents close preserves the dock open order")
	var blocked: Dictionary = state.request("character")
	_expect(blocked.accepted and blocked.state.left == "character", "Character attribute UI request targets the existing left dock")


func _test_escape_priority() -> void:
	var state = State.new()
	state.request("skills")
	state.request("inventory")
	state.request("settings")
	var close_overlay: Dictionary = state.handle_key("escape")
	_expect(close_overlay.state.overlay.is_empty() and close_overlay.state.left == "skills" and close_overlay.state.right_inventory, "Escape closes an overlay before either dock")
	var close_recent: Dictionary = state.handle_key("escape")
	_expect(close_recent.state.left == "skills" and not close_recent.state.right_inventory, "Escape closes the most recently opened inventory dock first")
	var close_left: Dictionary = state.handle_key("escape")
	_expect(close_left.state.left.is_empty() and close_left.state.overlay.is_empty(), "Next Escape closes the remaining left dock")
	var open_pause: Dictionary = state.handle_key("escape")
	_expect(open_pause.state.overlay == "pause", "Escape with no open dock enters pause")

	var reversed = State.new()
	reversed.request("inventory")
	reversed.request("skills")
	var recent_left: Dictionary = reversed.close()
	_expect(recent_left.state.left.is_empty() and recent_left.state.right_inventory, "Escape order follows the most recent dock when left was opened last")


func _test_debug_overlays() -> void:
	var state = State.new()
	state.request("skills")
	state.request("inventory")
	var before: Dictionary = state.snapshot()
	var combat: Dictionary = state.handle_key("F6")
	_expect(combat.accepted and combat.state.overlay == "combat", "F6 selects the combat debug overlay")
	_expect(combat.state.left == before.left and combat.state.right_inventory == before.right_inventory, "Combat overlay retains both open docks")
	var combat_echo: Dictionary = state.handle_key("F6", true)
	_expect(not combat_echo.changed and combat_echo.state.overlay == "combat", "F6 key echo cannot close its active overlay")
	var monsters: Dictionary = state.handle_key("F7")
	_expect(monsters.accepted and monsters.state.overlay == "monsters", "F7 switches the shared overlay to the monster debug panel")
	_expect(monsters.state.left == before.left and monsters.state.right_inventory == before.right_inventory, "F6/F7 overlay switching leaves both docks intact")
	var requested_combat: Dictionary = state.request("combat")
	_expect(requested_combat.state.overlay == "combat", "UI request combat selects the same shared overlay as F6")
	var requested_monsters: Dictionary = state.request("monsters")
	_expect(requested_monsters.state.overlay == "monsters", "UI request monsters selects the same shared overlay as F7")
	var restored: Dictionary = state.handle_key("escape")
	_expect(restored.state.overlay.is_empty() and restored.state.left == "skills" and restored.state.right_inventory, "Escape closes the debug overlay and restores both docks")
	var closed_same: Dictionary = state.handle_key("F6")
	_expect(closed_same.state.overlay == "combat", "F6 opens combat when no overlay is active")
	var toggled_off: Dictionary = state.handle_key("F6")
	_expect(toggled_off.state.overlay.is_empty() and toggled_off.state.left == "skills" and toggled_off.state.right_inventory, "F6 toggles its own overlay closed without losing docks")
	state.handle_key("F7")
	var monsters_toggled_off: Dictionary = state.handle_key("F7")
	_expect(monsters_toggled_off.state.overlay.is_empty() and monsters_toggled_off.state.left == "skills" and monsters_toggled_off.state.right_inventory, "F7 toggles its own overlay closed without losing docks")


func _test_key_echo_unknown_and_copy_boundaries() -> void:
	var state = State.new()
	var opened: Dictionary = state.handle_key("I")
	var before: Dictionary = state.snapshot()
	var echo_result: Dictionary = state.handle_key("i", true)
	_expect(echo_result.accepted and not echo_result.changed and echo_result.state == before, "Key echo is consumed without toggling the inventory twice")
	var unknown_key: Dictionary = state.handle_key("C")
	_expect(not unknown_key.accepted and unknown_key.state == before, "C is not intercepted by this menu state and remains available to existing routing")
	var unknown_request: Dictionary = state.request("stats")
	_expect(not unknown_request.accepted and not unknown_request.changed and unknown_request.state == before, "Unknown UI requests leave state unchanged")
	var no_echo_route: Dictionary = state.handle_key("F9", true)
	_expect(not no_echo_route.accepted and no_echo_route.state == before, "Unknown echoed keys are harmless")
	var escaped_snapshot: Dictionary = state.snapshot()
	escaped_snapshot.left = "forged"
	escaped_snapshot.open_order.clear()
	opened.state.open_order.append("forged")
	_expect(state.snapshot() == before, "Snapshots and transition results expose detached nested arrays")


func _test_death_boundary() -> void:
	var state = State.new()
	state.request("skills")
	state.request("inventory")
	var death: Dictionary = state.request("death")
	_expect(death.state.overlay == "death" and death.state.death_latched and death.state.paused, "Death request latches a paused terminal state")
	var after_escape: Dictionary = state.handle_key("escape")
	_expect(not after_escape.changed and after_escape.state == death.state, "Escape cannot dismiss death or restore live combat")
	var debug_after_death: Dictionary = state.handle_key("F7")
	_expect(not debug_after_death.changed and debug_after_death.state == death.state, "F7 cannot replace the death overlay or revive the run")
	var generic_close: Dictionary = state.close("overlay")
	_expect(not generic_close.accepted and generic_close.state == death.state, "Generic overlay close cannot dismiss death")
	var explicit_close: Dictionary = state.close("death")
	_expect(explicit_close.accepted and explicit_close.state.overlay.is_empty(), "Host can explicitly close the death view")
	_expect(explicit_close.state.death_latched and explicit_close.state.paused, "Explicit death-view close remains terminal and paused")
	var attempted_menu: Dictionary = state.request("skills")
	_expect(not attempted_menu.accepted and attempted_menu.state.death_latched and attempted_menu.state.paused, "A latched death state rejects normal menu requests until the host replaces it after a run reset")
	var escape_after_close: Dictionary = state.close()
	_expect(not escape_after_close.changed and escape_after_close.state.overlay.is_empty() and escape_after_close.state.paused, "Escape after explicit death-view close still cannot enter live gameplay")
