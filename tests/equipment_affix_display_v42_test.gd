extends SceneTree
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Presenter = preload("res://scripts/ui/unified_item_presentation.gd")
class ViewModel extends RefCounted:
	var payload: Dictionary
	func item(_uid: String) -> Dictionary:
		return {"uid": payload.id, "kind": "equipment", "definition_id": "equipment:" + str(payload.base_id), "payload": payload}
	func item_definition(_uid: String) -> Dictionary: return Gear.definition(payload)
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var model := ViewModel.new()
	var cases := [
		{"id":"attack_life_leech", "expected":"+0.20%"},
		{"id":"attack_mana_leech", "expected":"+0.10%"},
		{"id":"global_critical_chance", "expected":"+15%"},
		{"id":"global_critical_multiplier", "expected":"+5个百分点"},
		{"id":"rootwell", "expected":""}]
	for entry: Dictionary in cases:
		var family := Gear.affix_definition(entry.id)
		var affix := {"id":str(entry.id), "tier":1, "value":int(family.tiers[0].min)}
		model.payload = {"id":"gear_000999", "base_id":"wayglass_token", "rarity":"magic", "item_level":1, "affixes":[affix]}
		expect(Gear.validate_instance(model.payload), "Fixture is actual legal catalog equipment " + entry.id)
		var before := var_to_bytes(model.payload)
		var shown := Gear.affix_display(affix)
		var card := Presenter.view(model, model.payload.id)
		expect(card.affix_lines == [shown.line], "Item card uses exactly shared validated wording " + entry.id)
		if not str(entry.expected).is_empty(): expect(shown.value_text == entry.expected, "Correct percent or percentage point unit " + entry.id)
		expect(var_to_bytes(model.payload) == before, "Presentation leaves equipment unchanged " + entry.id)
		expect(not str(card.affix_lines).contains("装备合计"), "No unwanted summed equipment total")
	expect(not Gear.affix_display({"id":"attack_life_leech","tier":1,"value":2000}).ok, "Out of range ticks have no plausible display")
	print("Equipment affix display v42: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
