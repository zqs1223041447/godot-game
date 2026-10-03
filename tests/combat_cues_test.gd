extends SceneTree
const Runtime = preload("res://scripts/visuals/combat_cues.gd")
const Renderer = preload("res://scripts/visuals/combat_cue_renderer.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	var pool := Runtime.new()
	var source := {"destination":Vector2(20,30),"radius":200.0,"direction":Vector2(2,0),"skill":"chain","color":Color.CYAN,"untrusted_object":RefCounted.new()}
	var first: int = pool.emit_cue("chain",Vector2(1,2),source)
	expect(first==1 and pool.cues.size()==1,"admitted cue returns stable ID")
	source.radius = 999.0
	source.destination = Vector2.ZERO
	expect(pool.cues[0].radius == 200 and pool.cues[0].destination == Vector2(20,30),"caller mutation cannot alter cue")
	expect(not pool.cues[0].has("untrusted_object"),"only value fields copied")
	expect(pool.cues[0].direction == Vector2.RIGHT,"directions normalized")
	expect(pool.emit_cue("invalid",Vector2.ZERO)==0,"unknown cue rejected")
	expect(pool.emit_cue("chain",Vector2(INF,0))==0,"nonfinite origin rejected")
	expect(pool.emit_cue("chain",Vector2.ZERO,{"destination":Vector2(NAN,0)})==0,"nonfinite destination rejected")
	expect(pool.emit_cue("chain",Vector2.ZERO,{"radius":NAN})==0,"nonfinite radius rejected")
	expect(pool.emit_cue("impact",Vector2.ZERO,{"color":Color(NAN,0,0)})==0,"nonfinite color rejected")
	pool.emit_cue("cast",Vector2.ZERO,{"radius":9999,"direction":Vector2.ZERO})
	expect(pool.cues.back().radius == 500 and pool.cues.back().direction==Vector2.RIGHT,"radius bounded and zero direction safe")
	pool.advance(-1)
	pool.advance(NAN)
	pool.advance(INF)
	expect(pool.cues[0].age==0,"invalid time does not alter pool")
	pool.advance(0.1)
	expect(is_equal_approx(float(pool.cues[0].age),0.1),"valid time advances presentation only")
	pool.advance(1)
	expect(pool.cues.is_empty(),"expired cues all removed")
	pool.reset()
	for i: int in range(Runtime.MAX_CUES):
		pool.emit_cue("impact",Vector2.ZERO)
	var boundary_id: int = pool.emit_cue("nova",Vector2.ZERO,{"radius":155.0})
	expect(pool.cues.size()==Runtime.MAX_CUES and pool.cues.back().id==boundary_id,"essential boundary replaces oldest cosmetic at cap")
	for i: int in range(Runtime.MAX_CUES*2):
		pool.emit_cue("impact",Vector2.ZERO)
	expect(pool.cues.any(func(cue:Dictionary)->bool:return cue.id==boundary_id),"cosmetics cannot evict essential boundary")
	pool.reset()
	for i: int in range(Runtime.MAX_CUES):
		pool.emit_cue("chain",Vector2.ZERO,{"destination":Vector2(100,0)})
	expect(pool.emit_cue("impact",Vector2.ZERO)==0,"cosmetic rejected when pool is entirely essential")
	expect(pool.cues.size()==Runtime.MAX_CUES,"all-essential overflow stays bounded")
	for i: int in range(1000):
		pool.emit_cue("meteor",Vector2(i%1280,i%720),{"radius":110})
		expect(pool.cues.size()<=Runtime.MAX_CUES,"stress capacity %d"%i)
	pool.advance(0.7)
	expect(pool.cues.is_empty(),"stress pool drains within longest lifetime")
	for kind: String in Runtime.LIFETIMES:
		var cue_id:int=pool.emit_cue(kind,Vector2.ZERO,{"half_angle":PI/2} if kind=="cleave" else {})
		expect(cue_id>0,"declared kind admits its valid geometry "+kind)
		expect(float(pool.cues.back().duration)>0 and float(pool.cues.back().duration)<=0.65,"bounded lifetime "+kind)
	expect(Renderer.GROUND.has("meteor") and not Renderer.GROUND.has("chain"),"ground and target-link layers distinct")
	pool.reset()
	expect(pool.cues.is_empty() and pool.next_id==1 and pool.dropped==0,"reset removes transient feedback")
	print("combat_cues_test: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: "+message)
