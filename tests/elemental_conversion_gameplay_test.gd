extends "res://tests/physical_fire_conversion_gameplay_test.gd"
## v078 reuses accepted v069 actual-Main helpers, not its fire-only assertions.
const Fixture = preload("res://tests/fixtures/v078/elemental_conversion_fixture.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Base = preload("res://scripts/combat/damage_base_compiler.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const ELEMENTS := ["fire", "cold", "lightning"]
var focus_weapon := ""

func clean() -> void:
	super.clean()
	arena.freeze_runtime.reset(); arena.trap_runtime.reset(); arena.trap_trace.clear()

func set_mastery(enabled: bool) -> bool:
	return accepted(Fixture.select(arena.state, arena.build_save_path, ELEMENTS if enabled else []), "Select real three source masteries" if enabled else "Refund real three source masteries")

func own(base: String) -> String:
	if base != "runewood_focus": return super.own(base)
	var uid := "gear_%06d" % int(arena.state.snapshot().next_item_serial)
	var affixes: Array = []
	for id: String in ["attack_added_physical", "attack_added_fire", "coalglow", "wellturn"]:
		affixes.append({"id":id, "tier":3, "value":int(Gear.affix_definition(id).tiers[2].max)})
	var item := {"id":uid,"base_id":base,"rarity":"rare","item_level":16,"affixes":affixes}
	if not check(Gear.validate_instance(item) and arena.state._admit_reward_item(Items.wrap_equipment(item)), "Legal four-affix real added-physical/fire equipment"): return ""
	return uid

func equip_links(skill: String, links: Array) -> String:
	if not groups.has(skill):
		var uid: String = arena.state.award_gem("skill:"+skill)
		if not check(not uid.is_empty(), "Owned main gem "+skill): return ""
		var free := ""
		for group: Dictionary in arena.state.snapshot().skill_groups:
			if str(arena.state.skill_group(group.id).main_uid).is_empty(): free = str(group.id); break
		if not check(not free.is_empty(), "Vacant actual skill group"): return ""
		if not accepted(arena.state.move_item(uid,{"kind":"skill_main","group_id":free},arena.state.revision(),arena.build_save_path),"Equip main "+skill): return ""
		groups[skill] = free
	for index: int in range(links.size()):
		var uid: String = arena.state.award_gem("support:"+str(links[index]))
		if not check(not uid.is_empty(), "Owned support "+str(links[index])): return ""
		if not accepted(arena.state.move_item(uid,{"kind":"skill_support","group_id":groups[skill],"index":index},arena.state.revision(),arena.build_save_path),"Equip support "+str(links[index])): return ""
	return groups[skill]

func legal_source_and_owned_group() -> void:
	if not accepted(arena.enter_town_test(arena.world_context().revision),"Real test profile town") or not accepted(arena.start_map(arena.map_draft().revision),"Real map entry"): return
	blade = own("forgeblade"); bow = own("ashwood_bow"); focus_weapon = own("runewood_focus")
	if [blade,bow,focus_weapon].has("") or not equip(blade): return
	for group: Dictionary in arena.state.snapshot().skill_groups:
		var cast: Dictionary = arena.state.get_group_cast(group.id)
		if cast.get("ok",false): groups[cast.skill_id] = group.id
	if equip_links("cleave",[]).is_empty() or equip_links("tornado",["physical_focus","fire_focus","ignite","focus","efficiency"]).is_empty(): return
	var result: Dictionary = Fixture.prepare(arena.state,arena.build_save_path,ELEMENTS)
	if not accepted(result,"Real connected Witch source allocation"): return
	check(arena.state.snapshot().talents.allocated.size() == 28 and arena.state.talent_points == 0,"All 27 earned points are actually spent, plus free source root")
	check(arena.state.snapshot().progress.level == 23 and arena.state.snapshot().talents.class_id == 3,"Level23 Witch owns the exact 27-point budget")
	var stats: Dictionary = arena.state.get_stats()
	for type: String in ELEMENTS: near(stats.get("physical_to_"+type+"_conversion",0.0),0.4,"Actual source forty percent "+type)
	for type: String in ["cold","lightning"]:
		near(stats.get(type+"_penetration",0.0),0.06,"Source notable owns six percent "+type+" penetration")
		check(float(stats.get(type+"_increased",0.0)) >= 0.3,"Original thirty percent increased remains active "+type)
	check(arena.state.Rules.reason(arena.state.snapshot()).is_empty(),"Full same-character source fixture is accepted by current schema")
	var cast: Dictionary = arena.state.get_group_cast(groups.tornado)
	if not accepted(cast,"Five-support actual source cast") or not packet_contract(cast.packets.parent,"Full source parent"): return
	var before := readonly(); var loaded := Model.new()
	check(loaded.load_build(arena.build_save_path) and loaded.snapshot() == arena.state.snapshot(),"Current source48/schema48 fixture reloads exactly")
	check(loaded.get_group_cast(groups.tornado) == cast and readonly() == before,"Reload and source compile are read-only")
	var output := OS.get_environment("ELEMENTAL_FIXTURE_OUTPUT")
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(arena.build_save_path))
	report.source = {"talents":arena.state.snapshot().talents,"stats":stats,"items":arena.state.snapshot().items,"version":arena.state.snapshot().version}
	completed = true

func packet_contract(packet: Dictionary, label: String) -> bool:
	if not check(packet.has("conversion") and Base.packet_error(packet).is_empty(),label+" has a valid assembled conversion packet"): return false
	var trace: Dictionary = packet.conversion
	var p: float = packet.base.get("physical",0.0)
	near(p,float(packet.assembly.intrinsic.get("physical",0.0))+float(packet.assembly.added.get("physical",0.0))+float(packet.assembly.get("weapon",{}).get("contribution",{}).get("physical",0.0)),label+" converts the complete assembled physical base")
	if trace.get("version",1) == 1:
		check(trace == {"source_type":"physical","target_type":"fire","fraction":0.4,"source_base":p,"remaining_base":p*0.6,"converted_base":p*0.4},label+" exact legacy fire descriptor")
	else:
		check(trace.size() == 7 and trace.source_type == "physical" and trace.source_base == p,label+" exact v2 descriptor structure")
		var total: float = 0.4 * trace.requested.size(); var remaining: float = 0.0 if total > 1.0 else 1.0-total
		near(trace.remaining_base,p*remaining,label+" residual physical")
		if total > 1.0: check(trace.remaining_base == 0.0,label+" normalized physical explicitly zero")
		var conserved: float = trace.remaining_base
		for type: String in trace.requested:
			near(trace.requested[type],0.4,label+" requested "+type)
			near(trace.effective[type],0.4/maxf(1.0,total),label+" effective "+type)
			near(trace.converted_base[type],p*0.4/maxf(1.0,total),label+" converted base "+type)
			conserved += float(trace.converted_base[type])
		near(conserved,p,label+" physical mass conservation")
	return true

func expected_raw(packet: Dictionary, snapshot: Dictionary, critical: float = 1.0) -> Dictionary:
	var result := {}; var converted := {}; var remaining: float = packet.base.get("physical",0.0)
	if packet.has("conversion"):
		remaining = float(packet.conversion.remaining_base)
		converted = packet.conversion.converted_base if packet.conversion.get("version",1)==2 else {"fire":packet.conversion.converted_base}
	for type: String in Damage.TYPES:
		var native: float = remaining if type == "physical" else packet.base.get(type,0.0)
		var final := scale_piece(native,packet,snapshot.modifiers,[type]) * critical
		if converted.has(type): final += scale_piece(float(converted[type]),packet,snapshot.modifiers,["physical",type])*critical
		if native > 0.0 or float(converted.get(type,0.0)) > 0.0: result[type] = final
	return result

func assert_raw(record: Dictionary, expected: Dictionary, label: String) -> void:
	check(record.before_defense_components.keys() == expected.keys(),label+" exact final component types")
	for type: String in expected: near(record.before_defense_components[type],expected[type],label+" independently derived "+type)

func source_matrix_and_previews() -> void:
	var samples: Array = []
	for selected: Array in [[],["cold"],["lightning"],["cold","lightning"],["fire","cold"],ELEMENTS]:
		if not accepted(Fixture.select(arena.state,arena.build_save_path,selected),"Real source selection "+str(selected)): return
		if not equip(blade): return
		var fixture_dir:=OS.get_environment("ELEMENTAL_FIXTURE_DIRECTORY")
		if not fixture_dir.is_empty():
			var label: String="zero" if selected.is_empty() else "-".join(selected)
			FileAccess.open(fixture_dir+"/"+label+".json",FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(arena.build_save_path))
		if selected.is_empty(): continue
		for weapon: String in [blade,bow,focus_weapon]:
			if not equip(weapon): return
			for skill: String in ["basic","cleave","tornado"]:
				var cast: Dictionary = arena.state.get_basic_cast() if skill=="basic" else arena.state.get_group_cast(groups[skill])
				if not accepted(cast,"Source model compile "+skill): return
				var before := readonly(); var frozen := var_to_bytes(cast)
				var profile: Dictionary = cast.get("conversion_profile",{})
				check(profile.get("version")==2 and profile.size()==7 and profile.enabled and profile.source_type=="physical","Exact v2 public conversion profile")
				check(profile.normalized == (selected.size()==3),"Normalization only when requested sum exceeds one")
				near(profile.physical_fraction,0.0 if selected.size()==3 else 1.0-0.4*selected.size(),"Public residual physical fraction")
				var fractions := {}
				for type: String in ["cold","lightning"]:
					if selected.has(type): fractions[type] = 0.06
				check(cast.get("penetration_profile",{})=={"enabled":true,"fractions":fractions,"minimum_resistance":-1.0},"Profile only includes final types actually present in packets")
				var entries: Array = Preview.entries(cast)
				for entry: Dictionary in entries:
					var packet: Dictionary = entry.packet
					if float(packet.base.get("physical",0.0)) > 0.0:
						if not packet_contract(packet,skill+" "+str(selected)): return
						var resolved: Dictionary = Damage.resolve(packet,cast.snapshot.modifiers)
						for type: String in expected_raw(packet,cast.snapshot): near(resolved.components[type],expected_raw(packet,cast.snapshot)[type]*(1.06 if fractions.has(type) else 1.0),"Preview resolver agrees with independent type oracle")
					else: check(not packet.has("conversion") and not packet.has("penetration"),"Pure-fire secondary adds neither empty field")
				check(not Preview.summary(cast).is_empty() and not Preview.details(cast).is_empty(),"Preview accepts actual source v2 cast")
				check(var_to_bytes(cast)==frozen and readonly()==before,"Preview leaves snapshot, RNG-independent model and disk unchanged")
				samples.append({"selected":selected,"weapon":weapon,"skill":skill,"profile":profile,"penetration":cast.get("penetration_profile",{})})
	if not set_mastery(true): return
	report.source_matrix = samples; completed = true

func actual_source_hits() -> void:
	var observations: Array = []
	for selected: Array in [["cold"],["lightning"],["cold","lightning"],ELEMENTS]:
		if not accepted(Fixture.select(arena.state,arena.build_save_path,selected),"Actual hit source selection"): return
		for mode: Array in [[blade,"basic","direct"],[bow,"basic","projectile"],[blade,"cleave","direct"],[focus_weapon,"tornado","parent"]]:
			if not equip(mode[0]): return
			clean(); var enemy := target(Vector2(40,0)); enemy.resistances={"cold":0.0,"lightning":0.0}
			var cast: Dictionary = arena.state.get_basic_cast() if mode[1]=="basic" else arena.state.get_group_cast(groups[mode[1]])
			if not accepted(cast,"Actual source-driven "+mode[1]): return
			var packet: Dictionary = cast.packets[mode[2]]
			if mode[0]==focus_weapon: check(packet.assembly.added.physical>0.0 and packet.assembly.added.fire>0.0,"Real equipment contributes both added physical and native fire")
			else: check(float(packet.assembly.weapon.contribution.physical)>0.0,"Real local weapon contributes before split")
			var before := readonly(); var resistances := var_to_bytes(enemy.resistances)
			if mode[1]=="basic": arena.auto_fire=true; arena._update_auto_attack(); arena.auto_fire=false
			elif not check(arena.cast_group(groups[mode[1]]),"Owned group actual cast"): return
			arena._update_projectiles(0.15)
			if not check(not arena.damage_trace.is_empty(),"Actual settled source hit"): return
			var record: Dictionary = arena.damage_trace[0]
			assert_raw(record,expected_raw(packet,cast.snapshot,record.get("critical",{}).get("multiplier",1.0)),"Source actual "+mode[1])
			for row: Dictionary in record.details:
				if row.type in ["cold","lightning"]:
					near(row.resistance,-0.06,"Actual zero resistance becomes negative via penetration")
					check(row.parts.back().lineage==["physical",row.type],"Converted elemental part owns exact lineage")
			check(var_to_bytes(enemy.resistances)==resistances and readonly()==before,"Actual hit never mutates target resistance source or save")
			check(arena.freeze_runtime.is_empty() and arena.shock_runtime.is_empty(),"Converted cold/lightning does not invent frost lock or shock")
			if mode[1]!="tornado": check(arena.burn_runtime.is_empty(),"Basic and cleave do not gain burning eligibility")
			observations.append(record)
	for skill: String in ["cleave","tornado"]:
		for support: String in ["frost_lock","shock","cold_focus","lightning_focus"]: check(not Supports.compatibility_reason(skill,[support],5).is_empty(),"Conversion preserves original support gate "+skill+"/"+support)
	if not set_mastery(true): return
	report.actual_hits=observations; completed=true

func controlled_stats(critical: bool=false, resolute: bool=false) -> Dictionary:
	var stats := super.controlled_stats(critical,resolute)
	stats.physical_to_cold_conversion=0.4; stats.physical_to_lightning_conversion=0.4
	stats.cold_penetration=0.06; stats.lightning_penetration=0.06
	return stats

func focus_defense_leech_and_critical() -> void:
	var observations: Array=[]
	for selected: Array in [["cold","lightning"],ELEMENTS]:
		for critical: bool in [false,true]:
			clean(); var stats:=controlled_stats(critical)
			if not selected.has("fire"): stats.erase(STAT)
			var snapshot:=Combat.snapshot(stats,[])
			snapshot.modifiers.append({"id":"dual_once","mode":"increased","value":0.3,"all_tags":["hit","attack"],"damage_types":["physical","fire","cold","lightning"]})
			var cast:=Compiler.compile_group("tornado",snapshot,["physical_focus","fire_focus"])
			if not accepted(cast,"Independent focus clauses compile"): return
			var enemy:=target(Vector2(60,0)); enemy.armour=240.0; enemy.resistances={"fire":0.25,"cold":0.9,"lightning":-1.0}
			var small:=target(Vector2(65,8)); small.armour=240.0; small.resistances=enemy.resistances.duplicate(true); small.health=10.0; small.shield=5.0
			var rng: Dictionary=arena.critical_runtime.checkpoint()
			if not check(arena._execute_compiled(cast),"Actual focused v2 cast"): return
			arena._update_projectiles(0.2)
			if not check(not arena.damage_trace.is_empty(),"Focused v2 actual hits"): return
			for record: Dictionary in arena.damage_trace:
				var expected:=expected_raw(cast.packets.parent,cast.snapshot,2.0 if critical else 1.0)
				assert_raw(record,expected,"v2 focused actual hit")
				for row: Dictionary in record.details:
					if row.type=="physical": near(row.final,expected.physical*(1.0-240.0/(240.0+5.0*expected.physical)),"Armour only residual physical")
					elif row.type=="cold": near(row.final,expected.cold*0.16,"Ninety percent minus six percentage points")
					elif row.type=="lightning": near(row.final,expected.lightning*2.0,"Negative hundred resistance respects lower floor")
					for part: Dictionary in row.parts:
						check(part.modifiers.count("dual_once")==1,"One multi-type modifier entry applied exactly once")
						if part.lineage.size()==2 and row.type=="fire":
							near(part.more,0.96*0.96,"Physical and fire focus each preserve two independent MORE clauses")
							check(part.modifiers.count("support:physical_focus")==2 and part.modifiers.count("support:fire_focus")==2,"Shared IDs do not deduplicate support clauses")
				var actual: float=record.shield_spent+record.health_lost
				var physical: float=actual*float(record.components.get("physical",0.0))/record.total
				if not check(record.has("leech"),"All attack types admit actual leech"): return
				near(record.leech.health,actual*0.01+physical*0.02,"Life leech uses actual all-type loss and only residual physical share")
				near(record.leech.mana,actual*0.02+physical*0.03,"Mana leech obeys v2 physical source exclusion")
				if record.target_id==small.id: near(actual,15.0,"Overkill excluded from both leech bases")
			var after: Dictionary=arena.critical_runtime.checkpoint()
			check(after.draws==rng.draws and after.events-rng.events==(1 if critical else 0),"All arrows and targets share original certain critical event")
			observations.append(arena.damage_trace.duplicate(true))
	report.focus_defense_leech=observations; completed=true

func penetration_defense_and_trap() -> void:
	clean()
	var cast:=Compiler.compile_group("nova",Combat.snapshot(controlled_stats(),[]),["ambush"])
	if not accepted(cast,"Native lightning trap with source penetration"): return
	check(not cast.packets.direct.has("conversion") and cast.has("penetration_profile"),"Native-only trap penetrates without inventing physical conversion")
	for raw: float in [1.2,0.9,0.0,-1.0,-1.4]:
		var mitigation: Dictionary={"lightning":raw}; var original:=var_to_bytes(mitigation)
		var resolved: Dictionary=Damage.resolve(cast.packets.direct,cast.snapshot.modifiers,mitigation)
		var row:=detail(resolved,"lightning"); var effective:=clampf(raw,-1.0,0.9); var final:=maxf(-1.0,effective-0.06)
		near(row.effective_resistance,effective,"Base resistance clamp precedes penetration")
		near(row.penetration,0.06,"Native lightning six percent")
		near(row.resistance,final,"Penetration has only final lower clamp")
		near(row.final,row.before_defense*(1.0-final),"Resolved native type after penetration")
		var settled:=Defense.settle_resolved(resolved,5.0,10.0)
		check(settled.ok and settled.details==resolved.details,"Real Defense accepts and preserves penetration receipt")
		near(settled.shield_spent+settled.health_lost,15.0,"Real Defense bounded actual loss")
		check(var_to_bytes(mitigation)==original,"Penetration never mutates resistance input")
	var group:=equip_links("nova",["ambush"])
	if group.is_empty() or not set_mastery(true): return
	clean(); var actual: Dictionary=arena.state.get_group_cast(group); var enemy:=target(Vector2(60,0))
	if not check(arena.cast_group(group),"Real owned native-lightning trap placed"): return
	var frozen:=var_to_bytes(arena.trap_runtime._entries); var critical: Dictionary=arena.critical_runtime.checkpoint()
	if not set_mastery(false) or not equip(blade): return
	for notable: String in ["8833","56716"]:
		if not accepted(arena.state.refund_passive(notable,arena.state.revision(),arena.build_save_path),"Refund penetration source with trap in flight"): return
	check(not arena.state.get_group_cast(group).has("penetration_profile"),"Future trap has no penetration after notable refunds")
	var support_uid: String=""
	for row: Dictionary in arena.state.snapshot().skill_groups:
		if row.id==group: support_uid=str(arena.state.skill_group(group).support_uids[0])
	if not accepted(arena.state.move_item(support_uid,arena.state.first_bag_position(support_uid),arena.state.revision(),arena.build_save_path),"Remove actual trap support while armed"): return
	check(var_to_bytes(arena.trap_runtime._entries)==frozen,"Refund and weapon/support replacement leave placed trap fully frozen")
	arena.elapsed=0.35; arena._update_traps()
	if not check(arena.trap_runtime.is_empty() and arena.damage_trace.size()==1,"Placed trap triggers exactly once after refund"): return
	var hit: Dictionary=arena.damage_trace[0]
	assert_raw(hit,expected_raw(actual.packets.direct,actual.snapshot,hit.get("critical",{}).get("multiplier",1.0)),"Frozen actual trap")
	near(detail(hit,"lightning").penetration,0.06,"Placed trap retains its penetration")
	check(arena.critical_runtime.checkpoint()==critical and enemy.health<10000.0,"Trap consumes original critical once and reaches actual target")
	for notable: String in ["8833","56716"]:
		if not accepted(arena.state.allocate_passive(notable,0,arena.state.revision(),arena.build_save_path),"Restore actual source notable"): return
	if not set_mastery(true): return
	report.trap=hit; completed=true

func strict_frozen_packet_admission() -> void:
	if not set_mastery(true): return
	var original: Dictionary=arena.state.get_group_cast(groups.tornado)
	if not accepted(original,"Legal original v2 packet for strict boundary"): return
	var original_bytes:=var_to_bytes(original)
	for mutation: String in ["requested","effective","remaining","converted","penetration","extra"]:
		clean(); target(Vector2(60,0))
		var bad: Dictionary=original.duplicate(true)
		match mutation:
			"requested": bad.packets.parent.conversion.requested.cold=0.4000001
			"effective": bad.packets.parent.conversion.effective.cold+=0.0000001
			"remaining": bad.packets.parent.conversion.remaining_base=0.0000001
			"converted": bad.packets.parent.conversion.converted_base.cold+=0.0000001
			"penetration": bad.packets.parent.penetration.cold=0.0600001
			"extra": bad.packets.parent.conversion.unowned=true
		bad.snapshot.compiled_packets.parent=bad.packets.parent.duplicate(true)
		check(not Base.packet_error(bad.packets.parent).is_empty(),"Strict packet validator rejects "+mutation)
		check(Combat.tornado_packet(bad.snapshot,"parent").is_empty(),"Frozen packet read rejects rather than reassembling "+mutation)
		var before: Array=[readonly(),arena.rng.state,arena.critical_runtime.checkpoint(),arena.mana,arena.cooldowns.duplicate(true),arena.projectile_runtime.next_cast_id,arena.projectile_runtime.next_projectile_id]
		check(not arena._execute_compiled(bad),"Actual emission rejects malformed frozen parent "+mutation)
		var after: Array=[readonly(),arena.rng.state,arena.critical_runtime.checkpoint(),arena.mana,arena.cooldowns.duplicate(true),arena.projectile_runtime.next_cast_id,arena.projectile_runtime.next_projectile_id]
		check(var_to_bytes(after)==var_to_bytes(before) and arena.projectiles.is_empty() and arena.damage_trace.is_empty(),"Rejected parent preserves resources/RNG/identities/save "+mutation)
	check(var_to_bytes(original)==original_bytes,"Strict probes never mutate lawful original")
	completed=true

func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v078-gameplay") or not OS.get_user_data_dir().begins_with(isolated+"/"): quit(78); return
	create_timer(45.0).timeout.connect(watchdog)
	arena=load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire=false
	var selected:=OS.get_environment("ELEMENTAL_GAMEPLAY_SECTIONS").split(",",false)
	for test: Callable in [legal_source_and_owned_group,source_matrix_and_previews,actual_source_hits,focus_defense_leech_and_critical,tornado_ignite_and_ember,pure_fire_and_dot_unchanged,frozen_parent_child_return_and_secondary,penetration_defense_and_trap,strict_frozen_packet_admission]:
		if not selected.is_empty() and not selected.has(test.get_method()) and test.get_method()!="legal_source_and_owned_group": continue
		print("ELEMENTAL_SECTION_BEGIN ",test.get_method())
		if not section(test): break
		print("ELEMENTAL_SECTION_END ",test.get_method())
	report.merge({"checks":checks,"failures":failures,"sections":sections,"scope":"Bounded actual Main plus legal source48 27-point allocations, real owned gear/groups, Compiler/Preview, Defense and frozen carriers; no UI/export/full history"})
	var output:=OS.get_environment("ELEMENTAL_GAMEPLAY_REPORT")
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("ELEMENTAL_GAMEPLAY ",JSON.stringify({"checks":checks,"failures":failures,"sections":sections}))
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)
