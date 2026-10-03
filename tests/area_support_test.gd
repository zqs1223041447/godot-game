extends SceneTree
const Rules = preload("res://scripts/combat/area_support_rules.gd")
const Registry = preload("res://scripts/combat/support_registry.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Data = preload("res://scripts/game_data.gd")
const Model = preload("res://scripts/build_state.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	call_deferred("run")
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func near(actual: float, expected: float, label: String) -> void:
	expect(absf(actual-expected)<0.00001, "%s %.9f / %.9f" % [label,actual,expected])
func run() -> void:
	seed(18001)
	var expected_rng: int = randi()
	seed(18001)
	var state := Model.new()
	var snapshot: Dictionary = state.get_combat_snapshot()
	var original: Dictionary = snapshot.duplicate(true)
	expect(Rules.definition_error(Rules.get_definition("breadth")).is_empty(), "Own executable metadata validates")
	expect(Registry.SUPPORTS.size()==16 and Registry.MAX_SUPPORTS==2, "Batched catalog choices, two per-skill slots")
	for skill: String in Data.SKILLS:
		var eligible: bool = skill in ["nova","meteor"]
		expect(Registry.supports_for_skill(skill).has("breadth")==eligible,"Explicit area compatibility " + skill)
		if not eligible:
			expect(not Compiler.compile_skill(skill,snapshot,["breadth"]).ok,"No silent support no-op " + skill)
	for skill: String in ["nova","meteor"]:
		var base: Dictionary = Compiler.compile_skill(skill,snapshot,[])
		var wide: Dictionary = Compiler.compile_skill(skill,snapshot,["breadth"])
		var radius: float = 155.0 if skill=="nova" else 110.0
		expect(base.ok and wide.ok,"Compile zero and one area support")
		expect(base.recipe=={"radius":radius},"No-support recipe exactly preserves original radius")
		near(wide.recipe.radius,186.0 if skill=="nova" else 132.0,"Literal accepted radii")
		near(pow(wide.recipe.radius/base.recipe.radius,2),1.44,"Area is radius squared, not linear")
		near(wide.mana,28.8 if skill=="nova" else 38.4,"Exact costs")
		near(wide.cooldown,base.cooldown,"Cooldown unchanged")
		expect(wide.initial_count==0 and not wide.snapshot.has("initial_count"),"Area does not reserve phantom projectile slots")
		near(Damage.resolve(wide.packets.direct,wide.snapshot.modifiers).total,Damage.resolve(base.packets.direct,base.snapshot.modifiers).total*0.85,"Direct packet total multiplier")
		expect(base.packets==wide.packets,"Base/added effectiveness unchanged; support is one scoped more factor")
		expect(Preview.details(wide).contains("面积 ×1.44") and Preview.details(wide).contains("平方根"),"Preview explains geometry")
		for version: int in range(1,12):
			expect(not Registry.saved_links_reason(skill,["breadth"],version).is_empty(),"Old vocabulary rejects new ID")
		expect(Registry.saved_links_reason(skill,["breadth"],12).is_empty(),"Schema12 explicitly accepts ID")
		for bad: Variant in [["breadth","breadth"],["breadth","volley"],["breadth","focus"],["breadth","pierce"],["breadth","bad"],["breadth",1],[true],null,{},"breadth"]:
			var result: Dictionary = Rules.compile_area(skill,{"radius":radius},bad)
			expect(not result.error.is_empty() and result.recipe.is_empty() and result.modifiers.is_empty() and result.mana_multiplier==1.0,"Malformed/mixed selection has no partial effects")
		for bad: Variant in [-1,0,1001,INF,NAN,true,"155",null]:
			expect(not Rules.compile_area(skill,{"radius":bad},[]).error.is_empty(),"Invalid radius fails before admission")
		expect(not Rules.compile_area(skill,wide.recipe,["breadth"]).error.is_empty(),"Re-entry recipe rejected")
		expect(not Compiler.compile_skill(skill,wide.snapshot,["breadth"]).ok,"Re-entry snapshot rejected")
		var detached: Dictionary = wide.duplicate(true)
		detached.recipe.radius=1
		detached.snapshot.modifiers.clear()
		expect(Compiler.compile_skill(skill,snapshot,["breadth"])==wide,"Returned recipes/modifiers are detached")
		for other: String in Data.SKILLS:
			if other==skill: continue
			var cast: Dictionary = Compiler.compile_skill(other,snapshot,[])
			for entry: Dictionary in Preview.entries(cast):
				near(Damage.resolve(entry.packet,wide.snapshot.modifiers).total,Damage.resolve(entry.packet,snapshot.modifiers).total,"Other skills and explosion scope unaffected")
	for op: String in Rules.OPERATIONS:
		for value: Variant in [INF,NAN,"1",null,true,-99.0,0.0,100.0]:
			var definition: Dictionary = Rules.get_definition("breadth")
			for operation: Dictionary in definition.operations:
				if operation.op==op: operation.value=value
			expect(not Rules.definition_error(definition).is_empty(),"Invalid operation rejects " + op)
	var duplicated: Dictionary = Rules.get_definition("breadth")
	duplicated.operations[1]=duplicated.operations[0].duplicate()
	expect(not Rules.definition_error(duplicated).is_empty(),"Duplicate op cannot replace damage tradeoff")
	expect(snapshot==original,"Inputs remain unmodified")
	expect(randi()==expected_rng,"Pure compile consumes no global RNG")
	print("Area support rules: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
