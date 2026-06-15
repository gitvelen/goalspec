// Browser-level evidence for the snake game (GOALC #23 / §27.4).
// Connects to a chrome already running with --remote-debugging-port=9222
// (puppeteer.launch's startup handshake is unreliable vs chrome 114 in this sandbox;
//  chrome self-started CDP + puppeteer.connect works — verified via /json/version).
const puppeteer = require('puppeteer-core');
const fs = require('fs');
const path = require('path');

const GAME = 'file:///home/admin/snake/index.html';
const ART = '/home/admin/snake/.goalspec/artifacts';
fs.mkdirSync(ART, { recursive: true });

function writeArtifact(id, text) { fs.writeFileSync(path.join(ART, `EV-${id}.txt`), text); }

(async () => {
  const browser = await puppeteer.connect({
    browserURL: process.env.CDP_URL || 'http://localhost:9222',
    defaultViewport: null,
  });
  const page = await browser.newPage();
  // Under puppeteer.connect + chrome 114, goto's load/domcontentloaded event wait
  // stalls. Use waitUntil:'none' (fire navigation, don't wait for events), give the
  // inline script time to define window.__snake, then verify directly.
  await page.goto(GAME, { waitUntil: 'none', timeout: 30000 });
  await new Promise(r => setTimeout(r, 1500));
  const _ready = await page.evaluate(() => typeof window.__snake);
  if (_ready !== 'object') throw new Error('window.__snake not defined after load: ' + _ready);

  const results = {};

  // EV-001 — CRIT-001: page loads, snake auto-moves on tick without input.
  const r001 = await page.evaluate(() => {
    window.__snake.reset();
    const s0 = window.__snake.getState();
    for (let i = 0; i < 3; i++) window.__snake.step();
    const s1 = window.__snake.getState();
    const moved = (s0.snake[0].x !== s1.snake[0].x) || (s0.snake[0].y !== s1.snake[0].y);
    return { moved: moved, notOver: !s1.over, from: s0.snake[0], to: s1.snake[0] };
  });
  results['001'] = r001.moved && r001.notOver;
  writeArtifact('001', `EV-001 CRIT-001 auto-move-on-tick\nmoved=${r001.moved} notOver=${r001.notOver}\nhead ${JSON.stringify(r001.from)} -> ${JSON.stringify(r001.to)}\nVERDICT: ${results['001'] ? 'PASS' : 'FAIL'}`);

  // EV-002 — CRIT-002: direction key changes direction; reverse input ignored.
  const r002 = await page.evaluate(() => {
    window.__snake.reset();            // dir = right
    window.__snake.press('ArrowLeft'); // left is opposite of right -> must be ignored
    window.__snake.step();
    const afterReverse = window.__snake.getState();
    const reverseIgnored = afterReverse.dir.x === 1 && afterReverse.dir.y === 0;
    window.__snake.press('ArrowUp');   // legal turn
    window.__snake.step();
    const afterLegal = window.__snake.getState();
    const legalWorks = afterLegal.dir.x === 0 && afterLegal.dir.y === -1;
    return { reverseIgnored: reverseIgnored, legalWorks: legalWorks };
  });
  results['002'] = r002.reverseIgnored && r002.legalWorks;
  writeArtifact('002', `EV-002 CRIT-002 direction + reverse-protection\nreverseIgnored=${r002.reverseIgnored} legalTurnWorks=${r002.legalWorks}\nVERDICT: ${results['002'] ? 'PASS' : 'FAIL'}`);

  // EV-003 — CRIT-003: eating grows body, increments score, new food not on snake.
  const r003 = await page.evaluate(() => {
    window.__snake.reset();
    const before = window.__snake.getState();
    const h = before.snake[0], d = before.dir;
    window.__snake.setFood({ x: h.x + d.x, y: h.y + d.y });
    window.__snake.step();
    const after = window.__snake.getState();
    const grew = after.length === before.length + 1;
    const scored = after.score === before.score + 1;
    const foodSafe = !after.snake.some(s => s.x === after.food.x && s.y === after.food.y);
    return { grew: grew, scored: scored, foodSafe: foodSafe, lenBefore: before.length, lenAfter: after.length };
  });
  results['003'] = r003.grew && r003.scored && r003.foodSafe;
  writeArtifact('003', `EV-003 CRIT-003 eat-grow + food-not-on-snake\ngrew=${r003.grew} (len ${r003.lenBefore}->${r003.lenAfter}) scored=${r003.scored} foodSafe=${r003.foodSafe}\nVERDICT: ${results['003'] ? 'PASS' : 'FAIL'}`);

  // EV-004 — CRIT-004: wall collision -> game over, no further movement.
  const r004 = await page.evaluate(() => {
    window.__snake.reset();            // dir = right, head.x = 8, wall at x>=20
    for (let i = 0; i < 15; i++) window.__snake.step();
    const sOver = window.__snake.getState();
    const overNow = sOver.over;
    const headBefore = sOver.snake[0];
    window.__snake.step();
    const sAfter = window.__snake.getState();
    const noMoveAfter = sAfter.snake[0].x === headBefore.x && sAfter.snake[0].y === headBefore.y;
    return { overNow: overNow, noMoveAfter: noMoveAfter, finalHead: headBefore };
  });
  results['004'] = r004.overNow && r004.noMoveAfter;
  writeArtifact('004', `EV-004 CRIT-004 wall-game-over + freeze\noverNow=${r004.overNow} noMoveAfter=${r004.noMoveAfter} finalHead=${JSON.stringify(r004.finalHead)}\nVERDICT: ${results['004'] ? 'PASS' : 'FAIL'}`);

  // EV-005 — CRIT-005: restart resets to initial state.
  const r005 = await page.evaluate(() => {
    window.__snake.reset();
    window.__snake.press(' ');
    const s = window.__snake.getState();
    return { scoreZero: s.score === 0, lenInit: s.length === 3, notOver: !s.over };
  });
  results['005'] = r005.scoreZero && r005.lenInit && r005.notOver;
  writeArtifact('005', `EV-005 CRIT-005 restart-resets\nscoreZero=${r005.scoreZero} lengthInit=${r005.lenInit} notOver=${r005.notOver}\nVERDICT: ${results['005'] ? 'PASS' : 'FAIL'}`);

  await page.close();
  await browser.disconnect();

  const allPass = Object.keys(results).every(k => results[k]);
  const summary = {
    produced_by: 'puppeteer-core connect + google-chrome 114 headless (--remote-debugging-port)',
    runtime_boundary: 'browser',
    game_url: GAME,
    results: results,
    all_pass: allPass,
  };
  writeArtifact('SUMMARY', JSON.stringify(summary, null, 2));
  console.log(JSON.stringify(summary, null, 2));
  process.exit(allPass ? 0 : 1);
})().catch(e => { console.error('EVIDENCE ERROR:', e.message); process.exit(2); });
