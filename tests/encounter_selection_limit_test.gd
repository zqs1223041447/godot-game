extends SceneTree

const Controls = preload("res://scripts/ui/encounter_controls.gd")
const Catalog = preload("res://scripts/encounters/encounter_catalog.gd")
var checks := 0
var failures := 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var panel = Controls.new()
	var ids: Array[String] = Catalog.get_ids()
	var original: Array[String] = [ids[0], ids[1]]
	var events: Array = []
	panel.encounter_requested.connect(func(selection: Array[String]): events.append(selection))
	panel.set_context([])
	panel._options[ids[0]].button_pressed = true
	panel._options[ids[1]].button_pressed = true
	expect(panel.get_selected_ids() == original, "Two user selections are accepted")
	expect(not panel._options[ids[0]].disabled and not panel._options[ids[1]].disabled, "Selected options remain removable at the cap")
	expect(panel._options[ids[2]].disabled, "Unselected options are disabled at the cap")
	expect(panel._options[ids[2]].tooltip_text.contains("最多"), "Blocked option explains the selection limit")
	panel._options[ids[2]].button_pressed = true
	expect(panel.get_selected_ids() == original, "Over-limit user callback preserves accepted draft")
	expect(not panel._options[ids[2]].button_pressed, "Rejected checkbox is restored")
	expect(not panel._confirm.disabled and panel._selection_error.is_empty(), "Limit attempt never poisons valid context")
	panel._confirm.pressed.emit()
	expect(events.size() == 1 and events[0] == original, "Confirmation still emits accepted draft")
	panel._options[ids[0]].button_pressed = false
	expect(not panel._options[ids[2]].disabled and panel._options[ids[2]].tooltip_text.is_empty(), "Removing a choice clears limit lock and tooltip")
	panel._options[ids[2]].button_pressed = true
	expect(panel.get_selected_ids() == [ids[1], ids[2]], "Replacement can be selected without reopening")
	panel._options[ids[1]].button_pressed = false
	panel._options[ids[2]].button_pressed = false
	expect(panel.get_selected_ids().is_empty() and not panel._confirm.disabled, "Repeated deselection restores ordinary encounter")
	for id: String in ids:
		expect(not panel._options[id].disabled, "Every choice available below cap: " + id)
	expect(not panel.set_context([ids[0], ids[1], ids[2]]), "Over-limit external context remains rejected")
	expect(panel.get_selected_ids().is_empty() and panel._confirm.disabled, "Invalid external context fails closed")
	for id: String in ids:
		expect(panel._options[id].disabled, "Invalid external context locks all options: " + id)
	panel._options[ids[0]].button_pressed = true
	expect(panel.get_selected_ids().is_empty(), "Forced invalid-context toggle cannot recover draft")
	panel.set_context(original, "owner lock")
	for id: String in ids:
		expect(panel._options[id].disabled and panel._options[id].tooltip_text == "owner lock", "Owner lock takes priority: " + id)
	panel._options[ids[0]].button_pressed = false
	expect(panel.get_selected_ids() == original and panel._options[ids[0]].button_pressed, "Owner lock restores forced toggle")
	panel.set_context([ids[0]])
	expect(not panel._confirm.disabled and not panel._options[ids[2]].disabled, "Valid external context recovers controls")
	panel.free()
	print("Encounter selection limit: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
