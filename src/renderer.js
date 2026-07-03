const state = {
  settings: null,
  requestId: 0,
  debounceTimer: null,
  dragTimer: null,
  dragTimeout: null,
  lastResult: ''
};

const $ = (id) => document.getElementById(id);

const elements = {
  status: $('status'),
  sourceText: $('sourceText'),
  resultText: $('resultText'),
  pasteInput: $('pasteInput'),
  translateNow: $('translateNow'),
  copyResult: $('copyResult'),
  pasteResult: $('pasteResult'),
  swapText: $('swapText'),
  clearText: $('clearText'),
  baseUrl: $('baseUrl'),
  apiKey: $('apiKey'),
  model: $('model'),
  temperature: $('temperature'),
  topP: $('topP'),
  maxTokens: $('maxTokens'),
  debounceMs: $('debounceMs'),
  autoTranslate: $('autoTranslate'),
  watchClipboard: $('watchClipboard'),
  autoCopy: $('autoCopy'),
  autoPaste: $('autoPaste'),
  alwaysOnTop: $('alwaysOnTop')
};

const dragStrip = document.querySelector('.window-drag-strip');
const topbar = document.querySelector('.topbar');

function setStatus(text) {
  elements.status.textContent = text;
}

function normalizeSettingsFromForm() {
  return {
    baseUrl: elements.baseUrl.value.trim(),
    apiKey: elements.apiKey.value.trim(),
    model: elements.model.value.trim(),
    temperature: Number(elements.temperature.value) || 0.4,
    topP: Number(elements.topP.value) || 0.8,
    maxTokens: Number(elements.maxTokens.value) || 8192,
    debounceMs: Number(elements.debounceMs.value) || 650,
    autoTranslate: elements.autoTranslate.checked,
    watchClipboard: elements.watchClipboard.checked,
    autoCopy: elements.autoCopy.checked,
    autoPaste: elements.autoPaste.checked,
    alwaysOnTop: elements.alwaysOnTop.checked
  };
}

function renderSettings(settings) {
  state.settings = settings;
  elements.baseUrl.value = settings.baseUrl || '';
  elements.apiKey.value = settings.apiKey || '';
  elements.model.value = settings.model || '';
  elements.temperature.value = settings.temperature || 0.4;
  elements.topP.value = settings.topP || 0.8;
  elements.maxTokens.value = settings.maxTokens || 8192;
  elements.debounceMs.value = settings.debounceMs || 650;
  elements.autoTranslate.checked = Boolean(settings.autoTranslate);
  elements.watchClipboard.checked = Boolean(settings.watchClipboard);
  elements.autoCopy.checked = Boolean(settings.autoCopy);
  elements.autoPaste.checked = Boolean(settings.autoPaste);
  elements.alwaysOnTop.checked = Boolean(settings.alwaysOnTop);
}

async function persistSettings() {
  state.settings = await window.tt.saveSettings(normalizeSettingsFromForm());
  renderSettings(state.settings);
  setStatus('设置已保存');
}

function scheduleTranslation() {
  clearTimeout(state.debounceTimer);
  if (!state.settings?.autoTranslate) return;
  state.debounceTimer = setTimeout(() => {
    translateCurrentText();
  }, state.settings.debounceMs || 650);
}

async function translateCurrentText() {
  const text = elements.sourceText.value.trim();
  const requestId = ++state.requestId;

  if (!text) {
    elements.resultText.value = '';
    state.lastResult = '';
    setStatus('Ready');
    return;
  }

  setStatus('Translating...');

  try {
    const translated = await window.tt.translate(text, normalizeSettingsFromForm());
    if (requestId !== state.requestId) return;
    state.lastResult = translated;
    elements.resultText.value = translated;
    setStatus(elements.autoCopy.checked ? 'Done · copied' : 'Done');
  } catch (error) {
    if (requestId !== state.requestId) return;
    setStatus(error.message || '翻译失败');
  }
}

async function pullClipboardAndTranslate() {
  const text = await window.tt.readClipboard();
  if (!text) {
    setStatus('剪贴板为空');
    return;
  }
  elements.sourceText.value = text;
  await translateCurrentText();
}

async function copyResult() {
  const result = elements.resultText.value.trim();
  if (!result) return;
  await window.tt.writeClipboard(result);
  setStatus('已复制');
}

async function pasteResult() {
  const result = elements.resultText.value.trim();
  if (!result) return;

  try {
    await window.tt.pasteText(result);
    setStatus('已粘贴');
  } catch (error) {
    setStatus(`粘贴失败：${error.message}`);
  }
}

function startWindowDrag(event) {
  if (event.button !== 0 || event.target.closest('button, input, textarea, select, summary')) {
    return;
  }

  event.preventDefault();
  clearInterval(state.dragTimer);
  clearTimeout(state.dragTimeout);

  window.tt.startWindowDrag();
  state.dragTimer = setInterval(() => {
    window.tt.moveWindowDrag();
  }, 16);
  state.dragTimeout = setTimeout(endWindowDrag, 8000);
}

function endWindowDrag() {
  if (!state.dragTimer) return;

  clearInterval(state.dragTimer);
  clearTimeout(state.dragTimeout);
  state.dragTimer = null;
  state.dragTimeout = null;
  window.tt.endWindowDrag();
}

function bindEvents() {
  dragStrip.addEventListener('mousedown', startWindowDrag);
  topbar.addEventListener('mousedown', startWindowDrag);
  window.addEventListener('mouseup', endWindowDrag);
  window.addEventListener('blur', endWindowDrag);
  elements.sourceText.addEventListener('input', scheduleTranslation);
  elements.translateNow.addEventListener('click', translateCurrentText);
  elements.pasteInput.addEventListener('click', pullClipboardAndTranslate);
  elements.copyResult.addEventListener('click', copyResult);
  elements.pasteResult.addEventListener('click', pasteResult);
  elements.swapText.addEventListener('click', () => {
    const source = elements.sourceText.value;
    elements.sourceText.value = elements.resultText.value;
    elements.resultText.value = source;
    scheduleTranslation();
  });
  elements.clearText.addEventListener('click', () => {
    elements.sourceText.value = '';
    elements.resultText.value = '';
    state.lastResult = '';
    setStatus('Ready');
  });

  [
    elements.baseUrl,
    elements.apiKey,
    elements.model,
    elements.temperature,
    elements.topP,
    elements.maxTokens,
    elements.debounceMs,
    elements.autoTranslate,
    elements.watchClipboard,
    elements.autoCopy,
    elements.autoPaste,
    elements.alwaysOnTop
  ].forEach((element) => {
    element.addEventListener('change', persistSettings);
  });

  window.tt.onClipboardChanged((text) => {
    elements.sourceText.value = text;
    setStatus('Clipboard changed');
    scheduleTranslation();
  });

  window.tt.onSettingsUpdated((settings) => {
    renderSettings(settings);
  });

  window.tt.onTranslateClipboardShortcut(() => {
    pullClipboardAndTranslate();
  });

  window.tt.onPasteResultShortcut(() => {
    pasteResult();
  });
}

async function boot() {
  renderSettings(await window.tt.getSettings());
  bindEvents();
  setStatus('Ready');
}

boot();
