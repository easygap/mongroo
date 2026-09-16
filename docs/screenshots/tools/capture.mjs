// README 캡처 — 도트 개편 뒤의 실제 빌드 화면.
//
// 메모리 `mood-pot-capture-pipeline`의 절차: Playwright 헤드리스, UI 로그인,
// 해시 라우팅, 캔버스 좌표 탭. 걷기 움짤은 CDP 스크린캐스트(520×1126 DPR1).
//
//   node tmp/pixel-overhaul/capture.mjs <out-dir>
//
// 결과: hub.png(390 DPR2), battle.png(360x732 DPR2), walk-frames/*.png (+ walk.json)

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const playwright = require(
  'C:/Users/USER/AppData/Local/npm-cache/_npx/e41f203b7505f1fb/node_modules/playwright',
);

const OUT = process.argv[2] || 'tmp/pixel-overhaul/captures';
fs.mkdirSync(OUT, { recursive: true });
const BASE = 'http://localhost:8080';
const EMAIL = 'qa-pixel@example.com';
const PASSWORD = 'pixel-demo-2026!';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function tap(page, x, y, hold = 100) {
  await page.mouse.move(x, y);
  await page.mouse.down();
  await sleep(hold);
  await page.mouse.up();
}

async function login(page) {
  await page.goto(`${BASE}/#/login`, { waitUntil: 'load' });
  await sleep(4000);
  const { width } = page.viewportSize();
  await tap(page, width / 2, 325);
  await page.keyboard.type(EMAIL);
  await page.keyboard.press('Tab');
  await page.keyboard.type(PASSWORD);
  await sleep(300);
  await tap(page, width / 2, 470);
  await sleep(6000);
}

async function retreatIfActive(page) {
  // 진행 중인 판이 있으면 전투/필드가 뜬다. 상단 바의 귀환 → 확인.
  await page.goto(`${BASE}/#/expedition`, { waitUntil: 'load' });
  await sleep(6000);
}

async function main() {
  const browser = await playwright.chromium.launch({ headless: true, executablePath: 'C:/Users/USER/AppData/Local/ms-playwright/chromium_headless_shell-1234/chrome-headless-shell-win64/chrome-headless-shell.exe' });
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    colorScheme: 'light',
    locale: 'ko-KR',
  });
  const page = await context.newPage();
  await login(page);

  // 1) 허브 배너 — 정원 탭 → 탐험 서브탭 (전환 애니메이션 때문에 두 번).
  await page.goto(`${BASE}/#/garden`, { waitUntil: 'load' });
  await sleep(5000);
  await tap(page, 332, 70);
  await sleep(3000);
  await tap(page, 332, 70);
  await sleep(5000);
  await page.screenshot({ path: path.join(OUT, 'hub.png') });

  // 2) 스테이지로 들어가 걷기 필드까지.
  await retreatIfActive(page);
  await tap(page, 345, 205); // 다른 스테이지·캐릭터 고르기
  await sleep(4000);
  await tap(page, 195, 200); // 첫 스테이지 행
  await sleep(4000);
  await tap(page, 195, 797); // 다시 걸기
  await sleep(5000);
  await tap(page, 195, 645); // 보상 없이 자유 탐험
  await sleep(7000);
  await page.screenshot({ path: path.join(OUT, 'walk.png') });

  // 3) 걷기 움짤 — 520×1126 DPR1 스크린캐스트.
  await page.setViewportSize({ width: 520, height: 1126 });
  await sleep(3000);
  const cdp = await context.newCDPSession(page);
  const frames = [];
  cdp.on('Page.screencastFrame', async ({ data, sessionId, metadata }) => {
    frames.push({ data, timestamp: metadata.timestamp });
    await cdp.send('Page.screencastFrameAck', { sessionId });
  });
  await cdp.send('Page.startScreencast', {
    format: 'png',
    quality: 100,
    maxWidth: 520,
    maxHeight: 1126,
    everyNthFrame: 1,
  });
  // 필드 가운데를 한 번 눌러 포커스를 준 뒤 방향키로 걷는다.
  await tap(page, 260, 640, 60);
  await sleep(300);
  const route = [
    'ArrowDown', 'ArrowDown', 'ArrowDown', 'ArrowRight', 'ArrowRight',
    'ArrowRight', 'ArrowRight', 'ArrowDown', 'ArrowDown', 'ArrowLeft',
    'ArrowLeft', 'ArrowLeft', 'ArrowUp', 'ArrowUp', 'ArrowRight', 'ArrowRight',
  ];
  for (const key of route) {
    await page.keyboard.down(key);
    await sleep(120);
    await page.keyboard.up(key);
    await sleep(220);
  }
  await sleep(600);
  await cdp.send('Page.stopScreencast');
  const frameDir = path.join(OUT, 'walk-frames');
  fs.mkdirSync(frameDir, { recursive: true });
  frames.forEach((frame, index) => {
    fs.writeFileSync(
      path.join(frameDir, `f${String(index).padStart(4, '0')}.png`),
      Buffer.from(frame.data, 'base64'),
    );
  });
  fs.writeFileSync(
    path.join(OUT, 'walk.json'),
    JSON.stringify(frames.map((f) => f.timestamp)),
  );
  console.log('walk frames', frames.length);

  // 4) 전투 — 360×732 DPR2. 깃발로 목적지까지 가서 전투 진입.
  await page.setViewportSize({ width: 360, height: 732 });
  await sleep(3000);
  await tap(page, 360 - 8 - 21, 265);
  await sleep(1500);
  await tap(page, 360 - 8 - 21, 265);
  await sleep(8000);
  await page.screenshot({ path: path.join(OUT, 'battle.png') });
  // 한 차례 — 기본 공격 카드.
  await tap(page, 42, 690);
  await sleep(450);
  await page.screenshot({ path: path.join(OUT, 'battle-hit.png') });
  await sleep(4000);
  await page.screenshot({ path: path.join(OUT, 'battle-round2.png') });

  await browser.close();
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
