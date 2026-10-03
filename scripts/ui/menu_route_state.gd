extends RefCounted
## Pure shortcut-to-window and pause state. The host owns all scenes and input events.

const WINDOW_NONE: String = ""
const WINDOW_PAUSE: String = "pause"
const WINDOW_SETTINGS: String = "settings"
const WINDOW_INVENTORY: String = "inventory"
const WINDOW_PASSIVE_TREE: String = "passive_tree"
const WINDOW_SKILL_GEMS: String = "skill_gems"
const WINDOW_DEBUG_BUILD: String = "debug_build"
const WINDOW_DEBUG_MONSTERS: String = "debug_monsters"

const ACTION_UNCHANGED: String = "unchanged"
const ACTION_OPEN: String = "open"
const ACTION_SWITCH: String = "switch"
const ACTION_CLOSE: String = "close"

var _active_window: String = WINDOW_NONE


## Return a fresh, render-independent snapshot for the host controller.
func current_state() -> Dictionary:
	return _result(ACTION_UNCHANGED, false)


## Request a root window by ID. Existing routes are replaced; optional toggle closes the same route.
func request_window(id: String, toggle: bool = false) -> Dictionary:
	if not _is_known_window(id):
		return _result(ACTION_UNCHANGED, false)
	if id == _active_window:
		if toggle:
			_active_window = WINDOW_NONE
			return _result(ACTION_CLOSE, true)
		return _result(ACTION_UNCHANGED, false)
	var is_switch: bool = not _active_window.is_empty()
	_active_window = id
	return _result(ACTION_SWITCH if is_switch else ACTION_OPEN, true)


## Apply a physical key code without depending on InputMap or InputEventKey.
## Releases and key echo are ignored. Returned fields are action, changed, window, paused.
func handle_key(physical_keycode: int, pressed: bool = true, echo: bool = false) -> Dictionary:
	if not pressed or echo:
		return _result(ACTION_UNCHANGED, false)

	var requested_window: String = _window_for_key(physical_keycode)
	if not requested_window.is_empty():
		return request_window(requested_window, true)

	if physical_keycode == KEY_ESCAPE:
		if not _active_window.is_empty():
			_active_window = WINDOW_NONE
			return _result(ACTION_CLOSE, true)
		return request_window(WINDOW_PAUSE)

	return _result(ACTION_UNCHANGED, false)


func _window_for_key(physical_keycode: int) -> String:
	if physical_keycode == KEY_I or physical_keycode == KEY_B:
		return WINDOW_INVENTORY
	if physical_keycode == KEY_T:
		return WINDOW_PASSIVE_TREE
	if physical_keycode == KEY_K:
		return WINDOW_SKILL_GEMS
	if physical_keycode == KEY_F6:
		return WINDOW_DEBUG_BUILD
	if physical_keycode == KEY_F7:
		return WINDOW_DEBUG_MONSTERS
	return WINDOW_NONE


func _is_known_window(id: String) -> bool:
	return id == WINDOW_PAUSE or id == WINDOW_SETTINGS or id == WINDOW_INVENTORY or \
		id == WINDOW_PASSIVE_TREE or id == WINDOW_SKILL_GEMS or id == WINDOW_DEBUG_BUILD or \
		id == WINDOW_DEBUG_MONSTERS


func _result(action: String, changed: bool) -> Dictionary:
	return {
		"action": action,
		"changed": changed,
		"window": _active_window,
		"paused": not _active_window.is_empty(),
	}
