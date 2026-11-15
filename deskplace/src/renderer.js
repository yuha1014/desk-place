const STORAGE_KEY = 'deskplace-state-v1';
const defaults = { focus: '오늘은 중요한 일에\n차분히 집중하기', notes: '', todos: [], positions: {}, widgets: {}, wallpaper: null };
let state = readState();
const $ = (selector) => document.querySelector(selector);

function readState() {
  try { return { ...defaults, ...JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}') }; }
  catch { return { ...defaults }; }
}
function saveState() { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); }
function applyPanelColor() {
  const autoMatch = $('#match-wallpaper-color').checked;
  $('.workspace').classList.toggle('match-wallpaper-color', autoMatch);
  const color = autoMatch ? (state.detectedWallpaperColor || '#fffaf4') : (state.panelColor || '#fffaf4');
  document.documentElement.style.setProperty('--wallpaper-panel-color', color);
}
function updateCount() { $('#note-count').textContent = `${$('#notes-input').value.length}자`; }
function updateClock() {
  const now = new Date();
  $('#clock-time').textContent = new Intl.DateTimeFormat('ko-KR', { hour: '2-digit', minute: '2-digit', hour12: false }).format(now);
  $('#clock-date').textContent = new Intl.DateTimeFormat('ko-KR', { year: 'numeric', month: 'long', day: 'numeric', weekday: 'long' }).format(now);
  $('#date-line').textContent = new Intl.DateTimeFormat('ko-KR', { month: 'long', day: 'numeric', weekday: 'long' }).format(now);
}
function renderTodos() {
  const list = $('#todo-list');
  list.replaceChildren();
  state.todos.forEach((todo) => {
    const item = document.createElement('li');
    item.className = `todo-item${todo.done ? ' done' : ''}`;
    const checkbox = document.createElement('input'); checkbox.type = 'checkbox'; checkbox.checked = todo.done; checkbox.setAttribute('aria-label', '완료 표시');
    checkbox.addEventListener('change', () => { todo.done = checkbox.checked; saveState(); renderTodos(); });
    const text = document.createElement('span'); text.className = 'todo-text'; text.textContent = todo.text; text.title = '두 번 클릭해 이름 변경'; text.addEventListener('dblclick', () => editTodo(todo.id));
    const remove = document.createElement('button'); remove.className = 'delete-task'; remove.textContent = '×'; remove.setAttribute('aria-label', '할 일 삭제'); remove.addEventListener('click', () => { state.todos = state.todos.filter((entry) => entry.id !== todo.id); saveState(); renderTodos(); });
    item.append(checkbox, text, remove); list.append(item);
  });
  $('#empty-todos').hidden = state.todos.length > 0;
  $('#task-total').textContent = `${state.todos.filter((todo) => !todo.done).length}`;
}
function editTodo(id) {
  const todo = state.todos.find((entry) => entry.id === id);
  if (!todo) return;
  const input = document.createElement('input'); input.value = todo.text; input.maxLength = 100; input.className = 'todo-form-input';
  const label = [...$('#todo-list').querySelectorAll('.todo-item')].find((el) => el.querySelector('.todo-text').textContent === todo.text)?.querySelector('.todo-text');
  if (!label) return;
  label.replaceWith(input); input.focus(); input.select();
  const finish = () => { const value = input.value.trim(); if (value) todo.text = value; saveState(); renderTodos(); };
  input.addEventListener('blur', finish, { once: true });
  input.addEventListener('keydown', (event) => { if (event.key === 'Enter') input.blur(); if (event.key === 'Escape') { input.value = todo.text; input.blur(); } });
}
function restorePositions() {
  const compact = matchMedia('(max-width: 850px)').matches;
  const wallpaperMode = $('.workspace').classList.contains('wallpaper-mode');
  if (compact && !wallpaperMode) return;
  document.querySelectorAll('[data-panel]').forEach((panel) => {
    const saved = state.positions[panel.dataset.panel];
    if (saved) {
      const x = Math.max(0, Math.min(saved.x, window.innerWidth - panel.offsetWidth));
      const y = Math.max(64, Math.min(saved.y, window.innerHeight - panel.offsetHeight));
      panel.style.left = `${x}px`; panel.style.top = `${y}px`; panel.style.right = 'auto';
      if (x !== saved.x || y !== saved.y) state.positions[panel.dataset.panel] = { x, y };
    }
  });
  saveState();
  scheduleHitRegionSync();
}
function setWallpaper(file) {
  if (!file?.opened) return;
  $('.workspace').classList.add('wallpaper-mode');
  state.wallpaper = { name: file.name || '선택한 HTML' };
  $('#date-line').textContent = `배경 HTML · ${file.name || '선택한 HTML'}`;
  saveState();
  scheduleHitRegionSync();
}
function resetWallpaper() {
  window.deskplace.resetWallpaper();
  $('.workspace').classList.remove('wallpaper-mode');
  state.wallpaper = null;
  saveState();
  scheduleHitRegionSync();
}
function applyWidgetPreference(key) {
  const panel = document.querySelector(`[data-panel="${key}"]`);
  const preference = state.widgets[key] || {};
  if (!panel) return;
  panel.classList.toggle('is-hidden', preference.visible === false);
  panel.style.zoom = String((preference.scale || 100) / 100);
  scheduleHitRegionSync();
}
function setupWidgetSettings() {
  const adjustDefaultScale = !state.smallWidgetDefaultsApplied;
  document.querySelectorAll('[data-widget-setting]').forEach((row) => {
    const key = row.dataset.widgetSetting;
    const preference = state.widgets[key] || { visible: true, scale: 85 };
    if (adjustDefaultScale && preference.scale === 100) preference.scale = 85;
    state.widgets[key] = preference;
    const visible = row.querySelector('.widget-visible');
    const scale = row.querySelector('.widget-scale');
    const output = row.querySelector('output');
    visible.checked = preference.visible !== false;
    scale.value = String(preference.scale || 85);
    output.value = `${scale.value}%`;
    visible.addEventListener('change', () => {
      preference.visible = visible.checked;
      applyWidgetPreference(key);
      saveState();
      scheduleHitRegionSync();
    });
    scale.addEventListener('input', () => {
      preference.scale = Number(scale.value);
      output.value = `${scale.value}%`;
      applyWidgetPreference(key);
      saveState();
      scheduleHitRegionSync();
    });
    applyWidgetPreference(key);
  });
  state.smallWidgetDefaultsApplied = true;
  saveState();
}
let hitRegionFrame = 0;
function scheduleHitRegionSync() {
  if (hitRegionFrame) cancelAnimationFrame(hitRegionFrame);
  hitRegionFrame = requestAnimationFrame(() => {
    hitRegionFrame = 0;
    const targets = [...document.querySelectorAll('.panel, #open-html, #show-desktop, #settings-toggle')]
      .filter((element) => !element.closest('.hidden') && element.getClientRects().length > 0);
    const regions = targets.map((element) => {
      const rect = element.getBoundingClientRect();
      return { x: rect.left, y: rect.top, width: rect.width, height: rect.height };
    });
    window.deskplace.setInteractiveRegions(regions);
  });
}
function enablePanelDragging() {
  document.querySelectorAll('[data-panel]').forEach((panel) => {
    const handle = panel.querySelector('.drag-handle');
    if (!handle) return;
    handle.addEventListener('pointerdown', (event) => {
      if (matchMedia('(max-width: 850px)').matches || event.button !== 0) return;
      const rect = panel.getBoundingClientRect();
      panel.style.left = `${rect.left}px`; panel.style.top = `${rect.top}px`; panel.style.right = 'auto';
      const offsetX = event.clientX - rect.left; const offsetY = event.clientY - rect.top;
      handle.setPointerCapture(event.pointerId);
      const move = (moveEvent) => {
        const maxX = Math.max(0, window.innerWidth - panel.offsetWidth);
        const maxY = Math.max(64, window.innerHeight - panel.offsetHeight);
        const x = Math.min(maxX, Math.max(0, moveEvent.clientX - offsetX));
        const y = Math.min(maxY, Math.max(64, moveEvent.clientY - offsetY));
        panel.style.left = `${x}px`; panel.style.top = `${y}px`;
        scheduleHitRegionSync();
      };
      const end = () => {
        handle.removeEventListener('pointermove', move); handle.removeEventListener('pointerup', end);
        const rectNow = panel.getBoundingClientRect(); state.positions[panel.dataset.panel] = { x: rectNow.left, y: rectNow.top }; saveState(); scheduleHitRegionSync();
      };
      handle.addEventListener('pointermove', move); handle.addEventListener('pointerup', end, { once: true });
    });
  });
}

$('#notes-input').value = state.notes;
const focus = $('[data-save="focus"]'); focus.innerText = state.focus;
focus.addEventListener('input', () => { state.focus = focus.innerText; saveState(); });
$('#notes-input').addEventListener('input', (event) => { state.notes = event.target.value; updateCount(); saveState(); });
$('#todo-form').addEventListener('submit', (event) => { event.preventDefault(); const input = $('#todo-input'); const text = input.value.trim(); if (!text) return; state.todos.push({ id: crypto.randomUUID(), text, done: false }); input.value = ''; saveState(); renderTodos(); });
$('#settings-toggle').addEventListener('click', () => { $('#settings-panel').classList.toggle('hidden'); scheduleHitRegionSync(); });
$('#settings-close').addEventListener('click', () => { $('#settings-panel').classList.add('hidden'); scheduleHitRegionSync(); });
$('#settings-panel').addEventListener('pointerdown', (event) => event.stopPropagation());
$('#settings-panel').addEventListener('input', scheduleHitRegionSync);
$('#settings-panel').addEventListener('change', scheduleHitRegionSync);
$('#open-html').addEventListener('click', async () => {
  const result = await window.deskplace.openHtml();
  setWallpaper(result);
});
$('#reset-wallpaper').addEventListener('click', resetWallpaper);
$('#match-wallpaper-color').checked = state.matchWallpaperColor !== false;
$('#manual-panel-color').value = state.panelColor || '#fffaf4';
applyPanelColor();
$('#match-wallpaper-color').addEventListener('change', () => {
  state.matchWallpaperColor = $('#match-wallpaper-color').checked;
  applyPanelColor(); saveState(); scheduleHitRegionSync();
});
$('#manual-panel-color').addEventListener('input', (event) => {
  state.panelColor = event.target.value;
  if (!$('#match-wallpaper-color').checked) applyPanelColor();
  saveState();
});
const wallpaperScale = $('#wallpaper-scale');
wallpaperScale.value = String(state.wallpaperScale || 100);
$('#wallpaper-scale-output').value = `${wallpaperScale.value}%`;
wallpaperScale.addEventListener('input', () => {
  state.wallpaperScale = Number(wallpaperScale.value);
  $('#wallpaper-scale-output').value = `${wallpaperScale.value}%`;
  window.deskplace.setWallpaperScale(state.wallpaperScale);
  saveState();
});
window.deskplace.setWallpaperScale(state.wallpaperScale || 100);
window.addEventListener('deskplace:wallpaper-color', (event) => {
  state.detectedWallpaperColor = event.detail;
  if ($('#match-wallpaper-color').checked) applyPanelColor();
});
$('#show-desktop').addEventListener('click', () => window.deskplace.showDesktop());
$('#launch-toggle').addEventListener('change', async (event) => {
  const result = await window.deskplace.setLoginItem(event.target.checked);
  event.target.checked = result.enabled;
  $('#login-support').textContent = result.supported ? (result.enabled ? '로그인 시 자동으로 시작합니다.' : '자동 시작이 꺼져 있습니다.') : '로그인 시 시작 설정은 macOS에서만 지원됩니다.';
});
$('#edge-to-edge-toggle').addEventListener('change', async (event) => {
  const result = await window.deskplace.setEdgeToEdge(event.target.checked);
  event.target.checked = result.enabled;
  scheduleHitRegionSync();
});
$('#keep-awake-toggle').addEventListener('change', async (event) => {
  const result = await window.deskplace.setKeepAwake(event.target.checked);
  event.target.checked = result.enabled;
});
window.deskplace.getKeepAwake().then((result) => {
  $('#keep-awake-toggle').checked = result.enabled;
});

updateClock(); setInterval(updateClock, 1000); updateCount(); renderTodos(); setupWidgetSettings(); enablePanelDragging(); restorePositions(); scheduleHitRegionSync();
window.addEventListener('resize', restorePositions);
if (state.wallpaper?.name) setWallpaper({ opened: true, ...state.wallpaper });
window.deskplace.getLoginItem().then((result) => {
  $('#launch-toggle').checked = result.enabled;
  $('#login-support').textContent = result.supported ? '' : '로그인 시 시작 설정은 macOS에서만 지원됩니다.';
});
window.deskplace.getEdgeToEdge().then((result) => {
  $('#edge-to-edge-toggle').checked = result.enabled;
  scheduleHitRegionSync();
});
