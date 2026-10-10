from pathlib import Path
import json,re
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from functools import partial
from threading import Thread
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[3];QA=Path(__file__).resolve().parent
server=ThreadingHTTPServer(('127.0.0.1',0),partial(SimpleHTTPRequestHandler,directory=str(ROOT/'docs/reference')))
Thread(target=server.serve_forever,daemon=True).start()
try:
    with sync_playwright() as p:
        browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
        page=browser.new_page(viewport={'width':1440,'height':1080},device_scale_factor=1)
        errors=[];page.on('pageerror',lambda err:errors.append(str(err)))
        page.goto('http://127.0.0.1:%d/index.html#maps-ginkgo_arcade'%server.server_port,wait_until='load')
        card=page.locator('#maps-ginkgo_arcade');card.wait_for(state='visible')
        for word in ['西叶追击与雷圈','第3名额','0.7秒','半径65','15%','没有候选就不替换']:
            assert word in re.sub(r'\s+','',card.inner_text()),word
        page.locator('#query').fill('西叶追击');assert card.is_visible()
        card.locator('h4',has_text='西叶追击与雷圈').scroll_into_view_if_needed()
        page.screenshot(path=str(QA/'f8-west-storm.png'))
        page.locator('#query').fill('')
        card.locator('a[href="#monsters-storm_skitter"]').first.click()
        page.locator('#monsters-storm_skitter').wait_for(state='visible')
        assert not errors,errors
        (QA/'browser.json').write_text(json.dumps({'errors':errors,'browser':browser.version,'search':'西叶追击','related_link':'Ginkgo west -> existing storm skitter','method':'Loopback-only generated HTML, original search/link controls. No F8 keystroke or external hosting claim.'},ensure_ascii=False,indent=2)+'\n')
        browser.close()
finally:server.shutdown()
print('Ginkgo west card, original search and existing monster link passed')
