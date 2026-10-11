extends SceneTree
const Compiler = preload("/tmp/godot-shade-inward-baseline/skill_compiler.gd")
func _initialize() -> void:
 var source = Compiler.Recipes.snapshot({"damage":26.0},[])
 var before = Compiler.compile_group("shade_bolt",source,[])
 var selected = Compiler.compile_group("shade_bolt",source,["inward_pull"])
 print(JSON.stringify({"baseline":"6dbf3f9","plain_ok":before.ok,"selected_ok":selected.ok,"reason":selected.error,"mana":before.mana,"recipe":before.recipe}))
 quit(0 if before.ok and not selected.ok else 1)
