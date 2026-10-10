extends "res://tests/resistance_targeted_transactions_test.gd"
const Probe=preload("res://docs/qa/armour-targeted-reforge/capture_baseline.gd")
const Export=preload("res://tools/export_reference.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const OP="targeted_reforge_armour"
const QA="res://docs/qa/armour-targeted-reforge/"
func _initialize()->void:call_deferred("run")
func target_present(item:Dictionary)->bool:return item.affixes.any(func(a):return a.id=="ironhide")
func rule_checks()->void:
	var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(QA+"baseline.json"))
	check(Probe.fingerprints(baseline.operations)==baseline.fingerprints,"756 pre-edit existing craft plans retain exact typed results")
	var expected:Array=baseline.operations.duplicate();expected.append(OP)
	check(Craft.operation_ids()==expected and Rules.VERSION==61 and Gear.CURRENT_VOCABULARY==51,"Only append armour target; save61 and equipment51 unchanged")
	check(Craft.Targeted.TARGETS[OP].families==["ironhide"],"Only existing flat armour family selected")
	for base:String in Gear.all_base_ids():
		for rarity:String in ["magic","rare"]:
			var source:=Export._crafting_probe_instance(base,1,rarity)
			check(Craft.operation_quote(source,OP).ok==(base=="emberhide_vest"),"Exact eligible base/rarity: "+base+"/"+rarity)
	var tiers:Dictionary={};var counts:Dictionary={}
	for level:int in [1,7,8,15,16,30]:
		for rarity:String in ["magic","rare"]:
			var source:=Export._crafting_probe_instance("emberhide_vest",level,rarity)
			var original:=var_to_bytes(source)
			for roll:int in range(16):
				seed(717);var control:=randi();seed(717)
				var plan:=Craft.operation_plan(source,OP,roll)
				check(plan.ok and target_present(plan.instance) and Gear.validate_instance(plan.instance),"Valid target guarantee %s/%d/%d"%[rarity,level,roll])
				check(var_to_bytes(source)==original and randi()==control,"Planning preserves input and global RNG")
				check(plan.cost=={"calibration_shard":16 if rarity=="magic" else 40} and plan.instance.id==source.id and plan.instance.base_id==source.base_id and plan.instance.item_level==level and plan.instance.rarity==rarity,"Same item identity/level/rarity and exact fee")
				counts[str(plan.instance.affixes.size())]=true
				for a:Dictionary in plan.instance.affixes:
					if a.id=="ironhide":
						tiers[str(a.tier)]=true
						check(a.tier<=(1 if level<8 else 2 if level<16 else 3),"No tier bypass")
	check(tiers.size()==3 and counts.size()==5,"Witness all existing ironhide tiers and magic1-2/rare4-6 counts")
	var ordinary:=Export._crafting_probe_instance("emberhide_vest",1,"magic");ordinary.rarity="normal";ordinary.affixes=[]
	check(not Craft.operation_quote(ordinary,OP).ok,"Normal purchased base needs existing enchant first")
	var current:=Export._crafting_probe_instance("emberhide_vest",1,"magic")
	check(not Craft.Targeted.quote(current,OP,37).ok and Craft.Targeted.quote(current,OP,39).ok,"Historical vocabulary37 cannot acquire future ironhide;39 already can")
	report.rule_coverage={"old_plan_comparisons":756,"new_plans":192,"tiers":tiers.keys(),"counts":counts.keys()}
func transaction_checks()->void:
	for rarity:String in ["magic","rare"]:
		var cost:=16 if rarity=="magic" else 40
		var f:=fixture("emberhide_vest",rarity,"",cost)
		var model:FaultModel=f.model
		var before:=mark(f)
		var quote:=model.crafting_quote(OP,f.source.id,f.path)
		check(quote.ok and quote.cost=={"calibration_shard":cost},"Real exact-funds quote "+rarity)
		model.cancel_crafting_quote(quote.handle)
		check(not model.execute_crafting(quote.handle,f.source).ok,"Cancelled quote rejects")
		unchanged(f,before,"Cancel preserves item/money/disk")
		quote=model.crafting_quote(OP,f.source.id,f.path)
		model.fail_save=true
		check(not model.execute_crafting(quote.handle,f.source).ok,"Atomic write fault rejects")
		unchanged(f,before,"Write failure retains all ownership/currency/revisions",1)
		model.fail_save=false
		check(model.execute_crafting(quote.handle,f.source).ok,"Same quote retries after write failure")
		check(model.crafting_balance()==0 and target_present(model.item(f.source.id).payload) and model.successful_saves==before.saves+1,"One debit and one successful write with ironhide")
		var after:=mark(f)
		check(not model.execute_crafting(quote.handle,f.source).ok,"Duplicate confirmation rejects")
		unchanged(f,after,"No duplicate debit or new item")
		var old:Dictionary=bytes_to_var(before.state)
		for field:String in Rules.FIELDS:
			if field not in ["items","locations","revision","crafting"]:check(model.snapshot()[field]==old[field],"Preserve unrelated domain "+field)
		var reopened:=Model.new();check(reopened.load_build(f.path) and Planner._same_data(reopened.snapshot(),model.snapshot()),"Crafted same-UID item reloads")
		var poor:=fixture("emberhide_vest",rarity,"",cost-1);before=mark(poor)
		check(not poor.model.crafting_quote(OP,poor.source.id,poor.path).ok,"One shard short rejects "+rarity);unchanged(poor,before,"No partial fee")
	var f:=fixture("emberhide_vest","magic","",100);var quote:Dictionary=f.model.crafting_quote(OP,f.source.id,f.path)
	check(f.model.move_item(f.source.id,{"kind":"equipment","slot_id":"body_armour"},f.model.revision(),f.path).ok,"Equip source via original transaction")
	var before:=mark(f)
	check(not f.model.execute_crafting(quote.handle,f.source).ok and not f.model.crafting_quote(OP,f.source.id,f.path).ok,"Equipped and stale source rejected")
	unchanged(f,before,"Stale/equipped rejection preserves state")
	f=fixture("emberhide_vest","magic","",100);quote=f.model.crafting_quote(OP,f.source.id,f.path)
	var original_disk:=FileAccess.get_file_as_bytes(f.path)
	var file:=FileAccess.open(f.path,FileAccess.WRITE);file.store_buffer(original_disk)
	file.store_string("external-change");file.close()
	before=mark(f)
	check(not f.model.execute_crafting(quote.handle,f.source).ok,"External disk change rejected");unchanged(f,before,"External source preserved")
func purchase_ui_flow()->void:
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.size=Vector2i(1280,720);root.add_child(arena);await frames(3)
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	var model:Model=arena.state
	# Controlled real shard item, admitted through existing helper. Not a natural earning claim.
	arena._begin_progress_transaction()
	var admitted:=model._admit_reward_item(Items.calibration_shard("item_%06d"%model.snapshot().next_item_serial,32))
	arena._end_progress_transaction()
	check(admitted and arena.save_build(),"Legal physical32-shard fixture through original reward batching in actual formal town")
	var purchase:Dictionary=arena.normal_equipment_purchase_quote("emberhide_vest",model.revision())
	check(purchase.ok and arena.execute_normal_equipment_purchase(purchase.handle,"emberhide_vest").ok,"Actual formal merchant buys level1 normal vest for8")
	var uid:String=purchase.uid
	var quote:=model.crafting_quote("enchant",uid,arena.NORMAL_BUILD_PATH)
	check(quote.ok and model.execute_crafting(quote.handle,model.item(uid).payload).ok and model.crafting_balance()==16,"Original enchant spends8 and yields legal magic vest")
	var enchanted:Dictionary=model.item(uid).payload.duplicate(true)
	while arena.hud.is_blocking():arena.hud.close_panel()
	arena.hud.open_panel("inventory");await frames()
	var panel:Control=arena.hud._inventory_panel;panel._select_item(uid);await frames()
	var controls:Control=panel._craft_controls;var index:=-1
	for i:int in range(controls._target_select.item_count):
		if controls._target_select.get_item_metadata(i)==OP:index=i
	check(index>=0,"Actual current inventory discovers armour target")
	if index<0:arena.queue_free();return
	controls._target_select.select(index);controls._target_select.item_selected.emit(index)
	check(not controls._target_button.disabled,"Actual paid target button enabled")
	var before:=model.snapshot();var disk:=FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	await request_craft(panel)
	var dialog:String=panel._craft_dialog.dialog_text
	check(panel._craft_dialog.visible and dialog.contains("护甲") and dialog.contains("16") and dialog.contains("全部原词缀将被替换") and dialog.contains("不保证高阶"),"Real confirmation discloses armour/price/replacement/risk")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(QA+"confirmation.png")==OK,"Capture native confirmation")
	panel._craft_dialog.get_cancel_button().pressed.emit();await frames()
	check(model.snapshot()==before and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==disk,"Actual cancel is inert")
	await request_craft(panel);var saves:int=model.successful_saves
	panel._craft_dialog.get_ok_button().pressed.emit();await frames()
	check(model.crafting_balance()==0 and model.successful_saves==saves+1 and target_present(model.item(uid).payload),"Actual UI confirm crafts same purchased UID and debits16 once")
	var crafted:Dictionary=model.item(uid).payload.duplicate(true);before=model.snapshot()
	panel._craft_dialog.confirmed.emit();await frames();check(model.snapshot()==before,"Repeated actual UI callback is inert")
	check(crafted.item_level==1 and crafted.affixes.filter(func(a):return a.id=="ironhide")[0].tier==1,"Merchant route cannot bypass level1 tier cap")
	check(model.equip(uid),"Equip actual purchased/enchant/reforged vest")
	await frames()
	var armour:float=model.get_stats().armour
	var expected:float=100.0*(1.0-minf(0.9,armour/(armour+500.0)))
	var settled:=Defense.incoming_source_hit({"physical":100.0},model.get_stats(),0.0,1000.0)
	check(armour>=30 and armour<=50 and is_equal_approx(settled.remaining_health,1000.0-expected),"Original armour formula uses crafted flat30-50 without unit mismatch")
	arena.shield=0.0;arena.health=arena._stats.max_health;arena.invulnerable=0.0
	var hp:float=arena.health
	check(arena.hit_player_components({"physical":20.0}),"Actual Main accepts physical source hit")
	check(is_equal_approx(arena.health,hp-20.0*(1.0-minf(0.9,armour/(armour+100.0)))),"Actual Main settlement consumes equipped crafted armour")
	var reopened:=Model.new();check(reopened.load_build(arena.NORMAL_BUILD_PATH) and reopened.get_stats()==model.get_stats(),"Equipped result reload keeps actual stats and schema61")
	report.purchase_ui={"source":enchanted,"crafted":crafted,"armour":armour,"physical100_after_armour":expected,"confirmation":dialog,"funding":"Controlled lawful32-shard item; actual merchant8, enchant8, target16. Not natural earning claim."}
	arena.queue_free();await frames()
	completed=true
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-armour-"):quit(78);return
	rule_checks();transaction_checks();completed=false;await purchase_ui_flow()
	check(completed,"Entire purchase/UI/equip/Main settlement section completed")
	report.checks=checks;report.failure_count=failures;report.display=DisplayServer.get_name();report.schema=Rules.VERSION
	FileAccess.open(OS.get_environment("ARMOUR_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("ARMOUR_TARGETED checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
