function pickFile() {
  const status = document.getElementById('status');
  const viewer = document.getElementById('viewer');
  const meta = document.getElementById('meta');

  status.textContent = 'Opening native file picker…';
  viewer.value = '';
  meta.textContent = '';

  CrystalUI.file_picker.pick({ accept: '.txt' });
}

CrystalUI.on('file_picker.selected', function (data) {
  document.getElementById('status').textContent = 'Loaded: ' + data.name;
  document.getElementById('meta').textContent = data.path;
  document.getElementById('viewer').value = data.content;
});

CrystalUI.on('file_picker.canceled', function () {
  document.getElementById('status').textContent = 'Canceled';
});

CrystalUI.on('file_picker.error', function (data) {
  document.getElementById('status').textContent = 'Error: ' + (data.error || 'unknown');
});
