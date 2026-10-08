extends "res://tests/attack_elemental_passive_test.gd"
## Reuse assertions and production imports; run only the bounded CI mechanism.
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Leech=preload("res://scripts/combat/leech_rules.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const QA="res://docs/qa/chaos-inoculation/"
const CI="11455"
const ENTRY="Maximum Life becomes 1, Immune to Chaos Damage"
const CI_ROUTE=["54447","57226","21678","32210","8948","27659","37671","27415","32710","49605","60440",CI]
const SAVE="user://build_save.json"
var evidence:Array=[]
func check(ok:bool,label:String)->void:
	evidence.append({"label":label,"ok":ok});super.check(ok,label)
func clean(value:Variant)->Variant:return JSON.parse_string(JSON.stringify(value,"",true,true))
func selected()->Dictionary:
	var candidate:Dictionary=Rules.decode_v58(JSON.parse_string(FileAccess.get_file_as_string(QA+"schema58-town.json")))
	candidate.version=59;candidate.talents.allocated.append(CI);candidate.talents.normal_points-=1
	check(Rules.reason(candidate).is_empty(),"Complete legal eleven-point Witch CI selection")
	return candidate
func source_checks()->void:
	var oracle:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(QA+"schema58-oracle.json"))
	var effects:Dictionary={};var changed:Array=[]
	for id:String in Source.Data.nodes():
		var node:Dictionary=Source.Data.node(id)
		if node.type=="mastery":
			for effect:Dictionary in node.mastery_effects:
				var old:=Source.node_effect(id,int(effect.effect),58)
				effects[id+":"+str(effect.effect)]=old
				if old!=Source.node_effect(id,int(effect.effect),59):changed.append(id)
		else:
			var old:=Source.node_effect(id,0,58);effects[id+":0"]=old
			if old!=Source.node_effect(id,0,59):changed.append(id)
	check(effects.size()==oracle.effects_count and JSON.stringify(clean(effects),"",true,true).sha256_text()==oracle.effects_policy58_sha256,"Complete frozen58 effect-policy fingerprint preserved")
	check(changed==[CI],"Only existing11455 changes execution; all other nodes/masteries frozen")
	check(Source.lines_for(CI)==[ENTRY] and Source.node_effect(CI).grants==[{"stat":"chaos_inoculation","value":1.0,"mode":"flat"}],"Complete exact original source sentence grants one mechanism")
	for version:int in [19,41,57,58]:check(Source.node_effect(CI,0,version).status=="unsupported","Old policy rejects CI: %d"%version)
	for line:String in [ENTRY+"."," "+ENTRY,ENTRY+"\n","Maximum Life becomes 1","Immune to Chaos Damage"]:check(not Source.line_effect(line).supported,"No partial/variant wording admission")
	check(not Patterns.parse_line(ENTRY,false).supported,"Disabled historical vocabulary cannot open CI")
	check(Locale.node_name(CI)=="混沌防护" and Locale.line_status(ENTRY).implemented and not Locale.display_line(ENTRY).contains(Locale.NOT_IMPLEMENTED),"Original Chinese and consumer-backed implementation status")
	for index:int in range(1,CI_ROUTE.size()):check(Source.Data.adjacency(CI_ROUTE[index-1]).has(CI_ROUTE[index]),"Actual Witch route edge")
func arithmetic_checks()->void:
	var candidate:=selected();var off:=candidate.duplicate(true);off.talents.allocated.pop_back();off.talents.normal_points+=1
	var before:=Game._stats_for(off);var stats:=Game._stats_for(candidate)
	close(stats.max_health,1.0,"All native/equipment/Strength capacity contributions overridden last")
	var projected:=stats.duplicate(true);projected.erase("chaos_inoculation");projected.max_health=before.max_health
	check(projected==before,"Inactive zero-regeneration fixture changes only life capacity and CI flag")
	var oracle:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(QA+"schema58-oracle.json"))
	check(clean(before)==oracle.stats,"Unselected59 stats equal original58 production bytes")
	var packets:Array=[{"chaos":100.0},{"chaos":100.0,"physical":50.0,"fire":30.0},{"physical":50.0,"cold":30.0}]
	for index:int in range(packets.size()):check(clean(Defense.incoming_source_hit(packets[index],before,40.0,50.0))==oracle.hits[index],"Unselected hit matches exact frozen58 oracle")
	for shield:float in [0.0,0.25,50.0]:
		var pure:=Defense.incoming_source_hit({"chaos":100.0},stats,shield,1.0,"player",0.15,5.0,0.4)
		check(pure.ok and pure.damage_total==0.0 and pure.remaining_shield==shield and pure.remaining_health==1.0 and pure.remaining_mana==5.0,"Pure chaos consumes no shield/mana/life even under shock")
		check(pure.raw_components.chaos==100.0 and pure.mitigated_components.chaos==100.0 and pure.details[0].chaos_immune and pure.details[0].resistance==0.0,"Explicit immunity retains raw amount and honest resistance")
	var defense:=stats.duplicate(true);defense.chaos_resistance=10.0;defense.fire_resistance=0.5;defense.armour=100.0
	close(Defense.source_profile(defense).effective_resistances.chaos,0.75,"CI does not alter resistance cap")
	var mixed:=Defense.incoming_source_hit({"chaos":100.0,"physical":2.0,"fire":2.0},defense,0.5,1.0,"player",0.15,5.0,0.4)
	var ordinary:=Defense.incoming_source_hit({"physical":2.0,"fire":2.0},defense,0.5,1.0,"player",0.15,5.0,0.4)
	for key:String in ["damage_total","shield_spent","health_lost","mana_spent","remaining_shield","remaining_health","remaining_mana","overkill"]:close(mixed[key],ordinary[key],"Mixed non-chaos components retain armour/resistance/shock/shield/mana order: "+key)
	check(mixed.raw_components.chaos==100.0 and mixed.components.chaos==0.0,"Mixed raw chaos retained with zero settled component")
	var without:=defense.duplicate(true);without.erase("chaos_inoculation")
	var nonchaos:=Defense.incoming_source_hit({"physical":2.0,"cold":2.0},defense,0.0,1.0)
	nonchaos.erase("chaos_immune")
	check(nonchaos==Defense.incoming_source_hit({"physical":2.0,"cold":2.0},without,0.0,1.0),"Physical/elemental settlement completely unchanged")
	var old_chaos:=Defense.incoming_source_hit({"chaos":4.0},without,10.0,1.0)
	check(old_chaos.remaining_shield==9.0 and old_chaos.remaining_health==1.0,"Unselected chaos retains original shield-first rule, no bypass")
	for bad:Variant in [true,-1.0,0.5,NAN,INF]:
		var invalid:=stats.duplicate(true);invalid.chaos_inoculation=bad
		check(not Defense.incoming_source_hit({"chaos":10.0},invalid,10.0,1.0).ok,"Invalid CI flags fail without hiding malformed stats")
	check(not Defense.incoming_source_hit({"chaos":NAN},stats,10.0,1.0).ok,"Immunity cannot launder non-finite damage")
	var raw:=Game.Legacy.BASE_STATS.duplicate(true);raw.max_health=1000.0;raw.life_regen=10.0;raw.life_regen_percent=0.2
	var recovered:=Source.apply_stats(raw,candidate)
	close(recovered.life_regen,10.2,"Percentage Life regeneration reads final one Life; flat supply unchanged")
	raw.zealots_oath=1.0;recovered=Source.apply_stats(raw,candidate)
	check(recovered.life_regen==0.0 and is_equal_approx(recovered.shield_regeneration_rate,10.0+0.2*recovered.max_shield),"Existing Zealot redirection reads shield capacity, not one Life")
	var leech:=Leech.profile(stats)
	check(leech.ok and is_equal_approx(leech.health.instance_amount_cap,0.1) and is_equal_approx(leech.health.total_rate_cap,0.2),"Existing Life leech caps use one Life; no shield leech added")
	check(Leech.RESOURCE_KEYS==["health","mana"],"Ghost Reaver/extra resource system remains absent")
func resources(arena:Node)->Array:return [arena.health,arena.mana,arena.shield,arena.invulnerable,arena.damage_delay,arena._player_evasion_entropy,arena.rng.state]
func joined_candidate(targets:Array)->Dictionary:
	var candidate:=selected()
	for target:String in targets:
		var queue:Array=candidate.talents.allocated.duplicate();var parents:Dictionary={}
		for id:String in queue:parents[id]=""
		var cursor:=0
		while cursor<queue.size() and not parents.has(target):
			var id:String=queue[cursor];cursor+=1
			for next:String in Source.Data.adjacency(id):
				if parents.has(next):continue
				var node:=Source.Data.node(next)
				if node.type in ["mastery","start"] or node.source.get("isProxy",false) or node.source.get("isBlighted",false) or Source.node_effect(next).status!="full":continue
				parents[next]=id;queue.append(next)
		check(parents.has(target),"Existing complete connected combination target: "+target)
		var path:Array=[];var at:String=target
		while not candidate.talents.allocated.has(at):path.push_front(at);at=parents[at]
		candidate.talents.allocated.append_array(path)
	candidate.progress.level=maxi(7,candidate.talents.allocated.size()-5)
	candidate.talents.normal_points=candidate.progress.level+4-(candidate.talents.allocated.size()-1)
	check(Rules.reason(candidate).is_empty(),"Combination uses only real nodes and full canonical point validation")
	return candidate
func actual_hits(arena:Node)->void:
	arena.health=1.0;arena.shield=5.0;arena.mana=10.0;arena.invulnerable=0.0;arena.damage_delay=2.0
	var previous:=resources(arena);var admissions:int=arena.attack_admission_trace.size()
	check(not arena.hit_player_components({"chaos":100.0},77,["hit","attack"]),"Pure immune hit retains existing zero-damage refusal")
	check(resources(arena)==previous and arena.attack_admission_trace.size()==admissions,"Immune hit does not alter RNG/entropy/resources/hurt window/recharge delay")
	check(arena.incoming_damage_trace.back().raw_components.chaos==100.0 and arena.incoming_damage_trace.back().damage_total==0.0,"Actual Main keeps pure immune original ledger")
	arena._world_mode="normal";arena.spawn_timer=10000.0;arena.wave=5
	var guard:Dictionary=arena._spawn_monster("chaos_guard",Vector2(600,300),"ordinary","",[])
	check(not guard.is_empty(),"Existing authored chaos guardian admitted")
	if not guard.is_empty():
		guard.spawn=0.0;guard.attack_timer=0.0;guard.exploration_awake=true;arena.player_pos=guard.pos+Vector2(40,0)
		arena._start_enemy_telegraphs();var started:Dictionary=arena.telegraphs.state_for(guard.id)
		check(not started.is_empty() and started.packet.base.keys()==["chaos"],"Real guardian telegraph carries existing pure-chaos packet")
		previous=resources(arena);arena._advance_enemy_telegraphs(1.0)
		check(resources(arena)==previous and not arena.telegraph_trace.back().applied,"Real telegraph cannot hurt immune player or interrupt recharge")
	arena.enemies.clear();arena.telegraphs.reset()
	arena.shield=0.25;arena.health=1.0;arena.invulnerable=0.0
	var expected:=Defense.incoming_source_hit({"chaos":100.0,"fire":0.5},arena._stats,0.25,1.0)
	check(arena.hit_player_components({"chaos":100.0,"fire":0.5},78,["hit"]),"Mixed packet retains real damage admission")
	close(arena.health,expected.remaining_health,"Mixed actual Main life matches ordinary remainder")
	check(arena.incoming_damage_trace.back().raw_components.chaos==100.0 and arena.invulnerable==0.32 and arena.damage_delay==arena._stats.shield_recharge_delay,"Only actual non-chaos injury triggers old hurt window/recharge reset")
	# Existing flask use and resource stage; no inventory or definition is invented.
	arena.health=0.4;arena.invulnerable=10.0;arena.shield=0.0
	var flask:Dictionary=arena.state.flask_slots()[0]
	var used:Dictionary=arena.flask_runtime.use(flask.uid,arena.health,1.0,arena._stats)
	check(used.ok,"Existing equipped Life flask starts below one Life")
	arena.tick(1.0/60.0)
	check(arena.health<=1.0 and arena.health>0.4,"Actual resource tick clamps existing flask recovery to one Life")
	check(not arena.flask_runtime.use(flask.uid,1.0,1.0,arena._stats).ok,"Full one-Life flask use refuses without phantom recovery")
	# Two bounded existing mechanisms, using complete connected legal builds.
	var selected_stats:Dictionary=arena._stats.duplicate(true)
	arena._stats=Game._stats_for(joined_candidate(["34098"]))
	arena.health=1.0;arena.shield=0.25;arena.mana=10.0;arena.invulnerable=0.0
	expected=Defense.incoming_source_hit({"chaos":100.0,"fire":0.75},arena._stats,0.25,1.0,"player",0.0,10.0,0.4)
	check(arena.hit_player_components({"chaos":100.0,"fire":0.75},79,["hit"]) and is_equal_approx(arena.mana,expected.remaining_mana) and is_equal_approx(arena.health,expected.remaining_health),"Actual legal CI/Mind over Matter build diverts only non-chaos remainder after shield")
	arena._stats=Game._stats_for(joined_candidate(["63425","32482"]))
	arena.flask_runtime.reset(arena.state.owned_flasks())
	arena.health=0.4;arena.shield=0.0;arena.damage_delay=2.0;arena.invulnerable=10.0
	var rate:float=arena._stats.shield_regeneration_rate
	check(rate>0.0 and arena._stats.max_health==1.0 and arena._stats.life_regen==0.0,"Legal CI/Zealot/percentage-regeneration build derives independent shield recovery")
	arena.tick(1.0/60.0)
	check(arena.health==0.4 and is_equal_approx(arena.shield,rate/60.0) and arena.damage_delay>0.0,"Actual resource phase regenerates shield during recharge delay without healing Life")
	arena._stats=selected_stats
	# Burn remains fire: neither CI nor chaos resistance silently removes it.
	arena.invulnerable=0.0;arena._burn_immunity_until=0.0;arena.health=1.0;arena.shield=0.0
	arena._settle_burn_segments([{"target_kind":"player","raw_amount":2.0,"raw_dps":2.0,"from_time":arena.elapsed,"to_time":arena.elapsed+1.0}])
	check(not arena.alive and arena.health==0.0,"Existing fire burn can still kill the one-Life player")
func transaction_checks()->void:
	var source:Dictionary=Rules.decode_v58(JSON.parse_string(FileAccess.get_file_as_string(QA+"schema58-town.json")))
	source.talents.allocated=["54447"];source.talents.normal_points=11
	check(Rules.reason_v58(source).is_empty(),"Legal level7 unspent Witch fixture before actual path purchases")
	FileAccess.open(SAVE,FileAccess.WRITE).store_string(JSON.stringify(source,"\t",true,true))
	var game:=Game.new();check(game.load_build(SAVE),"Actual schema58 profile loads through migration")
	var arena=load("res://scenes/main.tscn").instantiate();arena.state=game;arena.build_save_path=SAVE
	root.add_child(arena);arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	for id:String in CI_ROUTE.slice(1,-1):check(game.allocate_passive(id,0,game.revision(),SAVE).ok,"Actual paid connected prefix allocation: "+id)
	check(game.talent_points==1 and game.snapshot().talents.allocated==CI_ROUTE.slice(0,-1),"Ten real paid steps leave exactly one point")
	var panel:=PassivePanel.new();root.add_child(panel);panel.setup(game,SAVE);panel._node_clicked(CI,MOUSE_BUTTON_LEFT,false);panel._node_hovered(CI,Rect2())
	check(not panel._allocate.disabled and panel._detail.text.contains("混沌防护") and not panel._detail.text.contains(Locale.NOT_IMPLEMENTED),"Actual detail and allocation button expose full original Chinese mechanism")
	arena.health=0.6;var current_resources:=resources(arena);var before:=game.snapshot();var disk:=FileAccess.get_file_as_bytes(SAVE);var max_before:float=game.get_stats().max_health
	check(DirAccess.make_dir_absolute(SAVE+".tmp")==OK,"Inject allocation atomic write failure")
	check(not game.allocate_passive(CI,0,game.revision(),SAVE).ok and game.snapshot()==before and resources(arena)==current_resources and FileAccess.get_file_as_bytes(SAVE)==disk,"Failed allocation preserves points, resources, memory and disk")
	check(DirAccess.remove_absolute(SAVE+".tmp")==OK,"Remove only fixture fault")
	var saves:int=game.successful_saves;panel._allocate.pressed.emit()
	check(game.snapshot().talents.allocated==CI_ROUTE and game.talent_points==0 and game.successful_saves==saves+1,"Actual button pays eleventh route point and commits once")
	check(arena._stats.max_health==1.0 and arena.health==0.6,"Allocation clamps capacity without healing damaged Life")
	var after:=game.snapshot();var reopened:=Game.new()
	check(reopened.load_build(SAVE) and reopened.snapshot()==after and reopened.get_stats().max_health==1.0 and reopened.save_attempts==0,"Allocated59 reload preserves selection without rewriting")
	check(not game.refund_passive("60440",game.revision(),SAVE).ok and game.snapshot()==after,"Cannot remove the required bridge behind allocated keystone")
	actual_hits(arena)
	# New live fixture for refund; allocation/refund must never revive a dead actor.
	arena.alive=true;arena.health=0.4
	after=game.snapshot();disk=FileAccess.get_file_as_bytes(SAVE);current_resources=resources(arena)
	check(DirAccess.make_dir_absolute(SAVE+".tmp")==OK,"Inject refund write failure")
	check(not game.refund_passive(CI,game.revision(),SAVE).ok and game.snapshot()==after and resources(arena)==current_resources and FileAccess.get_file_as_bytes(SAVE)==disk,"Failed refund preserves CI, point count and current resources")
	check(DirAccess.remove_absolute(SAVE+".tmp")==OK,"Remove refund fixture fault")
	check(game.refund_passive(CI,game.revision(),SAVE).ok and game.talent_points==1 and arena._stats.max_health==max_before and arena.health==0.4,"Refund restores capacity/point, never grants free Life")
	arena.health=max_before-1.0
	check(game.allocate_passive(CI,0,game.revision(),SAVE).ok and arena.health==1.0 and arena._stats.max_health==1.0,"Allocation also clamps a living above-one-Life actor to exactly one")
	check(game.refund_passive(CI,game.revision(),SAVE).ok and arena.health==1.0 and arena._stats.max_health==max_before,"Refund from one Life restores only the ceiling")
	check(reopened.load_build(SAVE) and reopened.snapshot()==game.snapshot() and not reopened.get_stats().has("chaos_inoculation"),"Refunded profile reloads exact inactive state")
	panel.free();arena.free()
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-ci-"):quit(78);return
	source_checks();arithmetic_checks();transaction_checks()
	FileAccess.open(OS.get_environment("CI_REPORT"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"failed_labels":failures,"evidence":evidence},"\t")+"\n")
	print("CHAOS_INOCULATION checks=%d failures=%d"%[checks,failures.size()]);quit(1 if not failures.is_empty() else 0)
