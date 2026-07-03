const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('tt', {
  getSettings: () => ipcRenderer.invoke('settings:get'),
  saveSettings: (settings) => ipcRenderer.invoke('settings:save', settings),
  translate: (text, settings) => ipcRenderer.invoke('translate', { text, settings }),
  readClipboard: () => ipcRenderer.invoke('clipboard:read'),
  writeClipboard: (text) => ipcRenderer.invoke('clipboard:write', text),
  pasteText: (text) => ipcRenderer.invoke('paste:text', text),
  setAlwaysOnTop: (enabled) => ipcRenderer.invoke('window:always-on-top', enabled),
  startWindowDrag: () => ipcRenderer.send('window:drag-start'),
  moveWindowDrag: () => ipcRenderer.send('window:drag-move'),
  endWindowDrag: () => ipcRenderer.send('window:drag-end'),
  onClipboardChanged: (callback) => {
    ipcRenderer.on('clipboard-changed', (_event, text) => callback(text));
  },
  onSettingsUpdated: (callback) => {
    ipcRenderer.on('settings-updated', (_event, settings) => callback(settings));
  },
  onTranslateClipboardShortcut: (callback) => {
    ipcRenderer.on('shortcut-translate-clipboard', callback);
  },
  onPasteResultShortcut: (callback) => {
    ipcRenderer.on('shortcut-paste-result', callback);
  }
});
