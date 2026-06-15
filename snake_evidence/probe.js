const p = require('puppeteer-core');
(async () => {
  try {
    console.log('connecting...');
    const b = await p.connect({ browserURL: 'http://localhost:9335', defaultViewport: null });
    console.log('connected');
    const pg = await b.newPage();
    await pg.goto('file:///home/admin/snake/index.html', { waitUntil: 'load', timeout: 30000 });
    console.log('goto done url=', pg.url());
    const bodyLen = await pg.evaluate(() => document.body.innerHTML.length);
    console.log('bodyLen=', bodyLen);
    const ty = await pg.evaluate(() => typeof window.__snake);
    console.log('snakeType=', ty);
    const r = await pg.evaluate(() => { try { window.__snake.reset(); window.__snake.step(); return window.__snake.getState(); } catch (e) { return { err: e.message }; } });
    console.log('call result=', JSON.stringify(r));
    await pg.close(); await b.disconnect();
    console.log('PROBE OK');
  } catch (e) { console.error('FAIL', e.message); }
})();
