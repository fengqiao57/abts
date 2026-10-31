const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { sign, Store, mediaAllowed, isAudio } = require('../electron/core.cjs');
const { Downloads, fetchMedia } = require('../electron/downloads.cjs');
const { books, createApi, wave } = require('./fixture.cjs');
const { createDiagnostics } = require('../electron/diagnostics.cjs');
const temp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'abts-test-'));
test('WBI signature matches the fixed sample key and timestamp', () => {
  const result = sign({ foo: '114', bar: '514', baz: 1919810 },
    'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
    'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png', 1702204169);
  // Mixin for these image keys: ea1db124af3c7062474693fa704f4ff8.
  assert.equal(result.w_rid, '6149fdadf571698ca7e6a567265cd0ee');
});
test('listening progress survives restart without deleting completed chapters', () => {
  const dir = temp(), store = new Store(dir), book = books[0];
  store.remember(book);
  store.state.favorites.push(book.bvid);
  store.progress(book.bvid, 1001, 180, 180);
  store.progress(book.bvid, 1002, 42, 180);
  const restored = new Store(dir);
  assert.equal(restored.state.history[book.bvid].chapters[1001].position, 180);
  assert.equal(restored.state.history[book.bvid].chapters[1002].position, 42);
  assert.equal(restored.state.current.cid, 1002);
  assert.deepEqual(restored.state.favorites, [book.bvid]);
});
test('a corrupt library recovers the previous atomic backup', () => {
  const dir = temp(), store = new Store(dir);
  store.remember(books[0]); store.save(); store.save();
  fs.writeFileSync(store.file, '{bad json');
  assert.equal(new Store(dir).state.books[books[0].bvid].title, books[0].title);
});
test('existing settings and recovered backups inherit the new playback shortcut', () => {
  const dir = temp(), file = path.join(dir, 'library.json');
  const legacy = { settings: { hideShortcut: 'Control+Alt+J', rate: 1.5 } };
  fs.writeFileSync(file, JSON.stringify(legacy));
  const restored = new Store(dir);
  assert.equal(restored.state.settings.hideShortcut, 'Control+Alt+J');
  assert.equal(restored.state.settings.playbackShortcut, 'Control+Alt+P');
  fs.writeFileSync(file + '.backup', JSON.stringify(legacy));
  fs.writeFileSync(file, '{bad json');
  const backup = new Store(dir);
  assert.equal(backup.state.settings.hideShortcut, 'Control+Alt+J');
  assert.equal(backup.state.settings.playbackShortcut, 'Control+Alt+P');
});
test('audiobook filter rejects unrelated commentary and short clips', () => {
  assert.equal(isAudio({ title: '三体有声小说', duration: '1:20:00' }, '三体'), true);
  assert.equal(isAudio({ title: '三体有声小说解说', duration: '1:20:00' }, '三体'), false);
  assert.equal(isAudio({ title: '有声小说片段', duration: '1:00' }, '三体'), false);
});
test('media proxy rejects local addresses, credentials and deceptive suffixes', () => {
  for (const url of ['http://127.0.0.1/test', 'file:///C:/secret', 'https://bilivideo.com.evil.example/test', 'https://foo.bilivideo.com:8443/test', 'https://x:y@foo.bilivideo.com/test']) {
    assert.equal(mediaAllowed(url), false, url);
  }
  assert.equal(mediaAllowed('https://upos-sz-mirrorbd.bilivideo.com/audio'), true);
});
test('media redirects are validated before following', async () => {
  let calls = 0;
  const api = { headers: () => ({}), fetch: async () => { calls++; return new Response(null, { status: 302, headers: { location: 'http://127.0.0.1/private' } }); } };
  await assert.rejects(fetchMedia(api, 'https://test.bilivideo.com/audio'), /不受支持/);
  assert.equal(calls, 1);
});
test('interrupted downloads resume exact bytes and reconcile missing files', async () => {
  const dir = temp(), store = new Store(dir), api = createApi(), book = books[0];
  store.remember(book);
  const task = { id: `${book.bvid}-1001`, bvid: book.bvid, cid: 1001, title: 'part1', index: 0, status: 'queued' };
  store.state.downloads.push(task);
  fs.mkdirSync(path.join(dir, 'audio'));
  fs.writeFileSync(`${store.cacheFile(task)}.part`, wave().subarray(0, 1071));
  const downloads = new Downloads(store, api);
  await downloads.run();
  assert.equal(task.status, 'done', task.error);
  assert.deepEqual(fs.readFileSync(store.cacheFile(task)), wave());
  assert.equal(fs.existsSync(`${store.cacheFile(task)}.part`), false);
  store.save();
  fs.unlinkSync(store.cacheFile(task));
  assert.equal(new Store(dir).state.downloads[0].status, 'failed');
});
test('diagnostics redact credentials, preserve errors, and rotate bounded logs', async () => {
  const log = createDiagnostics(temp(), { maxBytes: 1500 });
  log.log('failure', { error: new Error('request https://api.bilibili.com/x?token=private'),
    Cookie: 'sensitive', nested: { SESSDATA: 'hidden' } });
  await log.flush();
  const line = fs.readFileSync(log.file, 'utf8');
  assert.equal(line.includes('private'), false);
  assert.equal(line.includes('sensitive'), false);
  assert.equal(line.includes('hidden'), false);
  assert.match(JSON.parse(line).detail.error.message, /request https:\/\/api.bilibili.com\/x$/);
  for (let n = 0; n < 30; n++) log.log('window', { n, visible: true, minimized: false });
  await log.flush();
  assert.ok(fs.statSync(log.file).size <= 1500);
  assert.ok(fs.statSync(log.file + '.previous').size <= 1500);
  const records = fs.readFileSync(log.file, 'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(records.at(-1).detail.n, 29);
});
