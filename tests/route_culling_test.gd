extends SceneTree
const Layer=preload("res://scripts/visuals/static_arena_layer.gd")
const Layout=preload("res://scripts/world/exploration_map_layout.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var layer:=Layer.new();root.add_child(layer)
	var geometry:Dictionary=Layout.layout("old_garden",Layout.WORLD_BOUNDS)
	layer.configure(Layout.WORLD_BOUNDS,ThemeDB.fallback_font)
	layer.set_geometry(geometry)
	await process_frame
	assert(layer._route_parts.size()==216)
	assert(layer.get_children()[-1]==layer._camp_signs)
	var first:Node2D=layer._route_parts[0]
	layer.configure(Layout.WORLD_BOUNDS,ThemeDB.fallback_font);layer.set_geometry(geometry)
	assert(first==layer._route_parts[0])
	for i in range(215):assert(layer._route_parts[i].index==i)
	layer.set_geometry({})
	await process_frame
	assert(layer._route_parts.is_empty())
	assert(layer.get_child_count()==1)
	layer.set_geometry(geometry)
	await process_frame
	assert(layer._route_parts.size()==216)
	assert(layer.get_child_count()==217)
	layer.free()
	print("ROUTE_LIFECYCLE_PASS");quit()
