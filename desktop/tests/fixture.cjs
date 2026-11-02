const { UA } = require('../electron/bili.cjs');
const books = [
  { bvid: 'BV1234567890', title: '三体 · 地球往事 有声小说', author: '测试演播者', mid: 1234, duration: 540, play: 120000, pic: '', pages: 3, desc: '用于自动化验证的本地音频，不包含网络作品。' },
  { bvid: 'BV1234567891', title: '古典评书 · 测试作品', author: '评书演播者', mid: 1235, duration: 540, play: 85000, pic: '', pages: 3 },
  { bvid: 'BV1234567892', title: '世界名著 · 朗读测试', author: '朗读演播者', mid: 1236, duration: 540, play: 48000, pic: '', pages: 3 }
].map((b, index) => ({ ...b, chapters: [1,2,3].map(n => ({ cid: 1000 + index * 10 + n, title: `第 ${n} 集 · 本地测试音频`, duration: 180, index: n - 1 })) }));
function wave() {
  const size = 8000 * 2 * 180, buffer = Buffer.alloc(44 + size);
  buffer.write('RIFF'); buffer.writeUInt32LE(36 + size, 4); buffer.write('WAVEfmt ', 8);
  buffer.writeUInt32LE(16,16); buffer.writeUInt16LE(1,20); buffer.writeUInt16LE(1,22);
  buffer.writeUInt32LE(8000,24); buffer.writeUInt32LE(16000,28); buffer.writeUInt16LE(2,32); buffer.writeUInt16LE(16,34);
  buffer.write('data',36); buffer.writeUInt32LE(size,40);
  return buffer;
}
function createApi() {
  const content = wave();
  let offline = process.argv.includes('--offline');
  return {
    headers: () => ({ 'User-Agent': UA }),
    search: async (query, page, type) => {
      if (offline) throw new Error('测试：网络不可用');
      if (type === 'user') return { items: [{ mid: 1234, name: '测试演播者', face: '' }], hasMore: false };
      return { items: books, hasMore: false };
    },
    detail: async id => {
      if (offline) throw new Error('测试：网络不可用');
      return books.find(b => b.bvid === id);
    },
    audio: async (bvid, cid) => {
      if (offline) throw new Error('测试：网络不可用');
      return [`https://test.bilivideo.com/${bvid}/${cid}`];
    },
    userBooks: async () => ({ items: books, hasMore: false }),
    qr: async () => ({ qrcode_key: 'test', url: 'https://www.bilibili.com' }),
    poll: async () => 86101,
    user: async () => ({ loggedIn: false, name: '', face: '' }),
    logout: () => {},
    fetch: async (_url, options) => {
      const range = options.headers.Range?.match(/^bytes=(\d+)-(\d*)$/);
      const start = Number(range?.[1] || 0), end = range?.[2] ? Number(range[2]) : content.length - 1;
      const headers = { 'Content-Type': 'audio/wav', 'Content-Length': String(end - start + 1), 'Accept-Ranges': 'bytes' };
      if (range) headers['Content-Range'] = `bytes ${start}-${end}/${content.length}`;
      return new Response(content.subarray(start, end + 1), { status: range ? 206 : 200, headers });
    }
  };
}
module.exports = { createApi, books, wave };
