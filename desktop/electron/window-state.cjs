let showWindow;
const pendingRestore = new WeakSet();

function installWindowRecovery(window, { isHidden, record = () => {} }) {
  const synchronize = () => {
    if (!pendingRestore.has(window) || isHidden() || window.isMinimized()) return;
    pendingRestore.delete(window);
    // The native taskbar restore does not run Chromium's Widget::Show lifecycle.
    // Synchronize it only after the user has restored the window, without activation.
    window.showInactive();
    if (window.isFocused()) window.webContents.focus();
    record('window-input-synchronized');
  };
  window.on('restore', synchronize);
  window.on('focus', synchronize);
}

function restoreToTaskbar(window) {
  if (process.platform === 'win32') {
    if (!showWindow) {
      showWindow = require('koffi').load('user32.dll')
        .func('bool __stdcall ShowWindow(void *hWnd, int nCmdShow)');
    }
    const handle = window.getNativeWindowHandle();
    const hwnd = handle.length === 8 ? handle.readBigUInt64LE() : handle.readUInt32LE();
    pendingRestore.add(window);
    // SW_SHOWMINNOACTIVE restores a taskbar entry without exposing or activating the window.
    showWindow(hwnd, 7);
  } else {
    window.minimize();
  }
  window.setSkipTaskbar(false);
}

module.exports = { restoreToTaskbar, installWindowRecovery };
