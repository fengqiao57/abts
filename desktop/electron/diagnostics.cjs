const fs = require('node:fs/promises');
const path = require('node:path');

function redact(value) {
  return String(value).replace(/https?:\/\/[^\s"'<>]+/g, url => url.split('?')[0])
    .replace(/\b(SESSDATA|bili_jct|Cookie|Authorization|qrcode_key)\s*[:=]\s*[^\s,;]+/gi, '$1=[redacted]');
}
function sanitize(value, depth = 0) {
  if (depth > 8) return '[truncated]';
  if (value instanceof Error) return sanitize({ name: value.name, message: value.message, stack: value.stack }, depth + 1);
  if (typeof value === 'string') return redact(value);
  if (Array.isArray(value)) return value.slice(0, 50).map(item => sanitize(item, depth + 1));
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).slice(0, 50).map(([key, item]) =>
    [key, /cookie|authorization|sessdata|bili_jct|qrcode_key|password/i.test(key) ? '[redacted]' : sanitize(item, depth + 1)]));
  return value;
}

function createDiagnostics(dir, { maxBytes = 1024 * 1024 } = {}) {
  const file = path.join(dir, 'diagnostics.jsonl');
  let size = 0;
  let queue = fs.mkdir(dir, { recursive: true }).then(async () => {
    try { size = (await fs.stat(file)).size; } catch {}
  });
  let dropped = 0;
  const log = (event, detail = {}) => {
    if (dropped > 200) return;
    let line;
    try {
      line = JSON.stringify({ time: new Date().toISOString(), event, detail: sanitize(detail) }) + '\n';
    } catch { return; }
    if (line.length > 16000) line = JSON.stringify({ time: new Date().toISOString(), event, truncated: true }) + '\n';
    const bytes = Buffer.byteLength(line);
    dropped++;
    queue = queue.then(async () => {
      if (size + bytes > maxBytes) {
        await fs.rm(file + '.previous', { force: true });
        try { await fs.rename(file, file + '.previous'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
        size = 0;
      }
      await fs.appendFile(file, line, 'utf8');
      size += bytes;
    }).catch(() => {}).finally(() => { dropped--; });
  };
  return { log, flush: () => queue, file };
}
module.exports = { createDiagnostics };
