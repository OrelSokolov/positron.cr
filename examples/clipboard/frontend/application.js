const statusEl = document.getElementById('status');
const textInput = document.getElementById('textInput');
const imageThumb = document.getElementById('imageThumb');
const imagePlaceholder = document.getElementById('imagePlaceholder');
const fileList = document.getElementById('fileList');

function setStatus(message) {
  statusEl.textContent = message;
}

async function pasteText() {
  setStatus('Reading text from clipboard...');
  try {
    const text = await Positron.clipboard.read_text();
    textInput.value = text || '';
    setStatus(text == null ? 'Clipboard does not contain text' : 'Text pasted');
  } catch (err) {
    setStatus('Failed to read text: ' + err.message);
  }
}

async function pasteImage() {
  setStatus('Reading image from clipboard...');
  try {
    const uri = await Positron.clipboard.read_image();
    if (uri) {
      imageThumb.src = uri;
      imageThumb.style.display = 'block';
      imagePlaceholder.style.display = 'none';
      setStatus('Image pasted');
    } else {
      imageThumb.style.display = 'none';
      imagePlaceholder.style.display = 'flex';
      setStatus('Clipboard does not contain an image');
    }
  } catch (err) {
    setStatus('Failed to read image: ' + err.message);
  }
}

async function pasteFiles() {
  setStatus('Reading files from clipboard...');
  try {
    const files = await Positron.clipboard.read_files();
    fileList.innerHTML = '';
    if (files.length === 0) {
      setStatus('Clipboard does not contain files');
      return;
    }
    files.forEach(file => {
      const li = document.createElement('li');
      li.textContent = file;
      fileList.appendChild(li);
    });
    setStatus(`${files.length} file(s) pasted`);
  } catch (err) {
    setStatus('Failed to read files: ' + err.message);
  }
}

// Intercept native paste events and route them through the Crystal Host.
window.addEventListener('paste', async (event) => {
  event.preventDefault();

  const types = event.clipboardData ? Array.from(event.clipboardData.types) : [];

  if (types.includes('text/plain') || types.includes('text')) {
    await pasteText();
    return;
  }

  if (types.some(t => t.startsWith('image/'))) {
    await pasteImage();
    return;
  }

  if (types.includes('Files')) {
    await pasteFiles();
    return;
  }

  // Fallback: try image, then text, then files.
  await pasteImage();
  if (imageThumb.style.display === 'block') return;

  await pasteText();
  if (textInput.value) return;

  await pasteFiles();
});
