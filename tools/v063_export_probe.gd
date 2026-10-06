extends SceneTree
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Model=preload("res://scripts/canonical_game_state.gd")
const Same=preload("res://scripts/items/crafting_transaction_planner.gd")
var output:=""
var rows:Array[Dictionary]=[]
var failures:=0
var completed:=false
var arena:Node
var evidence:Dictionary={}
func _initialize()->void:call_deferred("run")
func sha(b:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(b);return h.finish().hex_encode()
func check(ok:bool,label:String)->bool:
	rows.append({"ok":ok,"label":label})
	if not ok:failures+=1;push_error(label);report();quit(1)
	return ok
func report()->void:
	if output.is_empty():return
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify({"ok":completed and failures==0,"completed":completed,"checks":rows.size(),"failures":failures,"results":rows,"source_commit":OS.get_environment("V063_SOURCE"),"pck_sha256":sha(FileAccess.get_file_as_bytes(OS.get_environment("V063_MAIN_PACK"))),"evidence":evidence,"scope":"Same-PCK Linux small monster burn/resource/death flow, not a repeated timing or Windows hardware test"},"\t",true,true))
func run()->void:
	output=OS.get_environment("V063_PACK_QA")
	if output.is_empty() or OS.get_environment("V063_GOLDEN").is_empty() or not ProjectSettings.globalize_path("res://").is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v063-"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output);create_timer(25.0).timeout.connect(func():check(false,"Packed burn probe stalled"))
	var encoded:=FileAccess.get_file_as_bytes(OS.get_environment("V063_GOLDEN"))
	if not check(sha(encoded)==OS.get_environment("V063_GOLDEN_SHA256"),"Frozen baseline return vector bytes verified"):return
	var vectors:Variant=bytes_to_var(encoded)
	if not check(vectors is Array and vectors.size()==7,"Seven independent baseline vectors load"):return
	var rules:=Defense.new()
	for i:int in range(vectors.size()):
		var actual:Dictionary=rules.callv("incoming_burn",vectors[i].args)
		if not check(var_to_bytes(actual)==var_to_bytes(vectors[i].expected),"Packed full typed receipt exactly matches old vector "+str(i)):return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;arena.hud.close_panel()
	if not check(str(ProjectSettings.get_setting("application/config/version"))=="0.63.0" and arena.state.snapshot().version==39,"Actual version0.63 and unchanged schema39"):return
	var font:=load("res://assets/fonts/arena_sans.otf") as FontFile
	if not check(sha(font.data)==OS.get_environment("V063_PACK_FONT_SHA256"),"Packaged font bytes remain v62"):return
	if not check(arena.leave_normal_town(arena.world_context().revision).ok,"Existing actual practice entry"):return
	arena.enemies.clear();arena.projectiles.clear();arena.burn_runtime.reset();arena.burn_trace.clear();arena.feedback_runtime.reset();arena.kills=0;arena.reward_kills=0;arena.wave=1;arena.elapsed=0.0;arena.rng.seed=63063
	var enemy:Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(150,0),"ordinary","",[],true)
	if not check(not enemy.is_empty(),"Actual original reward-eligible monster admitted"):return
	enemy.spawn=0.0;enemy.health=10.0;enemy.max_health=10.0;enemy.shield=5.0;enemy.max_shield=5.0;enemy.resistances={"fire":0.25}
	if not check(arena.burn_runtime.apply("monster",int(enemy.id),71,20.0,1.0,0.0).ok,"Attach ordinary frozen fire burn"):return
	arena.elapsed=0.5;arena._begin_progress_transaction();arena._advance_monster_burn(enemy,0.5);arena._end_progress_transaction()
	if not check(enemy.shield==0.0 and enemy.health==7.5 and arena.burn_trace.size()==1,"First actual half-second consumes5shield then2.5health"):return
	var first:Dictionary=arena.burn_trace.back().settlement
	if not check(first.shield_spent==5.0 and first.health_lost==2.5 and first.overkill==0.0 and first.actor=="monster" and first.stage=="burning","Actual receipt reports exact shield/life/metadata"):return
	arena.elapsed=1.0;arena._begin_progress_transaction();arena._advance_monster_burn(enemy,1.0);arena._end_progress_transaction()
	if not check(enemy.health==0.0 and arena.reward_kills==1 and arena.kills==1 and arena.burn_runtime.status_for("monster",int(enemy.id)).is_empty(),"Original expiry/death settles exactly one legal root reward"):return
	var second:Dictionary=arena.burn_trace.back().settlement
	if not check(second.health_lost==7.5 and second.shield_spent==0.0 and second.remaining_health==0.0 and arena.total_damage==15.0,"Second actual segment keeps exact resource accounting"):return
	var before:=var_to_bytes([arena.state.snapshot(),arena.rng.state,arena.reward_kills,arena.total_damage]);arena._finish_enemy_death(enemy,false)
	if not check(before==var_to_bytes([arena.state.snapshot(),arena.rng.state,arena.reward_kills,arena.total_damage]),"Repeated death cannot repeat XP/reward or RNG"):return
	var overkill:Dictionary=Defense.incoming_burn(40.0,0.25,0.0,5.0,"monster")
	if not check(overkill.damage_total==30.0 and overkill.health_lost==5.0 and overkill.overkill==25.0,"Packed overkill never becomes actual health loss"):return
	if not check(arena.save_build(),"Existing state persists after actual burn reward"):return
	var loaded:=Model.new()
	if not check(loaded.load_build(arena.build_save_path) and Same._same_data(loaded.snapshot(),arena.state.snapshot()),"Unchanged schema and actual reward reload exactly"):return
	evidence={"first":first,"second":second,"overkill":overkill,"root_rewards":arena.reward_kills,"font_sha256":sha(font.data),"schema":39}
	completed=true;report();print("Packed v63 settlement probe: %d checks, %d failures"%[rows.size(),failures]);arena.queue_free();await process_frame;quit(0)
