extends SceneTree
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
func _initialize() -> void:
	var current := Store.new().snapshot()
	var parsed := Source.line_effect("+1% to maximum Fire Resistance")
	var compound := Source.line_effect("+2% to all maximum Elemental Resistances")
	assert(current.version == 36 and parsed.supported and compound.grants.size() == 3)
	print("Schema36 source and store compile/default initialization passed")
	quit()
