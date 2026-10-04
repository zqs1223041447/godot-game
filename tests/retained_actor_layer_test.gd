extends SceneTree
const Layer=preload("res://scripts/visuals/retained_actor_layer.gd")
const Factory=preload("res://scripts/monsters/monster_runtime.gd")
const Catalog=preload("res://scripts/monsters/monster_catalog.gd")
const Settings=preload("res://scripts/visuals/visual_settings.gd")
class Fixture extends Node2D:
	var enemies:Array[Dictionary]=[]
	var visual_settings=Settings.new()
	var elapsed:=0.0
	var player_pos:=Vector2(640,360)
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Fixture.new();root.add_child(host);var layer:=Layer.new();host.add_child(layer);var factory:=Factory.new()
	for id:String in Catalog.TEMPLATES:
		var enemy:Dictionary=factory.create_root(id,5,Vector2(100+host.enemies.size()*55,100),"map_boss" if id=="rift_warden" else "demo","",[],false)
		check(not enemy.is_empty(),"Every authored family has a real display fixture")
		host.enemies.append(enemy)
	var initial:PackedByteArray=var_to_bytes(host.enemies);var rng_state:int=factory.rng.state if factory.get("rng")!=null else 0
	layer.sync(host);var first:Dictionary=layer.diagnostics();var n:int=host.enemies.size()
	check(first.actors==n and first.pieces==n*3 and first.body_rebuild_requests==n,"Each identity owns exactly shadow limbs body")
	for unused:int in range(12):host.elapsed+=0.137;layer.sync(host)
	check(layer.diagnostics().body_rebuild_requests==n,"Continuous elapsed leaves static bodies retained")
	check(var_to_bytes(host.enemies)==initial,"Visual synchronization is read-only")
	for enemy:Dictionary in host.enemies:enemy.pos+=Vector2(0.113,0.071)
	layer.sync(host);check(layer.diagnostics().body_rebuild_requests==n,"Subpixel movement and continuous direction do not rebuild the body")
	for enemy:Dictionary in host.enemies:enemy.flash=0.1
	layer.sync(host);check(layer.diagnostics().body_rebuild_requests==n*2,"Flash begins by invalidating every actual body")
	for enemy:Dictionary in host.enemies:enemy.flash=0.05
	layer.sync(host);check(layer.diagnostics().body_rebuild_requests==n*2,"Positive flash countdown does not rebuild identical tint")
	for enemy:Dictionary in host.enemies:enemy.flash=0.0
	layer.sync(host);check(layer.diagnostics().body_rebuild_requests==n*3,"Flash ending restores the original body")
	host.enemies[0].radius+=0.125;layer.sync(host);check(layer.diagnostics().body_rebuild_requests==n*3+1,"Exact radius change invalidates only the matching identity")
	host.enemies.reverse();var before:PackedByteArray=var_to_bytes(host.enemies);layer.sync(host)
	check(var_to_bytes(host.enemies)==before,"Y sort never mutates authoritative enemy order")
	var ordered:Array=host.enemies.duplicate();ordered.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.pos.y<b.pos.y)
	for i:int in range(n):
		for part:int in range(3):check(layer.get_child(i*3+part).enemy.id==ordered[i].id,"Retained pieces preserve original actor ordering")
	host.enemies.remove_at(0);layer.sync(host);check(layer.diagnostics().actors==n-1 and layer.get_child_count()==(n-1)*3,"Removing a corpse immediately detaches all three pieces")
	layer.clear();check(layer.diagnostics().actors==0 and layer.get_child_count()==0,"Restart/return clears retained identities before new admission")
	layer.sync(host);check(layer.diagnostics().actors==n-1,"Re-entry reconstructs current actors only")
	host.queue_free();await process_frame;await process_frame
	print("Retained actor lifecycle: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
