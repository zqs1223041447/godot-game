extends "res://tests/cleave_inward_test.gd"
var input_samples: Array=[]
var dash_group := ""
var dash_key := 0

func key_event(code: int, down: bool, repeated: bool=false) -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=code;event.keycode=code;event.pressed=down;event.echo=repeated
	Input.parse_input_event(event);Input.flush_buffered_events()

func mouse_event(direction: Vector2, down: bool) -> void:
	View.update_follow_camera(arena,arena.player_pos,arena.ARENA)
	var local: Vector2=View.world_to_screen(arena,arena.player_pos)+direction*160.0
	var native: Vector2=root.get_screen_transform()*local
	var motion:=InputEventMouseMotion.new();motion.position=native;motion.global_position=native
	Input.parse_input_event(motion)
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
	event.position=native;event.global_position=native;event.pressed=down
	Input.parse_input_event(event);Input.flush_buffered_events()

func reset_input_case() -> void:
	for code: int in [KEY_W,KEY_A,KEY_S,KEY_D,dash_key]:key_event(code,false)
	mouse_event(Vector2.UP,false)
	park();arena.player_pos=arena.ARENA.position+Vector2(600,1600)
	prep_actor(arena.enemies[0],arena.player_pos,5.0);arena.enemies[0].speed=0.0
	arena.player_facing=Vector2.UP;arena.auto_fire=false;arena.attack_timer=999.0
	ready_cast();arena.invulnerable=0.0

func press_dash(expected: Vector2, label: String) -> void:
	var start: Vector2=arena.player_pos
	var mana_before: float=arena.mana
	key_event(dash_key,true)
	check(arena.group_cooldown_remaining(dash_group)>0.0,"Real physical bound key invokes group cast: "+label)
	vector_near(arena.player_pos,expected,label)
	near(mana_before-arena.mana,12.0,"One real-key payment")
	near(arena.invulnerable,0.6,"Original protection grant")
	var saved:=spell_state();var endpoint: Vector2=arena.player_pos
	key_event(dash_key,true,true)
	check(spell_state()==saved and arena.player_pos==endpoint,"Key-repeat echo never casts again")
	key_event(dash_key,false)
	input_samples.append({"label":label,"start":start,"end":arena.player_pos,"movement":Input.get_vector("move_left","move_right","move_up","move_down"),"mouse_held":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"facing":arena.player_facing})

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-aim-input-") or not OS.get_user_data_dir().begins_with(isolated+"/") or FileAccess.file_exists("user://build_save.json"):quit(78);return
	var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/v094-integration/owned-fixture.json"));file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	for group: Dictionary in arena.state.snapshot().skill_groups:
		if arena.state.skill_group(group.id).skill_id=="dash":dash_group=group.id
	for binding: Dictionary in arena.state.snapshot().bindings:
		if binding.group_id==dash_group:dash_key=int(binding.keycode)
	check(not dash_group.is_empty() and dash_key>0,"Use actual saved dash binding")
	if not enter("old_garden"):await finish();return
	reset_input_case();press_dash(arena.player_pos+Vector2(0,-175),"Idle keys and overlap retain original up heading")
	reset_input_case();mouse_event(Vector2.RIGHT,true)
	check(arena._aim_direction().dot(Vector2.RIGHT)>0.999,"Actual held mouse establishes right aim")
	press_dash(arena.player_pos+Vector2(175,0),"Mouse determines idle-input dash")
	reset_input_case();mouse_event(Vector2.UP,true);key_event(KEY_D,true)
	check(Input.is_action_pressed("move_right"),"Physical D maps into original move action")
	var start: Vector2=arena.player_pos
	arena.tick(1.0/60.0)
	check(arena.player_pos.x>start.x and is_equal_approx(arena.player_pos.y,start.y),"Held key moves through actual Main tick")
	arena.enemies[0].pos=arena.player_pos
	press_dash(arena.player_pos+Vector2(175,0),"Moving right overrides upward mouse for dash")
	reset_input_case();key_event(KEY_W,true);key_event(KEY_D,true)
	var expected: Vector2=arena.player_pos+Vector2(1,-1).normalized()*175.0
	press_dash(expected,"Diagonal physical keys retain normalized dash distance")
	reset_input_case()
	if not return_to_town("Input checks retain original build") or not enter("broken_ruins"):await finish();return
	reset_input_case()
	var wall: Rect2=arena.world_geometry().walls[0]
	arena.player_pos=Vector2(wall.position.x-50,wall.get_center().y);arena.enemies[0].pos=arena.player_pos
	mouse_event(Vector2.UP,true);key_event(KEY_D,true)
	start=arena.player_pos
	arena.tick(1.0/60.0);arena.enemies[0].pos=arena.player_pos
	var expected_end: Vector2=arena._geometry.move(arena.player_pos,arena.player_pos+Vector2(175,0),arena.PLAYER_RADIUS)
	press_dash(expected_end,"Real held-key dash uses authoritative wall endpoint")
	check(arena.player_pos.x>start.x and arena.player_pos.x<=wall.position.x-arena.PLAYER_RADIUS and arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS),"Input-driven endpoint remains clear on original wall side")
	key_event(KEY_D,false);mouse_event(Vector2.UP,false)
	check(Input.get_vector("move_left","move_right","move_up","move_down")==Vector2.ZERO and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"All actual held inputs release")
	await finish()

func finish() -> void:
	for code: int in [KEY_W,KEY_A,KEY_S,KEY_D,dash_key]:key_event(code,false)
	if is_instance_valid(arena):mouse_event(Vector2.UP,false)
	FileAccess.open(OS.get_environment("INPUT_REPORT"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"labels":labels,"dash_group":dash_group,"dash_key":dash_key,"samples":input_samples},"\t",true,true)+"\n")
	print("AIM_INPUT_FLOW checks=%d failures=%d"%[checks,failures])
	if is_instance_valid(arena):arena.queue_free();await process_frame
	quit(1 if failures else 0)
