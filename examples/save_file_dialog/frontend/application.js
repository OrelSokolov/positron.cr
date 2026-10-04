function saveFile() {
  const status = document.getElementById('status');
  const meta = document.getElementById('meta');
  const filename = document.getElementById('filename').value.trim() || 'note.txt';
  const content = document.getElementById('editor').value;

  status.textContent = 'Opening native save dialog…';
  meta.textContent = '';

  Positron.save_file_dialog.save({ suggested_name: filename, content: content });
}

Positron.on('save_file_dialog.saved', function (data) {
  document.getElementById('status').textContent = 'Saved: ' + data.name;
  document.getElementById('meta').textContent = data.path;
});

Positron.on('save_file_dialog.canceled', function () {
  document.getElementById('status').textContent = 'Canceled';
});

Positron.on('save_file_dialog.error', function (data) {
  document.getElementById('status').textContent = 'Error: ' + (data.error || 'unknown');
});
