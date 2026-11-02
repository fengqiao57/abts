const { _electron: electron } = require('playwright');
const path = require('node:path');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { Store } = require('../electron/core.cjs');
const root = path.resolve(__dirname, '..');
const profile = path.resolve(root, '../window-input-profile-' + Date.now());
const store = new Store(profile);
store.state.settings.hideShortcut = 'Control+Alt+F18';
store.state.settings.playbackShortcut = 'Control+Alt+F19';
store.save();
const executable = process.env.ABTS_TEST_EXE;
let app;
const wait = ms => new Promise(r => setTimeout(r, ms));
async function run() {
  app = await electron.launch(executable
    ? { executablePath: executable, args: [`--profile=${profile}`] }
    : { args: [root, '--test-mode', `--profile=${profile}`] });
  const page = await app.firstWindow();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.getByRole('heading', { name: '发现好声音' }).waitFor();
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await app.evaluate(({ BrowserWindow, app }) => {
    const w = BrowserWindow.getAllWindows()[0];
    const ffi = process.mainModule.require(app.getAppPath() + '/node_modules/koffi');
    const dll = ffi.load('user32.dll');
    global.__inputTest = {
      window: w, hwnd: w.getNativeWindowHandle().readBigUInt64LE(),
      showWindow: dll.func('bool __stdcall ShowWindow(void *hWnd, int nCmdShow)'),
      isIconic: dll.func('bool __stdcall IsIconic(void *hWnd)'),
      visible: dll.func('bool __stdcall IsWindowVisible(void *hWnd)'),
      focusEvents: 0
    };
    w.on('focus', () => global.__inputTest.focusEvents++);
  });
  await page.evaluate(() => {
    window.__inputTest = { pointer: 0 };
    document.addEventListener('pointerdown', () => window.__inputTest.pointer++, true);
  });
  for (let cycle = 0; cycle < 24; cycle++) {
    await page.evaluate(() => window.abts.toggleHidden());
    assert.equal(await page.evaluate(async () => (await window.abts.state()).windowHidden), true);
    await app.evaluate(() => { global.__inputTest.focusEvents = 0; });
    await page.evaluate(() => window.abts.toggleHidden());
    await wait(30);
    const taskbar = await app.evaluate(() => {
      const t = global.__inputTest;
      return { visible: t.visible(t.hwnd), minimized: t.isIconic(t.hwnd), focusEvents: t.focusEvents };
    });
    assert.deepEqual(taskbar, { visible: true, minimized: true, focusEvents: 0 });
    // SW_RESTORE follows the native taskbar path without BrowserWindow.show().
    await app.evaluate(() => global.__inputTest.showWindow(global.__inputTest.hwnd, 9));
    await page.getByRole('button', { name: /^书架/ }).click();
    await page.getByRole('heading', { name: '我的书架', exact: true }).waitFor();
    await page.getByRole('button', { name: '设置', exact: true }).click();
    await page.getByRole('heading', { name: '设置', exact: true }).waitFor();
    await page.getByRole('button', { name: '睡眠定时', exact: true }).click();
    await page.getByRole('dialog').waitFor();
    await page.getByRole('dialog').getByRole('button', { name: '关闭', exact: true }).click();
    assert.equal(await page.getByRole('dialog').count(), 0);
  }
  assert.ok(await page.evaluate(() => window.__inputTest.pointer) >= 96);
  // Restoring while a legitimate modal is open must preserve and close it normally.
  await page.getByRole('button', { name: '睡眠定时', exact: true }).click();
  await page.evaluate(() => window.abts.toggleHidden());
  await page.evaluate(() => window.abts.toggleHidden());
  await app.evaluate(() => global.__inputTest.showWindow(global.__inputTest.hwnd, 9));
  await page.getByRole('dialog').getByRole('button', { name: '关闭', exact: true }).click();
  await page.getByRole('button', { name: /^最近收听/ }).click();
  await page.getByRole('heading', { name: '最近收听', exact: true }).waitFor();
  // Concurrent hide/unhide requests must settle without a late restoration exposing it.
  await page.evaluate(async () => { for (let n = 0; n < 10; n++) await window.abts.toggleHidden(); });
  const result = await app.evaluate(() => ({ visible: global.__inputTest.visible(global.__inputTest.hwnd),
    minimized: global.__inputTest.isIconic(global.__inputTest.hwnd) }));
  assert.deepEqual(result, { visible: true, minimized: true });
  await app.evaluate(() => global.__inputTest.showWindow(global.__inputTest.hwnd, 9));
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await page.getByRole('heading', { name: '设置', exact: true }).waitFor();
  await page.evaluate(() => { setTimeout(() => { throw new Error('ABTS diagnostic capture test'); }, 0); });
  await wait(1000);
  const logs = fs.readFileSync(path.join(profile, 'logs/diagnostics.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
  assert.ok(logs.filter(r => r.event === 'window-input-synchronized').length >= 26);
  assert.ok(logs.some(r => r.event === 'renderer-input'));
  assert.ok(logs.some(r => r.event === 'renderer-error' && r.detail.renderer.message.includes('diagnostic capture test')));
  assert.equal(errors.filter(e => !e.includes('ABTS diagnostic capture test')).length, 0);
  const report = { version: await app.evaluate(({ app }) => app.getVersion()), packaged: !!executable,
    restoreCycles: 24, dialogPreserved: true, rapidToggleRequests: 10, noFocusOnUnhide: true,
    pointerEvents: await page.evaluate(() => window.__inputTest.pointer), rendererErrorCaptured: true,
    nativeMouseInjection: false, profile };
  console.log(JSON.stringify(report, null, 2));
  fs.writeFileSync(path.join(root, executable ? '../packaged-window-input-results.json' : '../window-input-results.json'), JSON.stringify(report, null, 2));
}
run().catch(e => { console.error(e); process.exitCode = 1; }).finally(async () => { if (app) await app.close(); });
