class_name MapCatalog
extends RefCounted
const Encounters=preload("res://scripts/encounters/encounter_catalog.gd")
const MAPS={
	"old_garden":{"name":"旧庭试炼","description":"开阔庭院，无实体残墙。击败24个普通根怪，再击败裂隙守卫并清理其后代。","wave":4,"ordinary_target":24,"boss_id":"rift_warden"},
	"broken_ruins":{"name":"断垣试炼","description":"两道错位残墙需绕行，攻击受墙体遮挡；贯穿不穿墙，碰墙不触发到期效果。击败36个普通根怪，再击败裂隙守卫并清理其后代。","wave":5,"ordinary_target":36,"boss_id":"rift_warden"}}
const SPECIAL={
	"elemental_aegis":{"name":"元素庇护","description":"地图怪物三元素原始抗性各加20个百分点，有效上限75%；物理和混沌不变，无额外奖励。","kind":"defense","minimum_wave":4,"resistance_bonus":0.20,"damage_types":["fire","cold","lightning"]},
	"frost_patrol":{"name":"霜纹巡逻","description":"原本生成重甲体的普通名额改为霜纹守卫，保留原稀有度与机制；灰烬名额不变。冰霜圆形预警可走开，不产生冻结。","minimum_wave":4,"species":"brute","template":"frost_guard"},
	"storm_patrol":{"name":"雷纹巡逻","description":"原本生成掠行体的普通名额改为雷纹掠行体，保留原稀有度与机制；灰烬名额不变。雷电圆形预警可走开，不产生感电。","minimum_wave":5,"species":"skitter","template":"storm_skitter"}}
static func options()->Dictionary:
	var maps:Array[Dictionary]=[];var special:Array[Dictionary]=[];var normal:Array[Dictionary]=[]
	for id:String in MAPS:var row:Dictionary=MAPS[id].duplicate(true);row.id=id;maps.append(row)
	for id:String in SPECIAL:var row:Dictionary=SPECIAL[id].duplicate(true);row.id=id;special.append(row)
	for id:String in Encounters.get_ids():normal.append(Encounters.get_definition(id))
	return {"maps":maps,"normal_modifiers":normal,"special_modifiers":special,"max_normal":2,"max_special":1,
		"cost_policy":{"id":"test_free","enabled":true,"label":"测试模式免费制作地图","cost":{},"affects_legacy_currency":false}}
