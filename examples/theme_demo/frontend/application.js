async function refreshTheme() {
  const result = document.getElementById('result');
  result.innerHTML = '<pre>Reading system theme...</pre>';

  try {
    const info = await CrystalUI.theme.get_info();
    document.body.setAttribute('data-theme', info.mode);

    const lines = [
      'mode:         ' + info.mode,
      'accent_color: ' + (info.accent_color || 'unknown'),
      'material_you: ' + info.material_you,
      'high_contrast:' + info.high_contrast,
    ];
    result.innerHTML = '<pre>' + lines.join('\n') + '</pre>';
  } catch (err) {
    result.innerHTML = '<pre style="color:#e01b24">' + err.message + '</pre>';
  }
}

refreshTheme();
