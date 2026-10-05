#!/usr/bin/env python3
"""Build a separate, source-hash-pinned Simplified Chinese passive-tree map.

The English tree/source data is deliberately never edited.  This build step
emits an ID-keyed name map and an exact-raw-line-keyed display map.  It fails
closed when any source word has no reviewed Chinese vocabulary entry.
"""
from __future__ import annotations

import collections
import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "data/passives/official_tree_runtime.json"
RAW_SOURCE = ROOT / "data/passive_source/data.json"
OUT = ROOT / "data/passive_source/localization_zh_CN.json"
EXPECTED_SHA256 = "7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122"

# Long phrases precede individual terms.  These are presentation-only forms;
# no localized text is ever passed to SourceStatPatterns.
PHRASES = {
    "Fire Damage over Time": "火焰持续伤害",
    "Cold Damage over Time": "冰霜持续伤害",
    "Lightning Damage over Time": "闪电持续伤害",
    "Chaos Damage over Time": "混沌持续伤害",
    "Physical Damage over Time": "物理持续伤害",
    "Damage over Time": "持续伤害",
    "Energy Shield Recharge Rate": "能量护盾充能速度",
    "Energy Shield Recharge": "能量护盾充能",
    "Energy Shield": "能量护盾",
    "Maximum Life": "最大生命",
    "maximum Life": "最大生命",
    "Maximum Mana": "最大魔力",
    "maximum Mana": "最大魔力",
    "Maximum Energy Shield": "最大能量护盾",
    "maximum Energy Shield": "最大能量护盾",
    "Life Recovery": "生命回复",
    "Mana Recovery": "魔力回复",
    "Energy Shield Recovery": "能量护盾回复",
    "Life Regeneration": "生命回复",
    "Mana Regeneration": "魔力回复",
    "Life Regeneration Rate": "生命回复速度",
    "Mana Regeneration Rate": "魔力回复速度",
    "Critical Strike Multiplier": "暴击伤害倍率",
    "Critical Strike Chance": "暴击几率",
    "Spell Critical Strike Chance": "法术暴击几率",
    "Melee Critical Strike Chance": "近战暴击几率",
    "Critical Strike": "暴击",
    "Elemental Resistances": "元素抗性",
    "Elemental Resistance": "元素抗性",
    "Fire Resistance": "火焰抗性",
    "Cold Resistance": "冰霜抗性",
    "Lightning Resistance": "闪电抗性",
    "Chaos Resistance": "混沌抗性",
    "Physical Damage": "物理伤害",
    "Fire Damage": "火焰伤害",
    "Cold Damage": "冰霜伤害",
    "Lightning Damage": "闪电伤害",
    "Chaos Damage": "混沌伤害",
    "Elemental Damage": "元素伤害",
    "Attack Damage": "攻击伤害",
    "Spell Damage": "法术伤害",
    "Projectile Damage": "投射物伤害",
    "Melee Damage": "近战伤害",
    "Damage Taken": "所受伤害",
    "Damage with Hits": "击中伤害",
    "Damage with Ailments": "异常状态伤害",
    "Damage over Time Taken": "所受持续伤害",
    "Damage with Hits and Ailments": "击中与异常状态伤害",
    "Attack and Cast Speed": "攻击与施法速度",
    "Cast Speed": "施法速度",
    "Attack Speed": "攻击速度",
    "Movement Speed": "移动速度",
    "Action Speed": "行动速度",
    "Cooldown Recovery Rate": "冷却回复速度",
    "Mana Reservation Efficiency": "魔力保留效能",
    "Life Reservation Efficiency": "生命保留效能",
    "Area of Effect": "效果范围",
    "Area Damage": "范围伤害",
    "Spell Suppression": "法术压制",
    "Suppressed Spell Damage": "被压制的法术伤害",
    "Physical Damage Reduction": "物理伤害减免",
    "Elemental Damage Reduction": "元素伤害减免",
    "Damage over Time Multiplier": "持续伤害倍率",
    "Fire Damage over Time Multiplier": "火焰持续伤害倍率",
    "Cold Damage over Time Multiplier": "冰霜持续伤害倍率",
    "Critical Strike Multiplier": "暴击伤害倍率",
    "Passive Skill Point": "被动天赋点",
    "Passive Skill Points": "被动天赋点",
    "Jewel Socket": "珠宝插槽",
    "Skill Gems": "技能宝石",
    "Skill Gem": "技能宝石",
    "Skill Effect Duration": "技能效果持续时间",
    "Effect of": "效果",
    "Area of Effect per": "每",
    "Low Life": "低血状态",
    "Full Life": "满血状态",
    "Low Energy Shield": "低能量护盾状态",
    "Full Energy Shield": "满能量护盾状态",
    "Dual Wielding": "双持",
    "Two Handed": "双手",
    "Damage over Time": "持续伤害",
    "Non-Damaging Ailments": "非伤害性异常状态",
    "Damaging Ailments": "伤害性异常状态",
    "Ailments": "异常状态",
    "Endurance Charge": "耐力球",
    "Endurance Charges": "耐力球",
    "Frenzy Charge": "狂怒球",
    "Frenzy Charges": "狂怒球",
    "Power Charge": "暴击球",
    "Power Charges": "暴击球",
    "Energy Shield Leech": "能量护盾偷取",
    "Life Leech": "生命偷取",
    "Mana Leech": "魔力偷取",
    "Attack Damage Leeched": "攻击伤害偷取",
    "Damage Leeched": "伤害偷取",
    "Chance to Block Attack Damage": "攻击伤害格挡几率",
    "Chance to Block Spell Damage": "法术伤害格挡几率",
    "Block Attack Damage": "格挡攻击伤害",
    "Block Spell Damage": "格挡法术伤害",
    "Maximum total": "每秒最大总",
    "total Recovery per second": "每秒总回复",
    "Recovery per second": "每秒回复",
    "maximum total": "每秒最大总",
    "Life per second": "每秒生命",
    "Mana per second": "每秒魔力",
    "Energy Shield per second": "每秒能量护盾",
    "per second": "每秒",
    "per Level": "每级",
    "for each": "每个",
    "for every": "每",
    "no more than": "不超过",
    "more than": "超过",
    "less than": "少于",
    "instead of": "而非",
    "as though": "视为",
    "as Extra": "作为额外",
    "on Kill": "击杀时",
    "on Hit": "击中时",
    "while Leeching": "偷取期间",
    "while Channelling": "引导期间",
    "while Dual Wielding": "双持时",
    "while holding a Shield": "持盾时",
    "while holding a Staff": "持长杖时",
    "while at maximum": "达到最大值时",
    "while on Full Life": "满血时",
    "while on Low Life": "低血时",
    "when you use": "使用时",
    "when you have": "拥有时",
    "for the past": "在过去",
    "in the past": "在过去",
    "at least": "至少",
    "up to a maximum of": "最多达到",
    "up to": "至多",
    "a maximum of": "最多",
    "chance to": "几率",
    "chance of": "几率",
    "Damage taken": "所受伤害",
    "Life gained": "获得生命",
    "Mana gained": "获得魔力",
    "Damage Converted to": "伤害转化为",
    "Converted to": "转化为",
}

# Shared PoE/game vocabulary.  The four damage modifiers are deliberately
# separate: increased/reduced are additive; more/less are independent multipliers.
WORDS = {
    "a": "一", "an": "一", "the": "", "and": "与", "or": "或", "of": "的",
    "to": "至", "from": "来自", "by": "由", "for": "对", "with": "与", "without": "没有",
    "if": "若", "when": "当", "while": "当", "after": "后", "before": "前", "during": "期间",
    "per": "每", "each": "每个", "every": "每", "you": "你", "your": "你的", "you've": "你已",
    "you're": "你正", "they": "它们", "their": "它们的", "it": "它", "is": "是", "are": "是",
    "have": "拥有", "has": "拥有", "been": "已", "be": "成为", "being": "处于", "can": "可以",
    "cannot": "无法", "can't": "无法", "does": "会", "do": "会", "not": "不", "no": "没有",
    "all": "所有", "any": "任意", "other": "其他", "another": "另一个", "additional": "额外",
    "extra": "额外", "more": "额外提高", "less": "额外降低", "increased": "提高", "increases": "提高",
    "increase": "提高", "reduced": "降低", "reductions": "降低", "reduction": "降低",
    "faster": "更快", "slower": "更慢", "inherently": "固有地", "bonus": "加成", "bonuses": "加成",
    "effect": "效果", "effects": "效果", "magnitude": "幅度", "chance": "几率", "rate": "速度",
    "speed": "速度", "duration": "持续时间", "cooldown": "冷却", "recovery": "回复", "recover": "回复",
    "recovers": "回复", "regenerate": "回复", "regenerates": "回复", "regeneration": "回复",
    "regenerate": "回复", "gain": "获得", "gains": "获得", "gained": "获得", "grants": "获得",
    "grant": "授予", "deal": "造成", "deals": "造成", "dealt": "造成", "take": "承受",
    "taken": "所受", "cause": "造成", "causes": "造成", "inflict": "施加", "inflicts": "施加",
    "applies": "施加", "apply": "施加", "remove": "移除", "removes": "移除", "removed": "移除",
    "avoid": "避免", "avoids": "避免", "avoidance": "避免", "prevent": "防止", "prevents": "防止",
    "ignore": "无视", "penetrate": "穿透", "penetrates": "穿透", "pierce": "穿透", "pierces": "穿透",
    "convert": "转化", "converts": "转化", "converted": "转化", "create": "创造", "creates": "创造",
    "trigger": "触发", "triggered": "触发", "triggers": "触发", "summon": "召唤", "summoned": "召唤",
    "kill": "击杀", "killed": "击杀", "when": "当", "use": "使用", "used": "使用",
    "attack": "攻击", "attacks": "攻击", "attacker": "攻击者", "spell": "法术", "spells": "法术",
    "skill": "技能", "skills": "技能", "melee": "近战", "projectile": "投射物", "projectiles": "投射物",
    "physical": "物理", "fire": "火焰", "cold": "冰霜", "lightning": "闪电", "chaos": "混沌",
    "elemental": "元素", "damage": "伤害", "damaging": "伤害性", "hit": "击中", "hits": "击中",
    "life": "生命", "mana": "魔力", "maximum": "最大", "maximum": "最大", "energy": "能量",
    "shield": "护盾", "armour": "护甲", "armor": "护甲", "evasion": "闪避", "accuracy": "命中",
    "rating": "值", "resistance": "抗性", "resistances": "抗性", "multiplier": "倍率",
    "over": "超过", "time": "时间", "second": "秒", "seconds": "秒", "minute": "分钟",
    "metres": "米", "metre": "米", "range": "距离", "radius": "半径", "area": "范围",
    "nearby": "附近", "close": "近距离", "enemy": "敌人", "enemies": "敌人", "target": "目标",
    "targets": "目标", "monster": "怪物", "monsters": "怪物", "minion": "召唤物", "minions": "召唤物",
    "allies": "友军", "ally": "友军", "party": "队伍", "member": "成员", "members": "成员",
    "life": "生命", "flask": "药剂", "flasks": "药剂", "tincture": "灵药", "tinctures": "灵药",
    "charge": "球", "charges": "球", "endurance": "耐力", "frenzy": "狂怒", "power": "暴击",
    "critical": "暴击", "strike": "攻击", "mastery": "专精", "passive": "被动", "point": "点",
    "points": "点", "jewel": "珠宝", "socket": "插槽", "skill": "技能", "gem": "宝石", "gems": "宝石",
    "ailment": "异常状态", "ailments": "异常状态", "bleed": "流血", "bleeding": "流血",
    "ignite": "点燃", "ignites": "点燃", "ignited": "被点燃", "burning": "燃烧", "poison": "中毒",
    "poisoned": "中毒", "poisoning": "中毒", "chill": "冰缓", "chilled": "被冰缓", "freeze": "冻结",
    "frozen": "被冻结", "shock": "感电", "shocked": "被感电", "stun": "眩晕", "stunned": "被眩晕",
    "block": "格挡", "blocked": "已格挡", "chance": "几率", "critical": "暴击", "strike": "打击",
    "cast": "施法", "casting": "施法", "channel": "引导", "channelling": "引导", "warcry": "战吼",
    "warcries": "战吼", "aura": "光环", "auras": "光环", "herald": "捷光", "banner": "旗帜",
    "brand": "烙印", "brands": "烙印", "totem": "图腾", "totems": "图腾", "trap": "陷阱",
    "traps": "陷阱", "mine": "地雷", "mines": "地雷", "curse": "诅咒", "curses": "诅咒",
    "cursed": "被诅咒", "mark": "印记", "marked": "被标记", "impale": "穿刺", "impales": "穿刺",
    "bleed": "流血", "leech": "偷取", "leeched": "已偷取", "leeching": "偷取中", "recoup": "追回复",
    "recouped": "追回复", "reservation": "保留", "reserved": "已保留", "efficiency": "效能",
    "cost": "消耗", "costs": "消耗", "level": "等级", "levels": "等级", "weapon": "武器",
    "weapons": "武器", "sword": "剑", "swords": "剑", "axe": "斧", "axes": "斧", "mace": "锤",
    "maces": "锤", "sceptre": "权杖", "sceptres": "权杖", "staff": "长杖", "staves": "长杖",
    "wand": "魔杖", "wands": "魔杖", "bow": "弓", "bows": "弓", "claw": "爪", "claws": "爪",
    "dagger": "匕首", "daggers": "匕首", "shield": "盾牌", "body": "身体", "armour": "护甲",
    "helmet": "头盔", "helmets": "头盔", "gloves": "手套", "boots": "鞋子", "belt": "腰带",
    "amulet": "项链", "amulets": "项链", "ring": "戒指", "rings": "戒指", "dual": "双持",
    "wield": "持用", "wielding": "持用", "hand": "手", "handed": "手持", "main": "主",
    "off": "副", "attack": "攻击", "movement": "移动", "action": "行动", "speed": "速度",
    "attribute": "属性", "attributes": "属性", "strength": "力量", "dexterity": "敏捷",
    "intelligence": "智慧", "accuracy": "命中", "physical": "物理", "fire": "火焰", "cold": "冰霜",
    "lightning": "闪电", "chaos": "混沌", "elemental": "元素", "all": "所有", "maximum": "最大",
    "minimum": "最小", "base": "基础", "value": "数值", "increased": "提高", "reduced": "降低",
    "increase": "提高", "increases": "提高", "reduction": "降低", "reductions": "降低",
    "more": "额外提高", "less": "额外降低", "extra": "额外", "additional": "额外", "faster": "更快",
    "slower": "更慢", "recently": "近期", "recent": "近期", "past": "过去", "every": "每",
    "each": "每个", "another": "另一个", "one": "一", "two": "两", "twice": "两倍",
    "half": "一半", "quarter": "四分之一", "third": "三分之一", "first": "首次", "final": "最后",
    "last": "持续", "random": "随机", "different": "不同", "same": "相同", "equal": "等同",
    "allies": "友军", "nearby": "附近", "affected": "受到影响", "affect": "影响", "applied": "生效",
    "equipped": "已装备", "socketed": "已镶嵌", "allocated": "已分配", "unreserved": "未保留",
    "unreserved": "未保留", "while": "当", "when": "当", "if": "若", "until": "直到", "during": "期间",
    "before": "之前", "after": "之后", "instead": "改为", "cannot": "无法", "can't": "无法",
    "unaffected": "不受影响", "immune": "免疫", "immune": "免疫", "prevent": "防止", "remove": "移除",
    "destroyed": "摧毁", "explode": "爆炸", "explodes": "爆炸", "exploding": "爆炸", "explosion": "爆炸",
    "deal": "造成", "deals": "造成", "dealing": "造成", "take": "承受", "taken": "所受", "gain": "获得",
    "gains": "获得", "gained": "获得", "grant": "授予", "grants": "获得", "recover": "回复",
    "recovery": "回复", "recovering": "回复", "regenerate": "回复", "regeneration": "回复",
    "penetrate": "穿透", "penetrates": "穿透", "pierce": "穿透", "pierces": "穿透", "ignore": "无视",
    "ignores": "无视", "convert": "转化", "converted": "转化", "converts": "转化", "trigger": "触发",
    "triggered": "触发", "triggers": "触发", "create": "创造", "creates": "创造", "summon": "召唤",
    "summons": "召唤", "summoned": "召唤", "hit": "击中", "hits": "击中", "killed": "击杀",
    "kill": "击杀", "killing": "击杀", "cause": "造成", "causes": "造成", "inflict": "施加",
    "inflicts": "施加", "applies": "施加", "apply": "施加", "grants": "获得", "grant": "给予",
    "taunt": "嘲讽", "taunted": "被嘲讽", "hinder": "阻碍", "hindered": "被阻碍", "blind": "致盲",
    "blinded": "被致盲", "fortify": "护体", "fortified": "护体", "fortification": "护体值",
    "intimidate": "威吓", "intimidated": "被威吓", "maim": "瘫痪", "maimed": "被瘫痪",
    "exert": "强化", "exerted": "已强化", "exerted": "强化后的", "stance": "姿态", "stances": "姿态",
    "rage": "怒火", "valour": "勇气值", "soul": "灵魂", "souls": "灵魂", "corpse": "尸体",
    "corpses": "尸体", "ground": "地面", "area": "区域", "near": "附近", "presence": "范围内",
    "radius": "半径", "range": "范围", "number": "数量", "count": "数量", "threshold": "门槛",
    "chance": "几率", "effect": "效果", "duration": "持续时间", "speed": "速度", "rate": "速度",
    "recharge": "充能", "recharging": "充能", "delay": "延迟", "recovery": "回复", "efficiency": "效能",
    "reservation": "保留", "modifier": "词缀", "modifiers": "词缀", "damage": "伤害", "life": "生命",
    "mana": "魔力", "energy": "能量", "shield": "护盾", "armour": "护甲", "evasion": "闪避",
    "accuracy": "命中", "resistance": "抗性", "resistances": "抗性", "multiplier": "倍率",
    "elemental": "元素", "physical": "物理", "fire": "火焰", "cold": "冰霜", "lightning": "闪电",
    "chaos": "混沌", "attack": "攻击", "attacks": "攻击", "spell": "法术", "spells": "法术",
    "skill": "技能", "skills": "技能", "melee": "近战", "projectile": "投射物", "projectiles": "投射物",
    "critical": "暴击", "strike": "打击", "block": "格挡", "ailment": "异常状态", "ailments": "异常状态",
    "poison": "中毒", "poisoned": "中毒", "bleed": "流血", "bleeding": "流血", "ignite": "点燃",
    "ignited": "被点燃", "burning": "燃烧", "chill": "冰缓", "chilled": "被冰缓", "freeze": "冻结",
    "frozen": "被冻结", "shock": "感电", "shocked": "被感电", "stun": "眩晕", "stunned": "被眩晕",
    "curse": "诅咒", "curses": "诅咒", "cursed": "被诅咒", "aura": "光环", "auras": "光环",
    "herald": "捷光", "banner": "旗帜", "brand": "烙印", "totem": "图腾", "totems": "图腾",
    "trap": "陷阱", "traps": "陷阱", "mine": "地雷", "mines": "地雷", "flask": "药剂",
    "flasks": "药剂", "tincture": "灵药", "tinctures": "灵药", "minion": "召唤物", "minions": "召唤物",
    "enemy": "敌人", "enemies": "敌人", "target": "目标", "targets": "目标", "monster": "怪物",
    "monsters": "怪物", "ally": "友军", "allies": "友军", "party": "队伍", "member": "成员",
    "members": "成员", "nearby": "附近", "close": "近距离", "low": "低", "full": "满",
    "maximum": "最大", "minimum": "最小", "base": "基础", "life": "生命", "mana": "魔力",
    "charges": "球", "charge": "球", "endurance": "耐力", "frenzy": "狂怒", "power": "暴击",
    "mastery": "专精", "passive": "被动", "point": "点", "points": "点", "jewel": "珠宝",
    "socket": "插槽", "gem": "宝石", "gems": "宝石", "level": "等级", "levels": "等级",
    "weapon": "武器", "weapons": "武器", "sword": "剑", "swords": "剑", "axe": "斧", "axes": "斧",
    "mace": "锤", "maces": "锤", "sceptre": "权杖", "sceptres": "权杖", "staff": "长杖",
    "staves": "长杖", "wand": "魔杖", "wands": "魔杖", "bow": "弓", "bows": "弓", "claw": "爪",
    "claws": "爪", "dagger": "匕首", "daggers": "匕首", "shield": "盾牌", "body": "身体",
    "helmet": "头盔", "helmets": "头盔", "gloves": "手套", "boots": "鞋子", "belt": "腰带",
    "amulet": "项链", "amulets": "项链", "ring": "戒指", "rings": "戒指", "dual": "双持",
    "wield": "持用", "wielding": "持用", "hand": "手", "handed": "手持", "main": "主",
    "off": "副", "strength": "力量", "dexterity": "敏捷", "intelligence": "智慧", "attribute": "属性",
    "attributes": "属性", "recently": "近期", "recent": "近期", "past": "过去", "first": "首次",
    "final": "最后", "last": "最后", "random": "随机", "different": "不同", "same": "相同",
    "equal": "等同", "affected": "受到影响", "affect": "影响", "applied": "生效", "equipped": "已装备",
    "socketed": "已镶嵌", "allocated": "已分配", "unreserved": "未保留", "while": "当", "when": "当",
    "if": "若", "until": "直到", "during": "期间", "before": "之前", "after": "之后", "instead": "改为",
    "unaffected": "不受影响", "immune": "免疫", "destroyed": "摧毁", "explode": "爆炸", "explodes": "爆炸",
    "exploding": "爆炸", "explosion": "爆炸", "metre": "米", "metres": "米", "second": "秒",
    "seconds": "秒", "minute": "分钟", "per": "每", "each": "每个", "every": "每", "to": "至",
    "of": "的", "from": "来自", "by": "由", "for": "对", "with": "与", "without": "没有",
    "and": "与", "or": "或", "the": "", "a": "一", "an": "一", "any": "任意", "all": "所有",
    "other": "其他", "another": "另一个", "one": "一", "two": "两", "twice": "两倍", "half": "一半",
    "quarter": "四分之一", "third": "三分之一", "more": "额外提高", "less": "额外降低",
    "increased": "提高", "reduced": "降低", "increases": "提高", "increase": "提高",
    "reduction": "降低", "reductions": "降低", "extra": "额外", "additional": "额外", "faster": "更快",
    "slower": "更慢", "number": "数量", "value": "数值", "type": "类型", "types": "类型",
    "damageable": "可受伤的", "nearby": "附近", "large": "大型", "small": "小型", "medium": "中型",
    "rare": "稀有", "unique": "传奇", "magic": "魔法", "normal": "普通", "enemy": "敌人",
    "enemies": "敌人", "monster": "怪物", "monsters": "怪物", "you": "你", "your": "你的",
    "you've": "你已", "you're": "你正", "they": "它们", "their": "它们的", "it": "它", "is": "是",
    "are": "是", "has": "拥有", "have": "拥有", "been": "已", "be": "成为", "being": "处于",
    "can": "可以", "cannot": "无法", "can't": "无法", "does": "会", "do": "会", "not": "不", "no": "没有",
    "strength's": "力量的", "dexterity's": "敏捷的", "intelligence's": "智慧的",
    # Attributes and common skill/archetype names.
    "scion": "贵族", "marauder": "野蛮人", "ranger": "游侠", "witch": "女巫", "duelist": "决斗者",
    "templar": "圣堂武僧", "shadow": "暗影", "ascendant": "升华者", "assassin": "刺客", "berserker": "暴徒",
    "champion": "冠军", "chieftain": "酋长", "deadeye": "锐眼", "elementalist": "元素使", "gladiator": "卫士",
    "guardian": "守护者", "hierophant": "圣宗", "inquisitor": "判官", "juggernaut": "勇士", "necromancer": "死灵师",
    "occultist": "秘术师", "pathfinder": "追猎者", "raider": "侠客", "saboteur": "破坏者", "slayer": "处刑者",
    "trickster": "欺诈师", "warden": "守林人", "chieftain": "酋长", "reliquarian": "遗物收藏家", "luminary": "辉光者",
    "king": "王", "king's": "王的", "mists": "迷雾", "abyssal": "深渊", "aul": "奥尔", "brinerot": "盐沼盗匪",
    "catarina": "卡塔莉娜", "farrul": "法鲁尔", "lycia": "莉西亚", "olroth": "奥洛斯", "oshabi": "奥莎比",
    "trialmaster": "试炼大师", "warlock": "术士", "breachlord": "裂隙领主", "primalist": "原始主义者",
    "necromantic": "死灵", "delirious": " delirious", "abyssal": "深渊", "ascendancy": "升华",
    "arakaali's": "阿拉卡力的", "ahn's": "安恩的", "doedre's": "多伊德里的", "doryani's": "多里亚尼的",
    "kaom's": "卡奥姆的", "ngamahu's": "纳伽玛胡的", "ramako": "拉玛柯", "hinekora": "希内科拉",
    "sione's": "西奥妮的", "tukohama": "图科哈玛", "valako": "瓦拉柯", "xirgil's": "希尔吉尔的",
    "sione": "西奥妮", "chayula": "夏乌拉", "esh": "艾许", "tul": "图尔", "tukohama": "图科哈玛",
    "shimmeron": "微光之触", "elevore": "伊莱沃尔", "afarud": "阿法鲁德", "kitava": "奇塔弗",
    "hinekora": "希内科拉", "ngamahu": "纳伽玛胡", "tasalio": "塔萨里奥", "valako": "瓦拉柯",
    "ramako": "拉玛柯", "arcanist's": "奥术师的", "precursor's": "先驱者的", "farrul's": "法鲁尔的",
    "doedre's": "多伊德里的", "doryani's": "多里亚尼的", "hinekora,": "希内科拉，", "valako,": "瓦拉柯，",
    "ramako,": "拉玛柯，", "sione,": "西奥妮，", "ngamahu,": "纳伽玛胡，", "xirgil's": "希尔吉尔的",
    "mastery": "专精", "fire": "火焰", "cold": "冰霜", "lightning": "闪电", "chaos": "混沌",
    "physical": "物理", "elemental": "元素", "arcane": "奥术", "holy": "神圣", "dark": "黑暗",
    "blood": "鲜血", "soul": "灵魂", "storm": "风暴", "frost": "寒霜", "frozen": "冻结",
    "wood": "木", "grove": "林地", "tide": "潮汐", "wind": "风", "winter": "冬季", "sun": "太阳",
    "moon": "月亮", "star": "星辰", "stars": "星辰", "light": "光", "darkness": "黑暗", "shadow": "暗影",
    "flame": "烈焰", "flames": "烈焰", "ash": "灰烬", "fire": "火焰", "fury": "怒火", "might": "力量",
    "power": "力量", "strength": "力量", "agility": "敏捷", "wisdom": "智慧", "knowledge": "知识",
    "precision": "精准", "accuracy": "命中", "speed": "速度", "damage": "伤害", "life": "生命",
    "mana": "魔力", "armour": "护甲", "evasion": "闪避", "shield": "护盾", "resistance": "抗性",
    "resistances": "抗性", "recovery": "回复", "regeneration": "回复", "leech": "偷取", "duration": "持续时间",
    "effect": "效果", "range": "距离", "radius": "半径", "area": "范围", "weapon": "武器", "skill": "技能",
    "attack": "攻击", "spell": "法术", "projectile": "投射物", "melee": "近战", "critical": "暴击",
    "strike": "打击", "block": "格挡", "ailment": "异常状态", "ailments": "异常状态", "chance": "几率",
    "mastery": "专精", "passive": "被动", "jewel": "珠宝", "socket": "插槽", "point": "点",
    "of": "之", "the": "", "and": "与", "for": "对", "a": "", "an": "",
}

# Reviewed vocabulary for the long-tail source terminology and named passives.
# Proper character/place/skill names use established Chinese names where known;
# less common one-off names are transliterated by the fallback below.
WORDS.update({
    "able": "能够", "above": "以上", "activate": "激活", "activation": "激活", "active": "生效中",
    "added": "附加", "adds": "增加", "affecting": "影响", "affects": "影响", "again": "再次",
    "against": "对", "also": "也", "already": "已经", "always": "始终", "among": "其中",
    "around": "周围", "as": "作为", "at": "在", "away": "远离", "become": "变为", "becomes": "变为",
    "below": "以下", "both": "两者", "but": "但", "by": "由", "causing": "造成", "change": "改变",
    "changed": "改变后", "could": "可以", "doesn't": "不会", "don't": "不会", "ever": "曾经",
    "found": "找到", "from": "来自", "if": "若", "in": "在", "into": "成为", "is": "是",
    "it": "它", "its": "其", "near": "附近", "never": "从不", "new": "新的", "no": "没有",
    "of": "的", "on": "时", "once": "每次", "only": "仅", "or": "或", "other": "其他",
    "own": "自身", "that": "该", "than": "比", "the": "", "their": "其", "them": "它们",
    "there": "其中", "this": "此", "those": "那些", "through": "穿过", "to": "至", "under": "低于",
    "up": "上升", "was": "曾", "way": "方式", "were": "曾", "which": "其", "within": "范围内",
    "with": "与", "without": "没有", "would": "会", "you": "你", "your": "你的", "yourself": "你自身",
    "you've": "你已", "you're": "你正", "they've": "它们已", "wasn't": "并未", "haven't": "尚未",
    "s": "的", "non": "非", "proxy": "代理", "position": "位置", "master": "主", "on": "时",
    "retaliation": "反击", "suppression": "法术压制", "suppress": "压制", "suppressed": "被压制",
    "exposure": "曝露", "reflected": "反射", "inflicted": "施加", "linked": "连接的", "link": "连接",
    "links": "连接", "total": "总计", "below": "以下", "supported": "被辅助", "support": "辅助",
    "instant": "瞬发", "instant": "瞬时", "inherent": "固有", "elusive": "灵巧", "vaal": "瓦尔",
    "surge": "浪涌", "buff": "增益效果", "buffs": "增益效果", "call": "呼唤", "guard": "防护",
    "consume": "消耗", "consumed": "已消耗", "wildwood": "幽林", "wisps": "灵尘", "steel": "钢铁",
    "quantity": "数量", "double": "翻倍", "aggravate": "加剧", "throwing": "投掷", "there": "其中",
    "unholy": "邪秽", "travel": "飞行", "moving": "移动", "added": "附加", "holding": "持有",
    "consecrated": "奉献", "mercenary": "佣兵", "onslaught": "猛攻", "detonated": "引爆",
    "stuns": "眩晕", "culling": "斩杀", "stationary": "静止", "placement": "放置", "withered": "枯萎",
    "poisons": "中毒", "masteries": "专精", "always": "始终", "raised": "召唤", "expired": "结束",
    "affecting": "影响", "usable": "可使用", "loss": "损失", "offerings": "奉献物", "back": "返回",
    "lose": "失去", "doubled": "翻倍", "phasing": "迷踪", "items": "物品", "defend": "防御",
    "golems": "魔像", "become": "变为", "attached": "附着", "unleash": "释出", "active": "已激活",
    "farther": "更远", "debilitate": "虚弱", "modified": "改变", "damaged": "受伤", "knock": "击退",
    "tenth": "十分之一", "debuffs": "减益效果", "corrupted": "腐化", "attachment": "附着", "place": "放置",
    "hexproof": "免疫诅咒", "mirage": "幻影", "permanently": "永久", "recall": "召回", "throw": "投掷",
    "placed": "已放置", "ward": "灵护", "intensity": "强度", "seals": "封印", "chests": "宝箱",
    "open": "开启", "shocks": "感电", "within": "范围内", "filling": "填满", "ever": "曾经",
    "wild": "荒野", "red": "红色", "marks": "印记", "uncapped": "未封顶", "longer": "更久",
    "nightblade": "夜刃", "repeat": "重复", "spread": "扩散", "higher": "更高", "adjacent": "相邻",
    "cruelty": "残暴", "adrenaline": "肾上腺素", "equip": "装备", "spectres": "灵体", "occur": "发生",
    "based": "基于", "left": "离开", "stunning": "眩晕", "unlucky": "不幸", "jewels": "珠宝",
    "archer": "弓箭手", "overcapped": "超上限", "reduce": "降低", "chills": "冰缓", "death": "死亡",
    "arrows": "箭矢", "bypass": "绕过", "evade": "闪避", "crush": "碾压", "lowered": "降低",
    "values": "数值", "treat": "视为", "inverted": "反转", "element": "元素", "lucky": "幸运",
    "hitting": "击中", "expires": "结束", "dies": "死亡", "arrow": "箭矢", "allocate": "分配",
    "starting": "起始", "passives": "被动天赋", "expire": "结束", "nearest": "最近", "beast": "野兽",
    "hallowing": "圣化", "detonate": "引爆", "provides": "提供", "bark": "树皮", "links": "连接",
    "share": "共享", "highest": "最高", "deactivate": "停用", "start": "开始", "ms": "毫秒",
    "older": "更久", "convocation": "号召", "sand": "沙地", "mirror": "镜像", "blink": "闪现",
    "quiver": "箭袋", "shards": "碎片", "multiply": "乘算", "able": "能够", "transfers": "转移",
    "chain": "连锁", "reserve": "保留", "blue": "蓝色", "cover": "覆盖", "explicit": "明示的",
    "skeletons": "骷髅", "plague": "瘟疫", "bearer": "携带者", "beams": "光束", "break": "断开",
    "long": "较长", "players": "玩家", "stealth": "隐匿", "fortifying": "获得护体", "fanatic": "狂热",
    "granted": "获得", "transfiguration": "蜕变", "lost": "失去", "triple": "三倍", "green": "绿色",
    "ruthless": "残酷", "linger": "持续", "spellslinger": "法术 slinger", "chained": "连锁", "get": "获得",
    "unbound": "未束缚", "penance": "忏悔", "started": "开始", "critically": "暴击时", "spent": "消耗",
    "tension": "张力", "baryatic": "巴雅提克", "reaching": "抵达", "attacked": "攻击", "infinite": "无限",
    "die": "死亡", "remain": "保持", "lasting": "持续", "purity": "纯净", "times": "次", "most": "最多",
    "sacrifice": "牺牲", "zombies": "僵尸", "thunder": "雷霆", "attach": "附着", "force": "力量",
    "never": "从不", "debuff": "减益效果", "lower": "更低", "remain": "保持", "new": "新的",
    "further": "更远", "four": "四", "fourth": "第四", "sixth": "第六", "tenth": "十分之一",
    "once": "一次", "only": "仅", "own": "自身", "owner": "拥有者", "pacified": "平息", "pacify": "平息",
    "passage": "通路", "penalties": "惩罚", "permanently": "永久", "phantasm": "幻灵", "phantasmal": "幻灵",
    "phantasms": "幻灵", "pierced": "穿透", "place": "放置", "placed": "已放置", "players": "玩家",
    "poisons": "中毒", "possible": "可能", "prevented": "被防止", "prevention": "防止", "previous": "之前",
    "pride": "骄傲", "protects": "保护", "provides": "提供", "proximity": "接近", "punishment": "惩戒",
    "quantity": "数量", "queue": "队列", "quivers": "箭袋", "radiance": "辉光", "raging": "怒火中",
    "raise": "召唤", "raised": "召唤", "randomly": "随机", "ranged": "远程", "reach": "达到", "reaching": "抵达",
    "recalled": "召回", "recovered": "回复", "reduce": "降低", "reduces": "降低", "reducing": "降低",
    "reflected": "反射", "reflection": "反射", "reflects": "反射", "refresh": "刷新", "regain": "重新获得",
    "regenerated": "回复", "relic": "遗物", "remaining": "剩余", "remote": "远程", "repeat": "重复",
    "replaced": "替换", "require": "需要", "required": "需要", "reserve": "保留", "restoration": "恢复",
    "restore": "恢复", "resummoned": "重新召唤", "return": "返回", "returning": "返回", "right": "正确",
    "ruby": "红玉", "rucksack": "背包", "s": "的", "sacrifice": "牺牲", "sapped": "枯竭",
    "sapphire": "蓝玉", "scorch": "焦灼", "seal": "封印", "seals": "封印", "sentinel": "哨兵",
    "sentinels": "哨兵", "sequences": "序列", "shadow's": "暗影的", "shake": "震荡", "shards": "碎片",
    "shatter": "粉碎", "shattered": "粉碎", "shepherd": "牧者", "shield's": "护盾的", "shields": "护盾",
    "shocks": "感电", "shots": "射击", "shroud": "帷幕", "sixth": "第六", "skeleton": "骷髅",
    "skeletons": "骷髅", "slot": "插槽", "slots": "插槽", "smoke": "烟雾", "spawn": "生成", "spawned": "生成",
    "spectral": "幽魂", "spectre": "灵体", "spend": "消耗", "spending": "消耗", "spent": "消耗",
    "spiders": "蜘蛛", "spiritinfusion": "灵体灌注", "splash": "溅射", "spread": "扩散", "stacks": "层",
    "start": "开始", "started": "开始", "starting": "起始", "starts": "开始", "steal": "窃取",
    "stealth": "隐匿", "store": "储存", "strikes": "打击", "stunning": "眩晕", "stuns": "眩晕",
    "support": "辅助", "supported": "被辅助", "surrounding": "周围", "suspend": "暂停", "takes": "承受",
    "taking": "承受", "target's": "目标的", "targeting": "瞄准", "taunts": "嘲讽", "tenth": "十分之一",
    "terrain": "地形", "than": "比", "that": "该", "them": "它们", "there": "其中", "they've": "它们已",
    "this": "此", "those": "那些", "throw": "投掷", "thrown": "投出", "tiger": "猛虎", "times": "次",
    "tension": "张力", "tenth": "十分之一", "tenth": "十分之一", "ting": "触发", "total": "总计",
    "totem's": "图腾的", "transfers": "转移", "transfiguration": "蜕变", "transformed": "转化",
    "travel": "飞行", "travels": "飞行", "treat": "视为", "tree": "天赋树", "triggerbots": "触发机器人",
    "triple": "三倍", "unattached": "未附着", "unbound": "未束缚", "unbroken": "未破碎", "uncapped": "未封顶",
    "under": "低于", "unearth": "掘地", "unencumbered": "未受负重影响", "unfreeze": "解冻", "unholy": "邪秽",
    "unleash": "释出", "unlucky": "不幸", "unnerved": "受惊", "unsealed": "未封印", "upfront": "预先",
    "usable": "可使用", "using": "使用", "utility": "功能性", "values": "数值", "vine": "藤蔓",
    "vines": "藤蔓", "viridian": "翠绿", "virulence": "毒性", "vulnerability": "脆弱", "war": "战争",
    "warcried": "战吼后", "was": "曾", "weeping": "哀泣", "well": "良好", "were": "曾", "whichever": "无论哪种",
    "wild": "荒野", "wildwood": "幽林", "wisps": "灵尘", "witch's": "女巫的", "wither": "枯萎",
    "withering": "枯萎", "within": "范围内", "would": "会", "wounds": "伤口", "yours": "你的",
    "yourself": "你自身", "zealotry": "狂热",
    # Frequently named passive concepts.
    "acrimony": "怨愤", "acrobatics": "移形换影", "acuity": "锐利", "adamant": "坚定", "adaptive": "适应",
    "adder's": "毒蛇的", "adept": "熟练", "adjacent": "相邻", "admonisher": "训诫者", "advance": "前进",
    "advantage": "优势", "aegis": "神盾", "aerialist": "空中行者", "aerodynamics": "空气动力学",
    "affliction": "苦痛", "agent": "使者", "aggravate": "加剧", "aggravation": "恶化", "aggression": "侵袭",
    "aggressive": "侵略性", "agnostic": "不可知论者", "agony": "苦楚", "ahead": "先机", "aid": "援助",
    "al": "阿尔", "alchemist": "炼金术士", "alacrity": "轻捷", "ambidexterity": "双手灵巧", "ambition": "雄心",
    "amidst": "身处", "amplify": "增幅", "ancestral": "先祖", "animosity": "敌意", "annihilation": "湮灭",
    "anointed": "涂油", "antifreeze": "防冻", "antivenom": "解毒", "apathy": "冷漠", "apostate": "背教者",
    "apparatus": "装置", "application": "应用", "aptitude": "天赋", "archer": "弓箭手", "arcing": "电弧",
    "arsonist": "纵火者", "artisan": "工匠", "artist": "艺者", "artistry": "技艺", "aspect": "形态",
    "assassination": "暗杀", "assault": "突袭", "atrophy": "萎缩", "attrition": "消耗", "attunement": "调谐",
    "augury": "预兆", "authority": "权威", "avatar": "化身", "avidity": "贪欲", "awakening": "觉醒",
    "awareness": "洞察", "awe": "敬畏", "backstabbing": "背刺", "ballistics": "弹道学", "bane": "灾厄",
    "bannerman": "旗手", "barbarism": "野蛮", "bastion": "堡垒", "battery": "蓄能", "battlefield": "战场",
    "beacon": "信标", "beef": "强健", "beetle's": "甲虫的", "bellow": "咆哮", "berserking": "狂暴",
    "binding": "束缚", "bitter": "苦痛", "blacksmith": "铁匠", "blacksmith's": "铁匠的", "bladedancer": "刃舞者",
    "blanketed": "笼罩", "blightheart": "枯萎之心", "bloodletting": "放血", "bloodline": "血脉", "bloodscent": "血腥气息",
    "bloodsoaked": "浸血", "bloom": "绽放", "blowback": "反冲", "bodyguard": "护卫", "bodyguards": "护卫",
    "bone": "骨骼", "boon": "恩泽", "bravery": "勇气", "breakers": "破坏者", "brinkmanship": "临界战术",
    "broadside": "齐射", "bulwark": "壁垒", "butchery": "屠戮", "calamitous": "灾厄", "calculated": "精算",
    "cannibalised": "吞噬", "cannibalistic": "食人", "capacitor": "电容", "carapace": "甲壳", "caress": "轻抚",
    "carnage": "屠杀", "cascade": "连锁", "cauterisation": "灼烧", "chalice": "圣杯", "charisma": "魅力",
    "chemistry": "炼金", "choir": "合唱", "clockwork": "发条", "clout": "威势", "coldhearted": "冷酷",
    "colloidal": "胶质", "combatant": "战士", "composure": "沉着", "concoction": "调剂", "concussive": "震荡",
    "conduit": "导体", "conjoined": "结合", "conjured": "召唤", "conquest": "征服", "conservationist": "守护者",
    "contemplative": "沉思", "counterattack": "反击", "counterweight": "配重", "crackling": "噼啪", "crank": "曲柄",
    "cremator": "焚化者", "cryogenesis": "低温生成", "dawnbreaker": "破晓者", "deathmarked": "死亡标记",
    "deceitful": "欺诈", "deflection": "偏斜", "disemboweling": "开膛", "dismembering": "肢解", "dread": "恐惧",
    "drought": "干旱", "druidic": "德鲁伊", "endbringer": "终焉使者", "farsight": "远见", "fettle": "健壮",
    "fidelitas": "菲德利塔斯", "fleetfoot": "疾足", "fletcher": "制箭师", "fusillade": "齐射", "gloomfang": "幽暗之牙",
    "gravepact": "墓地契约", "haemorrhage": "大出血", "hematophagy": "嗜血", "heartseeker": "觅心者", "heartstopper": "断心者",
    "huntleader": "猎群领袖", "ironwood": "铁木", "kamasa": "卡玛萨", "kopec": "科佩克", "lethe": "遗忘之河",
    "lobotomy": "脑叶切除", "magebane": "法师克星", "nightstalker": "夜行者", "phlebotomist": "放血者",
    "pitfighter": "斗坑战士", "polaric": "极星", "queller": "平息者", "raker": "搜掠者", "runebinder": "符文缚者",
    "runesmith": "符文匠", "sanguimancy": "血术", "spinecruncher": "碎脊者", "throatseeker": "觅喉者",
    "toxicist": "毒术师", "vinespike": "藤刺", "wandslinger": "魔杖手", "yaomac": "亚欧马克",
    "zealot's": "狂信者的", "nature's": "自然的", "hunter's": "猎人的", "mother's": "母亲的",
    "mender's": "修复者的", "farrul's": "法鲁尔的", "golem's": "魔像的", "hound's": "猎犬的",
    "thief's": "盗贼的", "toad's": "蟾蜍的", "veteran's": "老兵的", "warrior's": "战士的",
    "precursor's": "先驱者的", "arcanist's": "奥术师的", "gladiator's": "卫士的", "razor's": "剃刃的",
    "serpent's": "巨蛇的", "shaman's": "萨满的", "storm's": "风暴的", "winter's": "冬季的",
    "kaom's": "卡奥姆的", "ngamahu's": "纳伽玛胡的", "xirgil's": "希尔吉尔的", "doedre's": "多伊德里的",
    "doryani's": "多里亚尼的", "sione's": "西奥妮的", "arakaali's": "阿拉卡力的", "ahn's": "安恩的",
    "nature": "自然", "nature's": "自然的", "vaal": "瓦尔", "aegis": "神盾", "aura": "光环",
    "vivid": "鲜活", "primal": "原始", "ancestral": "先祖", "wild": "荒野", "ward": "灵护",
    "found": "已发现", "path": "路径", "position": "位置", "basic": "基础", "bloodline": "血脉",
    "caster": "施法者", "throwing": "投掷", "heart": "之心", "will": "意志", "primal": "原始",
    "blade": "刀刃", "offence": "进攻", "placement": "放置", "force": "力量", "decay": "衰败",
    "defence": "防御", "focus": "专注", "faith": "信念", "flesh": "血肉", "death": "死亡", "oath": "誓约",
    "legendary": "传奇", "aspect": "形态", "protection": "防护", "divine": "神圣", "barrier": "屏障",
    "burn": "燃烧", "hunter": "猎人", "eye": "之眼", "essence": "精华", "shaper": "塑界者",
    "bond": "羁绊", "iron": "铁", "hex": "诅咒", "martial": "武技", "display": "显现", "warrior": "战士",
    "battle": "战斗", "steel": "钢铁", "gaze": "凝视", "lich": "巫妖", "deep": "深层", "skin": "皮肤",
    "righteous": "正义", "killer": "杀手", "skewering": "贯穿", "enduring": "持久", "brutal": "残暴",
    "runes": "符文", "disciple": "门徒", "spirit": "灵体", "void": "虚空", "deadly": "致命", "technique": "技艺",
    "blast": "爆破", "prismatic": "棱彩", "pure": "纯粹", "dance": "舞步", "unwavering": "坚定不移",
    "sanctuary": "圣所", "drinker": "饮者", "savage": "野蛮", "penetration": "穿透", "slaughter": "屠戮",
    "explosive": "爆炸", "wounds": "伤口", "munitions": "军火", "expiry": "消逝", "breaker": "破坏者",
    "vigour": "活力", "evil": "邪恶", "blades": "刀刃", "command": "统御", "pain": "痛苦", "destruction": "毁灭",
    "shot": "射击", "rite": "仪式", "potency": "效力", "fervour": "热忱", "pact": "契约", "volatile": "易燃",
    "dominion": "主宰", "lesson": "教诲", "breath": "吐息", "powerful": "强大", "assault": "突袭",
    "wicked": "邪恶", "price": "代价", "leader": "领袖", "instruments": "器具", "inspiration": "灵感",
    "golem": "魔像", "status": "状态", "form": "形态", "overwhelm": "压制", "charm": "护符", "army": "军团",
    "infusion": "灌注", "recall": "召回", "attunement": "调谐", "careful": "谨慎", "infused": "灌注",
    "quick": "迅捷", "combat": "战斗", "chain": "连锁", "purpose": "使命", "elements": "元素",
    "divinity": "神性", "blows": "重击", "mercenary": "佣兵", "war": "战争", "priest": "祭司",
    "precise": "精准", "vicious": "凶残", "walker": "行者", "natural": "自然", "embrace": "拥抱",
    "wall": "壁垒", "self": "自身", "profane": "亵渎", "specialist": "专家", "tempest": "风暴",
    "fangs": "獠牙", "utmost": "极致", "born": "天生", "forbidden": "禁忌", "perfection": "完美",
    "bulwark": "壁垒", "wildwood": "幽林", "seal": "封印", "reflexes": "反射", "legacy": "传承",
    "pursuit": "追猎", "dancer": "舞者", "conservation": "守护", "atrophy": "枯萎", "seasons": "四季",
    "eternal": "永恒", "suffering": "苦难", "bolts": "箭矢", "knockback": "击退", "judgement": "审判",
    "zeal": "热忱", "thrill": "快感", "shadows": "暗影", "stone": "岩石", "offering": "奉献物",
    "holding": "持有", "fight": "战斗", "wrath": "怒火", "cruel": "残酷", "feast": "盛宴", "jagged": "锯齿",
    "fatal": "致命", "consecrated": "奉献", "toxic": "剧毒", "usable": "可使用", "consumed": "已消耗",
    "empowered": "强化", "caller": "召唤者", "disorienting": "迷乱", "archer": "弓箭手", "wolf": "狼",
    "crimson": "深红", "lasting": "持续", "mystic": "秘术", "swiftness": "迅捷", "bear": "熊",
    "instability": "不稳定", "graceful": "优雅", "melding": "融合", "opportunistic": "伺机", "mystical": "神秘",
    "crusade": "远征", "wasting": "衰耗", "vitality": "活力", "fearsome": "骇人", "toxins": "毒素",
    "vengeance": "复仇", "explosives": "爆炸物", "stamina": "耐力", "destructive": "毁灭性", "capacitor": "电容",
    "invigorating": "振奋", "eagle": "雄鹰", "sabotage": "破坏", "doom": "厄运", "unholy": "邪秽",
    "intensity": "强度", "arms": "武器", "perfect": "完美", "agony": "苦楚", "veteran": "老兵", "impact": "冲击",
    "thoughts": "思绪", "ghost": "幽魂", "mage": "法师", "bane": "灾厄", "siphon": "虹吸", "relentless": " relentless",
    "bringer": "使者", "ruin": "毁灭", "blizzard": "暴风雪", "response": "回应", "teachings": "教诲",
    "endless": "无尽", "student": "学徒", "beacon": "信标", "wildwood": "幽林", "protection": "防护",
})

WORDS.update({
    # Additional titles and source-word inflections found by a full-corpus pass.
    "alive": "存活", "angle": "角度", "angry": "愤怒", "arena": "竞技场", "arm": "手臂",
    "arrowheads": "箭头", "arsenal": "武库", "art": "技艺", "arts": "技艺", "assert": "坚定",
    "assured": "确保", "astonishing": "惊人", "asylum": "庇护所", "ball": "球", "basics": "基础",
    "belts": "腰带", "bestowed": "授予", "bite": "撕咬", "black": "黑色", "blank": "空白",
    "blaze": "烈焰", "blessed": "受祝福", "blessing": "祝福", "blooded": "浸血", "bloodless": "无血",
    "blunt": "钝击", "bomb": "炸弹", "bound": "束缚", "breaths": "吐息", "brewed": "调制",
    "bright": "明亮", "brine": "盐水", "brink": "边缘", "brush": "拂扫", "brutality": "残暴",
    "burden": "负担", "burst": "爆发", "cage": "牢笼", "calculation": "计算", "calm": "沉静",
    "cane": "手杖", "cat": "猫", "challenge": "挑战", "chilling": "冰缓", "chip": "碎片",
    "circle": "圆环", "circling": "环绕", "clarity": "清晰", "cleansed": "净化", "cleansing": "净化",
    "cleaving": "劈砍", "clever": "机敏", "cloth": "布料", "coated": "涂覆", "commander": "统领",
    "compound": "复合", "conduction": "传导", "confident": "坚定", "connections": "连接", "constitution": "体质",
    "construction": "构筑", "contempt": "蔑视", "control": "控制", "conviction": "定罪", "cooked": "炙烤",
    "coordination": "协调", "cordial": "热忱", "core": "核心", "cornered": "困兽", "corrosive": "腐蚀",
    "corruption": "腐化", "corruption's": "腐化的", "courage": "勇气", "cracking": "破裂", "craft": "工艺",
    "crave": "渴望", "crazy": "疯狂", "creeping": "蔓延", "crime": "罪行", "crusader": "十字军",
    "crusher": "粉碎者", "crushing": "粉碎", "cry": "呼喊", "crystal": "水晶", "cult": "教团",
    "cunning": "狡诈", "cuts": "斩击", "damned": "被诅咒", "dancing": "舞动", "daring": "大胆",
    "darting": "突进", "dazzling": "耀眼", "dead": "死亡", "death's": "死亡的", "decree": "法令",
    "deeds": "功绩", "defences": "防御", "defender": "防御者", "defiance": "抗争", "defiant": "不屈",
    "defiled": "亵渎", "defy": "抗拒", "deliberate": "蓄意", "delivery": "投递", "demise": "陨落",
    "demolitions": "爆破", "depth": "深度", "dervish": "旋刃舞者", "desiccated": "干涸", "design": "设计",
    "destroyer": "毁灭者", "detect": "察觉", "determined": "坚定", "detonation": "引爆", "detonations": "引爆",
    "devastating": "毁灭性", "devastation": "毁灭", "devastator": "毁灭者", "devices": "装置", "devotion": "虔诚",
    "dhih": "迪希", "diamond": "钻石", "didn't": "没有", "dire": "可怕", "dirty": "污秽",
    "disciples": "门徒", "discipline": "纪律", "discord": "不和", "disease": "疾病", "disintegration": "瓦解",
    "distance": "距离", "distilled": "蒸馏的", "distiller": "蒸馏师", "dominance": "主宰", "dominator": "主宰者",
    "dragon": "巨龙", "draw": "抽取", "dreamer": "梦行者", "drive": "驱动", "dynamo": "发电机",
    "eater": "吞噬者", "echo": "回响", "ed": "之", "edge": "边缘", "efficient": "高效", "effigy": "雕像",
    "ego": "自我", "elder": "长老", "eldritch": "异界", "electric": "闪电", "elegant": "优雅", "elixir": "灵药",
    "enhanced": "强化", "enigmatic": "神秘", "entrench": "固守", "entropy": "熵", "envoy": "使者",
    "equilibrium": "平衡", "equity": "公正", "escalation": "升级", "escape": "逃脱", "ethereal": "空灵",
    "everlasting": "永恒", "example": "范例", "exceptional": "卓越", "excess": "过量", "execution": "处决",
    "executioner": "处刑者", "expanse": "延展", "expansive": "扩张", "expeditious": "迅捷", "expendability": "消耗",
    "experience": "经验", "experienced": "老练", "expert": "专家", "expertise": "专精", "exploit": "利用",
    "extraction": "提取", "falcon": "猎鹰", "fall": "坠落", "fan": "扇动", "fang": "獠牙", "far": "远",
    "farewell": "告别", "farric": "法里克", "fasting": "禁食", "fealty": "效忠", "fear": "恐惧",
    "feasting": "宴飨", "feed": "喂养", "feeders": "吞噬者", "feline": "猫科", "feller": "伐木者",
    "femurs": "股骨", "fending": "防御", "fertile": "肥沃", "field": "领域", "fiends": "恶魔",
    "fiery": "炽热", "finesse": "技巧", "fingers": "手指", "flame's": "烈焰的", "flammable": "易燃",
    "flash": "闪光", "flaying": "剥皮", "flexible": "灵活", "flow": "流动", "flows": "流动",
    "focal": "焦点", "foe": "敌人", "foes": "敌人", "follow": "跟随", "forceful": "强力",
    "forces": "力量", "foresight": "预见", "forethought": "深谋", "forger": "锻造者", "forget": "忘却",
    "forgiveness": "宽恕", "fork": "分叉", "forking": "分裂", "formula": "公式", "fortitude": "坚毅",
    "foul": "污秽", "frantic": "狂乱", "freedom": "自由", "frenetic": "狂热", "frequency": "频率",
    "frigid": "严寒", "fuel": "燃料", "fulfilling": "充盈", "fundamentals": "基础", "furious": "狂怒",
    "fusilade": "齐射", "fusillade": "齐射", "galvanic": "电流", "gambit": "奇策", "gathering": "汇聚",
    "genius": "天才", "getaway": "脱身", "ghastly": "骇人", "gifts": "恩赐", "glacial": "冰川",
    "glade": "林间空地", "gladiatorial": "斗士的", "glancing": "擦击", "glory": "荣耀", "glutton": "暴食者",
    "gluttony": "暴食", "golden": "黄金", "goliath": "歌利亚", "gore": "血腥", "grace": "优雅",
    "grand": "宏伟", "gratuitous": "无端", "grave": "墓穴", "grim": "冷酷", "grip": "握持",
    "growth": "成长", "guarding": "守护", "guerilla": "游击", "guidance": "指引", "guile": "诡计",
    "hammer": "战锤", "handling": "操控", "happen": "发生", "harbinger": "先驱者", "hard": "坚硬",
    "hardened": "硬化", "harmony": "和谐", "harpooner": "鱼叉手", "harrier": "猎手", "harsh": "严酷",
    "harvester": "收割者", "hasty": "仓促", "hatchet": "手斧", "haunting": "萦绕", "hawk": "苍鹰",
    "headsman": "刽子手", "health": "生命", "hearty": "强健", "heat": "热量", "heavy": "沉重",
    "heraldry": "纹章", "heralds": "捷光", "herbalism": "草药学", "herbalist": "草药师", "heresy": "异端",
    "heritage": "传承", "hero": "英雄", "heroism": "英勇", "hibernator": "冬眠者", "high": "高",
    "hill": "山丘", "hired": "受雇", "hitter": "击中者", "holistic": "整体", "hollow": "空洞",
    "hope": "希望", "horde": "兽群", "howl": "嚎叫", "hues": "色彩", "hulking": "魁梧",
    "hunger": "饥饿", "hunt": "狩猎", "hunted": "被猎杀", "hypnotic": "催眠", "ice": "冰",
    "icon": "徽记", "idea": "构想", "ideas": "构想", "ideation": "构思", "illuminated": "照亮",
    "imbalanced": "失衡", "impacts": "冲击", "impaler": "穿刺者", "impression": "印象", "improvisor": "即兴者",
    "inclinations": "倾向", "incorporeal": "无形", "indiscriminate": "无差别", "indomitable": "不屈",
    "inevitable": "不可避免", "inexorable": "无情", "infamy": "恶名", "influence": "影响力",
    "injury": "伤害", "inoculation": "防护", "insatiable": "贪得无厌", "insightfulness": "洞察力",
    "inspirational": "鼓舞人心", "inspired": "受到启发", "inspiring": "鼓舞", "instinct": "本能",
    "insulated": "绝缘", "intellect": "智力", "intensifying": "增强", "intent": "意图", "intentions": "意图",
    "interruption": "中断", "introspection": "内省", "intuition": "直觉", "inveterate": "根深蒂固",
    "jewellery": "珠宝", "jugular": "颈脉", "justice": "正义", "kinetic": "动能", "kineticism": "动能术",
    "knife": "匕首", "knighthood": "骑士精神", "knocks": "击退", "lash": "鞭击", "lava": "熔岩",
    "lead": "引领", "leadership": "领导力", "legends": "传说", "lessons": "教训", "lethality": "杀伤力",
    "liege": "领主", "like": "如同", "liquid": "液体", "lone": "孤独", "longshot": "远射",
    "lord": "领主", "loyal": "忠诚", "loyalty": "忠诚", "lust": "欲望", "lynx": "猞猁",
    "maelstrom": "漩涡", "magmatic": "岩浆", "magnifier": "放大者", "magpie": "喜鹊", "maji": "玛吉",
    "maker": "造物者", "malice": "恶意", "malicious": "恶毒", "manifestation": "显现", "march": "行军",
    "marshal": "统帅", "mass": "质量", "masterful": "精湛", "mastermind": "谋士", "matter": "物质",
    "me": "我", "measured": "精准", "medicine": "药剂", "meditation": "冥想", "mender": "修复者",
    "mental": "精神", "mentality": "心智", "merciless": "无情", "messenger": "信使", "metal": "金属",
    "militarism": "军国主义", "mind": "心智", "mindfulness": "专注", "mindless": "无心", "misery": "苦难",
    "mistress": "女主人", "mistwalker": "雾行者", "mixed": "混合", "mixture": "混合物", "mob": "群怪",
    "molten": "熔火", "moment": "瞬间", "momentum": "动能", "mortifying": "羞辱", "mountain": "山岳",
    "movements": "移动", "multishot": "多重射击", "murderous": "杀戮", "muscle": "肌肉", "mysticism": "神秘术",
    "nameless": "无名", "naught": "虚无", "need": "需求", "nimbleness": "灵巧", "noble": "高贵",
    "nomadic": "游牧", "numbing": "麻痹", "oak": "橡木", "oblivion": "湮灭", "occupying": "占据",
    "one's": "自身的", "openness": "开放", "opportunity": "机会", "oppression": "压迫", "overcharge": "过载",
    "overcharged": "过载", "overload": "超载", "overlord": "霸主", "overprepared": "准备充分", "overshock": "过度感电",
    "overwhelming": "压倒性", "owl": "猫头鹰", "pack": "兽群", "pall": "阴霾", "palm": "掌心",
    "paralysis": "麻痹", "patience": "耐心", "peace": "平静", "peak": "巅峰", "penitence": "忏悔",
    "perception": "感知", "perfected": "完善", "perfectionist": "完美主义者", "performance": "表现", "perseverance": "坚持",
    "persistence": "持久", "physique": "体魄", "piercing": "穿刺", "pillage": "掠夺", "pious": "虔诚",
    "plaguebringer": "瘟疫使者", "poisonous": "有毒", "polymath": "博学者", "portents": "征兆", "potent": "强效",
    "practical": "实用", "practiced": "熟练", "practised": "熟练", "preparation": "准备", "prepared": "准备就绪",
    "presage": "预兆", "preservation": "保存", "pressure": "压力", "prey": "猎物", "primeval": "原初",
    "primordial": "原始", "prism": "棱镜", "prodigal": "挥霍", "prodigious": "惊人", "proficiency": "熟练度",
    "projection": "投射", "prolonged": "延长", "prophecy": "预言", "providence": "天佑", "provocateur": "挑衅者",
    "prowess": "英勇", "prowler": "潜行者", "psyche": "心灵", "purposeful": "坚定", "pyromaniac": "纵火狂",
    "pyrotechnics": "烟火术", "quickstep": "轻步", "radiant": "辉耀", "rallying": "集结", "rampart": "壁垒",
    "rapidity": "迅速", "rattling": "震颤", "ravenous": "贪婪", "raze": "夷平", "reaction": "反应",
    "readiness": "准备", "reapplication": "重新施加", "reaver": "掠夺者", "rebirth": "重生", "redemption": "救赎",
    "reinforcement": "增援", "reinvigoration": "复振", "release": "释放", "remains": "残骸", "remarkable": "非凡",
    "remedies": "疗法", "rend": "撕裂", "renewal": "复苏", "renowned": "闻名", "repartee": "机锋",
    "repeater": "连发", "replenishing": "补充", "reply": "回应", "reprisal": "报复", "resistant": "抗性",
    "resolute": "坚决", "resourcefulness": "机变", "retort": "回击", "retribution": "惩罚", "revelry": "狂欢",
    "revenge": "复仇", "rhythm": "节奏", "ribcage": "胸腔", "ricochet": "弹跳", "rime": "霜冻",
    "riot": "暴乱", "risk": "风险", "rites": "仪式", "ritual": "仪式", "river": "河流", "roar": "咆哮",
    "roaring": "咆哮", "robust": "强韧", "roiling": "翻涌", "roots": "根系", "rot": "腐坏", "rote": "机械重复",
    "rotten": "腐烂", "rouse": "唤醒", "run": "奔行", "runic": "符文", "rush": "冲锋", "sacred": "神圣",
    "sadist": "施虐者", "safeguard": "守护", "sage": "贤者", "saint": "圣者", "saints": "圣者",
    "salt": "盐", "sanctity": "圣洁", "sanctum": "圣殿", "sands": "沙漠", "sap": "树液", "sapper": "工兵",
    "savagery": "野蛮", "savant": "博学者", "savour": "品味", "scale": "鳞片", "scars": "伤痕",
    "scintillating": "闪耀", "screams": "尖啸", "searching": "搜寻", "searing": "灼热", "season": "季节",
    "seasoned": "老练", "secrets": "秘密", "seeker": "寻觅者", "selective": "选择性", "sensation": "感知",
    "sentries": "哨兵", "sentry": "哨兵", "septic": "腐败", "serpent": "巨蛇", "serpentine": "蛇形",
    "servant": "仆从", "servitude": "奴役", "set": "套装", "settling": "沉降", "seven": "七",
    "shade": "幽影", "shadowed": "笼罩暗影", "shamanistic": "萨满", "shifting": "变换", "shining": "闪耀",
    "shout": "呼喊", "shrapnel": "弹片", "shrieking": "尖啸", "shrine": "圣坛", "sign": "标记",
    "silent": "寂静", "silhouette": "剪影", "sinner": "罪人", "six": "六", "skeletal": "骸骨",
    "skittering": "疾行", "skull": "头骨", "skullbreaker": "碎颅者", "sleepless": "不眠", "sleight": "巧手",
    "smashing": "粉碎", "smite": "惩击", "smoking": "烟雾", "snaring": "束缚", "snow": "雪",
    "snowforged": "雪铸", "snowstorm": "暴雪", "soldier": "士兵", "solipsism": "唯我论", "sovereignty": "主权",
    "special": "特殊", "spellbreaker": "破法者", "spike": "尖刺", "spiked": "尖刺", "spire": "尖塔",
    "spirits": "灵体", "spiritual": "精神", "spite": "怨恨", "spiteful": "怨毒", "split": "分裂",
    "splitting": "分裂", "spring": "泉源", "stand": "立足", "starlight": "星光", "static": "静态",
    "steadfast": "坚定", "steady": "稳定", "steelwood": "钢木", "steeped": "浸润", "step": "步伐",
    "steps": "步伐", "stoic": "坚忍", "stormrider": "风暴骑者", "storms": "风暴", "streamlined": "流畅",
    "striker": "打击者", "strong": "强大", "stubborn": "顽固", "style": "风格", "sublime": "崇高",
    "successive": "连续", "suffusion": "浸染", "summer": "夏日", "sun's": "太阳的", "supercharge": "超载",
    "supreme": "至高", "surefooted": "稳健", "surgeon": "外科医生", "surging": "涌动", "surprise": "突袭",
    "surveillance": "监视", "survivalist": "求生者", "survivor": "幸存者", "sustenance": "滋养", "swagger": "自信",
    "swift": "迅捷", "swings": "挥击", "swordplay": "剑术", "tactics": "战术", "talents": "天赋",
    "taste": "品味", "techniques": "技艺", "tempered": "淬炼", "tempt": "诱惑", "tenacity": "坚韧",
    "terror": "恐惧", "terrors": "恐惧", "testudo": "龟阵", "thaumophage": "奇术吞噬者", "therapy": "疗愈",
    "thick": "厚重", "thief": "盗贼", "thought": "思绪", "threat": "威胁", "thunderstruck": "雷击",
    "tireless": "不倦", "titanic": "巨人", "tolerance": "容忍", "torment": "折磨", "totemic": "图腾",
    "touch": "触碰", "towering": "高耸", "training": "训练", "trance": "恍惚", "tranquility": "宁静",
    "trauma": "创伤", "trial": "试炼", "tribal": "部族", "trick": "诡计", "trickery": "欺诈",
    "true": "真正", "twin": "双生", "umbral": "幽影", "unbreakable": "坚不可摧", "uncompromising": "毫不妥协",
    "undeniable": "不可否认", "undertaker": "送葬者", "unfaltering": "坚定不移", "unflinching": "无畏",
    "unhallowed": "亵渎", "unlight": "暗光", "unnatural": "非自然", "unrelenting": "无情", "unrestrained": "不受约束",
    "unseen": "隐匿", "unspeakable": "不可言说", "unstable": "不稳定", "unstoppable": "不可阻挡",
    "untiring": "不知疲倦", "untouchable": "不可触及", "unwaveringly": "坚定地", "unyielding": "不屈",
    "vampirism": "吸血", "vanquisher": "征服者", "vast": "广阔", "vector": "方向", "velka": "维尔卡",
    "vengeant": "复仇", "venoms": "毒液", "versatile": "多才", "versatility": "多面性", "victim": "受害者",
    "vile": "邪恶", "violence": "暴力", "viper": "毒蛇", "virtue": "美德", "vital": " vital",
    "voltage": "电压", "voracious": "贪婪", "wake": "苏醒", "warning": "警告", "watchtowers": "瞭望塔",
    "water": "流水", "waves": "波涛", "weak": "虚弱", "weakness": "虚弱", "weathered": "历经风霜",
    "weave": "编织", "weaver": "编织者", "weight": "重量", "wellspring": "源泉", "whirling": "旋转",
    "whispers": "低语", "widespread": "广泛", "wilds": "荒野", "window": "窗口", "winds": "疾风",
    "wish": "愿望", "witnesses": "见证者", "wizardry": "巫术", "word": "言语", "words": "言语",
    "worship": "崇拜", "worthy": "值得", "wound": "伤口", "wrapped": "包裹", "wrecking": "摧毁",
    "written": "书写", "youth": "青春", "relentless": "无情", "spellslinger": "法术 slinger",
    "delirious": "迷乱", "non": "非", "low": "低", "high": "高", "on": "时", "in": "在",
    "as": "作为", "at": "处于", "than": "比", "that": "该", "there": "其中", "which": "其",
    "also": "也", "against": "对", "below": "以下", "above": "以上", "with": "与", "without": "没有",
    "inside": "内部", "outside": "外部", "within": "范围内", "around": "周围", "ever": "曾经",
    "once": "一次", "only": "仅", "already": "已经", "still": "仍然", "lessen": "减少",
    "allowed": "允许", "attempt": "尝试", "alive": "存活", "allied": "友军", "archers": "弓箭手",
    "attackers": "攻击者", "banners": "旗帜", "barkskin": "树皮之肤", "barnacles": "藤壶", "barrage": "弹幕",
    "barrages": "弹幕", "battlemage": "战斗法师", "began": "开始", "belts": "腰带", "bifurcatedcrit": "分岔暴击",
    "bifurcates": "分岔", "bismuth": "铋", "bonefeeders": "食骨者", "breaks": "破坏", "brittle": "脆弱",
    "bypasses": "绕过", "called": "呼唤", "capped": "封顶", "category": "类别", "chaining": "连锁",
    "chains": "连锁", "chaotic": "混沌", "character": "角色", "chosen": "选中", "cloud": "云雾",
    "cluster": "集群", "colliding": "碰撞", "conductivity": "导电性", "consuming": "消耗", "convergence": "汇聚",
    "counted": "计入", "covered": "覆盖", "created": "创造", "cryonic": "低温", "damagable": "可受伤的",
    "deactivated": "已停用", "desecrate": "亵渎", "despair": "绝望", "determination": "坚定", "died": "死亡",
    "directions": "方向", "disabled": "禁用", "dodge": "闪避", "domain": "领域", "drop": "掉落",
    "drowning": "溺水", "due": "由于", "effigy": "雕像", "empty": "空", "enfeeble": "衰弱",
    "evaded": "已闪避", "exceeds": "超过", "fail": "失败", "fanaticism": "狂热", "farric": "法里克",
    "fertile": "肥沃", "fewer": "更少", "filled": "填满", "fired": "发射", "fishing": "垂钓",
    "fist": "拳头", "flammability": "可燃性", "following": "接下来", "fork": "分叉", "forking": "分裂",
    "foulborn": "污秽诞生", "freezes": "冻结", "frostbite": "冻伤", "fungal": "真菌", "gaining": "获得",
    "gale": "疾风", "glorious": "荣耀", "granting": "授予", "grasping": "抓取", "greater": "更高",
    "green": "绿色", "having": "拥有", "hexes": "诅咒", "hexproof": "免疫诅咒", "hire": "雇佣",
    "hit's": "击中时", "hoarfrost": "白霜", "icons": "图标", "impaled": "被穿刺", "impenetrable": "不可穿透",
    "ing": "中", "insufficient": "不足", "interact": "互动", "interrupted": "被打断", "inventory": "背包",
    "item": "物品", "items": "物品", "knocked": "击退", "land": "着地", "later": "之后", "leave": "离开",
    "left": "离开", "line": "行", "location": "位置", "losing": "失去", "loss": "损失", "lost": "失去",
    "lowest": "最低", "madness": "疯狂", "malediction": "恶咒", "malevolence": "恶意", "mania": "躁狂",
    "many": "许多", "marks": "印记", "masteries": "专精", "minimap": "小地图", "missing": "缺失",
    "misty": "迷雾", "moved": "移动", "much": "许多", "notable": "核心天赋", "occur": "发生",
    "offerings": "奉献物", "older": "更久", "open": "开启", "overcapped": "超上限", "overkill": "过量击杀",
    "own": "自身", "owner": "拥有者", "passages": "通路", "passives": "被动天赋", "penance": "忏悔",
    "phantasms": "幻灵", "pierced": "穿透", "players": "玩家", "poisons": "中毒", "possible": "可能",
    "prevented": "被阻止", "prevention": "防止", "previous": "之前", "pride": "骄傲", "profane": "亵渎",
    "protects": "保护", "provides": "提供", "proximity": "接近", "punishment": "惩戒", "queue": "队列",
    "quiver": "箭袋", "quivers": "箭袋", "radiance": "辉光", "radiance's": "辉光的", "raging": "怒火中",
    "randomly": "随机", "ranged": "远程", "reaching": "抵达", "recalled": "召回", "recovered": "回复",
    "reduces": "降低", "reducing": "降低", "reflection": "反射", "reflects": "反射", "regain": "重新获得",
    "regenerated": "回复", "relic": "遗物", "remaining": "剩余", "remote": "远程", "reoccur": "再次触发",
    "replaced": "替换", "require": "需要", "required": "需要", "restoration": "恢复", "restore": "恢复",
    "resummoned": "重新召唤", "returning": "返回", "ruby": "红玉", "rucksack": "背包", "sapped": "被压制",
    "sapphire": "蓝玉", "scorch": "焦灼", "seals": "封印", "sentinels": "哨兵", "sequences": "序列",
    "shake": "震荡", "shards": "碎片", "shatter": "粉碎", "shattered": "粉碎", "shepherd": "牧者",
    "shields": "护盾", "shocks": "感电", "shots": "射击", "shroud": "帷幕", "skeleton": "骷髅", "skeletons": "骷髅",
    "slot": "插槽", "slots": "插槽", "smoke": "烟雾", "spawn": "生成", "spawned": "生成", "spectral": "幽魂",
    "spectre": "灵体", "spend": "消耗", "spending": "消耗", "spent": "消耗", "spiders": "蜘蛛", "spiritinfusion": "灵体灌注",
    "splash": "溅射", "spread": "扩散", "stacks": "层", "started": "开始", "starting": "起始", "starts": "开始",
    "steal": "窃取", "stealth": "隐匿", "store": "储存", "stunning": "眩晕", "stuns": "眩晕", "surrounding": "周围",
    "suspend": "暂停", "takes": "承受", "taking": "承受", "target's": "目标的", "targeting": "瞄准", "taunts": "嘲讽",
    "tenth": "十分之一", "terrain": "地形", "they've": "它们已", "throw": "投掷", "thrown": "投出", "tiger": "猛虎",
    "times": "次", "totem's": "图腾的", "transfers": "转移", "transfiguration": "蜕变", "transformed": "转化",
    "travels": "飞行", "triggerbots": "触发机器人", "unattached": "未附着", "unbound": "未束缚", "unbroken": "未破碎",
    "under": "低于", "unearth": "掘地", "unencumbered": "未受负重影响", "unfreeze": "解冻", "unleash": "释出",
    "unlucky": "不幸", "unnerved": "受惊", "unsealed": "未封印", "upfront": "预先", "usable": "可使用", "using": "使用",
    "utility": "功能性", "values": "数值", "vine": "藤蔓", "vines": "藤蔓", "virulence": "毒性", "warcried": "战吼后",
    "weeping": "哀泣", "well": "良好", "whichever": "无论哪种", "witch's": "女巫的", "withering": "枯萎",
    "would": "会", "wounds": "伤口", "yours": "你的", "yourself": "你自身", "zealotry": "狂热",
    "alchemist's": "炼金术士的", "assassin's": "刺客的", "banner's": "旗帜的", "duelist's": "决斗者的",
    "marauder's": "野蛮人的", "mercenary's": "佣兵的", "ranger's": "游侠的", "templar's": "圣堂武僧的",
    "hit's": "击中时", "totem's": "图腾的", "delirious": "迷乱", "relentless": "无情", "spellslinger": "法术施法者",
    "vital": "活力", "godless": "无神", "off": "离开", "s": "的", "war's": "战争的",
    "aggravated": "加剧", "amethyst": "紫水晶", "anger": "愤怒", "areas": "范围", "ballista": "弩炮",
    "haste": "急速", "hatred": "憎恨", "size": "尺寸", "so": "因此", "synaptic": "突触",
    "tailwind": "顺风", "temporal": "时空", "topaz": "黄玉", "torrent": "激流", "zombie": "僵尸",
    "kinginthemists": "迷雾之王",
})

NAME_OVERRIDES = {
    "": "",
    "Jewel Socket": "珠宝插槽",
    "root": "星图根节点",
    "Fire Mastery": "火焰专精",
    "Cold Mastery": "冰霜专精",
    "Lightning Mastery": "闪电专精",
    "Life Mastery": "生命专精",
    "Mana Mastery": "魔力专精",
    "Armour Mastery": "护甲专精",
}

PHRASES.update({
    "Projectile Speed": "投射物飞行速度",
    "Ignite Duration": "点燃持续时间",
    "Damage with Hits against Enemies": "对敌人的击中伤害",
    "Enemies that cannot have Life Leeched from them": "无法被偷取生命的敌人",
    "Life Modifiers on Equipped Body Armour": "已装备的身体护甲上的生命词缀",
    "Equipped Body Armour": "已装备的身体护甲",
    "Mana Cost Efficiency": "魔力消耗效能",
    "Life Leech": "生命偷取",
    "total Recovery per second from Life Leech": "生命偷取每秒总回复",
    "Spell Damage taken": "所受法术伤害",
    "Cold Damage taken": "所受冰霜伤害",
    "Fire Damage taken": "所受火焰伤害",
    "Lightning Damage taken": "所受闪电伤害",
    "Chaos Damage taken": "所受混沌伤害",
    "maximum number of Seals": "最大封印数",
    "Spells supported by Unleash": "受到释出辅助的法术",
    "Life Masteries allocated": "已分配的生命专精",
    "Chilled by your Hits": "被你的击中冰缓",
    "Cold Damage taken increased by Chill Effect": "所受冰霜伤害按冰缓效果提高",
    "increased by Chill Effect": "按冰缓效果提高",
    "on Equipped": "已装备的",
    "on you": "在你身上",
    "you have": "你拥有",
    "you've been Hit Recently": "你近期被击中",
    "if there are no": "若没有",
    "if you have at least": "若你至少拥有",
    "if you have": "若你拥有",
    "if you've": "若你已",
    "if you": "若你",
    "while you have": "当你拥有",
    "while you are": "当你处于",
    "while at": "当达到",
    "as Extra": "作为额外",
    "every second": "每秒",
    "Endurance Charge": "耐力球",
    "Endurance Charges": "耐力球",
    "Fire Damage over Time Multiplier": "火焰持续伤害倍率",
    "Attack Damage taken": "所受攻击伤害",
    "Damage taken": "所受伤害",
    "Damage over Time taken": "所受持续伤害",
    "Chance to Evade Attacks": "攻击闪避几率",
    "Chance to Block Attack Damage": "攻击伤害格挡几率",
    "Chance to Block Spell Damage": "法术伤害格挡几率",
    "Critical Strike Multiplier for Spell Damage": "法术伤害暴击倍率",
    "Critical Strike Multiplier for Melee Damage": "近战暴击倍率",
    "Life Regeneration Rate": "生命回复速度",
    "Mana Regeneration Rate": "魔力回复速度",
    "maximum Total Life Recovery per Second from Leech": "偷取每秒最大生命总回复",
    "Maximum total Life Recovery per second from Leech": "偷取每秒最大生命总回复",
    "Maximum total Mana Recovery per second from Leech": "偷取每秒最大魔力总回复",
    "Maximum total Energy Shield Recovery per second from Leech": "偷取每秒最大能量护盾总回复",
    "Damage over Time Multiplier for Poison you inflict on Bleeding Enemies": "你施加给流血敌人的中毒持续伤害倍率",
    "Damage over Time Multiplier for Ailments": "异常状态持续伤害倍率",
    "Effect of Herald Buffs on you": "你身上的捷光增益效果",
    "Effect of your Marks": "你的印记效果",
    "Area of Effect of Curse Aura Skills": "诅咒光环技能的效果范围",
    "Maximum Power Charges": "最大暴击球数量",
    "Minimum Power Charges": "最小暴击球数量",
    "Maximum Endurance Charges": "最大耐力球数量",
    "Maximum Frenzy Charges": "最大狂怒球数量",
    "Minimum number of Summoned Totems": "召唤图腾数量下限",
    "maximum number of Summoned Totems": "召唤图腾数量上限",
    "number of Summoned Totems": "召唤图腾数量",
    "Duration of Damaging Ailments": "伤害性异常状态持续时间",
    "Duration of Elemental Ailments": "元素异常状态持续时间",
    "Duration of Non-Damaging Ailments": "非伤害性异常状态持续时间",
    "Duration of Ailments": "异常状态持续时间",
    "Duration of your Ailments": "你的异常状态持续时间",
})

CLASS_NAMES = {
    "Scion": "贵族", "Marauder": "野蛮人", "Ranger": "游侠", "Witch": "女巫",
    "Duelist": "决斗者", "Templar": "圣堂武僧", "Shadow": "暗影",
}

MODIFIERS = {"increased": "提高", "reduced": "降低", "more": "额外提高", "less": "额外降低"}
WORD_PATTERN = re.compile(r"[A-Za-z]+(?:['’][A-Za-z]+)?")
NUMBER_PATTERN = re.compile(r"[+-]?\d+(?:\.\d+)?")


def _translate_terms(text: str, unknown: set[str]) -> str:
    # Protect modifier terms here; the entry point will translate them as
    # operators when they express a numeric modifier, and as normal wording
    # in other phrases.
    for source, target in sorted(PHRASES.items(), key=lambda row: len(row[0]), reverse=True):
        pattern = re.escape(source)
        if source[:1].isalpha():
            pattern = r"(?<![A-Za-z])" + pattern
        if source[-1:].isalpha():
            pattern += r"(?![A-Za-z])"
        text = re.sub(pattern, target, text, flags=re.IGNORECASE)

    def replace_word(match: re.Match[str]) -> str:
        raw = match.group(0)
        lower = raw.lower().replace("’", "'")
        value = WORDS.get(lower)
        if value is None:
            unknown.add(lower)
            return raw
        return value

    return _compact_zh(WORD_PATTERN.sub(replace_word, text))


def _compact_zh(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t]*\n[ \t]*", "\n", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\s*,\s*", "，", text)
    text = re.sub(r"\s*;\s*", "；", text)
    text = re.sub(r"(?<!\d)\.(?=\s|$)", "。", text)
    text = text.replace(":", "：")
    # Chinese modifier text does not need the source English word spaces.
    text = re.sub(r"(?<=[\u3400-\u9fff]) +(?=[\u3400-\u9fff0-9])", "", text)
    text = re.sub(r"(?<=[0-9%]) +(?=[\u3400-\u9fff])", "", text)
    text = re.sub(r"(?<=[\u3400-\u9fff]) +(?=[%+\-0-9])", "", text)
    return text.strip()


def _translate_condition(condition: str, unknown: set[str]) -> str:
    value = condition.strip()
    if not value:
        return ""
    # Frequent conditional grammars read more naturally with Chinese order.
    match = re.match(r"(?i)^if there are no (.+)$", value)
    if match:
        return "若没有" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^if you've been hit recently$", value)
    if match:
        return "若你近期被击中"
    match = re.match(r"(?i)^if you have been hit by an attack recently$", value)
    if match:
        return "若你近期被攻击击中"
    match = re.match(r"(?i)^if you have been hit recently$", value)
    if match:
        return "若你近期被击中"
    match = re.match(r"(?i)^if you haven't been hit by an attack recently$", value)
    if match:
        return "若你近期未被攻击击中"
    match = re.match(r"(?i)^if you haven't been hit recently$", value)
    if match:
        return "若你近期未被击中"
    match = re.match(r"(?i)^if you haven't dealt a critical strike recently$", value)
    if match:
        return "若你近期未造成暴击"
    match = re.match(r"(?i)^if you haven't moved in the past ([0-9]+(?:\.[0-9]+)?) seconds?$", value)
    if match:
        return f"若你在过去{match.group(1)}秒内未移动"
    match = re.match(r"(?i)^if you've killed recently$", value)
    if match:
        return "若你近期击杀过敌人"
    match = re.match(r"(?i)^if you have at least (.+)$", value)
    if match:
        return "若你至少拥有" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^if you've (.+)$", value)
    if match:
        return "若你已" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^if you (.+)$", value)
    if match:
        return "若你" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^if your (.+)$", value)
    if match:
        return "若你的" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^while you have (.+)$", value)
    if match:
        return "当你拥有" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^while you are (.+)$", value)
    if match:
        return "当你处于" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^while wielding (?:a |an )?(.+)$", value)
    if match:
        return "持有" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^while holding (?:a |an )?(.+)$", value)
    if match:
        return "持有" + _translate_terms(match.group(1), unknown) + "时"
    if value.lower() == "on you":
        return "在你身上"
    match = re.match(r"(?i)^for ([0-9]+(?:\.[0-9]+)?) seconds?$", value)
    if match:
        return f"持续{match.group(1)}秒"
    match = re.match(r"(?i)^for the past ([0-9]+(?:\.[0-9]+)?) seconds?$", value)
    if match:
        return f"在过去{match.group(1)}秒内"
    match = re.match(r"(?i)^from (.+?) for ([0-9]+(?:\.[0-9]+)?) seconds?$", value)
    if match:
        source, duration = match.groups()
        return _translate_terms(source, unknown) + f"，持续{duration}秒"
    if value.lower().startswith("against "):
        return "对" + _translate_terms(value[8:], unknown)
    if value.lower().startswith("per "):
        return "每" + _translate_terms(value[4:], unknown)
    if value.lower().startswith("for each "):
        return "每个" + _translate_terms(value[9:], unknown)
    if value.lower().startswith("for every "):
        return "每" + _translate_terms(value[10:], unknown)
    return _translate_terms(value, unknown)


def _split_condition(text: str) -> tuple[str, str]:
    # These connectors start the condition/qualifier part of ordinary passive
    # lines. "for" clauses are rendered as conditions after modifier scopes;
    # longer "for each" forms are checked first to keep scaling qualifiers intact.
    connectors = [
        " if ", " when ", " while ", " against ", " per ", " for each ", " for every ",
        " for ", " from ", " on you", " on kill", " on hit", " after ", " before ", " during ",
    ]
    found: list[tuple[int, str]] = []
    lowered = text.lower()
    for connector in connectors:
        index = lowered.find(connector)
        if index >= 0:
            found.append((index, connector.strip()))
    if not found:
        return text, ""
    index, _ = min(found)
    return text[:index], text[index:]


def translate_name(source: str, unknown: set[str]) -> str:
    if source in NAME_OVERRIDES:
        return NAME_OVERRIDES[source]
    return _translate_terms(source, unknown).strip()


def translate_effect(source: str, unknown: set[str]) -> str:
    # Preserve complete source entries, including embedded line breaks, as the
    # unit to which support is assigned. These display transforms do not split
    # or feed Chinese strings back into the source parser.
    if "\n" in source or "\r" in source:
        return "\n".join(translate_effect(part, unknown) for part in source.splitlines())

    faster_ailment = re.match(r"(?i)^Damaging Ailments deal damage ([0-9]+(?:\.[0-9]+)?)% faster$", source)
    if faster_ailment:
        return f"伤害型异常状态的伤害结算加快{faster_ailment.group(1)}%"

    special_multiplier = re.match(
        r"(?i)^([+-]?\d+(?:\.\d+)?)% to Damage over Time Multiplier for Poison you inflict on Bleeding Enemies$",
        source,
    )
    if special_multiplier:
        amount = special_multiplier.group(1)
        return f"你施加给流血敌人的中毒持续伤害倍率{amount}%"

    match = re.match(r"(?i)^You count as on (.+?) while at ([0-9]+(?:\.[0-9]+)?)% of maximum Life or below$", source)
    if match:
        state, amount = match.groups()
        return f"当生命不高于最大生命{amount}%时，你视为" + _translate_terms(state, unknown)
    match = re.match(r"(?i)^You count as on (.+?) while at ([0-9]+(?:\.[0-9]+)?)% of maximum Life or above$", source)
    if match:
        state, amount = match.groups()
        return f"当生命不低于最大生命{amount}%时，你视为" + _translate_terms(state, unknown)

    match = re.match(r"(?is)^Gain ([0-9]+(?:\.[0-9]+)?) (.+?) every second if you've been Hit Recently$", source)
    if match:
        amount, grant = match.groups()
        return f"若你近期被击中，每秒获得{amount}{_translate_terms(grant, unknown)}"

    match = re.match(r"(?is)^Every ([0-9]+(?:\.[0-9]+)?) seconds?, gain ([0-9]+(?:\.[0-9]+)?)% of (.+?)\s+as Extra (.+?) for ([0-9]+(?:\.[0-9]+)?) seconds?$", source)
    if match:
        cadence, percent, base, extra, duration = match.groups()
        return (f"每{cadence}秒，将{_translate_terms(base, unknown)}的{percent}%转为额外"
                f"{_translate_terms(extra, unknown)}，持续{duration}秒")

    match = re.match(r"(?i)^([+-]?[0-9]+(?:\.[0-9]+)?)%\s+[Cc]hance to (.+)$", source)
    if match:
        amount, action = match.groups()
        # Chance is a base chance, not an increased or more modifier.
        return _compact_zh(_translate_terms(action, unknown) + "几率" + amount + "%")

    # A multiplier stat adds percentage points to that multiplier. Keep its
    # additive sign and never label it as the independent "more" operator.
    match = re.match(r"^([+-]?\d+(?:\.\d+)?)%\s+to\s+(.+?\bMultiplier\b)(.*)$", source, re.IGNORECASE | re.DOTALL)
    if match:
        amount, stat, suffix = match.groups()
        label = _translate_terms(stat, unknown)
        _, condition = _split_condition(suffix)
        if condition:
            return _compact_zh(label + " " + amount + "%（" + _translate_condition(condition, unknown) + "）")
        if suffix.lower().startswith(" for "):
            return _compact_zh(_translate_terms(suffix[5:], unknown) + label + " " + amount + "%")
        return _compact_zh(label + " " + amount + "%" + _translate_terms(suffix, unknown))

    match = re.search(r"(?<![A-Za-z])([+-]?\d+(?:\.\d+)?)%\s+(increased|reduced|more|less)\s+", source, re.IGNORECASE)
    if match:
        amount, modifier = match.groups()
        prefix = source[:match.start()]
        body = source[match.end():]
        subject, condition = _split_condition(body)
        left = _translate_terms(prefix + subject, unknown).rstrip()
        result = left + MODIFIERS[modifier.lower()] + amount + "%"
        if condition:
            result += "（" + _translate_condition(condition, unknown) + "）"
        return _compact_zh(result)

    # The plus-to construction is a flat additive grant, not an increased or
    # more modifier. Keep signs for resistance, chance, rating, and attributes.
    match = re.match(r"^([+-]?\d+(?:\.\d+)?)%\s+to\s+(.+)$", source, re.IGNORECASE | re.DOTALL)
    if match:
        amount, body = match.groups()
        subject, condition = _split_condition(body)
        result = _translate_terms(subject, unknown).strip() + " " + amount + "%"
        if condition:
            result += "（" + _translate_condition(condition, unknown) + "）"
        return _compact_zh(result)
    match = re.match(r"^([+-]?\d+(?:\.\d+)?)\s+to\s+(.+)$", source, re.IGNORECASE | re.DOTALL)
    if match:
        amount, body = match.groups()
        subject, condition = _split_condition(body)
        result = _translate_terms(subject, unknown).strip() + " " + amount
        if condition:
            result += "（" + _translate_condition(condition, unknown) + "）"
        return _compact_zh(result)

    # "faster start" is a time reduction, not the more/less damage operator.
    text = re.sub(r"(?i)(\d+(?:\.\d+)?)% faster start of Energy Shield Recharge", r"能量护盾开始充能时间缩短\1%", source)
    return _compact_zh(_translate_terms(text, unknown))


def iter_source_texts(data: dict):
    for node in data["nodes"].values():
        yield node.get("name", "")
        yield from node.get("stats", [])
        for effect in node.get("masteryEffects", []):
            yield from effect.get("stats", [])


def main() -> int:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    digest = str(data.get("source", {}).get("data_sha256", ""))
    actual_source_hash = hashlib.sha256(RAW_SOURCE.read_bytes()).hexdigest()
    if digest != EXPECTED_SHA256 or actual_source_hash != EXPECTED_SHA256:
        raise SystemExit(f"pinned source hash mismatch: runtime={digest}, raw={actual_source_hash}")
    unknown: set[str] = set()
    names = {}
    for node_id, node in data["nodes"].items():
        source_name = node.get("name", "")
        names[str(node_id)] = {"source": source_name, "zh_CN": translate_name(source_name, unknown)}
    lines = {}
    for source in sorted(set(line for n in data["nodes"].values() for line in n.get("stats", [])) |
                         set(line for n in data["nodes"].values() for effect in n.get("masteryEffects", []) for line in effect.get("stats", []))):
        lines[source] = translate_effect(source, unknown)

    classes = {entry["name"]: CLASS_NAMES[entry["name"]] for entry in data["classes"]}
    partitions = {}
    for key, branch in data["special_subtrees"]["ascendancies"].items():
        # Store original key and source label, retaining the key for metadata.
        source_label = str(branch.get("name", key))
        partitions[key] = {"source": source_label, "zh_CN": translate_name(source_label, unknown)}

    if unknown:
        print("Untranslated source words (add reviewed entries to WORDS):", file=sys.stderr)
        print("\n".join(sorted(unknown)), file=sys.stderr)
        return 2

    names_with_source = {str(node_id): names[str(node_id)] for node_id in sorted(data["nodes"], key=lambda x: (not x.isdigit(), int(x) if x.isdigit() else x))}
    effect_occurrences = sum(len(n.get("stats", [])) for n in data["nodes"].values()) + sum(
        len(effect.get("stats", [])) for n in data["nodes"].values() for effect in n.get("masteryEffects", []))
    mastery_options = sum(len(n.get("masteryEffects", [])) for n in data["nodes"].values())
    payload = {
        "schema_version": 1,
        "source": {"version": data["source"]["version"], "sha256": digest},
        "term_contract": {
            "increased": "提高", "reduced": "降低", "more": "额外提高", "less": "额外降低",
            "multiplier_plus": "倍率 +X%（同类百分点加算）",
        },
        "classes": classes,
        "partitions": partitions,
        "nodes": names_with_source,
        "lines": lines,
        "coverage": {
            "source_nodes": len(names),
            "source_node_names": sum(bool(n["source"]) for n in names.values()),
            "unique_source_node_names": len(set(n["source"] for n in names.values() if n["source"])),
            "effect_occurrences": effect_occurrences,
            "unique_effect_lines": len(lines),
            "mastery_nodes": sum(bool(n.get("isMastery")) for n in data["nodes"].values()),
            "mastery_options": mastery_options,
            "standard_nodes": len(data["standard_tree"]["default_allocation_graph"]["node_ids"]),
            "jewel_sockets": sum(bool(n.get("isJewelSocket")) for n in data["nodes"].values()),
            "classes": len(classes),
            "ascendancy_partitions": len(partitions),
            "expansion_jewel_nodes": len(data["special_subtrees"]["expansion_jewels"]["positioned_node_ids"]),
            "untranslated_names": 0,
            "untranslated_effect_lines": 0,
        },
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)}: {len(names)} source IDs, {len(lines)} exact source-line mappings, {effect_occurrences} line occurrences")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
