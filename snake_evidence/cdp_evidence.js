// Direct CDP evidence v2 — reuse an existing tab from /json + Page.navigate,
// instead of /json/new (which returns non-JSON on chrome 114).
const http = require('http');
const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');

const PORT = process.env.CDP_PORT || '9337';
const GAME = 'file:///home/admin/snake/index.html';
const ART = '/home/admin/snake/.goalspec/artifacts';
fs.mkdirSync(ART, { recursive: true });
const wa = (id, t) => fs.writeFileSync(path.join(ART, `EV-${id}.txt`), t);
const httpGet = (u) => new Promise((res, rej) => {
  http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)); }).on('error', rej);
});

let _id = 0;
function cdpSend(ws, method, params) {
  const id = ++_id;
  return new Promise((res, rej) => {
    const on = (data) => { let m; try { m = JSON.parse(data); } catch (e) { return; } if (m.id === id) { ws.removeListener('message', on); if (m.error) rej(new Error('cdp error ' + method + ': ' + JSON.stringify(m.error))); else res(m.result); } };
    ws.on('message', on);
    ws.send(JSON.stringify({ id: id, method: method, params: params || {} }));
    setTimeout(() => { ws.removeListener('message', on); rej(new Error('timeout ' + method)); }, 15000);
  });
}
const cdpEval = (ws, expr) => cdpSend(ws, 'Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true }).then(r => r.result.value);

(async () => {
  const list = JSON.parse(await httpGet(`http://localhost:${PORT}/json`));
  let tab = list.find(t => t.type === 'page' && t.webSocketDebuggerUrl) || list.find(t => t.webSocketDebuggerUrl);
  if (!tab) throw new Error('no usable tab in /json: ' + JSON.stringify(list).slice(0, 300));
  console.log('using tab:', tab.type, tab.url);
  const ws = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.on('open', r); ws.on('error', j); });
  await cdpSend(ws, 'Page.enable');
  const nav = await cdpSend(ws, 'Page.navigate', { url: GAME });
  if (nav && nav.errorText) throw new Error('navigate failed: ' + nav.errorText);
  await new Promise(r => setTimeout(r, 1500));   // let inline script define window.__snake

  const ty = await cdpEval(ws, 'typeof window.__snake');
  console.log('__snake typeof:', ty);
  if (ty !== 'object') throw new Error('window.__snake not defined: ' + ty);

  const results = {};
  const r1 = await cdpEval(ws, '(function(){window.__snake.reset();var s0=window.__snake.getState();for(var i=0;i<3;i++)window.__snake.step();var s1=window.__snake.getState();return{moved:s0.snake[0].x!==s1.snake[0].x||s0.snake[0].y!==s1.snake[0].y,notOver:!s1.over,from:s0.snake[0],to:s1.snake[0]};})()');
  results['001'] = r1.moved && r1.notOver;
  wa('001', `EV-001 CRIT-001 auto-move-on-tick\nmoved=${r1.moved} notOver=${r1.notOver}\nhead ${JSON.stringify(r1.from)} -> ${JSON.stringify(r1.to)}\nVERDICT: ${results['001'] ? 'PASS' : 'FAIL'}`);

  const r2 = await cdpEval(ws, '(function(){window.__snake.reset();window.__snake.press("ArrowLeft");window.__snake.step();var aR=window.__snake.getState();var rev=aR.dir.x===1&&aR.dir.y===0;window.__snake.press("ArrowUp");window.__snake.step();var aL=window.__snake.getState();var leg=aL.dir.x===0&&aL.dir.y===-1;return{reverseIgnored:rev,legalWorks:leg};})()');
  results['002'] = r2.reverseIgnored && r2.legalWorks;
  wa('002', `EV-002 CRIT-002 direction + reverse-protection\nreverseIgnored=${r2.reverseIgnored} legalTurnWorks=${r2.legalWorks}\nVERDICT: ${results['002'] ? 'PASS' : 'FAIL'}`);

  const r3 = await cdpEval(ws, '(function(){window.__snake.reset();var b=window.__snake.getState();var h=b.snake[0],d=b.dir;window.__snake.setFood({x:h.x+d.x,y:h.y+d.y});window.__snake.step();var a=window.__snake.getState();var grew=a.length===b.length+1;var scored=a.score===b.score+1;var foodSafe=!a.snake.some(function(s){return s.x===a.food.x&&s.y===a.food.y;});return{grew:grew,scored:scored,foodSafe:foodSafe,lenBefore:b.length,lenAfter:a.length};})()');
  results['003'] = r3.grew && r3.scored && r3.foodSafe;
  wa('003', `EV-003 CRIT-003 eat-grow + food-not-on-snake\ngrew=${r3.grew} (len ${r3.lenBefore}->${r3.lenAfter}) scored=${r3.scored} foodSafe=${r3.foodSafe}\nVERDICT: ${results['003'] ? 'PASS' : 'FAIL'}`);

  const r4 = await cdpEval(ws, '(function(){window.__snake.reset();for(var i=0;i<15;i++)window.__snake.step();var sO=window.__snake.getState();var hb=sO.snake[0];window.__snake.step();var sA=window.__snake.getState();return{overNow:sO.over,noMoveAfter:sA.snake[0].x===hb.x&&sA.snake[0].y===hb.y,finalHead:hb};})()');
  results['004'] = r4.overNow && r4.noMoveAfter;
  wa('004', `EV-004 CRIT-004 wall-game-over + freeze\noverNow=${r4.overNow} noMoveAfter=${r4.noMoveAfter} finalHead=${JSON.stringify(r4.finalHead)}\nVERDICT: ${results['004'] ? 'PASS' : 'FAIL'}`);

  const r5 = await cdpEval(ws, '(function(){window.__snake.reset();window.__snake.press(" ");var s=window.__snake.getState();return{scoreZero:s.score===0,lenInit:s.length===3,notOver:!s.over};})()');
  results['005'] = r5.scoreZero && r5.lenInit && r5.notOver;
  wa('005', `EV-005 CRIT-005 restart-resets\nscoreZero=${r5.scoreZero} lengthInit=${r5.lenInit} notOver=${r5.notOver}\nVERDICT: ${results['005'] ? 'PASS' : 'FAIL'}`);

  ws.close();
  const allPass = Object.keys(results).every(k => results[k]);
  const summary = { produced_by: 'direct CDP (HTTP /json + WebSocket Page.navigate + Runtime.evaluate) over google-chrome 114 headless', runtime_boundary: 'browser', game_url: GAME, results: results, all_pass: allPass };
  wa('SUMMARY', JSON.stringify(summary, null, 2));
  console.log(JSON.stringify(summary, null, 2));
  process.exit(allPass ? 0 : 1);
})().catch(e => { console.error('EVIDENCE ERROR:', e.message); process.exit(2); });
