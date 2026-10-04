extends SceneTree
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const MonsterRuntime=preload("res://scripts/monsters/monster_runtime.gd")
const Runtime=preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Bosses=preload("res://scripts/monsters/map_boss_profiles.gd")
const Maps=preload("res://scripts/world/map_compiler.gd")
const Admission=preload("res://scripts/world/map_admission.gd")
const EncounterAdmission=preload("res://scripts/encounters/encounter_admission.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func prior_records()->Array:
	var records:Array=[];var id:=1
	for wave:int in [4,5,8]:
		for template:String in ["rift_warden","ember_guard","frost_guard","storm_skitter"]:
			var enemy:=Monsters.make_enemy(id,template,wave,Vector2(100,120),"level_boss" if template=="rift_warden" else "ordinary")
			records.append(enemy.duplicate(true));records.append(Monsters.telegraph_policy(enemy))
			if template!="rift_warden":
				enemy.spawn=0.0;var policy:=Monsters.telegraph_policy(enemy);var runtime:=Runtime.new()
				records.append(runtime.start(enemy,Vector2(200,120),policy.profile));records.append(runtime.state_for(id))
				for delta:float in [0.3,0.4,0.25,1.5]:records.append(runtime.advance(delta,[enemy]));records.append(runtime.state_for(id))
			id+=1
	return records
func _initialize()->void:
	var file:=FileAccess.open("res://tests/fixtures/v036_map_bosses/normal-boss-telegraphs-v35.bin",FileAccess.READ);var prior:Array=file.get_var(false);var now:=prior_records()
	check(prior.size()==114 and now.size()==114,"Frozen three-wave boss and old guard trajectories exist")
	for i:int in range(114):check(var_to_bytes(prior[i])==var_to_bytes(now[i]),"Normal boss/old guard bytes unchanged at%d"%i)
	for map_id:String in ["old_garden","broken_ruins"]:
		for modifiers:Array in [[],["enemy_damage_115","enemy_attack_speed_110"]]:
			var map:Dictionary=Maps.compile(map_id,modifiers,[]).profile;var factory:=MonsterRuntime.new();var pos:=Vector2(500,420)
			var result:=Admission.create_root(factory,map,"rift_warden",map.wave,pos,"map_boss","",[],true)
			check(result.ok and result.enemy.map_boss_attack_id==map.boss_attack_id,"Canonical map boss admitted with one map policy")
			var enemy:Dictionary=result.enemy;var definition:=Bosses.definition(map.boss_attack_id);var policy:=Monsters.telegraph_policy(enemy)
			check(Monsters.uses_telegraph(enemy) and policy.visual_pattern==definition.id and policy.target_rule==definition.target_rule,"Actual monster policy exposes frozen target rule and visual identity")
			check(policy.profile.windup_seconds==definition.profile.windup_seconds and policy.profile.radius==definition.profile.radius,"Difficulty modifiers do not shorten warning or change radius")
			check(is_equal_approx(policy.profile.recovery_seconds,definition.profile.recovery_seconds*Monsters.BASE_ATTACK_SPEED/enemy.attack_speed),"Only recovery uses the existing attack-speed consumer")
			var old_factory:=MonsterRuntime.new();var old:Dictionary=old_factory.create_root("rift_warden",map.wave,pos,"map_boss","",[],true) if modifiers.is_empty() else EncounterAdmission.create_root(old_factory,map.encounter_profile,"rift_warden",map.wave,pos,"map_boss","",[],true).enemy
			var stripped:=enemy.duplicate(true);stripped.erase("map_boss_attack_id")
			check(stripped==old,"Health/shield/affixes/rewards/identity/death-spawn data unchanged")
			enemy.spawn=0.0;var target:Vector2=enemy.pos if definition.target_rule=="self_at_start" else pos+Vector2(300,0);var runtime:=Runtime.new()
			var started:=runtime.start(enemy,target,policy.profile,policy.visual_pattern)
			check(started.ok and started.attack.visual_pattern==definition.id and started.attack.center==target,"Runtime freezes exact chosen center and visual identity")
			enemy.pos+=Vector2(40,40)
			check(runtime.state_for(enemy.id).center==target,"Moving source cannot move an existing ground warning")
			check(runtime.advance(float(policy.profile.windup_seconds)-0.001,[enemy]).is_empty(),"No event before complete windup")
			var events:=runtime.advance(0.001,[enemy]);check(events.size()==1 and events[0].center==target and events[0].visual_pattern==definition.id,"Exactly one event at threshold preserves fixed pattern/point")
			check(is_equal_approx(events[0].packet.base.physical,float(enemy.damage)*float(definition.profile.damage_multiplier)),"Packet uses final shared damage and exact policy multiplier")
			check(Runtime.overlaps(events[0],target+Vector2(definition.profile.radius+15.0,0),15.0) and not Runtime.overlaps(events[0],target+Vector2(definition.profile.radius+15.01,0),15.0),"True radius plus player radius includes boundary and excludes outside")
			check(runtime.advance(50.0,[enemy]).is_empty() and runtime.active_count()==0,"Recovery emits no second attack")
			enemy.health=0.0;old.health=0.0;old.pos=enemy.pos
			check(factory.process_death(enemy)==old_factory.process_death(old),"Death reward/lineage admission remains identical")
			check(factory.queue==old_factory.queue,"Same four children queued without copying boss policy")
			var children:=factory.drain(20,Rect2(0,0,2000,1200));check(children.size()==4,"Existing boss still creates four descendants")
			for child:Dictionary in children:check(not child.has("map_boss_attack_id") and not Monsters.uses_telegraph(child) and not child.reward_eligible,"Descendant cannot inherit map boss action or reward")
		var profile:Dictionary=Maps.compile(map_id,[],[]).profile;var factory:=MonsterRuntime.new();var before:Dictionary=EncounterAdmission._snapshot(factory)
		var tampered:=profile.duplicate(true);tampered.boss_attack_id="unknown"
		check(not Admission.create_root(factory,tampered,"rift_warden",profile.wave,Vector2.ZERO,"map_boss","",[],true).ok and EncounterAdmission._snapshot(factory)==before,"Malformed policy rejects before root identity/lineage mutation")
		var enemy:Dictionary=Admission.create_root(factory,profile,"rift_warden",profile.wave,Vector2.ZERO,"map_boss","",[],true).enemy;enemy.spawn=0.0
		var runtime:=Runtime.new();var policy:=Monsters.telegraph_policy(enemy)
		check(not runtime.start(enemy,Vector2.ZERO,policy.profile,"unknown").ok and runtime.active_count()==0,"Unknown visual identity rejects atomically")
		check(runtime.start(enemy,Vector2.ZERO,policy.profile,policy.visual_pattern).attack.attack_id==1,"Rejected metadata consumes no attack identity")
		runtime.cancel(enemy.id);check(runtime.advance(50.0,[enemy]).is_empty(),"Canceled map action never settles")
		runtime.start(enemy,Vector2.ZERO,policy.profile,policy.visual_pattern);runtime.reset();check(runtime.advance(50.0,[enemy]).is_empty(),"Run reset discards old map events")
		enemy.map_boss_attack_id="unknown";check(Monsters.uses_telegraph(enemy) and Monsters.telegraph_policy(enemy).is_empty(),"Corrupted action cannot silently become contact damage")
	var slam:=Bosses.definition("garden_slam");check(slam.trigger_distance<=float(slam.profile.radius)+15.0,"Slam begins with stationary player inside the true circle")
	print("Map boss rules: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
