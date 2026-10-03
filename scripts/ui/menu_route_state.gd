extends RefCounted
## Pure shortcut-to-window and pause state. The host owns all scenes and input events.

const WINDOW_NONE: String = ""
const WINDOW_INVENTORY: String = "inventory"
const WINDOW_PASSIVE_TREE: String = "passive_tree"
const WINDOW_SKILL_GEMS: String = "skill_gems"
const WINDOW_DEBUG_BUILD: String = "debug_build"
const WINDOW_DEBUG_MONSTERS: String = "debug_monsters"

const ACTION_UNCHANGED: String = "unchanged"
const ACTION_OPEN: String = "open"
const ACTION_SWITCH: String = "switch"
const ACTION_CLOSE: String = "close"
const ACTION_PAUSE: String = "pause"
const ACTION_RESUME: String = "resume"

var _active_window: String = WINDOW_NONE
var _pause_only: bool = false


## Return a fresh, render-independent snapshot for the host controller.
func current_state() -> Dictionary:
	return _result(ACTION_UNCHANGED, false)


## Apply a physical key code without depending on InputMap or InputEventKey.
## Releases and key echo are ignored. Returned fields are action, changed, window, paused.
func handle_key(physical_keycode: int, pressed: bool = true, echo: bool = false) -> Dictionary:
	if not pressed or echo:
		return _result(ACTION_UNCHANGED, false)

	var requested_window: String = _window_for_key(physical_keycode)
	if not requested_window.is_empty():
		if requested_window == _active_window:
			_active_window = WINDOW_NONE
			return _result(ACTION_CLOSE, true)
		var is_switch: bool = not _active_window.is_empty()
		_active_window = requested_window
		return _result(ACTION_SWITCH if is_switch else ACTION_OPEN, true)

	if physical_keycode == KEY_ESCAPE:
		if not _active_window.is_empty():
			_active_window = WINDOW_NONE
			return _result(ACTION_CLOSE, true)
		_pause_only = not _pause_only
		return _result(ACTION_PAUSE if _pause_only else ACTION_RESUME, true)

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


func _result(action: String, changed: bool) -> Dictionary:
	return {
		"action": action,
		"changed": changed,
		"window": _active_window,
		"paused": not _active_window.is_empty() or _pause_only,
	}
