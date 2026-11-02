const fs = require('node:fs');
const path = require('node:path');
const { Readable, Transform } = require('node:stream');
const { pipeline } = require('node:stream/promises');
const { BV, mediaAllowed } = require('./core.cjs');
async function fetchMedia(api, url, { signal, range } = {}) {
  for (let redirect = 0; redirect < 5; redirect++) {
    if (!mediaAllowed(url)) throw new Error('音频地址不受支持');
    const response = await api.fetch(url, {
      headers: { 'User-Agent': api.headers()['User-Agent'], Referer: 'https://www.bilibili.com/',
        ...(range ? { Range: range } : {}) },
      redirect: 'manual', signal: signal || AbortSignal.timeout(30000)
    });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const next = new URL(response.headers.get('location'), url).href;
      await response.body?.cancel();
      url = next;
      continue;
    }
    return response;
  }
  throw new Error('音频地址重定向过多');
}
class Downloads {
  constructor(store, api, emit = () => {}) {
    this.store = store; this.api = api; this.emit = emit;
    this.running = false; this.stopping = false; this.controller = null;
    fs.mkdirSync(path.join(store.dir, 'audio'), { recursive: true });
  }
  add(book, cids) {
    this.store.remember(book);
    const chapters = book.chapters?.filter(c => cids.includes(c.cid)) || [];
    if (!chapters.length) throw new Error('请先选择章节');
    for (const chapter of chapters) {
      const id = `${book.bvid}-${chapter.cid}`;
      const task = this.store.state.downloads.find(t => t.id === id);
      if (task) { if (task.status === 'failed') { task.status = 'queued'; task.error = ''; } continue; }
      this.store.state.downloads.push({ id, bvid: book.bvid, cid: chapter.cid,
        title: chapter.title, index: chapter.index, status: 'queued', received: 0, total: 0, error: '' });
    }
    this.store.save(); this.emit(); void this.run();
  }
  async run() {
    if (this.running || this.stopping) return;
    this.running = true;
    try {
      let task;
      while (!this.stopping && (task = this.store.state.downloads.find(t => t.status === 'queued'))) {
        this.active = task;
        task.status = 'downloading'; task.error = '';
        this.controller = new AbortController();
        this.store.save(); this.emit();
        try {
          const urls = await this.api.audio(task.bvid, task.cid);
          if (this.controller.signal.aborted) throw new Error('缓存已暂停');
          const file = this.store.cacheFile(task), partial = `${file}.part`;
          let received = fs.existsSync(partial) ? fs.statSync(partial).size : 0;
          let response = await fetchMedia(this.api, urls[0], {
            signal: AbortSignal.any([this.controller.signal, AbortSignal.timeout(20 * 60 * 1000)]),
            range: received ? `bytes=${received}-` : undefined
          });
          if (response.status === 416 && received) {
            await response.body?.cancel();
            received = 0;
            response = await fetchMedia(this.api, urls[0], { signal: this.controller.signal });
          }
          if (!response.ok || !response.body) throw new Error(`下载失败 HTTP ${response.status}`);
          if (response.status === 206 && received) {
            const start = Number(response.headers.get('content-range')?.match(/^bytes (\d+)-/)?.[1]);
            if (start !== received) throw new Error('续传位置不匹配，请移除后重新缓存');
          } else received = 0;
          task.received = received;
          task.total = received + Number(response.headers.get('content-length') || 0);
          if (fs.statfsSync) {
            const stat = fs.statfsSync(path.dirname(file));
            if (Number(stat.bavail) * Number(stat.bsize) < Math.max(task.total - received, 20 * 1024 * 1024)) {
              await response.body.cancel();
              throw new Error('磁盘空间不足');
            }
          }
          let last = 0;
          const meter = new Transform({ transform: (chunk, _, done) => {
            task.received += chunk.length;
            if (Date.now() - last > 400) { last = Date.now(); this.emit(); }
            done(null, chunk);
          } });
          await pipeline(Readable.fromWeb(response.body), meter,
            fs.createWriteStream(partial, { flags: received ? 'a' : 'w' }), { signal: this.controller.signal });
          if (!task.received || (task.total && task.received !== task.total)) throw new Error('文件未下载完整，请重试');
          fs.renameSync(partial, file);
          task.status = 'done'; task.total = task.received;
        } catch (error) {
          task.status = this.stopping ? 'queued' : 'failed';
          task.error = this.stopping ? '' : error.message;
        }
        this.active = null; this.controller = null;
        this.store.save(); this.emit();
      }
    } finally { this.running = false; }
  }
  retry(id) {
    const task = this.store.state.downloads.find(t => t.id === id);
    if (task && task.status === 'failed') {
      task.status = 'queued'; task.error = ''; this.store.save(); this.emit(); void this.run();
    }
  }
  async remove(id) {
    const task = this.store.state.downloads.find(t => t.id === id);
    if (!task) return;
    if (this.active === task) {
      this.controller?.abort();
      // Wait until the writer closes before removing a partial file on Windows.
      while (this.active === task) await new Promise(r => setTimeout(r, 30));
    }
    this.store.state.downloads = this.store.state.downloads.filter(t => t.id !== id);
    const file = this.store.cacheFile(task);
    for (const name of [file, `${file}.part`]) { try { fs.unlinkSync(name); } catch (e) { if (e.code !== 'ENOENT') throw e; } }
    this.store.save(); this.emit();
  }
  stop() { this.stopping = true; this.controller?.abort(); }
}
module.exports = { Downloads, fetchMedia };
