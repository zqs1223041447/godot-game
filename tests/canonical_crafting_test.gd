extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
class FaultModel extends Model:
	var fail_save := false
	func _write_bytes(path: String,bytes: PackedByteArray)->Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path,bytes)
var checks := 0
var failures := 0
func _initialize()->void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated+"/"):
		quit(78)
		return
	var state := FaultModel.new()
	var path := "user://canonical-craft-%d.json" % Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1887
	var ids: Array[String] = []
	for i:int in range(5): ids.append(state.award_equipment(rng,30,"rare","nine_slot"))
	check(not ids.has(""),"actual new-pool items admitted")
	check(state.save_build(path)==OK,"save coherent inventory")
	var preserve: Dictionary = state.snapshot()
	var source: Dictionary = state.item(ids[0]).payload
	var quote: Dictionary = state.crafting_quote("salvage",ids[0],path)
	check(quote.ok and not quote.has("seed") and not quote.has("candidate"),"issued economics only")
	check(not state.execute_crafting("forged",source).ok,"forged handle rejected")
	var wrong := source.duplicate(true)
	wrong.affixes.reverse()
	check(not state.execute_crafting(quote.handle,wrong).ok,"source mismatch rejected")
	check(state.snapshot()==preserve,"rejections no mutations")
	var result := state.execute_crafting(quote.handle,source)
	check(result.ok and state.item(ids[0]).is_empty(),"salvage removes one UID")
	check(state.crafting_balance()==int(quote.materials.calibration_shard),"salvage exact material amount")
	check(state.snapshot().crafting.keys() == ["revision"],"schema16 persists no second materials ledger")
	check(state.snapshot().items.size()==preserve.items.size()-1,"all gems and other items retained")
	check(not state.execute_crafting(quote.handle,source).ok,"repeated confirmation cannot consume twice")
	for i:int in [1,2]:
		source=state.item(ids[i]).payload
		quote=state.crafting_quote("salvage",ids[i],path)
		check(quote.ok and state.execute_crafting(quote.handle,source).ok,"earn real material through salvage")
	source=state.item(ids[3]).payload
	quote=state.crafting_quote("recalibrate",ids[3],path)
	check(quote.ok,"recalibrate affordable quote")
	var before:=state.snapshot()
	var balance_before:=state.crafting_balance()
	var disk:=FileAccess.get_file_as_bytes(path)
	state.fail_save=true
	check(not state.execute_crafting(quote.handle,source).ok,"atomic write failure surfaced")
	check(before==state.snapshot() and disk==FileAccess.get_file_as_bytes(path),"failure preserves full canonical build and wallet")
	state.fail_save=false
	var seed_text:=JSON.stringify({"rules":Craft.RULES_VERSION,"revision":int(before.crafting.revision),"item":source},"",true,true)
	var expected:=Craft.recalibrate_plan(source,seed_text.sha256_text().substr(0,15).hex_to_int())
	check(state.execute_crafting(quote.handle,source).ok,"same quote retries safely")
	check(state.item(ids[3]).payload==expected.instance,"released seed contract unchanged")
	check(state.crafting_balance()==balance_before-int(quote.cost.calibration_shard),"one exact payment")
	var reopened:=Model.new()
	check(reopened.load_build(path) and reopened.snapshot()==state.snapshot(),"wallet and all item locations roundtrip")
	quote=state.crafting_quote("salvage",ids[4],path)
	check(quote.ok,"fresh quote")
	check(state.load_build(path),"reload current save")
	check(not state.execute_crafting(quote.handle,state.item(ids[4]).payload).ok,"load clears quote authority")
	quote=state.crafting_quote("salvage",ids[4],path)
	state.add_xp(1)
	check(not state.execute_crafting(quote.handle,state.item(ids[4]).payload).ok,"intervening full-build mutation rejects old quote")
	print("Canonical crafting: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
