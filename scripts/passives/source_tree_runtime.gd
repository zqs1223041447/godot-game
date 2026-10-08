class_name SourceTreeRuntime
extends RefCounted
## Authoritative adapter from the pinned source graph to canonical saves.
## The private graph is validated once; each candidate still gets full selection,
## ownership, point and socket legality checks. Source artwork is never consumed.
const Data = preload("res://scripts/passives/source_tree_data.gd")
const Allocation = preload("res://scripts/passives/source_tree_allocation_rules.gd")
const Patterns = preload("res://scripts/passives/source_stat_patterns.gd")
const IronReflexes = preload("res://scripts/mechanics/iron_reflexes_rules.gd")
const ZealotsOath = preload("res://scripts/mechanics/zealots_oath_rules.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const TALENT_KEYS := ["source_version","class_id","allocated","masteries","ascendancy","ascendancy_allocated","normal_points","ascendancy_points"]
const SPATIAL_SAVE_VERSION:=20
const RECHARGE_SAVE_VERSION:=21
const RESOURCE_SAVE_VERSION:=22
const FLASK_SAVE_VERSION:=23
const CRITICAL_SAVE_VERSION:=24
const LEECH_SAVE_VERSION:=25
const FIRE_DOT_SAVE_VERSION:=32
const FASTER_BURN_SAVE_VERSION:=33
const MANA_GUARD_SAVE_VERSION:=35
const ELEMENTAL_RESISTANCE_CAP_SAVE_VERSION:=36
const RESOLUTE_TECHNIQUE_SAVE_VERSION:=38
const IRON_REFLEXES_SAVE_VERSION:=40
const ZEALOTS_OATH_SAVE_VERSION:=41
const PHYSICAL_FIRE_CONVERSION_SAVE_VERSION:=44
const PRECISE_TECHNIQUE_SAVE_VERSION:=45
const ELEMENTAL_CONVERSION_SAVE_VERSION:=48
const COLD_AILMENT_DURATION_SAVE_VERSION:=49
const ATTACK_ELEMENTAL_SAVE_VERSION:=55
const ONE_WITH_NATURE_SAVE_VERSION:=56
const IRON_GRIP_SAVE_VERSION:=57
const IRON_WILL_SAVE_VERSION:=58
const CHAOS_INOCULATION_SAVE_VERSION:=59
const CURRENT_SAVE_VERSION:=CHAOS_INOCULATION_SAVE_VERSION
static var _contexts: Dictionary = {}
static var _line_cache: Dictionary = {}
static var _node_effect_cache: Dictionary = {}
static var _analysis_key := PackedByteArray()
static var _analysis: Dictionary = {}


static func _execution_policy(version:int)->int:
	if version<SPATIAL_SAVE_VERSION:return 19
	if version<RECHARGE_SAVE_VERSION:return SPATIAL_SAVE_VERSION
	if version<RESOURCE_SAVE_VERSION:return RECHARGE_SAVE_VERSION
	if version<FLASK_SAVE_VERSION:return RESOURCE_SAVE_VERSION
	if version<CRITICAL_SAVE_VERSION:return FLASK_SAVE_VERSION
	if version<LEECH_SAVE_VERSION:return CRITICAL_SAVE_VERSION
	if version<FIRE_DOT_SAVE_VERSION:return LEECH_SAVE_VERSION
	if version<FASTER_BURN_SAVE_VERSION:return FIRE_DOT_SAVE_VERSION
	if version<MANA_GUARD_SAVE_VERSION:return FASTER_BURN_SAVE_VERSION
	if version<ELEMENTAL_RESISTANCE_CAP_SAVE_VERSION:return MANA_GUARD_SAVE_VERSION
	if version<RESOLUTE_TECHNIQUE_SAVE_VERSION:return ELEMENTAL_RESISTANCE_CAP_SAVE_VERSION
	if version<IRON_REFLEXES_SAVE_VERSION:return RESOLUTE_TECHNIQUE_SAVE_VERSION
	if version<ZEALOTS_OATH_SAVE_VERSION:return IRON_REFLEXES_SAVE_VERSION
	if version<PHYSICAL_FIRE_CONVERSION_SAVE_VERSION:return ZEALOTS_OATH_SAVE_VERSION
	if version<PRECISE_TECHNIQUE_SAVE_VERSION:return PHYSICAL_FIRE_CONVERSION_SAVE_VERSION
	if version<ELEMENTAL_CONVERSION_SAVE_VERSION:return PRECISE_TECHNIQUE_SAVE_VERSION
	if version<COLD_AILMENT_DURATION_SAVE_VERSION:return ELEMENTAL_CONVERSION_SAVE_VERSION
	if version<ATTACK_ELEMENTAL_SAVE_VERSION:return COLD_AILMENT_DURATION_SAVE_VERSION
	if version<ONE_WITH_NATURE_SAVE_VERSION:return ATTACK_ELEMENTAL_SAVE_VERSION
	if version<IRON_GRIP_SAVE_VERSION:return ONE_WITH_NATURE_SAVE_VERSION
	if version<IRON_WILL_SAVE_VERSION:return IRON_GRIP_SAVE_VERSION
	return IRON_WILL_SAVE_VERSION if version<CHAOS_INOCULATION_SAVE_VERSION else CHAOS_INOCULATION_SAVE_VERSION


static func _context(class_id: int, budget: int) -> Dictionary:
	if not Data.ready() or Data.start_for_class(class_id).is_empty(): return {}
	if not _contexts.has(class_id):
		var nodes := {}
		var adjacent := {}
		for id: String in Data.standard_ids():
			var node := Data.node(id)
			var effects: Array[int] = []
			for effect: Dictionary in node.mastery_effects: effects.append(int(effect.effect))
			nodes[id] = {"id":id,"type":"proxy" if node.source.get("isProxy",false) else node.type,
				"group_id":node.group_id,"position":node.position,"blighted":bool(node.source.get("isBlighted",false)),
				"class_id":int(node.source.get("classStartIndex",-1)),"mastery_effects":effects}
			adjacent[id] = Data.adjacency(id)
		var context := {"nodes":nodes,"adjacency":adjacent,"start_id":Data.start_for_class(class_id),"budget":123}
		if not Allocation._context_error(context).is_empty(): return {}
		_contexts[class_id] = context
	# Shallow copy only: caller never receives/mutates the private nodes/adjacency.
	var result: Dictionary = _contexts[class_id].duplicate(false)
	result.budget = budget
	return result


static func reason(candidate: Dictionary) -> String:
	return str(analyze(candidate).reason)


static func analyze(candidate: Dictionary) -> Dictionary:
	var talents: Variant = candidate.get("talents")
	if not Locations._exact_string_keys(talents,TALENT_KEYS): return _failure("天赋数据无效")
	if talents.source_version != "3.29.1" or not talents.class_id is int or talents.class_id < 0 or talents.class_id > 6: return _failure("源树或职业无效")
	if not talents.normal_points is int or talents.normal_points < 0 or talents.normal_points > 123: return _failure("普通天赋点数无效")
	# Ascendancy and expansion subgraphs remain separately browsable. They have no
	# earned-point consumer yet, and are not silently merged into the standard tree.
	if talents.ascendancy != "" or talents.ascendancy_allocated != [] or not talents.ascendancy_points is int or talents.ascendancy_points != 0:
		return _failure("升华点数来源与效果尚未接入，当前仅可浏览独立子树")
	var sockets := socket_rules(candidate)
	if not sockets.ok: return _failure(sockets.reason)
	var level: Variant = candidate.get("progress",{}).get("level")
	if not level is int or level < 1 or level > 1000: return _failure("成长等级无效")
	var budget := mini(level+4,123)
	var version:Variant=candidate.get("version",CURRENT_SAVE_VERSION)
	if not version is int:return _failure("天赋保存版本无效")
	var policy:int=_execution_policy(int(version))
	var key := var_to_bytes([talents,sockets.rules,budget,policy])
	if key == _analysis_key: return _analysis.duplicate(true)
	var context := _context(talents.class_id,budget)
	if context.is_empty(): return _failure("锁定源树不可用")
	var result := Allocation._analyze_validated_context(context,{"allocated":talents.allocated,"masteries":talents.masteries},sockets.rules)
	if result.legal and result.remaining != talents.normal_points: return _failure("天赋已用与剩余点数不符合成长预算")
	if result.legal:
		for id: String in talents.allocated:
			var execution := node_effect(id,int(talents.masteries.get(id,0)),policy)
			if execution.status != "full": return _failure("此节点仍有未实现效果，不能分配：%s" % Data.node(id).name)
	if result.legal:
		_analysis_key = key
		_analysis = result.duplicate(true)
	return result


static func socket_rules(candidate: Dictionary) -> Dictionary:
	var rules := {}
	for uid: String in candidate.get("locations",{}):
		var location: Dictionary = candidate.locations[uid]
		if location.get("kind","") != "passive_socket": continue
		var item: Dictionary = candidate.get("items",{}).get(uid,{})
		if item.get("kind") != "jewel" or not Jewels.validate_instance(item.get("payload")):
			return {"ok":false,"reason":"镶嵌珠宝实例无效","rules":{}}
		var id: String = str(location.get("node_id",""))
		if not Data.standard_socket_ids().has(id) or rules.has(id): return {"ok":false,"reason":"珠宝孔未知或重复","rules":{}}
		var rule := Jewels.allocation_rule(item.payload)
		rules[id] = {"rule_id":str(rule.get("id","")),"radius":float(rule.get("radius",0.0))}
	return {"ok":true,"reason":"","rules":rules}


static func lines_for(id: String, mastery_effect: int = 0) -> Array:
	var node := Data.node(id)
	if node.is_empty(): return []
	if node.type != "mastery": return node.stats.duplicate()
	for effect: Dictionary in node.mastery_effects:
		if int(effect.effect) == mastery_effect: return effect.stats.duplicate()
	return []


static func line_effect(line: String, save_version:int=CURRENT_SAVE_VERSION) -> Dictionary:
	var policy:int=_execution_policy(save_version)
	var key:="%d:%s"%[policy,line]
	if not _line_cache.has(key): _line_cache[key] = Patterns.parse_line(line,policy>=SPATIAL_SAVE_VERSION,policy>=RECHARGE_SAVE_VERSION,policy>=RESOURCE_SAVE_VERSION,policy>=FLASK_SAVE_VERSION,policy>=CRITICAL_SAVE_VERSION,policy>=LEECH_SAVE_VERSION,policy>=FIRE_DOT_SAVE_VERSION,policy>=FASTER_BURN_SAVE_VERSION,policy>=MANA_GUARD_SAVE_VERSION,policy>=ELEMENTAL_RESISTANCE_CAP_SAVE_VERSION,policy>=RESOLUTE_TECHNIQUE_SAVE_VERSION,policy>=IRON_REFLEXES_SAVE_VERSION,policy>=ZEALOTS_OATH_SAVE_VERSION,policy>=PHYSICAL_FIRE_CONVERSION_SAVE_VERSION,policy>=PRECISE_TECHNIQUE_SAVE_VERSION,policy>=ELEMENTAL_CONVERSION_SAVE_VERSION,policy>=COLD_AILMENT_DURATION_SAVE_VERSION,policy>=ATTACK_ELEMENTAL_SAVE_VERSION,policy>=ONE_WITH_NATURE_SAVE_VERSION,policy>=IRON_GRIP_SAVE_VERSION,policy>=IRON_WILL_SAVE_VERSION,policy>=CHAOS_INOCULATION_SAVE_VERSION)
	return _line_cache[key].duplicate(true)


static func node_effect(id: String, mastery_effect: int = 0, save_version:int=CURRENT_SAVE_VERSION) -> Dictionary:
	var policy:int=_execution_policy(save_version)
	var key := "%d:%s:%d" % [policy,id,mastery_effect]
	if _node_effect_cache.has(key): return _node_effect_cache[key].duplicate(true)
	var node := Data.node(id)
	if node.is_empty(): return {"status":"unsupported","supported":[],"unsupported":["未知源节点"],"grants":[]}
	var supported: Array = []
	var unsupported: Array = []
	var grants: Array = []
	for line: String in lines_for(id,mastery_effect):
		var parsed := line_effect(line,policy)
		if parsed.supported:
			supported.append(line)
			grants.append_array(parsed.grants)
		else: unsupported.append(line)
	var status := "full" if unsupported.is_empty() else "partial" if not supported.is_empty() else "unsupported"
	if node.type == "mastery":
		var found := false
		for effect: Dictionary in node.mastery_effects:
			if int(effect.effect) == mastery_effect: found = true
		if not found: status = "choice"
	var result := {"status":status,"supported":supported,"unsupported":unsupported,"grants":grants}
	_node_effect_cache[key] = result.duplicate(true)
	return result


static func apply_stats(stats: Dictionary, candidate: Dictionary) -> Dictionary:
	var result := stats.duplicate(true)
	var capacity_increased := {"max_health":0.0,"max_mana":0.0,"max_shield":0.0}
	var class_data := Data.class_definition(int(candidate.talents.class_id))
	for attribute: String in ["strength","dexterity","intelligence"]:
		result[attribute] = float(result.get(attribute,0.0)) + float(class_data.get("base_"+attribute.substr(0,3),0.0))
	for id: String in candidate.talents.allocated:
		var effect := node_effect(id,int(candidate.talents.masteries.get(id,0)),int(candidate.get("version",CURRENT_SAVE_VERSION)))
		for grant: Dictionary in effect.grants:
			if grant.mode == "increased" and capacity_increased.has(grant.stat):
				capacity_increased[grant.stat] += float(grant.value)
			elif grant.stat == "iron_reflexes": result.iron_reflexes = 1.0
			elif grant.stat == "zealots_oath": result.zealots_oath = 1.0
			elif grant.stat == "precise_technique" and effect.status == "full" and id == "63620": result.precise_technique = 1.0
			elif grant.stat == "iron_grip" and effect.status == "full" and id == "12926": result.iron_grip = 1.0
			elif grant.stat == "iron_will" and effect.status == "full" and id == "50288": result.iron_will = 1.0
			elif grant.stat == "chaos_inoculation" and effect.status == "full" and id == "11455": result.chaos_inoculation = 1.0
			elif grant.stat == "physical_to_fire_conversion": result.physical_to_fire_conversion = float(result.get("physical_to_fire_conversion", 0.0)) + float(grant.value)
			elif grant.stat in ["physical_to_cold_conversion", "physical_to_lightning_conversion", "cold_penetration", "lightning_penetration"] and effect.status == "full":
				result[grant.stat] = float(result.get(grant.stat, 0.0)) + float(grant.value)
			elif grant.stat == "cold_ailment_duration_increased":
				if effect.status == "full" and id == "14209": result[grant.stat] = float(result.get(grant.stat, 0.0)) + float(grant.value)
			elif result.has(grant.stat): result[grant.stat] += float(grant.value)
	# Every slotted jewel was admitted by the same allocation validator. Sum raw
	# flat/increased modifiers before final capacity/rate stages, never per item.
	for uid: String in candidate.locations:
		if candidate.locations[uid].kind != "passive_socket": continue
		var modifiers := Jewels.get_stats(candidate.items[uid].payload)
		for stat: String in modifiers:
			if result.has(stat): result[stat] += float(modifiers[stat])
	# Source-compatible aggregate attribute rounding. Intelligence ES uses the
	# 3.28+ value (per ten), not the obsolete per-five coefficient.
	for attribute: String in ["strength","dexterity","intelligence"]: result[attribute] = roundf(float(result[attribute]))
	result.max_health += floorf(float(result.strength)/2.0)
	result.max_mana += floorf(float(result.intelligence)/2.0)
	result.melee_physical_increased = float(result.get("melee_physical_increased",0.0)) + floorf(float(result.strength)/5.0)*0.01
	capacity_increased.max_shield += floorf(float(result.intelligence)/10.0)*0.01
	result.accuracy = (float(result.get("accuracy",100.0))+2.0*float(result.dexterity)) * (1.0+float(result.get("accuracy_increased",0.0)))
	if float(result.get("iron_reflexes", 0.0)) > 0.0:
		var conversion := IronReflexes.profile(float(result.get("armour", 0.0)), float(result.get("evasion", 15.0)),
			float(result.get("armour_increased", 0.0)), float(result.get("evasion_increased", 0.0)), _shared_defense_increased(candidate))
		assert(conversion.ok, "Validated source defence conversion must compile")
		result.armour = conversion.armour
		result.evasion = conversion.evasion
		result.evasion_converted_to_armour = conversion.converted_armour
	else:
		result.evasion = float(result.get("evasion",15.0)) * (1.0+float(result.get("evasion_increased",0.0))+floorf(float(result.dexterity)/5.0)*0.01)
		result.armour = float(result.get("armour",0.0))*(1.0+float(result.get("armour_increased",0.0)))
	for stat: String in capacity_increased: result[stat] *= 1.0 + float(capacity_increased[stat])
	# Final override follows every capacity source, before capacity-based recovery.
	if float(result.get("chaos_inoculation", 0.0)) == 1.0: result.max_health = 1.0
	if float(result.get("zealots_oath", 0.0)) > 0.0:
		var regeneration := ZealotsOath.profile(float(result.get("life_regen", 0.0)),
			float(result.get("life_regen_percent", 0.0)), float(result.max_shield))
		assert(regeneration.ok, "Validated source regeneration redirection must compile")
		result.life_regen = regeneration.life_rate
		result.shield_regeneration_rate = regeneration.shield_rate
	else:
		result.life_regen = float(result.get("life_regen",0.0)) + float(result.get("life_regen_percent",0.0))*float(result.max_health)
	return result


## Count a compound source modifier once on the converted portion. Two separate
## source entries never share identity, even when their numeric values are equal.
## Current equipment/jewels supply flat ratings only, so all rating-increase
## provenance is preserved here in the authoritative source entry boundary.
static func _shared_defense_increased(candidate: Dictionary) -> float:
	var shared := 0.0
	for id: String in candidate.talents.allocated:
		for line: String in lines_for(id, int(candidate.talents.masteries.get(id, 0))):
			var parsed := line_effect(line, int(candidate.get("version", CURRENT_SAVE_VERSION)))
			if not parsed.supported: continue
			var armour := 0.0
			var evasion := 0.0
			for grant: Dictionary in parsed.grants:
				if grant.mode != "increased": continue
				if grant.stat == "armour_increased": armour += float(grant.value)
				elif grant.stat == "evasion_increased": evasion += float(grant.value)
			shared += minf(armour, evasion)
	return shared


static func available(candidate: Dictionary) -> Array[String]:
	var analysis := analyze(candidate)
	var result: Array[String] = []
	if not analysis.legal or analysis.remaining <= 0: return result
	var context := _context(candidate.talents.class_id,mini(int(candidate.progress.level)+4,123))
	var choices := {}
	var notable_groups := {}
	for id: String in analysis.normal_connected:
		if context.nodes[id].type == "notable": notable_groups[context.nodes[id].group_id] = true
		for neighbor: String in context.adjacency[id]: choices[neighbor] = true
	for id: String in analysis.remote_sources: choices[id] = true
	for id: String in context.nodes:
		if context.nodes[id].type == "mastery" and notable_groups.has(context.nodes[id].group_id): choices[id] = true
	for id: String in choices:
		var node: Dictionary = context.nodes[id]
		if candidate.talents.allocated.has(id) or node.blighted or node.type in ["proxy","start"]: continue
		if node.type == "mastery" and not notable_groups.has(node.group_id): continue
		if node.type == "mastery":
			var supported_choice := false
			for effect: int in node.mastery_effects:
				if not candidate.talents.masteries.values().has(effect) and node_effect(id,effect,int(candidate.get("version",CURRENT_SAVE_VERSION))).status == "full": supported_choice = true
			if not supported_choice: continue
		elif node_effect(id,0,int(candidate.get("version",CURRENT_SAVE_VERSION))).status != "full": continue
		result.append(id)
	result.sort()
	return result


static func _failure(message: String) -> Dictionary:
	return {"legal":false,"reason":message,"normal_connected":[],"remote_sources":{},"active_sockets":[],"spent":0,"remaining":0}
