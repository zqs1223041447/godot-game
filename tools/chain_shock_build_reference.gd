extends SceneTree
const Exporter = preload("res://tools/export_reference.gd")
func _initialize() -> void:
	var result := {"chain_shock_build":Exporter.chain_shock_build_example()}
	FileAccess.open("res://docs/qa/chain-shock-build/reference-fragment.json",FileAccess.WRITE).store_string(JSON.stringify(Exporter.clean(result),"\t",true,true)+"\n")
	print("CHAIN_SHOCK_REFERENCE actual owned fixture recompiled read-only")
	quit()
