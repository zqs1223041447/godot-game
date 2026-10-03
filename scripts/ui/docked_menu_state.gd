extends RefCounted
## Pure state for two docked menus and one full-screen overlay.
## This object does not read input, render controls, or access gameplay/save data.

const LEFT_SKILLS: String = "skills"
const LEFT_CHARACTER: String = "character"
const OVERLAY_TALENTS: String = "talents"
const OVERLAY_PAUSE: String = "pause"
const OVERLAY_SETTINGS: String = "settings"
const OVERLAY_DEATH: String = "death"
const OVERLAY_COMBAT: String = "combat"
const OVERLAY_MONSTERS: String = "monsters"

var _left: String = ""
var _right_inventory: bool = false
var _overlay: String = ""
## Active docks from oldest to most recently opened/requested.
var _open_order: Array[String] = []
## Closing the death view does not turn a dead run back into active combat.
var _death_latched: bool = false


## Toggle a named dock or request one of the exclusive overlays.
## Supported requests: inventory, skills, character, talents, pause, settings,
## death, combat, monsters.
## skills and character occupy the same left dock; requesting the active one closes it.
func request(name: String) -> Dictionary:
	var action: String = name.strip_edges().to_lower()
	if action == OVERLAY_DEATH:
		var death_changed: bool = not _death_latched or _overlay != OVERLAY_DEATH
		_death_latched = true
		_overlay = OVERLAY_DEATH
		return _result(true, death_changed)
	if _death_latched:
		return _result(false, false)

	match action:
		"inventory":
			if not _overlay.is_empty():
				return _result(false, false)
			if _right_inventory:
				_right_inventory = false
				_remove_dock("inventory")
			else:
				_right_inventory = true
				_touch_dock("inventory")
			return _result(true, true)
		"skills", "character":
			if not _overlay.is_empty():
				return _result(false, false)
			if _left == action:
				_left = ""
				_remove_dock("left")
			else:
				_left = action
				_touch_dock("left")
			return _result(true, true)
		"talents":
			if _overlay == OVERLAY_TALENTS:
				_overlay = ""
				return _result(true, true)
			if _overlay.is_empty():
				_overlay = OVERLAY_TALENTS
				return _result(true, true)
			return _result(false, false)
		"pause", "settings":
			var changed: bool = _overlay != action
			_overlay = action
			return _result(true, changed)
		"combat", "monsters":
			var debug_changed: bool = _overlay != action
			_overlay = action
			return _result(true, debug_changed)
		_:
			return _result(false, false)


## Handle only the keys owned by this state contract. Pass InputEventKey.echo
## through explicitly; echoed key events are consumed without repeating a toggle.
func handle_key(key: String, echo: bool = false) -> Dictionary:
	var normalized: String = key.strip_edges().to_lower()
	if echo:
		return _result(normalized in ["i", "b", "c", "k", "t", "f6", "f7", "escape", "esc"], false)

	match normalized:
		"i", "b":
			return request("inventory")
		"c":
			return request("character")
		"k":
			return request("skills")
		"t":
			return request("talents")
		"f6":
			return _toggle_debug_overlay(OVERLAY_COMBAT)
		"f7":
			return _toggle_debug_overlay(OVERLAY_MONSTERS)
		"escape", "esc":
			return close()
		_:
			return _result(false, false)


## Close a specific dock/overlay, or apply Escape's priority when target is omitted:
## overlay, most recently opened dock, then pause. "death" explicitly hides the
## death view but keeps the state latched and paused until the host replaces it.
func close(target: String = "escape") -> Dictionary:
	var action: String = target.strip_edges().to_lower()
	match action:
		"escape", "esc":
			return _close_escape()
		"left":
			if _death_latched or not _overlay.is_empty() or _left.is_empty():
				return _result(false, false)
			_left = ""
			_remove_dock("left")
			return _result(true, true)
		"inventory", "right":
			if _death_latched or not _overlay.is_empty() or not _right_inventory:
				return _result(false, false)
			_right_inventory = false
			_remove_dock("inventory")
			return _result(true, true)
		"overlay":
			if _death_latched or _overlay.is_empty():
				return _result(false, false)
			_overlay = ""
			return _result(true, true)
		"death":
			if not _death_latched or _overlay != OVERLAY_DEATH:
				return _result(false, false)
			_overlay = ""
			return _result(true, true)
		_:
			return _result(false, false)


## Return a detached snapshot. Mutating this Dictionary or its arrays never
## changes the state object.
func snapshot() -> Dictionary:
	return _snapshot_data().duplicate(true)


func _close_escape() -> Dictionary:
	if _death_latched:
		return _result(true, false)
	if not _overlay.is_empty():
		_overlay = ""
		return _result(true, true)
	if not _open_order.is_empty():
		var most_recent: String = _open_order[_open_order.size() - 1]
		if most_recent == "left":
			_left = ""
			_remove_dock("left")
		else:
			_right_inventory = false
			_remove_dock("inventory")
		return _result(true, true)
	_overlay = OVERLAY_PAUSE
	return _result(true, true)


func _toggle_debug_overlay(name: String) -> Dictionary:
	if _death_latched:
		return _result(false, false)
	if _overlay == name:
		_overlay = ""
	else:
		_overlay = name
	return _result(true, true)


func _touch_dock(dock: String) -> void:
	if _open_order.has(dock):
		_open_order.erase(dock)
	_open_order.append(dock)


func _remove_dock(dock: String) -> void:
	_open_order.erase(dock)


func _is_paused() -> bool:
	return _death_latched or not _left.is_empty() or _right_inventory or not _overlay.is_empty()


func _snapshot_data() -> Dictionary:
	return {
		"left": _left,
		"right_inventory": _right_inventory,
		"overlay": _overlay,
		"paused": _is_paused(),
		"death_latched": _death_latched,
		"open_order": _open_order.duplicate(true),
	}


func _result(accepted: bool, changed: bool) -> Dictionary:
	return {"accepted": accepted, "changed": changed, "state": _snapshot_data()}
