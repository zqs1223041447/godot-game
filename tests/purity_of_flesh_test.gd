extends "res://tests/attack_elemental_passive_migration_test.gd"
## Bounded source-policy, real allocation, item stacking and actual-Main checks.
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Locale = preload("res://scripts/passives/source_tree_localization.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const RingFixture = preload("res://tests/chaos_resistance_equipment_test.gd")
const QA = "res://docs/qa/purity-of-flesh/"
const TARGET = "58218"
const ENTRY = "+8% to Chaos Resistance"
const ROUTE = ["61525","63965","14151","27564","17735","58402","6764","14057","9386","5743",TARGET]
const SAVE = "user://build_save.json"
var evidence: Array = []
var arena: Node
var panel: Control
func check(ok: bool, label: String) -> void:
	evidence.append({"label":label,"ok":ok}); super.check(ok,label)
func close(actual: float, wanted: float, label: String) -> void: check(is_equal_approx(actual,wanted),label)
func clean(value: Variant) -> Variant: return JSON.parse_string(JSON.stringify(value,"",true,true))
func prefix() -> Dictionary:
	var source := Rules.decode_v59(JSON.parse_string(FileAccess.get_file_as_string(QA+"schema59-town.json")))
	source.version=Rules.VERSION
	return source
func selected() -> Dictionary:
	var result:=prefix();result.talents.allocated.append(TARGET);result.talents.normal_points-=1
	check(Rules.reason(result).is_empty(),"Full canonical validation of legal ten-point Templar build")
	return result
func source_checks() -> void:
	var oracle:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(QA+"schema59-oracle.json"))
	var effects:Dictionary={};var changed:Array=[]
	for id:String in Source.Data.nodes():
		var node:=Source.Data.node(id)
		if node.type=="mastery":
			for effect:Dictionary in node.mastery_effects:
				var old:=Source.node_effect(id,int(effect.effect),59);effects[id+":"+str(effect.effect)]=old
				if old!=Source.node_effect(id,int(effect.effect),60):changed.append(id)
		else:
			var old:=Source.node_effect(id,0,59);effects[id+":0"]=old
			if old!=Source.node_effect(id,0,60):changed.append(id)
	check(effects.size()==oracle.effects_count and JSON.stringify(clean(effects),"",true,true).sha256_text()==oracle.effects_policy59_sha256,"Complete pre-edit59 source effect fingerprint preserved")
	check(changed==[TARGET],"Only original58218 changes; every other node/mastery policy preserved")
	check(Source.node_effect(TARGET).status=="full" and Source.node_effect(TARGET).grants==[{"stat":"max_shield","value":0.08,"mode":"increased"},{"stat":"max_health","value":0.1,"mode":"increased"},{"stat":"chaos_resistance","value":0.08,"mode":"flat"}],"All three exact original effects are available together")
	for version:int in [19,55,58,59]:check(Source.node_effect(TARGET,0,version).status=="partial","Historical policy still rejects full allocation: %d"%version)
	for line:String in [ENTRY+"."," "+ENTRY,ENTRY+"\n","+13% to Chaos Resistance","+8% to maximum Chaos Resistance","Minions have "+ENTRY,ENTRY+" while on Low Life"]:check(not Source.line_effect(line).supported,"No unrelated amount, conditional, minion, cap or malformed wording admitted: "+line)
	check(not Source.Patterns.parse_line(ENTRY,false).supported,"Historical parser gate remains closed")
	var metadata:=Defense.chaos_resistance_metadata()
	check(metadata.description.contains("58218") and metadata.unsupported.has("other_source_talent_grants") and metadata.unsupported.has("maximum_chaos_resistance_add"),"Defense metadata names narrow real source support without opening other talents or caps")
	check(Locale.node_name(TARGET)=="纯净的血肉" and Locale.line_status(ENTRY).implemented and not Locale.display_line(ENTRY).contains(Locale.NOT_IMPLEMENTED),"Consumer-backed Chinese source line is implemented")
	for index:int in range(1,ROUTE.size()):check(Source.Data.adjacency(ROUTE[index-1]).has(ROUTE[index]),"Real source route edge: "+ROUTE[index])
	var before:=Game._stats_for(prefix())
	check(clean(before)==oracle.stats and not before.has("chaos_resistance"),"Unselected current build preserves pre-edit stats and no-source field shape")
	var packets:Array=[{"chaos":100.0},{"chaos":100.0,"physical":50.0,"fire":30.0},{"physical":50.0,"cold":30.0}]
	for index:int in range(packets.size()):check(clean(Defense.incoming_source_hit(packets[index],before,40.0,50.0))==oracle.hits[index],"Unselected actual defense matches pre-edit oracle")
func arithmetic_checks() -> void:
	var source:=selected();var before:=Game._stats_for(prefix());var stats:=Game._stats_for(source)
	close(stats.chaos_resistance,0.08,"Eight resistance percentage points compiled once")
	# Derive additive capacity gains from the real source/gear build with existing increases removed.
	var raw:=Game.Legacy.BASE_STATS.duplicate(true)
	raw.merge({"max_health":100.0,"max_mana":50.0,"max_shield":100.0,"strength":0.0,"intelligence":0.0,"dexterity":0.0},true)
	var base_source:=source.duplicate(true);base_source.talents.allocated=[ROUTE[0]]
	var base_stats:=Source.apply_stats(raw,base_source)
	var pure_source:=base_source.duplicate(true);pure_source.talents.allocated.append(TARGET)
	var exact:=Source.apply_stats(raw,pure_source)
	close(exact.max_health,base_stats.max_health*1.10,"Life percentage is additive in existing capacity stage")
	# Class Intelligence already adds shield increases, so +8% is on flat shield, not final capacity.
	close(exact.max_shield-base_stats.max_shield,8.0,"Shield +8% adds to existing Intelligence contribution, never multiplies final shield")
	check(stats.max_health>before.max_health and stats.max_shield>before.max_shield,"Fully legal actual build gains both existing capacities")
	var hit:=Defense.incoming_source_hit({"chaos":100.0},stats,40.0,100.0)
	check(hit.damage_total==92.0 and hit.shield_spent==40.0 and hit.health_lost==52.0,"100 chaos becomes92 and uses original shield-first settlement")
	for amount:float in [0.70,0.80]:
		raw.chaos_resistance=amount
		var capped:=Source.apply_stats(raw,pure_source)
		close(capped.chaos_resistance,amount+0.08,"Raw source resistance stacks without premature cap")
		close(Defense.chaos_resistance_profile(capped).effective,0.75,"Existing75% effective cap remains authoritative")
		close(Defense.incoming_source_hit({"chaos":100.0},capped,0.0,100.0).damage_total,25.0,"Actual capped damage has no new maximum-resistance mechanism")
	var nonchaos:=Defense.incoming_source_hit({"physical":20.0,"fire":20.0},stats,10.0,100.0)
	var prior:=Defense.incoming_source_hit({"physical":20.0,"fire":20.0},before,10.0,100.0)
	# Full defense metadata honestly reports newly added chaos resistance even for a non-chaos packet.
	for result:Dictionary in [nonchaos,prior]:
		result.erase("raw_resistances");result.erase("effective_resistances")
	check(nonchaos==prior,"Same pools retain exact non-chaos settlement apart from full resistance metadata")
func settle() -> void: await process_frame; await process_frame
func click(button:Button) -> void:
	var scroll:ScrollContainer=button.get_parent().get_parent();scroll.ensure_control_visible(button);await settle()
	var motion:=InputEventMouseMotion.new();motion.position=button.get_global_rect().get_center();Input.parse_input_event(motion)
	for down:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=motion.position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;Input.parse_input_event(event)
	await settle()
func capture(name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	var scroll:ScrollContainer=panel._detail.get_parent().get_parent();scroll.ensure_control_visible(panel._allocate);await settle();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OS.get_environment("PURITY_OUTPUT").path_join(name+".png"))==OK,"Native T screenshot: "+name)
func hit(arena_node:Node, expected_raw:float) -> void:
	arena_node.health=100.0;arena_node.shield=40.0;arena_node.invulnerable=0.0
	var state_before:Dictionary=arena_node.state.snapshot();var random_before:int=arena_node.rng.state
	check(arena_node.hit_player_components({"chaos":100.0},77,["hit"]),"Actual Main accepts non-evasion chaos packet")
	close(arena_node.incoming_damage_trace.back().damage_total,100.0*(1.0-expected_raw),"Actual Main settles compiled resistance")
	close(arena_node.health,140.0-100.0*(1.0-expected_raw),"Actual shield-first health result")
	check(arena_node.shield==0.0 and arena_node.state.snapshot()==state_before and arena_node.rng.state==random_before,"Hit changes combat pools only, no ownership, points, RNG or saving")
func live_checks() -> void:
	var game:=Game.new();var start:=prefix();start.talents.allocated=[ROUTE[0]];start.talents.normal_points=10
	check(Rules.reason(start).is_empty(),"Legal level6 ten-earned-point test fixture; no natural-progression claim")
	game._accept_memory(start);check(game.save_build(SAVE)==OK,"Save isolated formal fixture")
	arena=load("res://scenes/main.tscn").instantiate();arena.state=game;arena.build_save_path=SAVE;root.add_child(arena)
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;await settle()
	check(not game.allocate_passive(TARGET,0,game.revision(),SAVE).ok,"Disconnected target cannot be bought")
	for id:String in ROUTE.slice(1,-1):check(game.allocate_passive(id,0,game.revision(),SAVE).ok,"Real allocation pays each legal path point: "+id)
	check(game.snapshot().talents.allocated==ROUTE.slice(0,-1) and game.talent_points==1,"Nine real connected allocations leave one point")
	arena.hud.open_panel("talents");await settle();panel=arena.hud._passive_panel
	panel._tree.node_clicked.emit(TARGET,MOUSE_BUTTON_LEFT,false)
	panel._tree.pan=-Source.Data.node(TARGET).position*panel._tree.zoom;panel._tree.queue_redraw();await settle()
	check(not panel._allocate.disabled and panel._detail.text.contains("纯净的血肉") and not panel._detail.text.contains(Locale.NOT_IMPLEMENTED),"Native T presents complete original node and enables allocation")
	await capture("available")
	var before:=game.snapshot();var stats_before:=game.get_stats();var disk:=FileAccess.get_file_as_bytes(SAVE)
	check(DirAccess.make_dir_absolute(SAVE+".tmp")==OK,"Inject atomic allocation write fault")
	check(not game.allocate_passive(TARGET,0,game.revision(),SAVE).ok and game.snapshot()==before and game.get_stats()==stats_before and FileAccess.get_file_as_bytes(SAVE)==disk,"Failed write preserves entire build, stats, points and original file")
	check(DirAccess.remove_absolute(SAVE+".tmp")==OK,"Remove only isolated injected fault")
	arena.health=50.0;arena.shield=5.0
	var saves:int=game.successful_saves
	if DisplayServer.get_name()=="headless":panel._allocate.pressed.emit()
	else:await click(panel._allocate)
	check(game.talent_points==0 and game.snapshot().talents.allocated==ROUTE and game.successful_saves==saves+1,"Actual T button allocates target, pays one point and commits once")
	check(arena.health==50.0 and arena.shield==5.0 and arena._stats==game.get_stats(),"Capacity gain refreshes Main stats without free healing or shield refill")
	await capture("allocated")
	var reloaded:=Game.new();check(reloaded.load_build(SAVE) and reloaded.snapshot()==game.snapshot() and reloaded.get_stats()==game.get_stats() and reloaded.save_attempts==0,"Allocated current reload preserves full build without rewriting")
	check(not game.refund_passive("5743",game.revision(),SAVE).ok and game.talent_points==0,"Required path bridge cannot be refunded")
	hit(arena,0.08)
	# Existing legal equipment fixture, original item admission and equip transactions.
	var ring:=RingFixture.legal_ring("gear_%06d"%game.snapshot().next_item_serial)
	check(game._admit_reward_item(Store.Items.wrap_equipment(ring)) and game.equip(ring.id),"Existing legal25% chaos ring admitted and equipped through original commands")
	close(game.get_stats().chaos_resistance,0.33,"Equipped ring and actual passive sum to33%, not replace")
	hit(arena,0.33)
	var owned_before:=game.snapshot();var stats_with:=game.get_stats();disk=FileAccess.get_file_as_bytes(SAVE)
	arena.health=stats_with.max_health;arena.shield=stats_with.max_shield
	var pools_before:=[arena.health,arena.shield]
	check(arena.health>stats_before.max_health and arena.shield>stats_before.max_shield,"Real Main refund fixture starts above both lower post-refund caps")
	check(DirAccess.make_dir_absolute(SAVE+".tmp")==OK,"Inject atomic refund write fault")
	check(not game.refund_passive(TARGET,game.revision(),SAVE).ok and game.snapshot()==owned_before and game.get_stats()==stats_with and FileAccess.get_file_as_bytes(SAVE)==disk,"Failed refund keeps selected stats, points, ownership and disk")
	check([arena.health,arena.shield]==pools_before,"Failed refund leaves above-cap current pools untouched")
	check(DirAccess.remove_absolute(SAVE+".tmp")==OK,"Remove only isolated refund fault")
	await settle()
	check(not panel._refund.disabled,"Original deferred UI refresh enables selected leaf refund")
	saves=game.successful_saves
	if DisplayServer.get_name()=="headless":panel._refund.pressed.emit()
	else:await click(panel._refund)
	check(game.talent_points==1 and not game.snapshot().talents.allocated.has(TARGET) and game.successful_saves==saves+1,"Actual T refund returns one point and persists once")
	close(game.get_stats().chaos_resistance,0.25,"Refund removes exactly8%, retaining equipped source")
	check(arena.health==game.get_stats().max_health and arena.shield==game.get_stats().max_shield and arena.health<pools_before[0] and arena.shield<pools_before[1],"Real refund clamps Life and ES down to new caps without any healing")
	for field:String in Rules.FIELDS:
		if field not in ["revision","talents"]:check(game.snapshot()[field]==owned_before[field],"Refund leaves canonical domain unchanged: "+field)
	hit(arena,0.25)
	check(game.unequip("ring_1") and not game.get_stats().has("chaos_resistance"),"Removing final equipped source restores original no-resistance field shape")
	check(game.get_stats()==stats_before,"Allocation/refund/gear round trip restores original compiled stats")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-purity-"):quit(78);return
	source_checks();arithmetic_checks();await live_checks()
	var report:={"checks":checks,"failures":failures.size(),"failed_labels":failures,"evidence":evidence,"display":DisplayServer.get_name(),"fixture":"Legal level6 Templar ten-point source route; original starter gear and controlled existing25% ring. Actual canonical allocation/refund and Main hit path; no natural progression or frame-performance claim."}
	FileAccess.open(OS.get_environment("PURITY_OUTPUT").path_join("mechanism.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("PURITY_OF_FLESH checks=%d failures=%d"%[checks,failures.size()]);quit(1 if not failures.is_empty() else 0)
