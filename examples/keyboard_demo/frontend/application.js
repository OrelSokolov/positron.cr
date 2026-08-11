const hotkeyStage = document.getElementById('hotkeyStage');
const eventList = document.getElementById('eventList');
const kbdInfo = document.getElementById('kbdInfo');

const shortcutLabels = {
  select_all: 'Select all',
  bold: 'Bold'
};

function formatModifiers(e) {
  const parts = [];
  if (e.ctrlKey) parts.push('Ctrl');
  if (e.altKey) parts.push('Alt');
  if (e.shiftKey) parts.push('Shift');
  if (e.metaKey) parts.push('Meta');
  return parts;
}

function formatCombo(e) {
  const mods = formatModifiers(e);
  const key = e.key === ' ' ? 'Space' : e.key;
  return mods.concat(key).join(' + ');
}

function renderPillParts(e) {
  const mods = formatModifiers(e);
  const key = e.key === ' ' ? 'Space' : e.key;
  const label = e.shortcut && shortcutLabels[e.shortcut]
    ? `<span class="label">${shortcutLabels[e.shortcut]}</span>`
    : '';
  const keysHtml = mods
    .map(m => `<span class="key">${m}</span>`)
    .concat(`<span class="key">${key}</span>`)
    .join('<span class="sep">+</span>');
  return keysHtml + label;
}

function renderEvent(event) {
  const mods = [];
  if (event.ctrl) mods.push('Ctrl');
  if (event.alt) mods.push('Alt');
  if (event.shift) mods.push('Shift');
  if (event.meta) mods.push('Meta');
  const key = event.key === ' ' ? 'Space' : event.key;
  const keysHtml = mods
    .map(m => `<span class="k">${m}</span>`)
    .concat(`<span class="k">${key}</span>`)
    .join(' ');
  const shortcut = event.shortcut ? ` · ${event.shortcut}` : '';
  const time = new Date(event.timestamp).toLocaleTimeString();
  return `<li>
    <span class="combo">${keysHtml}</span>
    <span class="meta">${time}${shortcut}</span>
  </li>`;
}

function renderEvents(events) {
  if (!events || events.length === 0) {
    eventList.innerHTML = '<li class="empty">No events yet</li>';
    return;
  }
  eventList.innerHTML = events.slice().reverse().map(renderEvent).join('');
}

function showHotkeyPill(data) {
  const placeholder = hotkeyStage.querySelector('.hotkey-placeholder');
  if (placeholder) placeholder.remove();

  const pill = document.createElement('div');
  pill.className = 'hotkey-pill';
  pill.innerHTML = renderPillParts(data);
  hotkeyStage.appendChild(pill);
  hotkeyStage.classList.add('active');

  setTimeout(() => {
    pill.style.animation = 'fadeOutDown 0.35s ease forwards';
    setTimeout(() => {
      pill.remove();
      if (!hotkeyStage.querySelector('.hotkey-pill')) {
        hotkeyStage.classList.remove('active');
      }
    }, 350);
  }, 1400);
}

function highlightShortcut(id) {
  const chip = document.querySelector(`.shortcut-chip[data-id="${id}"]`);
  if (!chip) return;
  chip.classList.add('matched');
  setTimeout(() => chip.classList.remove('matched'), 700);
}

async function registerShortcuts() {
  // Register by physical key code so shortcuts work regardless of layout.
  await CrystalUI.keyboard.register_shortcut({
    id: 'select_all',
    key: '',
    code: 'KeyA',
    ctrl: true,
    alt: false,
    shift: false,
    meta: false,
    prevent_default: true
  });

  await CrystalUI.keyboard.register_shortcut({
    id: 'bold',
    key: '',
    code: 'KeyB',
    ctrl: true,
    alt: false,
    shift: false,
    meta: false,
    prevent_default: true
  });
}

async function clearEvents() {
  await CrystalUI.keyboard.clear_events();
  renderEvents([]);
}

async function loadEvents() {
  const events = await CrystalUI.keyboard.get_events();
  renderEvents(events);
}

async function updateKbdInfo() {
  const info = await CrystalUI.keyboard.get_virtual_keyboard_info();
  kbdInfo.innerHTML = `Height: <strong>${info.height} px</strong> · Visible: <strong>${info.visible}</strong>`;
}

function isModifierKey(key) {
  return ["Control", "Alt", "Shift", "Meta", "OS", "AltGraph"].includes(key);
}

document.addEventListener('keydown', function(e) {
  // Ignore repeated keys while held down.
  if (e.repeat) return;

  const payload = {
    type: 'keydown',
    key: e.key,
    code: e.code,
    ctrl: e.ctrlKey,
    alt: e.altKey,
    shift: e.shiftKey,
    meta: e.metaKey
  };

  CrystalUI.emit('keyboard.keydown', payload);

  // Local preview for real keys only — don't animate bare modifier presses.
  if (!isModifierKey(e.key)) {
    showHotkeyPill({
      key: e.key,
      ctrlKey: e.ctrlKey,
      altKey: e.altKey,
      shiftKey: e.shiftKey,
      metaKey: e.metaKey,
      shortcut: null
    });
  }
});

CrystalUI.on('state.keyboard.events', function() {
  loadEvents();
});

CrystalUI.on('state.keyboard.last_event', function(event) {
  if (!event) return;

  showHotkeyPill({
    key: event.key,
    ctrlKey: event.ctrl,
    altKey: event.alt,
    shiftKey: event.shift,
    metaKey: event.meta,
    shortcut: event.shortcut
  });

  if (event.shortcut) {
    highlightShortcut(event.shortcut);
  }
});

// Keep focus-hint clickable so users can focus the window.
document.querySelector('.focus-hint').addEventListener('click', function() {
  window.focus();
});

// Add a fade-out keyframe dynamically.
const style = document.createElement('style');
style.textContent = `
  @keyframes fadeOutDown {
    from { opacity: 1; transform: translateY(0) scale(1); }
    to { opacity: 0; transform: translateY(16px) scale(0.92); }
  }
`;
document.head.appendChild(style);

registerShortcuts();
loadEvents();
updateKbdInfo();
