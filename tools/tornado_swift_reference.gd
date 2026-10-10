extends SceneTree
## Bounded projection through the existing reference/compiler helpers.
const Exporter = preload("res://tools/export_reference.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Registry = preload("res://scripts/combat/support_registry.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
func _initialize() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/catalog.json"))
	var full := Exporter.Build.new()
	for id: String in Exporter.Data.COMBAT_STARTER_ITEMS: full.equip(id)
	var builds := {"fresh":Exporter.Canonical.new(), "full_tornado":full,
		"local_normal":Exporter.local_build(Exporter._local_instance()),
		"local_max":Exporter.local_build(Exporter._local_instance(["whetstone_edge","tempered_edge","wellturn","beatlink"],"rare"))}
	var examples := {}
	var target: Dictionary = catalog.known_target
	for config: String in builds:
		examples[config] = []
		var choices: Array = [["swift_projectiles"]]
		for id: String in Registry.supports_for_skill("tornado"):
			if id != "swift_projectiles": choices.append([id,"swift_projectiles"])
		for selection: Array in choices:
			var cast := Compiler.compile_skill("tornado",builds[config].get_combat_snapshot(),selection)
			assert(cast.ok)
			var packets: Array = []
			for entry: Dictionary in Preview.entries(cast):
				var defended := Damage.resolve(entry.packet,cast.snapshot.modifiers,target.defense_profile.effective_resistances)
				packets.append({"label":entry.label,"packet":entry.packet,"resolved":Damage.resolve(entry.packet,cast.snapshot.modifiers),
					"known_target_resolved":defended,"known_target_settlement":Defense.settle_resolved(defended,target.shield,target.health),
					"active":entry.label != "独立爆炸" or cast.snapshot.effects.has("explode_on_flight_end")})
			var brief := Exporter.support_cast_brief(cast)
			brief.supports = cast.support_ids; brief.packets = packets
			examples[config].append(brief)
	var snapshot: Dictionary = Exporter.Build.new().get_combat_snapshot()
	var fragment := {"support":Registry.get_definition("swift_projectiles"),"gem":Gems.definition("support:swift_projectiles"),
		"compatible":Registry.supports_for_skill("tornado"),"examples":examples,
		"program_example":{"before":Exporter.support_cast_brief(Compiler.compile_skill("tornado",snapshot,[])),
			"after":Exporter.support_cast_brief(Compiler.compile_skill("tornado",snapshot,["swift_projectiles"]))}}
	FileAccess.open("res://docs/qa/tornado-swift/reference-fragment.json",FileAccess.WRITE).store_string(JSON.stringify(Exporter.clean(fragment),"\t",true,true)+"\n")
	print("TORNADO_SWIFT_REFERENCE four existing builds projected")
	quit()
