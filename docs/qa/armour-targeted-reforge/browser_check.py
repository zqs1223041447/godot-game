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
        page.goto('http://127.0.0.1:%d/index.html#crafting-targeted_reforge_armour'%server.server_port,wait_until='load')
        card=page.locator('#crafting-targeted_reforge_armour');card.wait_for(state='visible')
        for word in ['护甲','灰烬皮甲','魔法16','稀有40','总计32碎片','不保证高阶','30–50']:
            assert word in re.sub(r'\s+','',card.inner_text()),word
        page.locator('#query').fill('护甲');assert card.is_visible()
        card.screenshot(path=str(QA/'f8-armour-card.png'))
        page.locator('#query').fill('')
        page.goto('http://127.0.0.1:%d/index.html#affixes-ironhide'%server.server_port,wait_until='load')
        page.locator('#affixes-ironhide').wait_for(state='visible')
        page.locator('#affixes-ironhide a[href="#crafting-targeted_reforge_armour"]').click()
        assert card.is_visible()
        assert not errors,errors
        (QA/'browser.json').write_text(json.dumps({'errors':errors,'browser':browser.version,'search':'护甲','related_link':'ironhide -> targeted armour','method':'Loopback-only generated HTML, original search/link controls. No F8 keystroke or external hosting claim.'},ensure_ascii=False,indent=2)+'\n')
        browser.close()
finally:server.shutdown()
print('Armour F8 card, original search and related link passed')
