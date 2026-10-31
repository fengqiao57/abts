const crypto = require('node:crypto');
const { sign, bookFrom, isAudio, mediaAllowed } = require('./core.cjs');
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
class Bili {
  constructor({ loadCookies = () => ({}), saveCookies = () => {}, fetchImpl = fetch } = {}) {
    this.cookies = loadCookies();
    this.saveCookies = saveCookies;
    this.fetch = fetchImpl;
    this.keys = null;
    this.warming = null;
    this.lastRequest = 0;
    this.queue = Promise.resolve();
  }
  headers() {
    return { 'User-Agent': UA, Referer: 'https://www.bilibili.com/',
      Cookie: Object.entries(this.cookies).map(([k, v]) => `${k}=${v}`).join('; ') };
  }
  async raw(url) {
    const response = await this.fetch(url, { headers: this.headers(), signal: AbortSignal.timeout(22000) });
    for (const cookie of response.headers.getSetCookie()) {
      const first = cookie.split(';')[0], eq = first.indexOf('=');
      if (eq > 0) this.cookies[first.slice(0, eq)] = first.slice(eq + 1);
    }
    this.saveCookies(this.cookies);
    return response;
  }
  async warmup() {
    if (this.keys && this.keys.at > Date.now() - 6 * 3600000) return;
    if (this.warming) return this.warming;
    this.warming = (async () => {
      // Keep the normal web guest session returned by the platform.
      if (!this.cookies.buvid3) {
        try {
          const r = await this.raw('https://api.bilibili.com/x/frontend/finger/spi');
          const data = (await r.json()).data;
          if (data?.b_3) this.cookies.buvid3 = data.b_3;
          if (data?.b_4) this.cookies.buvid4 = data.b_4;
        } catch {}
      }
      const r = await this.raw('https://api.bilibili.com/x/web-interface/nav');
      const data = (await r.json()).data;
      if (!data?.wbi_img) throw new Error('无法连接哔哩哔哩，请检查网络后重试');
      this.keys = { img: data.wbi_img.img_url, sub: data.wbi_img.sub_url, at: Date.now() };
    })();
    try { await this.warming; } finally { this.warming = null; }
  }
  request(endpoint, params = {}, wbi = false, passport = false) {
    const job = async () => {
      const wait = 650 - (Date.now() - this.lastRequest);
      if (wait > 0) await pause(wait);
      if (wbi) await this.warmup();
      let lastError;
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          if (attempt) await pause(1800);
          this.lastRequest = Date.now();
          const query = wbi ? sign(params, this.keys.img, this.keys.sub) : params;
          const url = new URL(endpoint, passport ? 'https://passport.bilibili.com' : 'https://api.bilibili.com');
          url.search = new URLSearchParams(query).toString();
          const r = await this.raw(url);
          if (!r.ok) throw new Error([403, 412].includes(r.status) ? '平台暂时限制了请求，请稍后重试或扫码登录' : `网络错误 HTTP ${r.status}`);
          const body = await r.json();
          if (body.code !== 0 && !(endpoint.endsWith('/nav') && body.code === -101)) {
            throw new Error([-412, -352, -509].includes(body.code) ? '平台暂时限制了请求，请稍后重试或扫码登录' : `哔哩哔哩：${body.message || body.msg || body.code}`);
          }
          if (body.data?.v_voucher) throw new Error('平台要求验证，请稍后重试或扫码登录');
          return body.data;
        } catch (e) { lastError = e; }
      }
      throw lastError;
    };
    const result = this.queue.then(job, job);
    this.queue = result.catch(() => {});
    return result;
  }
  async search(keyword, page = 1, type = 'video', order = '') {
    const raw = await this.request('/x/web-interface/wbi/search/type', {
      search_type: type === 'user' ? 'bili_user' : 'video', keyword, page,
      page_size: 20, platform: 'pc', web_location: 1430654, ...(order ? { order } : {})
    }, true);
    const list = raw?.result || [];
    if (type === 'user') return { items: list.map(u => ({
      mid: Number(u.mid), name: u.uname, face: u.upic?.replace(/^\/\//, 'https://'), fans: u.fans, sign: u.usign
    })), hasMore: page * 20 < Number(raw.numResults || 0) };
    return { items: list.filter(i => isAudio(i, keyword)).map(i => bookFrom(i)),
      hasMore: page * Number(raw.pagesize || 20) < Number(raw.numResults || 0), rawCount: list.length };
  }
  async detail(bvid) {
    const data = await this.request('/x/web-interface/view', { bvid });
    if (!data?.pages?.length) throw new Error('作品不存在、已删除或暂时无法访问');
    return bookFrom(data, true);
  }
  async audio(bvid, cid) {
    const data = await this.request('/x/player/wbi/playurl', {
      bvid, cid, qn: 80, fnval: 4048, fnver: 0, fourk: 1, try_look: 1
    }, true);
    const tracks = (data?.dash?.audio || []).sort((a, b) => (a.bandwidth || 0) - (b.bandwidth || 0));
    const urls = tracks.flatMap(t => [t.baseUrl || t.base_url, ...(t.backupUrl || t.backup_url || [])]).filter(mediaAllowed);
    if (!urls.length) throw new Error('此作品没有可用的公开音频轨道，请尝试其它作品或登录');
    return [...new Set(urls)];
  }
  async userBooks(user, page = 1) {
    try {
      const data = await this.request('/x/space/wbi/arc/search', { mid: user.mid, pn: page, ps: 30, order: 'pubdate' }, true);
      const list = data?.list?.vlist || [];
      if (list.length) return { items: list.map(i => bookFrom({ ...i, author: user.name, mid: user.mid })), hasMore: page * 30 < Number(data.page?.count || 0) };
    } catch {}
    const result = await this.request('/x/web-interface/wbi/search/type', { search_type: 'video', keyword: user.name, page, page_size: 50 }, true);
    return { items: (result?.result || []).filter(i => Number(i.mid) === Number(user.mid)).map(i => bookFrom(i)), hasMore: page * 50 < Number(result?.numResults || 0) };
  }
  async qr() {
    return this.request('/x/passport-login/web/qrcode/generate', { source: 'main-fe-header' }, false, true);
  }
  async poll(key) {
    const result = await this.request('/x/passport-login/web/qrcode/poll', { qrcode_key: key, source: 'main-fe-header' }, false, true);
    if (result.code === 0 && result.url) {
      const url = new URL(result.url);
      for (const name of ['SESSDATA', 'bili_jct', 'DedeUserID', 'DedeUserID__ckMd5']) {
        const value = url.searchParams.get(name);
        if (value) this.cookies[name] = encodeURIComponent(value);
      }
      this.saveCookies(this.cookies);
    }
    return result.code;
  }
  async user() {
    const data = await this.request('/x/web-interface/nav');
    return { loggedIn: !!data?.isLogin, name: data?.uname || '', face: data?.face || '' };
  }
  logout() { this.cookies = {}; this.keys = null; this.saveCookies({}); }
}
module.exports = { Bili, UA };
