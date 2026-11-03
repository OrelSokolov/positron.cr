// Pause/stop demo: demo.start fires an async_job (job id back
// immediately); demo.progress carries done/total; demo.pause/resume
// flip the token's pause flag; demo.stop cancels — demo.done arrives
// with cancelled=true and the units that managed to complete.

function $(id) { return document.getElementById(id); }

var total = 0;
var paused = false;
var running = false;

function set_state(state) {
  // state: 'idle' | 'running' | 'paused'
  var start = $('start');
  var pause = $('pause');
  var stop = $('stop');
  if (state === 'idle') {
    running = false; paused = false;
    start.disabled = false;
    pause.disabled = true; pause.textContent = 'Пауза';
    stop.disabled = true;
  } else if (state === 'running') {
    running = true; paused = false;
    start.disabled = true;
    pause.disabled = false; pause.textContent = 'Пауза';
    stop.disabled = false;
  } else { // paused
    running = true; paused = true;
    start.disabled = true;
    pause.disabled = false; pause.textContent = 'Продолжить';
    stop.disabled = false;
  }
}

function start() {
  if (running) return;
  var btn = $('start');
  var timeline = $('timeline');
  var result = $('result');
  btn.disabled = true;
  timeline.textContent = '';
  result.classList.remove('visible');
  $('bar').style.width = '0%';
  $('bar').classList.remove('paused');
  $('progress-label').textContent = 'стартуем…';
  set_state('running');

  Positron.call('demo.start', {}).then(function (r) {
    total = r.total;
    $('progress-label').textContent =
      'воркер #' + r.job + ' запущен: ' + r.total + ' с';
  }, function (err) {
    $('progress-label').textContent = 'ошибка запуска: ' + err;
    set_state('idle');
  });
}

Positron.on('demo.progress', function (p) {
  $('bar').style.width = (p.done / total * 100) + '%';
  $('progress-label').textContent =
    'прошло ' + p.done + ' из ' + p.total + ' с';
  $('timeline').insertAdjacentHTML(
    'beforeend',
    '<span>t=' + p.done + '</span> '
  );
});

Positron.on('demo.done', function (p) {
  var result = $('result');
  var label = $('progress-label');
  set_state('idle');
  if (p.cancelled) {
    $('bar').classList.add('cancelled');
    label.textContent =
      'остановлено на ' + p.done + ' из ' + p.total + ' с';
    result.textContent =
      'demo.done: cancelled=true, done=' + p.done +
      ', elapsed_ms=' + p.elapsed_ms;
  } else {
    $('bar').style.width = '100%';
    label.textContent = 'готово: ' + p.done + ' с';
    result.textContent =
      'demo.done: cancelled=false, done=' + p.done +
      ', elapsed_ms=' + p.elapsed_ms;
  }
  result.classList.add('visible');
});

$('start').onclick = start;

$('pause').onclick = function () {
  var command = paused ? 'demo.resume' : 'demo.pause';
  Positron.call(command, {}).then(function (r) {
    set_state(r.paused ? 'paused' : 'running');
    $('bar').classList.toggle('paused', r.paused);
    $('progress-label').textContent = r.paused
      ? 'пауза (' + $('progress-label').textContent + ')'
      : $('progress-label').textContent.replace(/^пауза \((.*)\)$/, '$1');
  }, function (err) {
    $('progress-label').textContent = 'ошибка: ' + err;
  });
};

$('stop').onclick = function () {
  Positron.call('demo.stop', {}).then(function () {
    $('progress-label').textContent = 'останавливаем…';
  });
};
