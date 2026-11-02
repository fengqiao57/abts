const { contextBridge, ipcRenderer } = require('electron');
const actions = ['state','search','detail','userBooks','favorite','follow','settings','progress',
  'resolve','download','retry','removeDownload','qr','poll','user','logout','external','openData','export','import','shortcut','toggleHidden','playing','openLogs'];
const api = Object.fromEntries(actions.map(name => [name, (...args) => ipcRenderer.invoke(`abts:${name}`, ...args)]));
api.subscribe = callback => {
  const handler = (_, data) => callback(data);
  ipcRenderer.on('abts:state', handler);
  return () => ipcRenderer.removeListener('abts:state', handler);
};
api.onFlush = callback => {
  ipcRenderer.on('abts:flush', callback);
  return () => ipcRenderer.removeListener('abts:flush', callback);
};
api.onTogglePlayback = callback => {
  const handler = () => callback();
  ipcRenderer.on('abts:togglePlayback', handler);
  return () => ipcRenderer.removeListener('abts:togglePlayback', handler);
};
api.reportError = (kind, detail) => {
  if (['renderer-error','renderer-rejection'].includes(kind)) {
    return ipcRenderer.invoke('abts:diagnostic', kind, detail).catch(() => {});
  }
};
contextBridge.exposeInMainWorld('abts', Object.freeze(api));
const report = (kind, detail) => ipcRenderer.invoke('abts:diagnostic', kind, detail).catch(() => {});
window.addEventListener('error', e => report('renderer-error', { message: String(e.message).slice(0, 2000),
  line: e.lineno, column: e.colno }));
window.addEventListener('unhandledrejection', e => report('renderer-rejection', {
  message: String(e.reason?.message || e.reason).slice(0, 2000) }));
window.addEventListener('DOMContentLoaded', () => {
  let clicks = 0, lastInput = 0, lastReport = 0;
  const snapshot = () => ({ visibility: document.visibilityState, focused: document.hasFocus(), clicks,
    lastInput, overlay: !!document.querySelector('.modal-backdrop'), activeTag: document.activeElement?.tagName });
  document.addEventListener('pointerdown', e => {
    clicks++; lastInput = Date.now();
    if (lastInput - lastReport < 1500) return;
    lastReport = lastInput;
    report('renderer-input', { ...snapshot(), tag: e.target?.tagName, button: e.button });
  }, true);
  document.addEventListener('visibilitychange', () => report('renderer-visibility', snapshot()));
  setInterval(() => report('renderer-heartbeat', snapshot()), 15000);
  report('renderer-visibility', snapshot());
});
