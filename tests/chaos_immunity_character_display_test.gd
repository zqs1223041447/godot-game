extends SceneTree
## Actual HUD character sheet, two legal canonical fixtures; no combat suite.
const Game=preload("res://scripts/canonical_game_state.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Character=preload("res://scripts/ui/canonical_character_panel.gd")
const RingFixture=preload("res://tests/chaos_resistance_equipment_test.gd")
const SAVE="user://build_save.json"
var checks:=0
var failures:Array[String]=[]
var rows:Array=[]
var signal_checks:=0
var signal_rows:Array=[]
var arena:Node
var model:RefCounted
var normal_life:float
var profile:Dictionary
var panel:Control
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func observation()->PackedByteArray:
	return var_to_bytes([model.snapshot(),FileAccess.get_file_as_bytes(SAVE),model.save_attempts,model.successful_saves,arena.health,arena.mana,arena.shield,arena.rng.state,arena.critical_runtime.checkpoint(),arena.flask_runtime.snapshot()])
func expected_normal()->Dictionary:
	return {"text":"%.0f%%" % (float(profile.effective)*100.0),"tooltip":"原始混沌抗性 %.1f%% · 当前上限 %.0f%%\n只降低混沌伤害；护盾仍按原规则先承伤。" % [float(profile.raw)*100.0,float(profile.cap)*100.0]}
func display_check(enabled:bool,label:String)->void:
	var original:=observation()
	panel.refresh()
	var text:String=panel._values.chaos_resistance.text
	var tooltip:String=panel._resistance_cards.chaos_resistance.tooltip_text
	check(panel._values.max_health.text==("1" if enabled else "%d" % roundi(normal_life)),label+": final Life ceiling")
	if enabled:
		check(text=="免疫" and tooltip.contains("混沌防护：最大生命为1，免疫混沌伤害。"),label+": explicit immunity and Life tradeoff")
		check(tooltip.contains("原始混沌抗性 %.1f%% · 当前上限 %.0f%%" % [float(profile.raw)*100.0,float(profile.cap)*100.0]),label+": existing raw resistance/cap retained")
		check(not tooltip.contains("护盾仍按原规则先承伤"),label+": no ordinary mitigation explanation on immune state")
	else:
		var old:=expected_normal()
		check(text==old.text and tooltip==old.tooltip,label+": exact old percentage and tooltip restored")
	check(model.get_chaos_resistance_profile()==profile,label+": resistance profile remains unchanged")
	check(observation()==original,label+": refresh observes without changing model, save, resources, RNG or flask state")
	rows.append({"case":label,"life_text":panel._values.max_health.text,"chaos_text":text,"tooltip":tooltip})
func open_character()->void:
	var original:=observation()
	arena.hud.open_panel("character")
	await process_frame
	panel=arena.hud._character_panel
	check(panel.is_visible_in_tree(),"Actual HUD character dock opens")
	check(observation()==original,"Opening/showing character dock has no resource or persistence side effect")
func transition(enabled:bool)->void:
	var before:Dictionary=model.snapshot();var saves:int=model.successful_saves
	var resources:Array=[arena.health,arena.mana,arena.shield]
	var result:Dictionary=model.allocate_passive("11455",0,model.revision(),SAVE) if enabled else model.refund_passive("11455",model.revision(),SAVE)
	check(result.ok,"Actual %s transaction" % ("allocation" if enabled else "refund"))
	var after:Dictionary=model.snapshot()
	var same:Dictionary=after.duplicate(true);same.talents=before.talents;same.revision=before.revision
	check(same==before and model.successful_saves==saves+1,"Model change/UI signal adds only the authorized talent/revision change and one save")
	check([arena.health,arena.mana,arena.shield]==resources,"Damaged below-one-Life fixture receives no resource mutation from transition/display")
func signal_display_check(enabled:bool,label:String)->void:
	# Direct reads only: never refresh before these assertions.
	var original:=observation()
	var text:String=panel._values.chaos_resistance.text
	var tooltip:String=panel._resistance_cards.chaos_resistance.tooltip_text
	var expected:=expected_normal()
	if enabled:
		expected={"text":"免疫","tooltip":"混沌防护：最大生命为1，免疫混沌伤害。\n原始混沌抗性 %.1f%% · 当前上限 %.0f%%" % [float(profile.raw)*100.0,float(profile.cap)*100.0]}
	check(text==expected.text and tooltip==expected.tooltip,label+": signal-driven exact label and tooltip")
	check(panel._values.max_health.text==("1" if enabled else "%d" % roundi(normal_life)),label+": signal-driven Life ceiling")
	check(observation()==original,label+": direct observation has no state or save side effects")
	signal_rows.append({"case":label,"life_text":panel._values.max_health.text,"chaos_text":text,"tooltip":tooltip})
func signal_flow(with_ring:bool)->void:
	var start_checks:=checks
	var counts:Array[int]=[0,0]
	model.changed.connect(func()->void:counts[0]+=1)
	panel.visibility_changed.connect(func()->void:counts[1]+=1)
	# Clear the HUD route, then show its existing dock directly. This isolates
	# real signals from open_panel/_build_character_dock's explicit refresh().
	arena.hud.close_panel()
	var dock:Control=arena.hud._dock_roots.left
	dock.show()
	await process_frame
	for hidden:bool in [false,true]:
		for enabled:bool in [true,false]:
			var label:String="ring=%s/hidden=%s/enabled=%s" % [with_ring,hidden,enabled]
			if hidden:
				dock.hide()
				await process_frame
			var generation:int=panel.refresh_generation
			var changed_count:int=counts[0]
			transition(enabled)
			await process_frame
			check(counts[0]==changed_count+1,label+": actual model.changed emitted once")
			if hidden:
				check(not panel.is_visible_in_tree() and panel.refresh_generation==generation,label+": hidden change defers refresh")
				var visible_count:int=counts[1]
				var original:=observation()
				dock.show()
				await process_frame
				check(counts[1]==visible_count+1,label+": inherited visibility_changed emitted on reopening")
				check(observation()==original,label+": signal-driven reopening has no state or save side effects")
			check(panel.is_visible_in_tree() and panel.refresh_generation>generation,label+": automatic refresh completed")
			signal_display_check(enabled,label)
	signal_checks+=checks-start_checks
func case_run(with_ring:bool)->void:
	var candidate:Dictionary=Rules.decode_v58(JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/chaos-inoculation/schema58-town.json")))
	candidate.version=59
	if with_ring:
		var uid: String="gear_%06d" % int(candidate.next_item_serial)
		candidate.items[uid]=Game.Items.wrap_equipment(RingFixture.legal_ring(uid))
		candidate.locations[uid]={"kind":"equipment","slot_id":"ring_1"};candidate.next_item_serial+=1
	var reason:String=Rules.reason(candidate)
	check(reason.is_empty(),"Explicit lawful Witch prefix fixture, existing 25%% ring=%s: %s" % [with_ring,reason])
	if not reason.is_empty():return
	FileAccess.open(SAVE,FileAccess.WRITE).store_string(JSON.stringify(candidate,"\t",true,true))
	model=Game.new();check(model.load_build(SAVE),"Load current59 fixture without migration")
	arena=load("res://scenes/main.tscn").instantiate();arena.state=model;arena.build_save_path=SAVE
	root.add_child(arena);arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	arena.health=0.5;arena.mana=8.0;arena.shield=9.0
	while arena.hud.is_blocking():arena.hud.close_panel()
	normal_life=model.get_stats().max_health;profile=model.get_chaos_resistance_profile()
	check(profile.effective==(0.25 if with_ring else 0.0),"Fixture supplies actual expected ordinary resistance")
	await open_character();display_check(false,"%s/unallocated" % with_ring)
	transition(true);display_check(true,"%s/allocated visible" % with_ring)
	transition(false);display_check(false,"%s/refunded visible" % with_ring)
	arena.hud.close_panel();check(not panel.is_visible_in_tree(),"HUD close hides character panel")
	var generation:int=panel.refresh_generation
	transition(true);check(panel.refresh_generation==generation,"Hidden allocation defers panel refresh")
	await open_character();display_check(true,"%s/reopened allocated" % with_ring)
	arena.hud.close_panel();generation=panel.refresh_generation
	transition(false);check(panel.refresh_generation==generation,"Hidden refund defers panel refresh")
	await open_character();display_check(false,"%s/reopened refunded" % with_ring)
	check(model.snapshot().version==59,"Display leaves schema59 unchanged")
	await signal_flow(with_ring)
	arena.queue_free();await process_frame;arena=null;panel=null;model=null
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-ci-display-"):quit(78);return
	check(Character.chaos_resistance_display({"ok":false},true).text=="—","Invalid resistance data keeps existing unavailable display")
	await case_run(false);await case_run(true)
	FileAccess.open(OS.get_environment("CI_DISPLAY_REPORT"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"original_checks":checks-signal_checks,"added_signal_checks":signal_checks,"failures":failures.size(),"failed_labels":failures,"rows":rows,"signal_rows":signal_rows},"\t")+"\n")
	print("CI_CHARACTER_DISPLAY checks=%d failures=%d" % [checks,failures.size()]);quit(1 if not failures.is_empty() else 0)
