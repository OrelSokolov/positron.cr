// 10 workers, tqdm-style lines: percent, done/total, elapsed<ETA,
// smoothed rate. One colored bar per worker (color by worker id),
// plus an overall bar whose ETA is remaining units over the sum of
// the live workers' current rates.

function $(id) { return document.getElementById(id); }

// 10 distinct colors, one per worker.
var PALETTE = [
  '#e6194b', '#f58231', '#d4c722', '#7fbf3f', '#3cb44b',
  '#2ec4b5', '#42a5f5', '#4363d8', '#911eb4', '#f032e6'
];

var FLEET_SIZE = 10;
var running = false;
var startAt = 0;
// Latest snapshot per worker id (done/rate/finished), for the overall bar.
var latest = {};

function fmtSecs(ms) {
  var s = ms / 1000;
  return (s >= 10 ? s.toFixed(0) : s.toFixed(1)) + 's';
}

// tqdm-style text bar: 42%|█████████░░░░| 42/100 [4.2s<5.8s, 10.0u/s]
function tqdmLine(p) {
  var width = 22;
  var filled = Math.round(p.percent / 100 * width);
  var bar = '';
  for (var i = 0; i < width; i++) bar += i < filled ? '█' : '░';
  var tail = p.percent >= 100
    ? fmtSecs(p.elapsed_ms)
    : fmtSecs(p.elapsed_ms) + '<' + fmtSecs(p.eta_ms);
  return pad3(p.percent) + '%|' + bar + '| ' + p.done + '/' + p.total +
    ' [' + tail + ', ' + p.rate.toFixed(1) + ' ед/с]';
}

function pad3(n) { return ('  ' + n).slice(-3); }

function workerRow(id, total, rateHint) {
  var color = PALETTE[(id - 1) % PALETTE.length];
  var row = document.createElement('div');
  row.className = 'worker';
  row.id = 'w' + id;
  row.innerHTML =
    '<div class="head"><span class="dot" style="background:' + color + '"></span>' +
    'воркер ' + id +
    ' <span class="mono rate-hint">~' + rateHint.toFixed(1) + ' ед/с</span></div>' +
    '<div class="progress-bar"><div class="fill" style="background:' + color + '"></div></div>' +
    '<div class="stats mono">…</div>';
  $('workers').appendChild(row);
}

function updateOverall() {
  var totalUnits = 0, doneUnits = 0, liveRate = 0;
  Object.keys(latest).forEach(function (id) {
    var p = latest[id];
    totalUnits += p.total;
    doneUnits += p.done;
    if (!p.finished) liveRate += p.rate;
  });
  var percent = totalUnits ? doneUnits / totalUnits * 100 : 0;
  var remaining = totalUnits - doneUnits;
  var eta = liveRate > 0 ? remaining / liveRate * 1000 : 0;

  $('overall-bar').style.width = percent + '%';
  $('overall-text').textContent =
    Math.round(percent) + '% — ' + doneUnits + '/' + totalUnits +
    ' ед., ETA ' + fmtSecs(eta) +
    ' (' + liveRate.toFixed(1) + ' ед/с по живым воркерам)';
}

$('start').onclick = function () {
  if (running) return;
  running = true;
  $('start').disabled = true;
  $('workers').innerHTML = '';
  latest = {};
  $('overall').classList.remove('hidden');

  Positron.call('demo.start', {}).catch(function (err) {
    $('overall-text').textContent = 'ошибка запуска: ' + err;
    running = false;
    $('start').disabled = false;
  });
};

Positron.on('demo.worker.started', function (w) {
  startAt = startAt || performance.now();
  workerRow(w.id, w.total, w.rate);
});

Positron.on('demo.worker.progress', function (p) {
  var row = $('w' + p.id);
  if (!row) return;
  row.querySelector('.fill').style.width = p.percent + '%';
  row.querySelector('.stats').innerHTML = tqdmLine(p);
  latest[p.id] = p;
  updateOverall();
});

Positron.on('demo.worker.done', function (d) {
  var row = $('w' + d.id);
  if (row) {
    row.classList.add('finished');
    row.querySelector('.stats').innerHTML += ' <span class="done-mark">✓ готово за ' +
      fmtSecs(d.elapsed_ms) + '</span>';
  }
  if (latest[d.id]) latest[d.id].finished = true;
  updateOverall();

  // Fleet complete when every worker has reported finished.
  var all = Object.keys(latest).length === FLEET_SIZE &&
    Object.keys(latest).every(function (id) { return latest[id].finished; });
  if (all) {
    running = false;
    $('start').disabled = false;
  }
});
