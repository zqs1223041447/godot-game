class_name MapCatalog
extends RefCounted
const Encounters=preload("res://scripts/encounters/encounter_catalog.gd")
const MAPS={
	"ruins_garden":{"name":"遗迹庭园","description":"沿古典断墙、拱门与岩石之间探索六处驻点。24个普通根怪与首领入场时全部在场；清理全部怪物和后代完成挑战。模块轮廓同时阻挡移动、弹体和视线。","wave":4,"ordinary_target":24,"boss_id":"rift_warden","boss_attack_id":"ruins_garden_slam","native_entry":true},
	"old_garden":{"name":"旧庭试炼","description":"开阔庭院，无实体残墙。靠近任意据点木牌激活整组8个根怪，可同时挑战多组。三个据点共24根怪，全部击败后前往首领入口，再清理首领和后代。首领近身震地锁定起手位置，看到预警走出圆圈。","wave":4,"ordinary_target":24,"boss_id":"rift_warden","boss_attack_id":"garden_slam"},
	"broken_ruins":{"name":"断垣试炼","description":"两道错位残墙需绕行；贯穿不穿墙，撞墙不触发到期效果。三个据点可自由选择推进顺序，每组12根怪可同时出场。全部36根怪击败后前往首领入口，再清理首领和后代。首领落印锁定你的起手位置，及时走开；墙体阻挡视线。","wave":5,"ordinary_target":36,"boss_id":"rift_warden","boss_attack_id":"ruins_mark"},
	"sunwell_terrace":{"name":"晴泉台地","description":"四座实体泉池阻挡移动、弹体和视线，沿池间通道绕行。西泉据点偏重壳与霜纹，北门据点混合编排，东阶据点偏掠行与雷纹；霜纹、雷纹分别从第4、5波出现。三个据点自由顺序，每组12根怪可同场挑战，共36根怪。清理后在南侧入口激活首领；两次回响均锁定起手位置，持续离开预警范围。","wave":6,"ordinary_target":36,"boss_id":"rift_warden","boss_attack_id":"sunwell_echo"},
	"ginkgo_arcade":{"name":"银杏回廊","description":"中央花圃与两座基台阻挡移动、弹体和视线，沿内外通路绕行。三个据点各12根怪，可自由选择顺序；清理36根怪后激活首领。回廊震击锁定首领起手位置：离开圆圈，或利用实体障碍阻断视线。","wave":6,"ordinary_target":36,"boss_id":"rift_warden","boss_attack_id":"ginkgo_shelter_slam"}}
const SPECIAL={
	"elemental_aegis":{"name":"元素庇护","description":"地图怪物三元素原始抗性各加20个百分点，有效上限75%；物理和混沌不变。","kind":"defense","minimum_wave":4,"resistance_bonus":0.20,"damage_types":["fire","cold","lightning"]},
	"frost_patrol":{"name":"霜纹巡逻","description":"原本生成重甲体的普通名额改为霜纹守卫，保留原稀有度与机制；灰烬名额不变。冰霜圆形预警可走开；受到实际冰霜伤害后，移动速度降低25%，持续1.2秒，不产生冻结。","minimum_wave":4,"species":"brute","template":"frost_guard"},
	"storm_patrol":{"name":"雷纹巡逻","description":"原本生成掠行体的普通名额改为雷纹掠行体，保留原稀有度与机制；灰烬名额不变。雷电圆形预警可走开；命中会施加1秒感电，使后续命中承受伤害提高15%。","minimum_wave":5,"species":"skitter","template":"storm_skitter"},
	"chaos_patrol":{"name":"蚀影巡逻","description":"原本生成重壳体的普通名额改为蚀影守卫，保留原稀有度与机制；灰烬、分裂、孵化和首领不变。纯混沌攻击蓄力1秒，锁定你的起手位置，走出圆圈即可避开；守卫有25%混沌抗性。","minimum_wave":5,"species":"brute","template":"chaos_guard"},
	"chaos_aegis":{"name":"混沌庇护","description":"地图根怪、首领与死亡后代的原始混沌抗性各加20个百分点，有效上限75%；物理与三元素不变。每个敌人从自身原始值施加一次，混沌命中仍先消耗护盾。","kind":"defense","minimum_wave":4,"resistance_bonus":0.20,"damage_types":["chaos"]}}
static func options(test_mode:bool=true)->Dictionary:
	var maps:Array[Dictionary]=[];var special:Array[Dictionary]=[];var normal:Array[Dictionary]=[]
	for id:String in MAPS:
		if test_mode and id == "ruins_garden": continue
		var row:Dictionary=MAPS[id].duplicate(true);row.id=id;maps.append(row)
	for id:String in SPECIAL:
		var row:Dictionary=SPECIAL[id].duplicate(true);row.id=id
		row["completion_reward_bonus"]=0 if test_mode else 2
		row["reward_description"]="测试模式不增加完成奖励" if test_mode else "正式地图完成奖励 +2 碎片"
		row.description+=" "+str(row.reward_description)+"。"
		special.append(row)
	for id:String in Encounters.get_ids():normal.append(Encounters.get_definition(id))
	return {"reward_mode":"test" if test_mode else "normal","maps":maps,"normal_modifiers":normal,"special_modifiers":special,"max_normal":2,"max_special":1,
		"cost_policy":{"id":"test_free","enabled":true,"label":"测试模式免费制作地图","cost":{},"affects_legacy_currency":false}}
