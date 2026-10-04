class_name MapCatalog
extends RefCounted
const Encounters=preload("res://scripts/encounters/encounter_catalog.gd")
const MAPS={
	"old_garden":{"name":"旧庭试炼","description":"开阔庭院，无实体残墙。靠近任意据点木牌激活整组8个根怪，可同时挑战多组。三个据点共24根怪，全部击败后前往首领入口，再清理首领和后代。首领近身震地锁定起手位置，看到预警走出圆圈。","wave":4,"ordinary_target":24,"boss_id":"rift_warden","boss_attack_id":"garden_slam"},
	"broken_ruins":{"name":"断垣试炼","description":"两道错位残墙需绕行；贯穿不穿墙，撞墙不触发到期效果。三个据点可自由选择推进顺序，每组12根怪可同时出场。全部36根怪击败后前往首领入口，再清理首领和后代。首领落印锁定你的起手位置，及时走开；墙体阻挡视线。","wave":5,"ordinary_target":36,"boss_id":"rift_warden","boss_attack_id":"ruins_mark"}}
const SPECIAL={
	"elemental_aegis":{"name":"元素庇护","description":"地图怪物三元素原始抗性各加20个百分点，有效上限75%；物理和混沌不变。","kind":"defense","minimum_wave":4,"resistance_bonus":0.20,"damage_types":["fire","cold","lightning"]},
	"frost_patrol":{"name":"霜纹巡逻","description":"原本生成重甲体的普通名额改为霜纹守卫，保留原稀有度与机制；灰烬名额不变。冰霜圆形预警可走开，不产生冻结。","minimum_wave":4,"species":"brute","template":"frost_guard"},
	"storm_patrol":{"name":"雷纹巡逻","description":"原本生成掠行体的普通名额改为雷纹掠行体，保留原稀有度与机制；灰烬名额不变。雷电圆形预警可走开，不产生感电。","minimum_wave":5,"species":"skitter","template":"storm_skitter"}}
static func options(test_mode:bool=true)->Dictionary:
	var maps:Array[Dictionary]=[];var special:Array[Dictionary]=[];var normal:Array[Dictionary]=[]
	for id:String in MAPS:var row:Dictionary=MAPS[id].duplicate(true);row.id=id;maps.append(row)
	for id:String in SPECIAL:
		var row:Dictionary=SPECIAL[id].duplicate(true);row.id=id
		row["completion_reward_bonus"]=0 if test_mode else 2
		row["reward_description"]="测试模式不增加完成奖励" if test_mode else "正式地图完成奖励 +2 碎片"
		row.description+=" "+str(row.reward_description)+"。"
		special.append(row)
	for id:String in Encounters.get_ids():normal.append(Encounters.get_definition(id))
	return {"reward_mode":"test" if test_mode else "normal","maps":maps,"normal_modifiers":normal,"special_modifiers":special,"max_normal":2,"max_special":1,
		"cost_policy":{"id":"test_free","enabled":true,"label":"测试模式免费制作地图","cost":{},"affects_legacy_currency":false}}
