extends SceneTree
## One current modifier only. No Main, migration, inventory, random rolls or art export.
const Maps=preload("res://scripts/world/map_catalog.gd")
const Compiler=preload("res://scripts/world/map_compiler.gd")
const Rules=preload("res://scripts/world/map_defense_rules.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
const BuildRules=preload("res://scripts/save/canonical_build_rules.gd")
static func collect()->Dictionary:
	var special:Dictionary=Maps.SPECIAL.chaos_aegis.duplicate(true);special.id="chaos_aegis"
	var modes:Dictionary={}
	for test_mode:bool in [true,false]:
		for row:Dictionary in Maps.options(test_mode).special_modifiers:
			if row.id==special.id:modes["test" if test_mode else "normal"]=row
	var profile:Dictionary=Compiler.compile("old_garden",[],[special.id]).profile
	var packet:Dictionary=Damage.packet({"physical":100.0,"fire":100.0,"cold":100.0,"lightning":100.0,"chaos":100.0},["hit"],"reference_chaos_aegis")
	var examples:Dictionary={}
	for template:String in ["crawler","ember_guard","chaos_guard","rift_warden"]:
		var source:Dictionary=Monsters.make_enemy(1,template,4,Vector2.ZERO,"map_boss" if template=="rift_warden" else "ordinary")
		var result:Dictionary=Rules.apply_to_enemy(source,profile);assert(result.ok)
		examples[template]={"source_stats":source.defense_stats,"raw_resistances":result.enemy.map_defense_source.raw_resistances,
			"effective_resistances":result.enemy.resistances,"before_components":Damage.resolve(packet,[],source.resistances).components,
			"after_components":Damage.resolve(packet,[],result.enemy.resistances).components}
	var caps:Array=[]
	for raw:float in [-0.5,0.0,0.25,0.65,0.9]:
		caps.append({"base_raw":raw,"after_raw":raw+float(special.resistance_bonus),"effective":Defense.chaos_resistance_profile({"chaos_resistance":raw+float(special.resistance_bonus)},"monster").effective})
	var inputs:Dictionary={}
	for path:String in ["scripts/world/map_catalog.gd","scripts/world/map_defense_rules.gd","scripts/world/map_admission.gd","scripts/world/map_compiler.gd","scripts/mechanics/defense_rules.gd","scripts/combat/damage_resolver.gd"]:
		inputs[path]=FileAccess.get_sha256("res://"+path)
	var eligible_tiers:Dictionary={}
	for map_id:String in Maps.MAPS:
		eligible_tiers[map_id]=[]
		for tier:int in [1,2,3]:
			if Compiler.compile_normal(map_id,tier,[],[special.id]).ok:eligible_tiers[map_id].append(tier)
	return {"id":special.id,"integration_status":"implemented","definition":special,"options":modes,"examples":examples,"cap_examples":caps,
		"chaos_cap":Defense.CHAOS_RESISTANCE_CAP,"save_version":BuildRules.VERSION,"source_sha256":inputs,"eligible_tiers":eligible_tiers,
		"balance_basis":"原创保守预算：复用元素庇护每类+20个百分点和最低波次4，仅影响混沌一种伤害；不是外部游戏规则或完整平衡证明。",
		"scope":"显式所选地图的根怪、首领及死亡后代；从各自原始防御施加一次，返城/重开不继承旧实例。",
		"preserves":"玩家、未选择词缀的地图、物理与三元素、敌人种类/身份/奖励/RNG和存档schema。混沌仍不绕盾；不新增中毒、持续伤害、穿透或最大混沌抗性。",
		"example_scope":"目录与实际共享规则的100点五类型单次命中，含蚀影守卫标量示例；混沌庇护与蚀影巡逻占同一个特殊槽，不能同时选择。不是实战DPS。"}
func _initialize()->void:
	for stem:String in ["rules-02","main-03"]:
		var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/chaos-aegis/"+stem+".json"))
		assert(report.failures==0 and report.checks>0)
		assert(not FileAccess.get_file_as_string("res://docs/qa/chaos-aegis/"+stem+".log").contains("ERROR:"))
	var output:=FileAccess.open("res://docs/qa/chaos-aegis/reference-fragment.json",FileAccess.WRITE)
	assert(output!=null);output.store_string(JSON.stringify(collect(),"\t",true,true)+"\n");output.close()
	print("Chaos aegis: bounded current catalog and shared defense examples exported");quit()
