extends SceneTree
## Focused v101 scheduler/geometry suite. Main settlement and rendering are separate.
const Runtime=preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Bosses=preload("res://scripts/monsters/map_boss_profiles.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Frozen=preload("res://docs/qa/v101-runtime/frozen/telegraphed_area_runtime.gd")
const FrozenBosses=preload("res://docs/qa/v101-runtime/frozen/map_boss_profiles.gd")
const CENTER=Vector2(345.25,456.5)
const PATTERN="ginkgo_shelter_slam"
const EPS=0.000000001
var checks:=0
var failures:=0

func _expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)

func _near(actual:float,expected:float,label:String)->void:
	_expect(is_finite(actual) and absf(actual-expected)<EPS,"%s: %.12f expected %.12f"%[label,actual,expected])

func _enemy(id:int=1,pattern:String=PATTERN)->Dictionary:
	return {"id":id,"root_id":id,"generation":0,"template_id":"rift_warden","rarity":"boss",
		"map_boss_attack_id":pattern,"pos":CENTER,"health":100.0,"spawn":0.0,"death_processed":false,
		"damage":100.0,"attack_speed":Monsters.BASE_ATTACK_SPEED,"contact_weights":{"physical":0.5,"fire":0.3,"cold":0.2}}

func _start(runtime:RefCounted,enemy:Dictionary,center:Vector2=CENTER)->Dictionary:
	var policy:Dictionary=Monsters.telegraph_policy(enemy)
	return runtime.start(enemy,center,policy.profile,policy.visual_pattern)

func _initialize()->void:
	if OS.get_name()!="Linux" or not OS.get_data_dir().begins_with("/tmp/godot-m1-v101-"):
		push_error("Use isolated Linux XDG storage under /tmp/godot-m1-v101-*");quit(2);return
	_test_authority_and_speed()
	_test_stages_and_snapshots()
	_test_partitions_capacity_and_order()
	_test_freeze_and_cancellation()
	_test_invalid_admission()
	_test_annulus_boundaries()
	_test_frozen_unchanged_paths()
	print("Ginkgo ring runtime: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _test_authority_and_speed()->void:
	var rule:=Bosses.definition(PATTERN)
	_expect(rule.target_rule=="self_at_start" and rule.trigger_distance==240.0,"Self-locked center and trigger stay authoritative")
	_expect(rule.pulse_count==2 and rule.pulse_interval==1.0 and rule.second_pulse=={"shape":"annulus","inner_radius":130.0,"radius":240.0,"windup_seconds":1.0},"Second stage authority is explicit")
	for speed:float in [0.01,0.2,Monsters.BASE_ATTACK_SPEED,2.0,10000.0]:
		var enemy:=_enemy();enemy.attack_speed=speed
		var policy:Dictionary=Monsters.telegraph_policy(enemy)
		_expect(policy.target_rule=="self_at_start" and policy.trigger_distance==240.0 and policy.visual_pattern==PATTERN,"Catalog retains targeting and identity")
		_expect(policy.profile.radius==130.0 and policy.profile.windup_seconds==1.4 and policy.profile.damage_multiplier==0.6,"Speed never changes first stage geometry, warning or budget")
		var recovery:float=clampf(1.9*Monsters.BASE_ATTACK_SPEED/maxf(0.2,speed),0.001,60.0)
		_near(policy.profile.recovery_seconds,recovery,"Only recovery uses catalog speed scaling")
		var runtime:=Runtime.new();_expect(_start(runtime,enemy).ok,"Scaled policy admits")
		var events:=runtime.advance(2.4,[enemy]);_expect(events.size()==2,"Every speed retains both complete warnings")
		_near(events[0].attack_age,1.4,"First warning deadline");_near(events[1].attack_age,2.4,"Second warning deadline")
		_near(runtime.state_for(enemy.id).elapsed,1.0,"Recovery presentation starts after full second warning")
		_expect(runtime.advance(recovery,[enemy]).is_empty() and runtime.active_count()==0,"Scaled recovery finishes exactly")

func _stage(runtime:RefCounted,index:int,phase:String,elapsed:float,label:String)->void:
	var state:Dictionary=runtime.state_for(1)
	_expect(not state.is_empty(),label+" exists")
	if state.is_empty():return
	_expect(state.phase==phase and state.pulse_index==index and state.pulse_count==2 and state.visual_pattern==PATTERN,label+" stage")
	_expect(state.center==CENTER and state.shape==("circle" if index==0 else "annulus") and state.inner_radius==(0.0 if index==0 else 130.0),label+" shape and frozen center")
	_expect(state.profile.radius==(130.0 if index==0 else 240.0) and state.profile.windup_seconds==(1.4 if index==0 else 1.0),label+" current stage profile")
	_near(state.elapsed,elapsed,label+" local presentation elapsed")

func _test_stages_and_snapshots()->void:
	var enemy:=_enemy();var runtime:=Runtime.new();var profile:Dictionary=Monsters.telegraph_policy(enemy).profile
	var inputs:=var_to_bytes([enemy,profile]);seed(101101);var expected_rng:=randi();seed(101101)
	var started:Dictionary=runtime.start(enemy,CENTER,profile,PATTERN)
	_expect(started.ok and started.attack.attack_id==1 and runtime.has_timed_sequence_actions(),"One timed action starts")
	_stage(runtime,0,"windup",0.0,"First warning")
	var before:=var_to_bytes(runtime.state_for(1))
	started.attack.profile.radius=1.0;started.attack.packet.base.fire=999.0;started.attack.second_pulse.inner_radius=1.0;started.attack.pulses_emitted=99
	_expect(var_to_bytes(runtime.state_for(1))==before,"Start response is fully detached")
	_expect(runtime.advance(1.399,[enemy]).is_empty(),"First warning cannot fire early")
	var first:=runtime.advance(0.001,[enemy]);_expect(first.size()==1,"First deadline emits once")
	if first.size()!=1:return
	_expect(first[0].type=="circle_attack" and first[0].shape=="circle" and first[0].radius==130.0 and first[0].inner_radius==0.0,"First receipt is an inner circle")
	_expect(first[0].profile_id=="ginkgo_inner_outer" and first[0].balance_version=="original-ginkgo-inner-outer-v1" and first[0].schema_version==1 and first[0].packet.skill_id=="ginkgo_inner_outer","Receipts identify the Ginkgo sequence")
	_expect(first[0].packet.base=={"physical":30.0,"fire":18.0,"cold":12.0} and first[0].packet.tags==["attack","area","hit"],"First stage has exactly 0.6D with original components and tags")
	_expect(var_to_bytes([enemy,profile])==inputs,"Caller inputs stay untouched")
	_stage(runtime,1,"windup",0.0,"Second warning begins after first event")
	var snapshot:=runtime.state_for(1);before=var_to_bytes(snapshot)
	snapshot.elapsed=99.0;snapshot.profile.radius=1.0;snapshot.packet.tags.clear();snapshot.second_pulse.windup_seconds=0.01
	_expect(var_to_bytes(runtime.state_for(1))==before,"Second-stage visual snapshot is deeply detached")
	first[0].packet.base.fire=999.0;first[0].profile.radius=1.0;first[0].center=Vector2.ZERO
	enemy.pos=Vector2(999,999);enemy.damage=9999.0;enemy.attack_speed=10000.0;enemy.contact_weights={"chaos":1.0};profile.damage_multiplier=99.0
	_expect(not _start(runtime,enemy,Vector2.ZERO).ok,"Moving source cannot start a competing cast")
	_expect(runtime.advance(0.5,[enemy]).is_empty(),"Half of second warning does no damage")
	_stage(runtime,1,"windup",0.5,"Second warning midpoint")
	_expect(runtime.advance(0.499,[enemy]).is_empty(),"Second warning cannot fire early")
	var second:=runtime.advance(0.001,[enemy]);_expect(second.size()==1,"Second deadline emits once")
	if second.size()!=1:return
	_expect(second[0].type=="annulus_attack" and second[0].shape=="annulus" and second[0].radius==240.0 and second[0].inner_radius==130.0,"Second receipt is the outer annulus")
	_expect(second[0].center==CENTER and second[0].attack_id==1 and second[0].pulse_index==1 and second[0].pulse_count==2,"Both stages retain one center and cast identity")
	_expect(second[0].profile.windup_seconds==1.0 and second[0].profile.radius==240.0 and second[0].profile.damage_multiplier==0.6,"Annulus receipt reports its current stage")
	_expect(second[0].packet.base=={"physical":30.0,"fire":18.0,"cold":12.0} and second[0].packet.tags==["attack","area","hit"],"Packet snapshot was taken once before enemy mutation")
	_stage(runtime,1,"recovery",1.0,"Final recovery")
	_near(runtime.state_for(1).profile.recovery_seconds,1.9,"Mid-cast speed cannot shorten recovery")
	_expect(runtime.advance(0.0,[enemy]).is_empty(),"Zero delta cannot replay")
	_expect(runtime.advance(1.899,[enemy]).is_empty() and runtime.active_count()==1,"Recovery persists to endpoint")
	_expect(runtime.advance(0.001,[enemy]).is_empty() and runtime.active_count()==0 and not runtime.has_timed_sequence_actions(),"Total 4.3 seconds completes")
	_expect(runtime.advance(1.0e308,[enemy]).is_empty(),"Finished cast never replays")
	_expect(randi()==expected_rng,"Pure scheduling consumes no RNG")

func _trajectory(steps:Array)->Array:
	var enemy:=_enemy();var runtime:=Runtime.new();_start(runtime,enemy)
	var elapsed:=0.0;var events:Array=[]
	for delta:float in steps:
		for event:Dictionary in runtime.advance(delta,[enemy]):
			_near(elapsed+event.step_time,event.attack_age,"Local offset reconstructs event time")
			_expect(event.step_time>=0.0 and event.step_time<=delta+EPS,"Event time belongs to supplied frame")
			event.erase("step_time");events.append(event)
		elapsed+=delta
	_expect(events.size()==2 and runtime.active_count()==0 and runtime.advance(100.0,[enemy]).is_empty(),"Partition completes with exactly two nonreplayable events")
	return events

func _test_partitions_capacity_and_order()->void:
	var whole:=var_to_bytes(_trajectory([4.3]));var frames:Array=[]
	for _frame:int in range(258):frames.append(1.0/60.0)
	for partition:Array in [[0.0,1.4,0.0,1.0,1.9],[0.4,1.0,0.2,0.8,0.9,1.0],frames,[1.0e308]]:
		_expect(var_to_bytes(_trajectory(partition))==whole,"Event bytes match all frame partitions except frame-local time")
	var runtime:=Runtime.new();var live:Array=[]
	for id:int in range(100,0,-1):
		var enemy:=_enemy(id);live.append(enemy);_expect(_start(runtime,enemy).ok,"Admit bounded source")
	_expect(not _start(runtime,_enemy(101)).ok and runtime.active_count()==100,"101st action rejects without eviction")
	var events:=runtime.advance(1.0e308,live)
	_expect(events.size()==200 and runtime.active_count()==0,"Huge delta yields exactly two events for each of 100 sources")
	for index:int in range(events.size()):
		_expect(events[index].source_id==index%100+1 and events[index].pulse_index==index/100,"Stable deadline/source ordering")

func _test_freeze_and_cancellation()->void:
	var enemy:=_enemy();var runtime:=Runtime.new();_start(runtime,enemy)
	var before:=var_to_bytes(runtime.state_for(1))
	_expect(runtime.advance(2.0,[enemy],true,{1:2.0}).is_empty() and var_to_bytes(runtime.state_for(1))==before,"Full freeze preserves first warning")
	var events:=runtime.advance(2.0,[enemy],true,{1:0.6})
	_expect(events.size()==1,"Partial frozen prefix resumes first warning")
	if events.size()==1:_near(events[0].step_time,2.0,"First deadline accounts for frozen prefix")
	_stage(runtime,1,"windup",0.0,"Freeze resumes into full second warning")
	before=var_to_bytes(runtime.state_for(1))
	_expect(runtime.advance(2.0,[enemy],false,{1:2.0}).is_empty() and var_to_bytes(runtime.state_for(1))==before,"Full freeze preserves second warning")
	events=runtime.advance(1.5,[enemy],false,{1:0.5});_expect(events.size()==1,"Second warning resumes once")
	if events.size()==1:_near(events[0].step_time,1.5,"Sequence retains precise event time without explicit timing flag")
	_stage(runtime,1,"recovery",1.0,"Recovery after freeze")
	for bad_prefix:Dictionary in [{1:-1.0},{1:INF},{1:2.1},{2:0.5},{1:true}]:
		before=var_to_bytes(runtime.state_for(1))
		_expect(runtime.advance(2.0,[enemy],true,bad_prefix).is_empty() and var_to_bytes(runtime.state_for(1))==before,"Malformed prefix transaction cannot change action")
	for elapsed:float in [0.7,1.4,1.9,2.4]:
		for mode:String in ["dead","protected","processed","removed","cancel","reset"]:
			enemy=_enemy();runtime=Runtime.new();_start(runtime,enemy);runtime.advance(elapsed,[enemy])
			var live:Array=[enemy]
			match mode:
				"dead":enemy.health=0.0
				"protected":enemy.spawn=0.1
				"processed":enemy.death_processed=true
				"removed":live.clear()
				"cancel":runtime.cancel(1)
				"reset":runtime.reset()
			_expect(runtime.advance(0.0,live).is_empty() and runtime.active_count()==0,"Liveness/cancel/reset clears stage: "+mode)
			_expect(runtime.advance(99.0,[_enemy()]).is_empty(),"Cancelled second stage never revives")
			var restarted:=_start(runtime,_enemy())
			_expect(restarted.ok and restarted.attack.attack_id==2 and restarted.attack.pulse_index==0,"Restart allocates new identity and full warning")
	# Liveness must still cancel during a fully frozen frame.
	enemy=_enemy();runtime=Runtime.new();_start(runtime,enemy);runtime.advance(1.4,[enemy]);enemy.health=0.0
	_expect(runtime.advance(10.0,[enemy],true,{1:10.0}).is_empty() and runtime.active_count()==0,"Full pause never suppresses liveness cancellation")
	# Resumed events across sources sort using wall-clock offsets.
	var other:=_enemy(2);enemy=_enemy();runtime=Runtime.new();_start(runtime,enemy);_start(runtime,other)
	events=runtime.advance(3.0,[enemy,other],true,{1:0.5})
	_expect(events.size()==4 and events[0].source_id==2 and events[1].source_id==1 and events[2].source_id==2 and events[3].source_id==1,"Frozen-prefix offsets sort before source identity")

func _reject(enemy:Variant,profile:Variant,pattern:Variant,label:String,center:Vector2=CENTER)->void:
	var runtime:=Runtime.new()
	_expect(not runtime.start(enemy,center,profile,pattern).ok and runtime.active_count()==0,label)
	_expect(_start(runtime,_enemy()).attack.attack_id==1,label+" does not allocate identity")

func _test_invalid_admission()->void:
	var good:=_enemy();var profile:Dictionary=Monsters.telegraph_policy(good).profile
	for pattern:Variant in ["",null,1,true,[],"unknown","sunwell_echo","ember_burn"]:_reject(good,profile,pattern,"Missing/forged visual authority rejects")
	for overrides:Variant in [null,true,[],{}, {"pulse_count":2}, {"second_pulse":{"inner_radius":0.0}}, {"radius":130.0}, {"shape":"annulus"}]:_reject(good,overrides,PATTERN,"Malformed or partial stage override rejects")
	for field:String in ["radius","windup_seconds","damage_multiplier","recovery_seconds"]:
		for value:Variant in [null,true,"1",NAN,INF,-INF,-1.0]:
			var invalid:=profile.duplicate(true);invalid[field]=value;_reject(good,invalid,PATTERN,"Invalid numeric override "+field)
		var changed:=profile.duplicate(true);changed[field]+=0.001;_reject(good,changed,PATTERN,"Valid but unauthorized stage budget "+field)
	for row:Array in [["root_id",2],["generation",1],["template_id","crawler"],["rarity","rare"],["map_boss_attack_id","sunwell_echo"],["health",0.0],["spawn",0.1],["death_processed",true],["attack_speed",0.0],["attack_speed",INF],["damage",NAN],["damage",-1.0]]:
		var invalid:=good.duplicate(true);invalid[row[0]]=row[1];_reject(invalid,profile,PATTERN,"Invalid source authority "+row[0])
	for weights:Variant in [null,true,[],{}, {"physical":0.5},{"chaos":-1.0},{"fire":NAN},{"unknown":1.0},{"physical":true}]:
		var invalid:=good.duplicate(true);invalid.contact_weights=weights;_reject(invalid,profile,PATTERN,"Malformed contact components")
	for point:Vector2 in [Vector2(INF,0),Vector2(0,NAN)]:_reject(good,profile,PATTERN,"Nonfinite center rejects",point)
	for invalid_delta:float in [0.0,-1.0,NAN,INF,-INF]:
		var runtime:=Runtime.new();_start(runtime,good);runtime.advance(1.4,[good]);var before:=var_to_bytes(runtime.state_for(1))
		_expect(runtime.advance(invalid_delta,[good]).is_empty() and var_to_bytes(runtime.state_for(1))==before,"Invalid/zero delta freezes pending ring")
	for universe:Variant in [null,{},true,[null],[{}],[good,good]]:
		var runtime:=Runtime.new();_start(runtime,good);runtime.advance(1.4,[good])
		_expect(runtime.advance(99.0,universe).is_empty() and runtime.active_count()==0,"Ambiguous source universe cancels entire sequence")

func _test_annulus_boundaries()->void:
	var event:Dictionary={"shape":"annulus","center":Vector2.ZERO,"inner_radius":130.0,"radius":240.0}
	# Main.PLAYER_RADIUS is 15.0; 16 additionally covers nearby arbitrary target sizes.
	_expect("const PLAYER_RADIUS := 15.0" in FileAccess.get_file_as_string("res://scripts/main.gd"),"Real player radius source remains 15")
	for radius:float in [0.0,15.0,16.0,130.0,300.0]:
		_expect(Runtime.overlaps(event,Vector2(240.0+radius,0),radius),"Outer tangency counts")
		_expect(not Runtime.overlaps(event,Vector2(240.01+radius,0),radius),"Beyond outer reach misses")
		if radius<130.0:
			_expect(Runtime.overlaps(event,Vector2(130.0-radius,0),radius),"Inner tangency counts")
			_expect(not Runtime.overlaps(event,Vector2(129.99-radius,0),radius),"Whole target inside hole is safe")
		else:_expect(Runtime.overlaps(event,Vector2.ZERO,radius),"Large target crosses inner edge even from center")
	_expect(not Runtime.overlaps(event,Vector2.ZERO,15.0) and Runtime.overlaps(event,Vector2(180,0),15.0),"Actual player can stay in center or be hit in ring")
	for field:String in ["inner_radius","radius"]:
		for value:Variant in [null,true,"1",[],NAN,INF,-INF,-1.0]:
			var invalid:=event.duplicate(true);invalid[field]=value;_expect(not Runtime.overlaps(invalid,Vector2(180,0),15.0),"Malformed annulus geometry rejects "+field)
	for inner:float in [0.0,240.0,241.0]:
		var invalid:=event.duplicate(true);invalid.inner_radius=inner;_expect(not Runtime.overlaps(invalid,Vector2(240,0),15.0),"Zero-hole/empty/inverted ring rejects")
	for radius:float in [-1.0,NAN,INF,-INF]:_expect(not Runtime.overlaps(event,Vector2(180,0),radius),"Malformed target radius rejects")
	for point:Vector2 in [Vector2(INF,0),Vector2(0,NAN)]:
		_expect(not Runtime.overlaps(event,point,15.0),"Nonfinite target center rejects")
		var invalid:=event.duplicate(true);invalid.center=point;_expect(not Runtime.overlaps(invalid,Vector2(180,0),15.0),"Nonfinite ring center rejects")
	var enormous:=event.duplicate(true);enormous.center=Vector2(1.0e30,1.0e30);enormous.inner_radius=1.0e30;enormous.radius=1.0e31
	_expect(Runtime.overlaps(enormous,Vector2(-1.0e30,1.0e30),0.0),"Finite huge center avoids float32 squared-distance overflow")
	enormous.inner_radius=1.0e20;enormous.radius=2.0e20
	_expect(not Runtime.overlaps(enormous,Vector2(-1.0e30,1.0e30),0.0),"Huge separated centers cannot overflow into a false positive")
	enormous.center=Vector2.ZERO;enormous.inner_radius=1.0e307;enormous.radius=1.0e308
	_expect(Runtime.overlaps(enormous,Vector2.ZERO,1.0e308),"Finite radii whose sum overflows are normalized safely")
	_expect(not Runtime.overlaps(enormous,Vector2.ZERO,1.0e306),"Huge annulus still protects fully contained target")

func _legacy_records(script:Script,enemy:Dictionary,timed:bool)->Dictionary:
	var runtime:RefCounted=script.new();var policy:Dictionary=Monsters.telegraph_policy(enemy)
	var profile:Dictionary=policy.get("profile",{});var pattern:String=policy.get("visual_pattern","")
	var start:Dictionary=runtime.start(enemy,CENTER,profile,pattern)
	var row:Dictionary={"start":start,"states":[runtime.state_for(enemy.id)],"events":[],"timed":[],"busy":runtime.start(enemy,CENTER,profile,pattern)}
	var windup:float=start.attack.profile.windup_seconds;var recovery:float=start.attack.profile.recovery_seconds
	for delta:float in [0.0,windup*0.5,windup*0.5,0.4,0.4,recovery*0.5,recovery*0.5,100.0]:
		row.events.append(runtime.advance(delta,[enemy],timed));row.states.append(runtime.state_for(enemy.id));row.timed.append(runtime.has_timed_sequence_actions())
	row.restart=runtime.start(enemy,CENTER,profile,pattern);row.paused=runtime.advance(windup+0.25,[enemy],timed,{int(enemy.id):0.25});row.paused_state=runtime.state_for(enemy.id)
	row.cancelled=runtime.advance(0.0,[]);row.after_cancel=runtime.state_for(enemy.id)
	row.errors=[]
	for bad:Variant in [null,true,[],{"unknown":1}, {"radius":NAN}]:row.errors.append(runtime.start(enemy,CENTER,bad,pattern))
	return row

func _test_frozen_unchanged_paths()->void:
	for pattern:String in ["garden_slam","ruins_mark","sunwell_echo"]:
		_expect(var_to_bytes(Bosses.definition(pattern))==var_to_bytes(FrozenBosses.definition(pattern)),"Other boss authority is byte-identical to bdea0872: "+pattern)
		for timed:bool in [false,true]:
			var enemy:=_enemy(1,pattern)
			_expect(var_to_bytes(_legacy_records(Runtime,enemy,timed))==var_to_bytes(_legacy_records(Frozen,enemy,timed)),"Frozen complete boss receipts/states/errors: %s timed=%s"%[pattern,timed])
	for template:String in ["crawler","ember_guard","frost_guard","storm_skitter","chaos_guard"]:
		var enemy:Dictionary=Monsters.make_enemy(1,template,6,Vector2(111,222),"ordinary");enemy.spawn=0.0
		for timed:bool in [false,true]:
			_expect(var_to_bytes(_legacy_records(Runtime,enemy,timed))==var_to_bytes(_legacy_records(Frozen,enemy,timed)),"Frozen complete ordinary receipts/states/errors: %s timed=%s"%[template,timed])
	for radius:Variant in [90.0,0.0,1.0e308,-1.0,NAN,INF,true,null]:
		for point:Vector2 in [Vector2.ZERO,Vector2(105,0),Vector2(105.01,0),Vector2(1.0e30,0),Vector2(INF,0)]:
			var event:Dictionary={"shape":"circle","center":Vector2.ZERO,"radius":radius}
			_expect(Runtime.overlaps(event,point,15.0)==Frozen.overlaps(event,point,15.0),"Legacy circle geometry remains exact, including malformed and overflow behavior")
