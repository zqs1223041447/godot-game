class_name MapAdmission
extends RefCounted
## Extends the existing factory transaction; failure never leaks a partial root
## or consumes a queued descendant. No RNG or combat settlement lives here.
const Compiler=preload("res://scripts/world/map_compiler.gd")
const Rules=preload("res://scripts/world/map_defense_rules.gd")
const Encounter=preload("res://scripts/encounters/encounter_admission.gd")
const BossAttacks=preload("res://scripts/monsters/map_boss_profiles.gd")

static func create_root(runtime:RefCounted,profile:Variant,template_id:String,wave:int,position:Vector2,context:String,rarity:String,mechanisms:Array,rewards:bool)->Dictionary:
	var reason:=Compiler.profile_reason(profile)
	if reason.is_empty() and context=="map_boss":reason=BossAttacks.profile_reason(profile)
	if not reason.is_empty():return {"ok":false,"error":reason}
	var before:Dictionary=Encounter._snapshot(runtime)
	var enemy:Dictionary
	if profile.normal_ids.is_empty():
		enemy=runtime.create_root(template_id,wave,position,context,rarity,mechanisms,rewards)
	else:
		var admitted:=Encounter.create_root(runtime,profile.encounter_profile,template_id,wave,position,context,rarity,mechanisms,rewards)
		if not admitted.ok:return admitted
		enemy=admitted.enemy
	if enemy.is_empty():
		Encounter._restore(runtime,before);return {"ok":false,"error":"地图怪物生成失败"}
	var applied:Dictionary=Rules.apply_to_enemy(enemy,profile) if Rules.active(profile) else {"ok":true,"error":"","enemy":enemy}
	if applied.ok and context=="map_boss":applied=BossAttacks.attach(applied.enemy,profile)
	if not applied.ok:Encounter._restore(runtime,before)
	return applied

static func drain(runtime:RefCounted,profile:Variant,available:int,bounds:Rect2)->Dictionary:
	var reason:=Compiler.profile_reason(profile)
	if not reason.is_empty():return {"ok":false,"error":reason}
	if available<=0 or runtime.queue.is_empty():return {"ok":true,"error":"","enemies":[]}
	var before:Dictionary=Encounter._snapshot(runtime)
	var enemies:Array[Dictionary]
	if profile.normal_ids.is_empty():enemies=runtime.drain(available,bounds)
	else:
		var admitted:=Encounter.drain(runtime,profile.encounter_profile,available,bounds)
		if not admitted.ok:return admitted
		enemies.assign(admitted.enemies)
	if enemies.size()!=mini(available,before.queue.size()):
		Encounter._restore(runtime,before);return {"ok":false,"error":"地图子怪生成失败，队列已保留"}
	if not Rules.active(profile):return {"ok":true,"error":"","enemies":enemies}
	var output:Array[Dictionary]=[]
	for enemy:Dictionary in enemies:
		var applied:=Rules.apply_to_enemy(enemy,profile)
		if not applied.ok:
			Encounter._restore(runtime,before);return {"ok":false,"error":str(applied.error)}
		output.append(applied.enemy)
	return {"ok":true,"error":"","enemies":output}
