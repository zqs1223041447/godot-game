extends SceneTree
const Same=preload("res://scripts/items/crafting_transaction_planner.gd")
func _initialize()->void:
	var expected:Dictionary=JSON.parse_string('{"version":34}')
	expected.version=35
	var actual:Dictionary=JSON.parse_string('{"version":35}')
	assert(typeof(expected.version)==TYPE_INT and typeof(actual.version)==TYPE_FLOAT)
	assert(not Same._same_data(actual,expected))
	assert(Same._same_data(JSON.parse_string(JSON.stringify(actual)),JSON.parse_string(JSON.stringify(expected))))
	print("Migration probe diagnostic: assigned schema is int, JSON reload is float; normalized strict comparison passes. 3 checks")
	quit(0)
