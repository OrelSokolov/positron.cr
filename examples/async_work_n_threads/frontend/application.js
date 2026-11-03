// N workers demo: demo.start {workers: n} splits one CPU-bound job
// between n parallel workers; demo.progress polls the shared atomic
// counter; demo.done carries elapsed time and the order-independent
// checksum. The runs table compares elapsed/speedup across worker
// counts (speedup vs the fastest 1-worker run so far).

function $(id) { return document.getElementById(id); }

var total = 0;
var running = false;
var paused = false;
var lastWorkers = 0;
var runNo = 0;
var baselineMs = null;  // fastest 1-worker run
var progressT0 = 0;

function set_state(state) {
  var start = $('start');
  var pause = $('pause');
  var stop = $('stop');
  running = state !== 'idle';
  paused = state === 'paused';
  start.disabled = running;
  pause.disabled = !running;
  pause.textContent = paused ? 'Продолжить' : 'Пауза';
  stop.disabled = !running;
  $('workers').disabled = running;
}

function start() {
  if (running) return;
  var rows = $('runs').querySelector('tbody');
  if (runNo === 0) rows.textContent = '';
  $('bar').style.width = '0%';
  $('bar').classList.remove('paused', 'cancelled');
  $('progress-label').textContent = 'стартуем…';
  set_state('running');

  var workers = parseInt($('workers').value, 10);
  Positron.call('demo.start', { workers: workers }).then(function (r) {
    total = r.total;
    lastWorkers = r.workers;
    progressT0 = performance.now();
    $('progress-label').textContent =
      'работают ' + r.workers + ' воркера(ов): 0 / ' + r.total;
  }, function (err) {
    $('progress-label').textContent = 'ошибка запуска: ' + err;
    set_state('idle');
  });
}

Positron.on('demo.progress', function (p) {
  var percent = p.done / p.total * 100;
  $('bar').style.width = percent + '%';
  var elapsed = (performance.now() - progressT0) / 1000;
  var rate = elapsed > 0 ? (p.done / 1e6 / elapsed).toFixed(0) : '—';
  $('progress-label').textContent =
    (p.paused ? 'пауза — ' : '') +
    p.done.toLocaleString('ru-RU') + ' / ' + p.total.toLocaleString('ru-RU') +
    ' (' + percent.toFixed(1) + '%, ' + rate + ' Mюнит/с)';
});

Positron.on('demo.done', function (p) {
  set_state('idle');
  var elapsedS = p.elapsed_ms / 1000;
  var rate = elapsedS > 0 ? (p.done / 1e6 / elapsedS).toFixed(0) : '—';
  var speedup = '—';

  if (p.workers === 1) {
    if (baselineMs === null || p.elapsed_ms < baselineMs) baselineMs = p.elapsed_ms;
  }
  if (baselineMs !== null && !p.cancelled) {
    speedup = '×' + (baselineMs / p.elapsed_ms).toFixed(2);
  }

  runNo += 1;
  $('runs').querySelector('tbody').insertAdjacentHTML('beforeend',
    '<tr>' +
    '<td>' + runNo + '</td>' +
    '<td>' + p.workers + '</td>' +
    '<td>' + elapsedS.toFixed(2) + '</td>' +
    '<td>' + rate + '</td>' +
    '<td>' + speedup + '</td>' +
    '<td class="mono">' + (p.cancelled
        ? 'стоп на ' + (p.done / 1e6).toFixed(0) + 'M'
        : 'checksum ' + p.checksum) + '</td>' +
    '</tr>'
  );

  if (p.cancelled) {
    $('bar').classList.add('cancelled');
    $('progress-label').textContent =
      'остановлено: ' + p.done.toLocaleString('ru-RU') + ' юнитов за ' +
      elapsedS.toFixed(2) + ' с';
  } else {
    $('bar').style.width = '100%';
    $('progress-label').textContent =
      'готово за ' + elapsedS.toFixed(2) + ' с (' + p.workers +
      ' воркера(ов), ' + rate + ' Mюнит/с' +
      (speedup !== '—' ? ', ' + speedup : '') + ')';
  }
});

$('start').onclick = start;

$('pause').onclick = function () {
  var command = paused ? 'demo.resume' : 'demo.pause';
  Positron.call(command, {}).then(function (r) {
    set_state(r.paused ? 'paused' : 'running');
    $('bar').classList.toggle('paused', r.paused);
  }, function (err) {
    $('progress-label').textContent = 'ошибка: ' + err;
  });
};

$('stop').onclick = function () {
  Positron.call('demo.stop', {}).then(function () {
    $('progress-label').textContent = 'останавливаем…';
  });
};
