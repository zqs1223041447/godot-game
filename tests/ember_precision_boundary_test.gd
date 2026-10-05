extends SceneTree
var checks:=0
var failures:=0
func _initialize()->void:call_deferred('run')
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func run()->void:
 if not OS.get_environment('XDG_DATA_HOME').begins_with('/tmp/godot-m1-'):quit(78);return
 var arena:Node=load('res://scenes/main.tscn').instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
 for life:float in [1e-20,1e-12,0.07,0.1]:
  arena.enemies.clear();arena.monster_runtime.reset();arena.burn_runtime.reset();arena._ember_deaths.clear();arena.elapsed=1000000.0;arena._world_mode='normal';arena.alive=true;arena.auto_fire=false;arena.player_pos=arena.ARENA.get_center()
  var source:Dictionary=arena._spawn_monster('brute',arena.player_pos+Vector2(50,0),'ordinary','',[],false)
  var receiver:Dictionary=arena._spawn_monster('brute',arena.player_pos+Vector2(100,0),'ordinary','',[],false)
  for e:Dictionary in [source,receiver]:e.spawn=0.0;e.shield=0.0;e.resistances.fire=0.0
  source.health=life;receiver.health=1000.0
  check(arena.burn_runtime.apply('monster',source.id,0,2.2,3.0,arena.elapsed,{'ember_generation':0,'ember_expiry':arena.elapsed+3.0}).ok,'Finite legal precision fixture')
  arena.elapsed+=0.5;arena._advance_monster_burns(arena.elapsed)
  var status:Dictionary=arena.burn_runtime.status_for('monster',receiver.id)
  check(source.health<=0.0 and source.death_processed,'Tiny-resource boundary terminates in one death')
  check(not status.is_empty() and status.provenance.ember_generation==1 and status.provenance.ember_expiry==1000003.0,'Positive one-clock-ULP boundary preserves absolute expiry')
  check(arena._ember_deaths.is_empty(),'No pending or looping transfer')
 print('EMBER_PRECISION_COMPLETE checks=%d failures=%d'%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
