extends "res://tests/passive_action_preview_test.gd"
## Bounded differential subset against the existing frozen transaction oracle.
func core_cases() -> void:
	compare_case("first-step",base_source,"2151",0,true,false)
	compare_case("disconnected-source",base_source,"26740",0,false,false,"invalid_candidate","断连")
	var chain:=selection(["58833","2151","37690","48423"],{},1)
	compare_case("legal-leaf-refund",chain,"48423",0,false,true)
	compare_case("bridge-disconnection",chain,"37690",0,false,false,"invalid_candidate","断连","refund")
