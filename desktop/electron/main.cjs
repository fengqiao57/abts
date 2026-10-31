const { app, BrowserWindow, ipcMain, protocol, shell, dialog, safeStorage, Menu, globalShortcut, powerSaveBlocker } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { Readable } = require('node:stream');
const { pathToFileURL } = require('node:url');
const { BV, Store, defaultState } = require('./core.cjs');
const { Bili } = require('./bili.cjs');
const { Downloads, fetchMedia } = require('./downloads.cjs');
const { restoreToTaskbar, installWindowRecovery } = require('./window-state.cjs');
const { createDiagnostics } = require('./diagnostics.cjs');

protocol.registerSchemesAsPrivileged([{ scheme: 'abts', privileges: {
  standard: true, secure: true, supportFetchAPI: true, stream: true
} }]);
const testMode = !app.isPackaged && process.argv.includes('--test-mode');
const profileArg = process.argv.find(a => a.startsWith('--profile='));
if (profileArg) app.setPath('userData', path.resolve(profileArg.slice(10)));
app.setAppUserModelId('dev.abts.desktop');
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) app.quit();
let window, store, api, downloads;
let diagnostics;
let lastHeartbeat = 0;
let quitting = false;
let hidden = false;
const shortcuts = {
  hide: { setting: 'hideShortcut', active: '', error: '', callback: toggleHidden },
  playback: { setting: 'playbackShortcut', active: '', error: '', callback: togglePlayback }
};
let playbackBlocker;
const tokens = new Map();
const startup = Date.now();
function record(event, detail = {}) { diagnostics?.log(event, detail); }
function windowSnapshot() {
  if (!window || window.isDestroyed()) return { destroyed: true };
  return { hidden, visible: window.isVisible(), minimized: window.isMinimized(),
    focused: window.isFocused(), enabled: window.isEnabled(),
    rendererFocused: window.webContents.isFocused(), loading: window.webContents.isLoading(),
    rendererPid: window.webContents.getOSProcessId() };
}
process.on('uncaughtExceptionMonitor', error => record('main-uncaught-exception', error));
process.on('unhandledRejection', error => record('main-unhandled-rejection', error));
app.on('child-process-gone', (_, details) => record('child-process-gone', details));
function runtimeState() {
  return { ...store.state, windowHidden: hidden, shortcutStatus: {
    active: shortcuts.hide.active, error: shortcuts.hide.error,
    playbackActive: shortcuts.playback.active, playbackError: shortcuts.playback.error
  } };
}
function emit() {
  if (window && !window.isDestroyed()) window.webContents.send('abts:state', runtimeState());
}
function checkBv(value) { if (!BV.test(value || '')) throw new Error('请输入有效的 BV 号或 B 站作品链接'); return value; }
function checkCid(bvid, cid) {
  checkBv(bvid);
  if (!store.state.books[bvid]?.chapters?.some(c => c.cid === Number(cid))) throw new Error('章节不存在，请重新打开作品');
  return Number(cid);
}
function createToken(value) {
  const key = crypto.randomBytes(24).toString('hex');
  tokens.set(key, value);
  if (tokens.size > 150) tokens.delete(tokens.keys().next().value);
  return `abts://audio/${key}`;
}
function toggleHidden() {
  if (!window || window.isDestroyed()) return;
  if (!hidden) {
    if (!shortcuts.hide.active) throw new Error('请先在设置中注册可用的全局快捷键');
    window.setSkipTaskbar(true);
    window.hide();
    hidden = true;
  } else {
    restoreToTaskbar(window);
    hidden = false;
  }
  record('toggle-hidden', windowSnapshot());
  emit();
}
function togglePlayback() {
  if (window && !window.isDestroyed()) window.webContents.send('abts:togglePlayback');
}
function setShortcut(accelerator, action = 'hide') {
  if (!Object.hasOwn(shortcuts, action)) throw new Error('无效的快捷键操作');
  const shortcut = shortcuts[action];
  if (typeof accelerator !== 'string' || accelerator.length > 80 ||
    !/^(?:(?:Control|Alt|Shift|Super)\+){1,3}(?:[A-Z0-9]|F(?:[1-9]|1[0-9]|2[0-4]))$/.test(accelerator)) {
    throw new Error('快捷键需包含 Ctrl、Alt 或 Shift 等修饰键和一个字母、数字或功能键');
  }
  if (accelerator === shortcut.active) return shortcut.active;
  if (Object.values(shortcuts).some(other => other !== shortcut && other.active === accelerator)) {
    throw new Error('隐藏与播放快捷键不能相同');
  }
  let registered = false;
  try { registered = globalShortcut.register(accelerator, shortcut.callback); } catch {}
  if (!registered) throw new Error('这个快捷键已被其它软件占用，请换一个组合');
  if (shortcut.active) globalShortcut.unregister(shortcut.active);
  shortcut.active = accelerator; shortcut.error = '';
  store.state.settings[shortcut.setting] = accelerator;
  store.save(); emit();
  return accelerator;
}
function register(name, handler) {
  ipcMain.handle(`abts:${name}`, async (event, ...args) => {
    if (event.sender !== window?.webContents || event.senderFrame !== window.webContents.mainFrame) throw new Error('无效请求来源');
    const started = Date.now();
    try { return await handler(...args); }
    catch (e) {
      record('ipc-error', { action: name, error: e });
      throw new Error(e.message || '操作失败，请重试');
    } finally {
      if (Date.now() - started > 5000) record('slow-ipc', { action: name, elapsedMs: Date.now() - started });
    }
  });
}
function setupHandlers() {
  register('state', () => runtimeState());
  register('shortcut', (accelerator, action) => setShortcut(accelerator, action));
  register('toggleHidden', () => toggleHidden());
  register('diagnostic', (kind, detail) => {
    if (!['renderer-error','renderer-rejection','renderer-heartbeat','renderer-input','renderer-visibility'].includes(kind)) return;
    if (JSON.stringify(detail)?.length > 4000) return;
    if (kind === 'renderer-heartbeat') {
      if (Date.now() - lastHeartbeat < 12000) return;
      lastHeartbeat = Date.now();
    }
    record(kind, { renderer: detail, window: windowSnapshot() });
  });
  register('openLogs', () => shell.openPath(path.dirname(diagnostics.file)));
  register('playing', playing => {
    if (playing && playbackBlocker == null) playbackBlocker = powerSaveBlocker.start('prevent-app-suspension');
    if (!playing && playbackBlocker != null) { powerSaveBlocker.stop(playbackBlocker); playbackBlocker = null; }
  });
  register('search', async (keyword, page = 1, type = 'video', order = '') => {
    keyword = String(keyword || '').trim().slice(0, 120);
    if (!keyword) return { items: [], hasMore: false };
    if (!['video', 'user'].includes(type) || !Number.isInteger(page) || page < 1 || page > 500) throw new Error('无效的搜索参数');
    if (page === 1) {
      store.state.searchHistory = [keyword, ...store.state.searchHistory.filter(k => k !== keyword)].slice(0, 12);
      store.save(); emit();
    }
    return api.search(keyword, page, type, ['click', 'pubdate'].includes(order) ? order : '');
  });
  register('detail', async bvid => {
    checkBv(bvid);
    try {
      const book = await api.detail(bvid);
      store.remember(book); store.save(); emit(); return book;
    } catch (e) {
      const book = store.state.books[bvid];
      if (book?.chapters?.length) return book;
      throw e;
    }
  });
  register('userBooks', (user, page) => {
    if (!Number.isSafeInteger(user?.mid) || user.mid <= 0) throw new Error('无效 UP 主');
    return api.userBooks({ mid: user.mid, name: String(user.name).slice(0, 100) }, Math.max(1, Math.min(500, Number(page) || 1)));
  });
  register('favorite', (bvid, value) => {
    checkBv(bvid);
    if (!store.state.books[bvid]) throw new Error('请先打开作品');
    store.state.favorites = store.state.favorites.filter(id => id !== bvid);
    if (value) store.state.favorites.unshift(bvid);
    store.save(); emit(); return store.state;
  });
  register('follow', (user, value) => {
    if (!Number.isSafeInteger(user?.mid) || user.mid <= 0) throw new Error('无效 UP 主');
    store.state.follows = store.state.follows.filter(u => u.mid !== user.mid);
    if (value) store.state.follows.unshift({ mid: user.mid, name: String(user.name).slice(0, 100), face: String(user.face || '') });
    store.save(); emit(); return store.state;
  });
  register('settings', patch => {
    const s = store.state.settings;
    if (['light', 'dark', 'system'].includes(patch?.theme)) s.theme = patch.theme;
    if (Number.isFinite(patch?.rate)) s.rate = Math.min(3, Math.max(0.5, patch.rate));
    if (Number.isFinite(patch?.volume)) s.volume = Math.min(1, Math.max(0, patch.volume));
    if (typeof patch?.stopAfter === 'boolean') s.stopAfter = patch.stopAfter;
    store.save(); emit(); return s;
  });
  register('progress', (bvid, cid, position, duration) => {
    checkCid(bvid, cid);
    if (!Number.isFinite(position) || !Number.isFinite(duration)) return;
    store.progress(bvid, Number(cid), position, duration); emit();
  });
  register('resolve', async (bvid, cid, forceOnline = false) => {
    cid = checkCid(bvid, cid);
    const task = store.state.downloads.find(t => t.bvid === bvid && t.cid === cid && t.status === 'done');
    if (task && !forceOnline && fs.existsSync(store.cacheFile(task))) return { url: createToken({ file: store.cacheFile(task) }), offline: true };
    const urls = await api.audio(bvid, cid);
    return { url: createToken({ urls }), offline: false };
  });
  register('download', (bvid, cids) => {
    checkBv(bvid);
    if (!Array.isArray(cids) || !cids.length || cids.length > 1000) throw new Error('请选择 1 至 1000 集');
    for (const cid of cids) checkCid(bvid, cid);
    downloads.add(store.state.books[bvid], cids);
  });
  register('retry', id => downloads.retry(String(id)));
  register('removeDownload', id => downloads.remove(String(id)));
  register('qr', async () => {
    const qr = await api.qr();
    const QRCode = require('qrcode');
    return { key: qr.qrcode_key, image: await QRCode.toDataURL(qr.url, { width: 240, margin: 2, errorCorrectionLevel: 'M' }) };
  });
  register('poll', key => {
    if (typeof key !== 'string' || key.length > 150) throw new Error('二维码无效');
    return api.poll(key);
  });
  register('user', () => api.user());
  register('logout', () => api.logout());
  register('external', url => {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' || !['github.com', 'bilibili.com'].some(d => parsed.hostname === d || parsed.hostname.endsWith('.' + d))) throw new Error('链接不受支持');
    return shell.openExternal(parsed.href);
  });
  register('openData', () => shell.openPath(store.dir));
  register('export', async () => {
    const result = await dialog.showSaveDialog(window, { defaultPath: 'ABTS-library-backup.json', filters: [{ name: 'JSON', extensions: ['json'] }] });
    if (result.canceled) return false;
    const { books, favorites, history, follows, settings, searchHistory, current } = store.state;
    fs.writeFileSync(result.filePath, JSON.stringify({ version: 1, books, favorites, history, follows, settings, searchHistory, current }, null, 2));
    return true;
  });
  register('import', async () => {
    const result = await dialog.showOpenDialog(window, { properties: ['openFile'], filters: [{ name: 'JSON', extensions: ['json'] }] });
    if (result.canceled) return false;
    if (fs.statSync(result.filePaths[0]).size > 30 * 1024 * 1024) throw new Error('备份文件过大');
    const backup = JSON.parse(fs.readFileSync(result.filePaths[0], 'utf8'));
    if (backup.version !== 1 || !backup.books || !Array.isArray(backup.favorites) || typeof backup.history !== 'object') throw new Error('不是有效的桌面版书架备份');
    for (const [bvid, book] of Object.entries(backup.books)) {
      checkBv(bvid);
      if (book.bvid !== bvid || typeof book.title !== 'string' || !Array.isArray(book.chapters)
        || book.chapters.some(c => !Number.isSafeInteger(c.cid) || c.cid <= 0 || typeof c.title !== 'string')) throw new Error('备份中的作品数据无效');
      store.remember(book);
    }
    store.state.favorites = [...new Set([...store.state.favorites, ...backup.favorites.filter(id => BV.test(id) && store.state.books[id])])];
    for (const [bvid, value] of Object.entries(backup.history)) {
      if (BV.test(bvid) && value && typeof value === 'object' && value.chapters && typeof value.chapters === 'object'
        && Number(value.updated) > Number(store.state.history[bvid]?.updated || 0)) store.state.history[bvid] = value;
    }
    store.save(); emit(); return true;
  });
}
async function audioResponse(request) {
  const token = tokens.get(new URL(request.url).pathname.slice(1));
  if (!token) return new Response('Expired', { status: 404 });
  if (token.file) {
    const size = fs.statSync(token.file).size;
    const range = request.headers.get('range');
    const match = range?.match(/^bytes=(\d*)-(\d*)$/);
    if (range && !match) return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${size}` } });
    const suffix = match && !match[1] && match[2];
    const start = suffix ? Math.max(0, size - Number(match[2])) : Number(match?.[1] || 0);
    const end = suffix ? size - 1 : match?.[2] ? Math.min(size - 1, Number(match[2])) : size - 1;
    if (start >= size || start > end) return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${size}` } });
    const headers = { 'Content-Type': 'audio/mp4', 'Accept-Ranges': 'bytes', 'Content-Length': String(end - start + 1) };
    if (range) headers['Content-Range'] = `bytes ${start}-${end}/${size}`;
    const body = Readable.toWeb(fs.createReadStream(token.file, { start, end }));
    return new Response(body, { status: range ? 206 : 200, headers });
  }
  for (const url of token.urls) {
    try {
      const response = await fetchMedia(api, url, { range: request.headers.get('range'), signal: request.signal });
      if (!response.ok) { await response.body?.cancel(); continue; }
      const headers = new Headers();
      for (const key of ['content-type', 'content-length', 'content-range', 'accept-ranges']) {
        if (response.headers.has(key)) headers.set(key, response.headers.get(key));
      }
      return new Response(response.body, { status: response.status, headers });
    } catch {}
  }
  return new Response('Audio unavailable', { status: 502 });
}
app.on('second-instance', () => {
  if (window) {
    if (hidden) { restoreToTaskbar(window); hidden = false; emit(); }
    else if (!window.isMinimized()) { window.show(); window.focus(); }
  }
});
if (gotLock) app.whenReady().then(async () => {
  diagnostics = createDiagnostics(path.join(app.getPath('userData'), 'logs'));
  record('startup', { version: app.getVersion(), electron: process.versions.electron, platform: process.platform });
  store = new Store(app.getPath('userData'));
  const cookieFile = path.join(store.dir, 'session.dat');
  api = new Bili({
    loadCookies: () => {
      try { return JSON.parse(safeStorage.decryptString(fs.readFileSync(cookieFile))); } catch { return {}; }
    },
    saveCookies: cookies => {
      if (safeStorage.isEncryptionAvailable()) {
        const tmp = `${cookieFile}.tmp`;
        fs.writeFileSync(tmp, safeStorage.encryptString(JSON.stringify(cookies)));
        fs.renameSync(tmp, cookieFile);
      }
    }
  });
  if (testMode) api = require('../tests/fixture.cjs').createApi();
  downloads = new Downloads(store, api, emit);
  for (const [action, shortcut] of Object.entries(shortcuts)) {
    try { setShortcut(store.state.settings[shortcut.setting], action); }
    catch (error) { shortcut.error = error.message; }
  }
  protocol.handle('abts', request => audioResponse(request).catch(() => new Response('Unavailable', { status: 500 })));
  setupHandlers();
  Menu.setApplicationMenu(Menu.buildFromTemplate([{
    label: '阿B听书', submenu: [
      { label: '缩小', role: 'zoomOut' }, { label: '放大', role: 'zoomIn' }, { label: '重置缩放', role: 'resetZoom' },
      { type: 'separator' }, { label: '退出', role: 'quit' }
    ]
  }, { label: '编辑', submenu: [{ role: 'undo' }, { role: 'redo' }, { type: 'separator' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] },
  { label: '诊断', submenu: [
    { label: '记录当前状态', click: () => { record('manual-snapshot', windowSnapshot()); } },
    { label: '打开日志目录', click: () => { void shell.openPath(path.dirname(diagnostics.file)); } }
  ] }]));
  window = new BrowserWindow({
    width: 1360, height: 900, minWidth: 860, minHeight: 620,
    backgroundColor: '#f7f8fa', title: '阿B听书 · 桌面版', icon: path.join(__dirname, '../assets/logo.png'),
    autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true, backgroundThrottling: false }
  });
  installWindowRecovery(window, { isHidden: () => hidden, record: event => record(event, windowSnapshot()) });
  for (const event of ['show','hide','restore','minimize','focus','blur','unresponsive','responsive']) {
    window.on(event, () => record('window-' + event, windowSnapshot()));
  }
  window.webContents.on('render-process-gone', (_, details) => record('renderer-gone', details));
  window.webContents.on('preload-error', (_, __, error) => record('preload-error', error));
  window.webContents.on('console-message', (_, details) => {
    if (details.level === 'error') record('renderer-console-error', { message: details.message });
  });
  const heartbeatWatch = setInterval(() => {
    if (lastHeartbeat && Date.now() - lastHeartbeat > 45000) {
      record('renderer-heartbeat-late', { elapsedMs: Date.now() - lastHeartbeat, window: windowSnapshot() });
    }
  }, 30000);
  heartbeatWatch.unref();
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', event => event.preventDefault());
  await window.loadFile(path.join(__dirname, '../dist/index.html'));
  window.on('close', event => {
    if (!quitting) {
      event.preventDefault(); quitting = true;
      window.webContents.send('abts:flush');
      setTimeout(() => window.destroy(), 250);
    }
  });
  downloads.run();
}).catch(e => { record('startup-error', e); dialog.showErrorBox('阿B听书启动失败', e.message); app.quit(); });
app.on('before-quit', () => { downloads?.stop(); globalShortcut.unregisterAll(); });
app.on('window-all-closed', () => { downloads?.stop(); app.quit(); });
