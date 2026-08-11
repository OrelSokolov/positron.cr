const statusEl = document.getElementById('status');
const monitorCountEl = document.getElementById('monitorCount');
const virtualSizeEl = document.getElementById('virtualSize');
const orientationEl = document.getElementById('orientation');
const monitorsEl = document.getElementById('monitors');

function setStatus(message) {
  statusEl.textContent = message;
}

function formatResolution(screen) {
  return `${screen.width} × ${screen.height}`;
}

function formatPosition(screen) {
  return `(${screen.x}, ${screen.y})`;
}

function renderScreen(screen) {
  const primaryBadge = screen.primary ? '<span class="badge">Primary</span>' : '';
  const physicalSize = screen.width_mm && screen.height_mm
    ? `${screen.width_mm} × ${screen.height_mm} mm`
    : 'Unknown';
  const manufacturer = screen.manufacturer || 'Unknown';
  const model = screen.model || 'Unknown';

  return `
    <article class="monitor-card ${screen.primary ? 'primary' : ''}">
      <div class="monitor-header">
        <h2 class="monitor-title">${escapeHtml(screen.name || screen.id)}</h2>
        ${primaryBadge}
      </div>
      <div class="monitor-grid">
        <div class="item">
          <span class="label">Resolution</span>
          <span class="value">${escapeHtml(formatResolution(screen))}</span>
        </div>
        <div class="item">
          <span class="label">Position</span>
          <span class="value">${escapeHtml(formatPosition(screen))}</span>
        </div>
        <div class="item">
          <span class="label">DPI</span>
          <span class="value">${screen.dpi.toFixed(2)}</span>
        </div>
        <div class="item">
          <span class="label">Scale</span>
          <span class="value">${screen.scale_factor}×</span>
        </div>
        <div class="item">
          <span class="label">Refresh</span>
          <span class="value">${screen.refresh_rate.toFixed(2)} Hz</span>
        </div>
        <div class="item">
          <span class="label">Orientation</span>
          <span class="value">${escapeHtml(screen.orientation)}</span>
        </div>
        <div class="item">
          <span class="label">Physical size</span>
          <span class="value">${escapeHtml(physicalSize)}</span>
        </div>
        <div class="item">
          <span class="label">Manufacturer</span>
          <span class="value">${escapeHtml(manufacturer)}</span>
        </div>
        <div class="item">
          <span class="label">Model</span>
          <span class="value">${escapeHtml(model)}</span>
        </div>
      </div>
    </article>
  `;
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = String(text);
  return div.innerHTML;
}

function renderInfo(info) {
  monitorCountEl.textContent = String(info.screens.length);
  virtualSizeEl.textContent = `${info.total_width} × ${info.total_height}`;
  orientationEl.textContent = info.orientation;

  monitorsEl.innerHTML = info.screens.map(renderScreen).join('');
}

async function refreshInfo() {
  setStatus('Reading display information...');
  try {
    const info = await CrystalUI.display.get_info();
    renderInfo(info);
    setStatus('Display information updated');
  } catch (err) {
    setStatus('Failed to read display info: ' + err.message);
  }
}

// Load information automatically on startup.
refreshInfo();
