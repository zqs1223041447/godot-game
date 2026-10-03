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
CATEGORIES = [('skills','主动技能'),('supports','辅助技能'),('equipment','随机装备'),('affixes','装备词缀'),('fixed_items','固定装备'),('jewels','珠宝'),('jewel_affixes','珠宝词缀'),('source_passives','源天赋与精通'),('passives','旧181节点研究'),('mechanisms','共用机制'),('weapon_stages','武器局部阶段'),('defenses','受击与防御'),('crafting','制作与回收'),('monsters','怪物图鉴'),('monster_attacks','怪物攻击'),('encounters','本轮挑战'),('rules','规则与边界')]
RULE_TITLES = {'damage':'伤害如何结算','supports':'辅助装配','projectiles':'分裂、返回与飞行结束','equipment':'装备与阶级','character_rates':'恢复、移动与普通攻击速度','basic_attack':'普通攻击与武器贡献','allocation':'天赋与珠宝规则','shared':'玩家和怪物共享机制','boundaries':'尚未实现的源游戏语义','sources':'数据来源与实现边界'}
CAPABILITIES = {'initial_projectiles':'初始投射物数量','projectile_hit':'投射物命中','finite_projectile_pierce':'有限穿透','area_hit':'直接范围命中','chain_hit':'连锁命中'}
SLOTS = {'weapon':'武器','armor':'护甲','charm':'项链','body_armour':'护甲','amulet':'项链','ring':'戒指','ring_1':'戒指一','ring_2':'戒指二','boots':'鞋','belt':'腰带','gloves':'手套','helmet':'头盔'}
TYPES = {'small':'小天赋','notable':'显著天赋','socket':'珠宝孔','start':'起点','keystone':'基石','mastery':'精通','prefix':'前缀','suffix':'后缀','ordinary':'普通珠宝','special':'特殊珠宝','legacy':'原始词池','expansion':'扩展词池','runewood':'符木点伤池','defense':'火抗防具池','local_weapon':'白蜡长弓池','nine_slot':'九槽装备池'}

def esc(value): return html.escape(str(value), quote=True)
def lines(value): return '<br>'.join(esc(value).split('\n'))
def number(value): return f'{value:g}' if isinstance(value, (int,float)) else str(value)
def anchor(cat, key): return f'{cat}-{key}'
DAMAGE_NAMES = {'physical':'物理','fire':'火焰','cold':'冰霜','lightning':'闪电','chaos':'混沌'}
def component_text(components):
    return ' + '.join(f'{DAMAGE_NAMES[k]} {number(v)}' for k,v in ((key,components.get(key,0)) for key in DAMAGE_NAMES) if v) or '无'
def percent(value): return number(value*100)+'%'
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
        diagrams+='<figure><figcaption>'+esc(monsters[template]['name'])+' · '+('最大生命' if field=='max_health' else '移动速度')+f'</figcaption><svg class="mechanism-diagram" viewBox="0 0 350 90" role="img" aria-label="{esc(definition["name"])}前后参数">{bars}</svg></figure>'
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
    labels={'radius':'世界半径','warning':'预警秒数','recovery':'默认恢复秒数','standing':'无火抗单次伤害','armored':'穿普通灰烬皮甲','moving':'成功移出后伤害'}
    rows=''.join(f'<li><span class="flow-step">{labels[key]}</span><strong data-telegraph-value="{key}" data-value="{esc(value)}">{number(value)}</strong></li>' for key,value in values.items())
    return f'<div class="telegraph-diagram">{pictures}</div><figure class="defense-flow"><figcaption>同源范围与结算 · 第 {sample["source_wave"]} 波灰烬守卫</figcaption><ol>{rows}</ol><p>图形采用实际事件半径与角色半径 {pr}；移动示例假设从预警开始持续直线移动、没有阻挡，移动速度 {sample["move_speed"]}，距离 {number(end)}。命中由同一圆形相交规则判断，伤害由真实分量与防御规则计算。护盾 {sample["shield_before"]} 先承伤，再扣生命；这是一次命中，不是每秒伤害。</p></figure>'

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


def build(data, art):
    records = []
    by_id = {}
    art_by_id = {(('fixed_items' if x.get('entry_type') == 'fixed_item' else x['category']),x['id']): x for x in art.get('entries',[])}
    def link(cat,key,label=None):
        label = label or (RULE_TITLES.get(key,key) if cat == 'rules' else data.get('source_tree',{}).get('nodes',{}).get(key,{}).get('name',key) if cat=='source_passives' else data.get(cat,{}).get(key,{}).get('name',key))
        return f'<a href="#{anchor(cat,key)}">{esc(label)}</a>'
    def equipped_links(cfg):
        instances=cfg.get('equipment_instances',{})
        return ' · '.join(link('equipment',instances[i]['base_id']) if i in instances else link('fixed_items',i) for i in cfg['equipped'].values())
    def links(cat,ids): return ' · '.join(link(cat,i) for i in ids) or '无'
    def details(title,body): return f'<details><summary>{esc(title)}</summary><div class="detail-body">{body}</div></details>'
    def facts(items): return '<dl class="facts">'+''.join(f'<div><dt>{esc(k)}</dt><dd>{v}</dd></div>' for k,v in items)+'</dl>'
    def tags(values): return '<div class="tags">'+''.join(f'<span>{esc(x)}</span>' for x in values)+'</div>'
    def add(cat,key,name,summary,body='',facet='',status='implemented',meta='',related=''):
        aid = anchor(cat,key)
        img = art_by_id.get((cat,key))
        image = f'<img class="emblem" src="art/{esc(img["file"])}" width="64" height="64" alt="" loading="lazy">' if img else '<span class="fallback-emblem" aria-hidden="true">✧</span>'
        badges = {'implemented':'已实现','research':'研究资料','planned':'尚未实现'}
        inner = f'<div class="entry-heading">{image}<div><span class="status {status}">{badges[status]}</span><h2><a href="#{aid}">{esc(name)}</a></h2><div class="entry-id">{esc(key)}</div></div></div>'
        if meta: inner += f'<div class="metadata">{meta}</div>'
        inner += f'<p class="summary">{lines(summary)}</p>{body}'
        if related: inner += f'<div class="related"><span>关联条目</span> {related}</div>'
        searchable = ' '.join([name,key,summary,html.unescape(__import__('re').sub('<[^>]+>',' ',body)),facet])
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
        body = facts([('原始消耗',number(s['mana'])+' 魔力'),('原始冷却',number(s['cooldown'])+' 秒'),('可装配辅助',links('supports',compatible))])+panels
        affected = [i for i,f in data['affixes'].items() if key in f.get('affected_skills',[])]
        related = link('rules','damage')+' · '+link('rules','supports')+((' · '+links('affixes',affected)) if affected else '')
        cards.append(add('skills',key,s['name'],s['description'],body,'投射物' if 'projectile_hit' in s['capabilities'] else '其他技能',related=related))
    for key,s in data['supports'].items():
        eligible = [i for i,x in data['skills'].items() if key in x['compatible_supports']]
        body = facts([('可装配技能',links('skills',eligible)),('能力要求',esc(' / '.join(CAPABILITIES.get(c,c) for c in s['requires']))),('规则来源','本游戏原创；运行版本 '+esc(data['game_version']))])
        if key == 'pierce':
            body += piercing_diagram(data['projectile_support_examples'],data['skills'])
        body += support_program_diagram(data['support_program_examples'][key],data['skills'],details)
        if key in ['breadth','concentrate']:
            body += area_diagram(data['area_support_examples'],data['skills'])
        cards.append(add('supports',key,s['name'],s['description'],body,{'area':'范围辅助','projectile':'投射物辅助','resource':'资源辅助','element':'分量专注','delivery':'投射物辅助','control':'减速控制','chain':'连锁辅助'}[data['support_program_examples'][key]['family']],related=link('rules','supports')))
    for key,e in data['equipment'].items():
        body = facts([('格数',' × '.join(map(number,e['size']))),('固有属性',lines(e['stats_text']))])+details('可出现的词缀',links('affixes',e['eligible_affixes']))
        related=link('rules','equipment')
        if e.get('stage')=='weapon_local':
            body+='<p>'+esc(e['normal_definition']['weapon_damage_summary'])+'</p><p>局部词缀与原有武器前缀共享稀有装备的三个前缀名额；两条局部前缀不能一起出现在仅允许一个前缀的魔法装备上。</p>'
            related+=' · '+link('weapon_stages','weapon_local')+' · '+link('rules','basic_attack')+' · '+link('skills','tornado')
        if e['stats'].get('fire_resistance',0): related+=' · '+link('defenses','fire_resistance','火焰抗性与受击结算')
        cards.append(add('equipment',key,e['name'],e['description'],body,SLOTS[e['slot']],meta=tags([SLOTS[e['slot']],TYPES[e['pool']]]),related=related))
    for key,f in data['affixes'].items():
        unit = '%' if f['unit']=='percent' else ' 点'
        rows = ''.join(f'<tr><th scope="row">T{int(t["tier"])}</th><td>{int(t["level"])}</td><td>{int(t["min"])}–{int(t["max"])}{unit}</td><td>{int(t["weight"])}</td></tr>' for t in f['tiers'])
        body = '<div class="table-scroll"><table><caption>原创阶级，端点包含在内</caption><thead><tr><th>阶级</th><th>物品等级</th><th>掷值</th><th>权重</th></tr></thead><tbody>'+rows+'</tbody></table></div>'
        body += details('资格、作用域与游戏内文本', facts([('可用底材',links('equipment',f['eligible_bases'])),('互斥组',esc(f['group'])),('运行时属性',esc(f['stat']))])+('<p>命中条件：'+esc(' + '.join(f.get('required_tags',[])))+'；阶段：'+esc(f.get('stage',''))+'</p>' if f.get('stage')=='skill_added_damage' else '')+'<p>'+lines('\n'.join(f['formatted_examples']))+'</p>')
        related = link('defenses','fire_resistance','火焰抗性与受击结算') if f['stat']=='fire_resistance' else (links('skills',f.get('affected_skills',[])) if f.get('affected_skills') else link('rules','character_rates'))
        if f.get('stage')=='weapon_local':
            body+='<p>阶段：本武器局部物理；只读取当前装备的白蜡长弓。不会进入角色统计，不增益法术或独立爆炸。图鉴的技能关联以普通长弓对照带此单词缀的合法魔法长弓，经实际编译器比较。</p>'
            related=link('weapon_stages','weapon_local')+' · '+links('skills',f['affected_skills'])+' · '+link('rules','basic_attack')
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
        effect=p['execution']; allowed=p['standard_graph'] and not p['source_proxy'] and not p['blighted_only']
        selectable=allowed and effect['status']=='full' and p['type']!='mastery'
        state='完整效果已接入；仍需合法连接、点数和位置资格' if selectable else '保留源数据；未完整执行的节点不可分配'
        if p['type']=='mastery': state='精通按所选效果单独验证；同组普通连通显著天赋及1点必需'
        if p['type'] in ['start','socket'] and selectable: state='结构节点规则已接入，不算属性效果覆盖'
        body=facts([('源版本','3.29.1'),('分区',esc(p['partition'])),('状态',esc(state)),('源坐标',esc(', '.join(number(x) for x in p['position'])) if p['has_position'] else '源记录没有坐标，不虚构布局')])
        if effect['unsupported']:body+=details('未实现的源效果 · 整节点锁定','<p>'+lines('\n'.join(effect['unsupported']))+'</p>')
        for choice in p['mastery_choices']:
            label='已执行' if allowed and choice['execution']['status']=='full' else '未完整执行 · 不可选择'
            body+=details(f'精通 {choice["effect"]} · {label}','<p>'+lines('\n'.join(choice['stats']))+'</p>')
        if p['neighbors']:body+=details('原始标准邻接',links('source_passives',p['neighbors']))
        cards.append(add('source_passives',key,p['name'],'\n'.join(p['stats']) or state,body,TYPES[p['type']],status='implemented' if selectable else 'research',related=link('rules','source_tree')))
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
        rows=''.join(f'<tr><th scope="row">{esc(data["configurations"][config]["name"])}</th><td>{number(sample["resolved_weapon"]["profile"]["base"]["physical"])}</td><td>{number(sample["resolved_weapon"]["profile"]["flat"]["physical"])}</td><td>{percent(sample["resolved_weapon"]["profile"]["increased"]["physical"])}</td><td>{number(sample["resolved_weapon"]["components"]["physical"])}</td></tr>' for config in ['local_normal','local_max'] for sample in [w['examples'][config]])
        body+='<div class="table-scroll"><table><caption>由合法实例推导的武器面板</caption><thead><tr><th>装备</th><th>P 固有</th><th>F 点伤</th><th>L 提高</th><th>W 物理</th></tr></thead><tbody>'+rows+'</tbody></table></div>'
        body+=details('最高局部掷值示例的完整实例',f'<p>稀有、物品等级 {rolled["instance"]["item_level"]}。两条局部前缀与两条合法后缀共同满足四词缀最低要求；所有示例掷值均取实际目录对应阶级上限。</p><p>'+lines('\n'.join(rolled['definition']['affix_lines']))+'</p><p>这一示例只表示局部物理项上限，未声称在伤害、法术、速度、生存等目标上普遍更优。</p>')
        body+=details('组装语义与明确边界','<p>先结算本武器物理 W，再按技能基础倍率加到攻击物理分量。原有角色基伤 B 继续存在；龙卷的 60/40 只分配 B，不能把 W 转为火焰。外部攻击附加点伤仍按自身附加效用结算；角色提高、辅助总增/总降和目标防御随后处理。</p><p>仅实现有限的物理局部阶段。尚无品质、局部攻速、局部暴击、伤害范围、伤害转换，也未采用完整 PoE 的武器替换整个攻击基础模型。底材、阶级、掷值、掉落权重与保留 B 的兼容适配均为本游戏原创。</p><p>同一武器槽不能同时装备白蜡长弓与符木法器；上图外部附加为零，字段仍与真实组装记录分别展示。</p>')
        body+=details('已验证的平衡范围','<p>当前固定矩阵含 288 组物品等级、稀有度、构筑背景、目标与辅助组合；真实编译回放完成 92,580 次候选评估。各指标分别寻找合法最优实例，最高优势约 +17.59%，稀有装备最高约 +16.26%，均通过当前 25% 预算线。</p><p>这不表示一件装备同时最大化所有指标，也不是实际每秒伤害或未来目标的普遍保证。额外的 75% 火抗未来压力目标中，龙卷母箭优势约 +25.39%，已经超出该预算线；加入这类防御时须重新审查。</p><p><a href="../benchmarks/v0.13-weapon-budget-report.md">完整预算报告、矩阵范围与重放方法</a> · <a href="../benchmarks/v0.13-weapon-budget-replay.json">实际编译回放数据与合法实例</a></p>')
        body+=details('历史语义研究来源','<p>以下 GGG 历史说明仅用于研究局部词缀与攻击基础/附加效用的区别，不是本游戏平衡背书，也不宣称当前版本完全复刻。</p><p>'+' · '.join(f'<a href="{esc(url)}">GGG 历史说明 {i+1}</a>' for i,url in enumerate(w['source_refs']))+'</p>')
        cards.append(add('weapon_stages',key,w['name'],w['description'],body,'局部物理',related=links('equipment',w['base_ids'])+' · '+links('affixes',[i for i,f in data['affixes'].items() if f.get('stage')==key])+' · '+link('rules','damage')))
    for key,d in data['defenses'].items():
        example=d['worked_example']
        body=facts([('支持对象','、'.join({'player':'玩家','monster':'怪物'}[a] for a in d['supported_actors'])),('有效下限',percent(d['minimum_effective'])),('有效上限',percent(d['maximum_effective'])),('规则版本',esc(d['balance_version']))])
        body+=defense_diagram(example)
        cap_rows=''.join(f'<tr><td>{percent(p["raw_resistances"]["fire"])}</td><td>{percent(p["effective_resistances"]["fire"])}</td></tr>' for p in d['cap_examples'])
        body+=details('原始值与有效值', '<p>原始抗性先相加，再按原创上下限约束；下面包含边界演算输入，不代表当前装备可以达到每一个原始值。</p><div class="table-scroll"><table><thead><tr><th>原始火抗</th><th>有效火抗</th></tr></thead><tbody>'+cap_rows+'</tbody></table></div>')
        body+=details('当前支持边界','<p>仅火焰抗性是当前可获得的防御属性。支持分量先减伤、再扣护盾、再扣生命。不包含护甲、穿透、异常状态或完整 PoE 防御体系；当前不实现混沌绕盾。</p><p>火抗上限、底材/词缀数值和怪物平衡均为本游戏原创，没有对应的 PoE 源规则背书。</p>')
        related=links('equipment',[i for i,e in data['equipment'].items() if e['stats'].get(d['stat'],0)])+' · '+links('affixes',[i for i,f in data['affixes'].items() if f['stat']==d['stat']])+' · '+links('monsters',[i for i,m in data['monsters'].items() if m.get('defense_stats',{}).get(d['stat'],0)])
        cards.append(add('defenses',key,d['name'],d['description'],body,'命中防御',related=related+' · '+link('rules','damage')))
    for key,c in data['crafting'].items():
        if c['kind']=='material':
            body=facts([('余额上限',number(c['maximum'])),('存档版本',number(c['save_version'])),('规则版本',esc(c['rules']['rules_version']))])
            body+='<p>首版只有一种材料。回收收益为稀有度基数（魔法1、稀有3）加全部词缀阶级之和；数值校准成本为该装备回收收益的2倍。T1入门、T3高阶是本游戏顺序，数值为可调原创平衡。</p>'
            related=link('crafting','salvage')+' · '+link('crafting','recalibrate')
        else:
            sample=c['example']; quote=sample['quote']; source=sample['source']
            amount=quote['materials'].get('calibration_shard',0) if key=='salvage' else quote['cost']['calibration_shard']
            action='获得' if key=='salvage' else '消耗'
            mark='<svg viewBox="0 0 64 64" width="48" height="48" aria-hidden="true"><path d="M32 5 L51 22 L42 53 L16 42 L12 21 Z M32 5 L29 30 L42 53 M12 21 L29 30 L51 22" fill="#dfc99a" stroke="#79571f" stroke-width="2"/></svg>'
            body='<figure class="defense-flow"><figcaption>实际规则示例 · 白蜡长弓</figcaption><ol><li><span class="flow-step">01 · 原物品</span><strong>'+esc(sample['before_definition']['base_name'])+'</strong><span>'+lines('\n'.join(sample['before_definition']['affix_lines']))+'</span></li><li><span class="flow-step">02 · '+action+'校准碎片</span>'+mark+f'<strong data-craft-value="{key}-amount" data-value="{amount}">{amount}</strong></li><li><span class="flow-step">03 · 余额与结果</span>'+f'<strong><span data-craft-value="{key}-before" data-value="{sample["balance_before"]}">{sample["balance_before"]}</span> → <span data-craft-value="{key}-after" data-value="{sample["balance_after"]}">{sample["balance_after"]}</span></strong>'
            body+='<span>原装备被消耗，空位释放</span>' if key=='salvage' else '<span>'+lines('\n'.join(sample['after_definition']['affix_lines']))+'</span>'
            body+='</li></ol><p class="fine">演示使用合法、未穿戴的最高档单词缀实例与固定示例种子；收益、成本、结果和完整构筑合法性来自实际规则/事务规划器。它不预告玩家下一次随机结果。</p></figure>'
            body+=facts([('可用底材',links('equipment',c['eligible_base_ids'])),('前置条件','在背包中、未穿戴的随机魔法/稀有装备；普通无词缀、固定示例和珠宝不适用'),('保存顺序','完整候选验证 → 原子写盘 → 内存提交与刷新'),('失败保护','拒绝或写盘失败不动装备、材料和序号；回收需确认，校准明确可能降低或不变'),('保持字段','物品ID、底材、物品等级、稀有度、词缀种类/顺序/阶级保持；校准只重掷原档数值')])
            related=link('crafting','calibration_shard')+' · '+link('equipment',source['base_id'])+' · '+links('affixes',[a['id'] for a in source['affixes']])
        cards.append(add('crafting',key,c['name'],c['description'],body,'材料' if c['kind']=='material' else '制作操作',related=related))
    for key,e in data['encounters'].items():
        body=encounter_diagram(key,e,data['monsters'])+facts([('倍率',number(e['multiplier'])),('作用字段',esc(e['field'])),('应用顺序','物种/波次/稀有度/机制生成标准怪物后，仅在入场前乘一次；死亡子怪按自己的标准值应用'),('其余属性','攻击伤害、护盾、防御、体型、重击时序与奖励资格保持'),('风险说明','仅参数变化；实战难度未合并评分'),('奖励','无额外经验、掉落、制作材料或地图物品'),('生命周期','暂停面板选择并确认重开后生效；普通重试保留，恢复常规/试验场清空；不随构筑保存')])
        cards.append(add('encounters',key,e['name'],e['description'],body,'本轮可选 · 原创规则',related=links('monsters',e['examples'].keys())+' · '+link('rules','encounters')))
    for key,a in data['monster_attacks'].items():
        p=a['profile']; policy=a['policy']
        body=telegraph_diagram(a)+facts([('来源',links('monsters',a['integrated_templates'])),('发动距离',number(policy['trigger_distance'])+' 世界单位'),('原始伤害',component_text(a['example']['event']['packet']['base'])),('倍率',number(p['damage_multiplier'])+' × 来源接触基底'),('攻速作用','只缩放恢复期；预警时间固定；开始后本次时序和伤害冻结'),('期间行动','暂停主动追击；击退仍有效；同一守卫不再叠加贴身接触攻击'),('取消与保护','来源死亡/出生保护/移除、玩家死亡或重开取消；暂停冻结时钟；多次同时命中沿用玩家无敌帧'),('规则版本',esc(a['balance_version']))])
        cards.append(add('monster_attacks',key,a['name'],a['description'],body,'已实装 · 原创规则',related=links('monsters',a['integrated_templates'])+' · '+link('equipment','emberhide_vest')+' · '+link('defenses','fire_resistance')))
    for key,m in data['monsters'].items():
        e=m['runtime_example']; tier=data['monster_rarities'][m['rarity']]['name']
        children=' · '.join(link('monsters',x['template'])+' × '+str(x['count']) for x in m['death_spawns']) or '无'
        summary=m['mechanism_text']+'。死亡后生成：'+('、'.join(data['monsters'][x['template']]['name']+' × '+str(x['count']) for x in m['death_spawns']) if m['death_spawns'] else '无子怪')
        body=facts([('稀有度',esc(tier)),('共用机制',links('mechanisms',m['mechanisms'])),('死亡子怪',children)])
        body+=facts([('攻击基底分量 · 防御前',esc(component_text(m['contact_components']))),('有效火焰抗性',percent(m['defense_profile']['effective_resistances']['fire']))])
        if m.get('source_ratings'):
            body+=facts([('命中值',number(m['source_ratings']['accuracy'])),('闪避值',number(m['source_ratings']['evasion']))])
        if m.get('telegraph_policy'):
            body+='<p>'+link('monster_attacks',m['telegraph_policy']['profile_id'],'查看锁点重击：预警、躲避与真实伤害')+'</p>'
        encounter=data['fire_encounter']
        if key==encounter['template_id']:
            body+=details('出现条件与专属装备奖励',f'<p>第 {encounter["minimum_wave"]} 波及之后，普通成功入场计数每逢 {encounter["ordinary_admission_interval"]} 的倍数出现。初始入场计入该计数；满员未入场不递增，重开重置。</p><p>符合奖励资格的原始怪物死亡时，仅结算一次：{encounter["reward_count"]} 件 {esc(data["equipment_rarities"][encounter["reward_rarity"]]["name"])} {esc(TYPES[encounter["reward_pool"]])} 装备。可用底材：{links("equipment",data["equipment_pools"][encounter["reward_pool"]]["base_ids"])}。</p><p>出生节奏、分量、抗性与掉落保障均为本游戏原创平衡。</p>')
        body+=details(f'第 {m["example_wave"]} 波模板示例',facts([(label,number(e[field])) for label,field in [('生命','max_health'),('护盾','max_shield'),('攻击基底 · 防御前','damage'),('速度','speed'),('攻击频率','attack_speed'),('经验奖励','xp_reward')]])+'<p>包含模板固有稀有度与机制。后续波次、普通随机稀有度和机制组合会改变这些值。</p>')
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
        ('supports','辅助装配','只有拥有所需能力的主动技能可装配辅助。同一技能不能重复装配同一辅助。',f'<p>每技能最多 {data["limits"]["max_supports"]} 个辅助；初始投射物上限 {data["limits"]["initial_projectiles"]}。16种选择覆盖8个主动技能；可用技能由原生配方固定，装备附加分量不会改变允许槽位。K仅显示兼容卡片。兼容性来自 SupportRegistry，数值来自 SkillCompiler；节能/疾咏改变耗魔和冷却，不改变施法动作速度。</p><p>'+links('supports',data['supports'])+'</p>','implemented'),
        ('projectiles','分裂、返回与飞行结束','龙卷母箭优先分裂；返回在抵达射程时朝当时角色中心取向，且每个载体至多一次。','<p>自然飞行结束可触发装备授予的爆炸。分裂、碰撞消耗和取消不会触发该爆炸；返回不刷新寿命。投射物增伤与投射物辅助不作用于独立爆炸。</p><p>'+links('fixed_items',['prism_bow','return_mantle','detonation_charm'])+'</p>','implemented'),
        ('equipment','装备与阶级','底材与词缀按自身阶段结算；局部武器项独立于角色统计。T1 → T3 是本游戏原创成长顺序；不是 PoE 官方阶级命名。',f'<p>物品等级 {data["limits"]["min_item_level"]}–{data["limits"]["max_item_level"]}。每次已产生的普通装备奖励按下表权重选择一个词池（当前 {esc(data["current_loot_profile_id"])}，权重合计 100）；不是每只怪物死亡的掉落概率，也不新增奖励分支。同族或同组不能重复出现。</p>'+pool_table+details('稀有度规则',facts([(r['name'],f'{r["min_affixes"]}–{r["max_affixes"]} 条；至多 {r["max_prefixes"]} 前缀 / {r["max_suffixes"]} 后缀') for r in data['equipment_rarities'].values()]))+'<p>装备 damage 仍为角色通用基础加值，护盾为角色全局容量；白蜡长弓的局部物理另由 '+link('weapon_stages','weapon_local')+' 结算。火卫的合格专属奖励仍强制选防御池，沿用一次奖励。</p>'+details('历史配置与存档兼容',historical_pools+f'<p>历史配置留给重放兼容，不再表示当前自然词池选择。当前存档结构 {data["save_version"]}；v8 迁移保留装备 ID、掷值、辅助与珠宝，保存迁移备份。更新不会免费赠送新弓或新增升级奖励。</p>'),'implemented'),
        ('basic_attack','普通攻击与武器贡献','普通自动攻击是独立的攻击消费者，不计入八个主动技能条目。','<p>普通投射物接收本武器物理；法术与独立爆炸不接收。以下两种构筑仅用于说明合法普通长弓与局部双前缀实例，仍保留原有角色基础伤害。</p><div class="table-scroll"><table><thead><tr><th>装备示例</th><th>原始分量</th><th>防御前</th><th>已知目标抗性后</th></tr></thead><tbody>'+basic_rows+'</tbody></table></div><p>'+link('weapon_stages','weapon_local')+' · '+link('rules','character_rates')+'</p>','implemented'),
        ('character_rates','恢复、移动与普通攻击速度','速度和恢复的固定加值先相加，再应用对应提高比率。','<p>普通攻击速度改变基础自动射击间隔；不缩短主动技能冷却。魔力恢复与移动速度分别使用自身比率。</p>','implemented'),
        ('allocation','天赋与珠宝规则','从起点沿连线分配天赋；珠宝只能镶入已分配的孔。普通珠宝提供属性，寻枝晶玉额外赋予范围内远程分配资格。','<p>'+lines(data['jewels'].get('branchfinder',{}).get('description',''))+'</p><p>覆盖图中的资格与连通状态由同一个 AllocationRules 分析器导出。图中可切换源孔失联示例：失联孔不激活覆盖。远程点不能向覆盖范围外扩路，也不能远程开启珠宝孔。</p><p><a href="#tree">查看原创新图与覆盖示例</a></p><p>本游戏半径、限定节点类型、首领奖励与原子拒绝卸除，均为原创实现规则；不是 PoE 数值或完整机制复刻。研究依据：<a href="https://www.pathofexile.com/forum/view-thread/1254452/page/2">GGG 范围与禁止向外扩路说明</a> · <a href="https://www.pathofexile.com/forum/view-thread/2792025">3.10.0c 珠宝更换连通修复</a> · <a href="https://www.pathofexile.com/forum/view-thread/3406659">3.21.1 Hotfix 3 替代来源修复</a>。</p>','implemented'),
        ('shared','玩家和怪物共享机制','天赋节点与怪物模板按同一个机制 ID 请求整组属性。怪物不支持的属性会使整个机制被拒绝。',details('玩家天赋合计上限',facts([(key,number(value)) for key,value in data['passive_caps'].items()]))+'<p>天赋合计先受自身安全上限约束；装备与珠宝另行结算。怪物稀有度、物种、波次与死亡模板保持独立。</p>','implemented'),
        ('boundaries','尚未实现的源游戏语义','本目录不表示复刻了源游戏的全部规则。未实现的研究项不能作为本游戏构筑能力使用。','<p>未实现：护甲减伤、抗性穿透、完整源游戏抗性引擎、武器品质、局部攻速/暴击、伤害范围、完整武器攻击基础替换、伤害转换、异常状态与暴击体系、召唤物、属性需求体系、星团与永恒珠宝重写、源游戏专属条件与资源机制，以及新增/替换词缀、升阶、定向制作和制作地图。当前仅实现回收与已有词缀数值校准。已经实现有限的局部物理武器阶段；当前可获得的防御属性仅有火焰抗性；其上限、怪物接触分量、护甲数值和掉落权重均为本游戏原创规则。未来是否加入其他体系及具体语义尚未承诺。</p>','planned'),
        ('sources','数据来源与实现边界','游戏目录从本地运行时导出。PoE 资料是语义和数值校准研究；本页只呈现已实现的原创内容、原创新图与必要的来源标识。',f'<p>天赋研究：PoE {esc(data["sources"]["passive"]["version"])}；固定提交 {esc(data["sources"]["passive"]["commit"])}。</p><p>词缀研究：PoE {esc(data["sources"]["affix"]["source_version"])}；RePoE 固定提交 {esc(data["sources"]["affix"]["export_commit"])}。</p><p><a href="{esc(data["sources"]["passive"]["repository"])}">天赋来源仓库</a> · <a href="{esc(data["sources"]["affix"]["export_repository"])}">词缀导出仓库</a>（可选外部链接，需要联网）</p><p>版本只证明此快照的研究依据，不表示源游戏当前全量可用性。运行不使用源游戏图像，原树功能数据与原文的执行覆盖分别标注。</p>','research'),
    ]
    if 'canonical' in data:
        c=data['canonical']; source=data['source_tree']; example=c['five_link_example']; defense=c['defense_example']
        rule_defs=[row for row in rule_defs if row[0] not in ['supports','allocation','shared','boundaries','sources']]
        ownership='<figure><svg viewBox="0 0 650 150" role="img" aria-label="一件物品只有一个位置"><g fill="#ead3a2" stroke="#8c6b42"><rect x="10" y="45" width="190" height="60" rx="8"/><rect x="330" y="5" width="300" height="40" rx="8"/><rect x="330" y="55" width="300" height="40" rx="8"/><rect x="330" y="105" width="300" height="40" rx="8"/></g><g stroke="#79571f" fill="none"><path d="M200 75H260V25H330M260 75H330M260 75V125H330"/></g><g fill="#3b281b" font-size="16" text-anchor="middle"><text x="105" y="80">唯一 UID · 独立实例</text><text x="480" y="31">12×8 背包 / 九装备位</text><text x="480" y="81">10+ 行技能 · 每行1主5辅</text><text x="480" y="131">天赋珠宝孔 / 迁移待安置</text></g></svg></figure>'
        slot_rows=facts([(SLOTS.get(slot,slot),esc(category)) for slot,category in c['slots'].items()])
        rule_defs.extend([
            ('ownership','统一物品与独立菜单','装备、珠宝、主动宝石和辅助宝石都以唯一UID持有，一个实例只能处于一个位置。',ownership+slot_rows+'<p>I/B行囊、T源树、K宝石独立打开；背景战斗冻结。悬停详情，Shift比较双戒指目标。容量下降保留宝石和多余技能行，仅停用超出部分。旧装备UID与掷值保持，armor→body_armour、charm→amulet；旧技能/辅助转为独立实例，原始文件先备份，失败不覆盖。</p>','implemented'),
            ('supports','技能行与五辅助','每行1个主宝石、5个辅助；10行起步，+1技能行词缀真正增加可绑定的行。',f'<p>16辅助全部保留，按主动技能原生能力判定资格；同组不重复同一辅助定义。同名主宝石可独立装配。组与主宝石UID双冷却账阻止换孔/换键刷新。</p><p>真实五辅助冰霜示例：耗魔 {number(example["mana"])}，冷却 {number(example["cooldown"])}秒，初始 {example["initial_count"]}发。</p>'+details('同源实际配方',lines(example['summary']+'\n'+example['details']))+'<p>每30次有效根怪击杀，从当前8主动+16辅助定义中等概率得到1件等级1/品质0的宝石；同名独立UID。此节奏是本游戏原型平衡。子代、重复死亡和演示无奖励；背包满或有待安置时整笔拒绝且回滚本次抽取随机状态。I中二次确认可丢弃重复宝石，不返材料。</p>','implemented'),
            ('source_tree','锁定源树与执行覆盖','完整源记录与已实现效果分别报告；数据存在不等于可花点使用。',f'<p>源版本 {source["source_version"]}，原始SHA256 {source["source_sha256"]}。保留 {len(source["nodes"])} 条记录、2387个标准位置和2697条内部边；升华/扩展分区分开。42代理与30涂油节点不可直接分配。<a href="#category-source_passives">逐项查源节点及精通</a></p><p>节点所有效果必须完整执行，精通按选中效果检查。未支持节点灰色锁定，也会阻断后续路径。源数值没有旧181投影上限；旧树仅作历史与怪物机制参考。</p><p>自己的职业起点免费，预算min(level+4,123)。普通节点/精通均1点，专精需同组普通连通的显著节点，重复效果ID拒绝。未分配其他节点可切七起点；升华点数来源尚未实现，不免费授点。</p>','implemented'),
            ('allocation','源树与珠宝资格','每件珠宝只有一个统一位置；孔必须已分配并沿普通连线连接自己的起点。','<p>寻枝半径280采用当前源坐标单位，允许小型/显著节点断连分配，仍花1点。远程点不向外扩路、不激活孔；未实现节点即使在范围内也不能分配。退款、移动、替换、取回都验证最终构筑，不能遗留依赖失效的节点。原型半径规则不是PoE某颗珠宝的完整复刻。</p><p>'+link('rules','source_tree')+'；下方旧181覆盖图保留作历史机制研究。</p>','implemented'),
            ('source_defenses','属性与命中防御','原始三属性数值进入真实容量、命中、闪避和近战物理作用域。','<p>力量每2点取整+1生命、每5点取整+1%近战物理；敏捷每点+2命中、每5点取整+1%闪避；智慧每2点取整+1魔力、每10点取整+1%护盾（3.28以后规则）。法术不进行攻击闪避。护甲随物理命中大小重新求减伤，三元素抗性分别限制到75%，然后护盾、生命。</p>'+facts([('同源混合受击示例','物理/火/冰/电各100；护甲500、抗性50%/25%/75%'),('防御后分量',esc(component_text(defense['components']))),('护盾扣减',number(defense['shield_spent'])),('生命扣减',number(defense['health_lost']))])+f'<p>本游戏敏捷型怪物闪避320；默认Scion命中140，对应 {percent(c["skitter_accuracy_example"]["base_chance"])}；增加10敏捷后命中160，对应 {percent(c["skitter_accuracy_example"]["improved_chance"])}。预览展示成功命中伤害，未把命中率伪乘成DPS。</p>','implemented'),
            ('shared','共享消费者与历史注册表','人物和怪物共用伤害分量、防御、命中和结算函数。','<p>旧MechanicRegistry仍约束怪物机制包；旧181节点引用保留作研究与回归。当前人物改用原始源树逐项能力门槛，不能再套用旧投影合计上限。未支持机制继续拒绝，不借导入数据悄悄生效。</p>','implemented'),
            ('boundaries','尚未实现的机制','未执行源节点整体锁定，原文与位置保留。','<p>仍未完成：施法动作时长/施法速度、暴击、格挡、压制、抗性穿透、异常与持续伤害体系、召唤物、属性装备需求、星团/永恒珠宝、升华点数来源及复杂条件机制。源树浏览不等于以上均可用。制作仍为回收与已有词缀数值校准；未发行四工艺研究独立保留。</p>','planned'),
            ('sources','来源与实现边界','目录来自运行时导出，源树保留功能数据，所有美术由本项目创作。',f'<p><a href="{esc(source["source_url"])}">GGG源树固定提交 {source["source_commit"]}</a> · 3.29.1。保留节点身份、原始规则词句、精通和几何；未包含官方图像或叙事风味文本。上游数据再分发授权未明确，不宣称公共领域。</p><p>旧181节点与词缀校准研究仍有各自固定版本，不代表当前角色全部源效果已实现。原型怪物数值、掉落权重与熵初值由本项目定义。</p><p><a href="source-tree-coverage.json">完整执行覆盖与七职业可达前沿JSON</a>：空stats结构节点和精通本体不冒充属性效果，精通逐选项统计；可达集合不代表123点可以全部同时点出。</p>','research')
        ])
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
