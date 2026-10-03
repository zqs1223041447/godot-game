extends SceneTree
## Direct contract checks for the pure menu router; no rendered nodes or input events.

const MenuRouteState = preload("res://scripts/ui/menu_route_state.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_shortcuts_and_toggles()
	_test_echo_release_and_unknown()
	_test_escape_pause_and_close()
	print("Menu route state: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _state(router: RefCounted, window: String, paused: bool) -> void:
	var state: Dictionary = router.current_state()
	_expect(state.window == window and state.paused == paused,
		"Snapshot reports one window and pause state (window=%s, paused=%s)" % [window, paused])


func _expect_transition(result: Dictionary, action: String, window: String, paused: bool) -> void:
	_expect(result.has_all(["action", "changed", "window", "paused"]), "Transition returns the documented fields")
	_expect(result.action == action and result.changed == (action != MenuRouteState.ACTION_UNCHANGED),
		"Transition action and changed flag match: " + action)
	_expect(result.window == window and result.paused == paused,
		"Transition returns host state (window=%s, paused=%s)" % [window, paused])


func _test_shortcuts_and_toggles() -> void:
	var router: RefCounted = MenuRouteState.new()
	_state(router, MenuRouteState.WINDOW_NONE, false)
	_expect_transition(router.handle_key(KEY_I), MenuRouteState.ACTION_OPEN, MenuRouteState.WINDOW_INVENTORY, true)
	_expect_transition(router.handle_key(KEY_B), MenuRouteState.ACTION_CLOSE, MenuRouteState.WINDOW_NONE, false)
	_expect_transition(router.handle_key(KEY_T), MenuRouteState.ACTION_OPEN, MenuRouteState.WINDOW_PASSIVE_TREE, true)
	_expect_transition(router.handle_key(KEY_K), MenuRouteState.ACTION_SWITCH, MenuRouteState.WINDOW_SKILL_GEMS, true)
	_expect_transition(router.handle_key(KEY_F6), MenuRouteState.ACTION_SWITCH, MenuRouteState.WINDOW_DEBUG_BUILD, true)
	_expect_transition(router.handle_key(KEY_F7), MenuRouteState.ACTION_SWITCH, MenuRouteState.WINDOW_DEBUG_MONSTERS, true)
	_expect_transition(router.handle_key(KEY_I), MenuRouteState.ACTION_SWITCH, MenuRouteState.WINDOW_INVENTORY, true)
	_expect_transition(router.handle_key(KEY_I), MenuRouteState.ACTION_CLOSE, MenuRouteState.WINDOW_NONE, false)


func _test_echo_release_and_unknown() -> void:
	var router: RefCounted = MenuRouteState.new()
	_expect_transition(router.handle_key(KEY_I), MenuRouteState.ACTION_OPEN, MenuRouteState.WINDOW_INVENTORY, true)
	_expect_transition(router.handle_key(KEY_I, true, true), MenuRouteState.ACTION_UNCHANGED,
		MenuRouteState.WINDOW_INVENTORY, true)
	_expect_transition(router.handle_key(KEY_B, false), MenuRouteState.ACTION_UNCHANGED,
		MenuRouteState.WINDOW_INVENTORY, true)
	_expect_transition(router.handle_key(KEY_Z), MenuRouteState.ACTION_UNCHANGED,
		MenuRouteState.WINDOW_INVENTORY, true)
	_expect_transition(router.handle_key(KEY_Z, true, true), MenuRouteState.ACTION_UNCHANGED,
		MenuRouteState.WINDOW_INVENTORY, true)
	_expect_transition(router.handle_key(KEY_ESCAPE, true, true), MenuRouteState.ACTION_UNCHANGED,
		MenuRouteState.WINDOW_INVENTORY, true)
	_state(router, MenuRouteState.WINDOW_INVENTORY, true)

	var empty_router: RefCounted = MenuRouteState.new()
	_expect_transition(empty_router.handle_key(KEY_Z), MenuRouteState.ACTION_UNCHANGED,
		MenuRouteState.WINDOW_NONE, false)
	_state(empty_router, MenuRouteState.WINDOW_NONE, false)


func _test_escape_pause_and_close() -> void:
	var router: RefCounted = MenuRouteState.new()
	_expect_transition(router.handle_key(KEY_ESCAPE), MenuRouteState.ACTION_PAUSE,
		MenuRouteState.WINDOW_NONE, true)
	_expect_transition(router.handle_key(KEY_F7), MenuRouteState.ACTION_OPEN,
		MenuRouteState.WINDOW_DEBUG_MONSTERS, true)
	_expect_transition(router.handle_key(KEY_ESCAPE), MenuRouteState.ACTION_CLOSE,
		MenuRouteState.WINDOW_NONE, true)
	_expect_transition(router.handle_key(KEY_ESCAPE), MenuRouteState.ACTION_RESUME,
		MenuRouteState.WINDOW_NONE, false)
	_expect_transition(router.handle_key(KEY_T), MenuRouteState.ACTION_OPEN,
		MenuRouteState.WINDOW_PASSIVE_TREE, true)
	_expect_transition(router.handle_key(KEY_ESCAPE), MenuRouteState.ACTION_CLOSE,
		MenuRouteState.WINDOW_NONE, false)
	_state(router, MenuRouteState.WINDOW_NONE, false)
