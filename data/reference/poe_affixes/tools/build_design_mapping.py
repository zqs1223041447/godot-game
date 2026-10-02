#!/usr/bin/env python3
"""Original semantic adapter proposal, deliberately not a runtime implementation."""
import json,pathlib
root=pathlib.Path(__file__).resolve().parents[1]
rows=[]
def add(id, source, stage, target, unit, status, note, tags=None, types=None):
 rows.append(dict(id=id,source_stat_ids=source,semantic_stage=stage,proposed_target=target,unit_transform=unit,status_against_game_v030=status,notes_zh=note,required_event_tags=tags or [],damage_types=types or []))
add('maximum_life',['base_maximum_life'],'character_aggregate','max_health','raw points','direct_value_analogue','可参考生命上限加值；PoE的具体数值不是本游戏平衡结论。')
add('maximum_mana',['base_maximum_mana'],'character_aggregate','max_mana','raw points','direct_value_analogue','可参考魔力上限加值；需确认技能耗蓝和回复经济。')
add('flat_global_energy_shield',['base_maximum_energy_shield'],'character_aggregate','max_shield','raw points','analogue_only','现有护盾有自己的恢复逻辑，不等同于完整PoE能量护盾。')
add('local_weapon_physical_increased',['local_physical_damage_+%'],'item_local_before_skill_base','weapon_local.physical_increased','raw / 100','not_implemented','只提升这把武器的基础物理伤害；不能塞进 global_increased；纯物理和物理+命中复合词缀会在本地叠加。',types=['physical'])
for t in ['physical','fire','cold','lightning','chaos']:
 add('local_weapon_flat_'+t,['local_minimum_added_'+t+'_damage','local_maximum_added_'+t+'_damage'],'item_local_before_skill_base','weapon_local.added_'+t,'raw damage endpoints; each endpoint has its own roll range','not_implemented','先掷装备词缀的min/max端点，再由命中掷伤害；不要把两个端点误作同一个词缀roll上下限。',types=[t])
 add('attack_flat_'+t,['attack_minimum_added_'+t+'_damage','attack_maximum_added_'+t+'_damage'],'skill_base_before_effectiveness','attack_added_'+t,'raw damage endpoints','not_implemented','仅攻击相关基础伤害；独立secondary爆炸没有attack标签时不继承；需先定义伤害效用。',tags=['attack'],types=[t])
for t in ['fire','cold','lightning']:
 add('spell_flat_'+t,['spell_minimum_added_'+t+'_damage','spell_maximum_added_'+t+'_damage'],'skill_base_before_effectiveness','spell_added_'+t,'raw damage endpoints','not_implemented','施法伤害加值，不能因技能会发射投射物就变成所有投射物的加值。',tags=['spell'],types=[t])
 add(t+'_increased',[t+'_damage_+%'],'damage_component_increased','typed_increased.'+t,'raw / 100','resolver_supports_explicit_modifier_not_snapshot_field','只匹配对应伤害分量；与同一分量适用的全局/攻击/投射物increased相加。',types=[t])
add('attack_elemental_increased',['elemental_damage_with_attack_skills_+%'],'damage_component_increased','modifier: attack + elemental','raw / 100','resolver_supports_explicit_modifier_not_snapshot_field','不得直接映射 elemental_increased：源词缀多了attack限制。当前龙卷箭体匹配，独立secondary火爆炸不匹配。',tags=['attack'],types=['fire','cold','lightning'])
add('spell_increased',['spell_damage_+%'],'damage_component_increased','modifier: spell','raw / 100','resolver_supports_explicit_modifier_not_snapshot_field','需要本次伤害是spell，装备在法杖上不意味着它是本地武器伤害。',tags=['spell'])
add('bow_skill_increased',['damage_+%_with_bow_skills'],'damage_component_increased','modifier: bow_skill','raw / 100','needs_skill_origin_contract','源文本限定弓技能；不能泛化为projectile_increased。')
add('local_attack_speed',['local_attack_speed_+%'],'item_local_attack_timing','weapon_local.attack_speed_increased','raw / 100','not_implemented','现有attack_speed是每秒次数加值；百分比不能直接加到这个字段。')
add('global_attack_speed',['attack_speed_+%'],'character_attack_timing','attack_speed_increased','raw / 100','not_implemented','先定义本地武器攻速与角色攻速两个阶段，再乘基础攻击频率。')
add('cast_speed',['base_cast_speed_+%'],'character_spell_timing','cast_speed_increased','raw / 100','not_implemented','需要施法时间与冷却时间分离；不能误作通用cooldown recovery。')
add('move_speed',['base_movement_velocity_+%'],'character_movement','move_speed_increased','raw / 100','not_implemented','现有move_speed是单位/秒；35%不能直接变成+35单位/秒。')
add('projectile_speed',['base_projectile_speed_+%'],'carrier_kinematics','projectile_speed_increased','raw / 100','not_implemented','这是载体速度，不是伤害；必须明确固定寿命/固定距离策略，避免隐式多次命中。')
add('additional_arrows',['number_of_additional_arrows'],'cast_spawn_recipe','bow_additional_arrows','raw integer','analogue_only','源是弓箭数量，不是全部技能投射物数量；如选用于本游戏，应只增加龙卷母弹，子弹仍各3枚并受预算。')
add('life_regen',['base_life_regeneration_rate_per_minute'],'character_recovery','life_regen_per_second','raw / 60','not_implemented','源为每分钟定点值；不能按raw当每秒生命。')
add('mana_regen_increased',['mana_regeneration_rate_+%'],'character_recovery','mana_regen_increased','raw / 100','not_implemented','现有mana_regen是每秒加值，源是increased比率，两者不同量纲。')
add('physical_attack_life_leech',['life_leech_from_physical_attack_damage_permyriad'],'post_damage_recovery','life_leech_fraction','raw / 10000','not_implemented','例如raw20–40 = 0.2%–0.4%，不是20%–40%；还需吸取实例/上限规则。',tags=['attack'],types=['physical'])
add('resistances',['base_fire_damage_resistance_%','base_cold_damage_resistance_%','base_lightning_damage_resistance_%','base_chaos_damage_resistance_%'],'defender_mitigation','resistance_by_type','raw / 100','requires_character_defense_adapter','不可混入伤害increased；源抗性与最大抗性上限是不同字段，现有-100%到90%夹取是本游戏规则。')
add('local_armour_defences',['local_base_physical_damage_reduction_rating','local_base_evasion_rating','local_energy_shield','local_ward'],'item_local_defence','item_defence_base','raw points','not_implemented','先在每件装备本地合成，再聚合角色；护甲/闪避/护盾/结界不可合成一个无类型防御。')
add('crit_and_dot',['critical_strike_chance_+%','local_critical_strike_chance_+%','base_critical_strike_multiplier_+','dot_multiplier_+'],'special_combat_system','separate crit/dot systems','stat-specific, see source; no blanket transform','not_implemented','暴击率提高、暴击倍率加值、DoT multiplier与more不能都按独立乘区相乘；后续要显式实现。')
add('convocation_grant',['local_display_grants_skil_convocation_level'],'effect_grant','effect registry entry','grants_effects is authoritative','not_implemented','该词缀除了stat还有grants_effects，不能只读取stats；当前原型不应静默授予不存在的技能。')
source_stats=json.loads((root/'normalized/stats.json').read_text())
for r in rows:
 r['source_stat_ids']=[s for s in r['source_stat_ids'] if s in source_stats]
 assert r['source_stat_ids']
(root/'design/godot_mapping.json').write_text(json.dumps({'schema_version':1,'kind':'original_design_proposal_not_runtime_data','basis_game_version':'v0.3.0','source_reference':'../source_manifest.json','balance_status':'No source magnitude is approved as game balance. No runtime affix import or crafting system implemented.','entries':rows},ensure_ascii=False,indent=2)+'\n')
print(len(rows),'original semantic mapping entries')
