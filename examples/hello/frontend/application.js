async function sendCommand() {
  const btn = document.getElementById('actionBtn');
  const result = document.getElementById('result');
  btn.classList.add('loading');
  result.classList.remove('success');
  result.textContent = 'Talking to the Crystal Host...';
  const data = await CrystalUI.call('hello', {});
  btn.classList.remove('loading');
  result.classList.add('success');
  result.innerHTML = '<strong>Crystal answered:</strong><br>' +
    Object.entries(data).map(([k, v]) => k + ': ' + v).join('<br>');
}

async function toggleTheme() {
  const current = await CrystalUI.settings.current_theme();
  const next = current === 'dark' ? 'light' : 'dark';
  await CrystalUI.settings.set_theme({ theme: next });
}

async function saveGreeting() {
  const name = prompt('What is your name?');
  if (!name) return;

  const result = document.getElementById('result');
  result.classList.remove('success');
  result.textContent = 'Saving...';

  await CrystalUI.preferences.set({ key: 'greeting', value: name });

  result.classList.add('success');
  result.textContent = 'Saved greeting for ' + name;
}

async function loadGreeting() {
  const result = document.getElementById('result');
  result.classList.remove('success');
  result.textContent = 'Loading...';

  const name = await CrystalUI.preferences.get({ key: 'greeting', default: 'stranger' });

  result.classList.add('success');
  result.innerHTML = '<strong>Hello, ' + name + '!</strong><br>Loaded from persistent storage.';
}
