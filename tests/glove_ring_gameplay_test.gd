extends "res://tests/precise_technique_gameplay_test.gd"
## v072 bounded consumers. Reuses proven Main cleanup/packet assertions only.
## Every gear fixture passes catalog + owned-state guards; v45 JSON is decoded
## by its historical authority before the exact v45→46 migration.
const Upgrade = preload("res://scripts/save/glove_ring_affix_migration.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Planner = preload("res://scripts/items/crafting_transaction_planner.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const Town = preload("res://scripts/town/town_catalog.gd")
const NEW_IDS = ["glove_accuracy", "ring_emberward", "ring_rimeward", "ring_stormward"]
const RING_IDS = ["nine_slot_prefix_vitality", "nine_slot_prefix_clarity", "nine_slot_prefix_aegis", "ring_emberward", "ring_rimeward", "ring_stormward"]
const GLOVE_IDS = ["nine_slot_prefix_vitality", "nine_slot_prefix_clarity", "glove_accuracy", "nine_slot_suffix_endurance", "nine_slot_suffix_mana_flow", "nine_slot_suffix_stride"]
const SIX_OPS = ["salvage", "recalibrate", "enchant", "elevate", "augment", "reforge"]
class FaultModel extends Model:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)
var serial := 0
var source46 := {}
var sources := {}
var output_fixtures := []
var active_section := ""

func section(test: Callable) -> bool:
	var before := checks
	completed = false
	active_section = test.get_method()
	test.call()
	if failures == 0: check(completed, "Section returned normally: " + active_section)
	sections[active_section] = checks - before
	return completed and failures == 0

func fresh_source(name: String = "selected-below") -> bool:
	if not sources.has(name):
		var path := "res://docs/qa/v070-gameplay/fixtures/" + name + ".json"
		var bytes := FileAccess.get_file_as_bytes(path)
		var old: Dictionary = Model.Rules.decode_v45(JSON.parse_string(bytes.get_string_from_utf8()))
		if not check(not old.is_empty() and Model.Rules.reason_v45(old).is_empty(), "Strict original45 source decodes: " + name): return false
		var migrated: Dictionary = Upgrade.migrate_v45(old)
		if not check(not migrated.is_empty() and Model.Rules.reason(migrated).is_empty(), "Strict version46 migration: " + name): return false
		var projected := migrated.duplicate(true); projected.version = 45
		if not check(projected == old and FileAccess.get_file_as_bytes(path) == bytes, "Migration changes only version; no gear/currency/points gifts and source45 bytes intact"): return false
		sources[name] = migrated
	serial += 1
	var model := Model.new(); model._accept_memory(sources[name].duplicate(true))
	var path := "user://glove-ring-main-%d.json" % serial
	if not check(model.save_build(path) == OK and model.pending_items().is_empty(), "Persist complete previously recovered source fixture"): return false
	arena._replace_build(model, path)
	groups.clear()
	for group: Dictionary in model.snapshot().skill_groups:
		var cast: Dictionary = model.get_group_cast(group.id)
		if cast.get("ok", false): groups[cast.skill_id] = group.id
	blade = str(model.equipped_items().weapon)
	clean()
	return check(groups.has("nova") and groups.has("cleave") and groups.has("tornado"), "Reused real owned skill groups")

func affix(id: String, tier: int = 3, value: int = -1) -> Dictionary:
	return {"id":id, "tier":tier, "value":int(Gear.affix_definition(id).tiers[tier-1].max) if value < 0 else value}
func gear_item(uid: String, base: String, rarity: String = "rare", ids: Array = [], accuracy_tier: int = 3, accuracy_value: int = 160) -> Dictionary:
	var rolls: Array = []
	for id: String in ids: rolls.append(affix(id, accuracy_tier, accuracy_value) if id == "glove_accuracy" else affix(id))
	return {"id":uid, "base_id":base, "rarity":rarity, "item_level":16, "affixes":rolls}
func admit(base: String, ids: Array, accuracy_tier: int = 3, accuracy_value: int = 160) -> String:
	var uid := "gear_%06d" % int(arena.state.snapshot().next_item_serial)
	var item := gear_item(uid, base, "rare", ids, accuracy_tier, accuracy_value)
	if not check(Gear.validate_instance(item) and arena.state._admit_reward_item(Items.wrap_equipment(item)), "Catalog and canonical ownership admit " + base): return ""
	return uid
func remove_slot(slot: String) -> bool:
	if not arena.state.equipped_items().has(slot): return true
	var uid: String = arena.state.equipped_items()[slot]
	var position: Dictionary = arena.state.first_bag_position(uid)
	return check(not position.is_empty(), "Available bag position for unequip") and accepted(arena.state.move_item(uid, position, arena.state.revision(), arena.build_save_path), "Guarded unequip " + slot)
func mist() -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster("mist_skitter", arena.player_pos + Vector2(40,0), "ordinary", "normal", [], false)
	if not check(not enemy.is_empty() and enemy.evasion == 1600.0, "Actual ordinary mist_skitter retains catalog evasion1600"): return {}
	enemy.spawn = 0.0; enemy.health = 10000.0; enemy.max_health = 10000.0; enemy.evasion_entropy = 0.0
	return enemy

func legal_source_setup() -> void:
	if not fresh_source(): return
	source46 = arena.state.snapshot()
	if not near(arena.state.get_stats().accuracy,284.0,"Original source final accuracy284") or not near(arena.state.get_stats().max_health,358.0,"Original source max-life358"): return
	if not check(Source.CURRENT_SAVE_VERSION == 45 and Model.Rules.VERSION == 46,"Save46 leaves source-effect policy45 unchanged"): return
	completed = true

func accuracy_and_precise() -> void:
	if not fresh_source(): return
	var baseline: Dictionary = arena.state.get_stats()
	var spell_before: Dictionary = arena.state.get_group_cast(groups.nova)
	var rows: Array = []
	for sample: Array in [[1,35,0.80],[1,60,0.82],[2,70,0.83],[2,110,0.86],[3,120,0.87],[3,160,0.89],[2,74,0.83]]:
		var uid := admit("nine_slot_threaded_gloves",GLOVE_IDS,int(sample[0]),int(sample[1]))
		if uid.is_empty() or not equip(uid,"gloves"): return
		var stats: Dictionary = arena.state.get_stats()
		if not near(stats.accuracy,284.0+float(sample[1]),"Flat glove accuracy added exactly once before source aggregate"): return
		if not near(stats.max_health,358.0,"Three-prefix glove preserves legal max-life358 comparison"): return
		for field: String in ["crit_base_chance","crit_base_multiplier"] + Model.Critical.STAT_KEYS:
			if not check(stats.has(field) and baseline.has(field) and stats[field] == baseline[field],"Glove does not change actual registered critical stat " + field): return
		clean(); var enemy := mist()
		if enemy.is_empty(): return
		var cast: Dictionary = arena.state.get_basic_cast()
		if not profile(cast,true,"Real glove condition" ): return
		if not near(Attack.chance(stats.accuracy,enemy.evasion),float(sample[2]),"Actual owned-gear vs real mist chance"): return
		for swing: int in range(2):
			arena.attack_timer = 0.0; arena.auto_fire = true; arena._update_auto_attack(); arena.auto_fire = false
		if not check(arena.attack_admission_trace.size()==2 and not arena.attack_admission_trace[0].hit and arena.attack_admission_trace[1].hit,"Actual Main misses then hits; accuracy grants no guaranteed admission"): return
		for row: Dictionary in arena.attack_admission_trace:
			if not near(row.chance,float(sample[2]),"Main attack admission uses compiled final accuracy"): return
		if not check(arena.damage_trace.size()==1,"Exactly one admitted actual basic hit"): return
		assert_hit(arena.damage_trace[0],cast.packets.direct,cast.snapshot,"Glove-gated actual basic")
		if failures: return
		clean(); enemy = mist()
		if enemy.is_empty(): return
		var spell: Dictionary = arena.state.get_group_cast(groups.nova)
		if not profile(spell,false,"Glove never makes spell eligible for attack MORE"): return
		if not check(expected_raw(spell.packets.direct,spell.snapshot)==expected_raw(spell_before.packets.direct,spell_before.snapshot),"Spell damage unchanged across actual accuracy threshold"): return
		if not check(arena.cast_group(groups.nova) and arena.damage_trace.size()==1 and arena.attack_admission_trace.is_empty(),"Actual spell hits real mist without accuracy admission"): return
		assert_hit(arena.damage_trace[0],spell.packets.direct,spell.snapshot,"Actual unchanged spell")
		if failures: return
		rows.append({"tier":sample[0],"roll":sample[1],"accuracy":stats.accuracy,"max_health":stats.max_health,"chance":sample[2],"precise":cast.precise_technique_profile})
		if int(sample[1])==74 and not export_fixture("precise-equal"): return
		if int(sample[1])==160 and not export_fixture("precise-above"): return
	report.accuracy_matrix = rows
	completed = true

func finesse_aggregate() -> void:
	if not fresh_source(): return
	var candidate: Dictionary = arena.state.snapshot()
	candidate.progress = {"level":5,"xp":0}; candidate.talents.normal_points = 1; candidate.revision += 1
	if not check(Model.Rules.reason(candidate).is_empty(),"Lawful earned ninth point at level5"): return
	if not accepted(arena.state._commit(candidate,arena.build_save_path),"Commit legal level5 point budget"): return
	if not check(arena.state.available_passives().has("54142"),"Real Finesse adjacent to existing route61306"): return
	if not accepted(arena.state.allocate_passive("54142",0,arena.state.revision(),arena.build_save_path),"Spend real point on Finesse"): return
	var before: Dictionary = arena.state.get_stats()
	if not near(before.accuracy_increased,0.15,"Existing Finesse adds15percent global increased") or not near(before.dexterity,112.0,"Existing Finesse adds20Dexterity"): return
	var uid := admit("nine_slot_threaded_gloves",GLOVE_IDS)
	if uid.is_empty() or not equip(uid,"gloves"): return
	var stats: Dictionary = arena.state.get_stats()
	if not near(stats.accuracy,(100.0+160.0+2.0*112.0)*1.15,"Full final accuracy uses one aggregate flat-then-increased stage"): return
	if not near(stats.accuracy-before.accuracy,160.0*1.15,"Glove flat receives Finesse exactly once"): return
	if not profile(arena.state.get_basic_cast(),true,"Finesse uses final accuracy for Precise"): return
	if not export_fixture("glove-finesse"): return
	report.finesse = {"before":before.accuracy,"after":stats.accuracy,"increased":stats.accuracy_increased,"route":arena.state.snapshot().talents.allocated}
	completed = true

func triple_rings_and_caps() -> void:
	if not fresh_source("refunded"): return
	for slot: String in arena.state.equipped_items():
		if slot != "weapon" and not remove_slot(slot): return
	var uids: Array = []
	for slot: String in ["ring_1","ring_2"]:
		var uid := admit("nine_slot_etched_ring",RING_IDS)
		if uid.is_empty() or not equip(uid,slot): return
		uids.append(uid)
	var chest := admit("emberhide_vest",["rootwell","deepwell","lanternveil","emberward","rimeward","stormward"])
	if chest.is_empty() or not equip(chest,"body_armour"): return
	var profile_data: Dictionary = arena.state.get_resistance_profile()
	if not check(uids[0]!=uids[1] and arena.state.equipped_items().ring_1==uids[0] and arena.state.equipped_items().ring_2==uids[1],"Actual two ring slots own independent UIDs"): return
	for element: String in ["fire","cold","lightning"]:
		if not near(profile_data.raw_resistances[element],0.90 if element=="fire" else 0.75,"Actual two rings plus chest raw " + element): return
		if not near(profile_data.maximum_resistances[element],0.75,"Ring suffix never changes default maximum " + element): return
		if not near(profile_data.effective_resistances[element],0.75,"Default cap uses75percent " + element): return
		clean(); var hp: float = arena.health
		if not check(arena.hit_player_components({element:100.0},0,["hit","spell"]),"Actual incoming elemental hit"): return
		if not near(arena.health,hp-25.0,"Actual main life loses25 after ring resistance"): return
	var full: Dictionary = arena.state.item(uids[0]).payload
	var duplicate := full.duplicate(true); duplicate.affixes[4] = affix("ring_emberward")
	if not check(not Gear.validate_instance(duplicate),"Same resistance group cannot occupy two suffixes"): return
	var fourth := full.duplicate(true); fourth.affixes.append(affix("nine_slot_suffix_endurance"))
	if not check(not Gear.validate_instance(fourth),"Triple-resist ring spends all three suffix positions"): return
	var extra_glove := gear_item("gear_999998","nine_slot_threaded_gloves","rare",GLOVE_IDS)
	extra_glove.affixes.append(affix("nine_slot_prefix_aegis"))
	if not check(not Gear.validate_instance(extra_glove),"Accuracy uses one of three prefix positions"): return
	if not export_fixture("rings-triple-default"): return
	# Explicit cap-only consumer boundary: real gear raw values are preserved,
	# only cap inputs are controlled here. This is not an obtainable passive build.
	var bounded: Dictionary = arena.state.get_stats()
	for element: String in ["fire","cold","lightning"]: bounded["maximum_"+element+"_resistance_add"] = 0.08
	var cap_only: Dictionary = Model.Defense.resistance_profile(bounded)
	for element: String in ["fire","cold","lightning"]:
		if not near(cap_only.effective_resistances[element],0.83 if element=="fire" else 0.75,"83 maximum still requires enough raw " + element): return
	# Existing independently audited source route, admitted under the real state
	# guard, provides an obtainable all-element83 cap without editing derived stats.
	var witness: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v059-source/allocation-witness.json"))
	var candidate: Dictionary = arena.state.snapshot()
	candidate.progress={"level":69,"xp":0}; candidate.talents.class_id=1
	candidate.talents.allocated=witness.allocated.duplicate(); candidate.talents.masteries={}; candidate.talents.normal_points=0; candidate.revision+=1
	if not check(Model.Rules.reason(candidate).is_empty(),"Previously audited73-point cap route is valid with actual rings"): return
	if not accepted(arena.state._commit(candidate,arena.build_save_path),"Commit validated existing cap source route"): return
	var source_cap: Dictionary = arena.state.get_resistance_profile()
	for element: String in ["fire","cold","lightning"]:
		if not near(source_cap.maximum_resistances[element],0.83,"Real source cap83 " + element): return
		if not check(source_cap.raw_resistances[element]>=0.83,"Actual ring and source raw meet83 " + element): return
		clean(); var hp: float = arena.health
		if not check(arena.hit_player_components({element:100.0},0,["hit","spell"]),"Actual83-cap incoming hit"): return
		if not near(arena.health,hp-17.0,"Actual source and rings mitigate100 to17"): return
	if not export_fixture("rings-source-cap83"): return
	report.rings={"uids":uids,"default":profile_data,"cap_only_control":cap_only,"actual_source_cap":source_cap}
	completed=true

func transaction_mark(f: Dictionary) -> Dictionary:
	return {"state":var_to_bytes(f.model.snapshot()),"disk":FileAccess.get_file_as_bytes(f.path),"attempts":f.model.save_attempts,"saves":f.model.successful_saves}
func unchanged(f: Dictionary, before: Dictionary, label: String, extra_attempts: int = 0) -> bool:
	return check(var_to_bytes(f.model.snapshot())==before.state and FileAccess.get_file_as_bytes(f.path)==before.disk and f.model.save_attempts==before.attempts+extra_attempts and f.model.successful_saves==before.saves,label+": exact state/disk/save accounting atomic")
func has_new(item: Dictionary) -> bool:
	return item.affixes.any(func(a: Dictionary) -> bool: return NEW_IDS.has(a.id))
func craft_fixture(operation: String, base: String, funds: int = 200) -> Dictionary:
	serial+=1
	var model:=FaultModel.new(); model._accept_memory(source46.duplicate(true))
	var ids: Array = GLOVE_IDS if base.ends_with("gloves") else RING_IDS
	var rarity: String = "rare"
	if operation=="enchant": rarity="normal"; ids=[]
	elif operation in ["elevate","augment"]: rarity="magic"; ids=["glove_accuracy" if base.ends_with("gloves") else "ring_emberward"]
	var source:=gear_item("gear_%06d"%int(model.snapshot().next_item_serial),base,rarity,ids)
	if not check(Gear.validate_instance(source) and Craft.operation_quote(source,operation).ok,"Legal operation precondition "+base+" "+operation): return {}
	if not check(model._admit_reward_item(Items.wrap_equipment(source)),"Admit owned craft UID"): return {}
	if funds>0 and not check(model._admit_reward_item(Items.calibration_shard("item_%06d"%int(model.snapshot().next_item_serial),funds)),"Admit actual shard stack"): return {}
	if operation in ["enchant","reforge"]:
		var candidate:=model.snapshot(); var found:=false
		for revision: int in range(160):
			var seed_text:=JSON.stringify({"rules":Craft.seed_rules_version(operation),"revision":revision,"item":source},"",true,true)
			var plan:=Craft.operation_plan(source,operation,seed_text.sha256_text().substr(0,15).hex_to_int())
			if plan.ok and has_new(plan.instance): candidate.crafting.revision=revision; found=true; break
		if not check(found and Model.Rules.reason(candidate).is_empty(),"Lawful current-pool revision witness "+operation): return {}
		model._accept_memory(candidate)
	var path:="user://glove-ring-craft-%d.json"%serial
	if not check(model.save_build(path)==OK,"Persist complete current46 craft source"): return {}
	return {"model":model,"source":source,"path":path}

func six_crafts_and_metadata() -> void:
	var results: Array=[]
	for base: String in ["nine_slot_threaded_gloves","nine_slot_etched_ring"]:
		for operation: String in SIX_OPS:
			var f:=craft_fixture(operation,base)
			if f.is_empty(): return
			var model: FaultModel=f.model; var source: Dictionary=f.source
			var before:=transaction_mark(f); var original:=model.snapshot(); var balance:=model.crafting_balance()
			var economics:=Craft.operation_quote(source,operation)
			var metadata:=model.crafting_operations(source.id,f.path)
			if not check(metadata.size()==10 and model._craft_quotes.is_empty(),"Six original plus four targeted metadata, no extra action or issued handle"): return
			for row: Dictionary in metadata:
				var expected:=Craft.operation_quote(source,row.operation)
				if not check(row.available==expected.ok,"Metadata uses real rarity/family precondition "+row.operation): return
			if not unchanged(f,before,"Read-only metadata"): return
			var quote:=model.crafting_quote(operation,source.id,f.path)
			if not check(quote.ok and quote.cost==economics.cost and quote.materials==economics.materials,"Actual exact fee/yield quote"): return
			if not check(not quote.has("seed") and not quote.has("candidate") and not quote.has("instance"),"Quote does not expose future rolls"): return
			model.cancel_crafting_quote(quote.handle)
			if not check(not model.execute_crafting(quote.handle,source).ok,"Cancelled authority rejected") or not unchanged(f,before,"Cancel"): return
			quote=model.crafting_quote(operation,source.id,f.path)
			var wrong:=source.duplicate(true); wrong.item_level=17
			if not check(not model.execute_crafting(quote.handle,wrong).ok,"Changed selected source rejected") or not unchanged(f,before,"Source mismatch"): return
			var seed_text:=JSON.stringify({"rules":Craft.seed_rules_version(operation),"revision":original.crafting.revision,"item":source},"",true,true)
			var expected:=Craft.operation_plan(source,operation,seed_text.sha256_text().substr(0,15).hex_to_int())
			model.fail_save=true
			if not check(not model.execute_crafting(quote.handle,source).ok,"Failed write rejects entire craft") or not unchanged(f,before,"Injected write failure",1): return
			model.fail_save=false
			if not accepted(model.execute_crafting(quote.handle,source),"Same valid authority retry commits"): return
			var after:=model.snapshot()
			if not check(model.successful_saves==before.saves+1 and after.crafting.revision==original.crafting.revision+1 and after.revision==original.revision+1,"Exactly one successful atomic craft revision"): return
			if not check(model.crafting_balance()==balance-int(economics.cost.get(Craft.MATERIAL_ID,0))+int(economics.materials.get(Craft.MATERIAL_ID,0)),"Exact actual wallet debit or salvage credit"): return
			if operation=="salvage":
				if not check(model.item(source.id).is_empty() and model.location(source.id).is_empty(),"Salvage consumes only selected UID"): return
			else:
				var item: Dictionary=model.item(source.id).payload
				if not check(item==expected.instance and Gear.validate_instance(item) and model.location(source.id)==original.locations[source.id],"Exact seeded legal replacement preserves UID/base/location"): return
				if operation in ["enchant","reforge"] and not check(has_new(item),"Actual committed current-pool growth supplies new family"): return
				if operation in ["elevate","augment"] and not check(item.affixes[0]==source.affixes[0],"Growth preserves exact existing new affix"): return
				if operation=="recalibrate":
					for i: int in range(source.affixes.size()):
						if not check(item.affixes[i].id==source.affixes[i].id and item.affixes[i].tier==source.affixes[i].tier,"Calibration retains family/order/tier"): return
			for uid: String in original.items:
				if uid==source.id or original.items[uid].kind=="currency": continue
				if not check(after.items[uid]==original.items[uid] and after.locations[uid]==original.locations[uid],"Unrelated owned gear and locations unchanged"): return
			before=transaction_mark(f)
			if not check(not model.execute_crafting(quote.handle,source).ok,"Successful authority cannot replay") or not unchanged(f,before,"Replay"): return
			var loaded:=Model.new()
			if not check(loaded.load_build(f.path) and Planner._same_data(loaded.snapshot(),after),"Current46 reload agrees with committed result"): return
			results.append({"base":base,"operation":operation,"cost":economics.cost,"materials":economics.materials,"balance_before":balance,"balance_after":model.crafting_balance()})
	report.six_crafts=results
	completed=true

func refusals_and_targeted() -> void:
	for operation: String in SIX_OPS:
		if operation=="salvage": continue
		var f:=craft_fixture(operation,"nine_slot_threaded_gloves",0)
		if f.is_empty(): return
		# The reused source has no craft balance; assert rather than assume it.
		if not check(f.model.crafting_balance()==0,"No-money fixture has no hidden inherited shards"): return
		var before:=transaction_mark(f)
		if not check(not f.model.crafting_quote(operation,f.source.id,f.path).ok,"Insufficient funds quote rejects "+operation) or not unchanged(f,before,"No funds"): return
	for kind: String in ["revision","external","reload"]:
		var f:=craft_fixture("recalibrate","nine_slot_etched_ring")
		if f.is_empty(): return
		var quote: Dictionary=f.model.crafting_quote("recalibrate",f.source.id,f.path)
		if not check(quote.ok,"Issue representative stale quote"): return
		if kind=="revision": f.model.add_xp(1)
		elif kind=="external": FileAccess.open(f.path,FileAccess.WRITE).store_string(JSON.stringify(f.model.snapshot(),"  "))
		else:
			if not check(f.model.load_build(f.path),"Reload before stale confirmation"): return
		var before:=transaction_mark(f)
		if not check(not f.model.execute_crafting(quote.handle,f.source).ok,"Old quote rejected after "+kind) or not unchanged(f,before,"Stale "+kind): return
	var targeted: Array=[]
	for operation: String in Craft.Targeted.operation_ids():
		var f:=craft_fixture("recalibrate","nine_slot_etched_ring")
		if f.is_empty(): return
		var before:=transaction_mark(f); var expected:=Craft.operation_quote(f.source,operation)
		var quote: Dictionary=f.model.crafting_quote(operation,f.source.id,f.path)
		if not check(quote.ok==expected.ok,"Existing targeted legality remains catalog-authoritative "+operation): return
		if expected.ok:
			if not check(quote.cost=={Craft.MATERIAL_ID:40},"Existing rare targeted fee40"): return
			if not accepted(f.model.execute_crafting(quote.handle,f.source),"Existing legal targeted craft"): return
			var item: Dictionary=f.model.item(f.source.id).payload
			if not check(Gear.validate_instance(item) and item.affixes.any(func(a: Dictionary)->bool:return Craft.Targeted.TARGETS[operation].families.has(a.id)),"Target guarantee and legal new-pool output"): return
		else:
			if not unchanged(f,before,"Unavailable ring target is atomic"): return
		targeted.append({"operation":operation,"available":expected.ok,"cost":expected.get("cost",{})})
	report.targeted=targeted
	completed=true

func full_bag_and_supply() -> void:
	var f:=craft_fixture("recalibrate","nine_slot_etched_ring")
	if f.is_empty(): return
	var model: FaultModel=f.model; var candidate:=model.snapshot()
	var context:=Model.Migration.paged_location_context(candidate,model._socket_ids)
	var occupied: Dictionary=Locations.validate_current(Items.metadata_for_items(candidate.items),candidate.locations,context).occupied_cells
	for page: int in range(2):
		for y: int in range(10):
			for x: int in range(12):
				if occupied.has("bag:%d:%d:%d"%[page,x,y]): continue
				var uid:="item_%06d"%int(candidate.next_item_serial); candidate.next_item_serial+=1
				candidate.items[uid]=Model.Gems.create_instance(uid,"skill:bolt")
				candidate.locations[uid]={"kind":"bag","page":page,"x":x,"y":y}
	if not check(Model.Rules.reason(candidate).is_empty(),"Full240-cell owned fixture validates"): return
	model._accept_memory(candidate)
	if not check(model.save_build(f.path)==OK,"Persist lawful full bag"): return
	var rng:=RandomNumberGenerator.new(); rng.seed=720072
	var before:=transaction_mark(f); var rng_before:=rng.state
	if not check(model.award_equipment(rng,16,"rare").is_empty() and rng.state==rng_before,"Full bag refuses current loot and preserves exact RNG") or not unchanged(f,before,"Full bag reward refusal"): return
	var quote:=model.crafting_quote("recalibrate",f.source.id,f.path)
	if not check(quote.ok and model.execute_crafting(quote.handle,f.source).ok and model.location(f.source.id)==candidate.locations[f.source.id],"Full bag still permits atomic in-place calibration"): return
	# Read the actual Main town stock: all fifteen established white bases,
	# unchanged stock IDs, and zero pre-enchanted gift items.
	if not fresh_source("refunded"): return
	var stock: Array=arena.town_stock("equipment_merchant")
	var bases: Array=[]
	for row: Dictionary in stock:
		if row.supply_kind!="base": continue
		bases.append(row.catalog_id)
		var sample:=Town.make_item(row,999999)
		if not check(sample.payload.rarity=="normal" and sample.payload.affixes.is_empty(),"Town supplies existing plain base, never a new-affix gift"): return
	var expected_bases: Array=Gear.all_base_ids(); bases.sort(); expected_bases.sort()
	if not check(bases==expected_bases and bases.size()==15,"Actual town stock has exactly existing15 bases"): return
	var seen_bases: Dictionary={}; var witnesses: Dictionary={}
	for seed_value: int in range(1,1601):
		var probe:=RandomNumberGenerator.new(); probe.seed=seed_value
		var rolled:=Gear.generate_loot_profile(probe,"gear_999999",16,"rare",Gear.CANONICAL_LOOT_PROFILE_ID)
		if not check(Gear.validate_instance(rolled),"Current catalog loot candidate validates"): return
		seen_bases[rolled.base_id]=true
		for roll: Dictionary in rolled.affixes:
			if NEW_IDS.has(roll.id) and not witnesses.has(roll.id): witnesses[roll.id]=seed_value
		if seen_bases.size()==15 and witnesses.size()==4: break
	if not check(seen_bases.size()==15 and witnesses.size()==4,"Bounded current pool reaches15 old bases and all4 new families"): return
	for id: String in NEW_IDS:
		if not fresh_source("refunded"): return
		# Drive the real root-death reward consumer with a deterministic legal
		# seed chosen above, not a manually injected roll or replacement item.
		arena.wave=9; arena.rng.seed=int(witnesses[id])
		var prior: Dictionary=arena.state.snapshot(); var next_uid:="gear_%06d"%int(prior.next_item_serial)
		arena._award_kill_equipment({"rarity":"rare","equipment_pool":""})
		var item: Dictionary=arena.state.item(next_uid)
		if not check(not item.is_empty() and item.payload.affixes.any(func(a: Dictionary)->bool:return a.id==id),"Actual Main equipment-award path produces "+id): return
		if not check(arena.state.snapshot().next_item_serial==prior.next_item_serial+1 and arena.state.location(next_uid).kind=="bag", "Single actual award owns exactly one next UID"): return
	report.supply={"town_bases":bases,"observed_bases":seen_bases.keys(),"new_family_seed_witnesses":witnesses}
	completed=true

func export_fixture(name: String) -> bool:
	var directory:=OS.get_environment("GLOVE_RING_FIXTURE_DIR")
	if directory.is_empty(): return true
	if not check(DirAccess.make_dir_recursive_absolute(directory)==OK,"Create fixture destination"): return false
	var raw: Dictionary=arena.state.snapshot()
	if not check(Model.Rules.reason(raw).is_empty() and arena.state.pending_items().is_empty(),"Export full lawful46 fixture "+name): return false
	var file:=FileAccess.open(directory+"/"+name+".json",FileAccess.WRITE)
	if not check(file!=null,"Open raw fixture"): return false
	file.store_string(JSON.stringify(raw,"\t",true,true)); file.close()
	var expected:={"stats":arena.state.get_stats(),"basic":arena.state.get_basic_cast(),"tornado":arena.state.get_group_cast(groups.tornado),"cleave":arena.state.get_group_cast(groups.cleave),"resistance":arena.state.get_resistance_profile()}
	file=FileAccess.open(directory+"/"+name+"-expected.json",FileAccess.WRITE)
	if not check(file!=null,"Open expected projection"): return false
	file.store_string(JSON.stringify(expected,"\t",true,true)); file.close()
	output_fixtures.append(name)
	return true

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v072-glove-ring-") or not OS.get_user_data_dir().begins_with(isolated+"/"):
		quit(78); return
	create_timer(40.0).timeout.connect(watchdog)
	arena=load("res://scenes/main.tscn").instantiate(); root.add_child(arena)
	await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire=false
	var selection:=OS.get_environment("GLOVE_RING_GAMEPLAY_SECTIONS").split(",",false)
	if section(legal_source_setup):
		for test: Callable in [accuracy_and_precise,finesse_aggregate,triple_rings_and_caps,six_crafts_and_metadata,refusals_and_targeted,full_bag_and_supply]:
			if not selection.is_empty() and not selection.has(test.get_method()): continue
			if not section(test): break
	report.merge({"checks":checks,"failures":failures,"sections":sections,"fixtures":output_fixtures,"scope":"Bounded real Main/model/crafting consumers; lawful migrated v45 source and owned equipment; source policy45 unchanged. Explicit cap-only boundary is labeled separately. No UI/export/performance acceptance."})
	var output:=OS.get_environment("GLOVE_RING_GAMEPLAY_REPORT")
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("GLOVE_RING_GAMEPLAY ",JSON.stringify({"checks":checks,"failures":failures,"sections":sections}))
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)
