const { _electron: electron } = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const { Store } = require('../electron/core.cjs');
const root = path.resolve(__dirname, '..');
const profile = path.resolve(root, '../shortcut-profile-' + Date.now());
const store = new Store(profile);
store.state.settings.hideShortcut = 'Control+Alt+F18';
store.state.settings.playbackShortcut = 'Control+Alt+F19';
store.save();
let app, page;
const errors = [];
const passed = [];
const wait = ms => new Promise(r => setTimeout(r, ms));
async function until(predicate) {
  for (let n = 0; n < 150; n++) { if (await predicate()) return; await wait(100); }
  throw new Error('Condition did not become true within 15 seconds');
}
const check = name => { passed.push(name); console.log('PASS:', name); };
async function launch() {
  app = await electron.launch({ args: [root, '--test-mode', `--profile=${profile}`] });
  page = await app.firstWindow();
  page.on('pageerror', e => errors.push(e.message));
  await page.getByRole('heading', { name: '发现好声音' }).waitFor();
  await app.evaluate(({ globalShortcut, BrowserWindow }) => {
    global.__mainWindow = BrowserWindow.getAllWindows()[0];
    global.__shortcutCallbacks = {};
    const register = globalShortcut.register.bind(globalShortcut);
    globalShortcut.register = (key, callback) => {
      const ok = register(key, callback);
      if (ok) global.__shortcutCallbacks[key] = callback;
      return ok;
    };
  });
}
async function invoke(action) {
  const settings = (await page.evaluate(() => window.abts.state())).settings;
  await app.evaluate((_, key) => {
    const assertCallback = global.__shortcutCallbacks[key];
    if (!assertCallback) throw new Error('Registered callback not captured: ' + key);
    assertCallback();
  }, settings[action === 'hide' ? 'hideShortcut' : 'playbackShortcut']);
}
async function nativeState() {
  return app.evaluate(({ BrowserWindow }, koffiPath) => {
    const w = global.__mainWindow;
    const h = w.getNativeWindowHandle().readBigUInt64LE();
    const dll = process.mainModule.require(koffiPath).load('user32.dll');
    const style = Number(dll.func('intptr_t __stdcall GetWindowLongPtrW(void *hWnd, int nIndex)')(h, -20));
    return { visible: dll.func('bool __stdcall IsWindowVisible(void *hWnd)')(h),
      minimized: dll.func('bool __stdcall IsIconic(void *hWnd)')(h),
      focused: w.isFocused(), toolWindow: !!(style & 0x80),
      owner: String(dll.func('void *__stdcall GetWindow(void *hWnd, unsigned int uCmd)')(h, 4)) };
  }, path.join(root, 'node_modules/koffi'));
}
async function expectHidden() {
  assert.equal((await page.evaluate(() => window.abts.state())).windowHidden, true);
  assert.equal((await nativeState()).visible, false);
}
async function expectTaskbarOnly() {
  assert.equal((await page.evaluate(() => window.abts.state())).windowHidden, false);
  const state = await nativeState();
  assert.equal(state.visible, true, JSON.stringify(state));
  assert.equal(state.minimized, true, JSON.stringify(state));
  assert.equal(state.focused, false, JSON.stringify(state));
  assert.equal(state.toolWindow, false, JSON.stringify(state));
  assert.equal(state.owner, 'null', JSON.stringify(state));
}
async function restoreManually() {
  await app.evaluate(({ BrowserWindow }) => {
    const w = global.__mainWindow; w.restore(); w.show(); w.focus();
  });
}
async function run() {
  await launch();
  await page.getByRole('button', { name: '设置', exact: true }).click();
  for (const [label, key] of [['隐藏', 'j'], ['播放', 'k']]) {
    await page.getByLabel(`设置${label}快捷键`).click();
    await page.keyboard.press(`Control+Alt+${key}`);
    await page.getByLabel(`设置${label}快捷键`).filter({ hasText: `Ctrl + Alt + ${key.toUpperCase()}` }).waitFor();
  }
  check('both shortcut recorders register and persist independent combinations');
  await invoke('playback');
  assert.equal(await page.getByRole('button', { name: '播放', exact: true }).isDisabled(), true);
  check('playback shortcut without a selected book does not open a window or invent playback');
  const conflict = await page.evaluate(async () => {
    try { await window.abts.shortcut('Control+Alt+J', 'playback'); return ''; } catch (e) { return e.message; }
  });
  assert.match(conflict, /不能相同/);
  await app.evaluate(({ globalShortcut }) => { globalShortcut.register('Control+Alt+F24', () => {}); });
  const occupied = await page.evaluate(async () => {
    try { await window.abts.shortcut('Control+Alt+F24', 'playback'); return ''; } catch (e) { return e.message; }
  });
  assert.match(occupied, /占用/);
  assert.equal(await app.evaluate(({ globalShortcut }) => globalShortcut.isRegistered('Control+Alt+K')), true);
  await app.evaluate(({ globalShortcut }) => { globalShortcut.unregister('Control+Alt+F24'); });
  check('duplicate and occupied shortcuts retain the previous working registration');

  await page.getByLabel('搜索书名、主播或粘贴 BV 链接').fill('BV1234567890');
  await page.getByLabel('搜索书名、主播或粘贴 BV 链接').press('Enter');
  await page.getByRole('button', { name: '开始收听', exact: true }).click();
  await page.getByRole('button', { name: '暂停', exact: true }).waitFor();
  await page.waitForFunction(() => document.querySelector('.scrubber span').textContent !== '0:00');
  await page.getByLabel('播放进度', { exact: true }).fill('42');
  await until(() => page.evaluate(async () => (await window.abts.state()).history.BV1234567890?.chapters?.[1001]?.position >= 42));
  await app.evaluate(({ BrowserWindow }) => {
    global.__focusEvents = 0;
    global.__mainWindow.on('focus', () => global.__focusEvents++);
  });
  await invoke('hide'); await expectHidden();
  const before = await page.evaluate(async () => (await window.abts.state()).history.BV1234567890.chapters[1001].position);
  await wait(6000);
  const after = await page.evaluate(async () => (await window.abts.state()).history.BV1234567890.chapters[1001].position);
  assert.ok(after > before + 2, `${before} -> ${after}`);
  check('foreground window hides and audio continues in the background');
  await invoke('playback');
  await page.getByRole('button', { name: '播放', exact: true }).waitFor();
  const pausedAt = await page.locator('.scrubber span').first().innerText();
  await wait(1200);
  assert.equal(await page.locator('.scrubber span').first().innerText(), pausedAt);
  await expectHidden();
  await invoke('playback');
  await page.getByRole('button', { name: '暂停', exact: true }).waitFor();
  await expectHidden();
  check('registered playback callback pauses and resumes audio without unhiding');
  await invoke('hide'); await expectTaskbarOnly();
  assert.equal(await app.evaluate(() => global.__focusEvents), 0);
  check('unhide restores a native visible minimized taskbar window without any focus event');
  await invoke('hide'); await expectHidden();
  await app.evaluate(({ app }) => app.emit('second-instance'));
  await expectTaskbarOnly();
  check('a minimized restored window hides again; a second launch does not expose a hidden window');
  await restoreManually();
  await app.evaluate(async ({ BrowserWindow }) => {
    global.__otherWindow = new BrowserWindow({ width: 360, height: 240, title: 'Shortcut test foreground' });
    await global.__otherWindow.loadURL('about:blank');
    global.__otherWindow.show(); global.__otherWindow.focus();
  });
  await until(() => app.evaluate(() => global.__otherWindow.isFocused()));
  assert.equal(await app.evaluate(() => global.__mainWindow.isFocused()), false);
  await invoke('hide'); await expectHidden();
  await invoke('hide'); await expectTaskbarOnly();
  assert.equal(await app.evaluate(() => global.__otherWindow.isFocused()), true);
  check('a covered window hides, then restores only to taskbar while the other window keeps focus');
  await app.evaluate(() => global.__otherWindow.destroy());
  await restoreManually();
  await app.evaluate(() => global.__mainWindow.minimize());
  await invoke('hide'); await expectHidden();
  await invoke('hide'); await expectTaskbarOnly();
  check('an ordinarily minimized window enters hidden state on the first shortcut');
  await restoreManually();
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await app.evaluate(() => global.__mainWindow.setSize(860, 680));
  assert.deepEqual(await page.evaluate(() => [...document.querySelectorAll('.setting-row,.player-bar,.topbar')].filter(e => e.scrollWidth > e.clientWidth + 2).map(e => e.className)), []);
  await page.screenshot({ path: path.join(root, '../shortcut-settings.png') });
  check('both shortcut controls fit the minimum supported window');
  await app.close(); app = null;
  await launch();
  const state = await page.evaluate(() => window.abts.state());
  assert.equal(state.settings.hideShortcut, 'Control+Alt+J');
  assert.equal(state.settings.playbackShortcut, 'Control+Alt+K');
  assert.equal(state.shortcutStatus.active, 'Control+Alt+J');
  assert.equal(state.shortcutStatus.playbackActive, 'Control+Alt+K');
  await page.evaluate(async () => {
    await window.abts.shortcut('Control+Alt+F18');
    await window.abts.shortcut('Control+Alt+J');
    await window.abts.shortcut('Control+Alt+F19', 'playback');
    await window.abts.shortcut('Control+Alt+K', 'playback');
  });
  await invoke('hide'); await expectHidden();
  await invoke('playback');
  await page.getByRole('button', { name: '暂停', exact: true }).waitFor();
  await expectHidden();
  check('restart restores both shortcuts; playback resumes the saved chapter while hidden');
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ passed, nativeKeyInjection: false, hiddenProgress: { before, after }, profile }, null, 2));
  fs.writeFileSync(path.join(root, '../shortcut-test-results.json'), JSON.stringify({ passed, nativeKeyInjection: false, hiddenProgress: { before, after }, profile }, null, 2));
}
run().catch(e => { console.error(e); process.exitCode = 1; }).finally(async () => { if (app) await app.close(); });
