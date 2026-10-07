extends SceneTree
const DependencyPlan = preload("res://tools/diagnostics/burn_read_dependency_shadow.gd")
const ClockRule = preload("res://scripts/combat/ember_event_clock.gd")
const FeedbackRule = preload("res://scripts/combat/combat_feedback_runtime.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _initialize() -> void: call_deferred("run")

func row(id: int, start: float = 0.0) -> Dictionary:
	return {"target_id":id, "last_time":start, "expires_at":2.0, "raw_dps":8.0}

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v097-read-"): quit(78); return
	if OS.get_environment("V097_RESET_ONLY") == "1":
		reset_checks();finish("reset-results.json");return
	var times: Array = [0.008498710574771513, 0.008495442978210952, 0.008485886630782776]
	var events: Array = []
	for index: int in range(times.size()): events.append({"time":times[index], "sequence":30-index})
	var input_bytes := var_to_bytes(events)
	for start: float in [0.0, 1000000.0]:
		var plan: Dictionary = DependencyPlan.prepare_events(events, start, start+1.0/60.0, start)
		check(plan.ok and plan.records.size()==3, "Original adjacent near-tie chain accepted")
		for index: int in range(3):
			check(plan.records[index].sequence==30-index, "Original non-ID event order preserved")
			check(plan.records[index].burn_at==start+times[0], "Burn clock uses original normalized offset")
			check(plan.records[index].shock_at==start+times[index], "Shock reads raw offset independently")
		check(not DependencyPlan.prepare_events([{"time":0.01},{"time":0.009}], start,start+0.02,start).ok, "True reverse rejected at either uptime")
		check(not DependencyPlan.prepare_events([{"time":0.001}],start,start+0.02,start+0.01).ok, "Initial clock cannot enlarge relative tie tolerance")
	check(var_to_bytes(events)==input_bytes, "Clock preparation leaves input bytes unchanged")
	check(DependencyPlan.prepare_events([{"time":0.0}],0.0,0.02,0.0).watermark==0.0, "Next batch has no previous watermark")
	check(DependencyPlan.prepare_events([{"time":0.000009}],0.0,0.02,0.00001).records[0].burn_at==0.00001, "Existing relative tie to initial watermark retained")
	for invalid: Variant in [null, {}, [{}], [{"time":true}], [{"time":NAN}], [{"time":INF}], [{"time":-1.0}]]:
		var rejected := DependencyPlan.prepare_events(invalid,0.0,0.1,0.0)
		check(not rejected.ok and rejected.records.is_empty() and rejected.requires_original_path, "Invalid whole plan yields no partial records")
	var rows: Array = [row(3),row(1),row(2)]
	var before := var_to_bytes(rows)
	var plan := DependencyPlan.read_plan(rows,"contact",0.125,[2],[])
	check(plan.ok and plan.materialize_ids==[1,2,3] and plan.first_positive_feedback_ids==[1,2,3], "First positive receipts retain original ID order")
	plan=DependencyPlan.read_plan(rows,"contact",0.125,[2],[1,2,3])
	check(plan.materialize_ids==[2] and plan.first_positive_feedback_ids.is_empty(), "Existing buckets allow target-only plan")
	plan=DependencyPlan.read_plan(rows,"refresh",0.125,[1],[1,2,3])
	check(plan.materialize_ids==[1], "Equal/stronger/weaker refresh must read old target first")
	plan=DependencyPlan.read_plan(rows,"expiry",2.0,[2],[1,2,3])
	check(plan.materialize_ids==[2] and plan.drain_due_before_reads, "Expiry reads are subordinate to due-death drain")
	for operation: String in ["burn_death","direct_lethal","observation","batch_exit","phase_exit"]:
		plan=DependencyPlan.read_plan(rows,operation,0.125,[2],[1,2,3])
		check(plan.materialize_ids==[1,2,3] and plan.mode=="full_barrier", "Boundary retains full original-ID barrier: "+operation)
	plan=DependencyPlan.read_plan(rows,"contact",0.125,[2],[1,2,3],true)
	check(plan.mode=="eager_replay" and plan.materialize_ids==[1,2,3] and not plan.numerical_equivalence_proven, "Uncertainty explicitly requires original-cut replay, not epsilon acceptance")
	check(var_to_bytes(rows)==before, "All plans leave source rows unchanged")
	plan.materialize_ids.clear()
	check(DependencyPlan.read_plan(rows,"batch_exit",0.125,[],[]).materialize_ids==[1,2,3], "Result mutation cannot affect later plans")
	check(DependencyPlan.read_plan([row(1,0.125)],"contact",0.125,[1],[]).first_positive_feedback_ids.is_empty(), "Zero-width contact does not reserve feedback")
	for invalid_rows: Variant in [null,[row(1),row(1)],[{"target_id":1}], [{"target_id":1,"last_time":1.0,"expires_at":2.0,"raw_dps":8.0}]]:
		check(not DependencyPlan.read_plan(invalid_rows,"contact",0.125,[],[]).ok, "Invalid or future state requires old path")
	check(not DependencyPlan.read_plan(rows,"unknown",0.125,[],[]).ok, "Unknown reader requires old path")
	check(not DependencyPlan.read_plan(rows,"contact",0.125,[true],[]).ok, "Boolean IDs are not coerced")
	check(not DependencyPlan.read_plan(rows,"contact",0.125,[],[1,1]).ok, "Duplicate pending facts rejected")
	var many: Array=[]
	for id: int in range(1,102): many.append(row(id))
	check(not DependencyPlan.read_plan(many,"contact",0.125,[],[]).ok, "101-target read plan rejected atomically")
	feedback_case(100, false)
	feedback_case(10, true)
	reset_checks()
	finish("read-results.json")

func reset_checks() -> void:
	var rows: Array = [row(1)]
	var original := var_to_bytes(rows)
	var reset_plan := DependencyPlan.read_plan(rows,"reset",1000000.0,[1],[],true)
	check(reset_plan.ok and reset_plan.mode=="discard", "Reset discards instead of advancing old statuses")
	check(reset_plan.materialize_ids.is_empty() and reset_plan.first_positive_feedback_ids.is_empty(), "Reset creates no damage or feedback through future time")
	check(not reset_plan.drain_due_before_reads and reset_plan.clear_queue, "Reset clears deadlines without triggering due deaths")
	check(var_to_bytes(rows)==original, "Reset dependency plan does not mutate caller state")

func finish(file_name: String) -> void:
	print("BURN_READ_SHADOW ",checks," checks / ",failures," failures")
	var f:=FileAccess.open("res://docs/qa/v097-shadow/"+file_name,FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Pure clock/read dependency and binary-exact feedback fixtures only; no Main integration, resource approximation proof or performance measurement"},"\t"));f.close()
	quit(1 if failures else 0)

func pending_ids(feedback: RefCounted) -> Array:
	var ids: Array=[]
	for pending: Dictionary in feedback._pending.values():
		if pending.target_kind=="monster" and pending.kind=="burn": ids.append(int(pending.target_id))
	return ids

func record_burn(feedback: RefCounted, id: int, amount: float) -> void:
	check(feedback.record({"target_kind":"monster","target_id":id,"kind":"burn","shield_spent":0.0,"health_lost":amount,"position":Vector2(id,0)}).ok,"Original feedback admission")

func metadata(feedback: RefCounted) -> Dictionary:
	return {"time":feedback._time,"sequence":feedback._next_sequence,"id":feedback._next_id,"pending":feedback._pending.duplicate(true),"visible":feedback._visible.duplicate(true),"entries":feedback.entries()}

func feedback_case(count: int, late_add: bool) -> void:
	var eager:=FeedbackRule.new();var lazy:=FeedbackRule.new()
	eager.advance(1.0/60.0);lazy.advance(1.0/60.0)
	var rows: Array=[]
	var eager_clocks: Dictionary={}
	for id: int in range(1,count+1): rows.append(row(id));eager_clocks[id]=0.0
	var cut_index:=0
	for at: float in [1.0/64.0,2.0/64.0,4.0/64.0]:
		for id: int in eager_clocks:
			record_burn(eager,id,8.0*(at-float(eager_clocks[id])));eager_clocks[id]=at
		var target:int=1+cut_index
		var plan:=DependencyPlan.read_plan(rows,"contact",at,[target],pending_ids(lazy))
		check(plan.ok, "Feedback-only lazy dependency plan accepted")
		for current: Dictionary in rows:
			if plan.materialize_ids.has(current.target_id):
				record_burn(lazy,current.target_id,8.0*(at-float(current.last_time)));current.last_time=at
		var hit:Dictionary={"target_kind":"monster","target_id":target,"kind":"hit","shield_spent":0.0,"health_lost":1.0,"position":Vector2(target,0)}
		eager.record(hit);lazy.record(hit)
		if late_add and cut_index==0: rows.append(row(count+1,at));eager_clocks[count+1]=at
		cut_index+=1
	var at:=4.0/64.0
	for current: Dictionary in rows:
		var amount:float=8.0*(at-float(current.last_time))
		if amount>0.0:record_burn(lazy,current.target_id,amount)
	check(var_to_bytes(metadata(eager))==var_to_bytes(metadata(lazy)), "Binary-exact first sequence, pending amounts and deadlines before publish")
	eager.flush_target("monster",2);lazy.flush_target("monster",2)
	check(var_to_bytes(metadata(eager))==var_to_bytes(metadata(lazy)), "Death flush follows complete amount synchronization")
	eager.advance(0.2);lazy.advance(0.2)
	check(eager.entries().size()<=48 and var_to_bytes(metadata(eager))==var_to_bytes(metadata(lazy)), "Visible48 priority and birth/deadline match under pressure")
	eager.advance(0.75);lazy.advance(0.75)
	check(eager.entries().is_empty() and var_to_bytes(metadata(eager))==var_to_bytes(metadata(lazy)), "Same expiry and no ghost visible rows")
