extends "res://tests/exploration_main_flow_test.gd"
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const HitDamage = preload("res://scripts/combat/damage_resolver.gd")
const CritRuntime = preload("res://scripts/combat/critical_strike_runtime.gd")
var group_id := "group_000009"
var active_uid := ""
var support_uid := ""
var cast_plain: Dictionary = {}
var cast_ring: Dictionary = {}
var samples: Array = []

func run() -> void:
	var file := FileAccess.open("user://build_save.json",FileAccess.WRITE)
	if not check(file!=null,"Fresh isolated Main profile writable"):quit(1);return
	file.store_buffer(FileAccess.get_file_as_bytes("res://docs/qa/v093-integration/equipped-fixture.json"));file.close()
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;pause()
	if not check(arena.world_context().normal_town and arena.state.pending_items().is_empty(),"Actual Main migrated legal previous fixture into formal town"):await finish();return
	if not purchase_and_link():await finish();return
	if not accepted(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision),"Prepare actual exploration map"):await finish();return
	if not accepted(arena.start_map(arena.map_draft().revision),"All map residents admitted before area probes"):await finish();return
	pause();check(arena.enemies.size()==25,"Unchanged complete garden roster")
	if not circle_probe():await finish();return
	if not return_to_town("Return after close-combat probes"):await finish();return
	pause()
	if not accepted(arena.craft_normal_map("broken_ruins",1,[],[],arena.map_draft().revision),"Prepare actual wall map"):await finish();return
	if not accepted(arena.start_map(arena.map_draft().revision),"Enter actual wall map with same support"):await finish();return
	pause()
	if not wall_probe_ring():await finish();return
	if not return_to_town("Final return preserves ownership"):await finish();return
	pause()
	var current: Dictionary=arena.state.get_group_cast(group_id)
	var reloaded := Model.new()
	if not check(reloaded.load_build(arena.build_save_path),"Reload actual saved purchase and link"):await finish();return
	check(reloaded.get_group_cast(group_id)==current and reloaded.item(support_uid)==arena.state.item(support_uid),"Owned support and final cast survive reload unchanged")
	FileAccess.open("res://docs/qa/v094-integration/owned-fixture.json",FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(arena.build_save_path))
	await finish()

func purchase(definition: String, cost: int) -> String:
	var balance: int=arena.state.crafting_balance()
	var quote: Dictionary=arena.normal_gem_trade_quote("buy",definition,arena.state.revision())
	if not accepted(quote,"Actual merchant quote "+definition):return ""
	var receipt: Dictionary=arena.execute_normal_gem_trade(quote.handle,definition)
	if not accepted(receipt,"Actual merchant executes "+definition):return ""
	check(arena.state.crafting_balance()==balance-cost,"Exact authorized gem price "+definition)
	var after: Dictionary=observation()
	check(not arena.execute_normal_gem_trade(quote.handle,definition).ok and observation()==after,"Repeated confirmation cannot charge again")
	return str(receipt.uid)

func purchase_and_link() -> bool:
	var found:=false
	for item: Dictionary in arena.state.snapshot().items.values():check(item.definition_id!="support:encircling_cleave","Migration does not grant new gem")
	for offer: Dictionary in arena.normal_gem_offers():
		if offer.definition_id=="support:encircling_cleave":found=true;check(offer.cost==4,"Formal dynamic offer shows4 shards")
	if not check(found,"New gem appears in actual formal merchant catalog"):return false
	var original: Dictionary=observation()
	var quote: Dictionary=arena.normal_gem_trade_quote("buy","support:encircling_cleave",arena.state.revision())
	if not accepted(quote,"New support cancelable quote"):return false
	arena.cancel_normal_gem_trade_quote(quote.handle)
	check(observation()==original,"Cancel leaves disk, materials, IDs and ownership unchanged")
	active_uid=purchase("skill:cleave",8);support_uid=purchase("support:encircling_cleave",4)
	if active_uid.is_empty() or support_uid.is_empty():return false
	if not accepted(arena.state.move_item(active_uid,{"kind":"skill_main","group_id":group_id},arena.state.revision(),arena.build_save_path),"Place purchased active in existing group9"):return false
	cast_plain=arena.state.get_group_cast(group_id)
	if not accepted(arena.state.move_item(support_uid,{"kind":"skill_support","group_id":group_id,"index":0},arena.state.revision(),arena.build_save_path),"Link purchased support by actual UID"):return false
	cast_ring=arena.state.get_group_cast(group_id)
	if not accepted(cast_plain,"Plain owned cleave") or not accepted(cast_ring,"Ring owned cleave"):return false
	check(cast_plain.recipe.half_angle==PI/2 and cast_ring.recipe.half_angle==PI,"Actual group changes180 to360 degrees")
	near(cast_ring.recipe.radius,cast_plain.recipe.radius,"Angle never increases radius")
	near(cast_ring.mana,cast_plain.mana*1.25,"Owned mana cost125%")
	near(cast_ring.cooldown,cast_plain.cooldown,"Owned cooldown unchanged")
	near(HitDamage.resolve(cast_ring.packets.direct,cast_ring.snapshot.modifiers).total,HitDamage.resolve(cast_plain.packets.direct,cast_plain.snapshot.modifiers).total*0.75,"Owned final primary damage75%")
	var before: Dictionary=observation()
	check(not arena.state.move_item(support_uid,{"kind":"skill_support","group_id":"group_000001","index":0},arena.state.revision(),arena.build_save_path).ok and observation()==before,"Wrong active skill rejection is atomic")
	return failures==0

func prep_actor(enemy: Dictionary, position: Vector2, radius: float=10.0) -> void:
	enemy.pos=position;enemy.spawn=0.0;enemy.health=10000.0;enemy.max_health=10000.0;enemy.shield=0.0;enemy.max_shield=0.0
	enemy.armour=0.0;enemy.evasion=0.0;enemy.evasion_entropy=50.0;enemy.radius=radius
	enemy.attack_timer=999.0;enemy.knockback=Vector2.ZERO;enemy.slow=0.0
	enemy.resistances={};enemy.shield_regen=0.0;enemy.shield_recharge_rate=0.0

func ready_cast() -> void:
	arena.group_cooldowns.reset();arena.mana=500.0;arena.invulnerable=100.0
	arena.damage_trace.clear();arena.visual_cues.reset()

func spell_state() -> PackedByteArray:
	return var_to_bytes([arena.mana,arena.group_cooldowns.snapshot(),arena.projectile_runtime.next_cast_id,arena.critical_runtime.checkpoint(),arena.enemies,arena.state.snapshot(),FileAccess.get_file_as_bytes(arena.build_save_path)])

func circle_probe() -> bool:
	arena.player_pos=arena.ARENA.position+Vector2(600,1600)
	for enemy: Dictionary in arena.enemies:enemy.pos=arena.ARENA.position+Vector2(3200,200);enemy.spawn=0.0;enemy.attack_timer=999.0
	var offsets: Array[Vector2]=[Vector2(55,0),Vector2(-75,0),Vector2(0,70),Vector2(0,-70),Vector2(55,45),Vector2(-55,45),Vector2(-55,-45),Vector2(55,-45),Vector2(96,0),Vector2(99,0),Vector2(-50,0),Vector2(60,0)]
	for index: int in range(offsets.size()):prep_actor(arena.enemies[index],arena.player_pos+offsets[index],1.0 if index in [8,9] else 10.0)
	arena.enemies[10].spawn=0.5
	arena.enemies[11].evasion=1e10;arena.enemies[11].evasion_entropy=0.0
	ready_cast();arena.mana=float(cast_ring.mana)-0.001
	var before: PackedByteArray=spell_state()
	check(not arena.cast_group(group_id) and spell_state()==before,"Insufficient mana changes no cast ID, entropy, targets, save or cooldown")
	ready_cast();var mana_before: float=arena.mana
	var oracle:=CritRuntime.new();oracle.restore(arena.critical_runtime.checkpoint());var critical: Dictionary=oracle.freeze(cast_ring.snapshot)
	if not check(critical.ok and arena.cast_group(group_id),"Actual owned group casts once"):return false
	near(arena.mana,mana_before-float(cast_ring.mana),"Successful area cast charges mana once")
	check(arena.critical_runtime.checkpoint()==oracle.checkpoint(),"Exactly one existing critical freeze per cast")
	check(arena.group_cooldown_remaining(group_id)==cast_ring.cooldown,"One cooldown debt")
	var targets: Array[int]=[]
	for hit: Dictionary in arena.damage_trace:targets.append(int(hit.target_id))
	check(targets.size()==9 and targets.size()==_unique(targets).size(),"Nine admitted bodies hit once, including boundary; circle seam never duplicates")
	for index: int in range(offsets.size()):
		check(targets.has(int(arena.enemies[index].id))==(index<9),"Actual geometry/admission for target"+str(index))
	check(arena.enemies[9].health==10000.0 and arena.enemies[10].health==10000.0 and arena.enemies[11].health==10000.0,"Beyond radius, protected and evaded targets remain undamaged")
	var expected: Dictionary=HitDamage.resolve(cast_ring.packets.direct,cast_ring.snapshot.modifiers,{},float(critical.snapshot.get("critical_roll",{}).get("multiplier",1.0)))
	for hit: Dictionary in arena.damage_trace:near(hit.total,expected.total,"Each admitted target receives one authoritative75% packet")
	check(arena.projectiles.is_empty(),"Ring melee does not create projectiles or secondary carriers")
	for cue: Dictionary in arena.visual_cues.cues:
		if cue.kind=="cleave":check(cue.half_angle==PI and cue.radius==cast_ring.recipe.radius,"Original cue reads same authoritative radius and angle")
	before=spell_state();check(not arena.cast_group(group_id) and spell_state()==before,"Immediate recast obeys original cooldown atomically")
	samples.append({"probe":"full_circle","targets":targets,"facing":arena.player_facing,"packet":cast_ring.packets.direct,"expected":expected,"receipts":arena.damage_trace.duplicate(true)})
	# Removing the support leaves the already compiled immutable cast untouched.
	var frozen: Dictionary=cast_ring.duplicate(true)
	if not accepted(arena.state.move_item(support_uid,arena.state.first_bag_position(support_uid),arena.state.revision(),arena.build_save_path),"Unlink actual support safely"):return false
	check(arena.state.get_group_cast(group_id)==cast_plain and cast_ring==frozen,"Unlink restores exact old cast; existing frozen result remains360")
	for index: int in range(offsets.size()):prep_actor(arena.enemies[index],arena.player_pos+offsets[index],1.0 if index in [8,9] else 10.0)
	arena.enemies[10].spawn=0.5;arena.enemies[11].evasion=1e10;arena.enemies[11].evasion_entropy=0.0
	ready_cast()
	if not check(arena.cast_group(group_id),"Plain cleave remains castable after unlink"):return false
	targets.clear()
	for hit: Dictionary in arena.damage_trace:targets.append(int(hit.target_id))
	check(not targets.has(int(arena.enemies[1].id)) and not targets.has(int(arena.enemies[5].id)) and not targets.has(int(arena.enemies[6].id)),"Exact rear and rear diagonals no longer hit without support")
	if not accepted(arena.state.move_item(support_uid,{"kind":"skill_support","group_id":group_id,"index":0},arena.state.revision(),arena.build_save_path),"Relink same support instance"):return false
	return failures==0

func _unique(values: Array) -> Dictionary:
	var out: Dictionary={}
	for value: Variant in values:out[value]=true
	return out

func wall_probe_ring() -> bool:
	for enemy: Dictionary in arena.enemies:enemy.pos=arena.ARENA.position+Vector2(3200,200);enemy.spawn=0.0;enemy.attack_timer=999.0
	var corner: Vector2=arena.world_geometry().walls[0].position
	arena.player_pos=corner+Vector2(-15,40)
	prep_actor(arena.enemies[0],arena.player_pos+Vector2(0,55))
	prep_actor(arena.enemies[1],corner+Vector2(40,-15))
	check(arena._geometry.is_clear(arena.player_pos,arena.PLAYER_RADIUS) and arena._geometry.is_clear(arena.enemies[1].pos,10.0),"Rear-wall fixture uses legal body positions")
	check(Vector2(arena.enemies[1].pos).distance_to(arena.player_pos)<float(cast_ring.recipe.radius) and not arena._terrain_visible(arena.player_pos,arena.enemies[1].pos),"Rear-side target lies inside circle but beyond actual wall LOS")
	ready_cast()
	if not check(arena.cast_group(group_id),"Actual ring cast near wall"):return false
	check(arena.enemies[0].health<10000.0 and arena.enemies[1].health==10000.0,"Existing LOS admits visible target and blocks rear target")
	return failures==0

func finish() -> void:
	var data: Dictionary={"checks":checks,"failures":failures,"labels":labels,"group_id":group_id,"active_uid":active_uid,"support_uid":support_uid,"plain":cast_plain,"ring":cast_ring,"samples":samples,"scope":"Actual formal purchase/equip/save and controlled existing map actors; not natural drops, full-play session or FPS"}
	FileAccess.open("res://docs/qa/v094-integration/main-result.json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t",true,true))
	print("ENCIRCLING_MAIN ",checks," checks, ",failures," failures")
	if is_instance_valid(arena):arena.queue_free();await process_frame
	quit(1 if failures else 0)
