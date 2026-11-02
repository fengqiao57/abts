const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const BV = /^BV[0-9A-Za-z]{10}$/;
const table = [46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,19,29,28,14,39,12,38,41,13,37,48,7,16,24,55,40,61,26,17,0,1,60,51,30,4,22,25,54,21,56,59,6,63,57,62,11,36,20,34,44,52];
const encode = value => encodeURIComponent(String(value)).replace(/[!'()*]/g, c => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
function sign(params, img, sub, now = Math.floor(Date.now() / 1000)) {
  const extract = s => s.split('/').pop().split('.')[0];
  const original = extract(img) + extract(sub);
  if (original.length < 64) throw new Error('接口签名初始化失败，请重试');
  const mix = table.slice(0, 32).map(i => original[i]).join('');
  const values = { ...params, wts: now };
  const query = Object.keys(values).sort().filter(k => values[k] != null)
    .map(k => `${encode(k)}=${encode(String(values[k]).replace(/[!'()*]/g, ''))}`).join('&');
  return { ...values, w_rid: crypto.createHash('md5').update(query + mix).digest('hex') };
}
function parseDuration(value) {
  if (typeof value === 'number') return value;
  return String(value || '0').split(':').reduce((a, b) => a * 60 + (Number(b) || 0), 0);
}
function clean(value) {
  return String(value || '').replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>');
}
function imageUrl(value) {
  const url = String(value || '').replace(/^\/\//, 'https://').replace(/^http:/, 'https:');
  try { return new URL(url).hostname.endsWith('.hdslb.com') ? url : ''; } catch { return ''; }
}
function bookFrom(item, detail = false) {
  return {
    bvid: item.bvid, title: clean(item.title), pic: imageUrl(item.pic),
    author: clean(item.owner?.name || item.author || ''), mid: Number(item.owner?.mid || item.mid || 0),
    duration: parseDuration(item.duration), pages: Array.isArray(item.pages) ? item.pages.length : Number(item.videos || 1),
    play: Number(item.stat?.view || item.play || 0), desc: clean(item.desc || item.description),
    ...(detail ? { chapters: (item.pages || []).map((p, index) => ({
      cid: Number(p.cid), title: clean(p.part), duration: Number(p.duration || 0), index
    })) } : {})
  };
}
function isAudio(item, keyword) {
  const title = clean(item.title);
  const meta = `${item.description || ''} ${item.tag || ''}`;
  const audio = /有声|听书|评书|相声|广播剧|演播|朗读|诵读|长书|连播|说书|单口|播讲|多人剧|小说剧/;
  const noise = /一口气看完|漫推|漫画|解说|讲解|解读|动画|鬼畜|混剪|沙雕|速看|reaction|预告|游戏实况|配音秀/i;
  const seconds = parseDuration(item.duration);
  if (noise.test(title + meta)) return false;
  return (audio.test(title) && seconds >= 300) || (Number(item.typeid) === 195 && seconds >= 600)
    || (audio.test(meta) && seconds >= 1800) || (audio.test(keyword) && seconds >= 1800);
}
function defaultState() {
  return { version: 1, books: {}, favorites: [], history: {}, follows: [], downloads: [],
    searchHistory: [], settings: { theme: 'light', rate: 1, volume: 0.8, stopAfter: false,
      hideShortcut: 'Control+Alt+H', playbackShortcut: 'Control+Alt+P' }, current: null };
}
class Store {
  constructor(dir) {
    this.dir = dir;
    this.file = path.join(dir, 'library.json');
    fs.mkdirSync(dir, { recursive: true });
    this.state = defaultState();
    try {
      const raw = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      this.state = { ...this.state, ...raw, settings: { ...this.state.settings, ...raw.settings } };
    } catch (e) {
      if (e.code !== 'ENOENT') {
        const backup = `${this.file}.backup`;
        try {
          const raw = JSON.parse(fs.readFileSync(backup, 'utf8'));
          this.state = { ...this.state, ...raw, settings: { ...this.state.settings, ...raw.settings } };
        } catch {}
      }
    }
    for (const task of this.state.downloads) {
      if (task.status === 'downloading') task.status = 'queued';
      if (task.status === 'done' && !fs.existsSync(this.cacheFile(task))) {
        task.status = 'failed'; task.error = '缓存文件不存在，请重试';
      }
    }
  }
  cacheFile(task) {
    if (!BV.test(task.bvid) || !Number.isSafeInteger(Number(task.cid)) || Number(task.cid) <= 0) throw new Error('无效章节');
    return path.join(this.dir, 'audio', `${task.bvid}-${Number(task.cid)}.m4a`);
  }
  save() {
    const tmp = `${this.file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(this.state, null, 2));
    if (fs.existsSync(this.file)) fs.copyFileSync(this.file, `${this.file}.backup`);
    fs.renameSync(tmp, this.file);
  }
  remember(book) {
    if (!book || !BV.test(book.bvid)) throw new Error('无效的 BV 号');
    this.state.books[book.bvid] = { ...this.state.books[book.bvid], ...book };
  }
  progress(bvid, cid, position, duration) {
    const book = this.state.books[bvid];
    if (!book || !book.chapters?.some(c => c.cid === cid)) return;
    const history = this.state.history[bvid] || { chapters: {} };
    history.chapters[cid] = { position: Math.max(0, Number(position) || 0), duration: Math.max(0, Number(duration) || 0) };
    history.cid = cid; history.updated = Date.now();
    this.state.history[bvid] = history;
    this.state.current = { bvid, cid };
    this.save();
  }
}
function mediaAllowed(value) {
  try {
    const u = new URL(value);
    return u.protocol === 'https:' && !u.username && !u.password && (!u.port || u.port === '443')
      && ['bilivideo.com', 'bilivideo.cn', 'akamaized.net', 'bilibili.com'].some(d => u.hostname === d || u.hostname.endsWith('.' + d));
  } catch { return false; }
}
module.exports = { BV, Store, sign, parseDuration, clean, bookFrom, isAudio, mediaAllowed, defaultState };
