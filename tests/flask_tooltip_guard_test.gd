extends SceneTree
func _initialize() -> void:
	var slot=load("res://scripts/ui/flask_slot.gd").new()
	var failures:=0
	if slot._make_custom_tooltip("")!=null: failures+=1
	slot.editing=true;slot.status={"uid":"occupied"}
	if slot._make_custom_tooltip("空药剂槽")!=null: failures+=1
	slot.free()
	print("Flask tooltip guard: 2 checks, %d failures"%failures)
	quit(1 if failures else 0)
