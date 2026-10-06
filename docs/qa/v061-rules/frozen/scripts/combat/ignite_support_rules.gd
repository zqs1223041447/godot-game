extends RefCounted
## Original hit-derived burning. The delayed settlement never repeats these factors.
const Program=preload("res://docs/qa/v061-rules/frozen/scripts/combat/support_program.gd")
const Burn=preload("res://docs/qa/v061-rules/frozen/scripts/combat/burn_rules.gd")
const SAVE_VERSION:=28
const SKILLS:Array[String]=["meteor","tornado"]
const SUPPORTS:Dictionary={"ignite":{
	"name":"点燃辅助","description":"主命中伤害 ×0.75，魔力消耗 ×1.20。火焰命中附燃3秒，每秒按该次防御前火焰伤害的30%；更强覆盖、同强刷新，不叠加。仅适配陨星与龙卷。",
	"skills":SKILLS,"requires":[],"family":"burning",
	"operations":[{"op":"primary_hit_more","value":-0.25},{"op":"mana_multiplier","value":1.20}]}}

static func get_definition(id:Variant)->Dictionary:
	return SUPPORTS[id].duplicate(true) if typeof(id)==TYPE_STRING and SUPPORTS.has(id) else {}

static func definition_error(value:Variant)->String:
	return "" if value is Dictionary and value==SUPPORTS.ignite else "点燃辅助定义无效"

static func compile_program(skill_id:Variant,support_ids:Variant,slot_limit:int=2)->Dictionary:
	var reason:String=Program.selection_error(skill_id,support_ids,SUPPORTS,slot_limit)
	if not reason.is_empty():return Program.failure(reason)
	var result:Dictionary=Program.empty()
	if support_ids.is_empty():return result
	result.modifiers.append(Program.primary_modifier("ignite",skill_id,float(Burn.PLAYER_POLICY.hit_multiplier)-1.0))
	result.mana_multiplier=float(Burn.PLAYER_POLICY.mana_multiplier)
	return result
