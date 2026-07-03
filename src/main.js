const { app, BrowserWindow, clipboard, globalShortcut, ipcMain, Menu, screen, shell } = require('electron');
const fs = require('fs/promises');
const path = require('path');
const { execFile } = require('child_process');

let mainWindow;
let settings = {};
let clipboardTimer = null;
let lastClipboardText = '';
let lastProgrammaticClipboardText = '';
let dragState = null;

const DEFAULT_SETTINGS = {
  baseUrl:
    process.env.TT_BASE_URL || 'http://192.168.52.22:9940/services/qwen36-35b-a3b-mtp-q6/v1',
  apiKey: process.env.TT_API_KEY || '',
  model: process.env.TT_MODEL || 'qwen36-35b-a3b-mtp',
  temperature: Number(process.env.TT_TEMPERATURE) || 0.4,
  topP: Number(process.env.TT_TOP_P) || 0.8,
  maxTokens: Number(process.env.TT_MAX_TOKENS) || 8192,
  debounceMs: 650,
  autoTranslate: true,
  watchClipboard: false,
  autoCopy: true,
  autoPaste: false,
  alwaysOnTop: true
};

function settingsPath() {
  return path.join(app.getPath('userData'), 'settings.json');
}

async function loadSettings() {
  try {
    const raw = await fs.readFile(settingsPath(), 'utf8');
    settings = { ...DEFAULT_SETTINGS, ...JSON.parse(raw) };
  } catch {
    settings = { ...DEFAULT_SETTINGS };
  }
}

async function saveSettings(nextSettings) {
  settings = { ...settings, ...nextSettings };
  await fs.mkdir(app.getPath('userData'), { recursive: true });
  await fs.writeFile(settingsPath(), JSON.stringify(settings, null, 2));
  applyWindowBehavior();
  updateClipboardWatcher();
  return settings;
}

function resolveChatUrl(baseUrl) {
  const trimmed = String(baseUrl || '').trim().replace(/\/+$/, '');
  if (!trimmed) {
    throw new Error('请先配置 LLM Base URL');
  }
  if (trimmed.endsWith('/chat/completions')) {
    return trimmed;
  }
  if (trimmed.endsWith('/v1')) {
    return `${trimmed}/chat/completions`;
  }
  return `${trimmed}/v1/chat/completions`;
}

function detectTargetLanguage(text) {
  return /[\u3400-\u9fff]/.test(text) ? 'English' : 'Simplified Chinese';
}

async function translateText(text, requestSettings = {}) {
  const source = String(text || '').trim();
  if (!source) return '';

  const merged = { ...settings, ...requestSettings };
  const targetLanguage = detectTargetLanguage(source);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 60000);

  try {
    const response = await fetch(resolveChatUrl(merged.baseUrl), {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'Content-Type': 'application/json',
        ...(merged.apiKey ? { Authorization: `Bearer ${merged.apiKey}` } : {})
      },
      body: JSON.stringify({
        model: merged.model,
        temperature: Number(merged.temperature) || DEFAULT_SETTINGS.temperature,
        top_p: Number(merged.topP) || DEFAULT_SETTINGS.topP,
        max_tokens: Number(merged.maxTokens) || DEFAULT_SETTINGS.maxTokens,
        stream: false,
        messages: [
          {
            role: 'system',
            content: [
              'You are a translation engine for Chinese and English.',
              'Translate the user text into the target language.',
              'Return only the translated text.',
              'Preserve markdown, code blocks, names, URLs, and numbers.',
              'Do not explain the translation.'
            ].join(' ')
          },
          {
            role: 'user',
            content: `Target language: ${targetLanguage}\n\nText:\n${source}`
          }
        ]
      })
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`LLM 请求失败：${response.status} ${body.slice(0, 300)}`);
    }

    const data = await response.json();
    const translated = data?.choices?.[0]?.message?.content?.trim();
    if (!translated) {
      throw new Error('LLM 响应里没有翻译结果');
    }

    if (merged.autoCopy) {
      writeClipboard(translated);
    }
    if (merged.autoPaste) {
      await pasteTextToFrontApp(translated);
    }

    return translated;
  } finally {
    clearTimeout(timer);
  }
}

function writeClipboard(text) {
  const value = String(text || '');
  lastProgrammaticClipboardText = value;
  lastClipboardText = value;
  clipboard.writeText(value);
}

async function pasteTextToFrontApp(text) {
  writeClipboard(text);

  if (process.platform !== 'darwin') {
    throw new Error('自动粘贴目前只支持 macOS');
  }

  const wasVisible = mainWindow?.isVisible();
  if (wasVisible) {
    mainWindow.hide();
  }

  await new Promise((resolve) => setTimeout(resolve, 120));
  await runAppleScript([
    'tell application "System Events"',
    '  keystroke "v" using command down',
    'end tell'
  ].join('\n'));

  if (wasVisible) {
    setTimeout(() => {
      if (!mainWindow?.isDestroyed()) {
        mainWindow.showInactive();
      }
    }, 180);
  }
}

function runAppleScript(script) {
  return new Promise((resolve, reject) => {
    execFile('osascript', ['-e', script], (error, stdout, stderr) => {
      if (error) {
        reject(new Error(stderr.trim() || error.message));
        return;
      }
      resolve(stdout);
    });
  });
}

function updateClipboardWatcher() {
  if (clipboardTimer) {
    clearInterval(clipboardTimer);
    clipboardTimer = null;
  }

  if (!settings.watchClipboard) return;

  lastClipboardText = clipboard.readText();
  clipboardTimer = setInterval(() => {
    const current = clipboard.readText();
    if (!current || current === lastClipboardText || current === lastProgrammaticClipboardText) {
      return;
    }
    lastClipboardText = current;
    mainWindow?.webContents.send('clipboard-changed', current);
  }, 550);
}

function applyWindowBehavior() {
  if (!mainWindow) return;
  mainWindow.setAlwaysOnTop(Boolean(settings.alwaysOnTop), 'floating');
  mainWindow.setVisibleOnAllWorkspaces(Boolean(settings.alwaysOnTop), {
    visibleOnFullScreen: true
  });
}

function createMenu() {
  const menu = Menu.buildFromTemplate([
    {
      label: app.name,
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' }
      ]
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'selectAll' }
      ]
    },
    {
      label: 'Window',
      submenu: [
        { role: 'minimize' },
        { role: 'close' },
        { type: 'separator' },
        {
          label: 'Toggle Always on Top',
          accelerator: 'CommandOrControl+Shift+O',
          click: async () => {
            await saveSettings({ alwaysOnTop: !settings.alwaysOnTop });
            mainWindow?.webContents.send('settings-updated', settings);
          }
        }
      ]
    },
    {
      label: 'Help',
      submenu: [
        {
          label: 'Open Settings File',
          click: () => shell.showItemInFolder(settingsPath())
        }
      ]
    }
  ]);
  Menu.setApplicationMenu(menu);
}

function registerShortcuts() {
  globalShortcut.unregisterAll();
  globalShortcut.register('CommandOrControl+Shift+T', () => {
    mainWindow?.webContents.send('shortcut-translate-clipboard');
  });
  globalShortcut.register('CommandOrControl+Shift+V', () => {
    mainWindow?.webContents.send('shortcut-paste-result');
  });
}

async function createWindow() {
  mainWindow = new BrowserWindow({
    width: 420,
    height: 540,
    minWidth: 340,
    minHeight: 420,
    show: false,
    title: 'TT Translator',
    titleBarStyle: 'hiddenInset',
    vibrancy: 'sidebar',
    visualEffectState: 'active',
    backgroundColor: '#f7f4ee',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  mainWindow.once('ready-to-show', () => {
    applyWindowBehavior();
    mainWindow.show();
  });

  await mainWindow.loadFile(path.join(__dirname, 'index.html'));
}

app.whenReady().then(async () => {
  await loadSettings();
  createMenu();
  await createWindow();
  updateClipboardWatcher();
  registerShortcuts();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  } else {
    mainWindow?.show();
  }
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
  if (clipboardTimer) clearInterval(clipboardTimer);
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

ipcMain.handle('settings:get', () => settings);
ipcMain.handle('settings:save', (_event, nextSettings) => saveSettings(nextSettings));
ipcMain.handle('translate', (_event, payload) => translateText(payload?.text, payload?.settings));
ipcMain.handle('clipboard:read', () => clipboard.readText());
ipcMain.handle('clipboard:write', (_event, text) => writeClipboard(text));
ipcMain.handle('paste:text', (_event, text) => pasteTextToFrontApp(text));
ipcMain.handle('window:always-on-top', async (_event, enabled) => {
  await saveSettings({ alwaysOnTop: Boolean(enabled) });
  return settings;
});

ipcMain.on('window:drag-start', (event) => {
  const windowToDrag = BrowserWindow.fromWebContents(event.sender);
  if (!windowToDrag) return;

  dragState = {
    windowId: windowToDrag.id,
    bounds: windowToDrag.getBounds(),
    cursor: screen.getCursorScreenPoint()
  };
});

ipcMain.on('window:drag-move', (event) => {
  const windowToDrag = BrowserWindow.fromWebContents(event.sender);
  if (!windowToDrag || !dragState || dragState.windowId !== windowToDrag.id) return;

  const cursor = screen.getCursorScreenPoint();
  windowToDrag.setPosition(
    Math.round(dragState.bounds.x + cursor.x - dragState.cursor.x),
    Math.round(dragState.bounds.y + cursor.y - dragState.cursor.y),
    false
  );
});

ipcMain.on('window:drag-end', () => {
  dragState = null;
});
