#!/usr/bin/env python3
"""Build the offline reference from Godot's exported catalog (stdlib only).
Run export_reference.gd first. Output is self-contained HTML plus local renderer PNGs.
No web fetch, package installation, user saves, or wall-clock metadata.
"""
from __future__ import annotations
import argparse
import hashlib
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / 'docs/reference'
CATEGORIES = [('skills','主动技能'),('supports','辅助技能'),('equipment','随机装备'),('affixes','装备词缀'),('fixed_items','固定装备'),('jewels','珠宝'),('jewel_affixes','珠宝词缀'),('source_passives','源天赋与精通'),('passives','旧181节点研究'),('mechanisms','共用机制'),('weapon_stages','武器局部阶段'),('defenses','受击与防御'),('flasks','生命与魔力药剂'),('currencies','堆叠材料'),('crafting','制作与回收'),('monsters','怪物图鉴'),('monster_attacks','怪物攻击'),('encounters','本轮挑战'),('town_services','城镇服务'),('maps','有限地图'),('map_specials','地图特殊词缀'),('rules','规则与边界')]
RULE_TITLES = {'damage':'伤害如何结算','supports':'辅助装配','projectiles':'分裂、返回与飞行结束','equipment':'装备与阶级','character_rates':'恢复、移动与普通攻击速度','basic_attack':'普通攻击与武器贡献','allocation':'天赋与珠宝规则','shared':'玩家和怪物共享机制','boundaries':'尚未实现的源游戏语义','sources':'数据来源与实现边界','ember_proliferation':'余烬扩散与剩余时长','shock':'感电与后续命中','source_fire_dot':'源天赋火焰持续伤害加成','source_faster_burn':'源天赋加速燃烧'}
CAPABILITIES = {'initial_projectiles':'初始投射物数量','projectile_hit':'投射物命中','finite_projectile_pierce':'有限穿透','area_hit':'直接范围命中','chain_hit':'连锁命中'}
SLOTS = {'weapon':'武器','armor':'护甲','charm':'项链','body_armour':'护甲','amulet':'项链','ring':'戒指','ring_1':'戒指一','ring_2':'戒指二','boots':'鞋','belt':'腰带','gloves':'手套','helmet':'头盔'}
TYPES = {'small':'小天赋','notable':'显著天赋','socket':'珠宝孔','start':'起点','keystone':'基石','mastery':'精通','prefix':'前缀','suffix':'后缀','ordinary':'普通珠宝','special':'特殊珠宝','legacy':'原始词池','expansion':'扩展词池','runewood':'符木点伤池','defense':'火抗防具池','local_weapon':'白蜡长弓池','nine_slot':'九槽装备池','build_legacy_v27':'构筑原底材池','build_nine_slot_v27':'构筑九槽池','forgeblade_v34':'锻纹短刃池'}
RULE_TITLES['forgeblade'] = '锻纹短刃与裂刃局部物理'
RULE_TITLES['melee_basic'] = '短刃近战普攻与裂刃衔接'
RULE_TITLES['mana_guard'] = '心灵升华与魔力先承伤'
RULE_TITLES['elemental_resistance_caps'] = '三元素最大抗性与有效抗性'
RULE_TITLES['elemental_defense_affixes'] = '灰烬皮甲与原始三抗供给'
RULE_TITLES['defense_rating_affixes'] = '灰烬皮甲：护甲、闪避与前缀取舍'
RULE_TITLES['resolute_technique'] = '坚决技艺：稳定命中与暴击取舍'
RULE_TITLES['iron_reflexes'] = '铁反射（闪转甲）：闪避转换与护甲取舍'
RULE_TITLES['zealots_oath'] = '狂信者的誓约：生命再生改为作用于能量护盾'
RULE_TITLES['ambush'] = '符印伏击：预置、触发与冻结快照'
RULE_TITLES['physical_fire_conversion'] = '物理转火焰：40%转换与伤害来源'
RULE_TITLES['precise_technique'] = '精准技艺：严格命中条件与全局禁暴击'
RULE_TITLES['inward_pull'] = '牵引辅助：朝真实爆发圆心反转冲量'
RULE_TITLES['glove_ring_affixes'] = '精瞄手套与三抗戒指：前后缀取舍'
RULE_TITLES['frost_lock'] = '霜锁辅助：短冻结、解冻免疫与攻击接续'
TYPES['defense_v37'] = '历史三抗防具池'
TYPES['defense_v39'] = '护甲闪避与三抗防具池'
TYPES['build_nine_slot_v46'] = '精瞄与三抗九槽池'

def esc(value): return html.escape(str(value), quote=True)
def lines(value): return '<br>'.join(esc(value).split('\n'))
def number(value): return f'{value:g}' if isinstance(value, (int,float)) else str(value)
def anchor(cat, key): return f'{cat}-{key}'
DAMAGE_NAMES = {'physical':'物理','fire':'火焰','cold':'冰霜','lightning':'闪电','chaos':'混沌'}
def component_text(components):
    return ' + '.join(f'{DAMAGE_NAMES[k]} {number(v)}' for k,v in ((key,components.get(key,0)) for key in DAMAGE_NAMES) if v) or '无'
def percent(value): return number(value*100)+'%'
def sunwell_value(key,value):
    return f'<strong data-sunwell-value="{esc(key)}" data-value="{esc(value)}">{number(value)}</strong>'

def sunwell_sequence(boss):
    sequence=boss['sequence'];definition=boss['definition'];rows=[]
    for pulse in sequence['pulses']:
        event=pulse['event'];index=event['pulse_index'];moving=pulse['cases']['moving']
        rows.append('<tr><th scope="row">第 '+str(index+1)+' 响</th><td>'+sunwell_value('deadline-'+str(index),pulse['normalized_deadline'])+' 秒</td><td>'+esc(' / '.join(number(v) for v in event['center']))+'</td><td>'+sunwell_value('radius-'+str(index),event['radius'])+'</td><td>'+component_text(event['packet']['base'])+'</td><td>原地：'+('范围内' if pulse['cases']['standing']['inside'] else '范围外')+'；持续退离：'+('范围内' if moving['inside'] else '范围外')+'</td></tr>')
    body='<h4>泉脉双响 · 同一锁点的两次结算</h4><div class="table-scroll"><table><caption>真实运行事件，时间统一从本次动作起手计</caption><thead><tr><th>回响</th><th>起手后时刻</th><th>锁定圆心 x / y</th><th>攻击半径</th><th>单响防御前分量</th><th>位置示例</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<p>每次预警 '+sunwell_value('warning',definition['profile']['windup_seconds'])+' 秒，共 '+sunwell_value('pulse-count',sequence['pulse_count'])+' 响，间隔 '+sunwell_value('pulse-interval',sequence['pulse_interval'])+' 秒；两响始终锁定玩家起手位置，第二响不会追踪新位置。单响接触分量倍率 '+sunwell_value('per-pulse-multiplier',definition['profile']['damage_multiplier'])+'，两响全部命中的防御前预算合计 '+sunwell_value('total-multiplier',sequence['total_contact_multiplier'])+' 倍。</p>'
    body+='<p>攻击圆半径 '+sunwell_value('attack-radius',definition['profile']['radius'])+'；本示例角色半径 '+sunwell_value('player-radius',boss['player_radius'])+'，角色中心距锁点须大于 '+sunwell_value('clear-center-distance',definition['profile']['radius']+boss['player_radius'])+' 才完全脱离圆形相交。持续离开锁点可以躲开两响；看到第一响结束也不要立即返回原圈。</p>'
    body+='<p>最后一响后进入恢复，基础 '+sunwell_value('base-recovery',sequence['base_recovery_seconds'])+' 秒；当前首领攻速 '+sunwell_value('attack-speed',sequence['source_attack_speed'])+'，真实策略恢复 '+sunwell_value('actual-recovery',sequence['actual_recovery_seconds'])+' 秒。攻速只影响恢复，两段完整预警不缩短。'+esc(sequence['settlement_scope'])+'。</p>'
    return body

def skill_delivery_diagram(skill_id, skill):
    if skill_id == 'cleave':
        recipe=skill['examples']['fresh'][0]['recipe']
        radius=recipe['radius']; half=recipe['half_angle']
        import math
        top=(70+64*math.cos(-half),80+64*math.sin(-half))
        end=(70+64*math.cos(half),80+64*math.sin(half))
        path=f'M70,80 L{top[0]:.4f},{top[1]:.4f} A64,64 0 {int(half>math.pi/2)} 1 {end[0]:.4f},{end[1]:.4f} Z'
        return f'<figure><svg viewBox="0 0 320 170" role="img" aria-label="裂刃真实前向扇区"><path d="{path}" fill="#d2c49e" fill-opacity="0.5" stroke="#796c4b"/><circle cx="70" cy="80" r="7" fill="#50654c"/><circle cx="117" cy="80" r="6" fill="#99584b"/><circle cx="36" cy="80" r="6" fill="#928a79"/><text x="158" y="67" fill="#382c21">半径 {number(radius)}</text><text x="158" y="89" fill="#382c21">前向 {number(math.degrees(half*2))}°</text><text x="158" y="111" fill="#382c21">近战 · 物理 · 范围</text></svg><figcaption>扇区与技能配方同源；目标体型参与边缘判定，背后不自动命中。力量与源近战物理节点影响这次攻击。</figcaption></figure>'
    if skill_id == 'shade_bolt':
        recipe=skill['projectile_recipe']
        return f'<figure><svg viewBox="0 0 320 150" role="img" aria-label="一次混沌飞弹命中"><circle cx="42" cy="66" r="8" fill="#50654c"/><path d="M58 66 L236 66" stroke="#9376a0" stroke-width="3"/><path d="M226 56 L246 66 L226 76 Z" fill="#775281"/><circle cx="264" cy="66" r="10" fill="#99584b"/><text x="35" y="115" fill="#382c21">速度 {number(recipe['speed'])} · 穿透 {number(recipe['pierce'])} · 固有混沌命中</text></svg><figcaption>源混沌增伤作用于该命中；装备附加分量仍按各自类型结算。没有毒、持续伤害或物理转换。</figcaption></figure>'
    return ''

def area_diagram(examples, skills):
    modes=[('base','无辅助'),('wide','广域'),('concentrated','凝域'),('combined','广域＋凝域')]
    body='<p>面积倍率先相乘，再统一开平方根得到半径倍率；双辅助面积0.9216、半径0.96。数值为本游戏初版预算，不改变投射物、独立爆炸或敌方重击。</p>'
    for skill_id,row in examples['skills'].items():
        scale=72/row['wide']['radius']; drawing=''
        for index,(mode,label) in enumerate(modes):
            x=90+index*155; sample=row[mode]
            drawing+=f'<circle cx="{x}" cy="92" r="{sample["radius"]*scale}" fill="#dfc08d" fill-opacity="0.20" stroke="#79571f" stroke-width="1.5" data-area-radius="{skill_id}-{mode}" data-value="{sample["radius"]}"/>'
            drawing+=f'<text x="{x}" y="185" text-anchor="middle" fill="#3b281b" font-size="13">{label} · {number(sample["radius"])}</text>'
        body+=f'<figure><svg viewBox="0 0 640 205" role="img" aria-label="{esc(skills[skill_id]["name"])}四种范围对比">{drawing}</svg><figcaption>{esc(skills[skill_id]["name"])} · 半径，目标体型仍参与实际命中。</figcaption></figure>'
        rows=''
        for mode,label in modes:
            sample=row[mode]
            rows+=f'<tr><th>{label}</th><td>{number(sample["area_multiplier"])}</td><td>{number(sample["radius"])}</td><td>{number(sample["hit_damage"])}</td><td>{number(sample["mana"])}</td></tr>'
        body+='<div class="table-scroll"><table><thead><tr><th>辅助</th><th>面积倍率</th><th>半径</th><th>单击 · 防御前</th><th>魔力</th></tr></thead><tbody>'+rows+'</tbody></table></div>'
        rows=''
        for layout,label in [('single','中心单个'),('cluster','原范围内聚集'),('near_original_edge','原边缘内侧'),('outer_band','原范围外圈')]:
            cells=''.join(f'<td>{len(row[mode]["layouts"][layout]["hit_indices"])}个 / {number(row[mode]["layouts"][layout]["total_before_defense"])}</td>' for mode,_ in modes)
            rows+='<tr><th>'+label+'</th>'+cells+'</tr>'
        body+='<div class="table-scroll"><table><thead><tr><th>固定站位 · 覆盖数/一次命中合计</th>'+''.join('<th>'+label+'</th>' for _,label in modes)+'</tr></thead><tbody>'+rows+'</tbody></table></div>'
    ref=examples['mechanism_reference']
    body+='<p>这些固定站位只说明取舍，不是通用DPS。范围、目标体型、抗性和魔力供给决定实际收益。</p>'
    body+='<p>机制背景：<a href="'+esc(ref['url'])+'">'+esc(ref['title'])+'</a>（'+esc(ref['date'])+'，GGG历史说明）。只借鉴面积与半径区别，未复刻完整PoE范围引擎或整数规则。</p>'
    return body

def support_program_diagram(entry, skills, details):
    body=''
    for skill,pair in entry['examples'].items():
        before,after=pair['before'],pair['after']
        metrics=[('魔力',before['mana'],after['mana']),('冷却秒',before['cooldown'],after['cooldown'])]
        br,ar=before['recipe'],after['recipe']
        if 'speed' in ar: metrics += [('投射速度',br['speed'],ar['speed']),('减速秒',br['slow'],ar['slow'])]
        if 'hit' in ar: metrics += [('总目标数',br['hit']['bounce_count'],ar['hit']['bounce_count']),('首段距离',br['first_range'],ar['first_range']),('续跳距离',br['followup_range'],ar['followup_range'])]
        if 'radius' in ar: metrics += [('半径',br['radius'],ar['radius']),('面积倍率',br.get('area_multiplier',1),ar.get('area_multiplier',1))]
        if after['initial_count']: metrics += [('初始投射物',before['initial_count'],after['initial_count'])]
        rows=''.join('<tr><th>'+label+'</th><td>'+number(a)+'</td><td>'+number(b)+'</td></tr>' for label,a,b in metrics)
        body += details(skills[skill]['name']+' · 同源前后示例','<div class="table-scroll"><table><thead><tr><th>参数</th><th>无辅助</th><th>该辅助</th></tr></thead><tbody>'+rows+'</tbody></table></div><p>'+esc(before['summary'])+'</p><p>'+esc(after['summary'])+'</p>'+details('实际分量、速度与范围规则',lines(after['details'])))
    return body

def piercing_diagram(examples, skills):
    content = '<p>同一直线六个固定目标，仅发射单枚载体；圆点是否点亮由真实碰撞事件导出。去返共用剩余穿透，命中上限不是保证命中数。</p>'
    for skill_id, pair in examples['skills'].items():
        content += '<h4>'+esc(skills[skill_id]['name'])+'</h4><svg class="mechanism-diagram" viewBox="0 0 480 132" role="img" aria-label="贯穿前后单枚命中示例">'
        for row, mode in enumerate(['before','after']):
            example=pair[mode]; y=36+row*56; hits=example['observed_hits']
            content += f'<text x="8" y="{y-15}" fill="#3b281b" font-size="13">'+('原配方' if mode=='before' else '贯穿辅助')+f'：{len(hits)} 次命中</text>'
            content += f'<path d="M 18 {y} H 450" stroke="#aa9c88" stroke-width="2" fill="none"/>'
            for target in range(1, examples['target_count']+1):
                x=48+target*60; fill='#8d6734' if target in hits else '#d4c9b8'
                content += f'<circle cx="{x}" cy="{y}" r="10" fill="{fill}" stroke="#69523a"/>'
            content += f'<text x="8" y="{y+24}" fill="#69523a" font-size="12" data-pierce-hits="{skill_id}-{mode}" data-value="{len(hits)}">单击 {number(example["hit_damage"])}，耗魔 {number(example["mana"])}</text>'
        content += '</svg>'
        before, after = pair['before'], pair['after']
        content += '<p>命中 '+str(len(before['observed_hits']))+' → '+str(len(after['observed_hits']))+'；耗魔 '+number(before['mana'])+' → '+number(after['mana'])+'；防御前单击 '+number(before['hit_damage'])+' → '+number(after['hit_damage'])+'</p>'
    return content

def encounter_diagram(key, definition, monsters):
    field=definition['field']; diagrams=''
    for template,sample in definition['examples'].items():
        before=sample['before'][field]; after=sample['after'][field]; maximum=max(before,after,1.0)
        bars=''
        for row,(label,value) in enumerate([('常规',before),('挑战',after)]):
            y=25+row*33; bar=value/maximum*205
            bars+=f'<text x="0" y="{y+14}" fill="#69523a" font-size="13">{label}</text><rect x="38" y="{y}" width="{bar}" height="19" fill="'+('#bca888' if row==0 else '#8f6736')+f'"/><text x="252" y="{y+14}" fill="#3b281b" font-size="13" data-encounter-value="{key}-{template}-{label}" data-value="{esc(value)}">{number(value)}</text>'
        label={'max_health':'最大生命','speed':'移动速度','damage':'原始攻击基底','attack_speed':'攻击速度','max_shield':'最大护盾','armour':'护甲'}[field]
        diagrams+='<figure><figcaption>'+esc(monsters[template]['name'])+' · '+label+f'</figcaption><svg class="mechanism-diagram" viewBox="0 0 350 90" role="img" aria-label="{esc(definition["name"])}前后参数">{bars}</svg></figure>'
    return '<div class="encounter-diagrams">'+diagrams+'</div><p class="fine">每组为第3波标准模板，之后只应用一次当前挑战；数据来自实际编译器。条形长度仅表示本行参数，不是综合难度、伤害或每秒收益。</p>'

def telegraph_diagram(attack):
    sample=attack['example']; event=sample['event']; profile=event['profile']; cases=sample['cases']
    radius=event['radius']; pr=sample['player_radius']; end=cases['moving']['position'][0]
    x0=-radius-pr-10; width=end+pr+15-x0
    pictures=''
    for mode,label in [('standing','留在原处'),('moving','直线移出')]:
        x,y=cases[mode]['position']; outcome='范围命中' if cases[mode]['inside'] else '范围外，未命中'
        pictures+=f'<figure><svg class="mechanism-diagram" viewBox="{x0} {-radius-pr-10} {width} {2*(radius+pr+10)}" role="img" aria-label="{esc(label+outcome)}"><circle cx="0" cy="0" r="{radius}" fill="#d4b888" fill-opacity=".25" stroke="#805b2e" stroke-width="2"/><path d="M 0 0 L {x} {y}" stroke="#775948" stroke-width="2" stroke-dasharray="5 4"/><circle cx="{x}" cy="{y}" r="{pr}" fill="#eee3c6" stroke="#6e302d" stroke-width="2"/><path d="M -5 0 H 5 M 0 -5 V 5" stroke="#805b2e" stroke-width="2"/></svg><figcaption>{label}：{outcome}</figcaption></figure>'
    values={'radius':radius,'warning':profile['windup_seconds'],'recovery':profile['recovery_seconds'],'standing':cases['standing']['settlement']['damage_total'],'armored':cases['armored']['settlement']['damage_total'],'moving':0.0 if not cases['moving']['inside'] else cases['moving']['settlement']['damage_total']}
    labels={'radius':'世界半径','warning':'预警秒数','recovery':'默认恢复秒数','standing':'未增加对应抗性','armored':attack.get('protection_label','穿普通灰烬皮甲'),'moving':'成功移出后伤害'}
    rows=''.join(f'<li><span class="flow-step">{labels[key]}</span><strong data-telegraph-value="{esc(attack['id'])}-{key}" data-value="{esc(value)}">{number(value)}</strong></li>' for key,value in values.items())
    return f'<div class="telegraph-diagram">{pictures}</div><figure class="defense-flow"><figcaption>同源范围与结算 · 第 {sample["source_wave"]} 波{esc(sample["source"]["name"])}</figcaption><ol>{rows}</ol><p>图形采用实际事件半径与角色半径 {pr}；移动示例假设从预警开始持续直线移动、没有阻挡，移动速度 {sample["move_speed"]}，距离 {number(end)}。命中由同一圆形相交规则判断，伤害由真实分量与防御规则计算。护盾 {sample["shield_before"]} 先承伤，再扣生命；这是一次命中，不是每秒伤害。</p></figure>'

def defense_diagram(example):
    trace=example['trace']
    total=sum(trace['raw_components'].values())
    stages=[
        ('命中分量',total,component_text(trace['raw_components']),'input_total'),
        ('经过抗性',trace['damage_total'],component_text(trace['components']),'damage_total'),
        ('护盾吸收',trace['shield_spent'],'剩余护盾 '+number(trace['remaining_shield']),'shield_spent'),
        ('生命扣减',trace['health_lost'],'剩余生命 '+number(trace['remaining_health']),'health_lost'),
    ]
    items=''.join(f'<li><span class="flow-step">{i+1:02d} · {esc(label)}</span><strong data-trace-value="{field}" data-value="{number(amount)}">{number(amount)}</strong><span>{esc(description)}</span></li>' for i,(label,amount,description,field) in enumerate(stages))
    return f'<figure class="defense-flow" aria-labelledby="defense-flow-title"><figcaption id="defense-flow-title">同一次命中 · 抗性 → 护盾 → 生命</figcaption><p>已知目标：火焰抗性 {percent(trace["effective_resistances"]["fire"])}，护盾 {number(example["shield_before"])}，生命 {number(example["health_before"])}。这是指定输入演算，不代表怪物固定伤害。</p><ol>{items}</ol><p class="fine">物理分量保持不变；本次火焰抵消 {number(trace["mitigated_components"].get("fire",0))}。整条演算来自实际受击规则，逐次结算，不是每秒伤害。</p></figure>'


def weapon_diagram(example):
    # Presentation only: all damage values are exported from real frozen packets.
    hit=example['hits']['parent']; packet=hit['packet']; trace=packet['assembly']; weapon=trace['weapon']; profile=weapon['profile']
    def value(field, amount, label):
        return f'<span>{esc(label)} <strong data-weapon-trace="{field}" data-value="{esc(amount)}">{number(amount)}</strong></span>'
    def components(prefix, values):
        return ''.join(value(prefix+'_'+k,v,DAMAGE_NAMES[k]) for k,v in values.items()) or '<span>无</span>'
    local=''.join([value('P',profile['base']['physical'],'P 固有'),value('F',profile['flat']['physical'],'F 局部点伤'),value('L',profile['increased']['physical'],'L 局部提高比率'),value('W',weapon['components']['physical'],'W 武器物理')])
    branches=[('原有角色基伤 B',components('intrinsic',trace['intrinsic']),'原有 60% 物理 / 40% 火焰分布仅用于 B'),('局部武器 W',components('weapon',weapon['contribution']),'全为物理，按技能基础倍率 '+number(weapon['coefficient'])),('外部附加点伤',components('added',trace['added']),'按附加效用 '+number(trace['added_effectiveness'])+'；此合法装备示例为零')]
    branches_html=''.join(f'<li><span class="flow-step">{esc(label)}</span>{values}<span>{esc(note)}</span></li>' for label,values,note in branches)
    settled=''.join([value('resolved',hit['resolved']['total'],'防御前'),value('known_target',hit['known_target_resolved']['total'],'已知火卫抗性后'),value('health_lost',hit['known_target_settlement']['health_lost'],'生命扣减')])
    return f'<figure class="weapon-flow" aria-labelledby="weapon-flow-title"><figcaption id="weapon-flow-title">白蜡长弓 → 龙卷母箭 · 同一命中的组装记录</figcaption><p>{esc(example["definition"]["weapon_damage_summary"])}</p><div class="weapon-local-inputs">{local}</div><ol>{branches_html}</ol><div class="weapon-result"><span class="flow-step">三路合入原始命中</span>{components("raw",packet["base"])}</div><div class="weapon-result"><span class="flow-step">再经角色增伤与目标防御</span>{settled}</div><p class="fine">图中取局部双前缀最高合法掷值、无辅助的母箭；是逐次命中，非全流派最优、总伤害或每秒伤害。数值由实际编译器、伤害解析器与受击规则导出。</p></figure>'


def forgeblade_rule(data, link, facts, details):
    blade=data['forgeblade']
    def value(key, amount):
        return f'<strong data-forgeblade-value="{esc(key)}" data-value="{esc(amount)}">{number(amount)}</strong>'
    body='<p>'+esc(blade['example_scope'])+'</p><p>'+esc(blade['formula'])+'。W按各自实际命中基础系数加入物理，不作用于原B或外部附加点伤；现有攻击、近战、物理、暴击与防御仍走后续阶段。范围提高只适用于含area标签的裂刃。'+link('rules','melee_basic')+'说明v0.56新增普攻消费者。</p>'
    body+=facts([('底材',link('equipment','forgeblade')),('格数',' × '.join(map(number,blade['base']['size']))),('局部消费者',link('rules','melee_basic')+' / basic/direct · hit + attack + melee；'+link('skills','cleave')+' / direct · hit + attack + melee + area'),('词池',esc(blade['pool_id'])),('保存版本',value('save-version',blade['save_version']))])
    body+='<h3>六族与合法物品</h3><p>两本地族都是前缀，不能同时出现在魔法装备；六族沿既有等级1/8/16与权重100/60/30，T1到T3为本游戏成长顺序。以下范围直接来自实际目录。</p>'
    rows=[]
    for key,family in blade['families'].items():
        ranges=data['affixes'][key]['formatted_ranges']
        rows.append('<tr><th>'+link('affixes',key)+'</th><td>'+TYPES[family['kind']]+'</td>'+''.join('<td>'+esc(r['min'])+' ～ '+esc(r['max'])+'</td>' for r in ranges)+'</tr>')
    body+='<div class="table-scroll"><table><thead><tr><th>族</th><th>类型</th><th>T1</th><th>T2</th><th>T3</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    combinations=[]
    for rarity,sets in blade['legal_family_sets'].items():
        for count in sorted(set(map(len,sets))):
            total=sum(len(ids)==count for ids in sets)
            combinations.append('<li>'+esc(data['equipment_rarities'][rarity]['name'])+' '+str(count)+'缀：'+value('family-sets-'+rarity+'-'+str(count),total)+'种族集合</li>')
    body+='<ul>'+''.join(combinations)+'</ul><p>在ilvl1用真实目录逐一验证全部族子集；档位与整数掷值另计，不是随机频率采样。</p><h3>合法实例 → 裂刃逐次命中</h3>'
    rows=[]
    for key,example in blade['examples'].items():
        hit=example['casts']['cleave']['hits']['direct'];critical=hit['critical']
        cells=[value(key+'-w',example['weapon']['components']['physical']),value(key+'-contribution',hit['local_contribution']),value(key+'-raw',sum(hit['packet']['base'].values())),value(key+'-resolved',hit['resolved']['total']),value(key+'-chance',critical['chance']),value(key+'-multiplier',critical['multiplier']),value(key+'-expected',hit['expected_zero_defense'])]
        rows.append('<tr><th>'+esc(example['name'])+'</th>'+''.join('<td>'+c+'</td>' for c in cells)+'</tr>')
        body+=details(example['name']+' · 合法实例',facts([('稀有度',esc(example['instance']['rarity'])),('物品等级',number(example['instance']['item_level']))])+'<p>'+lines('\n'.join(example['definition']['affix_lines']))+'</p>')
    body+='<div class="table-scroll"><table><thead><tr><th>物品</th><th>W</th><th>W×2.8</th><th>原始包</th><th>提高后普通命中</th><th>暴击几率</th><th>暴击倍率</th><th>0防御单次期望</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<p>小数0.07为7%几率，1.65为165%倍率。这里没有角色提高，原始包与提高后命中相同；真实默认角色有职业三属性，例如20力量的4%近战物理会在原始包之后结算。裸B18的裂刃原始包50.4；白短刃61.6，双T1金装65.8～69.72，T3局部顶86.8。不是默认角色面板或实战DPS。</p>'
    sample=blade['examples']['six_t3_max'];rows=[]
    for skill,cast in sample['casts'].items():
        for role,hit in cast['hits'].items():
            rows.append('<tr><th>'+('普通攻击' if skill=='basic' else link('skills',skill))+' / '+esc(role)+'</th><td>'+value('scope-'+skill+'-'+role,hit['local_contribution'])+'</td><td>'+percent(hit['critical']['chance'])+' / '+percent(hit['critical']['multiplier'])+'</td></tr>')
    body+=details('全部命中role的真实局部贡献与全局暴击','<table><thead><tr><th>命中</th><th>短刃W贡献</th><th>全局暴击几率 / 倍率</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table><p>除basic/direct与cleave/direct外，命中包逐字段等于同一全局属性、仅移除武器profile的对照。basic对照保留实际近战事件recipe再仅移除W，避免误换成投射物。dash与ward没有命中包；爆炸效果仅在隔离例子中显式开启，以展示其他技能的secondary规则，近战普攻不产生secondary。</p>')
    body+='<p>'+esc(blade['global_scope'])+'。施放时冻结W与暴击，换装不重解释已存在的命中包。伤害偷取继续依据防御后敌人的实际护盾与生命损失，不计过量伤害。</p>'
    resources=sample['definition']['stats']
    body+=facts([('T3深汲全局最大魔力增加',value('global-max-mana',resources['max_mana'])),('T3泉旋全局魔力恢复提高',value('global-mana-regen',resources['mana_regen_increased']))])
    body+='<h3>获取与制作</h3><p>测试城镇免费底材供应读取真实目录；正式游戏当前 '+esc(blade['current_loot_profile_id'])+'：'+' / '.join(esc(TYPES[row['pool_id']])+' '+value('loot-'+row['pool_id'],row['weight'])+'%' for row in blade['current_loot_profile'])+'。这是已产生普通装备奖励后的词池分布，旧profile保持；不增加根怪奖励资格或掉落次数，灰烬专属池不变。</p>'
    body+='<p>现有回收、校准、赋魔、升格、补缀、重铸六工艺复用，费用与回收公式不变。定向重铸保持稀有度并替换全部词缀，保证候选如下：</p><ul>'
    for operation,row in blade['crafting'].items():
        if not row['presentation'].get('targeted'): continue
        text=esc(row['presentation']['target_label'])+'：'
        if row['quote']['ok']:
            text+='魔法 '+value(operation+'-magic-cost',row['quote']['cost']['calibration_shard'])+'、稀有 '+value(operation+'-rare-cost',row['rare_quote']['cost']['calibration_shard'])+' 枚；候选 '+'、'.join(link('affixes',key) for key in row['eligible_families'])
        else: text+='禁用；'+esc(row['quote']['reason'])+' 不消耗随机数'
        body+='<li>'+text+'</li>'
    body+='</ul><p>报价仍绑定完整快照、UID、revision与可撤销句柄；先落盘后提交。取消、旧报价、外改、满包或保存失败不改变钱物与盘上状态。</p>'
    migration=blade['migration']
    body+='<h3>schema33 → 34与预算边界</h3><p>'+esc(migration['backup_contract'])+' 旧schema注入forgeblade整份拒绝，旧升级链仍逐版本冻结校验；源天赋执行政策保持33。</p><p>同源纯迁移示例只改变 '+esc('、'.join(migration['changed_fields']))+'；'+esc(migration['evidence_scope'])+'</p>'
    body+='<p>T3六族零防御单次暴击期望90.7494；历史符木合法四缀顶值对应普通90.384、基础暴击期望92.6436。护甲与火抗分别结算会改变比较，不能由此宣称完整配装最优或平衡通过。</p><p><a href="../qa/v055-budget/README.md">实现前静态可达预算与限制</a> · <a href="../FORGEBLADE.zh-CN.md">锻纹短刃规则说明</a></p>'
    return body


def melee_basic_rule(data, link, facts, details):
    melee=data['melee_basic']; blade=data['forgeblade']
    def value(key, amount):
        return f'<strong data-melee-basic-value="{esc(key)}" data-value="{esc(amount)}">{number(amount)}</strong>'
    body='<p>装备'+link('equipment','forgeblade')+'后，普通攻击使用近战direct派送；仍是既有普通攻击，不新增主动宝石或技能槽。白蜡长弓与其他旧武器保留原投射物路径。</p>'
    rows=[]
    for key,title,cast in [('basic','短刃普通攻击',melee['examples']['normal']),('cleave','裂刃斩',melee['cleave'])]:
        recipe=cast['recipe']; packet=cast['packets']['direct']; assembly=packet['assembly']
        cells=[esc(recipe.get('delivery','扇形技能')),value(key+'-radius',recipe['radius']),value(key+'-angle',cast['full_angle_degrees']),value(key+'-targets',recipe['max_targets']) if 'max_targets' in recipe else '范围内多个目标',value(key+'-coefficient',assembly['base_coefficient']),value(key+'-effectiveness',assembly['added_effectiveness']),value(key+'-mana',cast['mana']),value(key+'-cooldown',cast['cooldown']) if cast['has_cooldown_field'] else '原attack_timer间隔']
        rows.append('<tr><th>'+title+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
    body+='<div class="table-scroll"><table><thead><tr><th>攻击</th><th>派送</th><th>半径</th><th>全角度</th><th>最多目标</th><th>基础系数</th><th>附加效用</th><th>魔力</th><th>冷却/间隔</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<p>'+esc(melee['timing'])+' '+esc(melee['admission'])+'</p><p>'+esc(melee['scope'])+'</p>'
    body+='<h3>同一装备：隔离原始包与默认职业分开</h3><p>全部值直接读取实际compiler命中包及DamageResolver。隔离B18样本没有职业提高；默认职业示例使用真实Canonical装备UID、生产位置规划器及完整schema校验，仅在内存装备短刃，无其他装备或额外天赋。力量的近战物理提高在原始包之后结算。</p>'
    rows=[]
    for key,example in melee['equipped_examples'].items():
        basic=example['basic']; packet=basic['packets']['direct']; stats=example['stats']
        cells=[value(key+'-raw',sum(packet['base'].values())),value(key+'-isolated',melee['examples'][key]['resolved']['total']),value(key+'-strength',stats['strength']),value(key+'-melee-increased',stats['melee_physical_increased']),value(key+'-resolved',basic['resolved']['total']),value(key+'-cleave-resolved',example['cleave']['resolved']['total'])]
        rows.append('<tr><th>'+esc(blade['examples'][key]['name'])+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
        body+=details(blade['examples'][key]['name']+' · 实际装备与派送',facts([('UID',esc(example['instance']['uid'])),('装备位置',esc(example['location']['slot_id'])),('普攻标签',' + '.join(map(esc,packet['tags']))),('命中roles',' / '.join(map(esc,basic['packets']))),('实际编译预览',esc(basic['summary']))])+'<p>'+lines(basic['details'])+'</p>')
    body+='<div class="table-scroll"><table><thead><tr><th>合法短刃</th><th>普攻原始包</th><th>无职业提高普攻</th><th>默认力量</th><th>力量近战提高</th><th>默认职业普攻</th><th>默认职业裂刃</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<p>这些是零目标防御、非暴击的单次成功命中；全局暴击与资源仍按原全局范围计算。'+esc(melee['balance'])+'</p>'
    frozen=melee['legacy_inflight']['normal']['projectile']
    body+='<h3>旧飞箭与新近战分开冻结</h3><p>v0.55已飞出的短刃普通projectile保留原B：'+value('legacy-projectile-raw',sum(frozen['base'].values()))+'。这是独立v0.55导出包经过当前冻结读取器的结果；没有短刃W，不会因换装或本次派送变化重算为新近战。旧secondary同样保留原快照；新近战只有direct，不能借用旧返回或飞行结束爆炸。</p>'
    body+='<p>schema仍为'+value('save-version',melee['save_version'])+'，无新gem、词族、装备或图片。'+link('rules','forgeblade')+'保留词缀、制作与迁移资料。<a href="../MELEE_BASIC.zh-CN.md">近战普攻规则</a> · <a href="../qa/v056-reference/README.md">本批图鉴验证</a></p>'
    return body


def elemental_resistance_cap_rule(data, link, facts, details):
    caps=data['elemental_resistance_caps']; local=data['source_tree_localization']['nodes']
    def value(key, amount, ratio=False):
        return f'<strong data-resistance-cap-value="{esc(key)}" data-value="{esc(amount)}">{percent(amount) if ratio else number(amount)}</strong>'
    body=facts([('默认上限',value('base-cap',caps['base_cap'],True)),('本游戏安全上限',value('safety-cap',caps['safety_cap'],True)),('最低存档版本',value('save-version',caps['minimum_save_version']))])
    body+=''.join('<p>'+esc(caps[key])+'。</p>' for key in ['formula','source_reminder','scope'])
    labels={'default_75':'默认上限','raw_40_cap_83':'原始不足40%','raw_75_cap_83':'原始仍为75%','raw_83_cap_83':'原始足够83%','raw_100_cap_83':'原始溢出100%','safety_ceiling':'超过安全预算的边界输入'}
    rows=[]
    for key,ex in caps['examples'].items():
        p=ex['profile']
        cells=[value(key+'-raw',p['raw_resistances']['fire'],True),value(key+'-maximum',p['maximum_resistances']['fire'],True),value(key+'-effective',p['effective_resistances']['fire'],True)]
        cells += [value(key+'-'+element+'-hit',ex['hits'][element]['damage_total']) for element in ['fire','cold','lightning']]
        cells += [value(key+'-burn',ex['fire_burn']['damage_total'])]
        rows.append('<tr><th>'+esc(labels[key])+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
    body+='<h3>原始抗性、当前上限、有效抗性是三个数</h3><p>每行给三种元素相同原始值与上限加成。每列独立输入100点伤害、无护盾与魔力分担，燃烧列为100点原始火焰持续损伤。结果直接来自权威规则，不是实战DPS；最后一行只验证安全边界，不代表当前可取得25个百分点上限加成。</p><div class="table-scroll"><table><thead><tr><th>独立输入</th><th>原始抗性</th><th>当前上限</th><th>有效抗性</th><th>火命中</th><th>冰命中</th><th>电命中</th><th>火燃烧</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<p>原始抗性足够时，100点伤害由25降至17，较75%上限少承受32%；只提高上限不会补足原始抗性。C页三行显示有效值，提示同时给出原始值与当前上限，读取同一角色防御profile。</p>'
    body+='<h3>12个完整标准节点</h3>'
    for node_id in caps['new_complete_ordinary_nodes']:
        body+='<p>'+link('source_passives',node_id,local[node_id]['name']+' · '+node_id)+'：'+lines(local[node_id]['stats'])+'</p>'
    body+='<p>三种最大抗性各能累计8个百分点；表中节点保留所有其他已实现词句。含未实现效果的混合节点仍整体锁定；完整文本也不授予图外节点标准图资格。</p>'
    body+='<h3>混合、精通与图外边界</h3>'
    for node_id,node in caps['boundaries'].items():
        state='图外，仅浏览' if not node['standard_graph'] else ('精通效果逐项检查' if node['mastery_choices'] else '完整效果未接入，不可分配')
        body+=details(local[node_id]['name']+' · '+node_id+' · '+state,'<p>'+link('source_passives',node_id)+' · '+lines(local[node_id]['stats'])+'</p><p>执行判定：'+esc(node['execution']['status'])+'；来源为当前Godot源执行器。条件精通、召唤物与混沌最大抗性不在本批支持范围。</p>')
    for effect,entry in caps['mastery_boundaries'].items():
        host=entry['host_nodes'][0]
        body+=details('未接入精通效果 '+effect,'<p>'+lines(local[host]['mastery_choices'][effect])+'</p><p>执行判定：'+esc(entry['execution']['status'])+'；所在节点：'+'、'.join(link('source_passives',node_id,node_id) for node_id in entry['host_nodes'])+'。这是精通效果ID，不是标准节点ID。</p>')
    route=caps['reachable_build']; p=route['profile']
    body+='<h3>73点可达构筑与装备供给</h3><p>'+esc(caps['route_scope'])+'。</p>'+facts([('等级',value('route-level',route['level'])),('已用点数',value('route-points',route['points_spent']))]+[(DAMAGE_NAMES[element]+' 原始 / 当前上限 / 有效',value('route-'+element+'-raw',p['raw_resistances'][element],True)+' / '+value('route-'+element+'-maximum',p['maximum_resistances'][element],True)+' / '+value('route-'+element+'-effective',p['effective_resistances'][element],True)) for element in ['fire','cold','lightning']])
    body+=details('普通连接路线与全部节点','<p>'+' → '.join(link('source_passives',node_id,node_id) for node_id in route['allocated'])+'</p><p>列表为逐点可连接顺序，分支之间不表示每两个连续ID都有直接边；完整候选已通过生产构筑验证。</p>')
    equipment=caps['equipment']
    body+='<p>当前 '+link('equipment',equipment['base_id'])+' 提供原始火抗：底材 '+value('equipment-base-fire',equipment['base_raw_fire'],True)+' 加 '+link('affixes',equipment['affix_id'])+' 最高 '+value('equipment-affix-fire',equipment['affix_max_raw_fire'],True)+'，单件最多 '+value('equipment-total-fire',equipment['maximum_raw_fire'],True)+'。当前原始冰、电抗装备来源：'+ '、'.join(link('affixes',key) for key in equipment['equipment_cold_sources']+equipment['equipment_lightning_sources'])+'；v0.60胸甲单件预算见 '+link('rules','elemental_defense_affixes')+'，v0.72双戒供给与后缀取舍见 '+link('rules','glove_ring_affixes')+'。珠宝未新增抗性来源；提高最大上限后仍须检查原始抗性是否足够。</p>'
    body+='<h3>结算时间与旧存档</h3><p>'+esc(caps['timing'])+'。命中沿既有护甲、抗性、感电，再结算护盾、魔力分担、生命；燃烧不加入护甲或感电命中乘区。自然怪及现地图元素庇护未获得最大抗性加成，继续使用默认75%上限。</p><p>'+esc(caps['migration'])+'。缺字段或显式零保留既有结算与返回结构；新36文件不声称与旧35字节相同。</p><p><a href="../ELEMENTAL_RESISTANCE_CAPS.zh-CN.md">最大抗性说明</a> · '+link('rules','source_tree')+' · '+link('rules','mana_guard')+' · <a href="source-tree-coverage.json">同源执行覆盖JSON</a></p>'
    return body


def resolute_technique_rule(data, link, facts, details):
    rule=data['resolute_technique'];before=rule['examples']['before'];after=rule['examples']['after']
    def value(key, amount, ratio=False):
        return f'<strong data-resolute-value="{esc(key)}" data-value="{esc(amount)}">{percent(amount) if ratio else number(amount)}</strong>'
    body=facts([('源节点',link('source_passives','31961')),('可行路线',f'野蛮人 {value("required-level",rule["required_level"])} 级 / {value("points-spent",rule["points_spent"])} 点'),('存档 / 源政策 / 装备词汇',value('save-version',rule['minimum_save_version'])+' / '+value('source-policy',rule['source_policy'])+' / '+value('equipment-vocabulary',rule['equipment_vocabulary']))])
    body+='<p>'+esc(rule['scope'])+'。</p><p>'+esc(rule['bounds'])+'。</p>'
    body+='<p>'+esc(rule['example_scope'])+'。两边保留沿途全部属性；分配前余1点，分配后余0点，不把11点当成免费获得。</p>'
    body+='<h3>高闪避与零闪避：这一点换来了什么</h3><p>下表普通攻击取当前构筑同一枚投射物。成功命中伤害不含暴击；单次尝试期望先按暴击几率加权，再计闪避准入，不累计多弹、攻速或覆盖人数。</p>'
    rows=[]
    for target_id,label in [('evasive','敏捷型怪物的闪避'),('no_evasion','无闪避目标')]:
        left=before['casts']['basic']['hits']['projectile']['targets'][target_id];right=after['casts']['basic']['hits']['projectile']['targets'][target_id]
        cells=[value(target_id+'-evasion',rule['targets'][target_id]['evasion'])]
        for mode,case in [('before',left),('after',right)]:
            stem=target_id+'-'+mode
            cells += [value(stem+'-chance',case['admission']['chance'],True),value(stem+'-successful',case['successful_noncritical_hit']['total']),value(stem+'-expected',case['expected_per_attempt'])]
        rows.append('<tr><th>'+label+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
    body+='<div class="table-scroll"><table><caption>同构筑、无护甲与抗性的逐次比较</caption><thead><tr><th>目标</th><th>闪避值</th><th>分配前命中率</th><th>成功非暴击命中</th><th>每次尝试期望</th><th>分配后命中率</th><th>成功命中</th><th>每次尝试期望</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<p>原本有闪避时，稳定命中可能抵偿失去暴击的代价，结果取决于原命中率与暴击投入；原本已经100%命中的目标没有新增命中收益，只失去暴击机会。法术原本不进行攻击闪避，同样承担禁暴击代价。</p>'
    body+='<h3>攻击、法术和独立爆炸一并禁暴击</h3>';rows=[]
    role_labels={'projectile':'投射物','direct':'直接命中','parent':'母箭','child':'子箭','secondary':'独立爆炸'}
    for skill in ['basic','cleave','tornado','nova']:
        for role,hit in after['casts'][skill]['hits'].items():
            old=before['casts'][skill]['hits'][role];stem=skill+'-'+role
            label=('普通攻击' if skill=='basic' else link('skills',skill))+' / '+role_labels.get(role,role)
            cells=[value(stem+'-before-crit',old['critical']['chance'],True),value(stem+'-after-crit',hit['critical']['chance'],True),value(stem+'-before-expected',old['targets']['no_evasion']['expected_per_attempt']),value(stem+'-after-expected',hit['targets']['no_evasion']['expected_per_attempt'])]
            rows.append('<tr><th>'+label+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
    body+='<div class="table-scroll"><table><caption>零闪避、零防御下的全局代价；各行独立，不能相加成DPS</caption><thead><tr><th>命中来源</th><th>分配前暴击率</th><th>分配后暴击率</th><th>分配前单次期望</th><th>分配后单次期望</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div><p>已装备'+link('fixed_items','detonation_charm')+'才有独立爆炸，仍须满足自然飞行结束的触发条件。禁暴击时不展示无意义的暴击伤害倍率；既有词缀与潜在倍率仍保留，退款后的新施放恢复读取。</p>'
    body+='<h3>护甲与抗性继续结算</h3><p>'+esc(rule['defense_scope'])+'。</p>';rows=[]
    for skill,role in [('basic','projectile'),('cleave','direct'),('nova','direct'),('tornado','secondary')]:
        hit=after['casts'][skill]['hits'][role];stem='defense-'+skill+'-'+role
        rows.append('<tr><th>'+('普通攻击' if skill=='basic' else link('skills',skill))+' / '+role_labels[role]+'</th><td>'+value(stem+'-before',hit['targets']['no_evasion']['successful_noncritical_hit']['total'])+'</td><td>'+value(stem+'-after',hit['targets']['armour_and_capped_resistance']['successful_noncritical_hit']['total'])+'</td></tr>')
    body+=facts([('目标护甲',value('target-armour',rule['defense_profile']['armour'])),('目标有效三抗',' / '.join(value('target-'+element+'-resistance',rule['defense_profile']['effective_resistances'][element],True) for element in ['fire','cold','lightning']))])
    body+='<div class="table-scroll"><table><thead><tr><th>已分配坚决技艺</th><th>防御前成功命中</th><th>防御后成功命中</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+=''.join('<p>'+esc(rule[key])+'。</p>' for key in ['timing','randomness','migration'])
    body+=details('完整原词条与合法路径','<p>'+esc(rule['node']['source_lines'][0]).replace('\n','<br>')+'</p><p>'+' → '.join(link('source_passives',node) for node in rule['route'])+'</p><p>以上为v61/source38历史范围：当时仅31961成为完整标准节点，没有新精通，63620尚未开放；旧数值与构筑保留。当前source45已完整实现'+link('rules','precise_technique','精准技艺63620')+'；其他未完整支持的多行效果仍按当前源覆盖锁定。</p>')
    body+='<p>'+link('rules','source_critical')+' · '+link('rules','elemental_resistance_caps')+' · <a href="../RESOLUTE_TECHNIQUE.zh-CN.md">坚决技艺说明</a> · <a href="../qa/v061-reference/README.md">本批图鉴验证</a></p>'
    return body


def elemental_defense_affix_rule(data, link, facts, details):
    supply=data['elemental_defense_affixes']
    def value(key, amount, ratio=False):
        return f'<strong data-elemental-affix-value="{esc(key)}" data-value="{esc(amount)}">{percent(amount) if ratio else number(amount)}</strong>'
    body='<p>护寒、护雷是原始冰霜/闪电抗性后缀，只能出现在 '+link('equipment',supply['base_id'])+'，由同一装备formatter显示百分比；不会提高最大抗性，也不新增珠宝、装备位或底材。</p>'
    body+=facts([('当前装备词汇',value('vocabulary',supply['vocabulary'])),('三抗引入版本',value('save-version',supply['minimum_save_version'])),('天赋源政策',value('source-policy',supply['source_policy'])),('可穿胸甲数',value('body-slots',len(supply['slot_targets']))),('当前词池',esc(supply['pool_id']))])
    rows=[]
    for key,family in supply['new_families'].items():
        for tier,ranges in zip(family['tiers'],data['affixes'][key]['formatted_ranges']):
            stem=key+'-'+str(tier['tier'])
            rows.append('<tr><th>'+link('affixes',key)+'</th><td>T'+value(stem+'-tier',tier['tier'])+'</td><td>'+value(stem+'-level',tier['level'])+'</td><td>'+esc(family['label']+' '+ranges['min']+' ～ '+ranges['max'])+'</td><td>'+value(stem+'-weight',tier['weight'])+'</td></tr>')
    body+='<h3>同源档位与资格</h3><p>同族或同组不能重复，高物品等级仍可出低阶。整数25经实际目录只换算一次为25%，不会变成2500%或0.25%。白装无词缀；蓝装最多1前1后，冷电两个后缀不能同时存在；金装4–6词，最多3前3后。</p><div class="table-scroll"><table><thead><tr><th>族</th><th>档</th><th>最低物品等级</th><th>实际显示范围</th><th>候选权重</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<p>当前词池已扩为护甲、闪避与生命、魔力、护盾五个前缀族争三个名额，见 '+link('rules','defense_rating_affixes')+'。下表保留v0.60原三资源与三抗六词预算，仍合法，但不是唯一满前缀组合。</p>'
    body+='<h3>一件胸甲的真实预算</h3><p>'+esc(supply['budget_scope'])+'。生命、魔力、护盾为该物品含底材的加值；三抗读取装备所在合法角色的权威profile，默认上限仍75%。</p>'
    labels={'white_base':'测试供应白底材','six_max':'六词T3顶值','mana_recovery':'以泉旋替换护火'}
    rows=[]
    for key,example in supply['examples'].items():
        item=example['definition']['stats'];profile=example['profile']
        amounts=[value(key+'-health',item.get('max_health',0)),value(key+'-mana',item.get('max_mana',0)),value(key+'-shield',item.get('max_shield',0))]
        amounts += [value(key+'-'+element+'-raw',profile['raw_resistances'][element],True) for element in ['fire','cold','lightning']]
        amounts += [value(key+'-mana-regen',item.get('mana_regen_increased',0),True)]
        rows.append('<tr><th>'+esc(labels[key])+'</th>'+''.join('<td>'+cell+'</td>' for cell in amounts)+'</tr>')
    body+='<div class="table-scroll"><table><thead><tr><th>独立示例</th><th>生命加值</th><th>魔力加值</th><th>护盾加值</th><th>原始火抗</th><th>原始冰抗</th><th>原始电抗</th><th>魔力恢复提高</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    full=supply['examples']['six_max']
    body+=details('六个真实词缀与同源命中',lines('\n'.join(full['definition']['affix_lines']))+'<p>分别独立输入100点火、冰、电命中，省略护盾与魔力分担：'+ ' / '.join(DAMAGE_NAMES[element]+' '+value('six-max-'+element+'-hit',full['hits'][element]['damage_total']) for element in ['fire','cold','lightning'])+'。各元素分别减伤，不能把40%/25%/25%相加当成总减伤。</p>')
    rows=[]
    for key,label in [('default_75','达到默认75%有效抗性'),('safety_83','用满83%安全上限')]:
        rows.append('<tr><th>'+label+'</th>'+''.join('<td>'+value(key+'-'+element+'-gap',full['additional_raw_required'][key][element],True)+'</td>' for element in ['fire','cold','lightning'])+'</tr>')
    body+='<div class="table-scroll"><table><caption>六词顶值胸甲之外仍须补的原始抗性（百分点）</caption><thead><tr><th>目标</th><th>火</th><th>冰</th><th>电</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div><p>83%目标还须真实分配对应最大抗性天赋；新增后缀不会赠送这些天赋或上限。'+link('rules','elemental_resistance_caps')+'保留73点可达路线，但它不是这件装备的最省点搭配结论。</p>'
    body+='<p>'+esc(supply['tradeoff'])+'。同一胸甲位不能多穿灰烬皮甲补抗。</p><h3>实际取得与制作取舍</h3>'
    body+='<p>'+esc(supply['supply_scope'])+'。灰烬守卫的逻辑defense在实际奖励入口映射当前防御池，仍只结算原来的一件奖励；明确调用历史defense保留原结果。</p>'
    for map_id,example in supply['formal_map_tier_iii'].items():
        body+='<p>'+link('maps',map_id)+' III：真实奖励物品等级 '+value(map_id+'-ilvl',example['item_level'])+'；合格档位 '+esc(' / '.join('T'+str(t) for t in example['eligible_tiers']))+'。高档可出不等于必出。</p>'
    body+='<p>测试供应仍是白底材，仅有15%火抗；可使用已有真实测试材料制作。赋魔、升格、补缀、普通重铸使用当前池，普通重铸能得到三抗后缀；校准只重掷已有族和档位内数值。</p>'
    witness=supply['ordinary_reforge_witness']
    body+=details('历史v37普通重铸见证','<p>显式历史装备词汇 '+value('reforge-vocabulary',supply['reforge_vocabulary'])+'；工艺seed '+value('reforge-seed',witness['seed'])+'；由CraftingRules.operation_plan导出以下真实合法结果，保留原三抗制作样本；当前池的同seed结果可不同，不是随机频率或每次成功保证。</p>'+lines('\n'.join(witness['plan']['definition']['affix_lines'])))
    body+='<p>伤害定向的合法目标只有 '+ '、'.join(link('affixes',family['id']) for family in supply['damage_target_families'])+'，全是后缀；因此最多再容纳两条抗性。六工艺费用、回收公式与校准seed规则保持，不新增抗性定向按钮。</p>'
    body+='<h3>旧装、历史池与存档</h3><p>'+esc(supply['migration'])+'。旧35/36存档仍映射历史装备词汇34，原接口显式设备词汇35/36仍拒绝；旧36不能注入新族。玩家主动制作才会选择当前池。</p><p><a href="../ELEMENTAL_DEFENSE_AFFIXES.zh-CN.md">完整供给说明与复验入口</a> · '+link('rules','equipment')+' · '+link('crafting','calibration_shard')+'</p>'
    return body


def defense_rating_affix_rule(data,link,facts,details):
    rule=data['defense_rating_affixes']
    def value(key,amount,ratio=False):
        return f'<strong data-defense-rating-value="{esc(key)}" data-value="{esc(amount)}">{percent(amount) if ratio else number(amount)}</strong>'
    body=facts([('底材',link('equipment',rule['base_id'])),('存档 / 装备词汇 / 源政策',value('save-version',rule['minimum_save_version'])+' / '+value('vocabulary',rule['vocabulary'])+' / '+value('source-policy',rule['source_policy'])),('当前词池',esc(rule['pool_id'])),('当前掉落配置',esc(rule['loot_profile_id']))])
    body+='<p>'+esc(rule['rating_order'])+'。原始护甲×(1+护甲提高)；原始闪避×(1+闪避提高+每5敏捷的1%)。这些示例未分配铁反射（闪转甲）；其转换与敏捷例外见 '+link('rules','iron_reflexes')+'。以下最终数值已经由实际角色计算，网页不再乘算。</p>'
    rows=[]
    for key,family in rule['new_families'].items():
        for tier,ranges in zip(family['tiers'],data['affixes'][key]['formatted_ranges']):
            stem=key+'-'+str(tier['tier'])
            rows.append('<tr><th>'+link('affixes',key)+'</th><td>T'+value(stem+'-tier',tier['tier'])+'</td><td>'+value(stem+'-level',tier['level'])+'</td><td>'+value(stem+'-min',tier['min'])+' ～ '+value(stem+'-max',tier['max'])+'</td><td>'+value(stem+'-weight',tier['weight'])+'</td></tr>')
    body+='<h3>固定值前缀与资格</h3><p>仅灰烬皮甲，端点包含，高物品等级仍可出低阶。白装无词缀，魔法至多1前1后，稀有4–6词至多3前3后；同族或同组不重复。实际显示为“护甲 +X”与“闪避值 +X”，整数点数不除100。</p><div class="table-scroll"><table><thead><tr><th>族</th><th>阶</th><th>最低物品等级</th><th>固定点数</th><th>候选权重</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<h3>五选三：资源不能全拿</h3><p>'+esc(rule['tradeoff'])+'。候选前缀：'+ '、'.join(link('affixes',key) for key in rule['prefix_families'])+'。</p>'
    labels={'white_base':'白底材','rootwell':'双防御 + 生命','deepwell':'双防御 + 魔力','lanternveil':'双防御 + 护盾'}
    rows=[]
    for key,example in rule['examples'].items():
        item,stats=example['definition']['stats'],example['stats']
        cells=[value(key+'-item-'+field,item.get(field,0)) for field in ['armour','evasion','max_health','max_mana','max_shield']]
        cells += [value(key+'-final-'+field,stats[field]) for field in ['armour','evasion']]
        rows.append('<tr><th>'+esc(labels[key])+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
    body+='<p>三件金装均用合法T3顶值，后缀同为三抗；默认贵族只有起点，保留真实默认角色与其他装备。前五列为本件含底材加值，后两列为最终角色值。</p><div class="table-scroll"><table><thead><tr><th>装备</th><th>护甲加值</th><th>闪避加值</th><th>生命加值</th><th>魔力加值</th><th>护盾加值</th><th>最终护甲</th><th>最终闪避</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+=details('合法词缀实例',''.join('<p>'+esc(labels[key])+'</p>'+lines('\n'.join(example['definition']['affix_lines'])) for key,example in rule['examples'].items() if key!='white_base'))
    body+='<h3>最低闪避已有效，最高档仍会被命中</h3><p>'+esc(rule['accuracy_scope'])+'。下表只改变灰烬皮甲的闪避前缀；角色只有职业起点，敌方命中率由实际AttackHitRules取得。</p>'
    class_names={0:'贵族',1:'野蛮人',2:'游侠',3:'女巫',4:'决斗者',5:'圣堂武僧',6:'暗影刺客'}
    rows=[]
    for row in rule['evasion_rows']:
        if (row['tier'],row['bound']) not in [(1,'min'),(3,'max')]:continue
        stem='evasion-'+str(row['class_id'])+'-'+str(row['tier'])+'-'+row['bound']
        cells=[value(stem+'-dexterity',row['base_dexterity']),value(stem+'-flat',row['flat_item_evasion']),value(stem+'-effective',row['effective_evasion']),value(stem+'-accuracy',row['enemy_accuracy']),value(stem+'-before',row['baseline_hit_chance'],True),value(stem+'-after',row['hit_chance'],True)]
        rows.append('<tr><th>'+class_names[row['class_id']]+' · T'+str(row['tier'])+('最低' if row['bound']=='min' else '最高')+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
    body+='<div class="table-scroll"><table><thead><tr><th>职业 / 阶</th><th>敏捷</th><th>装备闪避</th><th>最终闪避</th><th>敌人命中值</th><th>白装敌命中率</th><th>装备后敌命中率</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<h3>护甲取决于每次物理命中的大小</h3><p>'+esc(rule['budget_scope'])+'。以下护甲来自合法双防御胸甲的最终统计；三图III首领均含现有凶猛15%增伤，晴泉两响分别结算，不相加成一次命中。</p>'
    rows=[]
    for index,row in enumerate(rule['catalog_attacks']):
        stem='attack-'+str(index)
        rows.append('<tr><th>'+link('maps',row['map_id'])+' '+('III 首领' if row['tier']==3 else 'I 爬行怪')+'</th><td>'+value(stem+'-armour',row['armour'])+'</td><td>'+value(stem+'-before',row['before']['damage_total'])+'</td><td>'+value(stem+'-after',row['after']['damage_total'])+'</td></tr>')
    body+='<div class="table-scroll"><table><thead><tr><th>实际目录单次命中</th><th>护甲</th><th>零护甲伤害</th><th>护甲后伤害</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<p>'+esc(rule['scope'])+'。护甲减伤沿既有90%上限，随后仍走护盾→魔力先承伤→生命。躲开灰烬攻击会阻止该次附燃，已经存在的燃烧继续结算。</p>'
    rows=[]
    for key,case in rule['scope_hits'].items():
        rows.append('<tr><th>'+DAMAGE_NAMES[key]+'</th><td>'+value('scope-'+key+'-before',case['before']['damage_total'])+'</td><td>'+value('scope-'+key+'-after',case['after']['damage_total'])+'</td></tr>')
    body+=details('隔离护甲的五类100点命中','<p>只设护甲，抗性、护盾、魔力分担均为零；这项比较不先掷闪避。</p><table><thead><tr><th>类型</th><th>零护甲</th><th>T3顶值护甲</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table><p>同样100点原始燃烧仍造成 '+value('burn-damage',rule['burn_example']['damage_total'])+'；燃烧入口不接受护甲或闪避参数。</p>')
    body+='<h3>制作、来源与旧结果</h3><p>六工艺复用原按钮与费用。赋魔、升格、补缀和重铸可取得当前新族；校准仅重掷已有族与档位。伤害定向仍保证真实伤害后缀，不能同时保留三抗；没有防御定向按钮。</p><p>'+esc(rule['legacy_scope'])+'。</p><p>'+esc(rule['migration'])+'。</p><p>灰烬守卫的逻辑defense奖励读取当前池；显式历史池保持。'+link('rules','elemental_defense_affixes')+'保留原三抗预算，'+link('rules','elemental_resistance_caps')+'说明原始值与上限取舍。</p>'
    body+='<p><a href="../DEFENSE_RATING_AFFIXES.zh-CN.md">完整护甲闪避规则</a> · <a href="../qa/v062-reference/README.md">本批图鉴证据</a> · '+link('rules','source_defenses')+' · '+link('crafting','calibration_shard')+'</p>'
    return body


def iron_reflexes_rule(data,link,facts,details):
    rule=data['iron_reflexes']
    def source_lines(raw_lines):
        return '\n'.join(data['source_tree_localization']['lines'][line]['text'] for line in raw_lines)
    def value(key,amount,ratio=False):
        return f'<strong data-iron-reflexes-value="{esc(key)}" data-value="{esc(amount)}">{percent(amount) if ratio else number(amount)}</strong>'
    body=facts([('关键天赋',link('source_passives',rule['node']['id'])),('存档 / 装备词汇 / 源政策',value('save-version',rule['minimum_save_version'])+' / '+value('vocabulary',rule['equipment_vocabulary'])+' / '+value('source-policy',rule['source_policy']))])
    body+='<p>'+lines(source_lines(rule['node']['source_lines']))+'</p><p>最终护甲 = '+esc(rule['formula'])+'；最终闪避 = '+value('final-evasion',rule['evasion'])+'。</p>'
    body+='<p>'+esc(rule['base_scope'])+'。IA为护甲提高，IE为闪避提高，均不含敏捷；'+esc(rule['shared_rule'])+'。</p><p>'+esc(rule['dexterity_rule'])+'。</p>'
    body+='<h3>真实装备与最后一点天赋</h3><p>'+esc(rule['example_scope'])+'。'+esc(rule['budget_scope'])+'。</p>'
    labels={'dual_ratings':'双防御胸甲 · 12点','dual_ratings_hybrid':'双防御胸甲 + 双提高 · 14点','resources_hybrid':'旧生命三抗胸甲 + 双提高 · 14点'}
    rows=[]
    for key,example in rule['examples'].items():
        for state,label in [('before','未点'),('after','已点')]:
            row=example[state];prefix=key+'-'+state+'-'
            cells=[value(prefix+'points',row['points_spent']),value(prefix+'armour',row['profile']['armour']),value(prefix+'evasion',row['profile']['evasion']),value(prefix+'converted',row['profile']['converted_armour']),value(prefix+'dexterity',row['stats']['dexterity']),value(prefix+'accuracy',row['stats']['accuracy']),value(prefix+'enemy-hit-chance',row['enemy_hit_chance'],True)]
            rows.append('<tr><th>'+esc(labels[key])+' · '+label+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
    body+='<div class="table-scroll"><table><thead><tr><th>合法构筑</th><th>已花点数</th><th>最终护甲</th><th>最终闪避</th><th>护甲中的转换贡献</th><th>敏捷</th><th>命中值</th><th>敌方攻击命中率</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<p>敌方命中值取当前自然怪物100。双防御分支示例的敌方命中率由71%变为100%；旧胸甲的低闪避在该命中值下原本已是100%。转换贡献已经包含在最终护甲中，不能再加一次；闪避为0后敌方攻击仍沿既有规则判定。</p>'
    for key,example in rule['examples'].items():
        inputs=example['inputs'];after=example['after']
        cells=[('等级 / 点数预算',value(key+'-level',after['level'])+' / '+value(key+'-budget',after['points_spent'])),('A0 / E0',value(key+'-A0',inputs['base_armour'])+' / '+value(key+'-E0',inputs['base_evasion'])),('IA / IE / H',' / '.join(value(key+'-'+field,inputs[field],True) for field in ['armour_increased','evasion_increased','shared_increased']))]
        body+=details(labels[key]+' · 原始值、合法装备与路线',facts(cells)+lines('\n'.join(after['definition']['affix_lines']))+'<p>'+' → '.join(link('source_passives',node_id,node_id) for node_id in after['allocated'])+'</p><p>完整候选通过当前构筑与源树校验，未读写用户存档；路线清单保留分支，箭头表示分配顺序。</p>')
    body+='<p>双提高来自 '+link('source_passives',rule['hybrid_source']['id'])+' 的同一原句：'+lines(source_lines(rule['hybrid_source']['source_lines']))+'。各6%的两个提高在转换部分只计一次；不同原句的独立提高不互相抵消。</p>'
    example=rule['examples']['dual_ratings_hybrid'];rows=[]
    for amount in ['20','100','500']:
        cells=[value('physical-'+amount+'-'+state,example[state]['physical_hits'][amount]['damage_total']) for state in ['before','after']]
        rows.append('<tr><th>物理 '+amount+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
    for kind,label in [('fire','火'),('cold','冰'),('lightning','电')]:
        rows.append('<tr><th>'+label+' 100</th>'+''.join('<td>'+value('element-'+kind+'-'+state,example[state]['elemental_hits'][kind]['damage_total'])+'</td>' for state in ['before','after'])+'</tr>')
    rows.append('<tr><th>原始燃烧 100</th>'+''.join('<td>'+value('burn-'+state,example[state]['burn']['damage_total'])+'</td>' for state in ['before','after'])+'</tr>')
    body+='<h3>转换护甲影响哪些伤害</h3><p>'+esc(rule['scope'])+'。以下使用上表同一14点双防御胸甲角色的真实护甲与抗性，比较已获准命中的损伤，不把闪避概率乘进伤害。</p><div class="table-scroll"><table><thead><tr><th>独立输入</th><th>点前损伤</th><th>点后损伤</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+=''.join('<p>'+esc(rule[key])+'。</p>' for key in ['resource_rule','migration','complete_gate'])
    body+='<p><a href="../IRON_REFLEXES_RULES.zh-CN.md">完整铁反射（闪转甲）规则</a> · <a href="../qa/v064-reference/README.md">本批图鉴证据</a> · '+link('rules','defense_rating_affixes')+' · '+link('rules','source_defenses')+'</p>'
    return body


def zealots_oath_rule(data,link,facts,details):
    rule=data['zealots_oath']
    def value(key,amount,ratio=False):
        return f'<strong data-zealots-oath-value="{esc(key)}" data-value="{esc(amount)}">{percent(amount) if ratio else format(amount, ".10g")}</strong>'
    body=facts([('关键天赋',link('source_passives',rule['node']['id'])),('存档 / 装备词汇 / 源政策',value('save-version',rule['minimum_save_version'])+' / '+value('vocabulary',rule['equipment_vocabulary'])+' / '+value('source-policy',rule['source_policy']))])
    body+='<p>生命再生改为作用于能量护盾。每秒护盾再生 = '+esc(rule['formula'])+'；生命再生 = '+value('active-life-rate',0)+'。</p><p>'+esc(rule['raw_rule'])+'。</p>'
    body+='<h3>真实装备与最后一点天赋</h3><p>'+esc(rule['example_scope'])+'。下列结果直接读取实际Model的最终数值；页面不再乘算。</p>'
    body+=facts([('原始固定再生 R',value('raw-flat',rule['raw_flat_regeneration'])+' / 秒'),('原始百分比 P',value('raw-percent',rule['life_regeneration_fraction'],True))])
    labels={'before':'未点 · 守护长袍','after':'已点 · 守护长袍','changed_shield':'已点 · 改穿灯帷潮缄袍'}
    rows=[]
    for key in ['before','after','changed_shield']:
        row=rule['examples'][key]
        cells=[value(key+'-points',row['points_spent']),value(key+'-remaining',row['points_remaining']),value(key+'-max-life',row['stats']['max_health']),value(key+'-max-shield',row['stats']['max_shield']),value(key+'-life-rate',row['profile']['life_rate']),value(key+'-shield-rate',row['profile']['shield_rate']),value(key+'-recharge-rate',row['stats']['shield_recharge_rate']),value(key+'-recharge-delay',row['stats']['shield_recharge_delay'])]
        rows.append('<tr><th>'+esc(labels[key])+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
    body+='<div class="table-scroll"><table><thead><tr><th>合法构筑</th><th>已花点数</th><th>余点</th><th>最终生命</th><th>最终护盾</th><th>生命再生 / 秒</th><th>护盾再生 / 秒</th><th>独立充能 / 秒</th><th>充能等待秒数</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<p>'+esc(rule['tradeoff'])+'。</p><p>'+esc(rule['capacity_rule'])+'。</p>'
    source_rows=[]
    for node_id,source in rule['sources'].items():
        translated='\n'.join(data['source_tree_localization']['lines'][line]['text'] for line in source['source_lines'])
        source_rows.append('<p>'+link('source_passives',node_id,node_id)+'：'+lines(translated)+'</p>')
    body+=details('原始再生、护盾提高与合法装备', ''.join(source_rows)+'<p>31033同时供固定10与1.2%；32482另供0.6%，合计1.8%。38906提高护盾4%，智慧按既有取整规则先进入最终护盾。</p>'+''.join('<p>'+link('equipment',instance['base_id'])+'：'+lines('\n'.join(rule['examples']['changed_shield']['equipment'][slot]['definition']['affix_lines']))+'</p>' for slot,instance in [('body_armour',rule['instances']['tidebound_coat']),('amulet',rule['instances']['wayglass_token'])]))
    body+=details('主路线、独立分支与预算', '<p>等级 '+value('level',19)+'，总点数预算 '+value('budget',23)+'。主路线：'+' → '.join(link('source_passives',node_id,node_id) for node_id in rule['route'])+'</p><p>再生分支：'+'、'.join(link('source_passives',node_id,node_id) for node_id in rule['regeneration_branch'])+'；护盾分支：'+'、'.join(link('source_passives',node_id,node_id) for node_id in rule['shield_branch'])+'。分支是附加分配清单，不表示各分支之间有连续边。三个完整候选均通过实际构筑与源树校验，不读写用户存档。</p>')
    body+=''.join('<p>'+esc(rule[key])+'。</p>' for key in ['scope','timing','lifecycle','migration','complete_gate'])
    body+='<p><a href="../ZEALOTS_OATH_RULES.zh-CN.md">完整狂信者的誓约规则</a> · <a href="../qa/v065-reference/README.md">本批图鉴证据</a> · '+link('rules','source_recharge')+' · '+link('rules','character_rates')+' · <a href="source-tree-coverage.json">同源执行覆盖JSON</a></p>'
    return body


def ambush_rule(data,link,facts,details):
    rule=data['ambush']; policy=rule['policy']
    def value(key,amount):
        return f'<strong data-ambush-value="{esc(key)}" data-value="{esc(amount)}">{format(amount, ".10g")}</strong>'
    body=facts([('适配技能',' · '.join(link('skills',key) for key in rule['skills'])),('存档 / 源政策 / 装备词汇',value('save-version',rule['minimum_save_version'])+' / '+value('source-policy',rule['source_policy'])+' / '+value('vocabulary',rule['equipment_vocabulary'])),('布防',value('arming',policy['arming_seconds'])+' 秒'),('触发半径',value('trigger-radius',policy['trigger_radius'])),('未触发寿命',value('lifetime',policy['lifetime_seconds'])+' 秒'),('所有技能组共享上限',value('maximum-traps',policy['maximum_traps'])+' 枚'),('主命中倍率',value('hit-multiplier',policy['hit_multiplier'])),('魔力倍率',value('mana-multiplier',policy['mana_multiplier']))])
    body+=''.join('<p>'+esc(rule[key])+'。</p>' for key in ['placement','payment','snapshot','geometry'])
    body+='<h3>少量代表组合 · 加入伏击前后</h3><p>'+esc(rule['example_scope'])+'。每行左值是相同其他辅助下的普通直接施放，右值为加入伏击；数值直接来自生产编译结果。</p>'
    for skill,examples in rule['examples'].items():
        rows=[];status_rows=[]
        for mode,pair in examples.items():
            before,after=pair['before'],pair['after'];prefix=skill+'-'+mode
            others=[key for key in after['support_ids'] if key!='ambush']
            label='仅伏击' if not others else '伏击＋'+'＋'.join(data['supports'][key]['name'].removesuffix('辅助') for key in others)
            cells=[]
            for field,source in [('hit',lambda row:row['resolved']['total']),('mana',lambda row:row['mana']),('cooldown',lambda row:row['cooldown']),('radius',lambda row:row['recipe']['radius'])]:
                cells.append(value(prefix+'-'+field+'-before',source(before))+' → '+value(prefix+'-'+field+'-after',source(after)))
            cells.append(value(prefix+'-trigger-radius',after['trap_profile']['trigger_radius']))
            rows.append('<tr><th>'+esc(label)+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
            if 'shock_profile' in after:
                status=after['shock_profile']
                status_rows.append('<p>'+esc(label)+'：感电 '+value(prefix+'-shock-duration',status['duration'])+' 秒，后续命中承伤增加 '+value(prefix+'-shock-increased',status['hit_damage_taken_increased'])+'（比例）；本次施加命中不享受自己的新感电。</p>')
            if 'burn_profile' in after:
                status=after['burn_profile'];direct=status['roles']['direct']
                status_rows.append('<p>'+esc(label)+'：燃烧 '+value(prefix+'-burn-duration',status['duration'])+' 秒，每秒 '+value(prefix+'-burn-dps',direct['dps'])+' 火焰，完整持续 '+value(prefix+'-burn-total',direct['total'])+'；这些值已包含伏击对主命中火分量的影响。</p>')
                if 'proliferation' in status:
                    propagation=status['proliferation']
                    status_rows.append('<p>余烬死亡扩散半径 '+value(prefix+'-ember-radius',propagation['radius'])+'，最多 '+value(prefix+'-ember-targets',propagation['max_targets'])+' 个目标；沿原规则保留每秒伤害和剩余时长，不再传播。</p>')
        body+='<h4>'+link('skills',skill)+'</h4><div class="table-scroll"><table><thead><tr><th>辅助组合</th><th>防御前单击</th><th>魔力</th><th>冷却秒</th><th>爆发半径</th><th>触发半径</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'+''.join(status_rows)
    body+=''.join('<p>'+esc(rule[key])+'。</p>' for key in ['statuses','timing','lifecycle','damage_scope','provenance'])
    quote=rule['merchant_quote']
    body+='<p>正式宝石商人使用现有交易：'+value('merchant-cost',quote['cost']['calibration_shard'])+' 碎片；独立测试目录免费供应。原里程碑奖励仍是 '+value('reward-count',rule['normal_reward_definition_count'])+' 枚固定身份，符印伏击不插入其序列。</p><p>'+esc(rule['migration'])+'。</p>'
    body+='<p>'+link('supports','ambush')+' · '+link('rules','shock')+' · '+link('rules','burning')+' · '+link('rules','ember_proliferation')+' · <a href="../AMBUSH_SUPPORT_RULES.zh-CN.md">完整符印伏击规则</a> · <a href="../qa/v066-reference/README.md">本批图鉴验证</a></p>'
    return body


def inward_pull_rule(data,link,facts,details):
    rule=data['inward_pull'];policy=rule['policy']
    def value(key,amount):
        return f'<strong data-inward-pull-value="{esc(key)}" data-value="{esc(amount)}">{format(amount, ".10g")}</strong>'
    body=facts([('适配技能',' · '.join(link('skills',key) for key in rule['skills'])),('存档 / 源政策 / 装备词汇',value('save-version',rule['minimum_save_version'])+' / '+value('source-policy',rule['source_policy'])+' / '+value('vocabulary',rule['equipment_vocabulary'])),('初始冲量速度',value('impulse-speed',policy['impulse_speed'])),('魔力倍率',value('mana-multiplier',policy['mana_multiplier'])),('方向',esc(policy['direction'])+' · 朝本次真实爆发圆心')])
    body+=''.join('<p>'+esc(rule[key])+'。</p>' for key in ['scope','direction','movement','snapshot'])
    body+='<h3>四组代表组合 · 加入牵引前后</h3><p>'+esc(rule['example_scope'])+'。每行保持其他辅助相同，右值只新增牵引；数值直接读取生产编译结果。</p>'
    for skill,examples in rule['examples'].items():
        rows=[];status_rows=[]
        for mode,pair in examples.items():
            before,after=pair['before'],pair['after'];prefix=skill+'-'+mode
            others=[key for key in after['support_ids'] if key!='inward_pull']
            label='仅牵引' if not others else '牵引＋'+'＋'.join(data['supports'][key]['name'].removesuffix('辅助') for key in others)
            cells=[]
            for field,source in [('hit',lambda row:row['resolved']['total']),('mana',lambda row:row['mana']),('cooldown',lambda row:row['cooldown']),('radius',lambda row:row['recipe']['radius'])]:
                cells.append(value(prefix+'-'+field+'-before',source(before))+' → '+value(prefix+'-'+field+'-after',source(after)))
            cells.append(value(prefix+'-trigger-radius',after['trap_profile']['trigger_radius']) if 'trap_profile' in after else '直接施放')
            rows.append('<tr><th>'+esc(label)+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
            if 'shock_profile' in after:
                status=after['shock_profile']
                status_rows.append('<p>'+esc(label)+'：感电 '+value(prefix+'-shock-duration',status['duration'])+' 秒，后续命中承伤增加 '+value(prefix+'-shock-increased',status['hit_damage_taken_increased'])+'（比例），均与加入牵引前相同。</p>')
            if 'burn_profile' in after:
                status=after['burn_profile'];direct=status['roles']['direct']
                status_rows.append('<p>'+esc(label)+'：燃烧 '+value(prefix+'-burn-duration',status['duration'])+' 秒，每秒 '+value(prefix+'-burn-dps',direct['dps'])+' 火焰，完整持续 '+value(prefix+'-burn-total',direct['total'])+'；余烬扩散半径 '+value(prefix+'-ember-radius',status['proliferation']['radius'])+'、最多 '+value(prefix+'-ember-targets',status['proliferation']['max_targets'])+' 个目标，均与加入牵引前相同。</p>')
        body+='<h4>'+link('skills',skill)+'</h4><div class="table-scroll"><table><thead><tr><th>辅助组合</th><th>防御前单击</th><th>魔力</th><th>冷却秒</th><th>爆发半径</th><th>伏击触发半径</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'+''.join(status_rows)
    body+=''.join('<p>'+esc(rule[key])+'。</p>' for key in ['statuses','damage_scope','risk'])
    body+='<p>正式宝石商人售价 '+value('merchant-cost',rule['merchant_quote']['cost']['calibration_shard'])+' 碎片；独立测试目录免费供应。原里程碑奖励仍为 '+value('reward-count',rule['normal_reward_definition_count'])+' 枚固定身份，牵引不插入其序列。</p><p>'+esc(rule['migration'])+'。</p>'
    body+='<p>'+link('supports','inward_pull')+' · '+link('rules','ambush')+' · '+link('rules','shock')+' · '+link('rules','ember_proliferation')+' · <a href="../INWARD_PULL_SUPPORT.zh-CN.md">完整牵引辅助规则</a> · <a href="../qa/v067-reference/README.md">本批图鉴验证</a></p>'
    return body


def physical_fire_conversion_rule(data,link,facts,details):
    rule=data['physical_fire_conversion']
    def value(key,amount):
        return f'<strong data-physical-fire-value="{esc(key)}" data-value="{esc(amount)}">{format(amount, ".10g")}</strong>'
    body=facts([('既有火焰精通',value('effect-id',rule['effect_id'])+' · '+link('source_passives',rule['mastery_id'])),('最低存档 / 当前源政策 / 装备词汇',value('save-version',rule['minimum_save_version'])+' / '+value('source-policy',rule['source_policy'])+' / '+value('vocabulary',rule['equipment_vocabulary'])),('物理转火焰比例',value('fraction',rule['fraction'])+'（40%）')])
    body+=''.join('<p>'+esc(rule[key])+'。</p>' for key in ['assembly','lineage','focus','defense'])
    body+='<h3>五组实际编译对照 · 仅切换精通</h3><p>'+esc(rule['example_scope'])+'。护甲靶为护甲500且零抗性；火抗靶为火抗75%且零护甲；均无护盾、生命10000。两个靶分别说明防御取舍，不代表固定怪物模板。</p>'
    role_labels={'direct':'直接命中','projectile':'普通投射物','parent':'龙卷母箭','child':'龙卷子箭','secondary':'纯火独立爆炸'}
    for key,pair in rule['examples'].items():
        before,after=pair['states']['before'],pair['states']['after']
        body+='<h4>'+esc(pair['name'])+'</h4><p>'+link('equipment',pair['base_id'])+' · '+(' · '.join(link('supports',sid) for sid in pair['supports']) or '无辅助')+'</p>'
        rows=[];provenance=[]
        for role in before['hits']:
            prefix=key+'-'+role;cells=[]
            for field in ['physical','fire']:
                cells.append(' → '.join(value(prefix+'-'+field+'-'+state,pair['states'][state]['hits'][role]['resolved']['components'].get(field,0)) for state in ['before','after']))
            for target in ['armour','fire_resistance']:
                cells.append(' → '.join(value(prefix+'-'+target+'-'+state,pair['states'][state]['hits'][role]['defended'][target]['settlement']['damage_total']) for state in ['before','after']))
            rows.append('<tr><th>'+esc(role_labels[role])+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
            hit=after['hits'][role];packet=hit['packet']
            if 'conversion' in packet:
                split=packet['conversion'];assembly=packet['assembly']
                provenance.append('<p>'+esc(role_labels[role])+'：组装物理 '+value(prefix+'-source',split['source_base'])+' = 固有 '+value(prefix+'-intrinsic',assembly['intrinsic'].get('physical',0))+' + 外部附加 '+value(prefix+'-added',assembly['added'].get('physical',0))+' + 局部武器贡献 '+value(prefix+'-weapon',assembly.get('weapon',{}).get('contribution',{}).get('physical',0))+'；残余物理 '+value(prefix+'-remaining',split['remaining_base'])+'，转换火焰 '+value(prefix+'-converted',split['converted_base'])+'。</p>')
                part_rows=[]
                for detail in hit['resolved']['details']:
                    for i,part in enumerate(detail['parts']):
                        pkey=prefix+'-'+detail['type']+'-part'+str(i)
                        part_rows.append('<tr><th>'+esc(' → '.join(DAMAGE_NAMES[t] for t in part['lineage']))+'</th>'+''.join('<td>'+value(pkey+'-'+field,part[field])+'</td>' for field in ['base','increased','more','before_defense'])+'<td>'+esc(', '.join(str(index)+': '+sid for index,sid in zip(part['modifier_indices'],part['modifiers'])))+'</td></tr>')
                provenance.append('<div class="table-scroll"><table><thead><tr><th>来源 → 最终类型</th><th>基底</th><th>increased合计</th><th>MORE乘积</th><th>防御前</th><th>modifier数组下标及id</th></tr></thead><tbody>'+''.join(part_rows)+'</tbody></table></div>')
        body+='<div class="table-scroll"><table><thead><tr><th>每次成功命中 · 未点 → 已点</th><th>防御前物理</th><th>防御前火焰</th><th>护甲靶实际伤害</th><th>火抗靶实际伤害</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
        body+='<p>耗魔 '+value(key+'-mana',after['mana'])+'、冷却 '+value(key+'-cooldown',after['cooldown'])+' 秒，选择精通前后相同；普攻两值为0，实际攻击节奏仍取角色攻速。剩余天赋点 '+value(key+'-points-before',before['points_remaining'])+' → '+value(key+'-points-after',after['points_remaining'])+'。</p>'
        if 'burn_profile' in after:
            burn_rows=[]
            for role in after['burn_profile']['roles']:
                prefix=key+'-burn-'+role
                burn_rows.append('<tr><th>'+esc(role_labels[role])+'</th>'+''.join('<td>'+' → '.join(value(prefix+'-'+field+'-'+state,pair['states'][state]['burn_profile']['roles'][role][field]) for state in ['before','after'])+'</td>' for field in ['fire_before_defense','dps','total'])+'</tr>')
            body+='<p>原有燃烧持续 '+value(key+'-burn-duration',after['burn_profile']['duration'])+' 秒；以下为不暴击、零火抗下理论燃烧预算，实际敌人火抗仍在每次结算生效。</p><div class="table-scroll"><table><thead><tr><th>既有点燃角色</th><th>唯一防御前火焰输入</th><th>每秒</th><th>完整持续总量</th></tr></thead><tbody>'+''.join(burn_rows)+'</tbody></table></div>'
        body+=details('组装、分量来源与逐条modifier证据',''.join(provenance)+'<p>最终details每种类型仅一行；内部parts保留lineage、base、increased、more、before_defense、modifiers、modifier_indices。原生火焰和转换火焰各自计算后才合并；这些值来自实际解析器。</p>')
    body+=''.join('<p>'+esc(rule[key])+'。</p>' for key in ['burn','leech','snapshot','availability','migration','bounds'])
    body+=details('既有入口、原始路线与完整英文', '<p>'+esc(rule['source_line'])+'</p><p>全部入口：'+'、'.join(link('source_passives',node_id,node_id) for node_id in rule['entrances'])+'。</p><p>当前可达组的显著天赋 → 精通：'+'；'.join(link('source_passives',gateway,gateway)+' → '+link('source_passives',mastery,mastery) for mastery,gateway in rule['reachable_gateways'].items())+'。</p><p>本页5级野蛮人路线：'+' → '.join(link('source_passives',node_id,node_id) for node_id in rule['route']+[rule['mastery_id']])+'；预算 '+value('point-budget',rule['point_budget'])+' 点。所有候选完整通过Canonical与源树校验，保存次数为0。</p>')
    body+='<p><a href="../PHYSICAL_FIRE_CONVERSION.zh-CN.md">完整物理转火焰合同</a> · <a href="../qa/v069-reference/README.md">本批图鉴验证</a> · <a href="source-tree-coverage.json">当前同源执行覆盖JSON</a> · '+link('rules','source_fire_dot')+' · '+link('rules','source_faster_burn')+' · '+link('rules','source_leech')+'</p>'
    return body


def precise_technique_rule(data,link,facts,details):
    rule=data['precise_technique']
    def value(key,amount):
        return f'<strong data-precise-value="{esc(key)}" data-value="{esc(amount)}">{format(amount, ".10g")}</strong>'
    body=facts([('关键天赋',link('source_passives','63620')),('最低存档 / 当前源政策 / 装备词汇',value('save-version',rule['minimum_save_version'])+' / '+value('source-policy',rule['source_policy'])+' / '+value('vocabulary',rule['equipment_vocabulary'])),('满足严格条件时的攻击MORE',value('attack-more',rule['attack_more'])+'（40%）')])
    body+=''.join('<p>'+esc(rule[key])+'。</p>' for key in ['condition','scope','critical_cost','early_tradeoff'])
    body+='<h3>三个通过实际Main的冻结构筑</h3><p>'+esc(rule['example_scope'])+'。</p>'
    names={'selected-above':'已分配 · 最终命中值高于最大生命','selected-below':'已分配 · 最终命中值低于最大生命','refunded':'已退款 · 恢复既有暴击规则'}
    roles={'direct':'直接命中','projectile':'普通投射物','parent':'龙卷母箭','child':'龙卷子箭','secondary':'独立爆炸'}
    for name in ['selected-above','selected-below','refunded']:
        row=rule['examples'][name];stats=row['stats'];profile=row['casts']['basic']['compiled'].get('precise_technique_profile',{})
        body+='<h4>'+names[name]+'</h4>'+facts([('最终命中值A',value(name+'-accuracy',stats['accuracy'])),('最终最大生命L',value(name+'-max-health',stats['max_health'])),('攻击MORE',value(name+'-attack-more',profile.get('attack_more',0))),('始终不能暴击','是' if profile.get('cannot_deal_critical_strikes',False) else '否'),('保存次数',value(name+'-save-attempts',row['save_attempts']))])
        hits=[]
        for skill in ['basic','cleave','tornado']:
            cast=row['casts'][skill];compiled=cast['compiled']
            for role,hit in cast['hits'].items():
                key=name+'-'+skill+'-'+role;cells=[]
                for dtype in ['physical','fire']:
                    cells.append(value(key+'-'+dtype,hit['resolved']['components'].get(dtype,0)))
                cells += [value(key+'-total',hit['resolved']['total']),value(key+'-critical-chance',hit['critical']['chance']),value(key+'-critical-multiplier',hit['critical']['multiplier'])]
                hits.append('<tr><th>'+('普通攻击' if skill=='basic' else link('skills',skill))+' / '+roles[role]+'</th>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
            body+=details(('普通攻击' if skill=='basic' else data['skills'][skill]['name'])+' · 真实编译预览','<p>'+esc(cast['summary'])+'</p><p>'+lines(cast['details'])+'</p><p>本次命中profile：'+esc(json.dumps(compiled.get('precise_technique_profile',{}),ensure_ascii=False,sort_keys=True))+'</p>')
        body+='<div class="table-scroll"><table><thead><tr><th>成功且不暴击的命中</th><th>物理</th><th>火焰</th><th>合计</th><th>最终暴击率（比例）</th><th>潜在暴击倍率</th></tr></thead><tbody>'+''.join(hits)+'</tbody></table></div>'
        equipment=''.join('<p>'+esc(SLOTS.get(slot,slot))+'：'+esc(item['definition']['name'])+' · '+esc(item['uid'])+'</p>' for slot,item in row['equipment'].items())
        route=' → '.join(link('source_passives',node,node) for node in row['talents']['allocated'])
        body+=details('实际构筑、来源文件与只读校验',equipment+'<p>原分配：'+route+'。</p><p><a href="../'+esc(row['fixture'].removeprefix('docs/'))+'">实际Main原始构筑</a> · <a href="../'+esc(row['expected_fixture'].removeprefix('docs/'))+'">同场景stats与compiled预期</a></p><p>原构筑SHA256：'+esc(row['fixture_sha256'])+'；完整候选校验通过、全部三种cast与实际Main预期相同、读取前后原文件字节保持。</p>')
    body+=''.join('<p>'+esc(rule[key])+'。</p>' for key in ['snapshot','availability','migration','bounds'])
    body+=details('完整原始多行英文','<p>'+lines('\n'.join(rule['node']['source_lines']))+'</p>')
    body+='<p><a href="../PRECISE_TECHNIQUE.zh-CN.md">精准技艺完整合同</a> · <a href="../qa/v070-reference/README.md">本批图鉴验证</a> · <a href="../qa/v070-gameplay/README.md">实际Main验证</a> · '+link('rules','resolute_technique')+' · '+link('rules','physical_fire_conversion')+' · '+link('rules','source_critical')+'</p>'
    return body


def frost_lock_rule(data,link,facts,details):
    rule=data['frost_lock'];policy=rule['policy'];examples=rule['examples']
    def value(key,amount):
        return f'<strong data-frost-lock-value="{esc(key)}" data-value="{esc(amount)}">{format(amount, ".10g")}</strong>'
    body=facts([('最低存档版本',value('save-version',rule['minimum_save_version'])),('装备词汇 / 源政策',value('vocabulary',rule['equipment_vocabulary'])+' / '+value('source-policy',rule['source_policy'])),('主命中 / 魔力倍率',value('hit-multiplier',policy['hit_multiplier'])+' / '+value('mana-multiplier',policy['mana_multiplier'])),('共享状态上限',value('max-targets',rule['max_targets'])+' 个怪物ID'),('互斥辅助',link('supports','lingering_chill'))])
    body+='<p>'+esc(rule['eligibility'])+'。</p><p>'+esc(rule['admission'])+'。</p>'
    rows=''
    for rarity,label in [('normal','普通'),('magic','魔法'),('rare','稀有'),('boss','首领')]:
        state=rule['timing']['states'][rarity]
        rows+='<tr><th>'+label+'</th><td>'+value(rarity+'-duration',policy['duration_by_rarity'][rarity])+'</td><td>'+value(rarity+'-immune-until',state['immune_until'])+'</td></tr>'
    body+='<h3>一次准入后的状态与时间</h3><p>以成功冻结为0秒；到期即解冻，再经过 '+value('immunity',policy['immunity_seconds'])+' 秒免疫才可重新冻结。期间后续命中不刷新或叠加。</p><div class="table-scroll"><table><thead><tr><th>目标</th><th>冻结秒数</th><th>再次可冻结时刻（秒）</th></tr></thead><tbody>'+rows+'</tbody></table></div>'
    body+='<p>'+esc(rule['paused'])+'。</p><p>'+esc(rule['continuing'])+'。</p><p>'+esc(rule['expiry'])+'。</p>'
    split=rule['timing']['partial_frame']
    body+='<p>普通敌人示例：从 '+value('frame-start',split['start'])+' 秒开始的 '+value('frame-delta',split['delta'])+' 秒帧，冻结前缀为 '+value('frame-prefix',split['frozen_prefix'])+' 秒，只推进余下 '+value('frame-active',split['active_delta'])+' 秒；原圆心与攻击进度接续。</p>'
    rows=''
    for key,label in [('plain_frost','同快照无辅助'),('frost','实际霜锁技能组')]:
        row=examples[key];cast=row['compiled']
        rows+='<tr><th>'+label+'</th><td>'+value(key+'-hit',row['resolved']['total'])+'</td><td>'+value(key+'-mana',cast['mana'])+'</td><td>'+value(key+'-count',cast['initial_count'])+'</td><td>'+value(key+'-pierce',cast['recipe']['pierce'])+'</td><td>'+value(key+'-slow',cast['recipe']['slow'])+'</td><td>'+value(key+'-cooldown',cast['cooldown'])+'</td></tr>'
    body+='<h3>通过实际Main的同源构筑</h3><p>'+esc(rule['example_scope'])+'。</p><div class="table-scroll"><table><thead><tr><th>状态</th><th>主命中</th><th>魔力</th><th>投射数</th><th>穿透</th><th>原减速秒</th><th>冷却秒</th></tr></thead><tbody>'+rows+'</tbody></table></div>'
    body+=details('施放快照与原命中预览','<p>'+esc(rule['snapshot'])+'。</p><p>'+esc(examples['frost']['summary'])+'</p><p>'+lines(examples['frost']['details'])+'</p>')
    body+='<p>正式商人 '+value('price',rule['merchant_quote']['cost']['calibration_shard'])+' 校准碎片；测试动态供应可取得。'+esc(rule['migration'])+'。</p><p>'+esc(rule['cleanup'])+'。</p>'
    body+='<p><a href="../'+esc(rule['fixture'].removeprefix('docs/'))+'">完整合法构筑</a> · <a href="../'+esc(rule['expected_fixture'].removeprefix('docs/'))+'">Main完整预期</a> · <a href="../FROST_LOCK_SUPPORT.zh-CN.md">霜锁辅助说明</a> · <a href="../qa/v073-reference/README.md">本批资料验证</a></p>'
    body+='<p>'+link('skills','frost')+' · '+link('supports','frost_lock')+' · '+link('supports','lingering_chill')+' · '+link('town_services','skill_merchant')+'。'+esc(rule['bounds'])+'。</p>'
    return body


def glove_ring_affix_rule(data,link,facts,details):
    rule=data['glove_ring_affixes']
    def value(key,amount,ratio=False):
        return f'<strong data-glove-ring-value="{esc(key)}" data-value="{esc(amount)}">{percent(amount) if ratio else format(amount,".10g")}</strong>'
    body=facts([('存档 / 装备词汇 / 源政策',value('save-version',rule['minimum_save_version'])+' / '+value('vocabulary',rule['equipment_vocabulary'])+' / '+value('source-policy',rule['source_policy'])),('既有槽位 / 随机底材 / 固定装备',value('slots',rule['existing_slot_count'])+' / '+value('bases',rule['existing_random_base_count'])+' / '+value('fixed',rule['existing_fixed_item_count']))])
    body+='<p>'+esc(rule['supply_scope'])+'。</p><p>'+esc(rule['accuracy_scope'])+'。</p>'
    rows=[]
    for key,family in rule['new_families'].items():
        rows.append('<tr><th>'+link('affixes',key)+'</th><td>'+TYPES[family['kind']]+'</td><td>'+link('equipment',family['allowed_base_ids'][0])+'</td>'+''.join('<td>'+esc(r['min'])+' ～ '+esc(r['max'])+'</td>' for r in data['affixes'][key]['formatted_ranges'])+'</tr>')
    body+='<div class="table-scroll"><table><caption>沿用等级1/8/16、权重100/60/30；高等级仍能掷到低阶</caption><thead><tr><th>词族</th><th>类型</th><th>唯一底材</th><th>T1</th><th>T2</th><th>T3</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div><p>'+esc(rule['prefix_tradeoff'])+'。</p>'
    probes=rule['accuracy_probes'];rows=[]
    for row in probes['tiers']:
        key='t'+str(int(row['tier']));ends=row['endpoints']
        rows.append('<tr><th>T'+str(int(row['tier']))+'</th><td>'+value(key+'-flat-min',ends['min']['flat_accuracy'])+' ～ '+value(key+'-flat-max',ends['max']['flat_accuracy'])+'</td><td>'+value(key+'-accuracy-min',ends['min']['accuracy'])+' ～ '+value(key+'-accuracy-max',ends['max']['accuracy'])+'</td><td>'+value(key+'-chance-min',ends['min']['chance'],True)+' ～ '+value(key+'-chance-max',ends['max']['chance'],True)+'</td></tr>')
    body+='<h3>对雾羽掠行体的命中收益</h3><p>隔离探针以最终命中A='+value('baseline-accuracy',probes['baseline_accuracy'])+'、闪避'+value('evasion',probes['evasion'])+'为起点；原命中率'+value('baseline-chance',probes['baseline_chance'],True)+'，以下只增加一条精瞄，不含命中提高。结果来自实际AttackHitRules；命中率变化不是伤害MORE或DPS。</p><div class="table-scroll"><table><thead><tr><th>档位</th><th>固定命中</th><th>最终命中</th><th>命中率</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<p>'+esc(rule['ring_tradeoff'])+'。</p><p>'+esc(rule['cap_scope'])+'。</p><h3>五个通过实际Main的原构筑</h3>'
    names={'precise-equal':'精准条件 · 命中等于生命','precise-above':'精准条件 · 命中高于生命','glove-finesse':'精瞄与源命中提高','rings-triple-default':'双戒加胸甲 · 默认上限','rings-source-cap83':'相同抗性供给 · 源上限83%'}
    for name in names:
        row=rule['examples'][name];stats=row['stats'];profile=row['casts']['basic'].get('precise_technique_profile',{});res=row['resistance']
        body+='<h4>'+names[name]+'</h4>'+facts([('最终命中A / 最大生命L',value(name+'-accuracy',stats['accuracy'])+' / '+value(name+'-life',stats['max_health'])),('精准攻击MORE',value(name+'-more',profile.get('attack_more',0),True)),('保存次数',value(name+'-saves',row['save_attempts']))])
        if name.startswith('rings-'):
            body+='<div class="table-scroll"><table><thead><tr><th>元素</th><th>原始抗性</th><th>最大上限</th><th>有效抗性</th></tr></thead><tbody>'+''.join('<tr><th>'+DAMAGE_NAMES[element]+'</th>'+''.join('<td>'+value(name+'-'+element+'-'+field,res[field][element],True)+'</td>' for field in ['raw_resistances','maximum_resistances','effective_resistances'])+'</tr>' for element in ['fire','cold','lightning'])+'</tbody></table></div>'
        equipment=''.join('<p>'+esc(SLOTS.get(slot,slot))+'：'+esc(item['definition']['name'])+' · '+esc(item['uid'])+'<br>'+lines('\n'.join(item['definition'].get('affix_lines',[])))+'</p>' for slot,item in row['equipment'].items())
        body+=details('实际装备与Main只读证据',equipment+'<p><a href="../'+esc(row['fixture'].removeprefix('docs/'))+'">Main原始构筑</a> · <a href="../'+esc(row['expected_fixture'].removeprefix('docs/'))+'">stats、三种cast与抗性预期</a>；SHA256 '+esc(row['fixture_sha256'])+'。全构筑校验、全部预期精度对照与读取前后字节保全均通过。</p>')
    body+='<p>精准技艺仍要求A严格大于最大生命；等于时没有攻击MORE，已分配时始终禁暴击。增加命中不授予坚决技艺，也不提高最大抗性。</p><p>'+esc(rule['migration'])+'。</p><p>'+esc(rule['bounds'])+'。</p>'
    body+='<p>'+link('rules','precise_technique')+' · '+link('rules','elemental_resistance_caps')+' · '+link('monsters','mist_skitter')+' · <a href="../GLOVE_RING_AFFIXES.zh-CN.md">手套与戒指合同</a> · <a href="../qa/v072-reference/README.md">本批资料验证</a></p>'
    return body


def mist_skitter_hint(monster, link):
    budget=monster['encounter_budget'];policy=budget['policy']
    def value(key, amount, ratio=False):
        return f'<strong data-mist-value="{esc(key)}" data-value="{esc(amount)}">{percent(amount) if ratio else number(amount)}</strong>'
    eligible=[row for row in budget['formal_profiles'] if row['eligible']]
    waves=' / '.join('第'+str(row['tier'])+'档（波次'+str(row['wave'])+'）' for row in eligible)
    body='<p>高闪避·较脆：闪避 '+value('evasion',monster['source_ratings']['evasion'])+'；生命为同波普通'+link('monsters',budget['baseline_template'])+'的 '+value('health-multiplier',policy['health_multiplier'],True)+'，攻击基底为 '+value('damage-multiplier',policy['damage_multiplier'],True)+'。移动、体型、攻击频率和原奖励资格保持。</p>'
    body+='<p>仅正式'+link('maps','sunwell_terrace')+'的'+esc(waves)+'：全部原编排与巡逻替换完成后，每据点首个仍为普通白色掠行体的名额才替换，最多 '+value('maximum-per-camp',budget['maximum_per_camp'])+' 只/据点、'+value('maximum-per-map',budget['maximum_per_map'])+' / '+value('map-root-count',budget['map_root_count'])+' 根怪；没有合格名额则为0，雷纹巡逻优先，可整图为0。第一档、其他地图及旧固定波次'+value('fixed-test-wave',budget['fixed_test_wave'])+'的测试地图不出现；不替换蓝金怪、首领或死亡后代。</p>'
    rows=[]
    for row in budget['accuracy_probes']:
        key=str(int(row['accuracy']))
        rows.append('<tr><th scope="row">'+value('accuracy-'+key,row['accuracy'])+'</th><td>'+value('baseline-chance-'+key,row['baseline_chance'],True)+'</td><td>'+value('mist-chance-'+key,row['mist_chance'],True)+'</td></tr>')
    body+='<div class="table-scroll"><table><caption>现有命中规则的独立输入探针；并非构筑排行或伤害增幅</caption><thead><tr><th>命中值</th><th>原掠行体 · 闪避 '+value('baseline-evasion',budget['baseline_evasion'])+'</th><th>雾羽掠行体命中率</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
    body+='<p>'+link('rules','resolute_technique')+'仍以不能暴击换取 '+value('resolute-chance',budget['accuracy_probes'][0]['resolute_chance'],True)+' 闪避准入；'+link('rules','precise_technique')+'不会绕过闪避。法术仍不进行攻击闪避，距离、墙体、出生保护及后续防御保持。没有额外随机抽签或掉落加成。<a href="../MIST_SKITTER.zh-CN.md">出现与预算合同</a></p>'
    return body


def build(data, art):
    records = []
    by_id = {}
    localization = data['source_tree_localization']
    localized_nodes = localization['nodes']
    def source_lines(raw_lines):
        return '\n'.join(localization['lines'][line]['text'] for line in raw_lines)
    art_by_id = {(('fixed_items' if x.get('entry_type') == 'fixed_item' else x['category']),x['id']): x for x in art.get('entries',[])}
    def link(cat,key,label=None):
        label = label or (RULE_TITLES.get(key,key) if cat == 'rules' else localized_nodes[key]['name'] if cat=='source_passives' else data.get(cat,{}).get(key,{}).get('name',key))
        return f'<a href="#{anchor(cat,key)}">{esc(label)}</a>'
    def equipped_links(cfg):
        instances=cfg.get('equipment_instances',{})
        return ' · '.join(link('equipment',instances[i]['base_id']) if i in instances else link('fixed_items',i) for i in cfg['equipped'].values())
    def links(cat,ids): return ' · '.join(link(cat,i) for i in ids) or '无'
    def details(title,body): return f'<details><summary>{esc(title)}</summary><div class="detail-body">{body}</div></details>'
    def facts(items): return '<dl class="facts">'+''.join(f'<div><dt>{esc(k)}</dt><dd>{v}</dd></div>' for k,v in items)+'</dl>'
    def tags(values): return '<div class="tags">'+''.join(f'<span>{esc(x)}</span>' for x in values)+'</div>'
    def add(cat,key,name,summary,body='',facet='',status='implemented',meta='',related='',search_aliases=''):
        aid = anchor(cat,key)
        img = art_by_id.get((cat,key))
        image = f'<img class="emblem" src="art/{esc(img["file"])}" width="64" height="64" alt="" loading="lazy">' if img else '<span class="fallback-emblem" aria-hidden="true">✧</span>'
        if cat=='supports' and key=='ignite':
            image=f'<img class="emblem" src="{esc(data["burning"]["icon_file"])}" width="64" height="64" alt="" loading="lazy">'
        elif cat=='supports' and key=='ember_proliferation':
            image=f'<img class="emblem" src="{esc(data["ember_proliferation"]["icon_file"])}" width="64" height="64" alt="" loading="lazy">'
        elif cat=='supports' and key=='shock':
            image=f'<img class="emblem" src="{esc(data["shock"]["icon_file"])}" width="64" height="64" alt="" loading="lazy">'
        elif cat=='supports' and key=='ambush':
            image=f'<img class="emblem" src="{esc(data["ambush"]["icon_file"])}" width="64" height="64" alt="" loading="lazy">'
        elif cat=='supports' and key=='inward_pull':
            image=f'<img class="emblem" src="{esc(data["inward_pull"]["icon_file"])}" width="64" height="64" alt="" loading="lazy">'
        elif cat=='supports' and key=='frost_lock':
            image=f'<img class="emblem" src="{esc(data["frost_lock"]["icon_file"])}" width="64" height="64" alt="" loading="lazy">'
        elif cat=='equipment' and key=='forgeblade':
            image=f'<img class="emblem" src="{esc(data["forgeblade"]["icon_file"])}" width="64" height="64" alt="" loading="lazy">'
        badges = {'implemented':'已实现','research':'研究资料','planned':'尚未实现'}
        inner = f'<div class="entry-heading">{image}<div><span class="status {status}">{badges[status]}</span><h2><a href="#{aid}">{esc(name)}</a></h2><div class="entry-id">{esc(key)}</div></div></div>'
        if meta: inner += f'<div class="metadata">{meta}</div>'
        inner += f'<p class="summary">{lines(summary)}</p>{body}'
        if related: inner += f'<div class="related"><span>关联条目</span> {related}</div>'
        searchable = ' '.join([name,key,summary,html.unescape(__import__('re').sub('<[^>]+>',' ',body)),facet])
        if search_aliases: searchable += ' ' + search_aliases
        record = {'id':aid,'cat':cat,'facet':facet,'status':status,'search':searchable.casefold()}
        records.append(record); by_id[aid] = record
        return f'<article class="entry{" defense-entry" if cat in ["defenses", "weapon_stages"] else ""}" id="{aid}" data-category="{cat}" tabindex="-1">{inner}</article>'
    cards = []
    for key,s in data['skills'].items():
        compatible = s['compatible_supports']
        panels = ''
        for config in ['fresh','full_tornado','local_normal','local_max']:
            examples=s['examples'][config]
            cfg = data['configurations'][config]
            body = f'<p>{equipped_links(cfg)}；仅起点，无镶嵌珠宝。角色基础伤害标量 {number(cfg["stats"]["damage"])}。</p>'
            if 'weapon_definition' in cfg:
                body+='<p>'+esc(cfg['weapon_definition']['weapon_damage_summary'])+'</p>'+details('实例与合法掷值',lines('\n'.join(cfg['weapon_definition']['affix_lines'])) or '<p>普通底材，无词缀。</p>')
            for example in examples:
                body += '<div class="example"><h4>'+('无辅助' if not example['supports'] else links('supports',example['supports']))+'</h4>'
                geometry = [('半径',number(example['recipe']['radius'])),('面积倍率',number(example['recipe'].get('area_multiplier',1.0)))] if 'area_hit' in s['capabilities'] else [('最多目标数',number(example['recipe']['hit']['bounce_count'])),('续跳距离',number(example['recipe']['followup_range']))] if key=='chain' else [('初始投射物',number(example['initial_count']))] if example['initial_count'] else []
                body += facts([('消耗',f'{number(example["mana"])} 魔力'),('冷却',f'{number(example["cooldown"])} 秒')]+geometry)
                body += '<p>'+esc(example['summary'])+'</p>'+details('分量与组装过程', '<p>'+lines(example['details'])+'</p>')
                target=data['known_target']
                defended_rows=''.join(f'<tr><th scope="row">{esc(p["label"])}</th><td>{number(p["resolved"]["total"])}</td><td>{number(p["known_target_resolved"]["total"])}</td><td>{number(p["known_target_settlement"]["health_lost"])}</td></tr>' for p in example['packets'] if p['active'])
                if defended_rows:
                    target_body=f'<p>目标为第 {target["wave"]} 波的 {link("monsters",target["template_id"])}：火抗 {percent(target["defense_profile"]["effective_resistances"]["fire"])}、护盾 {number(target["shield"])}、生命 {number(target["health"])}。每一行都从该目标的完整初始资源独立结算，不相加成总伤害。</p>'
                    target_body+='<div class="table-scroll"><table><thead><tr><th>命中</th><th>防御前</th><th>抗性后</th><th>生命扣减</th></tr></thead><tbody>'+defended_rows+'</tbody></table></div>'
                    body+=details('已知目标 · '+data['monsters'][target['template_id']]['name']+'受击示例',target_body)
                body+='</div>'
            panels += details(cfg['name']+' · 编译示例',body)
        body = skill_delivery_diagram(key,s)+facts([('原始消耗',number(s['mana'])+' 魔力'),('原始冷却',number(s['cooldown'])+' 秒'),('最低保存版本',number(s.get('minimum_save_version',14))),('可装配辅助',links('supports',compatible))])+panels
        affected = [i for i,f in data['affixes'].items() if key in f.get('affected_skills',[])]
        related = link('rules','damage')+' · '+link('rules','supports')+(' · '+link('rules','physical_fire_conversion') if key in ['physical_focus','fire_focus','ignite','ember_proliferation'] and 'physical_fire_conversion' in data else '')+((' · '+links('affixes',affected)) if affected else '')
        if 'ambush' in compatible:
            body+='<p>符印伏击改为脚下预置，成功放置时支付魔力；触发后才命中。'+link('rules','ambush','查看伏击、感电、燃烧与范围组合的代表编译示例')+'。</p>'
            related+=' · '+link('rules','ambush')
        if 'inward_pull' in compatible:
            body+='<p>牵引辅助把原击退冲量反转为朝本次真实爆发圆心，魔力乘1.20。'+link('rules','inward_pull','查看牵引与伏击冻结快照的代表编译示例')+'。</p>'
            related+=' · '+link('rules','inward_pull')
        if 'frost_lock' in compatible:
            body+='<p>霜锁辅助提供短冻结窗口，与寒意延长互斥；保留原3秒移动减缓。'+link('rules','frost_lock','查看冻结、免疫与原攻击接续')+'。</p>'
            related+=' · '+link('rules','frost_lock')
        cards.append(add('skills',key,s['name'],s['description'],body,'投射物' if 'projectile_hit' in s['capabilities'] else '其他技能',related=related))
    for key,s in data['supports'].items():
        eligible = [i for i,x in data['skills'].items() if key in x['compatible_supports']]
        body = facts([('可装配技能',links('skills',eligible)),('能力要求',esc(' / '.join(CAPABILITIES.get(c,c) for c in s['requires']))),('规则来源','本游戏原创；运行版本 '+esc(data['game_version']))])
        if key == 'pierce':
            body += piercing_diagram(data['projectile_support_examples'],data['skills'])
        body += support_program_diagram(data['support_program_examples'][key],data['skills'],details)
        if key in ['breadth','concentrate']:
            body += area_diagram(data['area_support_examples'],data['skills'])
        related=link('rules','supports')
        if key=='ember_proliferation':
            body+=facts([('互斥辅助',links('supports',data['ember_proliferation']['mutually_exclusive_with'])),('最低保存版本',number(data['ember_proliferation']['save_version']))])
            related+=' · '+link('rules','ember_proliferation')+' · '+link('town_services','skill_merchant','宝石商人')
        if key=='shock':
            body+=facts([('最低保存版本',number(data['shock']['save_version']))])
            related+=' · '+link('rules','shock')+' · '+link('town_services','skill_merchant','宝石商人')
        if key=='ambush':
            body+='<p>放置时不立即命中；脚下固定符印等待活敌触发。共享三枚，未触发过期不爆炸；范围只影响爆发圈。'+link('rules','ambush','查看冻结快照、魔力与冷却、原异常组合及生命周期')+'。</p>'
            related+=' · '+link('rules','ambush')+' · '+link('town_services','skill_merchant','宝石商人')
        if key=='inward_pull':
            body+='<p>沿用原冲量衰减、墙体碰撞与分离规则，不保证拉到圆心；可与符印伏击同用并在放置时冻结。'+link('rules','inward_pull','查看实际圆心、魔力代价与伤害不变的同源示例')+'。</p>'
            related+=' · '+link('rules','inward_pull')+' · '+link('rules','ambush')+' · '+link('town_services','skill_merchant','宝石商人')
        if key in ['frost_lock','lingering_chill']:
            body+='<p>霜锁辅助与寒意延长辅助不能同时装配；冻结只暂停自主行为，外力和资源状态继续。'+link('rules','frost_lock','查看完整准入与时间边界')+'。</p>'
            related+=' · '+link('rules','frost_lock')
        cards.append(add('supports',key,s['name'],s['description'],body,{'area':'范围辅助','projectile':'投射物辅助','resource':'资源辅助','element':'分量专注','delivery':'投射物辅助','control':'减速控制','chain':'连锁辅助','burning':'燃烧辅助','shock':'感电辅助','ambush':'预置伏击辅助','inward_pull':'冲量方向辅助','frost_lock':'冻结控制辅助'}[data['support_program_examples'][key]['family']],related=related))
    for key,e in data['equipment'].items():
        body = facts([('格数',' × '.join(map(number,e['size']))),('固有属性',lines(e['stats_text']))])+details('可出现的词缀',links('affixes',e['eligible_affixes']))
        related=link('rules','equipment')
        if e.get('stage')=='weapon_local':
            body+='<p>'+esc(e['normal_definition']['weapon_damage_summary'])+'</p><p>局部词缀与原有武器前缀共享稀有装备的三个前缀名额；两条局部前缀不能一起出现在仅允许一个前缀的魔法装备上。</p>'
            related+=' · '+link('weapon_stages','weapon_local')+' · '+(link('rules','forgeblade')+' · '+link('skills','cleave') if key=='forgeblade' else link('rules','basic_attack')+' · '+link('skills','tornado'))
        if key in data.get('glove_ring_affixes',{}).get('base_ids',[]): related+=' · '+link('rules','glove_ring_affixes')
        if e['stats'].get('fire_resistance',0): related+=' · '+link('defenses','fire_resistance','火焰抗性与受击结算')
        if key==data.get('elemental_defense_affixes',{}).get('base_id'): related+=' · '+link('rules','elemental_defense_affixes')+' · '+link('rules','defense_rating_affixes')
        display_pool=data['elemental_defense_affixes']['pool_id'] if key==data.get('elemental_defense_affixes',{}).get('base_id') else e['pool']
        cards.append(add('equipment',key,e['name'],e['description'],body,SLOTS[e['slot']],meta=tags([SLOTS[e['slot']],TYPES[display_pool]]),related=related))
    for key,f in data['affixes'].items():
        rows = ''.join(f'<tr><th scope="row">T{int(t["tier"])}</th><td>{int(t["level"])}</td><td>{esc(f["formatted_ranges"][i]["min"])} ～ {esc(f["formatted_ranges"][i]["max"])}</td><td>{int(t["weight"])}</td></tr>' for i,t in enumerate(f['tiers']))
        body = '<div class="table-scroll"><table><caption>原创阶级，端点包含在内</caption><thead><tr><th>阶级</th><th>物品等级</th><th>掷值</th><th>权重</th></tr></thead><tbody>'+rows+'</tbody></table></div>'
        body += details('资格、作用域与游戏内文本', facts([('可用底材',links('equipment',f['eligible_bases'])),('互斥组',esc(f['group'])),('运行时属性',esc(f['stat']))])+('<p>命中条件：'+esc(' + '.join(f.get('required_tags',[])))+'；阶段：'+esc(f.get('stage',''))+'</p>' if f.get('stage')=='skill_added_damage' else '')+'<p>'+lines('\n'.join(f['formatted_examples']))+'</p>')
        related = link('defenses','fire_resistance','火焰抗性与受击结算') if f['stat']=='fire_resistance' else (links('skills',f.get('affected_skills',[])) if f.get('affected_skills') else link('rules','character_rates'))
        if f['stat'] in ['fire_resistance','cold_resistance','lightning_resistance']:
            related=link('rules','elemental_defense_affixes')+' · '+link('rules','elemental_resistance_caps')
        if key in data.get('defense_rating_affixes',{}).get('new_families',{}):
            body+='<p>角色全局固定值；直接加到原始基数，由天赋和合计敏捷统一处理。不是百分比，也不是本地防具倍率；与生命、魔力、护盾争前缀名额。</p>'
            related=link('rules','defense_rating_affixes')+' · '+link('rules','source_defenses')
        if key in data.get('glove_ring_affixes',{}).get('new_families',{}):
            related=link('rules','glove_ring_affixes')+' · '+link('rules','precise_technique' if key=='glove_accuracy' else 'elemental_resistance_caps')
        if f['stat'] in ['attack_life_leech','attack_mana_leech']:
            body+='<p>按防御后实际扣除敌人护盾与生命计算，仅攻击命中；不含过量伤害或即时回复。与天赋同比例相加，仍受既有单次与总恢复上限。保存整数基点，100基点为1%，每一刻度为0.01个百分点。</p>'
            related=link('rules','source_leech')+' · '+links('skills',f['affected_skills'])
        elif f['stat'] in ['crit_chance_increased','crit_multiplier_add']:
            body+='<p>全局属性作用于攻击和法术命中；几率提高乘基础几率，倍率增加按百分点加算。独立爆炸读取自己的全局profile，同次施放快照保持。没有局部武器或暴击触发扩展。</p>'
            related=link('rules','source_critical')+' · '+links('skills',f['affected_skills'])
        if f.get('stage')=='weapon_local':
            body+='<p>阶段：本武器局部物理；只读取当前装备的合资格武器。白蜡长弓仅增强普攻与龙卷箭体，锻纹短刃仅增强裂刃direct；本地数值不进入角色统计，不增益法术或独立爆炸。原技能关联保留普通长弓对照单词缀合法魔法长弓的实际编译结果；短刃的独立实例与消费者矩阵见锻纹短刃规则卡。</p>'
            related=link('weapon_stages','weapon_local')+' · '+links('skills',f['affected_skills'])+' · '+link('rules','basic_attack')+' · '+link('rules','forgeblade')
        cards.append(add('affixes',key,f['name'],f['label'],body,TYPES[f['kind']],meta=tags([TYPES[f['kind']]]+[TYPES[p] for p in f['pools']]),related=related+' · '+link('rules','equipment')))
    for key,e in data['fixed_items'].items():
        cards.append(add('fixed_items',key,e['name'],e['description'],facts([('槽位',SLOTS[e['slot']]),('格数',' × '.join(map(number,e['size'])))]),SLOTS[e['slot']],related=link('rules','projectiles') if e.get('effects') else link('rules','damage')))
    for key,j in data['jewels'].items():
        if j['kind']=='special':
            summary=j['description']
            body=facts([('固有半径',number(j['rule']['radius'])),('可远程分配',esc(' / '.join(TYPES[x] for x in j['rule']['types']))),('规则',esc(j['rule']['id']))])+f'<p><a href="#tree">打开覆盖图，选择珠宝孔</a></p>'
        else:
            summary='镶入已分配的珠宝孔后，提供已掷出的角色属性加值。普通珠宝不改变连通规则。'
            body=facts([('前缀词池',links('jewel_affixes',j['prefixes'])),('后缀词池',links('jewel_affixes',j['suffixes']))])
            for example in j['examples']: body+=details('初始实例 · '+example['name'],'<p>'+lines(example['description'])+'</p>')
        cards.append(add('jewels',key,j['name'],summary,body,TYPES[j['kind']],related=link('rules','allocation')))
    for key,j in data['jewel_affixes'].items():
        bases=[k for k,v in data['jewels'].items() if key in v.get('prefixes',[])+v.get('suffixes',[])]
        cards.append(add('jewel_affixes',key,j['name'],j['range_text'],facts([('掷值步长',number(j['step'])),('可用珠宝',links('jewels',bases))]),TYPES[j['kind']],related=link('rules','allocation')))
    for key,p in data['passives'].items():
        sector=next((x['name'] for x in data['sectors'] if x['id']==p['sector']),'星图中心')
        body=details('连接与机制',facts([('相邻节点',links('passives',p['neighbors'])),('共用机制',links('mechanisms',p['mechanism_ids'])),('星图坐标',esc(', '.join(number(x) for x in p['position'])))]))
        cards.append(add('passives',key,p['name'],'历史181节点研究与怪物机制参考，已退出当前角色分配。\n'+p['description'],body,TYPES[p['type']],status='research',meta=tags([TYPES[p['type']],sector]),related=f'<a href="#tree" data-tree-node="{esc(key)}">旧图定位</a> · '+link('rules','allocation')))
    for key,p in data.get('source_tree',{}).get('nodes',{}).items():
        localized=localized_nodes[key]
        effect=p['execution']; allowed=p['standard_graph'] and not p['source_proxy'] and not p['blighted_only']
        selectable=allowed and effect['status']=='full' and p['type']!='mastery'
        state='完整效果已接入；仍需合法连接、点数和位置资格' if selectable else '保留源数据；未完整执行的节点不可分配'
        if p['type']=='mastery': state='精通按所选效果单独验证；同组普通连通显著天赋及1点必需'
        if p['type'] in ['start','socket'] and selectable: state='结构节点规则已接入，不算属性效果覆盖'
        body=facts([('源版本','3.29.1'),('分区',esc(localized['partition'])),('状态',esc(state)),('源坐标',esc(', '.join(number(x) for x in p['position'])) if p['has_position'] else '源记录没有坐标，不虚构布局')])
        if effect['unsupported']:body+=details('未实现的源效果 · 整节点锁定','<p>'+lines(source_lines(effect['unsupported']))+'</p>')
        for choice in p['mastery_choices']:
            label='已执行' if allowed and choice['execution']['status']=='full' else '未完整执行 · 不可选择'
            body+=details(f'精通 {choice["effect"]} · {label}','<p>'+lines(localized['mastery_choices'][str(choice['effect'])])+'</p>')
        if p['neighbors']:body+=details('原始标准邻接',links('source_passives',p['neighbors']))
        aliases=' '.join([p['name'],p['partition'],*p['stats'],*(line for choice in p['mastery_choices'] for line in choice['stats'])])
        cards.append(add('source_passives',key,localized['name'],localized['stats'] or state,body,TYPES[p['type']],status='implemented' if selectable else 'research',related=link('rules','source_tree')+(' · '+link('rules','physical_fire_conversion') if key in data.get('physical_fire_conversion',{}).get('entrances',{}) else '')+(' · '+link('rules','zealots_oath') if key == '63425' else '')+(' · '+link('rules','iron_reflexes') if key == '10661' else '')+(' · '+link('rules','resolute_technique') if key == '31961' else '')+(' · '+link('rules','precise_technique') if key == '63620' else '')+(' · '+link('rules','source_fire_dot') if key in data.get('source_fire_dot',{}).get('nodes',{}) else '')+(' · '+link('rules','source_faster_burn') if key in data.get('source_faster_burn',{}).get('nodes',{}) or key in data.get('source_faster_burn',{}).get('blocked_matching_nodes',{}) else '')+(' · '+link('rules','mana_guard') if key == data.get('mana_guard',{}).get('node',{}).get('id') or key in data.get('mana_guard',{}).get('blocked_matching_nodes',{}) else '')+(' · '+link('rules','elemental_resistance_caps') if key in data.get('elemental_resistance_caps',{}).get('nodes',{}) or key in data.get('elemental_resistance_caps',{}).get('boundaries',{}) else ''),search_aliases=aliases))
    for key,m in data['mechanisms'].items():
        player_nodes=[k for k,v in data['passives'].items() if key in v['mechanism_ids']]
        monsters=[k for k,v in data['monsters'].items() if key in v['mechanisms']]
        actors='玩家、怪物' if 'monster' in m['supported_actors'] else '仅玩家'
        body=facts([('支持对象',actors),('定义版本',esc(m['policy_version']))])+details('使用者与来源映射', '<p>天赋：'+links('passives',player_nodes)+'</p><p>怪物模板：'+links('monsters',monsters)+'</p><p>数值按固定参考基准映射，或保留原生加算提高语义。源游戏条件词条不会自动获得支持。</p>')
        cards.append(add('mechanisms',key,m['name'],m['description'],body,actors,related=link('rules','shared')+' · '+link('rules','sources')))
    for key,w in data['weapon_stages'].items():
        normal=w['examples']['local_normal']; rolled=w['examples']['local_max']
        body=facts([('作用对象','当前装备的白蜡长弓'),('生效命中',link('rules','basic_attack')+' · '+link('skills','tornado')+'（母箭 / 子箭）'),('局部规则版本',esc(w['balance_version']))])
        body+=weapon_diagram(rolled)
        body+='<p>上述图例保持白蜡长弓历史样本；锻纹短刃的W由普通近战basic/direct与裂刃cleave/direct消费，见 '+link('rules','melee_basic')+' 与 '+link('rules','forgeblade')+'。下列v0.13预算结论只描述历史长弓矩阵。</p>'
        rows=''.join(f'<tr><th scope="row">{esc(data["configurations"][config]["name"])}</th><td>{number(sample["resolved_weapon"]["profile"]["base"]["physical"])}</td><td>{number(sample["resolved_weapon"]["profile"]["flat"]["physical"])}</td><td>{percent(sample["resolved_weapon"]["profile"]["increased"]["physical"])}</td><td>{number(sample["resolved_weapon"]["components"]["physical"])}</td></tr>' for config in ['local_normal','local_max'] for sample in [w['examples'][config]])
        body+='<div class="table-scroll"><table><caption>由合法实例推导的武器面板</caption><thead><tr><th>装备</th><th>P 固有</th><th>F 点伤</th><th>L 提高</th><th>W 物理</th></tr></thead><tbody>'+rows+'</tbody></table></div>'
        body+=details('最高局部掷值示例的完整实例',f'<p>稀有、物品等级 {rolled["instance"]["item_level"]}。两条局部前缀与两条合法后缀共同满足四词缀最低要求；所有示例掷值均取实际目录对应阶级上限。</p><p>'+lines('\n'.join(rolled['definition']['affix_lines']))+'</p><p>这一示例只表示局部物理项上限，未声称在伤害、法术、速度、生存等目标上普遍更优。</p>')
        body+=details('组装语义与明确边界','<p>先结算本武器物理 W，再按技能基础倍率加到攻击物理分量。原有角色基伤 B 继续存在；龙卷的 60/40 只分配 B，不能把 W 转为火焰。外部攻击附加点伤仍按自身附加效用结算；角色提高、辅助总增/总降和目标防御随后处理。</p><p>仅实现有限的物理局部阶段。尚无品质、局部攻速、局部暴击、伤害范围、伤害转换，也未采用完整 PoE 的武器替换整个攻击基础模型。底材、阶级、掷值、掉落权重与保留 B 的兼容适配均为本游戏原创。</p><p>同一武器槽不能同时装备白蜡长弓与符木法器；上图外部附加为零，字段仍与真实组装记录分别展示。</p>')
        body+=details('已验证的平衡范围','<p>当前固定矩阵含 288 组物品等级、稀有度、构筑背景、目标与辅助组合；真实编译回放完成 92,580 次候选评估。各指标分别寻找合法最优实例，最高优势约 +17.59%，稀有装备最高约 +16.26%，均通过当前 25% 预算线。</p><p>这不表示一件装备同时最大化所有指标，也不是实际每秒伤害或未来目标的普遍保证。额外的 75% 火抗未来压力目标中，龙卷母箭优势约 +25.39%，已经超出该预算线；加入这类防御时须重新审查。</p><p><a href="../benchmarks/v0.13-weapon-budget-report.md">完整预算报告、矩阵范围与重放方法</a> · <a href="../benchmarks/v0.13-weapon-budget-replay.json">实际编译回放数据与合法实例</a></p>')
        body+=details('历史语义研究来源','<p>以下 GGG 历史说明仅用于研究局部词缀与攻击基础/附加效用的区别，不是本游戏平衡背书，也不宣称当前版本完全复刻。</p><p>'+' · '.join(f'<a href="{esc(url)}">GGG 历史说明 {i+1}</a>' for i,url in enumerate(w['source_refs']))+'</p>')
        cards.append(add('weapon_stages',key,w['name'],w['description'],body,'局部物理',related=links('equipment',w['base_ids'])+' · '+links('affixes',[i for i,f in data['affixes'].items() if f.get('stage')==key])+' · '+link('rules','damage')))
    for key,d in data['defenses'].items():
        example=d['worked_example']
        body=facts([('支持对象','、'.join({'player':'玩家','monster':'怪物'}[a] for a in d['supported_actors'])),('有效下限',percent(d['minimum_effective'])),('默认有效上限',percent(d['maximum_effective'])),('规则版本',esc(d['balance_version']))])
        body+=defense_diagram(example)
        cap_rows=''.join(f'<tr><td>{percent(p["raw_resistances"]["fire"])}</td><td>{percent(p["effective_resistances"]["fire"])}</td></tr>' for p in d['cap_examples'])
        body+=details('原始值与有效值', '<p>原始抗性先相加，再按原创上下限约束；下面包含边界演算输入，不代表当前装备可以达到每一个原始值。</p><div class="table-scroll"><table><thead><tr><th>原始火抗</th><th>有效火抗</th></tr></thead><tbody>'+cap_rows+'</tbody></table></div>')
        body+=details('当前支持边界','<p>此条保留早期火抗与护盾的指定输入演算，未含最大抗性加成或魔力分担。当前源天赋可提供原始三抗及三种最大抗性；默认75%，本游戏安全上限83%，详见 '+link('rules','elemental_resistance_caps')+'。命中还可结算护甲与感电，魔力先承伤见 '+link('rules','mana_guard')+'；当前不实现混沌绕盾或完整PoE防御体系。</p><p>本游戏上限、底材/词缀数值和怪物平衡不是PoE源规则背书。</p>')
        related=links('equipment',[i for i,e in data['equipment'].items() if e['stats'].get(d['stat'],0)])+' · '+links('affixes',[i for i,f in data['affixes'].items() if f['stat']==d['stat']])+' · '+links('monsters',[i for i,m in data['monsters'].items() if m.get('defense_stats',{}).get(d['stat'],0)])
        cards.append(add('defenses',key,d['name'],d['description'],body,'命中防御',related=related+' · '+link('rules','damage')))
    for key,c in data['crafting'].items():
        if c['kind']=='material':
            body=facts([('余额上限',number(c['maximum'])),('存档版本',number(c['save_version'])),('规则版本',esc(c['rules']['rules_version']))])
            body+='<p>真实校准碎片存放在背包中。回收收益为稀有度基数（魔法1、稀有3）加全部词缀阶级之和；校准成本为该装备回收收益的2倍。赋魔8、升格24、补缀6；重铸魔法10、稀有28。T1入门、T3高阶是本游戏顺序，数值为可调原创平衡。</p>'
            targeted_costs=[esc(entry['target_label'])+'：魔法'+number(entry['cost_by_rarity']['magic'])+'、稀有'+number(entry['cost_by_rarity']['rare']) for entry in data['crafting'].values() if entry.get('targeted')]
            if targeted_costs:body+='<p>定向重铸消耗校准碎片：'+'；'.join(targeted_costs)+'。仅在底材与物品等级存在合法目标及完整结果时可用。</p>'
            related=' · '.join(link('crafting',op) for op,entry in data['crafting'].items() if entry['kind']=='operation')
        else:
            sample=c['example']; quote=sample['quote']; source=sample['source']
            amount=quote['materials'].get('calibration_shard',0) if key=='salvage' else quote['cost']['calibration_shard']
            action='获得' if key=='salvage' else '消耗'
            mark='<svg viewBox="0 0 64 64" width="48" height="48" aria-hidden="true"><path d="M32 5 L51 22 L42 53 L16 42 L12 21 Z M32 5 L29 30 L42 53 M12 21 L29 30 L51 22" fill="#dfc99a" stroke="#79571f" stroke-width="2"/></svg>'
            body='<figure class="defense-flow"><figcaption>实际规则示例 · '+esc(sample['before_definition']['base_name'])+'</figcaption><ol><li><span class="flow-step">01 · 原物品</span><strong>'+esc(sample['before_definition']['base_name'])+'</strong><span>'+lines('\n'.join(sample['before_definition']['affix_lines']))+'</span></li><li><span class="flow-step">02 · '+action+'校准碎片</span>'+mark+f'<strong data-craft-value="{key}-amount" data-value="{amount}">{amount}</strong></li><li><span class="flow-step">03 · 余额与结果</span>'+f'<strong><span data-craft-value="{key}-before" data-value="{sample["balance_before"]}">{sample["balance_before"]}</span> → <span data-craft-value="{key}-after" data-value="{sample["balance_after"]}">{sample["balance_after"]}</span></strong>'
            body+='<span>原装备被消耗，空位释放</span>' if key=='salvage' else '<span>'+lines('\n'.join(sample['after_definition']['affix_lines']))+'</span>'
            body+='</li></ol><p class="fine">演示使用合法背包装备与固定示例种子；收益、成本和结果来自实际规则/规划器，真实碎片物品与完整当前版本候选通过当前校验。它不预告玩家下一次随机结果。</p></figure>'
            preconditions={'salvage':'背包中未穿戴的随机魔法或稀有装备','recalibrate':'背包中未穿戴的随机魔法或稀有装备','enchant':'背包中未穿戴的随机普通装备','elevate':'背包中未穿戴的随机魔法装备，能达到合法稀有词缀数','augment':'背包中的随机魔法或稀有装备，必须存在合法空位','reforge':'背包中未穿戴的随机魔法或稀有装备'}
            preserves={'salvage':'消耗选中装备，其余物品保持','recalibrate':'物品ID、底材、等级、稀有度、词缀种类/顺序/阶级；只重掷数值','enchant':'物品ID、底材、物品等级和位置','elevate':'物品ID、底材、物品等级、位置及已有全部词缀','augment':'物品ID、底材、物品等级、位置及已有全部词缀','reforge':'物品ID、底材、物品等级、位置和稀有度；全部词缀重新生成'}
            if c.get('targeted'):
                preconditions[key]=esc(c['eligibility_note'])
                preserves[key]=preserves['reforge']
                costs=' · '.join(('魔法' if rarity=='magic' else '稀有')+f' <span data-targeted-cost="{key}-{rarity}" data-value="{cost}">{cost}</span> 枚' for rarity,cost in c['cost_by_rarity'].items())
                eligibility='；'.join(link('equipment',entry['base_id'])+'：'+ ' / '.join(('魔法' if rarity=='magic' else '稀有')+'物品等级≥'+number(level) for rarity,level in entry['minimum_item_level_by_rarity'].items()) for entry in c['eligibility'])
                body+=facts([('保证目标',esc(c['target_label'])),('目标家族',links('affixes',c['target_family_ids'])),('费用',costs),('最低物品等级',eligibility),('抽取边界',esc(c['selection_note'])),('规则版本',esc(c['rules_version']))])
            body+=facts([('可用底材',links('equipment',c['eligible_base_ids'])),('前置条件',preconditions[key]),('风险',esc(c['risk'])),('保存顺序','完整候选验证 → 原子写盘 → 内存提交与刷新'),('失败保护','拒绝或写盘失败不动装备、材料和序号；取消不收费，失败重试保持种子'),('保持字段',preserves[key])])
            related=link('crafting','calibration_shard')+' · '+link('equipment',source['base_id'])+' · '+links('affixes',[a['id'] for a in source['affixes']])
        cards.append(add('crafting',key,c['name'],c['description'],body,'材料' if c['kind']=='material' else '制作操作',related=related))
    for key,f in data.get('flasks',{}).items():
        e=f['example']; resource='生命' if f['resource']=='health' else '魔力'
        rows=''.join(f'<tr><td>{number(r["time"])}秒</td><td data-flask-value="{key}-time-{i}" data-value="{esc(r["resource"])}">{number(r["resource"])}</td><td>{r["charges"]}</td></tr>' for i,r in enumerate(e['rows']))
        bar_width=220*e['restored']/e['maximum_at_use']
        chart=f'<figure><svg viewBox="0 0 280 62" role="img" aria-label="三秒实际药剂回复"><rect x="20" y="8" width="220" height="16" rx="3" fill="#c6b78c"/><rect x="20" y="8" width="{bar_width}" height="16" rx="3" fill="'+('#aa5046' if f['resource']=='health' else '#587da2')+f'"/><text x="20" y="48" fill="#493a2d">三秒恢复 {number(e["restored"])} / 最大 {number(e["maximum_at_use"])}</text></svg><figcaption>由实际FlaskRuntime推进；不含自然回复，满资源会提前结束。</figcaption></figure>'
        body=chart+facts([('占格','1×2，独立UID，不可堆叠'),('充能',f'{f["max_charges"]}上限 / 每次{f["cost"]}'),('资源',resource),('起手锁定',f'{number(f["duration"])}秒恢复使用瞬间最大值的{number(f["recovery_fraction"]*100)}%'),('使用门槛','活着、未暂停、资源未满、同资源未恢复、足够充能；失败不扣'),('获取',f'新档与首次schema18迁移各一瓶；每{f["acquisition"]["eligible_root_interval"]}有效根怪交替生命/魔力，满包拒收，额外RNG为零'),('战斗状态','换槽/卸下不补充，合法根怪给当时已装瓶各+1；后代/演示/重复尸体不充能。新战斗恢复30，临时charge不写构筑档'),('保存','旧原始文件验证并逐字节备份，完整候选成功写入后才更新；不丢原UID/位置/材料'),('未扩展','不恢复护盾，不清异常，不加药剂词缀')])+f'<table><thead><tr><th>经过</th><th>{resource}</th><th>充能</th></tr></thead><tbody>{rows}</tbody></table>'
        cards.append(add('flasks',key,f['name'],f['description'],body,'真实药剂物品',related=link('rules','ownership')))
    for key,c in data.get('currencies',{}).items():
        diagram='<figure><svg viewBox="0 0 650 130" role="img" aria-label="回收装备产生背包碎片，校准消耗同一物品堆"><g fill="#ead3a2" stroke="#8c6b42"><rect x="10" y="35" width="170" height="60" rx="8"/><rect x="235" y="20" width="180" height="90" rx="8"/><rect x="470" y="35" width="170" height="60" rx="8"/></g><g fill="#3b281b" font-size="16" text-anchor="middle"><text x="95" y="70">回收装备</text><text x="325" y="58">1×1 碎片物品堆</text><text x="325" y="86">唯一UID · 真实数量</text><text x="555" y="70">消耗碎片校准</text></g><g fill="none" stroke="#79571f" stroke-width="2"><path d="M185 65H229M219 59L229 65L219 71M420 65H464M454 59L464 65L454 71"/></g></svg></figure>'
        body=diagram+facts([('占用','1×1 背包格'),('单堆与全库存上限',number(c['stack_limit'])),('持久数量来源',esc(c['quantity_source'])),('保存版本',number(c['save_version']))])
        body+='<p>只有背包中的堆可用于制作。回收优先合入已有堆，否则使用被回收装备释放的格子；零数量堆被移除。拖到同种堆可合并，整堆丢弃需要确认。旧余额先原字节备份再转为真实物品；仅迁移满包时可保留在待安置区，该区域的碎片不能用于校准。</p>'
        body+='<p>该上限沿用本游戏原型的旧材料边界，不是PoE原版堆叠规则。实例数量随游戏过程变化，本页定义中的1枚仅为合法格式示例。</p>'
        cards.append(add('currencies',key,c['name'],c['description'],body,'物品化制作材料',related=' · '.join(link('crafting',op) for op,entry in data['crafting'].items() if entry['kind']=='operation')))
    for key,e in data['encounters'].items():
        body=encounter_diagram(key,e,data['monsters'])+facts([('操作',esc(e['operation'])),('实际规则',esc(e['description'])),('作用字段',esc(e['field'])),('固定来源','物种/波次/稀有度/机制生成标准怪物后，始终读取未加本轮普通词缀的基准；死亡子怪各按自己的标准值应用一次'),('保持','体型、身份、稀有度、原机制、RNG与奖励资格不变'),('风险说明','初版可调预算；实战难度未合并评分'),('奖励','无额外经验、掉落、制作材料或地图物品'),('生命周期','最多2普通；F7确认重开或城镇制图后生效，不随构筑保存')])
        if e['field']=='attack_speed':
            example=e['examples']['ember_guard']
            body+=facts([('预警秒数',number(example['before_telegraph']['profile']['windup_seconds'])+' → '+number(example['after_telegraph']['profile']['windup_seconds'])),('预警后恢复秒数',number(example['before_telegraph']['profile']['recovery_seconds'])+' → '+number(example['after_telegraph']['profile']['recovery_seconds']))])
        if e['field']=='max_shield':body+='<p>护幕额外盾为原始最大生命的20%，不含强健的1.20倍率；先选强健或先选护幕结果相同。最大盾和当前盾增加相同量，原缺失盾量保持，不是持续回血或每帧补盾。当前混沌命中仍先扣盾。</p>'
        if e['field']=='armour':body+='<p>护甲使用既有物理命中大小相关公式：同样+80护甲，对较小单次物理命中的减伤比例更高；元素和混沌部分不受护甲影响。可以与元素庇护同图，但两者各处理自己的伤害分量。</p>'
        cards.append(add('encounters',key,e['name'],e['description'],body,'本轮可选 · 原创规则',related=links('monsters',e['examples'].keys())+' · '+link('rules','encounters')))
    town=data.get('town_maps',{})
    if town:
        for service in town['services']:
            key=service['id'];stock=town['stock'].get(key,[])
            body=facts([('开放条件','测试档全服务；正式城镇开放宝石商人、工匠、天赋重置和地图装置'),('存档隔离',esc(town['normal_save'])+' → 首次显式复制 → '+esc(town['test_save'])),('测试供应','真实UID物品，免费但受背包与注册表上限限制'),('配置开关',esc(town['supply_setting'])),('交易保护','完整候选验证，保存成功才提交；旧档实例与货币不被测试交易改写')])
            if key=='skill_merchant':
                trade=data['normal_gem_trading']
                body+='<p>正式购买：主动8、辅助4校准碎片，背包所选宝石回收1。均为1级0品质，已装配或待安置不能回收。无词缀地图净得4碎片；买卖净损失3或7，不可套利。仅确认时原子保存；免费测试供应始终隔离。</p>'
                body+='<div class="table-scroll"><table><thead><tr><th>正式商品</th><th>购买碎片</th><th>回收碎片</th></tr></thead><tbody>'+''.join('<tr><td>'+esc(o['name'])+'</td><td data-gem-trade-id="'+esc(o['definition_id'])+'" data-cost="'+str(o['cost'])+'">'+str(o['cost'])+'</td><td>'+str(trade['recycle_credit'])+'</td></tr>' for o in trade['offers'])+'</tbody></table></div>'
            if stock:
                rows=[]
                for offer in stock:
                    kind=offer['supply_kind'];definition=offer['catalog_id']
                    cat={'base':'equipment','fixed':'fixed_items','jewel':'jewels','flask':'flasks','currency':'currencies'}.get(kind)
                    if kind=='gem':cat='skills' if definition.startswith('skill:') else 'supports';definition=definition.split(':',1)[1]
                    elif kind=='flask':definition=definition.split(':',1)[1]
                    elif kind=='currency':definition='calibration_shard'
                    rows.append('<tr><td>'+link(cat,definition,offer['name'])+'</td><td>'+str(offer.get('quantity',1))+'</td><td>'+esc(offer['price_label'])+'</td></tr>')
                body+='<div class="table-scroll"><table><thead><tr><th>实际供应目录</th><th>数量</th><th>价格</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
            if key=='passive_reset':body+='<p>保留当前起点，退还实际已花普通点。已镶珠宝保留原UID，优先回背包，放不下进入可见待安置；保存失败不改变点数或物品。</p>'
            if key=='crafter':body+='<p>继续消耗测试档里的真实碎片，不建立材料钱包。测试背包装备可确认丢弃并重新领取，正常进度保留原回收规则。</p>'+links('crafting',[op for op,c in data['crafting'].items() if c['kind']=='operation'])
            body+='<p>重进测试档不重新复制或覆盖。退出后恢复正常档并进入正式城镇。被替换的旧model拒绝迟到写入；原确认、拖拽与面板一并关闭。</p>'
            cards.append(add('town_services',key,service['name'],'正式付费购买与独立测试供应' if key=='skill_merchant' else service['description'],body,'正式购买 · 测试供应' if key=='skill_merchant' else '可选测试服务'))
        for m in town['options']['maps']:
            key=m['id'];example=town['examples'][key]
            body='<figure class="defense-flow"><figcaption>有限地图流程</figcaption><ol><li><strong>城镇制图</strong><span>最多2普通 + 1特殊</span></li><li><strong>'+str(m['ordinary_target'])+' 个根怪</strong><span>固定第'+str(m['wave'])+'波强度</span></li><li><strong>裂隙守卫</strong><span>首领一次奖励，后代零奖励</span></li><li><strong>清理后代 → 返城</strong><span>已得进度保存到测试档</span></li></ol></figure>'
            body+=facts([('普通目标',number(m['ordinary_target'])),('波次',number(m['wave'])),('首领',link('monsters',m['boss_id'])),('费用',esc(town['options']['cost_policy']['label'])),('普通词缀',links('encounters',[x['id'] for x in town['options']['normal_modifiers']])),('额外收益','无地图加成；现有合法根怪XP/装备/宝石/药剂奖励照常'),('中途离开','保存已有进度后放弃本图，不恢复旧怪或复领同一根怪奖励'),('重开','重新初始化有限目标与根怪身份'),('持久化','构筑与物品保存；草案和地图运行仅本会话')])
            body+=details('同源编译示例',facts([('选择',esc(example['compiled']['summary'])),('生命倍率',number(example['compiled']['encounter_profile']['multipliers']['max_health'])),('移动倍率',number(example['compiled']['encounter_profile']['multipliers']['speed'])),('特殊替换',esc(example['special_replacements']))]))
            normal=data.get('normal_journey',{})
            if normal:
                rows=[r for r in normal['tiers'] if r['id']==key]
                body='<h4>正式地图成长</h4>'+facts([('I / II / III 波次',' / '.join(str(r['wave']) for r in rows)),('对应入场碎片',' / '.join(str(r['fee']) for r in rows)),('基础完成碎片',' / '.join(str(r['completion_reward']) for r in rows)),('词缀奖励','普通每项+1、特殊每项+2，最多+4'),('解锁','各地图独立，完成本图解锁下一档'),('结算与重开',normal['lifecycle']),('满包待领',normal['claims']),('累计获取','每30合法根怪宝石，每60药剂；后代无收益'),('存档',normal['migration'])])+'<h4>独立测试地图与共用战斗</h4>'+body
            boss=data.get('map_bosses',{}).get(key)
            if boss:
                d=boss['definition'];p=boss['policy']['profile'];event=boss['event'];cx,cy=event['center'];sx,sy=boss['source']['pos'];mx,my=boss['cases']['moving']['position'];radius=event['radius'];left=min(cx-radius,mx)-45;right=max(cx+radius,sx+boss['source']['radius'])+45
                body+=facts([('首领动作',esc(d['name'])),('锁定点','首领起手位置' if d['target_rule']=='self_at_start' else '玩家起手位置；结算不追踪'),('完整预警',number(p['windup_seconds'])+' 秒'),('半径 / 启动距离',number(p['radius'])+' / '+number(d['trigger_distance'])),('恢复时间',number(p['recovery_seconds'])+' 秒，攻速只影响此项'),('单次伤害',component_text(event['packet']['base'])+'，同图当前接触分量 × '+number(p['damage_multiplier']))])
                body+=f'<figure><figcaption>{esc(d["name"])} · 起手锁点与退离示意</figcaption><svg viewBox="{number(left)} -175 {number(right-left)} 350" role="img" aria-label="同源首领预警圆心与半径"><circle cx="{number(cx)}" cy="{number(cy)}" r="{number(radius)}" fill="#d9b677" fill-opacity=".25" stroke="#775537" stroke-width="3"/><circle cx="{number(sx)}" cy="{number(sy)}" r="{number(boss["source"]["radius"])}" fill="#ac7856"/><path d="M0 0L{number(mx)} {number(my)}" stroke="#427365" stroke-width="3" stroke-dasharray="6 5"/><circle cx="0" cy="0" r="{number(boss["player_radius"])}" fill="#68968a"/><circle cx="{number(mx)}" cy="{number(my)}" r="{number(boss["player_radius"])}" fill="#b9d0b8" stroke="#427365"/><g fill="#493523" font-size="14"><text x="{number(sx-30)}" y="-42">首领</text><text x="-35" y="36">玩家起手</text><text x="{number(mx-28)}" y="36">已退离</text></g></svg></figure><p>{esc(boss["scope"])}。</p><p>{esc(boss["rules"])}。{esc(boss["preserves"])}。</p><p>预算为本游戏可调原型，不是平衡结论；圆周为最大危险边界，墙体视线仍可阻挡实际命中。</p>'
            camp_layout=data.get('map_camps',{}).get(key)
            if boss and 'sequence' in boss:
                body=body.replace('圆周为最大危险边界，墙体视线仍可阻挡实际命中。','圆周为攻击区域边缘，角色身体须完全移出；泉池视线仍可阻挡实际命中。')
                body+=sunwell_sequence(boss)
            if camp_layout:
                if key=='sunwell_terrace':
                    sunwell=data[key];camps=camp_layout['camps'];migration=sunwell['migration_example']
                    if 'mist_skitter' in data['monsters']:
                        budget=data['monsters']['mist_skitter']['encounter_budget']
                        body+='<p>正式第二、三档可能遇到'+link('monsters','mist_skitter')+'：每据点最多'+number(budget['maximum_per_camp'])+'只白怪，整图至多'+number(budget['maximum_per_map'])+'/'+number(budget['map_root_count'])+'根怪；没有合格名额则不出现，雷纹巡逻优先。第一档与旧固定波次'+number(budget['fixed_test_wave'])+'测试地图不出现。</p>'
                    intro=facts([('据点',esc(' / '.join(c['name'] for c in camps))),('密度',sunwell_value('camp-count',len(camps))+' 组 × '+sunwell_value('camp-roots',camps[0]['root_count'])+' 根怪，共 '+sunwell_value('total-roots',sum(c['root_count'] for c in camps))),('推进顺序','任意顺序，可同时激活多组；不必清完一组才触发下一组'),('整组出现','进入木牌 '+sunwell_value('trigger-radius',camps[0]['trigger_radius'])+' 范围，同组完整出现；出生提示 '+sunwell_value('spawn-seconds',sunwell['spawn_seconds'])+' 秒'),('安全边界','全部位置离玩家至少 '+sunwell_value('player-clearance',sunwell['player_clearance'])+'，真实半径不越界或压池；容量不足整组等待'),('首领入口','全部普通根怪死亡后开启南侧入口；首领及所有后代死亡才完成'),('经济','保留既有分档费用和完成奖励，后代不增加奖励'),('存档','schema '+sunwell_value('save-version',sunwell['save_version'])+'；旧 '+str(migration['from_version'])+' 验证后备份原字节，只升级版本并增加晴泉进度起点，物品和货币保持')])
                    tier_rows=[]
                    for row in sunwell['tiers']:
                        base=row['base'];maximum=row['maximum_bonus_example'];tier=base['journey_tier']
                        tier_rows.append('<tr><th scope="row">'+esc(base['name'])+'</th><td>'+sunwell_value('tier-'+str(tier)+'-wave',base['wave'])+'</td><td>'+sunwell_value('tier-'+str(tier)+'-fee',base['fee'])+'</td><td>'+sunwell_value('tier-'+str(tier)+'-reward',base['completion_reward'])+'</td><td>'+sunwell_value('tier-'+str(tier)+'-max-bonus',maximum['completion_reward']-base['completion_reward'])+'</td><td>'+links('map_specials',row['eligible_special_ids'])+'</td></tr>')
                    intro+='<div class="table-scroll"><table><caption>正式三档的真实费用与奖励；特殊词缀仍受波次门槛限制</caption><thead><tr><th>阶级</th><th>波次</th><th>入场碎片</th><th>基础完成碎片</th><th>可选词缀最大加奖</th><th>可选特殊词缀</th></tr></thead><tbody>'+''.join(tier_rows)+'</tbody></table></div>'
                    intro+='<h4>同源据点编排</h4><p>'+esc(sunwell['roster_scope'])+'。霜纹从第 '+sunwell_value('frost-min-wave',sunwell['elemental_gates']['frost_guard']['minimum_wave'])+' 波出现，雷纹从第 '+sunwell_value('storm-min-wave',sunwell['elemental_gates']['storm_skitter']['minimum_wave'])+' 波出现；低于门槛回退为相应基础物种。下表是基础物种抽签的按位示例，不代表每次实际整组抽签结果。</p>'
                    for wave,rosters in sunwell['roster_examples_by_wave'].items():
                        intro+=details('第 '+wave+' 波 · 据点内序号编排',facts([(c['name'],' → '.join(link('monsters',template) for template in rosters[c['id']])) for c in camps]))
                    body='<h4>据点自由推进</h4>'+intro+body
                else:
                    body='<h4>据点自由推进</h4>'+facts([('每组普通根怪',str(camp_layout['camps'][0]['root_count'])),('推进顺序','三个据点任意顺序，可同时激活多组'),('整组出现','靠近木牌64范围，完整8或12只同次入场，保留0.6秒出生提示'),('安全边界','全部位置离玩家至少230，真实半径不越界或压墙；容量不足整组等待'),('首领入口','全部普通根怪死亡后开启独立入口；首领及所有后代死亡才完成'),('原经济','费用、总根怪、原稀有度/机制和完成奖励保持；后代不增加奖励')])+body
            geometry=example['geometry'];bounds=geometry['bounds'];width,height=bounds['size'];ox,oy=bounds['position']
            walls=''.join(f'<rect x="{number(w["position"][0]-ox)}" y="{number(w["position"][1]-oy)}" width="{number(w["size"][0])}" height="{number(w["size"][1])}" fill="#a89472" stroke="#594d38" stroke-width="4"/>' for w in geometry['walls'])
            if geometry.get('obstacle_style')=='spring_basin':
                walls=''.join(f'<rect data-sunwell-obstacle="{i}" x="{number(w["position"][0]-ox)}" y="{number(w["position"][1]-oy)}" width="{number(w["size"][0])}" height="{number(w["size"][1])}" fill="#b7d7d4" stroke="#657d75" stroke-width="4"/>' for i,w in enumerate(geometry['walls']))
                geometry={**geometry,'spawn':geometry['entry']}
            body+=f'<figure><figcaption>实际同源地形平面图：{esc(m["name"])}</figcaption><svg viewBox="0 0 {number(width)} {number(height)}" role="img" aria-label="真实墙体足印与绕行通道"><rect width="{number(width)}" height="{number(height)}" fill="#ddd7b8"/>{walls}<circle cx="{number(geometry["spawn"][0]-ox)}" cy="{number(geometry["spawn"][1]-oy)}" r="16" fill="#527553"/></svg></figure>'
            if key=='sunwell_terrace':
                body+='<p>浅色矩形为 '+sunwell_value('obstacle-count',len(geometry['walls']))+' 座实体泉池，阻挡移动、弹体与视线；中央十字与外侧留有通路，需沿池间或外侧绕行。击退与冲刺也受阻，贯穿和返回弹体不能穿池；碰池终止不触发自然到期爆炸、分裂或返回。范围命中、连锁与敌预警仍检查墙视线。地图完成保留地形，返城清除障碍。</p>'
            else:
                body+='<p>旧庭为开阔庭院；断垣的两道错位残墙有真实阻挡，角色、怪物需沿端部通道绕行，击退和冲刺同样受阻。贯穿不能穿墙，返回飞行也会碰墙；碰墙终止不触发自然到期爆炸、分裂或返回。范围命中、连锁与敌预警也检查墙视线，圈只表示最大半径。地图完成保留地形，返城清除障碍；不是可破坏场景或完整终局系统。</p>'
            cards.append(add('maps',key,m['name'],m['description'],body,'正式三档 / 独立测试',related=link('town_services','map_device')))
        for special in town['options']['special_modifiers']:
            if special.get('kind')=='defense':
                body=facts([('最低波次',number(special['minimum_wave'])),('原始加值',number(special['resistance_bonus']*100)+' 个百分点 / '+ '、'.join(DAMAGE_NAMES[t] for t in special['damage_types'])),('有效上限','未授予最大抗性加成，默认0%–75%'),('适用','根怪、首领、死亡后代各从本身原始值加一次'),('保留','物理/混沌抗性、护甲、血盾伤速、身份、稀有度、奖励和RNG'),('分层','最多1特殊词缀，与霜纹/雷纹巡逻互斥')])
                body+='<figure class="defense-flow"><figcaption>与角色天赋共享的结算</figcaption><ol><li><strong>原始抗性</strong><span>原怪物 + 地图20个百分点</span></li><li><strong>有效抗性</strong><span>未加最大抗性，默认0%–75%</span></li><li><strong>按类型减伤</strong><span>三元素各自结算</span></li><li><strong>护盾 → 生命</strong><span>物理/混沌部分保持</span></li></ol></figure>'
                for template,example in town['defense_examples'].items():
                    body+=details('同源100点各类型示例：'+data['monsters'][template]['name'],facts([('怪物',link('monsters',template)),('有效抗性',' / '.join(DAMAGE_NAMES[t]+percent(example['effective_resistances'][t]) for t in special['damage_types'])),('施加前单次命中',component_text(example['before_components'])),('施加后单次命中',component_text(example['after_components']))]))
                body+='<p>这提供物理/混沌与元素构筑之间的取舍；混沌或物理技能若装备附加了元素伤害，其元素分量仍按对应抗性结算。数值是本游戏测试预算，无额外掉落倍率，不代表PoE地图经济。</p>'
            else:
                consumer='已有元素预警攻击和共享防御链；雷纹锁点震击按显式规则施加感电' if data['monsters'][special['template']]['telegraph_policy'].get('shock_policy') else '已有冰冷预警攻击和共享防御链；不增加冻结或感电'
                body=facts([('最低波次',number(special['minimum_wave'])),('匹配原物种',link('monsters',special['species'])),('替换为',link('monsters',special['template'])),('保留','原抽签稀有度、机制、血伤速度与XP；灰烬名额优先'),('真实消费者',consumer),('分层','独立于生命/速度普通词缀，最多1个特殊词缀')])
            cards.append(add('map_specials',special['id'],special['name'],special['description'],body,'已实装特殊词缀',related=links('maps',[m['id'] for m in town['options']['maps'] if m['wave']>=special['minimum_wave']])))
    for key,a in data['monster_attacks'].items():
        p=a['profile']; policy=a['policy']
        body=telegraph_diagram(a)+facts([('来源',links('monsters',a['integrated_templates'])),('发动距离',number(policy['trigger_distance'])+' 世界单位'),('原始伤害',component_text(a['example']['event']['packet']['base'])),('倍率',number(p['damage_multiplier'])+' × 来源接触基底'),('攻速作用','只缩放恢复期；预警时间固定；开始后本次时序和伤害冻结'),('期间行动','暂停主动追击；击退仍有效；同一守卫不再叠加贴身接触攻击'),('取消与保护','来源死亡/出生保护/移除、玩家死亡或重开取消；暂停冻结时钟；多次同时命中沿用玩家无敌帧'),('规则版本',esc(a['balance_version']))])
        if a.get('natural_selection'):
            n=a['natural_selection']
            body+=facts([('自然出现',f'第 {n["minimum_wave"]} 波起，已成功普通入场序号除 {n["admission_modulus"]} 余 {n["admission_remainder"]}，且原抽签为 '+link('monsters',n['source_template'])),('保留原抽签','同物种的白/蓝/金、共享词缀、基础生命/伤害/移动与经验；没有强升蓝或额外奖励'),('防御示例','初始等级合法天赋路径：'+esc(' → '.join(a['example']['allocated_path']))+'。数值在攻击成功命中条件下，现有攻击闪避另可阻止命中。')])
        cards.append(add('monster_attacks',key,a['name'],a['description'],body,'已实装 · 原创规则',related=links('monsters',a['integrated_templates'])))
    for key,m in data['monsters'].items():
        e=m['runtime_example']; tier=data['monster_rarities'][m['rarity']]['name']
        children=' · '.join(link('monsters',x['template'])+' × '+str(x['count']) for x in m['death_spawns']) or '无'
        summary=m['mechanism_text']+'。死亡后生成：'+('、'.join(data['monsters'][x['template']]['name']+' × '+str(x['count']) for x in m['death_spawns']) if m['death_spawns'] else '无子怪')
        body=facts([('稀有度',esc(tier)),('共用机制',links('mechanisms',m['mechanisms'])),('死亡子怪',children)])
        body+=facts([('攻击基底分量 · 防御前',esc(component_text(m['contact_components']))),('有效火焰抗性',percent(m['defense_profile']['effective_resistances']['fire']))])
        if m.get('source_ratings'):
            body+=facts([('命中值',number(m['source_ratings']['accuracy'])),('闪避值',number(m['source_ratings']['evasion']))])
        if key=='mist_skitter':
            body+=mist_skitter_hint(m,link)
        if m.get('telegraph_policy'):
            body+='<p>'+link('monster_attacks',m.get('attack_reference',m['telegraph_policy']['profile_id']),'查看锁点重击：预警、躲避与真实伤害')+'</p>'
        encounter=data['fire_encounter']
        if key==encounter['template_id']:
            body+=details('出现条件与专属装备奖励',f'<p>第 {encounter["minimum_wave"]} 波及之后，普通成功入场计数每逢 {encounter["ordinary_admission_interval"]} 的倍数出现。初始入场计入该计数；满员未入场不递增，重开重置。</p><p>符合奖励资格的原始怪物死亡时，仅结算一次：{encounter["reward_count"]} 件 {esc(data["equipment_rarities"][encounter["reward_rarity"]]["name"])} {esc(TYPES[encounter["reward_pool"]])} 装备。可用底材：{links("equipment",data["equipment_pools"][encounter["reward_pool"]]["base_ids"])}。逻辑defense在实际奖励入口映射当前防御池，详见 {link("rules","elemental_defense_affixes")}；显式旧池仍保留历史结果。</p><p>出生节奏、分量、抗性与掉落保障均为本游戏原创平衡。</p>')
        example_note='这是正式第二档的普通模板；第三档沿同波掠行体再应用上述预算，不接受蓝金稀有度或新增机制。' if key=='mist_skitter' else '包含模板固有稀有度与机制。后续波次、普通随机稀有度和机制组合会改变这些值。'
        body+=details(f'第 {m["example_wave"]} 波模板示例',facts([(label,number(e[field])) for label,field in [('生命','max_health'),('护盾','max_shield'),('攻击基底 · 防御前','damage'),('速度','speed'),('攻击频率','attack_speed'),('经验奖励','xp_reward')]])+'<p>'+example_note+'</p>')
        cards.append(add('monsters',key,m['name'],summary,body,tier,related=link('rules','shared')+' · '+link('defenses','fire_resistance')))

    total_weight=sum(p['weight'] for p in data['current_loot_profile'])
    pool_rows=''.join(f'<tr><th scope="row">{esc(TYPES[p["pool_id"]])}</th><td>{number(p["weight"])}</td><td>{percent(p["weight"]/total_weight)}</td><td>{links("equipment",data["equipment_pools"][p["pool_id"]]["base_ids"])}</td></tr>' for p in data['current_loot_profile'])
    pool_table='<div class="table-scroll"><table><caption>当前自然奖励 · 原创词池权重（每次已产生的装备奖励）</caption><thead><tr><th>词池</th><th>权重</th><th>条件概率</th><th>底材</th></tr></thead><tbody>'+pool_rows+'</tbody></table></div>'
    configs=''.join(f'<p>{esc(x["name"])}：{equipped_links(x)}</p>' for config in ['fresh','full_tornado','local_normal','local_max'] for x in [data['configurations'][config]])
    historical_pools=''.join('<p>'+esc(version)+'：'+' / '.join(esc(TYPES[row['pool_id']])+' '+number(row['weight']) for row in rows)+'</p>' for version,rows in data['loot_profiles'].items() if version!=data['current_loot_profile_id'])
    basic_rows=''.join(f'<tr><th scope="row">{esc(data["configurations"][config]["name"])}</th><td>{esc(component_text(sample["hits"]["basic"]["packet"]["base"]))}</td><td>{number(sample["hits"]["basic"]["resolved"]["total"])}</td><td>{number(sample["hits"]["basic"]["known_target_resolved"]["total"])}</td></tr>' for config in ['local_normal','local_max'] for sample in [data['weapon_stages']['weapon_local']['examples'][config]])
    rule_defs=[
        ('encounters','本轮挑战与重开','有限可选挑战已实装；不是完整终局地图系统。', '<p>'+links('encounters',data['encounters'].keys())+'</p><p>可选零、一或两项；确认会结束当前战斗并重置怪物、时间与本轮击败数，构筑/经验/物品/材料保留。普通重试沿用本轮选择；恢复常规与试验场清空，重新加载游戏为常规。</p><p>没有额外奖励，不消耗地图物品，不写入构筑存档。根怪和整批子怪在入场前应用同一冻结配置，失败回滚RNG/未发布身份与队列，不回退成普通怪。详细规则见随包 ENCOUNTER_INTEGRATION 文档。</p>', 'implemented'),
        ('damage','伤害如何结算','每次施放先冻结构筑快照，再由技能编译器组装命中。条目分别标注防御前与已知目标抗性后的逐次命中，不是总伤害或每秒伤害。',configs+'<p>'+link('defenses','fire_resistance','查看一次命中的抗性与护盾流程')+'</p><p>原有固有分量、支持攻击命中的局部武器物理与匹配攻击/法术标签的外部附加点伤先分路组装；适用的提高同组相加，总增/总降分别相乘。独立爆炸具有自己的标签与附加效用。</p>','implemented'),
        ('supports','辅助装配','只有拥有所需能力的主动技能可装配辅助。同一技能不能重复装配同一辅助。',f'<p>每技能最多 {data["limits"]["max_supports"]} 个辅助；初始投射物上限 {data["limits"]["initial_projectiles"]}。{len(data["supports"])}种选择覆盖{len(data["skills"])}个主动技能；可用技能由原生配方固定，装备附加分量不会改变允许槽位。K仅显示兼容卡片。兼容性来自 SupportRegistry，数值来自 SkillCompiler；节能/疾咏改变耗魔和冷却，不改变施法动作速度。</p><p>'+links('supports',data['supports'])+'</p>','implemented'),
        ('projectiles','分裂、返回与飞行结束','龙卷母箭优先分裂；返回在抵达射程时朝当时角色中心取向，且每个载体至多一次。','<p>自然飞行结束可触发装备授予的爆炸。分裂、碰撞消耗和取消不会触发该爆炸；返回不刷新寿命。投射物增伤与投射物辅助不作用于独立爆炸。</p><p>'+links('fixed_items',['prism_bow','return_mantle','detonation_charm'])+'</p>','implemented'),
        ('equipment','装备与阶级','底材与词缀按自身阶段结算；局部武器项独立于角色统计。T1 → T3 是本游戏原创成长顺序；不是 PoE 官方阶级命名。',f'<p>物品等级 {data["limits"]["min_item_level"]}–{data["limits"]["max_item_level"]}。每次已产生的普通装备奖励按下表权重选择一个词池（当前 {esc(data["current_loot_profile_id"])}，权重合计 100）；不是每只怪物死亡的掉落概率，也不新增奖励分支。同族或同组不能重复出现。</p>'+pool_table+details('稀有度规则',facts([(r['name'],f'{r["min_affixes"]}–{r["max_affixes"]} 条；至多 {r["max_prefixes"]} 前缀 / {r["max_suffixes"]} 后缀') for r in data['equipment_rarities'].values()]))+'<p>装备 damage 仍为角色通用基础加值，护盾为角色全局容量；白蜡长弓的局部物理另由 '+link('weapon_stages','weapon_local')+' 结算。火卫的合格专属奖励仍强制选防御池，沿用一次奖励。</p>'+details('历史配置与存档兼容',historical_pools+f'<p>历史配置留给重放兼容，不再表示当前自然词池选择。当前存档结构 {data["save_version"]}；v8 迁移保留装备 ID、掷值、辅助与珠宝，保存迁移备份。更新不会免费赠送新弓或新增升级奖励。</p>'),'implemented'),
        ('basic_attack','普通攻击与武器贡献','普通自动攻击是独立的攻击消费者，不计入八个主动技能条目。','<p>长弓普通投射物接收长弓本地物理；锻纹短刃改为近战direct并接收短刃W，详见 '+link('rules','melee_basic')+'。法术与独立爆炸不接收W。以下两种构筑仅用于说明合法普通长弓与局部双前缀实例，仍保留原有角色基础伤害。</p><div class="table-scroll"><table><thead><tr><th>装备示例</th><th>原始分量</th><th>防御前</th><th>已知目标抗性后</th></tr></thead><tbody>'+basic_rows+'</tbody></table></div><p>'+link('weapon_stages','weapon_local')+' · '+link('rules','character_rates')+'</p>','implemented'),
        ('character_rates','恢复、移动与普通攻击速度','速度和恢复的固定加值先相加，再应用对应提高比率。','<p>普通攻击速度改变基础自动射击间隔；不缩短主动技能冷却。魔力恢复与移动速度分别使用自身比率。</p>','implemented'),
        ('allocation','天赋与珠宝规则','从起点沿连线分配天赋；珠宝只能镶入已分配的孔。普通珠宝提供属性，寻枝晶玉额外赋予范围内远程分配资格。','<p>'+lines(data['jewels'].get('branchfinder',{}).get('description',''))+'</p><p>覆盖图中的资格与连通状态由同一个 AllocationRules 分析器导出。图中可切换源孔失联示例：失联孔不激活覆盖。远程点不能向覆盖范围外扩路，也不能远程开启珠宝孔。</p><p><a href="#tree">查看原创新图与覆盖示例</a></p><p>本游戏半径、限定节点类型、首领奖励与原子拒绝卸除，均为原创实现规则；不是 PoE 数值或完整机制复刻。研究依据：<a href="https://www.pathofexile.com/forum/view-thread/1254452/page/2">GGG 范围与禁止向外扩路说明</a> · <a href="https://www.pathofexile.com/forum/view-thread/2792025">3.10.0c 珠宝更换连通修复</a> · <a href="https://www.pathofexile.com/forum/view-thread/3406659">3.21.1 Hotfix 3 替代来源修复</a>。</p>','implemented'),
        ('shared','玩家和怪物共享机制','天赋节点与怪物模板按同一个机制 ID 请求整组属性。怪物不支持的属性会使整个机制被拒绝。',details('玩家天赋合计上限',facts([(key,number(value)) for key,value in data['passive_caps'].items()]))+'<p>天赋合计先受自身安全上限约束；装备与珠宝另行结算。怪物稀有度、物种、波次与死亡模板保持独立。</p>','implemented'),
        ('boundaries','尚未实现的源游戏语义','本目录不表示复刻了源游戏的全部规则。未实现的研究项不能作为本游戏构筑能力使用。','<p>未实现：护甲减伤、抗性穿透、完整源游戏抗性引擎、武器品质、局部攻速/暴击、伤害范围、完整武器攻击基础替换、伤害转换、异常状态与暴击体系、召唤物、属性需求体系、星团与永恒珠宝重写、源游戏专属条件与资源机制，以及新增/替换词缀、升阶、定向制作和制作地图。当前仅实现回收与已有词缀数值校准。已经实现有限的局部物理武器阶段；这一早期火抗边界为历史说明；当前源天赋与灰烬皮甲可供给原始三抗，现行预算见三抗装备与最大抗性条目。上限、怪物接触分量、护甲数值和掉落权重均为本游戏原创规则。未来是否加入其他体系及具体语义尚未承诺。</p>','planned'),
        ('sources','数据来源与实现边界','游戏目录从本地运行时导出。PoE 资料是语义和数值校准研究；本页只呈现已实现的原创内容、原创新图与必要的来源标识。',f'<p>天赋研究：PoE {esc(data["sources"]["passive"]["version"])}；固定提交 {esc(data["sources"]["passive"]["commit"])}。</p><p>词缀研究：PoE {esc(data["sources"]["affix"]["source_version"])}；RePoE 固定提交 {esc(data["sources"]["affix"]["export_commit"])}。</p><p><a href="{esc(data["sources"]["passive"]["repository"])}">天赋来源仓库</a> · <a href="{esc(data["sources"]["affix"]["export_repository"])}">词缀导出仓库</a>（可选外部链接，需要联网）</p><p>版本只证明此快照的研究依据，不表示源游戏当前全量可用性。运行不使用源游戏图像，原树功能数据与原文的执行覆盖分别标注。</p>','research'),
    ]
    if 'canonical' in data:
        c=data['canonical']; source=data['source_tree']; example=c['five_link_example']; defense=c['defense_example']
        rule_defs=[row for row in rule_defs if row[0] not in ['supports','allocation','shared','boundaries','sources']]
        bag_text=f"背包{c['bag_pages']}页，每页{c['bag_columns']}×{c['bag_rows']}格，共{c['bag_pages']*c['bag_columns']*c['bag_rows']}格。"
        ownership='<figure><svg viewBox="0 0 650 150" role="img" aria-label="一件物品只有一个位置"><g fill="#ead3a2" stroke="#8c6b42"><rect x="10" y="45" width="190" height="60" rx="8"/><rect x="330" y="5" width="300" height="40" rx="8"/><rect x="330" y="55" width="300" height="40" rx="8"/><rect x="330" y="105" width="300" height="40" rx="8"/></g><g stroke="#79571f" fill="none"><path d="M200 75H260V25H330M260 75H330M260 75V125H330"/></g><g fill="#3b281b" font-size="16" text-anchor="middle"><text x="105" y="80">唯一 UID · 独立实例</text><text x="480" y="31">2页×12×10 背包 / 九装备位</text><text x="480" y="81">10+ 行技能 · 每行1主5辅</text><text x="480" y="131">天赋珠宝孔 / 迁移待安置</text></g></svg></figure>'
        ownership=ownership.replace('2页×8×6',f"{c['bag_pages']}页×{c['bag_columns']}×{c['bag_rows']}")
        slot_rows=facts([(SLOTS.get(slot,slot),esc(category)) for slot,category in c['slots'].items()])
        rule_defs.extend([
            ('ownership','统一物品与独立菜单','装备、珠宝、宝石、药剂和碎片都以唯一UID持有，一个实例只能处于一个位置。',ownership+slot_rows+'<p>I/B行囊固定右侧，K技能与角色属性共用左侧；两侧可同时打开并拖动宝石。T源树全屏，关闭后恢复原左右栏；菜单打开时背景战斗冻结。'+bag_text+'悬停详情，Shift比较双戒指目标。容量下降保留宝石和多余技能行，仅停用超出部分。旧装备UID与掷值保持，armor→body_armour、charm→amulet；旧技能/辅助转为独立实例，原始文件先备份，失败不覆盖。v0.26沿用v0.21试玩目录，旧schema14至17先原字节备份后原子迁移为schema18；仅首次新增两瓶入药剂槽1/2，不删除旧物品或再次退天赋点。</p>','implemented'),
            ('supports','技能行与五辅助','每行1个主宝石、5个辅助；10行起步，+1技能行词缀真正增加可绑定的行。',f'<p>原16辅助保留，新增点燃辅助仅适配陨星/龙卷；按主动技能原生能力判定资格；同组不重复同一辅助定义。同名主宝石可独立装配。组与主宝石UID双冷却账阻止换孔/换键刷新。</p><p>真实五辅助冰霜示例：耗魔 {number(example["mana"])}，冷却 {number(example["cooldown"])}秒，初始 {example["initial_count"]}发。</p>'+details('同源实际配方',lines(example['summary']+'\n'+example['details']))+'<p>正式档每30有效根怪累积一件固定26种序列的1级0品质宝石，满包保留待领；原序列不插入新石。点燃辅助通过正式商人4碎片购买或独立测试供应获得。测试随机宝石使用当前目录，失败回滚随机状态；后代/重复死亡无奖励。同名独立UID，正式城镇可回收所选背包宝石得1碎片。</p>','implemented'),
            ('source_tree','锁定源树与执行覆盖','完整源记录与已实现效果分别报告；数据存在不等于可花点使用。',f'<p>源版本 {source["source_version"]}，原始SHA256 {source["source_sha256"]}。保留 {len(source["nodes"])} 条记录、2387个标准位置和2697条内部边；升华/扩展分区分开。42代理与30涂油节点不可直接分配。<a href="#category-source_passives">逐项查源节点及精通</a></p><p>节点所有效果必须完整执行，精通按选中效果检查。未支持节点灰色锁定，也会阻断后续路径。源数值没有旧181投影上限；旧树仅作历史与怪物机制参考。</p><p>自己的职业起点免费，预算min(level+4,123)。普通节点/精通均1点，专精需同组普通连通的显著节点，重复效果ID拒绝。未分配其他节点可切七起点；升华点数来源尚未实现，不免费授点。</p>','implemented'),
            ('allocation','源树与珠宝资格','每件珠宝只有一个统一位置；孔必须已分配并沿普通连线连接自己的起点。','<p>寻枝半径280采用当前源坐标单位，允许小型/显著节点断连分配，仍花1点。远程点不向外扩路、不激活孔；未实现节点即使在范围内也不能分配。退款、移动、替换、取回都验证最终构筑，不能遗留依赖失效的节点。原型半径规则不是PoE某颗珠宝的完整复刻。</p><p>'+link('rules','source_tree')+'；下方旧181覆盖图保留作历史机制研究。</p>','implemented'),
            ('source_defenses','属性与命中防御','原始三属性数值进入真实容量、命中、闪避和近战物理作用域。','<p>力量每2点取整+1生命、每5点取整+1%近战物理；敏捷每点+2命中、每5点取整+1%闪避（分配铁反射（闪转甲）后取消此闪避提高并转换原始闪避，见 '+link('rules','iron_reflexes')+'）；智慧每2点取整+1魔力、每10点取整+1%护盾（3.28以后规则）。法术不进行攻击闪避。护甲随物理命中大小重新求减伤，三元素分别使用当前抗性上限（默认75%，最大抗性天赋可提高到本游戏安全上限83%），原始与有效值详见 '+link('rules','elemental_resistance_caps')+'，然后护盾、生命。分配心灵升华后，护盾剩余损伤先按比例交由当前魔力承担，详见 '+link('rules','mana_guard')+'。本段混合受击示例未分配该节点。</p>'+facts([('同源混合受击示例','物理/火/冰/电各100；护甲500、抗性50%/25%/75%'),('防御后分量',esc(component_text(defense['components']))),('护盾扣减',number(defense['shield_spent'])),('生命扣减',number(defense['health_lost']))])+f'<p>本游戏敏捷型怪物闪避320；默认Scion命中140，对应 {percent(c["skitter_accuracy_example"]["base_chance"])}；增加10敏捷后命中160，对应 {percent(c["skitter_accuracy_example"]["improved_chance"])}。预览展示成功命中伤害，未把命中率伪乘成DPS。</p>','implemented'),
            ('shared','共享消费者与历史注册表','人物和怪物共用伤害分量、防御、命中和结算函数。','<p>旧MechanicRegistry仍约束怪物机制包；旧181节点引用保留作研究与回归。当前人物改用原始源树逐项能力门槛，不能再套用旧投影合计上限。未支持机制继续拒绝，不借导入数据悄悄生效。</p>','implemented'),
            ('boundaries','尚未实现的机制','未执行源节点整体锁定，原文与位置保留。','<p>仍未完成：施法动作时长/施法速度、条件/局部武器暴击、格挡、压制、抗性穿透、完整异常与持续伤害体系（无条件火焰持续伤害加成与三节点更快燃烧已接入；流血和中毒仍未实现）、召唤物、属性装备需求、星团/永恒珠宝、升华点数来源及复杂条件机制。源树浏览不等于以上均可用。制作已有回收、校准、赋魔、升格、补缀与重铸；更复杂的定向制作尚未实现。</p>','planned'),
            ('sources','来源与实现边界','目录来自运行时导出，源树保留功能数据，所有美术由本项目创作。',f'<p><a href="{esc(source["source_url"])}">GGG源树固定提交 {source["source_commit"]}</a> · 3.29.1。保留节点身份、原始规则词句、精通和几何；未包含官方图像或叙事风味文本。上游数据再分发授权未明确，不宣称公共领域。</p><p>旧181节点与词缀校准研究仍有各自固定版本，不代表当前角色全部源效果已实现。原型怪物数值、掉落权重与熵初值由本项目定义。</p><p><a href="source-tree-coverage.json">完整执行覆盖与七职业可达前沿JSON</a>：空stats结构节点和精通本体不冒充属性效果，精通逐选项统计；可达集合不代表123点可以全部同时点出。</p>','research')
        ])
    rule_defs.append(('combat_feedback','实际战斗反馈','普通命中、暴击命中与燃烧按目标分别汇总，显示真正减少的护盾与生命。','<p>固定0.20秒聚合窗口，单条显示0.75秒，最多48条可见数值。普通命中和暴击不混桶；暴击带感叹号，燃烧带“燃”，玩家受伤为红色负号。死亡时立即完成末击，暂停冻结，返城或重开清空。</p><p>过量伤害、免疫、闪避和零损伤不计入数值。心灵升华支出的魔力独立记账，不混入护盾或生命浮字。燃烧不显示命中次数；不同技能同类可合计，因此不标单一技能名。此处是已结算损伤显示，不是DPS或平均伤害估算。</p><p>原伤害数字开关、字体缩放与相机缩放保持，不新增常驻统计面板。原命中位置和粒子随机抽样时序不变，反馈本身不取随机或保存进度。</p>','implemented'))
    if 'burning' in data:
        burn=data['burning'];rows=[]
        for skill,example in burn['examples'].items():
            for role,value in example['profile']['roles'].items():
                rows.append((link('skills',skill)+' · '+esc(role),f"非暴击未计火抗每秒 {number(value['dps'])}，3秒总量 {number(value['total'])}；已含直击代价"))
        body=facts(rows)+'<p>'+esc(burn['scope'])+'。'+esc(burn['stacking'])+'。</p><p>'+esc(burn['secondary'])+'。'+esc(burn['immunity'])+'。</p><p>灰烬示例原接触标量20：保物理14、立即火7、每秒火7/3持续3秒，原始完整总量28；实际免疫/抗性会减少扣伤。预警仍0.7秒/90范围，可走开。</p><p>'+esc(burn['source_words'])+'。状态不存盘，不抽命中或表现随机数；真实死亡仍只走一次原奖励。</p>'
        rule_defs.append(('burning','点燃与燃烧取舍','牺牲即时命中换基础3秒持续火伤；更快燃烧压缩时长，单目标不叠加。',body,'implemented'))
    if 'ember_proliferation' in data:
        ember=data['ember_proliferation'];policy=ember['player_policy'];spread=ember['proliferation_policy']
        def ember_value(key, value, text=None):
            return f'<strong data-ember-value="{esc(key)}" data-value="{esc(value)}">{esc(number(value) if text is None else text)}</strong>'
        body=facts([
            ('主命中倍率',ember_value('hit_multiplier',policy['hit_multiplier'])),
            ('魔力倍率',ember_value('mana_multiplier',policy['mana_multiplier'])),
            ('每秒火伤基数',ember_value('rate_fraction',policy['rate_fraction'],percent(policy['rate_fraction']))),
            ('直接施加秒数',ember_value('duration',policy['duration'])),
            ('扩散半径',ember_value('radius',spread['radius'])),
            ('最多目标',ember_value('max_targets',spread['max_targets'])),
            ('最多跳数',ember_value('max_hops',spread['max_hops'])),
            ('可装配技能',links('skills',ember['examples'])),
            ('互斥辅助',links('supports',ember['mutually_exclusive_with']))])
        rows=[]
        for skill,example in ember['examples'].items():
            for role,value in example['profile']['roles'].items():
                prefix=skill+'-'+role+'-'
                cells=[link('skills',skill)+' · '+esc(role)]+[ember_value(prefix+field,value[field]) for field in ['fire_before_defense','dps','total']]
                rows.append('<tr>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
        body+='<div class="table-scroll"><table><caption>伤害标量100、无其他辅助；非暴击，未计目标火抗，已含直击代价</caption><thead><tr><th>主命中</th><th>防御前火焰</th><th>燃烧每秒</th><th>直接燃烧完整总量</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
        sample=ember['transfer_example'];source_burn=sample['source'];transfer=sample['transfer']['burn'];recipient=sample['recipient']
        body+=details('同源一跳示例 · 保留绝对截止时间',facts([
            ('原始施加时刻',ember_value('started_at',sample['started_at'])),
            ('源目标死亡时刻',ember_value('transferred_at',sample['transferred_at'])),
            ('源燃烧每秒',ember_value('source_dps',source_burn['raw_dps'])),
            ('继承燃烧每秒',ember_value('transferred_dps',transfer['raw_dps'])),
            ('原绝对截止时间',ember_value('source_expiry',source_burn['provenance']['ember_expiry'])),
            ('继承绝对截止时间',ember_value('transferred_expiry',recipient['provenance']['ember_expiry'])),
            ('只剩秒数',ember_value('remaining',transfer['duration']))])+f'<p>已传播目标再次死亡：{esc(sample["second_hop"]["reason"])}，不产生第二跳。到原截止时间后：{esc(sample["at_expiry"]["reason"])}，不再传播。以上来自实际燃烧状态与扩散规则，尚未套用接收目标的火抗。</p>')
        selection=ember['selection_example']
        body+=details('同源选取示例 · 断墙遗迹实体墙',f'<p>10个可见存活候选按距离排序，实际选中ID：{esc("、".join(map(str,selection["target_ids"])))}。ID {selection["wall_blocked_id"]} 被实际地图墙阻挡；ID {selection["spawn_protected_id"]} 仍在出生保护；ID {selection["dead_id"]} 已死亡；ID {selection["outside_radius_id"]} 超出半径；ID {esc("、".join(map(str,selection["over_cap_ids"])))} 因目标上限未入选。源目标自身不入选，同距按ID排序。</p>')
        migration=ember['migration_example'];quote=ember['merchant_quote']
        body+=facts([('正式获取',link('town_services','skill_merchant','宝石商人')+' · '+ember_value('merchant_cost',quote['cost']['calibration_shard'])+' 校准碎片'),('保存版本',ember_value('save_version',ember['save_version'])),('迁移赠物',ember_value('granted_items',migration['granted_items'])),('当前辅助数量',str(len(data['supports'])))])
        body+='<p>'+esc(ember['scope'])+'。</p><p>'+esc(ember['transfer_rule'])+'。</p><p>'+esc(ember['instant_kill_rule'])+'。</p><p>'+esc(ember['stacking'])+'。</p><p>'+esc(ember['lifecycle'])+'。</p><p>'+esc(ember['migration'])+f'。同源迁移示例物品数量 {migration["items_before"]} → {migration["items_after"]}；仅变化字段 {esc("、".join(migration["changed_fields"]))}。正式击杀宝石奖励词表保持冻结，未加入此新辅助。</p>'
        body+='<p>'+link('supports','ember_proliferation')+' · '+link('supports','ignite')+' · '+link('rules','burning','原点燃与燃烧规则')+'</p>'
        rule_defs.append(('ember_proliferation','余烬扩散与剩余时长','以更低燃烧比例和更高魔力消耗换取死亡传播；接收者保留原每秒伤害与截止时间。',body,'implemented'))
    if 'shock' in data:
        shock=data['shock'];policy=shock['player_policy'];enemy=shock['enemy_policy'];attack=shock['enemy_attack']['profile']
        def shock_value(key, value, text=None):
            return f'<strong data-shock-value="{esc(key)}" data-value="{esc(value)}">{esc(number(value) if text is None else text)}</strong>'
        body=facts([
            ('主命中倍率',shock_value('hit_multiplier',policy['hit_multiplier'])),
            ('魔力倍率',shock_value('mana_multiplier',policy['mana_multiplier'])),
            ('玩家施加秒数',shock_value('duration',policy['duration'])),
            ('后续命中受伤提高',shock_value('hit_damage_taken_increased',policy['hit_damage_taken_increased'],percent(policy['hit_damage_taken_increased']))),
            ('可装配技能',links('skills',shock['examples']))])
        rows=[]
        for skill,example in shock['examples'].items():
            label=link('skills',skill)+(' · 首跳＋末跳预览合计' if skill=='chain' else ' · 每枚投射物' if skill=='bolt' else ' · 每次范围命中')
            cells=[label]+[shock_value(skill+'-'+field,example[field]) for field in ['before_hit','supported_hit','before_mana','mana']]
            rows.append('<tr>'+''.join('<td>'+cell+'</td>' for cell in cells)+'</tr>')
        body+='<div class="table-scroll"><table><caption>伤害标量100、无其他辅助；生产编译器的非暴击预览条目与魔力。连锁列为首跳与末跳两条预览相加，不是单次命中或整次施放总伤害；未计目标防御和既有感电</caption><thead><tr><th>主动技能与统计范围</th><th>原预览值</th><th>辅助后预览值</th><th>原魔力</th><th>辅助后魔力</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
        sample=shock['settlement_example']
        body+=details('先命中、后施加 · 同源结算示例',facts([
            ('施加感电的命中',shock_value('first_hit',sample['first_hit']['health_lost'])),
            ('后续同输入命中',shock_value('later_hit',sample['later_hit']['health_lost'])),
            ('感电期间相同数值燃烧',shock_value('burn_while_shocked',sample['burn_while_shocked']['health_lost'])),
            ('刷新时刻',shock_value('refreshed_at',sample['refresh_status']['status']['refreshed_at'])),
            ('刷新后截止时刻',shock_value('expires_at',sample['refresh_status']['status']['expires_at']))])+'<p>示例为100闪电命中或100火焰持续损伤，无抗性与护盾、1000生命；先结算再施加。10秒施加，10.5秒再次施加后刷新至12.5秒；正好到期时已不生效。此例不代表技能实际固定伤害或DPS。</p>')
        body+=details('敌方感电 · '+data['monsters'][shock['enemy_template']]['name'],facts([
            ('施加来源',link('monsters',shock['enemy_template'])+' · '+link('monster_attacks','locked_circle_lightning')),
            ('敌方施加秒数',shock_value('enemy_duration',enemy['duration'])),
            ('后续命中受伤提高',shock_value('enemy_increased',enemy['hit_damage_taken_increased'],percent(enemy['hit_damage_taken_increased']))),
            ('前摇预警秒数',shock_value('windup_seconds',attack['windup_seconds'])),
            ('预警半径',shock_value('radius',attack['radius'])),
            ('基准恢复秒数',shock_value('recovery_seconds',attack['recovery_seconds'])),
            ('即时命中倍率',shock_value('enemy_hit_multiplier',attack['damage_multiplier']))])+'<p>雷纹锁点震击实际造成正值闪电损伤后才施加1秒感电；即时倍率由原1.6调整为1.4，0.7秒预警、65半径与基准1.6秒恢复保持。可移出锁定范围躲避，攻速只缩放恢复时间。</p>')
        migration=shock['migration_example'];quote=shock['merchant_quote']
        body+=facts([
            ('正式获取',link('town_services','skill_merchant','宝石商人')+' · '+shock_value('merchant_cost',quote['cost']['calibration_shard'])+' 校准碎片'),
            ('测试供应',esc(shock['test_offer']['price_label'])+' · 独立测试档'),
            ('保存版本',shock_value('save_version',shock['save_version'])),
            ('迁移赠物',shock_value('granted_items',migration['granted_items']))])
        body+=''.join('<p>'+esc(shock[key])+'。</p>' for key in ['scope','settlement','damage_scope','stacking','lifecycle','migration','source_words'])
        body+=f'<p>同源迁移示例物品数量 {migration["items_before"]} → {migration["items_after"]}；仅变化字段 {esc("、".join(migration["changed_fields"]))}。正式击杀宝石奖励词表与旧奖励序号保持冻结，未加入此新辅助。</p><p>'+link('supports','shock')+' · '+link('rules','burning','持续伤害规则')+'</p>'
        rule_defs.append(('shock','感电与后续命中','以主命中和魔力代价换取短时后续命中增伤；玩家与怪物共用受击边界。',body,'implemented'))
    if 'source_fire_dot' in data:
        fire=data['source_fire_dot']
        def fire_value(key,value,as_percent=False):
            label=percent(value) if as_percent else number(value)
            return f'<span data-fire-dot-value="{esc(key)}" data-value="{esc(value)}">{label}</span>'
        body='<p>以下为schema32引入的火焰持续伤害加成及历史覆盖证据；schema33新增的压缩时长规则见'+link('rules','source_faster_burn')+'。</p>'+''.join('<p>'+esc(fire[key])+'。</p>' for key in ['formula','units','snapshot_rule','preview_rule','scope','transfer_rule'])
        node_rows=[]
        for node_id,node in fire['nodes'].items():
            node_rows.append('<tr><th>'+link('source_passives',node_id,localized_nodes[node_id]['name']+' · '+node_id)+'</th><td>'+fire_value('node-'+node_id,node['fraction'],True)+'</td><td>'+lines(source_lines(node['source_lines']))+'</td><td>全部效果已执行；schema31锁定</td></tr>')
        body+='<h3>8个完整源节点</h3><div class="table-scroll"><table><thead><tr><th>源节点</th><th>火焰持续伤害加成</th><th>完整源词句</th><th>执行门槛</th></tr></thead><tbody>'+''.join(node_rows)+'</tbody></table></div>'
        example_rows=[]
        for index,example in enumerate(fire['examples']):
            base=example['base'];after=example['increased']
            for role,part in after['burn_profile']['roles'].items():
                prefix=f'example-{index}-{role}-'
                before=base['burn_profile']['roles'][role]
                example_rows.append('<tr><th>'+links('source_passives',example['source_nodes'])+'<br>'+link('skills',example['skill_id'])+' · '+link('supports',example['support_id'])+' · '+esc(role)+'</th><td>'+fire_value(prefix+'fraction',example['fraction'],True)+'</td><td>'+fire_value(prefix+'fire',part['fire_before_defense'])+'</td><td>'+fire_value(prefix+'before-dps',before['dps'])+' → '+fire_value(prefix+'after-dps',part['dps'])+'</td><td>'+fire_value(prefix+'total',part['total'])+'</td><td>'+fire_value(prefix+'duration',after['burn_profile']['duration'])+'秒</td></tr>')
        body+='<h3>真实编译器前后示例</h3><p>'+esc(fire['example_scope'])+'。</p><p>全部数值为非暴击、防御前示例；同一行比较同一命中角色，不把龙卷母箭、子箭或多目标数值相加为实战DPS。显式零值与无来源的完整编译结构一致。</p><div class="table-scroll"><table><thead><tr><th>输入与命中角色</th><th>加成之和</th><th>原始主命中火分量</th><th>燃烧每秒：无来源 → 有来源</th><th>完整时长燃烧总量</th><th>时长</th></tr></thead><tbody>'+''.join(example_rows)+'</tbody></table></div>'
        legal_rows=[]
        for index,example in enumerate(fire['legal_build_examples']):
            profile=example['cast']['burn_profile']
            legal_rows.append('<tr><th>职业'+str(example['class_id'])+' → '+link('source_passives',example['target'])+'</th><td>'+str(example['points_spent'])+'点 / 最低'+str(example['required_level'])+'级</td><td>'+fire_value(f'legal-{index}-fraction',example['stats']['fire_dot_multiplier_add'],True)+'</td><td>'+fire_value(f'legal-{index}-dps',profile['roles']['direct']['dps'])+'</td></tr>')
        body+=details('完整合法路线 · 保留沿途全部属性','<div class="table-scroll"><table><thead><tr><th>真实路线</th><th>预算</th><th>合计火焰持续伤害加成</th><th>点燃陨星每秒火伤</th></tr></thead><tbody>'+''.join(legal_rows)+'</tbody></table></div>')
        paths=''
        for entry in fire['class_paths']:
            rows=''.join('<tr><th>'+link('source_passives',node_id)+'</th><td>'+str(len(path)-1)+'</td><td>'+ ' → '.join(link('source_passives',n,n) for n in path)+'</td></tr>' for node_id,path in entry['paths_to_new_nodes'].items())
            paths+=details('职业'+str(entry['class_id'])+' · 八节点完整可分配路径','<p>非起点普通节点可达数 '+str(entry['old_reachable_count'])+' → '+str(entry['new_reachable_count'])+'；每条路线均通过当前完整构筑验证，旧schema31拒绝。</p><div class="table-scroll"><table><thead><tr><th>目标</th><th>点数</th><th>路径ID（含免费起点）</th></tr></thead><tbody>'+rows+'</tbody></table></div>')
        body+='<p>'+esc(fire['coverage_note'])+'。'+esc(fire['complete_gate'])+'。</p>'+paths
        body+='<p>边界核对：'+link('source_passives','12738',localization['partitions']['Elementalist']+'升华记录12738')+'的词句可完整解析，但不在标准可分配图，升华点数来源仍未接入。火焰精通36313的加成词句可解析，但其“'+esc(source_lines(['50% increased Ignite Duration on you']))+'”未实现，全部8处入口仍按完整效果门槛锁定；这两类记录均未新增可分配机制。</p>'
        transfer=fire['transfer_example'];source=transfer['source'];recipient=transfer['recipient']
        body+='<h3>余烬只继承一次</h3>'+facts([('施放加成',fire_value('transfer-fraction',transfer['fraction'],True)),('已增强的来源每秒火伤',fire_value('transfer-source-dps',source['raw_dps'])),('接收者每秒火伤',fire_value('transfer-recipient-dps',recipient['raw_dps'])),('开始 / 传播时刻',fire_value('transfer-started-at',transfer['started_at'])+' / '+fire_value('transfer-at',transfer['transferred_at'])),('共同绝对截止时间',fire_value('transfer-expiry',source['provenance']['ember_expiry'])),('接收者剩余秒数',fire_value('transfer-duration',transfer['transfer']['burn']['duration']))])
        migration=fire['migration_example']
        body+='<p>'+esc(fire['legacy_rule'])+'。同源迁移示例 '+str(migration['from_version'])+' → '+str(migration['to_version'])+'，变化字段仅 '+esc('、'.join(migration['changed_fields']))+'。</p><p>未接入：'+esc('、'.join(fire['unsupported']))+'；本批没有新增图像。</p>'
        body+='<p>'+link('rules','burning','点燃与燃烧')+' · '+link('rules','ember_proliferation')+' · '+link('rules','shock')+' · '+link('rules','source_tree','完整源树与分配规则')+' · <a href="source-tree-coverage.json">同源执行覆盖JSON</a></p>'
        rule_defs.append(('source_fire_dot','源天赋火焰持续伤害加成','合计源节点的无条件火焰持续伤害加成，在获准施放时冻结，只乘入一次燃烧每秒伤害。',body,'implemented'))
    if 'source_faster_burn' in data:
        faster=data['source_faster_burn']
        def faster_value(key,value,as_percent=False):
            label=percent(value) if as_percent else number(value)
            return f'<span data-faster-burn-value="{esc(key)}" data-value="{esc(value)}">{label}</span>'
        body=''.join('<p>'+esc(faster[key])+'。</p>' for key in ['formula','units','total_rule','snapshot_rule','preview_rule','zero_rule','scope','transfer_rule'])
        node_rows=[]
        for node_id,node in faster['nodes'].items():
            node_rows.append('<tr><th>'+link('source_passives',node_id,localized_nodes[node_id]['name']+' · '+node_id)+'</th><td>'+faster_value('node-'+node_id,node['fraction'],True)+'</td><td>'+lines(source_lines(node['source_lines']))+'</td><td>全部效果已执行；schema32锁定</td></tr>')
        body+='<h3>3个完整源节点</h3><div class="table-scroll"><table><thead><tr><th>源节点</th><th>更快伤害异常</th><th>完整源词句</th><th>执行门槛</th></tr></thead><tbody>'+''.join(node_rows)+'</tbody></table></div>'
        rows=[]
        for index,example in enumerate(faster['examples']):
            base=example['base']['burn_profile'];after=example['faster']['burn_profile']
            for role,part in after['roles'].items():
                before=base['roles'][role];prefix=f'example-{index}-{role}-'
                rows.append('<tr><th>'+link('skills',example['skill_id'])+' · '+link('supports',example['support_id'])+'<br>'+esc(role)+'</th><td>'+faster_value(prefix+'m',example['fire_dot_multiplier'],True)+' / '+faster_value(prefix+'f',example['faster_fraction'],True)+'</td><td>'+faster_value(prefix+'fire',part['fire_before_defense'])+'</td><td>'+faster_value(prefix+'before-dps',before['dps'])+' → '+faster_value(prefix+'after-dps',part['dps'])+'</td><td>'+faster_value(prefix+'before-duration',base['duration'])+' → '+faster_value(prefix+'after-duration',after['duration'])+'</td><td>'+faster_value(prefix+'before-total',before['total'])+' → '+faster_value(prefix+'after-total',part['total'])+'</td></tr>')
        body+='<h3>真实编译器：提高每秒伤害，同时缩短时长</h3><p>'+esc(faster['example_scope'])+'。</p><p>每行均为同一非暴击、防御前命中角色，显示生产编译器已算好的数值；不把龙卷母子、多目标或完整时长总量相加作为实战DPS。</p><div class="table-scroll"><table><thead><tr><th>主命中角色</th><th>M / F</th><th>原始主命中火分量</th><th>每秒：旧 → 加速</th><th>秒数：旧 → 加速</th><th>理论完整总量：旧 → 加速</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
        for index,example in enumerate(faster['legal_build_examples']):
            profile=example['cast']['burn_profile']
            body+=details('完整合法三节点支路 · 职业'+str(example['class_id']),'<p>'+' → '.join(link('source_passives',n,n) for n in example['allocated'])+'</p>'+facts([('预算',str(example['points_spent'])+'点 / 最低'+str(example['required_level'])+'级'),('合计F',faster_value(f'legal-{index}-f',example['stats'][faster['stat']],True)),('真实点燃陨星每秒火伤',faster_value(f'legal-{index}-dps',profile['roles']['direct']['dps'])),('最终秒数',faster_value(f'legal-{index}-duration',profile['duration'])),('理论完整总量',faster_value(f'legal-{index}-total',profile['roles']['direct']['total']))]))
        body+='<p>'+esc(faster['coverage_note'])+'。</p>'
        for entry in faster['class_paths']:
            rows=''.join('<tr><th>'+link('source_passives',node_id)+'</th><td>'+str(len(path)-1)+'</td><td>'+' → '.join(link('source_passives',n,n) for n in path)+'</td></tr>' for node_id,path in entry['paths_to_new_nodes'].items())
            body+=details('职业'+str(entry['class_id'])+' · 三节点完整可分配路径','<p>非起点普通节点可达数 '+str(entry['old_reachable_count'])+' → '+str(entry['new_reachable_count'])+'；实际完整构筑通过，旧schema32拒绝。这是分别可达的路线，不代表123点能全部同时分配。</p><div class="table-scroll"><table><thead><tr><th>目标</th><th>点数</th><th>路径ID（含免费起点）</th></tr></thead><tbody>'+rows+'</tbody></table></div>')
        gate=faster['complete_gate'].replace('partial','部分执行')
        for node_id,node in faster['blocked_matching_nodes'].items():
            gate=gate.replace(node['name'],localized_nodes[node_id]['name'])
        body+='<p>'+esc(gate)+'。</p>'
        for node_id,node in faster['blocked_matching_nodes'].items():
            body+='<p>'+link('source_passives',node_id,localized_nodes[node_id]['name']+' · '+node_id)+'：'+lines(source_lines(node['execution']['unsupported']))+'；仍锁定，不计入新增完整节点。</p>'
        transfer=faster['transfer_example'];origin=transfer['source'];recipient=transfer['recipient']
        body+='<h3>余烬继承压缩后的截止时间</h3>'+facts([('M / F',faster_value('transfer-m',transfer['fire_dot_multiplier'],True)+' / '+faster_value('transfer-f',transfer['faster_fraction'],True)),('来源每秒火伤',faster_value('transfer-source-dps',origin['raw_dps'])),('接收者每秒火伤',faster_value('transfer-recipient-dps',recipient['raw_dps'])),('开始 / 传播时刻',faster_value('transfer-started-at',transfer['started_at'])+' / '+faster_value('transfer-at',transfer['transferred_at'])),('共同绝对截止时间',faster_value('transfer-expiry',origin['provenance']['ember_expiry'])),('接收者剩余秒数',faster_value('transfer-duration',transfer['transfer']['burn']['duration']))])+'<p>到压缩后的截止时间不再传播；接收者没有再获得基础3秒或完整2.4秒。</p>'
        migration=faster['migration_example']
        body+='<p>'+esc(faster['legacy_rule'])+'。同源迁移示例 '+str(migration['from_version'])+' → '+str(migration['to_version'])+'，变化字段仅 '+esc('、'.join(migration['changed_fields']))+'。</p><p>尚未接入：'+esc('、'.join(faster['unsupported']))+'；本批没有新增图像。</p>'
        body+='<p>'+link('rules','source_fire_dot')+' · '+link('rules','burning','点燃与燃烧')+' · '+link('rules','ember_proliferation')+' · '+link('rules','shock')+' · '+link('rules','source_tree','完整源树与分配规则')+' · <a href="source-tree-coverage.json">同源执行覆盖JSON</a></p>'
        rule_defs.append(('source_faster_burn','源天赋加速燃烧','三节点合计25%更快：每秒伤害乘1.25，基础3秒压缩至2.4秒，理论完整总量保持。',body,'implemented'))
    if 'forgeblade' in data:
        rule_defs.append(('forgeblade',RULE_TITLES['forgeblade'],'本地物理4、六族合法词池；W增强普通近战与裂刃direct，全局暴击与资源仍保持原范围。',forgeblade_rule(data,link,facts,details),'implemented'))
    if 'melee_basic' in data:
        rule_defs.append(('melee_basic',RULE_TITLES['melee_basic'],'短刃普攻使用独立近战派送，保留原攻击间隔；与裂刃几何、资源及逐次伤害分开展示。',melee_basic_rule(data,link,facts,details),'implemented'))
    if 'resolute_technique' in data:
        rule_defs.append(('resolute_technique',RULE_TITLES['resolute_technique'],'命中不能被闪避，但所有命中不能暴击；已有装备与天赋仍需权衡。',resolute_technique_rule(data,link,facts,details),'implemented'))
    if 'defense_rating_affixes' in data:
        rule_defs.append(('defense_rating_affixes',RULE_TITLES['defense_rating_affixes'],'全局固定护甲与闪避占用已有前缀，物理命中、攻击准入和持续燃烧各有明确边界。',defense_rating_affix_rule(data,link,facts,details),'implemented'))
    if 'iron_reflexes' in data:
        rule_defs.append(('iron_reflexes',RULE_TITLES['iron_reflexes'],'全部原始闪避转换为护甲，取消敏捷闪避提高；同一句双提高只计一次，失去闪避仍有代价。',iron_reflexes_rule(data,link,facts,details),'implemented'))
    if 'frost_lock' in data:
        rule_defs.append(('frost_lock',RULE_TITLES['frost_lock'],'冰霜脉冲主命中乘0.75、魔力乘1.20；仅正值实际冰伤使存活敌人短暂冻结，解冻后免疫1.50秒。',frost_lock_rule(data,link,facts,details),'implemented'))
    if 'glove_ring_affixes' in data:
        rule_defs.append(('glove_ring_affixes',RULE_TITLES['glove_ring_affixes'],'既有手套新增固定命中前缀，既有双戒新增三抗后缀；通过实际Main的阈值与抗性供给对照。',glove_ring_affix_rule(data,link,facts,details),'implemented'))
    if 'precise_technique' in data:
        rule_defs.append(('precise_technique',RULE_TITLES['precise_technique'],'最终命中值严格高于最大生命时，攻击伤害额外提高40%；选中后始终不能暴击。',precise_technique_rule(data,link,facts,details),'implemented'))
    if 'physical_fire_conversion' in data:
        rule_defs.append(('physical_fire_conversion',RULE_TITLES['physical_fire_conversion'],'原始物理组装后40%转火；逐条伤害来源、专注取舍、燃烧与物理偷取边界。',physical_fire_conversion_rule(data,link,facts,details),'implemented'))
    if 'zealots_oath' in data:
        rule_defs.append(('zealots_oath',RULE_TITLES['zealots_oath'],'原始固定再生加百分比乘最终护盾；生命再生归零，护盾充能、药剂与偷取仍独立。',zealots_oath_rule(data,link,facts,details),'implemented'))
    if 'ambush' in data:
        rule_defs.append(('ambush',RULE_TITLES['ambush'],'技能改为脚下预置，布防后由活敌触发；共享三枚，未触发过期不爆炸。',ambush_rule(data,link,facts,details),'implemented'))
    if 'inward_pull' in data:
        rule_defs.append(('inward_pull',RULE_TITLES['inward_pull'],'新星与陨星将原冲量反转朝向真实爆发圆心；魔力乘1.20，伤害、冷却与范围不变。',inward_pull_rule(data,link,facts,details),'implemented'))
    if 'elemental_defense_affixes' in data:
        rule_defs.append(('elemental_defense_affixes',RULE_TITLES['elemental_defense_affixes'],'一件胸甲提供原始火、冰、电抗性；三抗满后缀仍须天赋补足原始值与最大上限。',elemental_defense_affix_rule(data,link,facts,details),'implemented'))
    if 'elemental_resistance_caps' in data:
        rule_defs.append(('elemental_resistance_caps',RULE_TITLES['elemental_resistance_caps'],'原始抗性仍需另行获得；默认上限75%，三元素最大抗性可分别提高到本游戏安全上限83%。',elemental_resistance_cap_rule(data,link,facts,details),'implemented'))
    if 'mana_guard' in data:
        guard=data['mana_guard']
        def guard_value(key,value,as_percent=False):
            label=percent(value) if as_percent else number(value)
            return f'<span data-mana-guard-value="{esc(key)}" data-value="{esc(value)}">{label}</span>'
        body=facts([('关键天赋',link('source_passives',guard['node']['id'])),('魔力先承伤比例',guard_value('fraction',guard['profile']['fraction'],True)),('最低存档版本',guard_value('save-version',guard['minimum_save_version'])),('未分配时',guard_value('disabled-fraction',guard['disabled_profile']['fraction'],True))])
        body+=''.join('<p>'+esc(guard[key])+'。</p>' for key in ['order','resource_rule','damage_basis'])
        body+='<h3>相同100损伤：命中与燃烧共享资源顺序</h3><p>'+esc(guard['example_scope'])+'。</p>'
        labels={'full_mana':'无盾、足魔','low_mana':'无盾、仅10魔力','partial_shield':'30护盾、足魔','full_shield':'护盾完全吸收','empty_mana':'魔力耗尽','lethal':'资源不足、致死'}
        fields=['damage_total','shield_spent','mana_spent','health_lost','overkill','remaining_shield','remaining_mana','remaining_health']
        rows=[]
        for key,example in guard['examples'].items():
            initial=example['input']
            for kind,label in [('hit','命中'),('burn','燃烧')]:
                rows.append('<tr><th>'+esc(labels[key])+' · '+label+'<br>起始盾/魔/血 '+number(initial['shield'])+'/'+number(initial['mana'])+'/'+number(initial['health'])+'</th>'+''.join('<td>'+guard_value(key+'-'+kind+'-'+field,example[kind][field])+'</td>' for field in fields)+'</tr>')
        body+='<div class="table-scroll"><table><thead><tr><th>独立示例</th><th>防御后损伤</th><th>盾支出</th><th>魔力支出</th><th>生命扣减</th><th>过量</th><th>剩余盾</th><th>剩余魔力</th><th>剩余生命</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div>'
        mixed=guard['mixed_mitigation_example']
        body+=details('混合伤害、护甲抗性与感电顺序','<p>物理/火/冰/电各100、混沌25，护甲500，火抗25%、冰抗50%、闪电原始抗性500%被限制到75%；15%感电只增强命中。初始护盾50、魔力100、生命200。</p>'+facts([('防御与感电后',guard_value('mixed-damage',mixed['damage_total'])),('盾支出',guard_value('mixed-shield',mixed['shield_spent'])),('魔力支出',guard_value('mixed-mana',mixed['mana_spent'])),('生命扣减',guard_value('mixed-health',mixed['health_lost']))]))
        body+='<p>'+esc(guard['zero_rule'])+'。三个入口的省略参数与显式0示例均由Godot比较完整Variant字节；冻结v57的完整规则回归见随版本交付的集中测试记录。</p>'
        body+='<h3>源词句和完整效果门槛</h3><p>'+lines(source_lines(guard['node']['source_lines']))+'。</p><p>'+esc(guard['complete_gate'])+'。</p>'
        for node_id,node in guard['blocked_matching_nodes'].items():
            body+='<p>'+link('source_passives',node_id,localized_nodes[node_id]['name']+' · '+node_id)+'：未实现词句 '+lines(source_lines(node['execution']['unsupported']))+'。</p>'
        body+='<p>'+esc(guard['route_scope'])+'。</p>'
        class_names={0:'贵族',1:'野蛮人',2:'游侠',3:'女巫',4:'决斗者',5:'圣堂武僧',6:'暗影刺客'}
        for route in guard['class_paths']:
            key=str(route['class_id'])
            body+=details(class_names[route['class_id']]+' · '+str(route['points_spent'])+'点受支持路线','<p>'+' → '.join(link('source_passives',node_id,node_id) for node_id in route['allocated'])+'</p>'+facts([('所需天赋点',guard_value('route-'+key+'-points',route['points_spent'])),('最低等级预算',guard_value('route-'+key+'-level',route['required_level'])),('完整构筑权威比例',guard_value('route-'+key+'-fraction',route['profile']['fraction'],True))])+'<p>候选通过当前完整构筑验证；旧schema34拒绝该新节点。保留沿途全部属性，无写档。</p>')
        migration=guard['migration_example']
        body+='<p>'+esc(guard['legacy_rule'])+'。同源内存迁移示例 '+str(migration['from_version'])+' → '+str(migration['to_version'])+'，变化字段仅 '+esc('、'.join(migration['changed_fields']))+'；新35文件不宣称与旧34文件字节相同。</p><p>尚未接入：'+esc('、'.join(guard['unsupported']))+'。本批没有新增图像。</p>'
        body+='<p>'+link('rules','source_tree','源树与分配规则')+' · '+link('rules','source_defenses','命中防御')+' · '+link('rules','burning','点燃与燃烧')+' · '+link('rules','source_mana_cost','魔力成本')+' · '+link('rules','source_leech','偷取')+' · <a href="source-tree-coverage.json">同源执行覆盖JSON</a></p>'
        rule_defs.append(('mana_guard',RULE_TITLES['mana_guard'],'护盾先吸收，再以当前魔力承担剩余损伤的40%；魔力不足部分由生命承担。',body,'implemented'))
    if 'source_spatial' in data:
        spatial=data['source_spatial']
        rows=[]
        for example in spatial['examples']:
            before,after=example['before']['recipe'],example['after']['recipe']
            if 'radius' in after: values=f"半径 {number(before['radius'])} → {number(after['radius'])}；面积倍率 {number(after['area_multiplier'])}"
            else: values=f"母箭速度 {number(before['parent']['speed'])} → {number(after['parent']['speed'])}；子箭速度 {number(before['child']['speed'])} → {number(after['child']['speed'])}"
            rows.append((link('source_passives',example['input']['node_id']),esc(values)))
        diagram='<figure><svg viewBox="0 0 600 140" role="img" aria-label="面积增加与半径平方根"><circle cx="90" cy="70" r="43" fill="#ecd59d" stroke="#987044"/><circle cx="275" cy="70" r="45.51" fill="#e8c982" stroke="#987044"/><path d="M150 70H212" stroke="#987044"/><g fill="#493523" font-size="14" text-anchor="middle"><text x="90" y="132">基础面积</text><text x="275" y="132">面积 +12%</text><text x="467" y="60">半径 × sqrt(1.12)</text><text x="467" y="86">伤害独立结算</text></g></svg></figure>'
        body=diagram+facts(rows)+'<p>'+esc(spatial['area_formula'])+'</p><p>'+esc(spatial['speed_formula'])+'</p><p>'+esc(spatial['secondary_explosion_scope'])+'。'+esc(spatial['snapshot_rule'])+'。</p><p>速度增幅不延长射程或寿命；仍由先到达的边界决定分裂、返回或结束，撞墙不触发自然到期效果。范围伤害与范围面积是两个独立属性；范围不增加珠宝覆盖、拾取距离或敌人预警。</p><p>'+esc(spatial['example_scope'])+'。</p><p>'+esc(spatial['legacy_rule'])+'。条件、武器限定、光环与召唤物等范围词句继续逐项锁定。</p>'
        rule_defs.append(('source_spatial','源天赋范围与投射速度','已有源树属性现在驱动实际命中半径、母子飞行与返回速度；按面积开方计算半径。',body,'implemented'))
    if 'source_recharge' in data:
        recharge=data['source_recharge'];rows=[]
        for ex in recharge['examples']:
            rows.append((link('source_passives',ex['node_id']),f"每秒 {number(ex['before']['rate'])} → {number(ex['after']['rate'])}；新损伤等待 {number(ex['before']['delay'])} → {number(ex['after']['delay'])}秒"))
        diagram='<figure><svg viewBox="0 0 640 120" role="img" aria-label="有效损伤后等待再充能"><path d="M30 75H330L590 25" fill="none" stroke="#618886" stroke-width="4"/><path d="M30 15V93M330 15V93" stroke="#aa8052" stroke-dasharray="4 4"/><g fill="#493523" font-size="15"><text x="16" y="114">有效损伤</text><text x="125" y="55">完整等待</text><text x="286" y="114">等待结束</text><text x="425" y="82">剩余时间 × 当前每秒速率</text></g></svg></figure>'
        body=diagram+facts(rows)+'<p>'+esc(recharge['rate_formula'])+'。</p><p>'+esc(recharge['delay_formula'])+'。</p><p>'+esc(recharge['timing'])+'。'+esc(recharge['changes'])+'。</p><p>'+esc(recharge['ward'])+'。</p><p>'+esc(recharge['example_scope'])+'；玩家与怪物使用同一计算器。</p><p>'+esc(recharge['legacy_rule'])+'。含未实现额外效果的节点继续整体锁定。</p>'
        rule_defs.append(('source_recharge','源天赋护盾充能','提高每秒回复并缩短下一次受击等待；沿本游戏既有平面基底，不改变即时护盾技能。',body,'implemented'))
    if 'source_mana_cost' in data:
        cost=data['source_mana_cost'];rows=[]
        for example in cost['examples']:
            factors=example['source_factors'];label=' + '.join(link('source_passives',n['node_id']) for n in example['source_nodes'])
            rows.append((label,f"辅助后 {number(factors['support_mana'])} × {number(factors['numerator'])} / {number(factors['denominator'])} = {number(factors['final_mana'])} 魔力"))
        diagram='<figure><svg viewBox="0 0 650 110" role="img" aria-label="魔力成本相乘再除效率"><g fill="#eeddb5" stroke="#8e704f"><rect x="12" y="28" width="150" height="52" rx="7"/><rect x="235" y="28" width="172" height="52" rx="7"/><rect x="486" y="28" width="150" height="52" rx="7"/></g><g fill="#493523" font-size="14" text-anchor="middle"><text x="87" y="60">辅助后魔力</text><text x="321" y="60">×成本 / 成本效率</text><text x="561" y="60">实际扣费</text><text x="198" y="59">→</text><text x="446" y="59">→</text></g></svg></figure>'
        body=diagram+facts(rows)+f"<p>9个新增完整普通节点；另有{len(cost['mastery']['entrances'])}处入口共享同一个15%效率精通（ID {cost['mastery']['effect_id']}），只能选一次，仍需本组显著节点与1点预算。</p>"+'<p>'+esc(cost['formula'])+'。</p><p>'+esc(cost['formula_origin'])+'。100%效率让成本减半，不是免费施放；沿既有浮点成本，不改整数舍入。</p><p>'+esc(cost['example_scope'])+'。</p><p>普通自动攻击仍免费。法力不足、完整弹体空间不足或冷却中都不扣费；已产生冷却债务保持。K行摘要与宝石当前组合悬停读同一最终数值。</p><p>'+esc(cost['legacy_rule'])+'。法术/诅咒/链接限定、生命转费和保留效率不在本批。</p>'
        rule_defs.append(('source_mana_cost','源天赋魔力成本取舍','效率与更高耗魔的魔力容量节点一起接入十个主动技能；与现有辅助同源结算。',body,'implemented'))
    if 'source_flasks' in data:
        flasks=data['source_flasks'];rows=[]
        for example in flasks['examples']:
            life=example['profiles']['flask:life'];mana=example['profiles']['flask:mana']
            rows.append((link('source_passives',example['node_id']),f"生命瓶 {number(life['recovery_total'])}；魔力瓶 {number(mana['recovery_total'])}；每个有效根怪 {number(life['charges_per_root'])} 充能"))
        charge_rows=''.join(f'<tr><td>{r["root_kills"]}</td><td>{r["whole_charges"]}</td><td>{number(r["remainder_micro"]/flasks["charge_unit"])}</td></tr>' for r in flasks['charge_rows'] if r['root_kills'] in [1,6,7,13,14,20])
        diagram='<figure><svg viewBox="0 0 650 110" role="img" aria-label="药剂使用冻结回复与根怪小数充能"><g fill="#eeddb5" stroke="#8e704f"><rect x="12" y="22" width="168" height="62" rx="7"/><rect x="235" y="22" width="172" height="62" rx="7"/><rect x="462" y="22" width="176" height="62" rx="7"/></g><g fill="#493523" font-size="14" text-anchor="middle"><text x="96" y="59">用瓶冻结本次总回复</text><text x="321" y="46">3秒内分次恢复</text><text x="321" y="69">受当前上限限制</text><text x="550" y="46">有效根怪充能</text><text x="550" y="69">按UID累计小数</text><text x="207" y="59">→</text></g></svg></figure>'
        body=diagram+facts(rows)+'<p>'+esc(flasks['example_scope'])+'。</p><p>'+esc(flasks['recovery_formula'])+'。'+esc(flasks['locked_recovery'])+'。</p><p>'+esc(flasks['charge_formula'])+'。'+esc(flasks['charge_lifecycle'])+'。</p><p>下面以15%充能获取、空瓶为例；余量保留到凑整点，20个有效根怪累计23点。</p><table><thead><tr><th>有效根怪数</th><th>可用整充能</th><th>保留小数</th></tr></thead><tbody>'+charge_rows+'</tbody></table><p>'+esc(flasks['reward_gate'])+'。'+esc(flasks['unchanged'])+'。</p><p>运行态充能与余量不进入存档；重开、回城和切换档案沿原战斗生命周期重置。</p><p>'+esc(flasks['legacy_rule'])+f'。本批{len(flasks["new_complete_ordinary_nodes"])}个新增完整普通节点；包含未实现附加效果的节点仍整体锁定。</p>'
        rule_defs.append(('source_flasks','源天赋药剂构筑','生命与魔力药剂回复、根怪充能获取一起生效，保留用瓶时机与满充能取舍。',body,'implemented'))
    if 'source_leech' in data:
        leech=data['source_leech']; rows=[]
        for example in leech['examples']:
            parts=[]
            for resource,label in [('health','生命'),('mana','法力')]:
                p=example['profile'][resource]
                parts.append(f'{label}：攻击 {p["attack_fraction"]*100:.2f}% / 物理攻击 {p["physical_attack_fraction"]*100:.2f}%；单次 {p["instance_rate"]:.2f}/秒，总上限 {p["total_rate_cap"]:.2f}/秒')
            rows.append((f'{example["required_level"]}级 / {example["points_spent"]}点', '；'.join(parts)))
        body=facts(rows)+''.join('<p>'+esc(leech[key])+'。</p>' for key in ['damage_basis','amount_formula','rate_formula','cap_formula','lifecycle','scope','coverage_note'])
        rule_defs.append(('source_leech','生命与法力偷取','真实攻击损伤转为受速率上限约束的持续恢复，两资源独立清账。',body,'implemented'))
    if 'source_critical' in data:
        critical=data['source_critical'];rows=[]
        for example in critical['examples']:
            label=' + '.join(link('source_passives',n['id']) for n in example['source_nodes']) or '本游戏基底'
            text=[]
            for skill,profile in example['profiles'].items():
                p=profile['primary'];text.append(f"{data['skills'][skill]['name']}：{percent(p['chance'])}几率 / {percent(p['multiplier'])}伤害")
            rows.append((label,esc('；'.join(text))))
        body=facts(rows)+'<p>'+esc(critical['balance_change'])+'。</p><p>'+esc(critical['chance_formula'])+'；'+esc(critical['multiplier_formula'])+'。</p><p>'+esc(critical['cast_rule'])+'。</p><p>'+esc(critical['secondary_rule'])+'。</p><p>'+esc(critical['damage_order'])+'。</p><p>'+esc(critical['randomness'])+'。</p><p>'+esc(critical['example_scope'])+'。</p><p>'+esc(critical['legacy_rule'])+f'。本批{len(critical["new_complete_ordinary_nodes"])}个新增完整普通节点，0个新增精通效果；45个新节点可从七起点经受支持路径抵达，余1个仍被未实现邻接效果隔开。可达不代表123点能同时全部分配。</p><p>玩家普通攻击和八种伤害主动共用实现；闪步与护盾不抽取暴击。K预估列出非暴击命中伤害以及最终概率/倍率，不冒称平均伤害或DPS。幸运、局部武器、条件、暴击触发和异常机制继续锁定。</p>'
        rule_defs.append(('source_critical','暴击与构筑作用域','全局、法术、近战与投射攻击暴击进入冻结施放，独立爆炸另取全局属性。',body,'implemented'))
    for key,name,summary,body,status in rule_defs: cards.append(add('rules',key,name,summary,body,{'implemented':'已实现规则','research':'研究来源','planned':'未实现边界'}[status],status))
    category_counts={cat:sum(x['cat']==cat for x in records) for cat,_ in CATEGORIES}
    nav=''.join(f'<a href="#category-{cat}" id="category-{cat}" class="nav-link" data-category="{cat}"><span>{label}</span><span>{category_counts[cat]}</span></a>' for cat,label in CATEGORIES)
    options=''.join(f'<option value="{esc(k)}">{esc(data["passives"][k]["name"])} · {esc(k)}</option>' for k in data['special_coverage'])
    svg_edges=''.join(f'<line x1="{data["passives"][a]["position"][0]}" y1="{data["passives"][a]["position"][1]}" x2="{data["passives"][b]["position"][0]}" y2="{data["passives"][b]["position"][1]}"/>' for a,b in data['edges'])
    svg_nodes=''
    for key,p in data['passives'].items():
        radius={'small':8,'notable':13,'socket':15,'start':19}[p['type']]
        svg_nodes+=f'<a href="#{anchor("passives",key)}" data-node="{esc(key)}" aria-label="{esc(p["name"])} · {esc(key)}"><circle cx="{p["position"][0]}" cy="{p["position"][1]}" r="{radius}" style="--node-color:{p["color"]}"/><title>{esc(p["name"])} · {esc(key)}</title></a>'
    extent = max(max(abs(v) for p in data['passives'].values() for v in p['position']) + 30, max(abs(v)+source['radius'] for sample in data['special_coverage'].values() for source in sample['connected']['active_sources'].values() for v in source['position'])) + 40
    tree=f'''<section id="tree" class="tree-panel" aria-labelledby="tree-title"><div class="section-heading"><div><span class="eyebrow">历史181节点 · 机制研究</span><h2 id="tree-title">旧181节点覆盖研究</h2></div><a href="#jewels-branchfinder">寻枝晶玉规则 ↗</a></div><p>选一个孔，查看沿连线抵达它后的覆盖。点击节点查看资格与条目入口；这是旧树说明示例，当前角色使用完整源树；此图不修改角色构筑。</p><div class="tree-controls"><label>示例源孔<select id="socket-choice">{options}</select></label><label>示例状态<select id="tree-mode"><option value="connected">源孔与起点连通</option><option value="with_remote">加入一个远程点</option><option value="disconnected">源孔失联（非法构筑）</option></select></label><div class="zoom-controls"><button id="zoom-in" type="button" aria-label="放大星图">＋</button><button id="zoom-out" type="button" aria-label="缩小星图">−</button><button id="zoom-reset" type="button">全图</button></div></div><div class="tree-layout"><div class="tree-scroll"><svg id="passive-map" viewBox="{-extent} {-extent} {2*extent} {2*extent}" role="img" aria-label="{len(data['passives'])} 个原创天赋节点及寻枝晶玉覆盖范围"><g class="tree-lines">{svg_edges}</g><circle id="coverage-radius" r="0"/><g class="tree-nodes">{svg_nodes}</g></svg></div><div class="tree-key"><h3>示例判定</h3><p id="tree-status" role="status"></p><ul><li><i class="legend connected"></i>已分配且连接起点</li><li><i class="legend covered"></i>寻枝覆盖的小/显著天赋</li><li><i class="legend remote"></i>已分配的远程点</li><li><i class="legend eligible"></i>当前可分配</li></ul><p id="tree-selection">选择任一节点，查看精确 ID 与条目</p><p class="fine">几何、连线来自 PassiveData；状态来自 AllocationRules。圆形范围不授予孔位远程资格。</p></div></div></section>'''
    digest=hashlib.sha256(json.dumps(data,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    document='''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>裂隙试炼 · 构筑手册</title><style>__STYLE__</style></head><body><a class="skip" href="#entries">跳到条目</a><header><a class="brand" href="#category-skills"><span class="brand-mark" aria-hidden="true">✧</span><span>裂隙试炼<small>构筑手册 · 离线版</small></span></a><div class="edition">运行时 __VERSION__<br><a href="#rules-sources">来源与边界</a></div></header><div class="shell"><aside><nav aria-label="目录分类"><a href="#category-all" id="category-all" class="nav-link" data-category="all"><span>全部条目</span><span>__TOTAL__</span></a>__NAV__<a href="#tree" class="nav-link tree-nav"><span>寻枝覆盖图</span><span>↗</span></a></nav><div class="sidebar-note">解压后直接打开本页<br>搜索、星图与数据均在本地<br><a href="catalog.json">导出的运行时数据</a></div></aside><main><div class="page-intro"><span class="eyebrow">冒险者案头册</span><h1 id="category-title">主动技能</h1><p>查找一条规则，接着沿关联条目理解你的构筑</p></div><div class="search-box"><label for="query">搜索名称、ID、机制或属性</label><div class="search-row"><input id="query" type="search" placeholder="试试：龙卷、寻枝、火焰、runewood" autocomplete="off"><button id="clear-search" type="button">清除</button></div><div class="filter-row"><label>细分<select id="facet"><option value="">全部</option></select></label><label>实现状态<select id="status"><option value="">全部</option><option value="implemented">已实现</option><option value="research">研究资料</option><option value="planned">尚未实现</option></select></label><span id="result-count" role="status" aria-live="polite"></span></div></div>__TREE__<section id="entries" class="entries" aria-label="目录条目">__CARDS__</section><p id="empty" hidden>没有匹配的条目。试试更短的名称，或清除细分筛选。</p><noscript><p>JavaScript 未启用：仍可阅读全部条目与打开详细面板；搜索和星图状态切换需要启用 JavaScript。</p></noscript><footer>本页由本游戏运行时目录生成 · <a href="#rules-sources">研究来源与实现边界</a><br>数据指纹 __DIGEST__</footer></main></div><script id="reference-data" type="application/json">__DATA__</script><script>__SCRIPT__</script></body></html>'''
    payload={'records':records,'categories':dict(CATEGORIES),'passives':data['passives'],'coverage':data['special_coverage']}
    replacements={'__STYLE__':(REF/'reference.css').read_text(),'__SCRIPT__':(REF/'reference.js').read_text(),'__VERSION__':esc(data['game_version']),'__TOTAL__':str(len(records)),'__NAV__':nav,'__TREE__':tree,'__CARDS__':'\n'.join(cards),'__DIGEST__':digest[:16], '__DATA__':json.dumps(payload,ensure_ascii=False,sort_keys=True,separators=(',',':')).replace('<','\\u003c')}
    for key,value in replacements.items(): document=document.replace(key,value)
    return document


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--check',action='store_true'); args=parser.parse_args()
    data=json.loads((REF/'catalog.json').read_text())
    if 'forgeblade' in data:
        source=ROOT/data['forgeblade']['icon_source'].removeprefix('res://')
        target=REF/data['forgeblade']['icon_file']
        if args.check:
            if not target.exists() or target.read_bytes()!=source.read_bytes():
                raise SystemExit('Forgeblade reference image differs from original asset bytes')
        elif not target.exists() or target.read_bytes()!=source.read_bytes():
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(source.read_bytes())
    if 'ambush' in data:
        source=ROOT/data['ambush']['icon_source'].removeprefix('res://')
        target=REF/data['ambush']['icon_file']
        if args.check:
            if not target.exists() or target.read_bytes()!=source.read_bytes():
                raise SystemExit('Ambush reference image differs from original asset bytes')
        elif not target.exists() or target.read_bytes()!=source.read_bytes():
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(source.read_bytes())
    if 'inward_pull' in data:
        source=ROOT/data['inward_pull']['icon_source'].removeprefix('res://')
        target=REF/data['inward_pull']['icon_file']
        if args.check:
            if not target.exists() or target.read_bytes()!=source.read_bytes():
                raise SystemExit('Inward Pull reference image differs from original asset bytes')
        elif not target.exists() or target.read_bytes()!=source.read_bytes():
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(source.read_bytes())
    if 'frost_lock' in data:
        source=ROOT/data['frost_lock']['icon_source'].removeprefix('res://')
        target=REF/data['frost_lock']['icon_file']
        if args.check:
            if not target.exists() or target.read_bytes()!=source.read_bytes():
                raise SystemExit('Frost Lock reference image differs from original asset bytes')
        elif not target.exists() or target.read_bytes()!=source.read_bytes():
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(source.read_bytes())
    manifest=REF/'art/manifest.json'
    art=json.loads(manifest.read_text()) if manifest.exists() else {}
    output=build(data,art)
    destination=REF/'index.html'
    if args.check:
        if not destination.exists() or destination.read_text()!=output: raise SystemExit('Reference HTML is stale; run tools/build_reference.py')
        print('Reference HTML matches runtime export and templates')
    else:
        destination.write_text(output,encoding='utf-8'); print(f'Built {destination.relative_to(ROOT)} ({len(output.encode()):,} bytes)')
if __name__=='__main__': main()
