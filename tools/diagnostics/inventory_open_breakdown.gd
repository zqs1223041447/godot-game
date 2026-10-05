extends SceneTree
## Small synchronous component probe. Does not reproduce main/HUD first-I latency.
## Run in fresh isolated XDG directories; never loads or saves a user build.
const Presentation = preload("res://scripts/visuals/visual_theme.gd")

class TimedState extends "res://scripts/canonical_game_state.gd":
	var profiling := false
	var times: Dictionary = {}
	var counts: Dictionary = {}
	func mark(key: String, began: int) -> void:
		times[key] = int(times.get(key, 0)) + Time.get_ticks_usec() - began
		counts[key] = int(counts.get(key, 0)) + 1
	func item_definition(uid: String) -> Dictionary:
		if not profiling: return super.item_definition(uid)
		var began := Time.get_ticks_usec()
		var result := super.item_definition(uid)
		mark("item_definition_all", began)
		var kind := str(result.get("kind", "empty"))
		# Same inclusive call duration, grouped by result kind; not additive to all.
		times["item_definition_"+kind] = int(times.get("item_definition_"+kind, 0)) + Time.get_ticks_usec() - began
		counts["item_definition_"+kind] = int(counts.get("item_definition_"+kind, 0)) + 1
		return result
	func snapshot() -> Dictionary:
		if not profiling: return super.snapshot()
		var began := Time.get_ticks_usec()
		var result := super.snapshot()
		mark("snapshot", began)
		return result
	func crafting_operations(uid: Variant, path: String = "user://build_save.json") -> Array[Dictionary]:
		if not profiling: return super.crafting_operations(uid, path)
		var began := Time.get_ticks_usec()
		var result := super.crafting_operations(uid, path)
		mark("crafting_operations", began)
		return result

class TimedPanel extends "res://scripts/ui/canonical_inventory_panel.gd":
	var times: Dictionary = {}
	var counts: Dictionary = {}
	func mark(key: String, began: int) -> void:
		times[key] = int(times.get(key, 0)) + Time.get_ticks_usec() - began
		counts[key] = int(counts.get(key, 0)) + 1
	func _build() -> void:
		var began := Time.get_ticks_usec()
		super._build()
		mark("build_including_child_ready", began)
	func refresh() -> void:
		var before := refresh_generation
		var began := Time.get_ticks_usec()
		super.refresh()
		mark("refresh_dirty" if before != refresh_generation else "refresh_noop", began)
	func _refresh_crafting() -> void:
		var began := Time.get_ticks_usec()
		super._refresh_crafting()
		mark("refresh_crafting", began)
	func _build_craft_confirmation() -> void:
		var began := Time.get_ticks_usec()
		super._build_craft_confirmation()
		mark("build_craft_confirmation", began)
	func _layout_slots() -> void:
		var began := Time.get_ticks_usec()
		super._layout_slots()
		mark("layout_slots", began)

class TimedControls extends "res://scripts/ui/crafting_controls.gd":
	var ensure_us := 0
	var ready_us := 0
	func _ensure_interface() -> void:
		var began := Time.get_ticks_usec()
		super._ensure_interface()
		ensure_us += Time.get_ticks_usec() - began
	func _ready() -> void:
		var began := Time.get_ticks_usec()
		super._ready()
		ready_us += Time.get_ticks_usec() - began

var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error("INVENTORY_BREAKDOWN_FAIL " + message)

func style_signature(style: StyleBox) -> Dictionary:
	var result := {}
	for property: Dictionary in style.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0: continue
		var key := str(property.name)
		if key in ["resource_name", "resource_local_to_scene", "resource_path"]: continue
		var value: Variant = style.get(key)
		if value is Resource: value = value.resource_path
		result[key] = value
	return result

func control_signature(controls: TimedControls) -> Dictionary:
	var result := {"local_default_font_size":controls.theme.default_font_size, "nodes":{}}
	var nodes := {"salvage":controls._salvage_button,"recalibrate":controls._recalibrate_button,
		"target_select":controls._target_select,"target_button":controls._target_button,"popup":controls._target_select.get_popup()}
	for key: String in nodes:
		var node: Variant = nodes[key]
		var row := {"font_size":node.get_theme_font_size("font_size"), "font":node.get_theme_font("font").resource_path,
			"font_color":node.get_theme_color("font_color"),"minimum":node.get_combined_minimum_size() if node is Control else Vector2.ZERO}
		var styles := {}
		for style_name: String in (["panel","hover"] if key == "popup" else ["normal","hover","pressed","disabled","focus"]):
			styles[style_name] = style_signature(node.get_theme_stylebox(style_name))
		row.styles = styles
		result.nodes[key] = row
	return result

func make_controls(host: Control, supplied_theme: Theme = null) -> Dictionary:
	var began := Time.get_ticks_usec()
	var controls := TimedControls.new()
	if supplied_theme != null: controls.theme = supplied_theme
	host.add_child(controls)
	var total := Time.get_ticks_usec() - began
	return {"node":controls,"new_add_ready_us":total,"ensure_interface_us":controls.ensure_us,"ready_us":controls.ready_us}

func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	var output := OS.get_environment("INVENTORY_BREAKDOWN_OUT")
	if not isolated.begins_with("/tmp/godot-m1-v051-") or not OS.get_user_data_dir().begins_with(isolated+"/") \
			or not OS.get_environment("XDG_CONFIG_HOME").begins_with("/tmp/godot-m1-v051-") \
			or not OS.get_environment("XDG_CACHE_HOME").begins_with("/tmp/godot-m1-v051-") or output.is_empty() \
			or FileAccess.file_exists("user://build_save.json"):
		push_error("Fresh isolated /tmp/godot-m1-v051-* XDG roots and INVENTORY_BREAKDOWN_OUT required")
		quit(78)
		return
	root.size = Vector2i(1280,720)
	var state := TimedState.new()
	var snapshot_before := state.snapshot()
	var host := VBoxContainer.new()
	host.theme = Presentation.create_theme()
	host.size = Vector2(420,720)
	root.add_child(host)
	var panel_rows: Array[Dictionary] = []
	for sample: int in range(3):
		state.times.clear(); state.counts.clear(); state.profiling = true
		var began := Time.get_ticks_usec()
		var panel := TimedPanel.new()
		host.add_child(panel)
		var new_add_us := Time.get_ticks_usec()-began
		began = Time.get_ticks_usec()
		panel.setup(state,"user://never-written.json")
		var setup_us := Time.get_ticks_usec()-began
		panel.refresh()
		state.profiling = false
		panel_rows.append({"sample":sample+1,"new_add_us":new_add_us,"setup_us":setup_us,
			"panel_nested_nonadditive_us":panel.times.duplicate(),"panel_calls":panel.counts.duplicate(),
			"state_nested_nonadditive_us":state.times.duplicate(),"state_calls":state.counts.duplicate(),
			"refresh_generation":panel.refresh_generation})
		check(panel.refresh_generation == 1,"exactly one dirty refresh per newly constructed panel")
		panel.free()
		await process_frame
	var theme_rows: Array[int] = []
	var control_rows: Array[Dictionary] = []
	for sample: int in range(3):
		var font_scale := 1.2 if sample == 1 else 1.0
		host.theme.default_font_size = roundi(16*font_scale)
		var began := Time.get_ticks_usec()
		var prepared_theme := Presentation.create_theme()
		theme_rows.append(Time.get_ticks_usec()-began)
		var baseline := make_controls(host)
		var prepared := make_controls(host,prepared_theme)
		var fallback_host := Control.new()
		root.add_child(fallback_host)
		var fallback := make_controls(fallback_host)
		Presentation.apply_font_scale(baseline.node,font_scale)
		Presentation.apply_font_scale(prepared.node,font_scale)
		var baseline_signature := control_signature(baseline.node)
		var prepared_signature := control_signature(prepared.node)
		check(baseline_signature == prepared_signature,"prepared unscaled theme preserves effective control/popup fonts, minimums, colors and styles")
		check(fallback.node.theme != null and fallback.node.theme.default_font_size == 16,"no-ancestor standalone fallback retained")
		control_rows.append({"sample":sample+1,"font_scale":font_scale,"ancestor_default_font_size":host.theme.default_font_size,
			"fresh_theme":metrics_only(baseline),"prepared_unscaled_theme":metrics_only(prepared),"standalone_fallback":metrics_only(fallback),
			"effective_style_signature_equal":baseline_signature == prepared_signature,
			"local_default_font_size":baseline_signature.local_default_font_size,
			"popup_font_size":baseline_signature.nodes.popup.font_size})
		baseline.node.free(); prepared.node.free(); fallback_host.free()
		await process_frame
	check(state.snapshot() == snapshot_before,"model unchanged")
	check(not FileAccess.file_exists("user://never-written.json") and not FileAccess.file_exists("user://build_save.json"),"no build save written")
	var report := {"source_revision":OS.get_environment("INVENTORY_BREAKDOWN_SOURCE"),"engine":Engine.get_version_info().string,
		"display_server":DisplayServer.get_name(),"user_data_dir":OS.get_user_data_dir(),"fixture_items":snapshot_before.items.size(),
		"scope":"Three same-process fresh panel samples with built-in starter state and no arena/main/HUD. Synchronous CPU components only, not original first-I latency or rendering. Sample 1 includes resources still cold after state/host setup; samples 2-3 share process resource caches. Nested times are nonadditive and instrument overhead is included.",
		"theme_comparison":"Prepared equivalent unscaled theme is constructed before the controls timer; its cost is listed separately. This measures upper-bound avoidable repeat creation, not free first-use creation. Ancestor theme is scaled independently. Structural appearance contract only; no rendered pixel comparison.",
		"panels":panel_rows,"create_theme_us":theme_rows,"controls":control_rows,"failures":failures,"exit_code":0 if failures.is_empty() else 1}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("Cannot write report"); quit(73); return
	file.store_string(JSON.stringify(report,"\t",true,true)); file.close()
	print("INVENTORY_OPEN_BREAKDOWN_COMPLETE ",output)
	print("PANEL_SETUP_US ",panel_rows.map(func(row): return row.setup_us))
	print("THEME_CREATE_US ",theme_rows)
	host.free()
	quit(0 if failures.is_empty() else 1)

func metrics_only(row: Dictionary) -> Dictionary:
	return {"new_add_ready_us":row.new_add_ready_us,"ensure_interface_us":row.ensure_interface_us,"ready_us":row.ready_us}
