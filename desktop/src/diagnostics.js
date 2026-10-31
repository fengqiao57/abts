window.addEventListener('error', event => {
  window.abts.reportError('renderer-error', {
    message: String(event.message).slice(0, 1200),
    stack: String(event.error?.stack || '').slice(0, 2000),
    line: event.lineno, column: event.colno
  });
});
window.addEventListener('unhandledrejection', event => {
  window.abts.reportError('renderer-rejection', {
    message: String(event.reason?.message || event.reason).slice(0, 1200),
    stack: String(event.reason?.stack || '').slice(0, 2000)
  });
});
