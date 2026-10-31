const { _electron: electron } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const profile = path.resolve(root, '../qa-profile-' + Date.now());
const { Store } = require('../electron/core.cjs');
const initial = new Store(profile);
initial.state.settings.hideShortcut = 'Control+Alt+F20';
initial.state.settings.playbackShortcut = 'Control+Alt+F21';
initial.save();
const shots = path.resolve(root, '../screenshots');
fs.mkdirSync(shots, { recursive: true });
let app;
const errors = [];
const wait = ms => new Promise(r => setTimeout(r, ms));
async function until(predicate) {
  for (let n = 0; n < 150; n++) { if (await predicate()) return; await wait(100); }
  throw new Error('Condition did not become true within 15 seconds');
}
async function launch(offline = false) {
  app = await electron.launch({ args: [root, '--test-mode', `--profile=${profile}`, ...(offline ? ['--offline'] : [])], timeout: 30000 });
  const page = await app.firstWindow();
  page.on('pageerror', e => errors.push(e.message));
  await page.getByRole('heading', { name: '发现好声音' }).waitFor();
  return page;
}
async function run() {
  let page = await launch();
  await page.locator('.book-card').first().waitFor();
  assert.equal(await page.locator('.book-card').count(), 3);
  await page.screenshot({ path: path.join(shots, 'discovery.png') });
  await page.getByLabel('搜索书名、主播或粘贴 BV 链接').fill('三体');
  await page.getByLabel('搜索书名、主播或粘贴 BV 链接').press('Enter');
  await page.getByRole('heading', { name: '“三体”', exact: true }).waitFor();
  await page.locator('.book-title').first().waitFor();
  await page.getByLabel('搜索书名、主播或粘贴 BV 链接').fill('BV1234567890');
  await page.getByLabel('搜索书名、主播或粘贴 BV 链接').press('Enter');
  await page.getByRole('heading', { name: '三体 · 地球往事 有声小说', exact: true }).waitFor();
  await page.getByRole('button', { name: '加入书架', exact: true }).click();
  await page.getByRole('button', { name: '已收藏', exact: true }).waitFor();
  await page.getByRole('button', { name: '开始收听', exact: true }).click();
  await page.getByRole('button', { name: '暂停', exact: true }).waitFor({ timeout: 15000 });
  await page.waitForFunction(() => document.querySelector('.scrubber span').textContent !== '0:00');
  await page.getByLabel('播放进度', { exact: true }).fill('42');
  await page.waitForFunction(() => document.querySelector('.scrubber span').textContent === '0:42');
  await page.getByRole('button', { name: '批量缓存', exact: true }).click();
  await page.getByLabel('选择 第 1 集 · 本地测试音频', { exact: true }).check();
  await page.getByLabel('选择 第 2 集 · 本地测试音频', { exact: true }).check();
  await page.getByRole('button', { name: '缓存所选', exact: true }).click();
  await until(() => page.evaluate(async () => (await window.abts.state()).downloads.filter(t => t.status === 'done').length === 2));
  const before = await page.evaluate(async () => (await window.abts.state()).history.BV1234567890?.chapters[1001]?.position);
  await page.getByRole('button', { name: /^隐藏窗口/ }).click();
  assert.equal(await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].isVisible()), false);
  await wait(6000);
  const after = await page.evaluate(async () => (await window.abts.state()).history.BV1234567890?.chapters[1001]?.position);
  assert.ok(after > before + 2, `Hidden playback did not advance: ${before} -> ${after}`);
  await page.evaluate(() => window.abts.toggleHidden());
  await app.evaluate(({ BrowserWindow }) => { const w = BrowserWindow.getAllWindows()[0]; w.restore(); w.show(); });
  await page.getByRole('button', { name: '暂停', exact: true }).click();
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await page.getByLabel('设置隐藏快捷键').click();
  await page.keyboard.press('Control+Alt+j');
  await page.getByLabel('设置隐藏快捷键').filter({ hasText: 'Ctrl + Alt + J' }).waitFor();
  assert.equal(await app.evaluate(({ globalShortcut }) => globalShortcut.isRegistered('Control+Alt+J')), true);
  assert.equal(await app.evaluate(({ globalShortcut }) => globalShortcut.isRegistered('Control+Alt+H')), false);
  await page.getByRole('button', { name: '深色', exact: true }).click();
  await page.screenshot({ path: path.join(shots, 'settings-dark.png') });
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(860, 680));
  const overflow = await page.evaluate(() => [...document.querySelectorAll('.setting-row,.player-bar,.topbar')].filter(e => e.scrollWidth > e.clientWidth + 2).map(e => e.className));
  assert.deepEqual(overflow, []);
  await page.screenshot({ path: path.join(shots, 'compact-settings.png') });
  await page.getByRole('button', { name: '浅色', exact: true }).click();
  await page.evaluate(() => window.abts.shortcut('Control+Alt+F20'));
  await app.close(); app = null;
  page = await launch(true);
  await page.getByRole('button', { name: /^书架/ }).click();
  await page.locator('.book-title').first().waitFor();
  assert.equal(await page.locator('.book-card').count(), 1);
  await page.locator('.book-title').first().click();
  await page.getByRole('button', { name: '继续收听', exact: true }).click();
  await page.getByRole('button', { name: '暂停', exact: true }).waitFor();
  await page.waitForFunction(() => parseInt(document.querySelector('.scrubber span').textContent.split(':')[1]) >= 42);
  await page.getByLabel('播放进度', { exact: true }).fill('80');
  await page.waitForFunction(() => document.querySelector('.scrubber span').textContent === '1:20');
  await page.screenshot({ path: path.join(shots, 'offline-playback.png') });
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ passed: true, scenarios: [
    'discovery', 'search Enter and direct BV link', 'detail and favorites', 'audio playback and seeking', 'batch downloads',
    'hidden playback advances with taskbar excluded', 'editable registered global shortcut',
    'theme and compact layout', 'restart persistence', 'offline playback and range seeking'
  ], profile, screenshots: shots, hiddenProgress: { before, after } }, null, 2));
}
run().catch(e => { console.error(e); process.exitCode = 1; }).finally(async () => { if (app) await app.close(); });
