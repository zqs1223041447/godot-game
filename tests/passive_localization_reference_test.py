#!/usr/bin/env python3
"""Display-only v57 passive localization against the immutable complete v56 catalog."""
import hashlib
import json
import re
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT/'docs/reference'
QA = ROOT/'docs/qa/v057-reference'


def sha(value):
    return hashlib.sha256(value).hexdigest()


def digest(value):
    return sha(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode())


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links, self.assets = [], [], []
        self.article, self.active_link, self.hidden = None, None, 0
        self.text, self.source_links = {}, []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.append(attrs['id'])
        if tag in ('script', 'style'):
            self.hidden += 1
        if tag == 'article':
            self.article = attrs['id']
            self.text[self.article] = []
        if tag == 'a':
            self.links.append(attrs.get('href', ''))
            if attrs.get('href', '').startswith('#source_passives-'):
                self.active_link = [attrs['href'].removeprefix('#source_passives-'), '']
        if tag in ('img', 'script', 'link'):
            url = attrs.get('src', attrs.get('href', ''))
            if url:
                self.assets.append(url)

    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.hidden -= 1
        if tag == 'article':
            self.article = None
        if tag == 'a' and self.active_link is not None:
            self.source_links.append(self.active_link)
            self.active_link = None

    def handle_data(self, text):
        if self.article and not self.hidden:
            self.text[self.article].append(text)
        if self.active_link is not None:
            self.active_link[1] += text


def compact(value):
    return re.sub(r'\s+', '', value)


def main():
    data = json.loads((REF/'catalog.json').read_text())
    baseline = json.loads((QA/'v056-reference-baseline.json').read_text())
    mapping = json.loads((ROOT/'data/passive_source/localization_zh_CN.json').read_text())
    document = (REF/'index.html').read_text()
    tree, localized = data['source_tree'], data['source_tree_localization']
    assert data['game_version'] == '0.57.0' and data['save_version'] == 34
    assert set(data) == set(baseline['section_sha256']) | {'source_tree_localization'}
    original = {key: value for key,value in data.items() if key != 'source_tree_localization'}
    original['game_version'] = baseline['game_version']
    assert digest(original) == baseline['catalog_sha256'], 'Only version and the new display key may change'
    assert {key:digest(value) for key,value in original.items()} == baseline['section_sha256']
    assert sha((REF/'source-tree-coverage.json').read_bytes()) == baseline['source_coverage_sha256']
    assert localized['locale'] == 'zh-CN' and localized['source_sha256'] == tree['source_sha256']
    assert localized['source_sha256'] == mapping['source']['sha256']
    assert len(tree['nodes']) == len(localized['nodes']) == 3390
    assert set(localized['nodes']) == set(tree['nodes']) == set(mapping['nodes'])
    suffix = localized['not_implemented_suffix']
    assert suffix == '（暂未实装）'
    raw_lines = {line for node in tree['nodes'].values() for line in node['stats']}
    raw_lines.update(line for node in tree['nodes'].values() for choice in node['mastery_choices'] for line in choice['stats'])
    assert set(localized['lines']) == raw_lines == set(mapping['lines'])
    implemented = 0
    for raw,row in localized['lines'].items():
        status = row['status']
        assert isinstance(status['implemented'], bool)
        assert row['text'] == mapping['lines'][raw] + ('' if status['implemented'] else suffix), raw
        if status['implemented']:
            assert status['parser_supported'] and status['grants'] and not status['missing_consumers'], raw
            implemented += 1
    page = Page()
    page.feed(document)
    payload = json.loads(re.search(r'<script id="reference-data" type="application/json">(.*?)</script>', document, re.S).group(1))
    records = {row['id']:row for row in payload['records']}
    cards = {key:card for card,key in re.findall(r'(<article\b[^>]*id="([^"]+)"[^>]*>.*?</article>)', document, re.S)}
    assert sorted(cards) == baseline['card_ids']
    for key,expected in baseline['unchanged_card_sha256'].items():
        card = cards[key]
        if key.startswith('supports-'):
            current = '本游戏原创；运行版本 ' + data['game_version']
            assert card.count(current) == 1
            card = card.replace(current, '本游戏原创；运行版本 ' + baseline['game_version'])
        assert sha(card.encode()) == expected, 'Unrelated visible card changed: '+key
    partitions = {key:row['zh_CN'] for key,row in mapping['partitions'].items()}
    partitions.update(standard='标准主树', expansion='扩展珠宝分区 · 仅浏览')
    assert localized['partitions'] == partitions
    occurrences = 0
    for node_id,node in tree['nodes'].items():
        row = localized['nodes'][node_id]
        visible = compact(' '.join(page.text['source_passives-'+node_id]))
        record = records['source_passives-'+node_id]
        if node_id == 'root':
            assert node['name'] == mapping['nodes'][node_id]['zh_CN'] == ''
            assert row['name'] == '节点名称缺失', 'Preserve shared adapter fallback for unnamed structural root'
        else:
            assert row['name'] == mapping['nodes'][node_id]['zh_CN'], node_id
        assert row['partition'] == partitions[node['partition']]
        assert row['stats'] == '\n'.join(localized['lines'][line]['text'] for line in node['stats'])
        assert compact(row['name']) in visible and compact(row['partition']) in visible
        assert compact(row['stats']) in visible
        assert row['name'].casefold() in record['search'] and node['name'].casefold() in record['search']
        assert node['partition'].casefold() in record['search']
        assert set(row['mastery_choices']) == {str(choice['effect']) for choice in node['mastery_choices']}
        allowed = node['standard_graph'] and not node['source_proxy'] and not node['blighted_only']
        expected_status = 'implemented' if allowed and node['execution']['status']=='full' and node['type']!='mastery' else 'research'
        assert record['status'] == expected_status
        assert record['facet'] in ('小天赋','显著天赋','珠宝孔','起点','基石','精通')
        for choice in node['mastery_choices']:
            text = '\n'.join(localized['lines'][line]['text'] for line in choice['stats'])
            assert row['mastery_choices'][str(choice['effect'])] == text
            assert compact(text) in visible
            occurrences += 1
        for raw in node['stats'] + [line for choice in node['mastery_choices'] for line in choice['stats']]:
            assert raw.casefold() in record['search']
            assert compact(localized['lines'][raw]['text']) in visible
            if re.search(r'[A-Za-z]{3}', raw):
                assert compact(raw) not in visible, ('Visible English passive sentence', node_id, raw)
        if re.search(r'[A-Za-z]{3}', node['name']):
            assert compact(node['name']) not in visible, ('Visible English node name', node_id)
    for node_id,label in page.source_links:
        assert label == node_id or localized['nodes'][node_id]['name'] in label or label == partitions['Elementalist']+'升华记录12738', (node_id,label)
    # Partial nodes and partially executable mastery must preserve per-line status.
    for node_id in ('48823', '19686'):
        node = tree['nodes'][node_id]
        assert [localized['lines'][line]['status']['implemented'] for line in node['stats']] == [False, True]
        assert localized['nodes'][node_id]['stats'].count(suffix) == 1
        assert records['source_passives-'+node_id]['status'] == 'research'
    assert all(localized['lines'][line]['status']['implemented'] for line in tree['nodes']['12738']['stats'])
    assert records['source_passives-12738']['status'] == 'research', 'An implemented sentence does not make an ascendancy node allocatable'
    choice = next(c for c in tree['nodes']['11505']['mastery_choices'] if c['effect']==36313)
    assert [localized['lines'][line]['status']['implemented'] for line in choice['stats']] == [True,False]
    assert localized['nodes']['11505']['mastery_choices']['36313'].count(suffix) == 1
    for kind in ('fire_dot', 'faster_burn'):
        source = data['source_'+kind]
        visible = compact(' '.join(page.text['rules-source_'+kind]))
        for node_id,node in source['nodes'].items():
            assert compact(localized['nodes'][node_id]['name']) in visible
            for raw in node['source_lines']:
                assert compact(localized['lines'][raw]['text']) in visible
                assert compact(raw) not in visible
    for node_id,node in data['source_faster_burn']['blocked_matching_nodes'].items():
        visible = compact(' '.join(page.text['rules-source_faster_burn']))
        assert 'partial' not in visible and '部分执行' in visible
        assert compact(node['name']) not in visible
        for raw in node['execution']['unsupported']:
            assert compact(localized['lines'][raw]['text']) in visible
    images = {p.relative_to(REF).as_posix():sha(p.read_bytes()) for p in REF.rglob('*.png')}
    assert len(images) == 68 and images == baseline['image_sha256']
    assert len(page.ids) == len(set(page.ids))
    assert all(url[1:] in page.ids for url in page.links if url.startswith('#'))
    assert all(not re.match(r'(https?:)?//',url) and (REF/url).is_file() for url in page.assets)
    assert {name:sha((REF/name).read_bytes()) for name in baseline['template_sha256']} == baseline['template_sha256']
    assert '<style>'+(REF/'reference.css').read_text()+'</style>' in document
    assert '<script>'+(REF/'reference.js').read_text()+'</script>' in document
    print(f'Passive localization reference PASS: 3389 mapped names plus the unnamed structural root, {len(raw_lines)} shared source lines ({implemented} implemented), {occurrences} mastery choices, 39 partitions')
    print(f'All {len(baseline["section_sha256"])} v56 catalog sections preserved; only version and display key differ; source execution/geometry/coverage and 68 PNGs identical')
    print(f'{len(page.ids)} anchors, {len(page.links)} links, bilingual hidden search, per-line gates and all unrelated cards verified')


if __name__ == '__main__':
    main()
