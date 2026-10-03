extends SceneTree
## Real-display observer. Mouse actions are supplied by CUA, not synthesized here.
var arena: Node2D
var directory: String
var last_revision: int
var stage: int=0
var cancelled: int=0
var capturing: bool=false
var records: Array[Dictionary]=[]
var input_events: Array[Dictionary]=[]
var initial_build: Dictionary
var interactive: bool=true

class Observer extends Node:
	var host: SceneTree
	func _input(event: InputEvent) -> void: host.observe(event)
	func _process(_delta: float) -> void: host.poll()

func _initialize() -> void: call_deferred("run")
func choices() -> Control: return arena.hud._panel_body.find_child("EncounterControls",true,false)

func run() -> void:
	var data: String=OS.get_environment("XDG_DATA_HOME").simplify_path()
	directory=OS.get_environment("GODOT_ENCOUNTER_QA_OUT")
	if OS.get_name()!="Linux" or DisplayServer.get_name()=="headless" or not data.begins_with("/tmp/godot-v017-native") or not OS.get_user_data_dir().begins_with(data+"/") or not directory.is_absolute_path():
		printerr("Encounter native QA requires a real display and isolated Linux user data")
		quit(78);return
	DirAccess.make_dir_recursive_absolute(directory)
	root.size=Vector2i(1280,720);root.position=Vector2i(10,30)
	root.title="v0.17 encounter QA - choose both, cancel, confirm, retry, choose ordinary"
	arena=load("res://scenes/main.tscn").instantiate()
	root.add_child(arena);arena.set_process(false)
	arena.rng.seed=170017
	initial_build=arena.state._snapshot()
	last_revision=arena.run_revision
	arena.hud._encounter_dialog.canceled.connect(func()->void:
		cancelled+=1
		print("ENCOUNTER_NATIVE_CANCEL preserved=",arena.run_revision==last_revision and arena.state._snapshot()==initial_build))
	var observer:=Observer.new();observer.host=self;root.add_child(observer)
	await show_choices()
	interactive=not OS.get_cmdline_user_args().has("--capture-only")
	if not interactive:
		await matrix()
		quit(0);return
	print("ENCOUNTER_NATIVE_READY")

func observe(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		input_events.append({"button":event.button_index,"position":[event.position.x,event.position.y]})
	elif event is InputEventKey and event.pressed and not event.echo:
		input_events.append({"key":OS.get_keycode_string(event.physical_keycode)})

func poll() -> void:
	if not interactive or capturing or stage>=3 or arena.run_revision==last_revision:return
	last_revision=arena.run_revision
	stage+=1
	print("ENCOUNTER_NATIVE_RUN stage=",stage," selection=",arena.encounter_selection()," build_unchanged=",arena.state._snapshot()==initial_build)
	next_step.call_deferred()

func next_step() -> void:
	await capture("run-%d"%stage)
	if stage==1:
		arena.hud.open_panel("pause")
		for frame: int in range(5):await process_frame
		arena.hud._panel_scroll.ensure_control_visible(arena.hud._panel_body.find_child("RestartButton",true,false))
		await capture("retry-button")
	elif stage==2:
		await show_choices()
	else:
		var valid: bool=cancelled>=1 and arena.encounter_selection().is_empty() and arena.state._snapshot()==initial_build
		print("ENCOUNTER_NATIVE_FLOW_PASS ",valid)
		await matrix()

func show_choices() -> void:
	arena.hud.open_panel("pause")
	for frame: int in range(5):await process_frame
	arena.hud._panel_scroll.ensure_control_visible(choices()._confirm)
	await capture("choices-%d"%stage)

func capture(label: String) -> void:
	capturing=true
	arena.queue_redraw()
	for frame: int in range(8):await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(directory.path_join(label+".png"))==OK)
	var monsters: Array[Dictionary]=[]
	for enemy: Dictionary in arena.enemies:
		monsters.append({"id":enemy.id,"template":enemy.template_id,"health":enemy.health,"max_health":enemy.max_health,"speed":enemy.speed,
			"challenge":enemy.get("encounter_source",{}).duplicate(true),"damage":enemy.damage,"reward_eligible":enemy.reward_eligible})
	records.append({"label":label,"resolution":[root.size.x,root.size.y],"run_revision":arena.run_revision,"selection":arena.encounter_selection(),
		"input_mode":"physical_observed" if interactive else "programmatic_render_capture","build_unchanged":arena.state._snapshot()==initial_build,"monsters":monsters,"ui_scale":arena.visual_settings.ui_scale,"font_scale":arena.visual_settings.font_scale})
	var file:=FileAccess.open(directory.path_join("native-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"cancel_count":cancelled,"inputs":input_events,"records":records,"fixture_changes":["isolated fresh save","simulation held while real menu input is exercised","fixed next-run RNG seed","menus reopened and scrolled between phases"],"stats_modified":false},"\t",true,true));file.close()
	capturing=false
	print("ENCOUNTER_NATIVE_CAPTURE ",label)

func matrix() -> void:
	interactive=false
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		for scale: float in [1.0,1.2]:
			root.size=resolution
			arena.visual_settings.font_scale=scale
			arena.visual_settings.ui_scale=1.1 if scale>1.0 else 1.0
			arena.hud._apply_presentation()
			arena.hud.open_panel("pause")
			for frame: int in range(5):await process_frame
			var control: Control=choices()
			control.set_context(["enemy_max_health_120","enemy_move_speed_110"])
			control._options.enemy_max_health_120.grab_focus()
			arena.hud._panel_scroll.ensure_control_visible(control._confirm)
			await capture("choices-%d-font%d"%[resolution.x,roundi(scale*100)])
			control._confirm.pressed.emit()
			await capture("confirmation-%d-font%d"%[resolution.x,roundi(scale*100)])
			arena.hud._encounter_dialog.canceled.emit()
	root.size=Vector2i(1280,720)
	print("ENCOUNTER_NATIVE_MATRIX_COMPLETE")
