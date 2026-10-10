extends SceneTree
## Narrow current-content fragment; no save, battle or full-catalog replay.
const Layout=preload("res://scripts/world/exploration_map_layout.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
static func collect()->Dictionary:
	return {"map_id":"ginkgo_arcade","outpost_id":"camp_west_1","ordinal":3,"tiers":[2,3],
		"from":"skitter","to":"storm_skitter","outpost_roots":4,"ordinary_roots":36,
		"description":Layout.description("ginkgo_arcade"),
		"scope":"仅正式II/III档西叶第一驻点第3名额；最终为普通、无机制掠行体时改为既有雷纹掠行体。固定测试地图与I档不变；裂殖、孵化、魔法/稀有怪及最终巡逻替换均保留，没有候选就不替换。",
		"combat":"追击与锁点雷击配合；雷圈锁定你的起手位置，0.7秒后结算，半径65。命中施加1秒感电，后续命中承伤提高15%；及时走出预警圈即可避开。",
		"budget":"仍为4怪驻点，全图36普通根怪加1首领；不追加抽取或实体，不改变位置、体型、稀有度、机制、死亡后代、掉落规则与schema61。",
		"history":"下方既有编排示例和旧版验收保留为历史资料；当前一处替换的生成、Main战斗和结算证据见本次记录。",
		"attack":Monsters.TelegraphProfiles.ELEMENTAL.storm_skitter.duplicate(true),
		"evidence_path":"docs/qa/ginkgo-west-storm/README.md"}
func _initialize()->void:
	FileAccess.open("res://docs/qa/ginkgo-west-storm/reference-fragment.json",FileAccess.WRITE).store_string(JSON.stringify(collect(),"\t",true,true)+"\n")
	print("GINKGO_WEST_STORM_REFERENCE one existing encounter; no battle replay");quit()
