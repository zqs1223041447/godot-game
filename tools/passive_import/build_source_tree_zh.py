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
    "Damage with Attack Skills": "攻击技能造成的伤害",
    "Damage with Spell Skills": "法术技能造成的伤害",
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
    "Flask Charges used": "药剂充能消耗",
    "Flask Charges": "药剂充能",
    "Flask Charge": "药剂充能",
    "Flask Charges gained": "获得的药剂充能",
    "Warcry Power": "战吼威力",
    "Power counted by Warcries": "战吼计入的威力",
    "Enemy Power": "敌方威力",
    "Skill Gems": "技能宝石",
    "Skill Gem": "技能宝石",
    "Skill Effect Duration": "技能效果持续时间",
    "Herald of Ash": "灰烬之捷",
    "Herald of Ice": "冰霜之捷",
    "Herald of Thunder": "雷电之捷",
    "Herald of Purity": "纯净之捷",
    "Herald of Agony": "苦痛之捷",
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
    "per Power Charge": "每个暴击球",
    "per Frenzy Charge": "每个狂怒球",
    "per Endurance Charge": "每个耐力球",
    "Power, Frenzy or Endurance Charge": "暴击球、狂怒球或耐力球",
    "Power, Frenzy or Endurance Charges": "暴击球、狂怒球或耐力球",
    "Endurance, Frenzy or Power Charge": "耐力球、狂怒球或暴击球",
    "Endurance, Frenzy or Power Charges": "耐力球、狂怒球或暴击球",
    "Endurance, Frenzy and Power Charges": "耐力球、狂怒球与暴击球",
    "Endurance, Frenzy and Power Charge Duration": "耐力球、狂怒球与暴击球的持续时间",
    "Power, Frenzy, and Endurance Charges": "暴击球、狂怒球与耐力球",
    "per Endurance, Frenzy or Power Charge": "每个耐力球、狂怒球或暴击球",
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
    "or more": "或以上",
    "or less": "或以下",
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
    "a": "", "an": "", "the": "", "and": "与", "or": "或", "of": "的",
    "to": "至", "from": "来自", "by": "由", "for": "对", "with": "与", "without": "没有",
    "if": "若", "when": "当", "while": "当", "after": "后", "before": "前", "during": "期间",
    "per": "每", "each": "每个", "every": "每", "you": "你", "your": "你的", "you've": "你已",
    "you're": "你正", "they": "它们", "their": "它们的", "it": "它", "is": "是", "are": "是",
    "have": "拥有", "has": "拥有", "been": "已", "be": "成为", "being": "处于", "can": "可以",
    "cannot": "无法", "can't": "无法", "does": "会", "do": "会", "not": "不", "no": "没有",
    "all": "所有", "any": "任意", "other": "其他", "another": "另一个", "additional": "额外",
    "extra": "额外", "more": "更多", "less": "更少", "increased": "提高", "increases": "提高",
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
    "charge": "球", "charges": "球", "endurance": "耐力", "frenzy": "狂怒", "power": "威力",
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
    "bleed": "流血", "leech": "偷取", "leeched": "已偷取", "leeching": "偷取中", "recoup": "延迟回复",
    "recouped": "延迟回复", "reservation": "保留", "reserved": "已保留", "efficiency": "效能",
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
    "more": "更多", "less": "更少", "extra": "额外", "additional": "额外", "faster": "更快",
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
    "charges": "球", "charge": "球", "endurance": "耐力", "frenzy": "狂怒", "power": "威力",
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
    "quarter": "四分之一", "third": "三分之一", "more": "更多", "less": "更少",
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
    "power": "威力", "strength": "力量", "agility": "敏捷", "wisdom": "智慧", "knowledge": "知识",
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
    "Fuel the Fight": "战斗补给",
    "Heart of Oak": "橡木之心",
    "Two Hand Mastery": "双手武器专精",
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
    "Maximum total Life Recovery per second from Leech": "生命偷取每秒总回复上限",
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
    "Damage over Time with Bow Skills": "弓技能造成的持续伤害",
    "Damage with Hits": "击中伤害",
    "Damage with Ailments": "异常状态伤害",
    "Damage with Hits and Ailments": "击中与异常状态伤害",
    "Damage dealt": "造成的伤害",
    "Damage taken": "所受伤害",
    "Enemy Stun Threshold": "敌人眩晕门槛",
    "Stun Threshold": "眩晕门槛",
    "Chance to Suppress Spell Damage": "法术压制几率",
    "Chance to Avoid being Stunned": "避免眩晕几率",
    "Chance to Shock": "感电几率",
    "is equal to": "等于",
    "is based on": "基于",
    "is doubled": "翻倍",
    "is not applied": "不生效",
    "cannot be Stunned": "无法被眩晕",
    "Enemies you Kill": "你击杀的敌人",
    "Enemy you Kill": "你击杀的敌人",
    "provides no inherent bonus to": "不提供固有加成",
    "provides no bonus to": "不提供加成",
    "Life Reservation Efficiency of Skills": "技能的生命保留效能",
    "Mana Reservation Efficiency of Skills": "技能的魔力保留效能",
    "Attack and Cast Speed": "攻击与施法速度",
    "Cooldown Recovery Rate": "冷却回复速度",
    "Effect of Buffs": "增益效果",
    "Effect of Auras": "光环效果",
    "Off Hand": "副手",
    "Main Hand": "主手",
    "Left and Right": "左右两侧",
    "Damage from Hits": "击中造成的伤害",
    "Damage from Spell Hits": "法术击中造成的伤害",
    "Maximum Life becomes": "最大生命变为",
    "Life Recovery from Regeneration": "生命回复",
    "Your Movement Speed": "你的移动速度",
    "Unreserved Life is Filled": "未保留生命已回满",
    "Unreserved Mana is Filled": "未保留魔力已回满",
    "Enemies that are on Low Life": "低血状态的敌人",
    "Enemies that are on Full Life": "满血状态的敌人",
    "Enemies affected by": "受到影响的敌人",
    "Damage over Time Multiplier for Bleeding": "流血持续伤害倍率",
    "Damage over Time Multiplier for Poison": "中毒持续伤害倍率",
    "Damage over Time Multiplier for Ignite": "点燃持续伤害倍率",
    "to maximum Chance to Block": "最大格挡几率",
    "is instant": "即时回复",
    "is lucky": "视为幸运",
    "is unlucky": "视为不幸",
    "is aggravated": "被加剧",
    "is immune to": "免疫",
    "at least one nearby corpse": "附近至少有一具尸体",
    "Immune to": "免疫",
    "Immune to Chaos Damage": "免疫混沌伤害",
    "Immune to Physical Damage": "免疫物理伤害",
    "Immune to Elemental Ailments": "免疫元素异常状态",
})

# Whole multiline entries are translated as complete display records. Keeping
# these reviewed phrases keyed by the exact raw string preserves line-level
# runtime support checks and makes complex effects auditable.
MULTILINE_OVERRIDES = {
    "+10% to all Elemental Resistances and maximum Elemental Resistances while affected by a Non-Vaal Guard Skill\n20% additional Physical Damage Reduction while affected by a Non-Vaal Guard Skill\n20% more Damage taken if a Non-Vaal Guard Buff was lost Recently": "受到非瓦尔防护技能影响时，所有元素抗性和元素抗性上限+10%\n受到非瓦尔防护技能影响时，物理伤害减免额外提高20%\n若近期失去非瓦尔防护增益效果，所受伤害额外提高20%",
    "+4% to Critical Strike Multiplier for each Mine Detonated\nRecently, up to 40%": "每近期引爆一座地雷，暴击伤害倍率+4%\n最多40%",
    "-1 to maximum number of Summoned Totems\nYou can have an additional Brand Attached to an Enemy": "召唤图腾数量上限-1\n你可以额外在一个敌人身上附着一个烙印",
    "-10% to maximum Chance to Block Attack Damage\n-10% to maximum Chance to Block Spell Damage\n+2% Chance to Block Spell Damage for each 1% Overcapped Chance to Block Attack Damage": "攻击伤害格挡几率上限-10%\n法术伤害格挡几率上限-10%\n攻击伤害格挡几率每超上限1%，法术伤害格挡几率+2%",
    "1.5% of Physical Damage prevented from Hits in the past\n10 seconds is Regenerated as Life per second": "过去10秒内被击中所阻止的物理伤害的1.5%，会转化为每秒回复的生命",
    "10% increased Critical Strike Chance for each Mine Detonated\nRecently, up to 100%": "你近期每引爆一座地雷，暴击几率提高10%\n最多提高100%",
    "10% increased Effect of Arcane Surge on you per\n200 Mana spent Recently, up to 50%": "你近期每消耗200魔力，身上的奥术浪涌效果提高10%\n最多提高50%",
    "100% chance to Defend with 200% of Armour\nMaximum Damage Reduction for any Damage Type is 50%": "以200%护甲值进行防御的几率为100%\n任意伤害类型的最大伤害减免为50%",
    "100% increased Armour and Energy Shield from Equipped Body Armour if Equipped Helmet,\nGloves and Boots all have Armour and Energy Shield": "若已装备的头盔、手套和鞋子均有护甲与能量护盾，已装备的身体护甲所提供的护甲与能量护盾提高100%",
    "20% chance on Hit to remove all Impales from Enemy\nImpales removed this way multiply their Reflected Damage for this Hit by the number of Hits they have left": "击中时有20%几率移除敌人身上的所有穿刺\n以此方式移除的穿刺会按其剩余击中次数，乘算此次击中的反射伤害",
    "20% increased Maximum total Life Recovery per second from\nLeech if you've dealt a Critical Strike recently": "若你近期造成过暴击，生命偷取每秒总回复上限提高20%",
    "20% less Attack Damage taken if you haven't been Hit by an Attack Recently\n10% more chance to Evade Attacks if you have been Hit by an Attack Recently\n20% more Attack Damage taken if you have been Hit by an Attack Recently": "若你近期未被攻击击中，所受攻击伤害额外降低20%\n若你近期被攻击击中，攻击闪避几率额外提高10%\n若你近期被攻击击中，所受攻击伤害额外提高20%",
    "25% more Maximum Lightning Damage\n50% less Minimum Lightning Damage\nCannot deal non-Lightning Damage": "闪电最大伤害额外提高25%\n闪电最小伤害额外降低50%\n无法造成非闪电伤害",
    "30% increased Armour and Evasion Rating if your Main Hand Weapon\nhas a Red and Green Socket": "若你的主手武器有红色和绿色插槽，护甲与闪避值提高30%",
    "40% more Attack Damage if Accuracy Rating is higher than Maximum Life\nNever deal Critical Strikes": "若命中值高于最大生命，攻击伤害额外提高40%\n不会造成暴击",
    "5% chance to Defend with 200% of Armour for each\ntime you've been Hit by an Enemy Recently, up to 30%": "你近期每被敌人击中一次，以200%护甲值进行防御的几率提高5%\n最多提高30%",
    "5% increased Poison Duration for each Poison you have inflicted Recently, up\nto a maximum of 100%": "你近期每施加一次中毒效果，中毒持续时间提高5%\n最多提高100%",
    "50% less Life Regeneration Rate\n50% less maximum Total Life Recovery per Second from Leech\nEnergy Shield Recharge instead applies to Life": "生命回复速度额外降低50%\n偷取每秒最大总生命回复额外降低50%\n能量护盾充能改为作用于生命",
    "50% of Physical, Cold and Lightning Damage Converted to Fire Damage\nDeal no Non-Fire Damage": "50%的物理、冰霜与闪电伤害转化为火焰伤害\n无法造成非火焰伤害",
    "Attack Projectiles always inflict Bleeding and Maim, and Knock Back Enemies\nProjectiles cannot Pierce, Fork or Chain": "攻击投射物始终施加流血与瘫痪，并击退敌人\n投射物无法穿透、分叉或连锁",
    "Auras from your Skills can only affect you\nAura Skills have 1% more Aura Effect per 2% of maximum Mana they Reserve\n40% more Mana Reservation of Aura Skills": "你的技能产生的光环只能影响你\n光环技能每保留最大魔力的2%，光环效果额外提高1%\n光环技能的魔力保留额外提高40%",
    "Auras from your Skills grant 2% increased Attack and Cast\nSpeed to you and Allies": "你的技能产生的光环使你和友军的攻击与施法速度提高2%",
    "Auras from your Skills grant 3% increased Attack and Cast\nSpeed to you and Allies": "你的技能产生的光环使你和友军的攻击与施法速度提高3%",
    "Auras from your Skills have 8% increased Effect on you for\neach Herald affecting you, up to a maximum of 40%": "每有一个捷光影响你，你身上的光环效果提高8%\n最多提高40%",
    "Bleeding Enemies you Kill Explode, dealing 20% of\ntheir Maximum Life as Physical Damage": "你击杀的流血敌人会爆炸，造成相当于其最大生命20%的物理伤害",
    "Cannot Evade enemy Attacks\nCannot be Stunned": "无法闪避敌人的攻击\n无法被眩晕",
    "Cannot Ignite, Chill, Freeze or Shock\nCritical Strikes inflict Scorch, Brittle and Sapped": "无法被点燃、冰缓、冻结或感电\n暴击会施加焦灼、脆弱与枯竭",
    "Cannot Recover Energy Shield to above Armour\n3% of Physical Damage prevented from Hits Recently is Regenerated as Energy Shield per second": "能量护盾无法回复到高于护甲值\n近期被击中所阻止的物理伤害的3%，会转化为每秒回复的能量护盾",
    "Cannot Recover Energy Shield to above Evasion Rating\nEvery 2 seconds, gain a Ghost Shroud, up to a maximum of 3\nWhen Hit, lose a Ghost Shroud to Recover Energy Shield equal to 3% of your Evasion Rating": "能量护盾无法回复到高于闪避值\n每2秒获得一层幽魂缠绕，最多3层\n被击中时，失去一层幽魂缠绕，回复相当于你闪避值3%的能量护盾",
    "Chance to Block Attack Damage is doubled\nChance to Block Spell Damage is doubled\nYou take 65% of Damage from Blocked Hits": "攻击伤害格挡几率翻倍\n法术伤害格挡几率翻倍\n你承受格挡击中伤害的65%",
    "Consecrated Ground you create also grants\n50% reduced duration of Damaging Ailments on you": "你创造的奉献地面还会使你身上的伤害型异常状态持续时间降低50%",
    "Consecrated Ground you create causes Life Regeneration to\nalso Recover Energy Shield for you and Allies": "你创造的奉献地面还会使你和友军的生命回复同时回复能量护盾",
    "Damage over Time Multiplier for Ailments is equal to Critical Strike Multiplier\nCritical Strikes do not deal extra Damage\nNon-Critical Strikes cannot inflict Ailments": "异常状态的持续伤害倍率等于暴击伤害倍率\n暴击不会造成额外伤害\n非暴击无法施加异常状态",
    "Damageable Minions deal 30% increased Damage for each second they have been alive,\nup to a maximum of 150%": "可受伤召唤物每存活一秒，造成的伤害提高30%\n最多提高150%",
    "Damageable Minions take 5% increased Damage for each second they have been alive,\nup to a maximum of 50%": "可受伤召唤物每存活一秒，受到的伤害提高5%\n最多提高50%",
    "Dexterity provides no inherent bonus to Evasion Rating\n+1% Chance to Suppress Spell Damage per 15 Dexterity": "敏捷不再提供闪避值固有加成\n每15点敏捷，法术压制几率+1%",
    "Enemies Chilled by your Hits have Cold Damage taken increased by Chill Effect\nEnemies in your Chilling Areas have Cold Damage taken increased by Chill Effect\nCannot deal non-Cold Damage": "被你的击中冰缓的敌人，按冰缓效果提高其所受冰霜伤害\n处于你创造的冰缓区域内的敌人，按冰缓效果提高其所受冰霜伤害\n无法造成非冰霜伤害",
    "Enemies you Kill that are affected by Elemental Ailments\ngrant 100% increased Flask Charges": "你击杀的受元素异常状态影响的敌人会使药剂充能获得提高100%",
    "Energy Shield Recharge is not interrupted by Damage if Recharge began Recently\n40% less Energy Shield Recharge Rate": "近期开始的能量护盾充能不会因伤害中断\n能量护盾充能速度额外降低40%",
    "Evasion Rating is Doubled against Projectile Attacks\n25% less Evasion Rating against Melee Attacks": "对投射物攻击时，闪避值翻倍\n对近战攻击时，闪避值额外降低25%",
    "Every 10 seconds, gain 30% of Physical Damage\nas Extra Fire Damage for 4 seconds": "每10秒，获得相当于物理伤害30%的额外火焰伤害，持续4秒",
    "Every 10 seconds:\nTake 50% less Damage from Hits for 5 seconds\nTake 50% less Damage over Time for 5 seconds": "每10秒：\n受到的击中伤害额外降低50%，持续5秒\n受到的持续伤害额外降低50%，持续5秒",
    "Every second, Consume a nearby Corpse to Recover 5% of Life and Mana\n10% more Damage taken if you haven't Consumed a Corpse Recently": "每秒消耗附近一具尸体，回复相当于最大生命和魔力各5%的数值\n若近期未消耗尸体，所受伤害额外提高10%",
    "Flasks adjacent to active Tinctures gain 2 charges when you Hit an\nEnemy with a Melee Weapon, no more than once every second": "你用近战武器击中敌人时，与已激活灵药相邻的药剂获得2点药剂充能\n每秒最多触发一次",
    "Flasks adjacent to active Tinctures gain 3 charges when you Hit an\nEnemy with a Melee Weapon, no more than once every second": "你用近战武器击中敌人时，与已激活灵药相邻的药剂获得3点药剂充能\n每秒最多触发一次",
    "Flasks adjacent to applied Tincture have 10% increased Effect when\nused if you've Hit an enemy with a Weapon Recently": "若你近期用武器击中过敌人，使用与已施加灵药相邻的药剂时，药剂效果提高10%",
    "Flasks adjacent to applied Tincture have 30% increased Effect when\nused if you've Hit an enemy with a Weapon Recently": "若你近期用武器击中过敌人，使用与已施加灵药相邻的药剂时，药剂效果提高30%",
    "For each nearby corpse, you and nearby Allies Regenerate 5 Mana\nper second, up to 50 per second": "每有一具附近尸体，你和附近友军每秒回复5魔力\n最多每秒回复50魔力",
    "Gain 1 Gale Force when you use a Skill\n10% increased Effect of Tailwind on you per Gale Force": "你使用技能时获得1层疾风之力\n每有一层疾风之力，你身上的顺风效果提高10%",
    "Gain 1 Unbound Fury when you inflict an Elemental Ailment with a Hit on an Enemy, no more than once every 0.2 seconds for each type of Ailment\nCannot gain Unbound Fury while Unbound": "你用击中对敌人施加元素异常状态时，获得1层未束缚怒火；每种异常状态0.2秒最多触发一次\n处于未束缚状态时无法获得未束缚怒火",
    "Gain 2 Grasping Vines each second while stationary\n2% chance to deal Double Damage per Grasping Vine\n1% less Damage taken per Grasping Vine": "静止时每秒获得2层抓握藤蔓\n每层抓握藤蔓使造成双倍伤害的几率提高2%\n每层抓握藤蔓使你所受伤害额外降低1%",
    "Gain 20% of Physical Damage as Extra Cold Damage if you've\nused a Sapphire Flask Recently": "若你近期使用过蓝玉药剂，物理伤害的20%作为额外冰霜伤害",
    "Gain 20% of Physical Damage as Extra Fire Damage if you've\nused a Ruby Flask Recently": "若你近期使用过红玉药剂，物理伤害的20%作为额外火焰伤害",
    "Gain 20% of Physical Damage as Extra Lightning Damage if you've\nused a Topaz Flask Recently": "若你近期使用过黄玉药剂，物理伤害的20%作为额外闪电伤害",
    "Gain Defiance for 10 seconds on losing Life to an Enemy Hit, no\nmore than once every 0.3 seconds": "因敌人击中而失去生命时，获得抗争10秒\n每0.3秒最多触发一次",
    "Grant bonuses to Non-Channelling Skills you use by consuming 3 Charges from a Flask of\neach of the following types, if possible:": "消耗以下每种类型药剂中的3点药剂充能，为你使用的非引导技能施加加成（若可行）：",
    "Grants maximum Energy Shield equal to 10% of your Reserved Mana to\nyou and nearby Allies": "为你和附近友军提供相当于你保留魔力10%的最大能量护盾",
    "Hits that deal Elemental Damage remove Exposure to those Elements and inflict Exposure to other Elements\nExposure inflicted this way applies -25% to Resistances": "造成元素伤害的击中会移除对应元素的曝露，并对其他元素施加曝露\n以此方式施加的曝露使抗性-25%",
    "If you've Impaled an Enemy Recently, you\nand nearby Allies have +1000 to Armour": "若你近期对敌人施加过穿刺，你和附近友军获得护甲+1000",
    "If your Mercenary's Life is higher than your own, 20% of Damage from Hits is\ntaken from your Mercenary's Life before you": "若你的佣兵生命值高于你自身，击中造成的伤害有20%会先由佣兵的生命值承受",
    "Increases and Reductions to Armour also apply to Energy\nShield Recharge Rate at 20% of their value": "护甲的提高与降低也会按其数值的20%作用于能量护盾充能速度",
    "Increases and Reductions to Light Radius also apply to Effect\nof your Link Skill Buffs on your Mercenary": "光照范围的提高与降低也会按其数值作用于你施加在佣兵身上的连接技能增益效果",
    "Inflict a Grasping Vine on Hit against Enemies with fewer than\n8 Grasping Vines during Effect of any Life Flask": "任意生命药剂效果期间，击中拥有少于8层抓握藤蔓的敌人时，对其施加一层抓握藤蔓",
    "Intelligence provides no inherent bonus to Energy Shield\n2% reduced Duration of Elemental Ailments on you per 15 Intelligence": "智慧不再提供能量护盾固有加成\n每15点智慧，你身上的元素异常状态持续时间降低2%",
    "Leech Energy Shield instead of Life\nMaximum total Energy Shield Recovery per second from Leech is doubled\nCannot Recharge Energy Shield": "改为偷取能量护盾而非生命\n偷取每秒最大能量护盾总回复翻倍\n能量护盾无法充能",
    "Life Flask Effects are not removed when Unreserved Life is Filled\nLife Flask Effects do not Queue": "未保留生命回满时，生命药剂效果不会移除\n生命药剂效果不会进入队列",
    "Life Leech from Melee Damage is Instant\nCannot Recover Life other than from Leech": "近战伤害产生的生命偷取会立即回复\n除偷取外，无法回复生命",
    "Lose all Rage on reaching Maximum Rage and gain Wild Savagery\nfor 1 second per 10 Rage lost this way": "达到最大怒火时，失去所有怒火并获得荒野蛮性\n以此方式每失去10点怒火，效果持续1秒",
    "Modifiers to Chance to Suppress Spell Damage instead apply to Chance to Dodge Spell Hits at 50% of their value\nMaximum Chance to Dodge Spell Hits is 75%": "法术压制几率词缀改为按其数值的50%作用于法术击中闪避几率\n法术击中闪避几率上限为75%",
    "Nearby Enemy Monsters' Fire Resistance against\nDamage over Time is -20% while you are Stationary": "静止时，附近敌人怪物对持续伤害的火焰抗性为-20%",
    "Non-Unique Jewels cause Small and Notable Passive Skills in a Large Radius to\nalso grant +4 to Strength": "非传奇珠宝使大型范围内的小型和核心被动天赋额外获得力量+4",
    "Projectiles deal 20% increased Damage with Hits and Ailments for\neach remaining Chain, up to a maximum of 100%": "投射物每剩余一段连锁，击中与异常状态伤害提高20%\n最多提高100%",
    "Projectiles deal 40% increased Damage with Hits to targets at the start\nof their movement, reducing to 0% as they travel farther": "投射物在移动开始处对目标的击中伤害提高40%\n随着飞行距离增加，伤害加成逐渐降至0%",
    "Projectiles gain Damage as they travel farther, dealing up\nto 30% more Damage with Hits and Ailments": "投射物飞行距离越远，造成的伤害越高\n击中与异常状态伤害最多额外提高30%",
    "Projectiles gain Damage as they travel farther, dealing up\nto 60% increased Damage with Hits to targets": "投射物飞行距离越远，造成的伤害越高\n对目标的击中伤害最多提高60%",
    "Removes all Energy Shield\nWhile not on Full Life, Sacrifice 20% of Mana per Second to Recover that much Life": "移除所有能量护盾\n未满血时，每秒牺牲20%魔力以回复等量生命",
    "Removes all mana\n10% more maximum Life\nSkills Cost Life instead of Mana\nSkills Reserve Life instead of Mana": "移除所有魔力\n最大生命额外提高10%\n技能消耗生命而非魔力\n技能保留生命而非魔力",
    "Skills that have dealt a Critical Strike in the past 8 seconds deal 40% more Elemental Damage with Hits and Ailments\nYour Critical Strikes do not deal extra Damage\nAilments never count as being from Critical Strikes": "过去8秒内造成过暴击的技能，其击中与异常状态造成的元素伤害额外提高40%\n你的暴击不会造成额外伤害\n异常状态不再视为来自暴击",
    "Spend Energy Shield before Mana for Skill Mana Costs\nEnergy Shield protects Mana instead of Life\n50% less Energy Shield Recharge Rate": "技能魔力消耗优先消耗能量护盾\n能量护盾保护魔力而非生命\n能量护盾充能速度额外降低50%",
    "Take 50% less Damage over Time if you've started taking Damage over Time in the past second\n100% more Duration of Ailments on you": "若你在过去一秒内开始承受持续伤害，所受持续伤害额外降低50%\n你身上的异常状态持续时间额外提高100%",
    "Tinctures inflict Weeping Wounds instead of Mana Burn\nEffects that interact with Mana Burn interact with Weeping Wounds instead": "灵药施加哀泣伤口而非魔力燃烧\n与魔力燃烧互动的效果改为与哀泣伤口互动",
    "Trigger Level 30 Assassin's Mark on Attack Critical Strike against\na Rare or Unique Enemy and you have no Mark": "对稀有或传奇敌人攻击造成暴击且你没有印记时，触发30级刺客印记",
    "Triggers Level 20 Primal Aegis when Allocated\nPrimal Aegis can take 75 Elemental Damage per Allocated Notable Passive Skill": "分配后触发20级原始神盾\n每分配一个核心被动天赋，原始神盾可承受75点元素伤害",
    "Unattached Brands gain 20% increased Brand Attachment Range per\nsecond, up to a maximum of 100%": "未附着的烙印每秒获得20%烙印附着范围\n最多提高100%",
    "When your Hits Impale Enemies, also Impale other Enemies near them\nInflict 5 additional Impales on Enemies you Impale\nFor 5 seconds after you Impale Enemies, they cannot be Impaled again, and Impales cannot be Called from them": "你的击中对敌人施加穿刺时，也会对其附近的其他敌人施加穿刺\n对你施加穿刺的敌人额外施加5层穿刺\n施加穿刺后5秒内，这些敌人无法再次被穿刺，且无法从它们身上调用穿刺",
    "You and nearby Allies deal 6 to 12 added Physical Damage for\neach Impale on Enemy": "你和附近友军每有一层敌人身上的穿刺，便附加6至12点物理伤害",
    "You can inflict Bleeding on an Enemy up to 8 times\nYour Bleeding does not deal extra Damage while the Enemy is moving and cannot be Aggravated\n50% less Damage with Bleeding": "你对每个敌人最多可施加8层流血\n敌人移动时，你造成的流血不会造成额外伤害，且无法被加剧\n流血伤害额外降低50%",
    "You can inflict an additional Ignite on each Enemy\nBase Ignite Duration is 1 second\n25% less Damage with Ignite\nCannot deal non-Fire Damage": "你对每个敌人可额外施加一层点燃\n基础点燃持续时间为1秒\n点燃伤害额外降低25%\n无法造成非火焰伤害",
    "You can only have one Herald\n50% more Effect of Herald Buffs on you\n100% more Damage with Hits from Herald Skills\n50% more Damage Over Time with Herald Skills\nMinions from Herald Skills deal 25% more Damage\nYour Aura Skills are Disabled": "你最多只能拥有一个捷光\n你身上的捷光增益效果额外提高50%\n捷光技能造成的击中伤害额外提高100%\n捷光技能造成的持续伤害额外提高50%\n捷光技能的召唤物伤害额外提高25%\n你的光环技能被禁用",
    "You can't deal Damage with Skills yourself\n+1 to maximum number of Summoned Totems": "你自身无法用技能造成伤害\n召唤图腾数量上限+1",
    "You count as Dual Wielding while you are Unencumbered\n40% more Attack Speed with Melee Skills while you are Unencumbered\nAdds 14 to 20 Attack Physical Damage to Melee Skills per 10 Dexterity while you are Unencumbered": "未装备武器时，你视为双持\n未装备武器时，近战技能的攻击速度额外提高40%\n未装备武器时，每10点敏捷使近战技能附加14至20点攻击物理伤害",
    "Your Hexes have infinite Duration\n20% less Effect of your Curses": "你的诅咒持续时间无限\n你的诅咒效果额外降低20%",
    "Your Mercenary and their Minions deal 8% more Damage for\neach Unique item they have equipped": "你的佣兵及其召唤物每装备一件传奇物品，伤害额外提高8%",
    "Your Warcries do not grant Buffs or Charges to You\n100% more Warcry Duration": "你的战吼不会对你施加增益效果或为你提供各类充能球\n战吼持续时间额外提高100%",
    "Your hits can't be Evaded\nNever deal Critical Strikes": "你的击中无法被闪避\n不会造成暴击",
}

# Reviewed exact single-row exceptions for common source grammar that does not
# map cleanly through word-by-word translation (negation, state, and timing).
SINGLE_LINE_OVERRIDES = {
    "Action Speed cannot be modified to below Base Value": "行动速度无法降低至基础值以下",
    "Action Speed cannot be modified to below Base Value if you have Equipped Boots with no Socketed Gems": "若你装备的鞋子没有镶嵌宝石，行动速度无法降低至基础值以下",
    "Cannot Be Stunned while you have Energy Shield": "当你拥有能量护盾时，不会被眩晕",
    "Cannot be Blinded": "无法被致盲",
    "Cannot be Chilled": "无法被冰缓",
    "Cannot be Chilled while Burning": "燃烧时不会被冰缓",
    "Cannot be Chilled while at maximum Frenzy Charges": "狂怒球达到上限时不会被冰缓",
    "Cannot be Frozen": "无法被冻结",
    "Cannot be Ignited while at maximum Endurance Charges": "耐力球达到上限时不会被点燃",
    "Cannot be Knocked Back": "不会被击退",
    "Cannot be Shocked while at maximum Power Charges": "暴击球达到上限时不会被感电",
    "Cannot be Stunned": "无法被眩晕",
    "Cannot be Stunned by Hits that deal only Physical Damage": "不会被仅造成物理伤害的击中眩晕",
    "Cannot be Stunned if you have an Equipped Helmet with no Socketed Gems": "若你装备的头盔没有镶嵌宝石，你不会被眩晕",
    "Cannot be Stunned while Leeching": "偷取期间不会被眩晕",
    "Cannot be Stunned while you have at least 25 Rage": "拥有至少25点怒火时不会被眩晕",
    "Corrupted Blood cannot be inflicted on you": "你不会受到腐化之血",
    "Damage cannot be Reflected": "伤害不会被反射",
    "Damaging Ailments Cannot Be inflicted on you while you already have one": "当你已受到一种伤害型异常状态时，无法再被施加伤害型异常状态",
    "Elemental Ailments cannot be inflicted on you if you have an Equipped Body Armour with no Socketed Gems": "若你装备的胸甲没有镶嵌宝石，你不会受到元素异常状态",
    "Elemental Hit's Added Damage cannot be replaced this way": "元素打击的附加伤害无法以此方式替换",
    "Elusive has 50% chance to be removed from you at 100% effect": "灵巧效果达到100%时，有50%几率从你身上移除",
    "Gain 3% of Missing Unreserved Life before being Hit by an Enemy Per Defiance": "每层抗争使你在被敌人击中前，获得相当于缺失未保留生命3%的数值",
    "Hits against you Cannot be Critical Strikes if you've been Stunned Recently": "若你近期被眩晕，对你的击中无法造成暴击",
    "Mines cannot be Damaged": "地雷不会受到伤害",
    "Minions cannot be Killed, but die 6 seconds after being reduced to 1 Life": "召唤物不会被击杀；生命降至1后6秒会死亡",
    "Minions created Recently cannot be Damaged": "近期召唤的召唤物不会受到伤害",
    "Movement Speed cannot be modified to below Base Value": "移动速度无法降低至基础值以下",
    "Non-Damaging Ailments Cannot Be inflicted on you while you already have one": "当你已受到一种非伤害性异常状态时，无法再被施加非伤害性异常状态",
    "Non-Unique Jewels cause Increases and Reductions to other Damage Types in a Large Radius to be Transformed to apply to Fire Damage": "非传奇珠宝会使大型范围内其他伤害类型的提高与降低转而作用于火焰伤害",
    "Projectiles have 30% chance to be able to Chain when colliding with terrain": "投射物与地形碰撞时，有30%几率触发连锁",
    "Summoned Golems are Resummoned 4 seconds after being Killed": "召唤的魔像被击杀后4秒会重新召唤",
    "Totems' Action Speed cannot be modified to below Base Value": "图腾的行动速度无法降低至基础值以下",
    "Traps cannot be Damaged": "陷阱不会受到伤害",
    "You cannot be Frozen if you've been Frozen Recently": "近期被冻结后，你不会再次被冻结",
    "You cannot be Hindered": "你不会受到阻碍",
    "You cannot be Ignited if you've been Ignited Recently": "近期被点燃后，你不会再次被点燃",
    "You cannot be Impaled": "你不会被穿刺",
    "You cannot be Maimed": "你不会被瘫痪",
    "You cannot be Shocked if you've been Shocked Recently": "近期被感电后，你不会再次被感电",
    "Your Elemental Resistances cannot be lowered by Curses": "诅咒无法降低你的元素抗性",
    "Your Hits against Marked Enemy cannot be Blocked or Suppressed": "你对被标记敌人的击中无法被格挡或压制",
    "10% increased Attack Speed when on Full Life": "满血时，攻击速度提高10%",
    "25% increased Attack Damage when on Full Life": "满血时，攻击伤害提高25%",
    "30% more Spell Damage when on Low Life": "低血时，法术伤害额外提高30%",
    "25% chance to gain an Endurance Charge each second while Channelling": "引导期间，每秒有25%几率获得一个耐力球",
    "Gain a Frenzy Charge each second while Moving": "移动期间，每秒获得一个狂怒球",
    "Gain a Power Charge each second while Channelling a Spell": "引导法术期间，每秒获得一个暴击球",
    "Gain a Power Charge after Spending a total of 200 Mana": "消耗魔力总计达到200点后，获得一个暴击球",
    "Linked targets share Endurance, Frenzy and Power Charges with you": "连接的目标与你共享耐力球、狂怒球与暴击球",
    "Share Endurance, Frenzy and Power Charges with nearby party members": "与你附近的队伍成员共享耐力球、狂怒球与暴击球",
    "Life Flasks gain a Charge when you hit an Enemy, no more than once each second": "击中敌人时，生命药剂获得一份药剂充能；每秒最多触发一次",
    "20% increased Armour per second you've been stationary, up to a maximum of 100%": "你每静止一秒，护甲提高20%，最多提高100%",
    "Tinctures deactivate when you have 12 or more Mana Burn": "当你身上有12层或以上魔力燃烧时，灵药会停用",
    "1% increased Flask Charges gained per Mana Burn on you": "你身上每层魔力燃烧，获得的药剂充能提高1%",
    "Gain a Flask Charge when you deal a Critical Strike": "造成暴击时，获得一份药剂充能",
    "25% chance to gain a Flask Charge when you deal a Critical Strike": "造成暴击时，有25%几率获得一份药剂充能",
    "25% chance for Flasks you use to not consume Charges": "你使用药剂时，有25%几率不消耗药剂充能",
    "50% chance for Flasks you use to not consume Charges": "你使用药剂时，有50%几率不消耗药剂充能",
    "If Bismuth Flask Charges are consumed, Penetrate 25% Elemental Resistances": "消耗铋药剂充能时，穿透25%元素抗性",
    "If Diamond Flask Charges are consumed, 250% increased Critical Strike Chance": "消耗钻石药剂充能时，暴击几率提高250%",
    "Life Flasks gain 3 Charges when you Suppress Spell Damage": "你压制法术伤害时，生命药剂获得3点药剂充能",
    "Marked Enemy grants 20% increased Flask Charges to you": "被标记的敌人使你获得的药剂充能提高20%",
    "Phantasms from Penance Mark grant 50% increased Flask Charges": "忏悔印记生成的幻灵使你获得的药剂充能提高50%",
    "Enemies you Kill that are affected by Elemental Ailments\ngrant 100% increased Flask Charges": "你击杀的受元素异常状态影响的敌人会使你获得的药剂充能提高100%",
    "1% of Damage Dealt by your Minions is Leeched to you as Life": "召唤物造成的伤害中，有1%作为生命偷取转移给你",
    "Gain 25% increased Armour per 5 Power for 8 seconds when you Warcry, up to a maximum of 100%": "使用战吼时，每5点战吼威力使护甲提高25%，持续8秒，最多提高100%",
    "20% increased total Power counted by Warcries": "战吼计入的总威力提高20%",
    "25% increased total Power counted by Warcries": "战吼计入的总威力提高25%",
    "Warcries grant 1 Rage per 5 Enemy Power, up to 5": "敌方威力每有5点，战吼提供1点怒火，最多5点",
    "Warcries have 5% Chance to grant an Endurance, Frenzy or Power Charge per Power": "战吼威力每有一点，战吼就有5%几率获得一个耐力球、狂怒球或暴击球",
    "Warcries have a minimum of 10 Power": "战吼威力至少为10点",
    "Warcries have infinite Power": "战吼威力无限",
    "+20% chance to Ignite, Freeze, Shock, and Poison Cursed Enemies": "对被诅咒敌人施加点燃、冻结、感电或中毒的几率+20%",
    "20% chance to Maim Enemies with Main Hand Hits": "主手击中时，有20%几率使敌人瘫痪",
    "30% chance to Freeze Enemies which are Chilled": "对处于冰缓状态的敌人，有30%几率施加冻结",
    "First and Final shots of Barrage sequences fire Projectiles that Return to you": "弹幕序列中的首发与最后一发会发射返回你的投射物",
    "+1% to Critical Strike Multiplier per 10 Maximum Energy Shield on Shield": "盾牌上的最大能量护盾每有10点，暴击伤害倍率+1%",
    "Life Recoup Effects instead occur over 3 seconds": "生命延迟回复效果改为在3秒内完成",
    "Hits have 20% chance to deal 50% more Area Damage": "击中有20%几率使范围伤害额外提高50%",
    "Hits have 30% chance to deal 50% more Area Damage": "击中有30%几率使范围伤害额外提高50%",
    "30% chance to take 50% less Area Damage from Hits": "有30%几率使你受到的击中范围伤害额外降低50%",
    "Hits Stun as though dealing 50% more Melee Fire Damage": "击中造成眩晕时，眩晕判定按额外提高50%的近战火焰伤害计算",
    "Intimidate you inflict causes targets to deal 10% less Damage": "你施加的威吓会使目标造成的伤害额外降低10%",
    "Poison you inflict with Critical Strikes deals 20% more Damage": "你以暴击施加的中毒造成的伤害额外提高20%",
    "Unsealed Spells gain 5% more Damage each time their effects Reoccur": "未封印法术的效果每再次触发一次，其伤害额外提高5%",
    "Tinctures applied to you have 30% less Mana Burn rate": "施加于你的灵药使魔力燃烧速度额外降低30%",
    "25% less Damage taken from other Enemies near your Marked Enemy": "你受到来自被你标记敌人附近其他敌人的伤害额外降低25%",
    "Arcane Surge also grants 10% more Spell Damage to you": "奥术涌浪还会使你获得的法术伤害额外提高10%",
    "Arcane Surge also grants 20% more Spell Damage to you": "奥术涌浪还会使你获得的法术伤害额外提高20%",
    "Deal 10% more Chaos Damage to enemies which have Energy Shield": "对拥有能量护盾的敌人造成的混沌伤害额外提高10%",
    "Deal up to 15% more Melee Damage to Enemies, based on proximity": "根据与敌人的距离，近战伤害最多额外提高15%",
    "Gain Convergence when you Hit a Unique Enemy, no more than once every 8 seconds": "击中传奇敌人时获得汇聚；每8秒最多触发一次",
    "Ignites from Stunning Melee Hits deal 20% more Damage": "近战击中造成眩晕时，点燃伤害额外提高20%",
    "Skills used by Totems deal 10% more Damage per maximum number of Summoned Totems": "召唤图腾数量上限每有一个，图腾使用的技能伤害额外提高10%",
    "Vaal Skills deal 1% more Damage per Soul Required": "瓦尔技能每需要一个灵魂，造成的伤害额外提高1%",
    "Vaal Skills require 30% less Souls per Use": "每次使用所需的灵魂数量额外降低30%",
    "Take 40% less Damage from Hits": "受到击中造成的伤害额外降低40%",
    "50% less Damage Taken from Damage over Time while you have Unbroken Ward": "拥有未破损灵护时，所受持续伤害额外降低50%",
    "10% more Maximum Physical Attack Damage": "攻击造成的最大物理伤害额外提高10%",
    "Brands have 100% more Activation Frequency if 75% of Attached Duration expired": "若烙印附着持续时间已过去75%，激活频率额外提高100%",
    "Herald Skills have 2% more Buff Effect for every 1% of Maximum Mana they Reserve": "捷光技能每保留最大魔力的1%，其增益效果额外提高2%",
    "25% increased Maximum Life if you have Equipped Gloves with no Socketed Gems": "若你装备的手套没有镶嵌宝石，最大生命提高25%",
    "30% increased Movement Speed if you have Equipped Boots with no Socketed Gems": "若你装备的鞋子没有镶嵌宝石，移动速度提高30%",
    "Defences from Equipped Body Armour are doubled if it has no Socketed Gems": "若你装备的胸甲没有镶嵌宝石，来自该胸甲的防御属性翻倍",
    "Minions affected by Affliction have Onslaught": "受到苦痛影响的召唤物获得猛攻",
    "Recover 1% of Mana on Kill while you have a Tincture active": "灵药激活期间，击杀时回复最大魔力的1%",
    "Gain 1 Fanatic Charge every second if you've Attacked in the past second": "若你在过去一秒内攻击过，每秒获得1层狂热球",
    "10% chance to Aggravate Bleeding on targets you Hit with Attacks": "你使用攻击击中的目标有10%几率使其流血加剧",
    "25% chance to Aggravate Bleeding on targets you Hit with Attacks": "你使用攻击击中的目标有25%几率使其流血加剧",
    "15% chance to Intimidate Enemies for 4 seconds on Hit with Attacks": "使用攻击击中敌人时，有15%几率威吓敌人，持续4秒",
    "Drop Brine Ground while moving, lasting 4 seconds": "移动时留下盐水地面，持续4秒",
    "Targets affected by Maim you inflict cannot deal Critical Strikes": "受到你施加的瘫痪影响的目标无法造成暴击",
    "20% chance to Maim Enemies on Critical Strike with Attacks": "使用攻击造成暴击时，有20%几率瘫痪敌人",
    "25% chance to Aggravate Bleeding on targets you Critically Strike with Attacks": "你使用攻击造成暴击时，有25%几率使目标流血加剧",
    "50% chance to Aggravate Bleeding on targets you Stun with Attacks Hits": "你使用攻击击晕目标时，有50%几率使其流血加剧",
    "While affected by Glorious Madness, inflict Mania on nearby Enemies every second": "受到荣耀疯狂影响时，每秒对附近敌人施加一层躁狂",
    "30% faster Restoration of Ward per Enemy Hit taken Recently": "近期每受到敌人一次击中，灵护恢复速度加快30%",
    "Freezes you inflict spread to other Enemies within 1.2 metres": "你施加的冻结会蔓延至1.2米内的其他敌人",
    "Ignites you inflict spread to other Enemies within a Radius of 1.5 metres": "你施加的点燃会蔓延至半径1.5米内的其他敌人",
    "Shocks you inflict spread to other Enemies within 1 metre": "你施加的感电会蔓延至1米内的其他敌人",
    "Rare and Unique Enemies within 120 metres have Minimap Icons": "120米内的稀有和传奇敌人会显示在小地图上",
}

# Longer single-row source effects combine multiple clauses. Keep these as
# complete reviewed sentences instead of allowing the lexical fallback to
# reorder conditions, subjects, and numeric scopes.
REVIEWED_LONG_LINE_OVERRIDES = {
    "Projectile Attack Hits deal up to 30% more Damage to targets at the start of their movement, dealing less Damage to targets as the projectile travels farther": "投射物攻击在飞行起点命中目标时，伤害最多额外提高30%；飞行距离越远，对目标造成的伤害额外降低",
    "Deal 1% more Damage with Hits and Ailments to Rare and Unique Enemies for every 2 seconds they've ever been in your Presence, up to a maximum of 50%": "稀有或传奇敌人在你附近每累计停留2秒，你对其造成的击中与异常状态伤害额外提高1%，最多额外提高50%",
    "Gain 10% of Physical Damage as Extra Lightning Damage for each of your Hallowing Flames that have been removed by an allied hit recently, up to 80%": "近期每有一道你的圣化烈焰被友军击中移除，你就获得相当于物理伤害10%的额外闪电伤害，最多80%",
    "Deal 1% more Damage with Hits and Ailments to Rare and Unique Enemies for each second they've ever been in your Presence, up to a maximum of 100%": "稀有或传奇敌人在你附近每累计停留一秒，你对其造成的击中与异常状态伤害额外提高1%，最多额外提高100%",
    "Spells you cast yourself gain Added Physical Damage equal to 75% of Life Cost, if Life Cost is not higher than the maximum you could spend": "你亲自施放的法术获得相当于生命消耗75%的附加物理伤害；仅当生命消耗不超过你可支付的上限时生效",
    "Tincture Effects Linger on you for 0.5 seconds per Mana Burn on you when the Tincture was deactivated, up to a maximum of 6 seconds": "灵药停用时，你身上每层魔力燃烧会使灵药效果额外持续0.5秒，最多6秒",
    "Cursed Enemies you or your Minions Kill have a 50% chance to Explode, dealing a quarter of their maximum Life as Chaos Damage": "被诅咒的敌人被你或你的召唤物击杀时，有50%几率爆炸，造成相当于其最大生命四分之一的混沌伤害",
    "25% chance to Trigger Level 20 Summon Elemental Relic when you or a nearby Ally Kill an Enemy, or Hit a Rare or Unique Enemy": "你或附近友军击杀敌人，或击中稀有或传奇敌人时，有25%几率触发20级召唤元素遗物",
    "Enemies permanently take 1% increased Damage for each second they've ever been Chilled by you, up to a maximum of 10%": "敌人每累计被你冰缓一秒，所受伤害永久提高1%，最多提高10%",
    "Skills gain Added Chaos Damage equal to 25% of Life Cost, if Life Cost is not higher than the maximum you could spend": "技能获得相当于生命消耗25%的附加混沌伤害；仅当生命消耗不超过你可支付的上限时生效",
    "Enemies permanently take 5% increased Damage for each second they've ever been Frozen by you, up to a maximum of 50%": "敌人每累计被你冻结一秒，所受伤害永久提高5%，最多提高50%",
    "You gain Added Lightning Damage instead of Added Damage of other types if Intelligence exceeds both other Attributes": "若你的智慧高于另外两项属性，你获得附加闪电伤害，替代其他类型的附加伤害",
    "Herald Skills and Minions from Herald Skills deal 1% more Damage for every 1% of Maximum Life those Skills Reserve": "捷光技能及其召唤物每保留1%最大生命，造成的伤害额外提高1%",
    "For each nearby corpse, you and nearby Allies Regenerate 0.2% of Energy Shield per second, up to 2.0% per second": "你和附近友军每有一具附近尸体，每秒回复最大能量护盾的0.2%，最多每秒2.0%",
    "+15% chance to Suppress Spell Damage if Equipped Helmet, Body Armour, Gloves, and Boots all have Evasion Rating": "若你装备的头盔、胸甲、手套和鞋子均有闪避值，法术压制几率+15%",
    "Enemies Killed with Attack Hits have a 15% chance to Explode, dealing a tenth of their Life as Physical Damage": "被攻击击中击杀的敌人有15%几率爆炸，造成相当于其生命值十分之一的物理伤害",
    "Enemies you or your Totems Kill have 10% chance to Explode, dealing 250% of their maximum Life as Fire Damage": "被你或你的图腾击杀的敌人有10%几率爆炸，造成相当于其最大生命250%的火焰伤害",
    "Enemies Killed near your Banner have 20% chance to Explode, dealing a tenth of their Life as Physical Damage": "在你的旗帜附近被击杀的敌人有20%几率爆炸，造成相当于其生命值十分之一的物理伤害",
    "You gain Added Cold Damage instead of Added Damage of other types if Dexterity exceeds both other Attributes": "若你的敏捷高于另外两项属性，你获得附加冰霜伤害，替代其他类型的附加伤害",
    "+1% to all maximum Elemental Resistances if Equipped Helmet, Body Armour, Gloves, and Boots all have Armour": "若你装备的头盔、胸甲、手套和鞋子均有护甲，所有元素抗性上限+1%",
    "10% more Attack Damage for each Non-Instant Spell you've Cast in the past 8 seconds, up to a maximum of 30%": "你在过去8秒内每施放一个非瞬时法术，攻击伤害额外提高10%，最多额外提高30%",
    "20% increased Maximum Energy Shield if both Equipped Left and Right Rings have an Explicit Evasion Modifier": "若你装备的左戒指和右戒指均带有闪避词缀，最大能量护盾提高20%",
    "Enemies Killed with Wand Hits have a 10% chance to Explode, dealing a quarter of their Life as Chaos Damage": "被魔杖击中击杀的敌人有10%几率爆炸，造成相当于其生命值四分之一的混沌伤害",
    "You and Allies near your Banner Regenerate 0.1% of Life per second for each Valour consumed for that Banner": "你和旗帜附近的友军每消耗一点该旗帜的英勇值，每秒回复最大生命的0.1%",
    "Burning Enemies you kill have a 3% chance to Explode, dealing a tenth of their maximum Life as Fire Damage": "被你击杀的燃烧敌人有3%几率爆炸，造成相当于其最大生命十分之一的火焰伤害",
    "30% more Damage with Hits and Ailments against Enemies that are on Low Life while you are wielding an Axe": "你持有斧类武器时，对低血敌人造成的击中与异常状态伤害额外提高30%",
    "5% chance to deal Double Damage if you've dealt a Critical Strike with a Two Handed Melee Weapon Recently": "若你近期使用双手近战武器造成过暴击，有5%几率造成双倍伤害",
    "Minions Explode when reduced to Low Life, dealing 33% of their Life as Fire Damage to surrounding Enemies": "召唤物降至低血状态时爆炸，对周围敌人造成相当于其生命值33%的火焰伤害",
    "10% increased Melee Damage for each second you've been affected by a Warcry Buff, up to a maximum of 60%": "你每受到战吼增益效果影响一秒，近战伤害提高10%，最多提高60%",
    "50% chance to inflict Withered for two seconds on Hit if there are 5 or fewer Withered Debuffs on Enemy": "击中敌人时，有50%几率对其施加枯萎，持续两秒；若敌人身上的枯萎减益不超过5层",
    "Enemies you Kill have a 10% chance to Explode, dealing a quarter of their maximum Life as Chaos Damage": "被你击杀的敌人有10%几率爆炸，造成相当于其最大生命四分之一的混沌伤害",
    "25% chance that if you would gain Endurance Charges, you instead gain up to maximum Endurance Charges": "你获得耐力球时有25%几率改为直接获得至耐力球上限所需的数量",
    "Enemies Taunted by your Warcries Explode on death, dealing 8% of their maximum Life as Chaos Damage": "被你的战吼嘲讽的敌人死亡时会爆炸，造成相当于其最大生命8%的混沌伤害",
    "Arrows gain Damage as they travel farther, dealing up to 50% increased Damage with Hits to targets": "箭矢飞行距离越远，击中伤害越高；对目标造成的击中伤害最多提高50%",
    "Arrows gain Critical Strike Chance as they travel farther, up to 100% increased Critical Strike Chance": "箭矢飞行距离越远，暴击几率提高越多，最多提高100%",
    "15% increased Area of Effect if you've Stunned an Enemy with a Two Handed Melee Weapon Recently": "若你近期使用双手近战武器击晕过敌人，效果范围提高15%",
    "Modifiers to Fire Resistance also apply to Cold and Lightning Resistances at 50% of their Value": "火焰抗性词缀也会按其数值的50%作用于冰霜抗性和闪电抗性",
    "+15% to Critical Strike Multiplier if you dealt a Critical Strike with a Herald Skill Recently": "若你近期使用捷光技能造成过暴击，暴击伤害倍率+15%",
    "10% chance to create Consecrated Ground when you Hit a Rare or Unique Enemy, lasting 8 seconds": "击中稀有或传奇敌人时，有10%几率生成奉献地面，持续8秒",
    "10% chance when you use a Retaliation Skill for a different Retaliation Skill to become Usable": "使用反击技能时，有10%几率使另一项反击技能变为可用",
    "25% chance when you use a Retaliation Skill for a different Retaliation Skill to become Usable": "使用反击技能时，有25%几率使另一项反击技能变为可用",
    "6% increased Energy Shield Recharge Rate for each different type of Mastery you have Allocated": "每分配一种不同类型的专精，能量护盾充能速度提高6%",
    "Four seconds after each Hit you take, lose Life equal to 40% of the Damage taken from that Hit": "每次受到击中后四秒，失去相当于该次击中伤害40%的生命",
    "When you kill a Poisoned Enemy during any Flask Effect, Enemies within 1.5 metres are Poisoned": "任意药剂效果期间，你击杀中毒敌人时，1.5米范围内的敌人会中毒",
    "1% increased Critical Strike Chance per point of Strength or Intelligence, whichever is lower": "力量或智慧中较低者每有一点，暴击几率提高1%",
    "25% of Damage taken Recouped as Life if Leech was removed by Filling Unreserved Life Recently": "若近期因未保留生命回满而移除偷取效果，所受伤害的25%会延迟回复为生命",
    "4% increased Attack and Cast Speed for each corpse Consumed Recently, up to a maximum of 200%": "近期每消耗一具尸体，攻击与施法速度提高4%，最多提高200%",
    "40% increased Energy Shield Recharge Rate if Equipped Amulet has an Explicit Evasion Modifier": "若你装备的项链带有闪避词缀，能量护盾充能速度提高40%",
    "If you've Cast a Spell Recently, you and nearby Allies have +10% Chance to Block Spell Damage": "若你近期施放过法术，你和附近友军的法术伤害格挡几率+10%",
    "If you've Cast a Spell Recently, you and nearby Allies have +25% Chance to Block Spell Damage": "若你近期施放过法术，你和附近友军的法术伤害格挡几率+25%",
    "Your Hits ignore Enemy Monster Lightning Resistances if all Equipped Rings are Synaptic Rings": "若你装备的戒指均为突触戒指，你的击中无视敌方怪物的闪电抗性",
    "20% increased Armour for each different Retaliation Skill you've used in the past 10 seconds": "你在过去10秒内每使用一种不同的反击技能，护甲提高20%",
    "Gain 25% increased Armour per 5 Power for 8 seconds when you Warcry, up to a maximum of 100%": "使用战吼时，每5点战吼威力使护甲提高25%，持续8秒，最多提高100%",
    "If you've Consumed a corpse Recently, you and your Minions have 30% increased Area of Effect": "若你近期消耗过尸体，你和你的召唤物的效果范围提高30%",
    "If your Mercenary's Life is lower than your own, 40% of Damage they take is Recouped as Life": "若佣兵的生命低于你，佣兵承受伤害的40%会延迟回复为生命",
    "Projectiles deal 20% increased Damage with Hits and Ailments for each time they have Chained": "投射物每连锁一次，击中与异常状态伤害提高20%",
    "Take no Extra Damage from Critical Strikes if you have Equipped Gloves with no Socketed Gems": "若你装备的手套没有镶嵌宝石，你不会受到暴击造成的额外伤害",
    "10% chance on Hitting an Enemy for all Impales on that Enemy to last for an additional Hit": "击中敌人时，有10%几率使该敌人身上的所有穿刺额外持续一次击中",
    "30% increased Effect of Impales you inflict with Two Handed Weapons on Non-Impaled Enemies": "你使用双手武器对尚未被穿刺的敌人施加的穿刺效果提高30%",
    "If you've Attacked Recently, you and nearby Allies have +10% Chance to Block Attack Damage": "若你近期攻击过，你和附近友军的攻击伤害格挡几率+10%",
    "If you've Attacked Recently, you and nearby Allies have +25% Chance to Block Attack Damage": "若你近期攻击过，你和附近友军的攻击伤害格挡几率+25%",
    "When you take a Savage Hit, lose Baryatic Tension to recover that much Life, up to maximum": "受到凶猛击中时，消耗巴雅提克张力以回复等量生命，最多回复至上限",
    "100% increased Evasion Rating if Energy Shield Recharge has started in the past 2 seconds": "若能量护盾充能在过去2秒内开始，闪避值提高100%",
    "Brands Attach to a new Enemy each time they Activate, no more than once every 0.3 seconds": "烙印每次启动都会附着到一名新敌人身上，每0.3秒最多触发一次",
    "Elusive also grants +40% to Critical Strike Multiplier for Skills Supported by Nightblade": "灵巧还使夜刃辅助的技能获得暴击伤害倍率+40%",
    "Gain 4 Mana per Enemy Hit with Attacks if you've used a Mana Flask in the past 10 seconds": "若你在过去10秒内使用过魔力药剂，每次攻击击中敌人时获得4点魔力",
    "Increases and reductions to Maximum Mana also apply to Shock Effect at 30% of their value": "最大魔力的提高与降低也会按其数值的30%作用于感电效果",
    "Inflict Fire, Cold and Lightning Exposure on Enemies when you Suppress their Spell Damage": "压制敌人的法术伤害时，对其施加火焰、冰霜和闪电曝露",
    "Modifiers to Maximum Fire Resistance also apply to Maximum Cold and Lightning Resistances": "最大火焰抗性词缀也会作用于最大冰霜抗性和最大闪电抗性",
    "Recover 1% of Energy Shield on Kill for each different type of Mastery you have Allocated": "每分配一种不同类型的专精，击杀时回复1%能量护盾",
    "Recover 5% of Energy Shield over 1 second when you take Physical Damage from an Enemy Hit": "受到敌人击中的物理伤害时，在1秒内回复5%能量护盾",
    "+2 to Level of all Lightning Skill Gems if at least 4 Foulborn Unique Items are Equipped": "若装备至少4件污秽传奇物品，所有闪电技能宝石等级+2",
    "Every 4 seconds, Recover 1 Life for every 0.1 Life Recovery per second from Regeneration": "每4秒根据生命回复速度回复生命：每秒回复速度每达到0.1，回复1点生命",
    "Skills used by Totems have 10% more Area of Effect per maximum number of Summoned Totems": "图腾使用的技能效果范围按召唤图腾数量上限每个额外提高10%",
    "25% increased Maximum total Life, Mana and Energy Shield Recovery per second from Leech": "偷取提供的每秒最大生命、魔力和能量护盾总回复提高25%",
    "Every 4 seconds, Regenerate Life equal to 1% of Armour and Evasion Rating over 1 second": "每4秒在1秒内回复相当于护甲值与闪避值总和1%的生命",
    "Maim you inflict causes Hits against the target to have 20% more Critical Strike Chance": "你施加的瘫痪会使对目标的击中暴击几率额外提高20%",
    "Regenerate 2% of Life per Second for each Trap Triggered Recently, up to 10% per second": "近期每触发一颗陷阱，每秒回复最大生命的2%，最多每秒10%",
    "Regenerate 2% of Life per second for each Mine Detonated Recently, up to 10% per second": "近期每引爆一颗地雷，每秒回复最大生命的2%，最多每秒10%",
    "Skills used by Mines have 15% increased Area of Effect if you Detonated a Mine Recently": "若你近期引爆过地雷，地雷使用的技能效果范围提高15%",
    "Tinctures applied to you have 15% increased Effect if you've used a Life Flask Recently": "若你近期使用过生命药剂，施加于你的灵药效果提高15%",
    "Your Hits ignore Enemy Monster Cold Resistances if all Equipped Rings are Cryonic Rings": "若你装备的戒指均为冷凝戒指，你的击中无视敌方怪物的冰霜抗性",
    "+50% to all Elemental Resistances if you have an Equipped Helmet with no Socketed Gems": "若你装备的头盔没有镶嵌宝石，所有元素抗性+50%",
    "+6% to Physical Damage over Time Multiplier if you've dealt a Critical Strike Recently": "若你近期造成过暴击，物理持续伤害倍率+6%",
    "10% increased Area of Effect per second you've been stationary, up to a maximum of 50%": "你每静止一秒，效果范围提高10%，最多提高50%",
    "20% chance for used Retaliation Skills to remain Usable and not consume a Cooldown Use": "已使用的反击技能有20%几率仍可使用，且不消耗一次冷却使用次数",
    "3% chance for Hits to deal 300% of Physical Damage as Extra Damage of a random Element": "击中有3%几率将物理伤害的300%转为随机元素的额外伤害",
    "50% chance for used Retaliation Skills to remain Usable and not consume a Cooldown Use": "已使用的反击技能有50%几率仍可使用，且不消耗一次冷却使用次数",
    "Attacks with Two Handed Melee Weapons deal 20% increased Damage with Hits and Ailments": "双手近战武器攻击造成的击中与异常状态伤害提高20%",
    "Attacks with Two Handed Melee Weapons deal 25% increased Damage with Hits and Ailments": "双手近战武器攻击造成的击中与异常状态伤害提高25%",
    "Brand Recall has 4% increased Cooldown Recovery Rate per Brand, up to a maximum of 40%": "每有一个烙印，烙印召回的冷却回复速度提高4%，最多提高40%",
    "25% increased Maximum total Life Recovery per second from Leech while at maximum Rage": "怒火达到上限时，偷取提供的每秒最大生命总回复提高25%",
    "Elemental Resistances are capped by your highest Maximum Elemental Resistance instead": "元素抗性上限改为你最高的元素抗性上限",
    "Every 4 seconds, Regenerate Energy Shield equal to 1% of Evasion Rating over 1 second": "每4秒在1秒内回复相当于闪避值1%的能量护盾",
    "Impale Damage dealt to Enemies Impaled by you ignores Enemy Physical Damage Reduction": "你施加穿刺后造成的穿刺伤害无视敌人的物理伤害减免",
    "When you leave your Banner's Area, recover 30% of the Valour consumed for that Banner": "离开旗帜范围时，回复该旗帜消耗英勇值的30%",
    "12% chance to deal Double Damage with Attacks if Attack Time is longer than 1 second": "攻击时间超过1秒时，攻击有12%几率造成双倍伤害",
    "12% increased maximum Life and Mana if your equipped Staff has a Red and Blue Socket": "若你装备的长杖有红色和蓝色插槽，最大生命和最大魔力提高12%",
    "8% more Damage with Hits and Ailments against Enemies affected by at least 5 Poisons": "对至少受到5层中毒影响的敌人，击中与异常状态伤害额外提高8%",
    "Consecrated Ground you create grants 30% increased Accuracy Rating to you and Allies": "你创造的奉献地面使你和友军的命中值提高30%",
    "Converts all Evasion Rating to Armour. Dexterity provides no bonus to Evasion Rating": "将全部闪避值转化为护甲；敏捷不再提供闪避值加成",
    "If Amethyst Flask Charges are consumed, 37% of Physical Damage as Extra Chaos Damage": "消耗紫晶药剂充能时，获得相当于物理伤害37%的额外混沌伤害",
    "Poisons you inflict during any Flask Effect have 20% chance to deal 100% more Damage": "任意药剂效果期间，你施加的中毒有20%几率使中毒伤害额外提高100%",
    "Remove a random Ailment on you when you consume at least 10 Valour to place a Banner": "消耗至少10点英勇值放置旗帜时，移除你身上一种随机异常状态",
    "Skills used by Mines deal 30% increased Area Damage if you Detonated a Mine Recently": "若你近期引爆过地雷，地雷使用的技能造成的范围伤害提高30%",
    "Unholy Might you grant also causes target's Damage to Penetrate 10% Chaos Resistance": "你施加的邪恶之力还会使目标造成的伤害穿透10%混沌抗性",
    "+1% to all maximum Elemental Resistances if you have Killed a Cursed Enemy Recently": "若你近期击杀过被诅咒的敌人，所有元素抗性上限+1%",
    "+2 to Level of all Cold Skill Gems if at least 4 Foulborn Unique Items are Equipped": "若装备至少4件污秽传奇物品，所有冰霜技能宝石等级+2",
    "+20% to Critical Strike Multiplier if you've been Channelling for at least 1 second": "引导至少1秒后，暴击伤害倍率+20%",
    "Gain 10% increased Attack Speed for 20 seconds when you Kill a Rare or Unique Enemy": "击杀稀有或传奇敌人时，攻击速度提高10%，持续20秒",
    "Hits have 15% chance to treat Enemy Monster Elemental Resistance values as inverted": "击中有15%几率将敌方怪物的元素抗性数值视为反转",
    "Impales you inflict gain 50% increased Effect once 1 second of Duration has expired": "你施加的穿刺持续1秒后，效果提高50%",
    "Projectiles deal 20% increased Damage with Hits and Ailments for each Enemy Pierced": "投射物每穿透一名敌人，击中与异常状态伤害提高20%",
    "Regenerate 2% of Life per Second if you've used a Life Flask in the past 10 seconds": "若你在过去10秒内使用过生命药剂，每秒回复最大生命的2%",
    "Strength's Damage bonus applies to Projectile Attack Damage as well as Melee Damage": "力量提供的伤害加成同时作用于投射物攻击伤害和近战伤害",
    "+60% to Critical Strike Multiplier if you haven't dealt a Critical Strike Recently": "若你近期未造成暴击，暴击伤害倍率+60%",
    "20% increased Buff Effect of your Links for which 50% of Link Duration has Expired": "连接持续时间已过去50%的连接技能增益效果提高20%",
    "40% reduced Effect of Non-Damaging Ailments on you during Effect of any Life Flask": "任意生命药剂效果期间，你身上的非伤害性异常状态效果降低40%",
    "5% increased Cooldown Recovery Rate for throwing Traps per Mine Detonated Recently": "近期每引爆一颗地雷，投掷陷阱的冷却回复速度提高5%",
    "Inherent Attack Speed bonus from Dual Wielding is doubled while wielding two Claws": "持有两把爪类武器时，双持提供的固有攻击速度加成翻倍",
    "Link Skills have 20% increased Buff Effect if you have Linked to a target Recently": "若你近期连接过目标，连接技能的增益效果提高20%",
    "Nearby Enemies have Lightning Exposure while you are affected by Herald of Thunder": "受到雷电之捷影响时，附近敌人会受到闪电曝露",
    "Non-Cluster, Non-Passage Jewels Socketed in your Passive Skill Tree have no effect": "镶嵌在被动天赋树中的非星团、非通路珠宝不产生效果",
    "Profane Ground you create also affects you and your Allies, granting Chaotic Might": "你创造的亵渎地面也会影响你和友军，并赋予混沌之力",
    "15% increased maximum Life if there are no Life Modifiers on Equipped Body Armour": "若你装备的胸甲没有生命词缀，最大生命提高15%",
    "20% of Damage from Hits is taken from your Sentinel of Radiance's Life before you": "击中伤害由你承受前，会先从光辉哨兵的生命值中扣除20%",
    "25% more Damage with Hits against Enemies that cannot have Life Leeched from them": "对无法被偷取生命的敌人，击中伤害额外提高25%",
    "6% increased Cast Speed for each different Non-Instant Spell you've Cast Recently": "近期每施放一种不同的非瞬时法术，施法速度提高6%",
    "Damage taken bypasses Unbroken Ward if the Hit deals less Damage than 15% of Ward": "若该次击中造成的伤害低于灵护值的15%，所受伤害会绕过未破损灵护",
    "Gain [SpiritInfusion|Spirit Infusion] every 0.5 seconds while Channelling a Spell": "引导法术时，每0.5秒获得一层灵体灌注",
    "Hallowing Flame you inflict has 1% increased magnitude per 2% Attack Block chance": "你施加的圣化烈焰效果幅度每有2%攻击伤害格挡几率便提高1%",
    "+8% Chance to Block Attack Damage if you've Stunned an Enemy Recently": "若你近期曾击晕敌人，攻击伤害格挡几率+8%",
    "15% increased Area of Effect if you have Stunned an Enemy Recently": "若你近期曾击晕敌人，效果范围提高15%",
    "15% increased Elemental Damage if you've Chilled an Enemy Recently": "若你近期曾使敌人冰缓，元素伤害提高15%",
    "20% increased Elemental Damage if you've Ignited an Enemy Recently": "若你近期曾点燃敌人，元素伤害提高20%",
    "25% increased Elemental Damage if you've Shocked an Enemy Recently": "若你近期曾使敌人感电，元素伤害提高25%",
    "30% increased Damage if you have Shocked an Enemy Recently": "若你近期曾使敌人感电，伤害提高30%",
    "30% increased Damage if you've Shattered an Enemy Recently": "若你近期曾粉碎敌人，伤害提高30%",
    "30% increased Mana Regeneration Rate if you have Frozen an Enemy Recently": "若你近期曾冻结敌人，魔力回复速度提高30%",
    "30% increased Mana Regeneration Rate if you have Shocked an Enemy Recently": "若你近期曾使敌人感电，魔力回复速度提高30%",
    "Regenerate 1% of Energy Shield per second if you've Cursed an Enemy Recently": "若你近期曾诅咒敌人，每秒回复相当于最大能量护盾1%的能量护盾",
    "Regenerate 1% of Life per second if you have Stunned an Enemy Recently": "若你近期曾击晕敌人，每秒回复相当于最大生命1%的生命",
    "Prevent +3% of Suppressed Spell Damage per Bark below maximum": "树皮层数每比上限少一层，额外防止+3%被压制的法术伤害",
    "10% chance to Avoid non-Damaging Ailments on you per Bark below maximum": "树皮层数每比上限少一层，避免自身受到非伤害性异常状态的几率增加10%",
}

CLASS_NAMES = {
    "Scion": "贵族", "Marauder": "野蛮人", "Ranger": "游侠", "Witch": "女巫",
    "Duelist": "决斗者", "Templar": "圣堂武僧", "Shadow": "暗影",
}

MODIFIERS = {"increased": "提高", "reduced": "降低", "more": "额外提高", "less": "额外降低"}
WORD_PATTERN = re.compile(r"[A-Za-z]+(?:['’][A-Za-z]+)?")
NUMBER_PATTERN = re.compile(r"[+-]?\d+(?:\.\d+)?")


def _translate_terms(text: str, unknown: set[str]) -> str:
    # Chinese classifiers belong between a number and a countable noun.
    text = re.sub(r"(?i)\bup to ([0-9]+(?:\.[0-9]+)?) additional\b", r"至多\1个额外", text)
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


STATUS_ZH = {
    "poison": "中毒", "poisoned": "中毒", "ignite": "点燃", "ignited": "点燃",
    "shock": "感电", "shocked": "感电", "freeze": "冻结", "frozen": "冻结",
    "chill": "冰缓", "chilled": "冰缓", "bleed": "流血", "bleeding": "流血",
}

STATUS_ACTION_ZH = {
    "poison": "使敌人中毒", "poisoned": "使敌人中毒",
    "ignite": "点燃敌人", "ignited": "点燃敌人",
    "shock": "使敌人感电", "shocked": "使敌人感电",
    "freeze": "冻结敌人", "frozen": "冻结敌人",
    "chill": "使敌人冰缓", "chilled": "使敌人冰缓",
    "bleed": "使敌人流血", "bleeding": "使敌人流血",
}

CHARGE_TYPE_ZH = {
    "power": "暴击球", "frenzy": "狂怒球", "endurance": "耐力球",
}

CHARGE_GAIN_TRIGGERS_ZH = {
    "on critical strike": "造成暴击时",
    "on critical strike with wands": "使用魔杖造成暴击时",
    "on kill": "击杀敌人时",
    "on kill while holding a shield": "持盾击杀敌人时",
    "on non-critical strike with a claw or dagger": "使用爪或匕首造成非暴击击中时",
    "on non-critical strike": "造成非暴击击中时",
    "when you shock a chilled enemy": "使冰缓敌人感电时",
    "when you stun with melee damage": "以近战伤害造成眩晕时",
    "when your mine is detonated targeting an enemy": "地雷以敌人为目标引爆时",
    "when you hit your marked enemy": "击中你标记的敌人时",
    "on melee critical strike": "造成近战暴击时",
    "when your trap is triggered by an enemy": "陷阱被敌人触发时",
    "when you block attack damage": "格挡攻击伤害时",
    "when you block": "格挡时",
    "when you stun an enemy with a melee hit": "以近战击中使敌人眩晕时",
    "when you block spell damage": "格挡法术伤害时",
    "when you use a mana flask": "使用魔力药剂时",
    "each second while channelling": "引导期间每秒",
    "when you are hit": "被击中时",
    "on kill while dual wielding": "双持时击杀敌人",
    "when you hit a unique enemy": "击中传奇敌人时",
}


def _status_list_zh(source: str) -> str:
    parts = re.split(r"(?i)\s*,\s*|\s+and\s+|\s+or\s+", source.strip())
    normalized = [part.strip().lower() for part in parts if part.strip()]
    if not normalized or any(part not in STATUS_ZH for part in normalized):
        return ""
    return "、".join(STATUS_ZH[part] for part in normalized)


def _charge_choices_zh(source: str) -> str:
    source = re.sub(r"(?i),\s*(and|or)\s+", r" \1 ", source.strip())
    parts = re.split(r"(?i)\s*,\s*|\s+and\s+|\s+or\s+", source)
    normalized = [part.strip().lower() for part in parts if part.strip()]
    if not normalized or any(part not in CHARGE_TYPE_ZH for part in normalized):
        return ""
    translated = [CHARGE_TYPE_ZH[part] for part in normalized]
    if re.search(r"(?i)\s+or\s+", source):
        return "、".join(translated[:-1]) + "或" + translated[-1]
    if re.search(r"(?i)\s+and\s+", source):
        return "、".join(translated[:-1]) + "与" + translated[-1]
    return "、".join(translated)


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
    match = re.match(r"(?i)^if you've hit an? (.+?) recently$", value)
    if match:
        return "若你近期击中过" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^if you've dealt an? (.+?) recently$", value)
    if match:
        return "若你近期造成过" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^if you've used an? (.+?) recently$", value)
    if match:
        return "若你近期使用过" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^if you've cast an? (.+?) recently$", value)
    if match:
        return "若你近期施放过" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^if you've been stunned while casting recently$", value)
    if match:
        return "若你近期施法时被眩晕"
    match = re.match(r"(?i)^if you've (.+?) recently$", value)
    if match:
        action = _translate_terms(match.group(1), unknown)
        action = action[1:] if action.startswith("已") else action
        return "若你近期已" + action
    match = re.match(r"(?i)^if you've consumed a corpse recently$", value)
    if match:
        return "若你近期消耗过尸体"
    match = re.match(r"(?i)^if you have at least ([0-9]+(?:\.[0-9]+)?) Life Masteries allocated$", value)
    if match:
        return "若你至少已分配" + match.group(1) + "个生命专精"
    match = re.match(r"(?i)^if you have at least (.+)$", value)
    if match:
        return "若你至少拥有" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^if you have not (.+?) recently$", value)
    if match:
        action = _translate_terms(match.group(1), unknown)
        action = action[1:] if action.startswith("已") else action
        return "若你近期未" + action
    match = re.match(r"(?i)^if you have an? equipped (.+?) with no socketed gems$", value)
    if match:
        return "若你装备的" + _translate_terms(match.group(1), unknown) + "没有镶嵌宝石"
    match = re.match(r"(?i)^if you are affected by (.+)$", value)
    if match:
        return "若你受到" + _translate_terms(match.group(1), unknown) + "影响"
    match = re.match(r"(?i)^if you've (.+)$", value)
    if match:
        translated = _translate_terms(match.group(1), unknown)
        if translated.startswith("已"):
            translated = translated[1:]
        return "若你已" + translated
    match = re.match(r"(?i)^if you (.+)$", value)
    if match:
        return "若你" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^if your (.+)$", value)
    if match:
        return "若你的" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^while you have (.+)$", value)
    if match:
        return "当你拥有" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^while you are affected by (.+)$", value)
    if match:
        return "受到" + _translate_terms(match.group(1), unknown) + "影响期间"
    match = re.match(r"(?i)^while you are (.+)$", value)
    if match:
        return "当你处于" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^while wielding (?:a |an )?(.+)$", value)
    if match:
        return "持有" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^while holding (?:a |an )?(.+)$", value)
    if match:
        return "持有" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^when you use (?:a |an )?(.+)$", value)
    if match:
        return "使用" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^when you consume (?:a |an )?(.+)$", value)
    if match:
        return "你消耗" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^when (Stunned|Frozen|Chilled|Ignited|Shocked)$", value)
    if match:
        status = {"stunned": "眩晕", "frozen": "冻结", "chilled": "冰缓", "ignited": "点燃", "shocked": "感电"}[match.group(1).lower()]
        return "受到" + status + "时"
    match = re.match(r"(?i)^when you kill (?:a |an )?(.+)$", value)
    if match:
        return "击杀" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^when your (.+?) is triggered by an enemy$", value)
    if match:
        return "你的" + _translate_terms(match.group(1), unknown) + "被敌人触发时"
    match = re.match(r"(?i)^when you are (.+)$", value)
    if match:
        return "当你处于" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^when on (.+)$", value)
    if match:
        return "处于" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^while on (.+)$", value)
    if match:
        return "处于" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^while at maximum (.+)$", value)
    if match:
        return _translate_terms(match.group(1), unknown) + "达到上限时"
    match = re.match(r"(?i)^while unbound$", value)
    if match:
        return "处于未束缚状态时"
    match = re.match(r"(?i)^while they are on (.+)$", value)
    if match:
        return "它们处于" + _translate_terms(match.group(1), unknown) + "时"
    match = re.match(r"(?i)^while there is at most one (Rare|Unique) or (Rare|Unique) Enemy nearby$", value)
    if match:
        return "附近至多有一名稀有或传奇敌人时"
    match = re.match(r"(?i)^while there are at least (two|three|four|[0-9]+(?:\.[0-9]+)?) (Rare|Unique) or (Rare|Unique) Enemies nearby$", value)
    if match:
        amount, _first, _second = match.groups()
        amount_zh = {"two": "两", "three": "三", "four": "四"}.get(amount.lower(), amount)
        return "附近至少有" + amount_zh + "名稀有或传奇敌人时"
    match = re.match(r"(?i)^during Effect of any (.+)$", value)
    if match:
        return "任意" + _translate_terms(match.group(1), unknown) + "效果期间"
    match = re.match(r"(?i)^while (moving|stationary)$", value)
    if match:
        return ("移动期间" if match.group(1).lower() == "moving" else "静止期间")
    match = re.match(r"(?i)^while affected by no (.+)$", value)
    if match:
        return "未受到任何" + _translate_terms(match.group(1), unknown) + "影响时"
    match = re.match(r"(?i)^while affected by (.+)$", value)
    if match:
        return "受到" + _translate_terms(match.group(1), unknown) + "影响时"
    match = re.match(r"(?i)^if equipped (.+)$", value)
    if match:
        return "若已装备" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^with at least one nearby corpse$", value)
    if match:
        return "附近至少有一具尸体时"
    if value.lower() == "on you":
        return "在你身上"
    match = re.match(r"(?i)^on hit with (.+)$", value)
    if match:
        scope = match.group(1)
        if scope.lower() == "attacks":
            return "使用攻击击中时"
        if scope.lower() == "spells":
            return "使用法术击中时"
        return "以" + _translate_terms(scope, unknown) + "击中时"
    match = re.match(r"(?i)^against enemies affected by (.+)$", value)
    if match:
        return "对受到" + _translate_terms(match.group(1), unknown) + "影响的敌人"
    match = re.match(r"(?i)^against enemies with (.+)$", value)
    if match:
        return "对受到" + _translate_terms(match.group(1), unknown) + "影响的敌人"
    match = re.match(r"(?i)^against enemies that are (not )?on low life$", value)
    if match:
        return "对" + ("不处于" if match.group(1) else "处于") + "低血状态的敌人"
    match = re.match(r"(?i)^against enemies which have (.+)$", value)
    if match:
        return "对拥有" + _translate_terms(match.group(1), unknown) + "的敌人"
    match = re.match(r"(?i)^at close range$", value)
    if match:
        return "处于近距离时"
    match = re.match(r"(?i)^for each different type of (.+?) you have allocated$", value)
    if match:
        return "你每分配一种不同类型的" + _translate_terms(match.group(1), unknown)
    match = re.match(r"(?i)^for every ([0-9]+(?:\.[0-9]+)?)% of maximum mana they reserve$", value)
    if match:
        return "其每保留最大魔力的" + match.group(1) + "%"
    match = re.match(r"(?i)^per (Frenzy|Endurance|Power) Charge$", value)
    if match:
        charge = {"frenzy": "狂怒球", "endurance": "耐力球", "power": "暴击球"}[match.group(1).lower()]
        return "每个" + charge
    match = re.match(r"(?i)^per (Frenzy|Endurance|Power) Charge, up to a maximum of ([0-9]+(?:\.[0-9]+)?)%$", value)
    if match:
        charge = {"frenzy": "狂怒球", "endurance": "耐力球", "power": "暴击球"}[match.group(1).lower()]
        return f"每个{charge}，最多达到{match.group(2)}%"
    match = re.match(r"(?i)^per maximum (Frenzy|Endurance|Power) Charge$", value)
    if match:
        charge = {"frenzy": "狂怒球", "endurance": "耐力球", "power": "暴击球"}[match.group(1).lower()]
        return "每增加一个" + charge + "上限"
    match = re.match(r"(?i)^per (Endurance, Frenzy or Power|Power, Frenzy or Endurance) Charge$", value)
    if match:
        return "每个" + _charge_choices_zh(match.group(1))
    match = re.match(r"(?i)^per Summoned Totem$", value)
    if match:
        return "每个召唤图腾"
    match = re.match(r"(?i)^per maximum number of Summoned Totems$", value)
    if match:
        return "按召唤图腾数量上限计算"
    match = re.match(r"(?i)^per Fortification above ([0-9]+(?:\.[0-9]+)?)$", value)
    if match:
        return "护体值超过" + match.group(1) + "点后的每层护体"
    match = re.match(r"(?i)^per Gale Force$", value)
    if match:
        return "每层疾风力量"
    match = re.match(r"(?i)^during any flask effect$", value)
    if match:
        return "任意药剂效果期间"
    match = re.match(r"(?i)^no more than once each second$", value)
    if match:
        return "每秒最多触发一次"
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
        " for ", " from ", " on you", " on kill", " on hit", " after ", " before ", " during ", " at close range",
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


def _modifier_left(prefix: str, subject: str, unknown: set[str]) -> str:
    # English passive text often says "Skills have X% increased Y". Render
    # that ownership relation as "技能的 Y" in Chinese.
    match = re.match(r"(?is)^(.*?)\b(?:have|has)\s+$", prefix)
    if match:
        owner = _translate_terms(match.group(1), unknown).rstrip()
        return _compact_zh(owner + "的" + _translate_terms(subject, unknown))
    normalized = subject.strip()
    if normalized.lower() == "damage taken":
        return "所受伤害"
    match = re.match(r"(?i)^(.+?) Damage Taken$", normalized)
    if match:
        return "所受" + _translate_terms(match.group(1), unknown) + "伤害"
    match = re.match(r"(?i)^Chance to Evade (.+)$", normalized)
    if match:
        return "对" + _translate_terms(match.group(1), unknown) + "的闪避几率"
    match = re.match(r"(?i)^Damage with Triggered Spells$", normalized)
    if match:
        return "触发法术造成的伤害"
    if normalized.lower() == "cost of link skills":
        return "连接技能消耗"
    match = re.match(r"(?i)^(.+?) Duration with (Two Handed Weapons?)$", normalized)
    if match:
        return "持有" + _translate_terms(match.group(2), unknown) + "时，" + _translate_terms(match.group(1) + " Duration", unknown)
    return _translate_terms(prefix + subject, unknown)


def translate_name(source: str, unknown: set[str]) -> str:
    if source in NAME_OVERRIDES:
        return NAME_OVERRIDES[source]
    return _translate_terms(source, unknown).strip()


def translate_effect(source: str, unknown: set[str]) -> str:
    # Preserve complete source entries, including embedded line breaks, as the
    # unit to which support is assigned. These display transforms do not split
    # or feed Chinese strings back into the source parser.
    if source in MULTILINE_OVERRIDES:
        return MULTILINE_OVERRIDES[source]
    if source in REVIEWED_LONG_LINE_OVERRIDES:
        return REVIEWED_LONG_LINE_OVERRIDES[source]
    if source in SINGLE_LINE_OVERRIDES:
        return SINGLE_LINE_OVERRIDES[source]
    if "\n" in source or "\r" in source:
        return "\n".join(translate_effect(part, unknown) for part in source.splitlines())

    # Recoup is a delayed recovery effect, not an instantaneous restoration.
    recoup = re.match(r"(?i)^([0-9]+(?:\.[0-9]+)?)% of (Physical )?Damage taken Recouped as (Life|Mana)(?: if (.+))?$", source)
    if recoup:
        amount, damage_type, resource, condition = recoup.groups()
        damage_zh = "物理伤害" if damage_type else "伤害"
        resource_zh = "生命" if resource.lower() == "life" else "魔力"
        result = f"所受{damage_zh}的{amount}%会延迟回复为{resource_zh}"
        if condition:
            result += "（" + _translate_condition("if " + condition, unknown) + "）"
        return result
    recoup_grant = re.match(r"(?i)^Arcane Surge also grants ([0-9]+(?:\.[0-9]+)?)% of Damage taken Recouped as (Life|Mana) to you$", source)
    if recoup_grant:
        amount, resource = recoup_grant.groups()
        resource_zh = "生命" if resource.lower() == "life" else "魔力"
        return f"奥术浪涌还会使你所受伤害的{amount}%延迟回复为{resource_zh}"

    # “over N seconds” in recovery stats means recovery is spread through
    # that interval; it is not a threshold comparison (“超过 N 秒”).
    recovery_over = re.match(
        r"(?i)^(Recover|Regenerate) ([0-9]+(?:\.[0-9]+)?)(%?)\s+(?:of\s+)?(Life|Mana|Energy Shield) over ([0-9]+(?:\.[0-9]+)?) seconds?(.*)$",
        source,
    )
    if recovery_over:
        _verb, amount, percent, resource, duration, suffix = recovery_over.groups()
        resource_zh = {"life": "生命", "mana": "魔力", "energy shield": "能量护盾"}[resource.lower()]
        restored = f"相当于最大{resource_zh}{amount}%的{resource_zh}" if percent else f"{amount}{resource_zh}"
        result = f"在{duration}秒内回复{restored}"
        if suffix.strip():
            _, condition = _split_condition(suffix)
            if condition:
                result += "（" + _translate_condition(condition, unknown) + "）"
        return result

    fired_projectiles = re.match(
        r"(?i)^(Attack Skills|Attacks|Bow Attacks|Wand Attacks|Skills) fire (an?|[0-9]+) additional (Projectile|Projectiles|Arrow|Arrows)(.*)$",
        source,
    )
    if fired_projectiles:
        owner, count, projectile, suffix = fired_projectiles.groups()
        owner_zh = {
            "attack skills": "攻击技能", "attacks": "攻击", "bow attacks": "弓类攻击",
            "wand attacks": "魔杖攻击", "skills": "技能",
        }[owner.lower()]
        count_zh = "一" if count.lower() in ["a", "an"] else count
        unit = "支" if projectile.lower().startswith("arrow") else "个"
        noun = "箭矢" if projectile.lower().startswith("arrow") else "投射物"
        result = f"{owner_zh}额外发射{count_zh}{unit}{noun}"
        if suffix.strip():
            _, condition = _split_condition(suffix)
            if condition:
                result = _translate_condition(condition, unknown) + "，" + result
        return result
    if re.match(r"(?i)^Projectiles are fired in random directions$", source):
        return "投射物会向随机方向发射"

    flask_charge_gain = re.match(
        r"(?i)^((?:Life|Mana) )?Flasks gain ([0-9]+) Charges? every ([0-9]+) seconds?$",
        source,
    )
    if flask_charge_gain:
        flask_kind, amount, interval = flask_charge_gain.groups()
        flask_zh = {"life ": "生命", "mana ": "魔力", None: ""}[flask_kind.lower() if flask_kind else None]
        return f"每{interval}秒，{flask_zh}药剂获得{amount}点药剂充能"

    chance_gain_charge = re.match(
        r"(?i)^([+-]?[0-9]+(?:\.[0-9]+)?)% chance to gain (?:a[n]? )?"
        r"((?:Power|Frenzy|Endurance)(?:(?:,\s*(?:and|or)\s+|,\s+|\s+(?:and|or)\s+)(?:Power|Frenzy|Endurance)){0,2}) Charge "
        r"(?:on (.+)|when (.+)|each second while (.+))$",
        source,
    )
    if chance_gain_charge:
        amount, choices, on_trigger, when_trigger, cadence_trigger = chance_gain_charge.groups()
        charges_zh = _charge_choices_zh(choices)
        if on_trigger:
            trigger = "on " + on_trigger
        elif when_trigger:
            trigger = "when " + when_trigger
        elif cadence_trigger:
            trigger = "each second while " + cadence_trigger
        else:
            trigger = ""
        trigger_zh = CHARGE_GAIN_TRIGGERS_ZH.get((trigger or "").strip().lower())
        if charges_zh and trigger_zh:
            return f"{trigger_zh}，有{amount}%几率获得一个{charges_zh}"
    steal_charge = re.match(
        r"(?i)^([+-]?[0-9]+(?:\.[0-9]+)?)% chance to Steal "
        r"((?:Power|Frenzy|Endurance)(?:(?:,\s*(?:and|or)\s+|,\s+|\s+(?:and|or)\s+)(?:Power|Frenzy|Endurance)){0,2}) Charges on Hit with (.+)$",
        source,
    )
    if steal_charge:
        amount, choices, attack_type = steal_charge.groups()
        choices_zh = _charge_choices_zh(choices)
        attack_zh = "爪类武器" if attack_type.lower() == "claws" else _translate_terms(attack_type, unknown)
        if choices_zh:
            return f"使用{attack_zh}击中敌人时，有{amount}%几率窃取{choices_zh}"

    # Chance-to-ailment wording describes effects applied to enemies. Keeping
    # the target explicit prevents a fluent but reversed “you become poisoned”
    # fallback. The attack/damage scope remains attached to the hit condition.
    chance_hit = re.match(
        r"(?i)^([+-]?[0-9]+(?:\.[0-9]+)?)% chance to (Poison|Ignite|Shock|Freeze|Chill|Bleed|Bleeding) on Hit(?: with (Attacks|Spell Damage))?$",
        source,
    )
    if chance_hit:
        amount, status, scope = chance_hit.groups()
        prefix = "击中敌人时" if not scope else ("使用攻击击中敌人时" if scope.lower() == "attacks" else "以法术伤害击中敌人时")
        return f"{prefix}，有{amount}%几率{STATUS_ACTION_ZH[status.lower()]}"

    exposure_chance = re.match(
        r"(?i)^([+-]?[0-9]+(?:\.[0-9]+)?)% chance to inflict (Fire|Cold|Lightning) Exposure on Hit with (.+)$",
        source,
    )
    if exposure_chance:
        amount, element, damage = exposure_chance.groups()
        element_zh = {"fire": "火焰", "cold": "冰霜", "lightning": "闪电"}[element.lower()]
        damage_zh = _translate_terms(damage, unknown)
        return f"以{damage_zh}击中敌人时，有{amount}%几率对其施加{element_zh}曝露"
    exposure_actor = re.match(r"(?i)^(.+?) have(?: a)? ([0-9]+(?:\.[0-9]+)?)% chance to apply (Fire|Cold|Lightning) Exposure on Hit$", source)
    if exposure_actor:
        actor, amount, element = exposure_actor.groups()
        actor_zh = _translate_terms(actor, unknown)
        element_zh = {"fire": "火焰", "cold": "冰霜", "lightning": "闪电"}[element.lower()]
        return f"{actor_zh}击中敌人时，有{amount}%几率对其施加{element_zh}曝露"

    exposure_inflict = re.match(r"(?i)^([+-]?[0-9]+(?:\.[0-9]+)?)% chance to Inflict (Fire|Cold|Lightning) Exposure on Hit with (.+)$", source)
    if exposure_inflict:
        amount, element, damage = exposure_inflict.groups()
        element_zh = {"fire": "火焰", "cold": "冰霜", "lightning": "闪电"}[element.lower()]
        return f"以{_translate_terms(damage, unknown)}击中敌人时，有{amount}%几率对其施加{element_zh}曝露"

    taunt_chance = re.match(r"(?i)^([+-]?[0-9]+(?:\.[0-9]+)?)% chance to Taunt Enemies on Projectile Hit$", source)
    if taunt_chance:
        return f"投射物击中敌人时，有{taunt_chance.group(1)}%几率嘲讽敌人"
    hinder_chance = re.match(r"(?i)^([+-]?[0-9]+(?:\.[0-9]+)?)% chance to Hinder Enemies on Hit with Spells$", source)
    if hinder_chance:
        return f"法术击中敌人时，有{hinder_chance.group(1)}%几率阻碍敌人"
    withered_chance = re.match(
        r"(?i)^([0-9]+(?:\.[0-9]+)?)% chance to inflict Withered for ([0-9]+|two) seconds on Hit$",
        source,
    )
    if withered_chance:
        amount, duration = withered_chance.groups()
        duration_zh = {"two": "两"}.get(duration.lower(), duration)
        return f"击中敌人时，有{amount}%几率对其施加枯萎，持续{duration_zh}秒"
    withered_more_stacks = re.match(
        r"(?i)^([0-9]+(?:\.[0-9]+)?)% chance when you inflict Withered to inflict up to ([0-9]+) Withered Debuffs instead$",
        source,
    )
    if withered_more_stacks:
        amount, stacks = withered_more_stacks.groups()
        return f"你对敌人施加枯萎时，有{amount}%几率改为对其施加最多{stacks}层枯萎减益效果"

    aggravate_bleeding = re.match(
        r"(?i)^([0-9]+(?:\.[0-9]+)?)% chance to Aggravate Bleeding on targets you "
        r"(Hit|Critically Strike|Stun)(?: with (Attacks(?: Hits)?|Exerted Attacks))$",
        source,
    )
    if aggravate_bleeding:
        amount, action, attack_type = aggravate_bleeding.groups()
        attack_zh = "竭尽攻击" if attack_type.lower() == "exerted attacks" else "攻击"
        action_zh = {
            "hit": f"用{attack_zh}击中目标",
            "critically strike": f"用{attack_zh}暴击击中目标",
            "stun": f"用{attack_zh}击晕目标",
        }[action.lower()]
        return f"你{action_zh}时，有{amount}%几率使其流血加剧"
    blind_bleeding = re.match(
        r"(?i)^([0-9]+(?:\.[0-9]+)?)% chance to Blind with Hits against Bleeding Enemies$",
        source,
    )
    if blind_bleeding:
        return f"击中流血敌人时，有{blind_bleeding.group(1)}%几率使其致盲"
    freeze_chilled = re.match(r"(?i)^([0-9]+(?:\.[0-9]+)?)% chance to Freeze Enemies which are Chilled$", source)
    if freeze_chilled:
        return f"对冰缓敌人有{freeze_chilled.group(1)}%几率施加冻结"
    periodic_freeze = re.match(
        r"(?i)^Every ([0-9]+(?:\.[0-9]+)?) seconds?, ([0-9]+(?:\.[0-9]+)?)% chance to Freeze nearby Non-Frozen Enemies for ([0-9]+(?:\.[0-9]+)?) seconds?$",
        source,
    )
    if periodic_freeze:
        interval, amount, duration = periodic_freeze.groups()
        return f"每{interval}秒，有{amount}%几率冻结附近未被冻结的敌人，持续{duration}秒"
    chance_status_list = re.match(r"(?i)^([+-]?[0-9]+(?:\.[0-9]+)?)% chance to (.+?)(?: while affected by (?:a )?Herald)?$", source)
    if chance_status_list:
        amount, status_text = chance_status_list.groups()
        suffix = ""
        affected = re.search(r"(?i) while affected by (?:a )?Herald$", source)
        if affected:
            suffix = "（受到捷光影响时）"
        labels = _status_list_zh(status_text)
        if labels:
            parts = re.split(r"(?i)\s*,\s*|\s+and\s+|\s+or\s+", status_text.strip())
            if len(parts) == 1 and parts[0].strip().lower() in STATUS_ACTION_ZH:
                effect = STATUS_ACTION_ZH[parts[0].strip().lower()]
                return f"有{amount}%几率{effect}{suffix}"
            return f"有{amount}%几率对敌人施加{labels}{suffix}"

    chance_actor = re.match(
        r"(?i)^(.+?) have(?: a)? ([0-9]+(?:\.[0-9]+)?)% chance to (Ignite|Shock|Freeze|Chill|Poison|Maim|Taunt|Hinder|cause Bleeding)(?: on Hit| Enemies on Hit(?: with (?:Spells|Projectile))?| Enemies with Main Hand Hits| cause Bleeding)?$",
        source,
    )
    if chance_actor:
        actor, amount, action = chance_actor.groups()
        actor_zh = {
            "attacks": "攻击", "minions": "召唤物", "raised zombies": "召唤的僵尸",
            "chaos spells": "混沌法术", "fire skills": "火焰技能", "cold skills": "冰霜技能",
            "lightning skills": "闪电技能",
        }.get(actor.lower())
        if actor_zh:
            action_zh = "流血" if action.lower() == "cause bleeding" else STATUS_ZH.get(action.lower(), {"maim": "瘫痪", "taunt": "嘲讽", "hinder": "阻碍"}.get(action.lower(), action))
            if action.lower() == "taunt":
                outcome = "嘲讽敌人"
            elif action.lower() == "hinder":
                outcome = "阻碍敌人"
            elif action.lower() == "cause bleeding":
                outcome = "使敌人流血"
            elif action.lower() == "maim":
                outcome = "瘫痪敌人"
            elif action.lower() in STATUS_ACTION_ZH:
                outcome = STATUS_ACTION_ZH[action.lower()]
            else:
                outcome = "使敌人" + action_zh
            return f"{actor_zh}击中敌人时，有{amount}%几率{outcome}"

    faster_ailment = re.match(r"(?i)^Damaging Ailments deal damage ([0-9]+(?:\.[0-9]+)?)% faster$", source)
    if faster_ailment:
        return f"伤害型异常状态的伤害结算加快{faster_ailment.group(1)}%"
    bow_dot = re.match(r"(?i)^([0-9]+(?:\.[0-9]+)?)% increased Damage over Time with Bow Skills$", source)
    if bow_dot:
        return f"弓技能造成的持续伤害提高{bow_dot.group(1)}%"

    match = re.match(r"(?i)^With at least one nearby corpse, (.+)$", source)
    if match:
        return "附近至少有一具尸体时，" + translate_effect(match.group(1), unknown)
    match = re.match(r"(?i)^Each Mine applies ([0-9]+(?:\.[0-9]+)?)% (increased|reduced) Damage (taken|dealt) to Enemies near it, up to ([0-9]+(?:\.[0-9]+)?)%$", source)
    if match:
        amount, modifier, scope, maximum = match.groups()
        verb = "所受伤害" if scope.lower() == "taken" else "造成的伤害"
        return f"每颗地雷使附近敌人的{verb}{MODIFIERS[modifier.lower()]}{amount}%，最多{MODIFIERS[modifier.lower()]}{maximum}%"
    match = re.match(r"(?i)^Every ([0-9]+(?:\.[0-9]+)?) seconds?, Regenerate Energy Shield equal to ([0-9]+(?:\.[0-9]+)?)% of Evasion Rating over ([0-9]+(?:\.[0-9]+)?) seconds?$", source)
    if match:
        cadence, amount, duration = match.groups()
        return f"每{cadence}秒，在{duration}秒内回复相当于闪避值{amount}%的能量护盾"
    match = re.match(r"(?i)^Reflects ([0-9]+(?:\.[0-9]+)?) (.+?) Damage to (.+)$", source)
    if match:
        amount, damage_type, targets = match.groups()
        return f"对{_translate_terms(targets, unknown)}反射{amount}{_translate_terms(damage_type, unknown)}伤害"
    match = re.match(r"(?i)^([0-9]+(?:\.[0-9]+)?)% of your Energy Shield is added to your Stun Threshold$", source)
    if match:
        return f"你的眩晕门槛增加相当于能量护盾{match.group(1)}%的数值"
    match = re.match(r"(?i)^Fire Exposure you inflict applies an extra (-?[0-9]+(?:\.[0-9]+)?)% to Fire Resistance$", source)
    if match:
        return f"你施加的火焰曝露使火焰抗性额外变动{match.group(1)}%"
    match = re.match(r"(?i)^Exposure you inflict applies (?:an extra )?(-?[0-9]+(?:\.[0-9]+)?)% to the affected Resistance$", source)
    if match:
        return f"你施加的曝露使受影响的抗性额外变动{match.group(1)}%"
    match = re.match(r"(?i)^Exposure you inflict applies at least (-?[0-9]+(?:\.[0-9]+)?)% to the affected Resistance$", source)
    if match:
        return f"你施加的曝露使受影响的抗性至少达到{match.group(1)}%"
    match = re.match(r"(?i)^([0-9]+(?:\.[0-9]+)?)% of (Life|Mana) Leech is Instant per Equipped Claw$", source)
    if match:
        amount, resource = match.groups()
        resource_zh = "生命" if resource.lower() == "life" else "魔力"
        return f"每装备一把爪类武器，{resource_zh}偷取的{amount}%即时回复"
    match = re.match(r"(?i)^Damageable Minions (deal|take) ([0-9]+(?:\.[0-9]+)?)% increased Damage for each second they have been alive, up to a maximum of ([0-9]+(?:\.[0-9]+)?)%$", source)
    if match:
        action, amount, maximum = match.groups()
        damage = "造成的伤害" if action.lower() == "deal" else "受到的伤害"
        return f"可受伤召唤物每存活一秒，{damage}提高{amount}%，最多提高{maximum}%"
    match = re.match(r"(?i)^Gain ([0-9]+(?:\.[0-9]+)?) (Life|Mana) per Enemy Hit with (.+?)(?: if (.+))?$", source)
    if match:
        amount, resource, attack_scope, condition = match.groups()
        resource_zh = "生命" if resource.lower() == "life" else "魔力"
        result = f"每次{_translate_terms(attack_scope, unknown)}击中敌人，获得{amount}{resource_zh}"
        if condition:
            result += "（" + _translate_condition("if " + condition, unknown) + "）"
        return _compact_zh(result)

    # Keep recovery sources and rates in natural Chinese order.
    match = re.match(r"(?i)^Regenerate ([0-9]+(?:\.[0-9]+)?)% of (Life|Mana|Energy Shield) per second(.*)$", source)
    if match:
        amount, resource, suffix = match.groups()
        resource_zh = {"life": "生命", "mana": "魔力", "energy shield": "能量护盾"}[resource.lower()]
        result = f"每秒回复相当于最大{resource_zh}{amount}%的{resource_zh}"
        if suffix:
            _, condition = _split_condition(suffix)
            if condition:
                result += "（" + _translate_condition(condition, unknown) + "）"
        return result
    match = re.match(r"(?i)^Regenerate ([0-9]+(?:\.[0-9]+)?) (Life|Mana|Energy Shield) per second(.*)$", source)
    if match:
        amount, resource, suffix = match.groups()
        resource_zh = {"life": "生命", "mana": "魔力", "energy shield": "能量护盾"}[resource.lower()]
        result = f"每秒回复{amount}{resource_zh}"
        if suffix:
            _, condition = _split_condition(suffix)
            if condition:
                result += "（" + _translate_condition(condition, unknown) + "）"
        return result

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

    match = re.match(r"(?i)^Every ([0-9]+(?:\.[0-9]+)?) seconds?, Consume (.+?) to Recover ([0-9]+(?:\.[0-9]+)?)% of (Life|Mana|Energy Shield)(.*)$", source)
    if match:
        cadence, consumed, amount, resource, suffix = match.groups()
        resource_zh = {"life": "生命", "mana": "魔力", "energy shield": "能量护盾"}[resource.lower()]
        result = f"每{cadence}秒消耗{_translate_terms(consumed, unknown)}，回复相当于最大{resource_zh}{amount}%的{resource_zh}"
        if suffix:
            _, condition = _split_condition(suffix)
            if condition:
                result += "（" + _translate_condition(condition, unknown) + "）"
        return result

    match = re.match(r"(?i)^Recover ([0-9]+(?:\.[0-9]+)?)(%?)\s+(?:of\s+)?(Life|Mana|Energy Shield)(.*)$", source)
    if match:
        amount, percent, resource, suffix = match.groups()
        resource_zh = {"life": "生命", "mana": "魔力", "energy shield": "能量护盾"}[resource.lower()]
        result = f"回复相当于最大{resource_zh}{amount}%的{resource_zh}" if percent else f"回复{amount}{resource_zh}"
        if suffix:
            duration = re.match(r"(?i)^\s+over ([0-9]+(?:\.[0-9]+)?) seconds?(.*)$", suffix)
            if duration:
                seconds, remainder = duration.groups()
                result += f"，在{seconds}秒内"
                suffix = remainder
            if suffix.strip():
                _, condition = _split_condition(suffix)
                if condition:
                    result += "（" + _translate_condition(condition, unknown) + "）"
        return result

    match = re.match(r"(?i)^([+-]?[0-9]+(?:\.[0-9]+)?)%\s+chance to Defend with ([0-9]+(?:\.[0-9]+)?)% of Armour(.*)$", source)
    if match:
        amount, armour_percent, suffix = match.groups()
        result = f"有{amount}%几率以相当于护甲值{armour_percent}%的数值进行防御"
        if suffix:
            _, condition = _split_condition(suffix)
            if condition:
                result += "（" + _translate_condition(condition, unknown) + "）"
        return _compact_zh(result)

    match = re.match(r"(?i)^([+-]?[0-9]+(?:\.[0-9]+)?)%\s+[Cc]hance to (.+)$", source)
    if match:
        amount, action = match.groups()
        # Chance is a base chance, not an increased or more modifier.
        subject, condition = _split_condition(action)
        avoid_being = re.match(r"(?i)^avoid being (Poisoned|Stunned|Chilled|Frozen|Ignited|Shocked|Impaled|Maimed|Hindered)$", subject)
        if avoid_being:
            translated_subject = "避免" + {
                "poisoned": "中毒", "stunned": "眩晕", "chilled": "冰缓", "frozen": "冻结",
                "ignited": "点燃", "shocked": "感电", "impaled": "穿刺", "maimed": "瘫痪",
                "hindered": "阻碍",
            }[avoid_being.group(1).lower()]
        else:
            translated_subject = _translate_terms(subject, unknown)
        result = translated_subject + "几率" + amount + "%" if amount.startswith(("+", "-")) else f"有{amount}%几率{translated_subject}"
        if condition:
            result += "（" + _translate_condition(condition, unknown) + "）"
        return _compact_zh(result)

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
        if suffix.lower().startswith(" with "):
            scope = _translate_terms(suffix[6:], unknown)
            return _compact_zh(scope + "的" + label + " " + amount + "%")
        return _compact_zh(label + " " + amount + "%" + _translate_terms(suffix, unknown))

    match = re.search(r"(?<![A-Za-z])([+-]?\d+(?:\.\d+)?)%\s+(increased|reduced|more|less)\s+", source, re.IGNORECASE)
    if match:
        amount, modifier = match.groups()
        prefix = source[:match.start()]
        body = source[match.end():]
        subject, condition = _split_condition(body)
        left = _modifier_left(prefix, subject, unknown).rstrip()
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
    text = re.sub(r"(?i)(\d+(?:\.\d+)?)% faster start of Energy Shield Recharge", r"能量护盾充能启动加快\1%", source)
    subject, condition = _split_condition(text)
    translated = _translate_terms(subject, unknown)
    if condition:
        translated += "（" + _translate_condition(condition, unknown) + "）"
    return _compact_zh(translated)


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

    multiline_sources = {source for source in lines if "\n" in source or "\r" in source}
    missing_multiline = multiline_sources - set(MULTILINE_OVERRIDES)
    if missing_multiline:
        print("Unreviewed multiline source effects:", file=sys.stderr)
        print("\n".join(sorted(missing_multiline)), file=sys.stderr)
        return 3
    long_sources = {source for source in lines if "\n" not in source and "\r" not in source and len(source) > 80}
    missing_long = long_sources - set(REVIEWED_LONG_LINE_OVERRIDES) - set(SINGLE_LINE_OVERRIDES)
    if missing_long:
        print("Unreviewed long single-line source effects:", file=sys.stderr)
        print("\n".join(sorted(missing_long)), file=sys.stderr)
        return 3

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
            "multiline_effect_lines": len(multiline_sources),
            "multiline_unreviewed": 0,
            "reviewed_long_single_line_effects": len(long_sources),
            "long_single_line_unreviewed": 0,
            "mastery_nodes": sum(bool(n.get("isMastery")) for n in data["nodes"].values()),
            "mastery_options": mastery_options,
            "standard_nodes": len(data["standard_tree"]["default_allocation_graph"]["node_ids"]),
            "jewel_sockets": sum(bool(n.get("isJewelSocket")) for n in data["nodes"].values()),
            "classes": len(classes),
            "ascendancy_partitions": len(partitions),
            "expansion_jewel_nodes": len(data["special_subtrees"]["expansion_jewels"]["positioned_node_ids"]),
            "reminder_text_records_not_displayed_by_canonical_panel": sum("reminderText" in n for n in data["nodes"].values()),
            "reminder_text_entries_not_displayed_by_canonical_panel": sum(
                len(n.get("reminderText", [])) for n in data["nodes"].values()
            ),
            "untranslated_names": 0,
            "untranslated_effect_lines": 0,
        },
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)}: {len(names)} source IDs, {len(lines)} exact source-line mappings, {effect_occurrences} line occurrences")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
