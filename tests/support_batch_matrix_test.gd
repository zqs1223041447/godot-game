extends SceneTree
## One consolidated compiler matrix: all legal zero/one/two-slot selections.
const Model=preload("res://scripts/build_state.gd")
const Data=preload("res://scripts/game_data.gd")
const Registry=preload("res://scripts/combat/support_registry.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
const Recipes=preload("res://scripts/combat/combat_data.gd")
const Expected: Dictionary={
	"tornado":["volley","focus","physical_focus","fire_focus","efficiency","quickcast"],
	"bolt":["volley","focus","pierce","swift_projectiles","heavy_projectiles","lightning_focus","efficiency","quickcast"],
	"frost":["volley","focus","pierce","swift_projectiles","heavy_projectiles","cold_focus","lingering_chill","efficiency","quickcast"],
	"nova":["breadth","concentrate","lightning_focus","efficiency","quickcast"],
	"meteor":["breadth","concentrate","fire_focus","efficiency","quickcast"],
	"chain":["chain_extension","chain_reach","lightning_focus","efficiency","quickcast"],
	"dash":["efficiency","quickcast"],"ward":["efficiency","quickcast"],
}
const MANA: Dictionary={"volley":1.30,"focus":1.20,"pierce":1.20,"breadth":1.20,"concentrate":1.20,
	"physical_focus":1.15,"fire_focus":1.15,"cold_focus":1.15,"lightning_focus":1.15,
	"swift_projectiles":1.10,"heavy_projectiles":1.15,"lingering_chill":1.10,"chain_extension":1.30,"chain_reach":1.15,
	"efficiency":0.80,"quickcast":1.40}
const PRIMARY: Dictionary={"volley":0.80,"focus":1.25,"pierce":0.85,"breadth":0.85,"concentrate":1.25,
	"heavy_projectiles":1.20,"lingering_chill":0.90,"chain_extension":0.80,"chain_reach":0.90}
const ELEMENTS: Dictionary={"physical_focus":"physical","fire_focus":"fire","cold_focus":"cold","lightning_focus":"lightning"}
var checks: int=0
var failures: int=0
var rows: int=0
var counts: Dictionary={}
func _initialize() -> void: call_deferred("run")
func expect(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func near(actual: float,expected: float,label: String) -> void:
	expect(absf(actual-expected)<0.00001,"%s %.9f / %.9f" % [label,actual,expected])
static func combinations(ids: Array) -> Array:
	var result: Array=[[]]
	for i: int in ids.size():
		result.append([ids[i]])
		for j: int in range(i+1,ids.size()): result.append([ids[i],ids[j]])
	return result
func run() -> void:
	seed(19001)
	var expected_rng: int=randi()
	seed(19001)
	expect(Registry.SUPPORTS.size()==16 and Model.SAVE_VERSION==13,"One batch of16 choices, one schema13 gate")
	for id: String in Registry.SUPPORTS:
		var definition: Dictionary=Registry.get_definition(id)
		expect(not definition.is_empty() and Registry.definition_error(definition).is_empty(),"Every registered program is valid: "+id)
	for skill: String in Data.SKILLS:
		var expected: Array=Expected[skill].duplicate();expected.sort()
		var eligible: Array=Registry.supports_for_skill(skill);eligible.sort()
		expect(eligible==expected,"Exact native capability whitelist: "+skill)
		counts[skill]=combinations(eligible).size()
		for id: String in Registry.SUPPORTS:
			expect(Registry.compatibility_reason(skill,[id]).is_empty()==expected.has(id),"No silent no-op eligibility: "+skill+"/"+id)
		for config: int in range(3):
			var state:=Model.new()
			if config==1:
				for item: String in ["prism_bow","return_mantle","detonation_charm"]: state.equip(item)
			var snapshot: Dictionary=state.get_combat_snapshot()
			if config==2:
				# Synthetic positive components exercise type filtering; no claim these
				# all exist together on an obtainable item in this prototype.
				snapshot.added_damage={"attack":{"physical":7.0,"fire":5.0,"cold":3.0,"lightning":2.0,"chaos":1.0},
					"spell":{"physical":4.0,"fire":6.0,"cold":8.0,"lightning":10.0,"chaos":2.0}}
			var original: Dictionary=snapshot.duplicate(true)
			var base: Dictionary=Compiler.compile_skill(skill,snapshot,[])
			expect(base.ok,"Zero-support baseline compiles: "+skill)
			for links: Array in combinations(eligible):
				var cast: Dictionary=Compiler.compile_skill(skill,snapshot,links)
				expect(cast.ok,"Matrix compile %s/%s/%d" % [skill,str(links),config])
				if not cast.ok: continue
				rows+=1
				var reverse: Array=links.duplicate();reverse.reverse()
				expect(Compiler.compile_skill(skill,snapshot,reverse)==cast,"Complete compiled output is order-independent")
				var cost: float=float(Data.SKILLS[skill].mana)
				var cooldown: float=float(Data.SKILLS[skill].cooldown)
				for id: String in links:
					cost*=float(MANA[id])
					if id=="efficiency": cooldown*=1.15
					if id=="quickcast": cooldown*=0.80
				near(cast.mana,cost,"Exact combined mana")
				near(cast.cooldown,cooldown,"Exact combined cooldown")
				var count: int=(3+int(snapshot.projectile_count)) if skill=="tornado" else 3 if skill=="bolt" else 5 if skill=="frost" else 0
				if links.has("volley"): count+=2
				expect(cast.initial_count==mini(count,9),"Unchanged global initial projectile semantics")
				if skill in ["nova","meteor"]:
					var area: float=(1.44 if links.has("breadth") else 1.0)*(0.64 if links.has("concentrate") else 1.0)
					near(cast.recipe.get("area_multiplier",1.0),area,"Area factors multiply")
					near(cast.recipe.radius,(155.0 if skill=="nova" else 110.0)*sqrt(area),"One square root of product; no incremental rounding")
				if skill in ["bolt","frost"]:
					near(cast.recipe.speed,(780.0 if skill=="bolt" else 520.0)*(1.35 if links.has("swift_projectiles") else 1.0)*(0.75 if links.has("heavy_projectiles") else 1.0),"Travel speed factors")
					near(cast.recipe.slow,(3.0 if skill=="frost" else 0.0)*(1.50 if links.has("lingering_chill") else 1.0),"Existing slow duration only")
					expect(cast.recipe.pierce==(1 if skill=="bolt" else 2)+(2 if links.has("pierce") else 0),"Pierce budget stays independent")
				if skill=="chain":
					expect(cast.packets.bounces.size()==(7 if links.has("chain_extension") else 5),"Chain count includes initial target")
					near(cast.recipe.first_range,600.0,"First targeting range unchanged")
					near(cast.recipe.followup_range,286.0 if links.has("chain_reach") else 220.0,"Followup range compiled")
				for role: String in ["parent","child","projectile","direct","secondary"]:
					if cast.packets.has(role): check_packet(cast.packets[role],base.packets[role],cast.snapshot.modifiers,snapshot.modifiers,links,role=="secondary")
				if skill=="chain":
					var spec: Dictionary=Data.SKILLS.chain.hit_recipe.duplicate(true);spec.bounce_count=7
					for index: int in cast.packets.bounces.size():
						near(cast.packets.bounces[index].assembly.base_coefficient,2.2-index*0.2,"Original per-target coefficient falloff")
						check_packet(cast.packets.bounces[index],Recipes.chain_packet(snapshot,spec,index),cast.snapshot.modifiers,snapshot.modifiers,links,false)
				if skill in ["dash","ward"]:
					expect(cast.packets.is_empty() and cast.recipe.is_empty() and cast.snapshot.modifiers==snapshot.modifiers,"Utility changes only resource timing")
				expect(not Compiler.compile_skill(skill,cast.snapshot,links).ok,"Frozen snapshot cannot be recompiled")
				expect(snapshot==original,"No input mutation in any matrix row")
				for version: int in [12,13]:
					var new_id: bool=false
					for id: String in links:
						if not id in ["volley","focus","pierce","breadth"]: new_id=true
					expect(Registry.saved_links_reason(skill,links,version).is_empty()==(version==13 or not new_id),"Single shared new-ID schema gate")
			for id: String in eligible:
				expect(not Compiler.compile_skill(skill,snapshot,[id,id]).ok,"Duplicate slots reject")
				expect(not Compiler.compile_skill(skill,snapshot,[id,"invalid"]).ok,"Unknown mixed ID rejects")
				expect(not Compiler.compile_skill(skill,snapshot,[id,"efficiency","quickcast"]).ok,"Global two-slot bound never truncates")
	expect(randi()==expected_rng,"Entire matrix consumes no global RNG")
	print("SUPPORT_BATCH_MATRIX "+JSON.stringify({"supports":16,"rows":rows,"per_skill_combinations":counts}))
	print("Support batch matrix: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func check_packet(actual: Dictionary,base: Dictionary,modifiers: Array,base_modifiers: Array,links: Array,secondary: bool) -> void:
	expect(actual==base,"Support modifiers do not secretly alter raw base or added-effectiveness assembly")
	var before: Dictionary=Damage.resolve(base,base_modifiers)
	var after: Dictionary=Damage.resolve(actual,modifiers)
	for type: String in Damage.TYPES:
		var multiplier: float=1.0
		if not secondary:
			for id: String in links:
				multiplier*=float(PRIMARY.get(id,1.0))
				if ELEMENTS.has(id): multiplier*=1.20 if ELEMENTS[id]==type else 0.80
		near(after.components.get(type,0.0),float(before.components.get(type,0.0))*multiplier,"Per-component primary/secondary scope algebra")
