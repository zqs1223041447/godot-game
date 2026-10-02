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
CATEGORIES = [('skills','主动技能'),('supports','辅助技能'),('equipment','随机装备'),('affixes','装备词缀'),('fixed_items','固定装备'),('jewels','珠宝'),('jewel_affixes','珠宝词缀'),('passives','天赋星图'),('mechanisms','共用机制'),('weapon_stages','武器局部阶段'),('defenses','受击与防御'),('monsters','怪物图鉴'),('rules','规则与边界')]
RULE_TITLES = {'damage':'伤害如何结算','supports':'辅助装配','projectiles':'分裂、返回与飞行结束','equipment':'装备与阶级','character_rates':'恢复、移动与普通攻击速度','basic_attack':'普通攻击与武器贡献','allocation':'天赋与珠宝规则','shared':'玩家和怪物共享机制','boundaries':'尚未实现的源游戏语义','sources':'数据来源与实现边界'}
SLOTS = {'weapon':'武器','armor':'护甲','charm':'护符'}
TYPES = {'small':'小天赋','notable':'显著天赋','socket':'珠宝孔','start':'起点','prefix':'前缀','suffix':'后缀','ordinary':'普通珠宝','special':'特殊珠宝','legacy':'原始词池','expansion':'扩展词池','runewood':'符木点伤池','defense':'火抗防具池','local_weapon':'白蜡长弓池'}

def esc(value): return html.escape(str(value), quote=True)
def lines(value): return '<br>'.join(esc(value).split('\n'))
def number(value): return f'{value:g}' if isinstance(value, (int,float)) else str(value)
def anchor(cat, key): return f'{cat}-{key}'
DAMAGE_NAMES = {'physical':'物理','fire':'火焰','cold':'冰霜','lightning':'闪电','chaos':'混沌'}
def component_text(components):
    return ' + '.join(f'{DAMAGE_NAMES[k]} {number(v)}' for k,v in ((key,components.get(key,0)) for key in DAMAGE_NAMES) if v) or '无'
def percent(value): return number(value*100)+'%'
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
        label = label or (RULE_TITLES.get(key,key) if cat == 'rules' else data.get(cat,{}).get(key,{}).get('name',key))
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
                body += facts([('消耗',f'{number(example["mana"])} 魔力'),('冷却',f'{number(example["cooldown"])} 秒'),('初始投射物',number(example['initial_count']))])
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
        body = facts([('可装配技能',links('skills',eligible)),('能力要求',esc(' / '.join(s['requires'])))])
        cards.append(add('supports',key,s['name'],s['description'],body,'投射物辅助',related=link('rules','supports')))
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
        cards.append(add('passives',key,p['name'],p['description'],body,TYPES[p['type']],meta=tags([TYPES[p['type']],sector]),related=f'<a href="#tree" data-tree-node="{esc(key)}">在星图定位</a> · '+link('rules','allocation')))
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
    for key,m in data['monsters'].items():
        e=m['runtime_example']; tier=data['monster_rarities'][m['rarity']]['name']
        children=' · '.join(link('monsters',x['template'])+' × '+str(x['count']) for x in m['death_spawns']) or '无'
        summary=m['mechanism_text']+'。死亡后生成：'+('、'.join(data['monsters'][x['template']]['name']+' × '+str(x['count']) for x in m['death_spawns']) if m['death_spawns'] else '无子怪')
        body=facts([('稀有度',esc(tier)),('共用机制',links('mechanisms',m['mechanisms'])),('死亡子怪',children)])
        body+=facts([('接触分量 · 防御前',esc(component_text(m['contact_components']))),('有效火焰抗性',percent(m['defense_profile']['effective_resistances']['fire']))])
        encounter=data['fire_encounter']
        if key==encounter['template_id']:
            body+=details('出现条件与专属装备奖励',f'<p>第 {encounter["minimum_wave"]} 波及之后，普通成功入场计数每逢 {encounter["ordinary_admission_interval"]} 的倍数出现。初始入场计入该计数；满员未入场不递增，重开重置。</p><p>符合奖励资格的原始怪物死亡时，仅结算一次：{encounter["reward_count"]} 件 {esc(data["equipment_rarities"][encounter["reward_rarity"]]["name"])} {esc(TYPES[encounter["reward_pool"]])} 装备。可用底材：{links("equipment",data["equipment_pools"][encounter["reward_pool"]]["base_ids"])}。</p><p>出生节奏、分量、抗性与掉落保障均为本游戏原创平衡。</p>')
        body+=details(f'第 {m["example_wave"]} 波模板示例',facts([(label,number(e[field])) for label,field in [('生命','max_health'),('护盾','max_shield'),('接触伤害 · 防御前','damage'),('速度','speed'),('攻击频率','attack_speed'),('经验奖励','xp_reward')]])+'<p>包含模板固有稀有度与机制。后续波次、普通随机稀有度和机制组合会改变这些值。</p>')
        cards.append(add('monsters',key,m['name'],summary,body,tier,related=link('rules','shared')+' · '+link('defenses','fire_resistance')))

    total_weight=sum(p['weight'] for p in data['current_loot_profile'])
    pool_rows=''.join(f'<tr><th scope="row">{esc(TYPES[p["pool_id"]])}</th><td>{number(p["weight"])}</td><td>{percent(p["weight"]/total_weight)}</td><td>{links("equipment",data["equipment_pools"][p["pool_id"]]["base_ids"])}</td></tr>' for p in data['current_loot_profile'])
    pool_table='<div class="table-scroll"><table><caption>当前自然奖励 · 原创词池权重（每次已产生的装备奖励）</caption><thead><tr><th>词池</th><th>权重</th><th>条件概率</th><th>底材</th></tr></thead><tbody>'+pool_rows+'</tbody></table></div>'
    configs=''.join(f'<p>{esc(x["name"])}：{equipped_links(x)}</p>' for config in ['fresh','full_tornado','local_normal','local_max'] for x in [data['configurations'][config]])
    historical_pools=''.join('<p>'+esc(version)+'：'+' / '.join(esc(TYPES[row['pool_id']])+' '+number(row['weight']) for row in rows)+'</p>' for version,rows in data['loot_profiles'].items() if version!=data['current_loot_profile_id'])
    basic_rows=''.join(f'<tr><th scope="row">{esc(data["configurations"][config]["name"])}</th><td>{esc(component_text(sample["hits"]["basic"]["packet"]["base"]))}</td><td>{number(sample["hits"]["basic"]["resolved"]["total"])}</td><td>{number(sample["hits"]["basic"]["known_target_resolved"]["total"])}</td></tr>' for config in ['local_normal','local_max'] for sample in [data['weapon_stages']['weapon_local']['examples'][config]])
    rule_defs=[
        ('damage','伤害如何结算','每次施放先冻结构筑快照，再由技能编译器组装命中。条目分别标注防御前与已知目标抗性后的逐次命中，不是总伤害或每秒伤害。',configs+'<p>'+link('defenses','fire_resistance','查看一次命中的抗性与护盾流程')+'</p><p>原有固有分量、支持攻击命中的局部武器物理与匹配攻击/法术标签的外部附加点伤先分路组装；适用的提高同组相加，总增/总降分别相乘。独立爆炸具有自己的标签与附加效用。</p>','implemented'),
        ('supports','辅助装配','只有拥有所需能力的主动技能可装配辅助。同一技能不能重复装配同一辅助。',f'<p>每技能最多 {data["limits"]["max_supports"]} 个辅助；初始投射物上限 {data["limits"]["initial_projectiles"]}。兼容性来自 SupportCatalog；数值来自 SkillCompiler。</p><p>'+links('supports',data['supports'])+'</p>','implemented'),
        ('projectiles','分裂、返回与飞行结束','龙卷母箭优先分裂；返回在抵达射程时朝当时角色中心取向，且每个载体至多一次。','<p>自然飞行结束可触发装备授予的爆炸。分裂、碰撞消耗和取消不会触发该爆炸；返回不刷新寿命。投射物增伤与投射物辅助不作用于独立爆炸。</p><p>'+links('fixed_items',['prism_bow','return_mantle','detonation_charm'])+'</p>','implemented'),
        ('equipment','装备与阶级','底材与词缀按自身阶段结算；局部武器项独立于角色统计。T1 → T3 是本游戏原创成长顺序；不是 PoE 官方阶级命名。',f'<p>物品等级 {data["limits"]["min_item_level"]}–{data["limits"]["max_item_level"]}。每次已产生的普通装备奖励按下表权重选择一个词池（当前 {esc(data["current_loot_profile_id"])}，权重合计 100）；不是每只怪物死亡的掉落概率，也不新增奖励分支。同族或同组不能重复出现。</p>'+pool_table+details('稀有度规则',facts([(r['name'],f'{r["min_affixes"]}–{r["max_affixes"]} 条；至多 {r["max_prefixes"]} 前缀 / {r["max_suffixes"]} 后缀') for r in data['equipment_rarities'].values()]))+'<p>装备 damage 仍为角色通用基础加值，护盾为角色全局容量；白蜡长弓的局部物理另由 '+link('weapon_stages','weapon_local')+' 结算。火卫的合格专属奖励仍强制选防御池，沿用一次奖励。</p>'+details('历史配置与存档兼容',historical_pools+f'<p>历史配置留给重放兼容，不再表示当前自然词池选择。当前存档结构 {data["save_version"]}；v8 迁移保留装备 ID、掷值、辅助与珠宝，保存迁移备份。更新不会免费赠送新弓或新增升级奖励。</p>'),'implemented'),
        ('basic_attack','普通攻击与武器贡献','普通自动攻击是独立的攻击消费者，不计入八个主动技能条目。','<p>普通投射物接收本武器物理；法术与独立爆炸不接收。以下两种构筑仅用于说明合法普通长弓与局部双前缀实例，仍保留原有角色基础伤害。</p><div class="table-scroll"><table><thead><tr><th>装备示例</th><th>原始分量</th><th>防御前</th><th>已知目标抗性后</th></tr></thead><tbody>'+basic_rows+'</tbody></table></div><p>'+link('weapon_stages','weapon_local')+' · '+link('rules','character_rates')+'</p>','implemented'),
        ('character_rates','恢复、移动与普通攻击速度','速度和恢复的固定加值先相加，再应用对应提高比率。','<p>普通攻击速度改变基础自动射击间隔；不缩短主动技能冷却。魔力恢复与移动速度分别使用自身比率。</p>','implemented'),
        ('allocation','天赋与珠宝规则','从起点沿连线分配天赋；珠宝只能镶入已分配的孔。普通珠宝提供属性，寻枝晶玉额外赋予范围内远程分配资格。','<p>'+lines(data['jewels'].get('branchfinder',{}).get('description',''))+'</p><p>覆盖图中的资格与连通状态由同一个 AllocationRules 分析器导出。图中可切换源孔失联示例：失联孔不激活覆盖。远程点不能向覆盖范围外扩路，也不能远程开启珠宝孔。</p><p><a href="#tree">查看原创新图与覆盖示例</a></p><p>本游戏半径、限定节点类型、首领奖励与原子拒绝卸除，均为原创实现规则；不是 PoE 数值或完整机制复刻。研究依据：<a href="https://www.pathofexile.com/forum/view-thread/1254452/page/2">GGG 范围与禁止向外扩路说明</a> · <a href="https://www.pathofexile.com/forum/view-thread/2792025">3.10.0c 珠宝更换连通修复</a> · <a href="https://www.pathofexile.com/forum/view-thread/3406659">3.21.1 Hotfix 3 替代来源修复</a>。</p>','implemented'),
        ('shared','玩家和怪物共享机制','天赋节点与怪物模板按同一个机制 ID 请求整组属性。怪物不支持的属性会使整个机制被拒绝。',details('玩家天赋合计上限',facts([(key,number(value)) for key,value in data['passive_caps'].items()]))+'<p>天赋合计先受自身安全上限约束；装备与珠宝另行结算。怪物稀有度、物种、波次与死亡模板保持独立。</p>','implemented'),
        ('boundaries','尚未实现的源游戏语义','本目录不表示复刻了源游戏的全部规则。未实现的研究项不能作为本游戏构筑能力使用。','<p>未实现：护甲减伤、穿透、完整源游戏抗性引擎、武器品质、局部攻速/暴击、伤害范围、完整武器攻击基础替换、伤害转换、异常状态与暴击体系、召唤物、属性需求体系、星团与永恒珠宝重写、源游戏专属条件与资源机制。已经实现有限的局部物理武器阶段；当前可获得的防御属性仅有火焰抗性；其上限、怪物接触分量、护甲数值和掉落权重均为本游戏原创规则。未来是否加入其他体系及具体语义尚未承诺。</p>','planned'),
        ('sources','数据来源与实现边界','游戏目录从本地运行时导出。PoE 资料是语义和数值校准研究；本页只呈现已实现的原创内容、原创新图与必要的来源标识。',f'<p>天赋研究：PoE {esc(data["sources"]["passive"]["version"])}；固定提交 {esc(data["sources"]["passive"]["commit"])}。</p><p>词缀研究：PoE {esc(data["sources"]["affix"]["source_version"])}；RePoE 固定提交 {esc(data["sources"]["affix"]["export_commit"])}。</p><p><a href="{esc(data["sources"]["passive"]["repository"])}">天赋来源仓库</a> · <a href="{esc(data["sources"]["affix"]["export_repository"])}">词缀导出仓库</a>（可选外部链接，需要联网）</p><p>版本只证明此快照的研究依据，不表示源游戏当前全量可用性。未分发源游戏图像、布局或词条原文。</p>','research'),
    ]
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
    tree=f'''<section id="tree" class="tree-panel" aria-labelledby="tree-title"><div class="section-heading"><div><span class="eyebrow">原创星图 · 共享规则分析</span><h2 id="tree-title">寻枝覆盖图</h2></div><a href="#jewels-branchfinder">寻枝晶玉规则 ↗</a></div><p>选一个孔，查看沿连线抵达它后的覆盖。点击节点查看资格与条目入口；这是说明示例，不修改角色构筑。</p><div class="tree-controls"><label>示例源孔<select id="socket-choice">{options}</select></label><label>示例状态<select id="tree-mode"><option value="connected">源孔与起点连通</option><option value="with_remote">加入一个远程点</option><option value="disconnected">源孔失联（非法构筑）</option></select></label><div class="zoom-controls"><button id="zoom-in" type="button" aria-label="放大星图">＋</button><button id="zoom-out" type="button" aria-label="缩小星图">−</button><button id="zoom-reset" type="button">全图</button></div></div><div class="tree-layout"><div class="tree-scroll"><svg id="passive-map" viewBox="{-extent} {-extent} {2*extent} {2*extent}" role="img" aria-label="{len(data['passives'])} 个原创天赋节点及寻枝晶玉覆盖范围"><g class="tree-lines">{svg_edges}</g><circle id="coverage-radius" r="0"/><g class="tree-nodes">{svg_nodes}</g></svg></div><div class="tree-key"><h3>示例判定</h3><p id="tree-status" role="status"></p><ul><li><i class="legend connected"></i>已分配且连接起点</li><li><i class="legend covered"></i>寻枝覆盖的小/显著天赋</li><li><i class="legend remote"></i>已分配的远程点</li><li><i class="legend eligible"></i>当前可分配</li></ul><p id="tree-selection">选择任一节点，查看精确 ID 与条目</p><p class="fine">几何、连线来自 PassiveData；状态来自 AllocationRules。圆形范围不授予孔位远程资格。</p></div></div></section>'''
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
