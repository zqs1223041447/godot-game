extends SceneTree
const Preview = preload("res://scripts/combat/damage_preview.gd")
func _initialize() -> void:
	var cast := {"skill_id":"basic", "recipe":{"delivery":"melee", "radius":60.0},"snapshot":{"effects":["explode_on_flight_end"],"explosion_recipe":{"radius":50.0,"area_multiplier":1.5}}}
	var before := var_to_bytes(cast)
	var lines := Preview.spatial_details(cast)
	if not lines.is_empty() or var_to_bytes(cast) != before:
		push_error("Melee basic must not imply projectile-ending explosion or mutate input")
		quit(1)
		return
	cast.recipe.delivery = "projectile"
	if Preview.spatial_details(cast).size() != 2:
		push_error("Existing non-melee explosion preview must remain unchanged")
		quit(1)
		return
	print("Melee explosion preview: 3 checks, 0 failures")
	quit(0)
