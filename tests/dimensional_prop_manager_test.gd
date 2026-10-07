extends SceneTree
const PropManager = preload("res://scripts/visuals/dimensional_prop_manager.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var depth := Node2D.new()
	root.add_child(depth)
	var actor := Node2D.new()
	actor.name = "ActorOwnedElsewhere"
	depth.add_child(actor)
	var manager := PropManager.new()
	manager._loaded = true
	var image := Image.create(8,8,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	manager._textures = {"wall":texture,"planter":texture,"tree":texture}
	manager._definitions = {
		"wall":{"world_footprint":[96,64],"anchor_px":[4,6],"pixels_per_world":2},
		"planter":{"world_footprint":[160,120],"anchor_px":[4,6],"pixels_per_world":2},
		"tree":{"world_footprint":[80,80],"anchor_px":[4,6],"pixels_per_world":2}}
	var source := {"id":"broken_ruins","bounds":Rect2(0,0,1200,900),"walls":[Rect2(500,150,100,384)],"revision":1}
	var original := var_to_bytes(source)
	var result := manager.configure(depth,source)
	expect(var_to_bytes(source) == original, "Authoritative geometry untouched")
	expect(result.dimensional_wall_indices == [0], "Only covered wall hidden in background")
	expect(manager.diagnostics().props == 8, "Long wall split into four pieces plus four border trees")
	var identities: Array = []
	for node: Node2D in manager._nodes:
		identities.append(node.get_instance_id())
		expect(node.get_parent() == depth and node.z_index == 0, "Props share actor depth parent and z")
	manager.configure(depth,source)
	var second: Array = []
	for node: Node2D in manager._nodes: second.append(node.get_instance_id())
	expect(identities == second, "Unchanged geometry reuses nodes")
	result.walls.clear()
	expect(manager._source.walls.size() == 1 and manager._presentation.walls.size() == 1, "Returned presentation is detached")
	manager.clear()
	expect(depth.get_child_count() == 1 and actor.get_parent() == depth, "Clear preserves actors")
	var fallback := PropManager.new()
	fallback._loaded = true
	result = fallback.configure(depth,source)
	expect(result.dimensional_wall_indices.is_empty() and fallback.diagnostics().props == 0, "Missing art keeps old walls")
	fallback.clear()
	depth.queue_free()
	await process_frame
	print("Dimensional props: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
