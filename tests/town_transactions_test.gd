extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Catalog=preload("res://scripts/town/town_catalog.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Items=preload("res://scripts/items/unified_item_catalog.gd")
const Locations=preload("res://scripts/items/item_location_rules.gd")
class FaultModel extends Model:
	var fail_save:=false
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:return ERR_CANT_CREATE if fail_save else super._write_bytes(path,bytes)
const PATH:="user://town_test_build_save.json"
var checks:=0
var failures:=0
func _initialize()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var state:=FaultModel.new();check(state.save_build(PATH)==OK,"Open isolated town test profile")
	var before:=state.snapshot();var bytes:=FileAccess.get_file_as_bytes(PATH)
	seed(991);var expected:=randi();seed(991)
	var total:=0
	for service:String in ["skill_merchant","equipment_merchant","jewel_merchant"]:
		for offer:Dictionary in Catalog.offers(service):
			total+=1
			var wrapped:=Catalog.make_item(offer,123)
			check(Items.validate_instance(wrapped),"Every supplied catalog base produces valid canonical payload "+offer.id)
			var result:=state.town_claim_offer(offer.id,state.revision(),PATH)
			check(result.ok,"Atomic actual offer admitted "+offer.id)
			if offer.supply_kind!="currency":check(state.item(result.uid).definition_id==wrapped.definition_id and state.location(result.uid).kind=="bag","Correct supply UID and actual footprint "+offer.id)
	check(randi()==expected,"All stock/transactions use no combat RNG")
	check(Catalog.offers("skill_merchant").size()==26 and Catalog.offers("jewel_merchant").size()==4,"All current26gem and4jewel definitions supplied")
	check(state.crafting_balance()==100,"Test currency is one actual inventory source")
	var quote_revision:=state.revision();var result:=state.town_claim_offer("skill:bolt",quote_revision,PATH)
	check(result.ok and not state.town_claim_offer("skill:bolt",quote_revision,PATH).ok,"Stale double click cannot create a second item")
	before=state.snapshot();bytes=FileAccess.get_file_as_bytes(PATH);state.fail_save=true
	check(not state.town_claim_offer("skill:bolt",state.revision(),PATH).ok and state.snapshot()==before and FileAccess.get_file_as_bytes(PATH)==bytes,"Supply write failure preserves UID allocator, inventory and disk")
	state.fail_save=false
	check(state.town_claim_offer("skill:bolt",state.revision(),PATH).ok,"Same request can retry after save recovery")
	before=state.snapshot();check(not state.town_claim_offer("skill:bolt",state.revision(),"user://build_save.json").ok and state.snapshot()==before,"Direct model cannot supply into normal save")
	check(not state.town_claim_offer("unimplemented",state.revision(),PATH).ok,"Unimplemented stock ID rejected")
	# A fresh model allows a causal remote-jewel reset without unrelated stock.
	var reset:=FaultModel.new();var reset_path:="user://passive-reset.json";check(reset.save_build(reset_path)==OK,"Save reset fixture")
	for id:String in ["2151","37690","48423","6230"]:check(reset.allocate_passive(id,0,reset.revision(),reset_path).ok,"Real path to source socket")
	var jewel:=reset.award_special_jewel();check(reset.move_item(jewel,{"kind":"passive_socket","node_id":"6230"},reset.revision(),reset_path).ok,"Socket real remote jewel")
	check(reset.allocate_passive("26740",0,reset.revision(),reset_path).ok,"Spend final point on actual remote source")
	before=reset.snapshot();bytes=FileAccess.get_file_as_bytes(reset_path);reset.fail_save=true
	check(not reset.reset_all_passives(reset.revision(),reset_path).ok and reset.snapshot()==before and FileAccess.get_file_as_bytes(reset_path)==bytes,"Reset save failure preserves tree and socket authority")
	reset.fail_save=false
	var old_points:int=reset.talent_points;result=reset.reset_all_passives(reset.revision(),reset_path)
	check(result.ok and result.refunded_points==5 and result.returned_jewels==1 and reset.talent_points==old_points+5,"Full reset refunds actual points once")
	check(reset.location(jewel).kind=="bag" and reset.item(jewel)==before.items[jewel] and reset.snapshot().talents.allocated.size()==1,"Jewel UID/payload preserved; only source start remains")
	check(reset.snapshot().migration_ledger==before.migration_ledger and reset.snapshot().skill_groups==before.skill_groups,"Budget ledger and all gem groups unchanged")
	# Full bag: reset must use visible recovery, never discard the socketed jewel.
	var full:=FaultModel.new();full._accept_memory(before);var full_path:="user://full-reset.json"
	var candidate:=full.snapshot();var context:=Model.Migration.paged_location_context(candidate,full._socket_ids)
	var occupied:Dictionary=Locations.validate_current(Items.metadata_for_items(candidate.items),candidate.locations,context).occupied_cells
	for page:int in range(2):
		for y:int in range(10):
			for x:int in range(12):
				if occupied.has("bag:%d:%d:%d"%[page,x,y]):continue
				var uid:="filled_%d_%d_%d"%[page,x,y];candidate.items[uid]=Model.Gems.create_instance(uid,"skill:bolt");candidate.locations[uid]={"kind":"bag","page":page,"x":x,"y":y}
	full._accept_memory(candidate);check(full.save_build(full_path)==OK,"Valid full240bag fixture")
	result=full.reset_all_passives(full.revision(),full_path)
	check(result.ok and full.location(jewel).kind=="recovery" and full.pending_items().has(jewel),"Full-bag reset retains socket jewel in visible recovery")
	check(Rules.reason(full.snapshot()).is_empty(),"Final reset candidate passes full ownership/point validation")
	print("Town transactions: %d offers, %d checks, %d failures"%[total,checks,failures]);quit(1 if failures else 0)
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(why)
