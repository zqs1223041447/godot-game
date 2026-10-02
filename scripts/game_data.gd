class_name GameData
extends RefCounted
## Read-only catalogs shared by combat, menus, and build validation.

const SKILLS: Dictionary = {
	"bolt": {
		"name": "奥术飞弹", "short_name": "飞弹", "icon": "I",
		"description": "发射三枚穿透飞弹，每枚造成 160% 伤害。", "mana": 7.0,
		"cooldown": 0.8, "damage": 28.0, "color": Color("76c9ff"),
	},
	"frost": {
		"name": "冰霜脉冲", "short_name": "冰霜", "icon": "II",
		"description": "扇形发射五枚冰弹，造成 85% 伤害并减速 3 秒。", "mana": 16.0,
		"cooldown": 4.0, "damage": 24.0, "color": Color("86edff"),
	},
	"nova": {
		"name": "奥能新星", "short_name": "新星", "icon": "III",
		"description": "引爆周围 155 范围的奥能，造成 270% 伤害并击退。", "mana": 24.0,
		"cooldown": 6.0, "damage": 60.0, "color": Color("c89bff"),
	},
	"dash": {
		"name": "闪光冲刺", "short_name": "冲刺", "icon": "IV",
		"description": "沿移动方向冲刺 175 距离，免疫伤害 0.6 秒。", "mana": 12.0,
		"cooldown": 3.0, "damage": 0.0, "color": Color("ffd27d"),
	},
	"ward": {
		"name": "守护结界", "short_name": "结界", "icon": "V",
		"description": "回复 75% 最大护盾，免疫伤害 0.8 秒。", "mana": 20.0,
		"cooldown": 7.0, "damage": 0.0, "color": Color("77ecc5"),
	},
	"meteor": {
		"name": "陨星坠落", "short_name": "陨星", "icon": "VI",
		"description": "在最近敌人处引爆陨星，造成 430% 范围伤害。", "mana": 32.0,
		"cooldown": 8.0, "damage": 100.0, "color": Color("ff9778"),
	},
	"chain": {
		"name": "连锁闪电", "short_name": "闪电", "icon": "VII",
		"description": "闪电弹跳最多五个敌人，伤害从 220% 逐次递减。", "mana": 22.0,
		"cooldown": 4.5, "damage": 42.0, "color": Color("ffeb88"),
	},
}

const ITEMS: Dictionary = {
	"ember_wand": {
		"name": "余烬法杖", "slot": "weapon", "description": "伤害 +8，魔力恢复 +1 / 秒",
		"stats": {"damage": 8.0, "mana_regen": 1.0},
	},
	"swift_blade": {
		"name": "疾风短刃", "slot": "weapon", "description": "攻击速度 +0.5 / 秒，移动速度 +20",
		"stats": {"attack_speed": 0.5, "move_speed": 20.0},
	},
	"guardian_robe": {
		"name": "守护长袍", "slot": "armor", "description": "最大护盾 +30，护盾恢复 +3 / 秒",
		"stats": {"max_shield": 30.0, "shield_regen": 3.0},
	},
	"vitality_armor": {
		"name": "生机轻甲", "slot": "armor", "description": "最大生命 +50，移动速度 +10",
		"stats": {"max_health": 50.0, "move_speed": 10.0},
	},
	"azure_charm": {
		"name": "湛蓝护符", "slot": "charm", "description": "最大魔力 +30，魔力恢复 +2 / 秒",
		"stats": {"max_mana": 30.0, "mana_regen": 2.0},
	},
	"storm_charm": {
		"name": "风暴护符", "slot": "charm", "description": "伤害 +6，攻击速度 +0.2 / 秒",
		"stats": {"damage": 6.0, "attack_speed": 0.2},
	},
}

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
