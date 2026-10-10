from pathlib import Path
import json
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from functools import partial
from threading import Thread
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[3]
QA=Path(__file__).resolve().parent
server=ThreadingHTTPServer(("127.0.0.1",0),partial(SimpleHTTPRequestHandler,directory=str(ROOT/"docs/reference")))
Thread(target=server.serve_forever,daemon=True).start()
with sync_playwright() as p:
    browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
    page=browser.new_page(viewport={'width':1440,'height':1080},device_scale_factor=1)
    errors=[];page.on('pageerror',lambda error:errors.append(str(error)))
    page.goto('http://127.0.0.1:%d/index.html#source_passives-27163'%server.server_port,wait_until='load')
    card=page.locator('#source_passives-27163');card.wait_for(state='visible')
    text=card.inner_text()
    assert '奥术意志' in text and '暂未实装' not in text
    assert '最大魔力提高30%' in text and '共8点' in text and '下夹' in text
    card.screenshot(path=str(QA/'f8-arcane-card.png'))
    # Actual original search and status filter operate on the refreshed records.
    page.locator('#query').fill('27163');page.locator('#status').select_option('implemented')
    assert card.is_visible()
    page.locator('#status').select_option('planned')
    assert not card.is_visible()
    page.locator('#status').select_option('');page.locator('#query').fill('10495')
    blocked=page.locator('#source_passives-10495');blocked.wait_for(state='visible')
    for detail in blocked.locator('details').all():
        if detail.get_attribute('open') is None:detail.locator('summary').first.click()
    assert '暂未实装' in blocked.inner_text()
    shared=json.loads((QA/'reference-fragment.json').read_text())['localized_line']['text']
    assert shared in blocked.inner_text()
    assert not errors,errors
    (QA/'browser.json').write_text(json.dumps({'page_errors':errors,'target':'27163','implemented_filter':True,'planned_filter_hides_target':True,'other_unsupported_node':'10495','other_node_still_unimplemented':True,'browser':browser.version,'method':'Chromium blocks file:// by administrator policy. Render same generated HTML through loopback-only HTTP, original search/status controls; no external hosting or game F8 key simulation.'},ensure_ascii=False,indent=2)+'\n')
    browser.close()
server.shutdown()
print('F8 browser target, search/status filters and unsupported neighbor checks passed')
