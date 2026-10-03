extends SceneTree
const Craft=preload("res://scripts/items/crafting_rules.gd")
const Items=preload("res://scripts/items/unified_item_catalog.gd")
const Weapon=preload("res://scripts/items/weapon_local_rules.gd")
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;arena.enemies.clear()
	while arena.hud.is_blocking():arena.hud.close_panel()
	var state=arena.state
	arena.health=10.0;arena.mana=10.0
	check(arena.use_flask("flask_1").ok and arena.use_flask("flask_2").ok,"Consume both real per-run flasks")
	var charges:Dictionary=arena.flask_runtime.snapshot()
	var path:="user://build_save.json"
	for spec:Dictionary in [{"base":"ashwood_bow","affix":"whetstone_edge","slot":"weapon"},{"base":"nine_slot_folded_belt","affix":"nine_slot_suffix_skill_row","slot":"belt"}]:
		var uid:="gear_%06d"%int(state.snapshot().next_item_serial)
		var source:Dictionary={"id":uid,"base_id":spec.base,"rarity":"normal","item_level":30,"affixes":[]}
		check(state._admit_reward_item(Items.wrap_equipment(source)),"Admit current catalog base "+spec.base)
		var candidate:Dictionary=state.snapshot()
		check(state._set_bag_currency_balance(candidate,100).ok,"Real shard funding fixture")
		# Choose a deterministic fixture revision that produces the target family;
		# production still derives the seed, no UI/caller supplies it.
		var found:=false
		for revision:int in range(200):
			var seed_text:=JSON.stringify({"rules":Craft.seed_rules_version("enchant"),"revision":revision,"item":source},"",true,true)
			var plan:=Craft.operation_plan(source,"enchant",seed_text.sha256_text().substr(0,15).hex_to_int())
			for affix:Dictionary in plan.instance.affixes:
				if affix.id==spec.affix:found=true;break
			if found:candidate.crafting.revision=revision;break
		check(found,"Target family actually reachable through current crafting "+spec.affix)
		state._accept_memory(candidate);check(state.save_build(path)==OK,"Save authority for deterministic fixture")
		var before_saves:int=state.successful_saves
		var quote:Dictionary=state.crafting_quote("enchant",uid,path)
		check(quote.ok and state.execute_crafting(quote.handle,quote.source_instance).ok,"Execute real enchant into target family")
		check(state.successful_saves==before_saves+1,"Main callback recognizes saved receipt, no second write")
		check(arena.flask_runtime.snapshot()==charges,"Craft changes preserve owned flask charge and active recovery")
		var location:Dictionary=state.location(uid)
		check(state.move_item(uid,{"kind":"equipment","slot_id":spec.slot},state.revision(),path).ok,"Equip actual crafted item")
		if spec.slot=="weapon":
			var profile:Dictionary=state.item_definition(uid).weapon_profile
			var physical:float=Weapon.resolve(profile).components.physical
			check(physical>4.0 and state.get_combat_snapshot().weapon_profile==profile,"Local W resolves from crafted affix and reaches snapshot")
			var cast:Dictionary=state.get_skill_cast("tornado")
			var assembly:Dictionary=cast.packets.parent.assembly.weapon
			check(assembly.profile==profile and is_equal_approx(assembly.contribution.physical,physical*float(assembly.coefficient)),"Actual compiled tornado consumes exact current local W")
			var before_profile:=profile.duplicate(true)
			check(state.move_item(uid,state.first_bag_position(uid),state.revision(),path).ok,"Crafted bow can return to bag")
			check(not state.get_combat_snapshot().has("weapon_profile") and cast.packets.parent.assembly.weapon.profile==before_profile,"Unequip removes current W while admitted recipe stays detached")
		else:
			check(state.active_group_capacity()==11 and state.snapshot().skill_groups.size()==11,"Crafted skill-row modifier creates live eleventh row")
			var gem:String=state.award_gem("skill:shade_bolt")
			check(not gem.is_empty() and state.move_item(gem,{"kind":"skill_main","group_id":"group_000011"},state.revision(),path).ok,"Real gem installs into crafted capacity")
			check(state.bind_group("group_000011",KEY_F1,state.revision(),path).ok,"Added row binds actual key")
			arena.mana=arena.get_stats().max_mana
			var count:int=arena.projectiles.size()
			check(arena.cast_group("group_000011") and arena.projectiles.size()>count,"Added row executes actual projectile skill")
			check(state.move_item(uid,state.first_bag_position(uid),state.revision(),path).ok,"Remove crafted capacity")
			check(state.active_group_capacity()==10 and state.location(gem).group_id=="group_000011" and not state.get_group_cast("group_000011").ok,"Capacity loss retains gem/UID but blocks inactive cast")
	print("Crafting growth consumers: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
