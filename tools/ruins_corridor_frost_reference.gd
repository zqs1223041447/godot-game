extends SceneTree
## One bounded existing-outpost rule; no live profile or battle replay.
const Layout=preload("res://scripts/world/exploration_map_layout.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
static func collect()->Dictionary:
	return {"map_id":"broken_ruins","outpost_id":"camp_north_2","ordinals":[5,6,7,8,9,10,11,12],"tiers":[2,3],
		"from":"brute","to":"frost_guard","outpost_roots":8,"ordinary_roots":36,
		"description":Layout.description("broken_ruins"),
		"scope":"仅正式II/III档两道残墙之间的北侧第二驻点。若八怪驻点已有霜纹守卫，整组不追加替换；否则依原名额顺序，将首个普通、无机制重壳体换为已有霜纹守卫。无合格候选则不变；特殊怪、魔法/稀有怪与最终巡逻替换优先保留。I档和固定测试地图不变。",
		"combat":"内廊寒击与原灰烬守卫配合：寒圈锁定起手位置，预警0.9秒、半径90；造成实际冰霜损失后减速25%，持续1.2秒，不冻结。提前离圈，避免受减速后滞留火圈；残墙可阻断起手视线，沿墙端绕行。",
		"budget":"保持8怪驻点和全图36普通根怪加1首领；只替换一个同体型模板，位置、稀有度、原后代与奖励规则不变，不追加随机抽取。",
		"history":"下方原有示例及历史地图验收不重新生成；本次新增编排的证据见独立记录。",
		"attack":Monsters.TelegraphProfiles.ELEMENTAL.frost_guard.duplicate(true),
		"evidence_path":"docs/qa/ruins-corridor-frost/README.md"}
func _initialize()->void:
	FileAccess.open("res://docs/qa/ruins-corridor-frost/reference-fragment.json",FileAccess.WRITE).store_string(JSON.stringify(collect(),"\t",true,true)+"\n")
	print("RUINS_CORRIDOR_FROST_REFERENCE one existing encounter; no battle replay");quit()
