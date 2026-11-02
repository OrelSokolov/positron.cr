// Async progress demo: the start command resolves immediately; progress
// arrives as `demo.progress` events (elapsed seconds t and t²), the final
// result as `demo.done`. Ping proves the host answers mid-job.

function $(id) { return document.getElementById(id); }

var seconds = 10;
var running = false;

function start() {
  if (running) return;
  var btn = $('start');
  var timeline = $('timeline');
  var result = $('result');
  btn.disabled = true;
  timeline.textContent = '';
  result.classList.remove('visible');
  $('bar').style.width = '0%';
  $('progress-label').textContent = 'стартуем…';

  Positron.call('demo.start', { seconds: seconds }).then(function (r) {
    $('progress-label').textContent =
      'воркер #' + r.job + ' запущен: ' + seconds + ' с';
  }, function (err) {
    $('progress-label').textContent = 'ошибка запуска: ' + err;
    btn.disabled = false;
  });
}

Positron.on('demo.progress', function (p) {
  running = true;
  $('bar').style.width = (p.elapsed / seconds * 100) + '%';
  $('progress-label').textContent =
    'прошло ' + p.elapsed + ' с, ' + p.elapsed + '² = ' + p.square;
  $('timeline').insertAdjacentHTML(
    'beforeend',
    '<span>t=' + p.elapsed + ' → ' + p.square + '</span> '
  );
});

Positron.on('demo.done', function (p) {
  running = false;
  var result = $('result');
  $('bar').style.width = '100%';
  $('progress-label').textContent =
    'готово: ' + p.elapsed + ' с, итог ' + p.elapsed + '² = ' + p.square;
  result.textContent =
    'demo.done: elapsed=' + p.elapsed + ', square=' + p.square;
  result.classList.add('visible');
  $('start').disabled = false;
});

$('start').onclick = start;

$('ping').onclick = function () {
  var out = $('progress-label');
  var label = out.textContent;
  Positron.call('demo.ping', {}).then(function (r) {
    out.textContent = label + ' — pong: ' + r.pong;
  });
};
