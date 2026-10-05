extends SceneTree
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred('run')
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func near(a:float,b:float,label:String)->void:check(absf(a-b)<0.000001*maxf(1.0,absf(b)),label)
func kill(enemy:Dictionary)->void:
 enemy.spawn=0.0;arena._damage_enemy(enemy,1000000000.0,Color.WHITE)
func run()->void:
 if not OS.get_environment('XDG_DATA_HOME').begins_with('/tmp/godot-m1-'):quit(78);return
 arena=load('res://scenes/main.tscn').instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
 check(arena.state.snapshot().version==30 and arena.state.normal_journey().best_tiers.sunwell_terrace==0,'New default schema30 third-map progress')
 check(arena.save_build(),'Save isolated actual default')
 check(arena.craft_normal_map('sunwell_terrace',1,[],[],arena.map_draft().revision).ok,'Real normal map device crafts SunwellI')
 check(arena.start_map(arena.map_draft().revision).ok,'Real normal map starts')
 while arena.hud.is_blocking():arena.hud.close_panel()
 var geometry:Dictionary=arena.world_geometry();var marks:Dictionary=geometry.landmarks
 check(geometry.id=='sunwell_terrace' and geometry.obstacle_style=='spring_basin' and geometry.walls.size()==4,'New physical basin geometry reaches main')
 check(arena.enemies.is_empty() and arena.world_context().ordinary_target==36,'Dormant full36-root encounter')
 var before_roots:int=arena.state.normal_journey().normal_root_kills
 for camp_index:int in [2,0,1]:
  var camp:Dictionary=marks.camps[camp_index];arena.player_pos=camp.trigger_center;var before:int=arena.enemies.size();arena._update_map_spawning(0.0)
  check(arena.enemies.size()==before+12,'Whole camp12 admits in freely chosen order')
  for enemy:Dictionary in arena.enemies:
   if int(enemy.id)>before:check(enemy.spawn==0.6 and arena._geometry.is_clear(enemy.pos,enemy.radius),'New roots retain real birth warning and collision clearance')
 check(arena.enemies.size()==36 and arena._map_run.snapshot().admitted==36,'All three groups coexist rather than sequential queue')
 var count:int=arena.enemies.size();arena._update_map_spawning(0.0);check(arena.enemies.size()==count,'Repeated trigger does not spawn twice')
 arena._begin_progress_transaction()
 for e:Dictionary in arena.enemies.duplicate():kill(e)
 arena._end_progress_transaction()
 check(arena._map_run.snapshot().ordinary_kills==36 and arena.world_context().boss_phase=='ready','Only36 roots open boss landmark')
 arena.player_pos=marks.boss.trigger_center;arena._update_map_spawning(0.0)
 var boss:Dictionary={}
 for e:Dictionary in arena.enemies:
  if int(e.id)==arena._map_run.boss_id:boss=e
 check(not boss.is_empty() and boss.map_boss_attack_id=='sunwell_echo','Natural registered boss has unique paired attack')
 if boss.is_empty():arena.queue_free();await process_frame;quit(1);return
 for e:Dictionary in arena.enemies:
  if e.id!=boss.id:e.speed=0.0;e.attack_timer=1000.0;e.pos=arena.ARENA.position+Vector2(60,60)
 boss.spawn=0.0;boss.pos=marks.boss.center;boss.knockback=Vector2.ZERO;boss.attack_timer=0.0
 arena.player_pos=boss.pos+Vector2(60,0);var fixed:Vector2=arena.player_pos
 arena._stats.max_health=10000.0;arena._stats.max_shield=5000.0;arena._stats.life_regen=0.0;arena._stats.shield_recharge_rate=0.0;arena._stats.armour=0.0;arena._stats.evasion=0.0
 arena.health=10000.0;arena.shield=7.0;arena.invulnerable=0.0;arena._player_evasion_entropy=99.0
 arena.telegraphs.reset();arena.telegraph_trace.clear();arena.incoming_damage_trace.clear()
 var rng:int=arena.rng.state;arena._start_enemy_telegraphs();var attack:Dictionary=arena.telegraphs.state_for(boss.id)
 check(not attack.is_empty() and attack.center==fixed and attack.pulse_index==0 and attack.pulse_count==2 and arena.rng.state==rng,'Actual start locks player point without RNG')
 near(attack.profile.radius,85.0,'Actual fixed85 radius');near(attack.profile.windup_seconds,0.8,'Actual complete0.8 windup')
 var expected:float=0.0
 for value:float in attack.packet.base.values():expected+=value
 arena.player_pos=fixed+Vector2(0,150);arena.tick(0.8)
 var second:Dictionary=arena.telegraphs.state_for(boss.id)
 check(arena.telegraph_trace.size()==1 and not arena.telegraph_trace[0].inside and not arena.telegraph_trace[0].applied,'Walking away avoids first pulse')
 check(second.phase=='windup' and second.pulse_index==1 and second.center==fixed,'Second pulse warns same locked center')
 near(second.elapsed,0.0,'Second full warning restarts displayed age only')
 arena.player_pos=fixed;var before_health:float=arena.health;var before_shield:float=arena.shield;arena.tick(0.8)
 check(arena.telegraph_trace.size()==2 and arena.telegraph_trace[1].applied,'Returning early to old circle is struck by second pulse')
 near(before_shield-arena.shield+before_health-arena.health,expected,'Only one0.65D packet paid after first dodge')
 var recovering:Dictionary=arena.telegraphs.state_for(boss.id)
 check(recovering.phase=='recovery' and recovering.pulse_index==1 and recovering.center==fixed,'Recovery follows second pulse at same center')
 near(recovering.elapsed,0.8,'Recovery display keeps original renderer age contract')
 # One larger legal test step still uses two real event times and the shared0.32 immunity.
 arena.telegraphs.reset();arena.telegraph_trace.clear();arena.incoming_damage_trace.clear();boss.attack_timer=0.0;boss.pos=marks.boss.center;arena.player_pos=fixed;arena.invulnerable=0.0;arena._burn_immunity_until=arena.elapsed;arena.health=10000.0;arena.shield=1000.0
 arena._start_enemy_telegraphs();before_health=arena.health;before_shield=arena.shield;arena.tick(1.6)
 check(arena.telegraph_trace.size()==2 and arena.telegraph_trace[0].applied and arena.telegraph_trace[1].applied,'Both deadlines settle despite one outer timestep')
 near(before_shield-arena.shield+before_health-arena.health,expected*2.0,'Two packets use total1.3D budget')
 near(arena.invulnerable,0.32,'Latest actual pulse owns remaining immunity')
 # Kill during the second warning, before its deadline: real cancellation and reward ownership.
 arena.telegraphs.reset();arena.telegraph_trace.clear();boss.attack_timer=0.0;arena.invulnerable=0.0;arena._burn_immunity_until=arena.elapsed;arena.player_pos=fixed
 arena._start_enemy_telegraphs();arena.player_pos=fixed+Vector2(0,150);arena.tick(0.8)
 arena._begin_progress_transaction();kill(boss);arena._end_progress_transaction()
 check(arena.telegraphs.state_for(boss.id).is_empty(),'Actual boss death cancels outstanding second pulse')
 var old_count:int=arena.telegraph_trace.size();arena.tick(0.8);check(arena.telegraph_trace.size()==old_count,'Canceled pulse never settles later')
 var loops:=0
 while loops<8:
  loops+=1;arena._flush_monster_spawns();var living:=0;arena._begin_progress_transaction()
  for e:Dictionary in arena.enemies.duplicate():
   if e.health>0.0:living+=1;kill(e)
  arena._end_progress_transaction()
  if living==0 and arena.monster_runtime.queue.is_empty():break
 arena._check_map_complete()
 check(arena.world_context().mode=='map_complete' and arena._map_run.snapshot().complete,'Actual third map requires boss and all descendants dead')
 check(arena.state.normal_journey().normal_root_kills-before_roots==37,'Exactly36 camp roots plus boss earn progression')
 var journey:Dictionary=arena.state.normal_journey();check(journey.best_tiers.sunwell_terrace==1 and journey.pending_map_reward.shards==4,'Real completion unlocksII and records4-shard reward')
 arena._check_map_complete();check(arena.state.normal_journey()==journey,'Completion cannot settle twice')
 check(arena.return_to_town(arena.world_context().revision).ok,'Actual return to normal town')
 var balance:int=arena.state.crafting_balance();var claimed:Dictionary=arena.claim_normal_rewards(arena.world_context().revision)
 check(claimed.ok and claimed.claimed_shards==4 and arena.state.crafting_balance()==balance+4,'Existing physical currency receives actual map reward')
 print('SUNWELL_GAMEPLAY_COMPLETE checks=%d failures=%d'%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
