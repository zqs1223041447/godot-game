#!/usr/bin/env python3
"""Render the actual offline F8 HTML in local headless Chromium, without network."""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
errors = []
checks = []


def check(value, label):
    assert value, label
    checks.append(label)


with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True,
                                args=['--no-sandbox', '--disable-dev-shm-usage'])
    page = browser.new_page(viewport={'width': 1440, 'height': 1080}, device_scale_factor=1)
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.route('http://**/*', lambda route: route.abort())
    page.route('https://**/*', lambda route: route.abort())
    page.goto((ROOT / 'docs/reference/index.html').as_uri() + '#maps-ruins_garden')
    card = page.locator('#maps-ruins_garden')
    card.wait_for(state='visible')
    check(page.locator('article:not([hidden])').count() == 5, 'Five map cards visible on direct F8 anchor')
    check('庭园缠印' in card.inner_text(), 'Current attack name rendered')
    query = page.locator('#query')
    for term in ['庭园缠印', 'ruins_garden', 'ruins_garden_inner_outer']:
        query.fill(term)
        check(page.locator('article:not([hidden])').count() == 1 and card.is_visible(), 'Search uniquely finds ruins card: ' + term)
    query.fill('no-such-ruins-attack')
    check(page.locator('#empty').is_visible(), 'No-result search shown')
    page.locator('#clear-search').click()
    check(page.locator('article:not([hidden])').count() == 5 and card.is_visible(), 'Clear restores map category')
    page.evaluate("location.hash = '#town_services-map_device'")
    device = page.locator('#town_services-map_device')
    device.wait_for(state='visible')
    device.locator('a[href="#maps-ruins_garden"]').click()
    check(page.url.endswith('#maps-ruins_garden') and card.is_visible(), 'Map-device link opens current ruins card')
    page.go_back()
    check(page.url.endswith('#town_services-map_device') and device.is_visible(), 'Browser Back restores map-device route')
    page.go_forward()
    card.wait_for(state='visible')
    check(page.url.endswith('#maps-ruins_garden'), 'Browser Forward restores ruins route')
    diagram = page.locator('svg[data-ruins-attack-diagram]')
    geometry = diagram.evaluate('''svg => {
      const first = svg.querySelector('[data-ruins-attack-shape="circle"]');
      const ring = svg.querySelector('[data-ruins-attack-shape="annulus"]');
      const inside = (shape, x, y) => shape.isPointInFill(new DOMPoint(x, y));
      return {firstRadius: first.r.baseVal.value,
              sameScale: first.getCTM().a === ring.getCTM().a,
              firstCenterFilled: inside(first, 0, 0),
              secondCenterEmpty: !inside(ring, 0, 0),
              secondInnerSafe: !inside(ring, 89, 0),
              secondRingFilled: inside(ring, 91, 0) && inside(ring, 209, 0),
              beyondOuterEmpty: !inside(ring, 211, 0)};
    }''')
    check(geometry['firstRadius'] == 90 and all(value for key, value in geometry.items() if key != 'firstRadius'),
          'Chromium confirms matching scale and actual unfilled annulus center')
    diagram.locator('..').screenshot(path=str(QA / 'reference-attack-diagram.png'))
    heading = card.locator('h4').filter(has_text='庭园缠印')
    heading.scroll_into_view_if_needed()
    rect = heading.evaluate('''h => {
      const a = h.getBoundingClientRect();
      const b = h.nextElementSibling.getBoundingClientRect();
      return {x:a.x, y:a.y + window.scrollY, width:a.width, height:b.bottom-a.top};
    }''')
    page.screenshot(path=str(QA / 'reference-attack-values.png'), clip=rect)
    check(not errors, 'No browser script errors')
    report = {'browser': browser.version, 'surface': 'Actual offline docs/reference/index.html, local headless Chromium',
              'viewport': {'width': 1440, 'height': 1080}, 'network_requests_blocked': True,
              'checks': checks, 'geometry': geometry, 'page_errors': errors,
              'screenshots': ['reference-attack-diagram.png', 'reference-attack-values.png'],
              'scope': 'Static F8 HTML/search/links/history and SVG fill geometry; not Godot gameplay or F8 key-launch acceptance'}
    (QA / 'reference-browser-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    browser.close()
print(f'RUINS_ATTACK_REFERENCE_BROWSER passed: {len(checks)} checks; actual F8 HTML, search, navigation/history, same-scale hollow ring; no JavaScript errors')
