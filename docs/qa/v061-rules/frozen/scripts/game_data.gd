extends RefCounted
## Read-only catalogs shared by combat, menus, and build validation.

## Capabilities gate support eligibility; they are never copied into damage-event tags.
## Bolt/frost launch parameters live here; tornado keeps CombatData.TORNADO as authority.
## The obsolete per-skill damage field was never a cast input and is intentionally absent.
const LEGACY_SKILL_IDS: Array[String] = ["tornado", "bolt", "frost", "nova", "dash", "ward", "meteor", "chain"]
const NEW_SKILL_SAVE_VERSION: int = 17
const NEW_SKILL_IDS: Array[String] = ["cleave", "shade_bolt"]
const SKILLS: Dictionary = {
	"cleave": {
		"name": "裂刃斩", "short_name": "裂刃", "icon": "IX",
		"description": "向面前半圆横扫，半径 95，造成 280% 物理攻击命中。近战与范围加成生效；不借用长弓本地伤害。",
		"mana": 12.0, "cooldown": 1.4, "color": Color("d3c3a2"),
		"capabilities": ["area_hit", "melee_hit"],
		"area_recipe": {"radius": 95.0}, "half_angle": PI / 2.0,
		"hit_recipe": {"base_coefficient": 2.8, "added_effectiveness": 2.8, "damage_type": "physical"},
	},
	"shade_bolt": {
		"name": "蚀影飞弹", "short_name": "蚀影", "icon": "X",
		"description": "发射一枚 240% 基础混沌伤害的法术飞弹，首次碰撞后结束。可由装备附加其他类型伤害；不造成毒或持续伤害。",
		"mana": 8.0, "cooldown": 1.2, "color": Color("9c87b1"),
		"capabilities": ["initial_projectiles", "projectile_hit"],
		"projectile_recipe": {"initial_count": 1, "spread": 0.14, "coefficient": 2.4, "added_effectiveness": 2.4,
			"pierce": 0, "slow": 0.0, "speed": 620.0, "damage_type": "chaos"},
	},
	"tornado": {
		"name": "龙卷射击", "short_name": "龙卷", "icon": "VIII",
		"description": "发射 3 枚母箭，每枚在射程终点分裂为 3 枚环形子箭。箭伤为物理 60% 与火焰 40%；子箭造成 70% 基础伤害。返回与爆炸由装备分别赋予。",
		"mana": 18.0, "cooldown": 2.5, "color": Color("a6e8aa"),
		"capabilities": ["initial_projectiles", "projectile_hit", "split_projectiles"],
	},
	"bolt": {
		"name": "奥术飞弹", "short_name": "飞弹", "icon": "I",
		"description": "发射三枚穿透飞弹，每枚造成 160% 伤害。", "mana": 7.0,
		"cooldown": 0.8, "color": Color("76c9ff"),
		"capabilities": ["initial_projectiles", "projectile_hit"],
		"projectile_recipe": {"initial_count": 3, "spread": 0.16, "coefficient": 1.6, "added_effectiveness": 1.6,
			"pierce": 1, "slow": 0.0, "speed": 780.0, "damage_type": "lightning"},
	},
	"frost": {
		"name": "冰霜脉冲", "short_name": "冰霜", "icon": "II",
		"description": "扇形发射五枚冰弹，造成 85% 伤害并减速 3 秒。", "mana": 16.0,
		"cooldown": 4.0, "color": Color("86edff"),
		"capabilities": ["initial_projectiles", "projectile_hit"],
		"projectile_recipe": {"initial_count": 5, "spread": 0.14, "coefficient": 0.85, "added_effectiveness": 0.85,
			"pierce": 2, "slow": 3.0, "speed": 520.0, "damage_type": "cold"},
	},
	"nova": {
		"name": "奥能新星", "short_name": "新星", "icon": "III",
		"description": "引爆周围 155 范围的奥能，造成 270% 伤害并击退。", "mana": 24.0,
		"cooldown": 6.0, "color": Color("c89bff"),
		"capabilities": ["area_hit"],
		"area_recipe": {"radius": 155.0},
		"hit_recipe": {"base_coefficient": 2.7, "added_effectiveness": 2.7, "damage_type": "lightning"},
	},
	"dash": {
		"name": "闪光冲刺", "short_name": "冲刺", "icon": "IV",
		"description": "沿移动方向冲刺 175 距离，免疫伤害 0.6 秒。", "mana": 12.0,
		"cooldown": 3.0, "color": Color("ffd27d"),
		"capabilities": ["movement"],
	},
	"ward": {
		"name": "守护结界", "short_name": "结界", "icon": "V",
		"description": "回复 75% 最大护盾，免疫伤害 0.8 秒。", "mana": 20.0,
		"cooldown": 7.0, "color": Color("77ecc5"),
		"capabilities": ["shield_recovery"],
	},
	"meteor": {
		"name": "陨星坠落", "short_name": "陨星", "icon": "VI",
		"description": "在最近敌人处引爆陨星，造成 430% 范围伤害。", "mana": 32.0,
		"cooldown": 8.0, "color": Color("ff9778"),
		"capabilities": ["area_hit"],
		"area_recipe": {"radius": 110.0},
		"hit_recipe": {"base_coefficient": 4.3, "added_effectiveness": 4.3, "damage_type": "fire"},
	},
	"chain": {
		"name": "连锁闪电", "short_name": "闪电", "icon": "VII",
		"description": "闪电弹跳最多五个敌人，伤害从 220% 逐次递减。", "mana": 22.0,
		"cooldown": 4.5, "color": Color("ffeb88"),
		"capabilities": ["chain_hit"],
		"targeting_recipe": {"first_range": 600.0, "followup_range": 220.0},
		"hit_recipe": {"base_coefficient": 2.2, "base_coefficient_loss_per_bounce": 0.2,
			"added_effectiveness": 2.2, "added_effectiveness_loss_per_bounce": 0.2,
			"bounce_count": 5, "damage_type": "lightning"},
	},
}

const COMBAT_STARTER_ITEMS: Array[String] = ["prism_bow", "return_mantle", "detonation_charm"]

const ITEMS: Dictionary = {
	"prism_bow": {
		"size": Vector2i(1, 3), "name": "棱光长弓", "slot": "weapon",
		"description": "基础伤害 +4，投射物伤害提高 40%，龙卷额外母箭 +2；其中投射物增伤不作用于爆炸。",
		"stats": {"damage": 4.0, "projectile_increased": 0.4, "projectile_count": 2.0},
	},
	"return_mantle": {
		"size": Vector2i(2, 3), "name": "归航披风", "slot": "armor",
		"description": "最大护盾 +15。投射物抵达射程后，朝此刻角色中心方向返回一次；穿过中心继续飞行，不刷新寿命。母箭优先分裂。",
		"stats": {"max_shield": 15.0}, "effects": ["return_on_range"],
	},
	"detonation_charm": {
		"size": Vector2i(1, 1), "name": "终焰护符", "slot": "charm",
		"description": "全局伤害提高 20%，元素伤害提高 30%。自然飞行结束爆炸：造成 90% 基础火焰范围伤害。返回可延后爆炸；分裂、碰撞消耗和取消不爆炸。",
		"stats": {"global_increased": 0.2, "elemental_increased": 0.3}, "effects": ["explode_on_flight_end"],
	},
	"ember_wand": {
		"size": Vector2i(1, 3),
		"name": "余烬法杖", "slot": "weapon", "description": "伤害 +8，魔力恢复 +1 / 秒",
		"stats": {"damage": 8.0, "mana_regen": 1.0},
	},
	"swift_blade": {
		"size": Vector2i(1, 3),
		"name": "疾风短刃", "slot": "weapon", "description": "攻击速度 +0.5 / 秒，移动速度 +20",
		"stats": {"attack_speed": 0.5, "move_speed": 20.0},
	},
	"guardian_robe": {
		"size": Vector2i(2, 3),
		"name": "守护长袍", "slot": "armor", "description": "最大护盾 +30，护盾恢复 +3 / 秒",
		"stats": {"max_shield": 30.0, "shield_regen": 3.0},
	},
	"vitality_armor": {
		"size": Vector2i(2, 3),
		"name": "生机轻甲", "slot": "armor", "description": "最大生命 +50，移动速度 +10",
		"stats": {"max_health": 50.0, "move_speed": 10.0},
	},
	"azure_charm": {
		"size": Vector2i(1, 1),
		"name": "湛蓝护符", "slot": "charm", "description": "最大魔力 +30，魔力恢复 +2 / 秒",
		"stats": {"max_mana": 30.0, "mana_regen": 2.0},
	},
	"storm_charm": {
		"size": Vector2i(1, 1),
		"name": "风暴护符", "slot": "charm", "description": "伤害 +6，攻击速度 +0.2 / 秒",
		"stats": {"damage": 6.0, "attack_speed": 0.2},
	},
}

## Version-1 migration catalog only. New builds use PassiveData and JewelData.
const TALENTS: Dictionary = {
	"power": {
		"name": "奥术精研", "description": "每级：伤害 +4", "max_rank": 5,
		"stats": {"damage": 4.0},
	},
	"vitality": {
		"name": "坚韧体魄", "description": "每级：最大生命 +20", "max_rank": 5,
		"stats": {"max_health": 20.0},
	},
	"focus": {
		"name": "魔力专注", "description": "每级：最大魔力 +12，魔力恢复 +1 / 秒", "max_rank": 5,
		"stats": {"max_mana": 12.0, "mana_regen": 1.0},
	},
	"haste": {
		"name": "迅捷律动", "description": "每级：攻击速度 +0.12 / 秒，移动速度 +8", "max_rank": 5,
		"stats": {"attack_speed": 0.12, "move_speed": 8.0},
	},
	"aegis": {
		"name": "能量屏障", "description": "每级：最大护盾 +12，护盾恢复 +1.5 / 秒", "max_rank": 5,
		"stats": {"max_shield": 12.0, "shield_regen": 1.5},
	},
}
