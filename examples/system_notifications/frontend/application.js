function setResult(text, success) {
  const el = document.getElementById('result');
  el.textContent = text;
  el.classList.toggle('success', success === true);
}

async function sendNotification() {
  setResult('Sending notification...');
  try {
    const id = await Positron.notifications.send({
      title: 'Hello from Positron',
      body: 'This bubble came from the Crystal Host via libnotify.'
    });
    setResult('Sent notification id: ' + id, true);
  } catch (err) {
    setResult('Error: ' + err.message, false);
  }
}

async function clearNotification() {
  const id = document.getElementById('notifId').value;
  if (!id) {
    setResult('Enter a notification id first');
    return;
  }
  setResult('Clearing ' + id + '...');
  try {
    const cleared = await Positron.notifications.clear({ id: id });
    setResult('Cleared: ' + cleared, cleared);
  } catch (err) {
    setResult('Error: ' + err.message, false);
  }
}

async function requestPermission() {
  setResult('Requesting permission...');
  try {
    const granted = await Positron.notifications.request_permission({});
    setResult('Permission granted: ' + granted, granted);
  } catch (err) {
    setResult('Error: ' + err.message, false);
  }
}

async function checkPermission() {
  try {
    const granted = await Positron.notifications.check_permission({});
    setResult('Permission status: ' + granted, granted);
  } catch (err) {
    setResult('Error: ' + err.message, false);
  }
}

Positron.on('notification.clicked', function(payload) {
  setResult('Notification clicked: ' + payload.id, true);
});
