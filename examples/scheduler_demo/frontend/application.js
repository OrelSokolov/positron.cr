// Scheduler demo: buttons switch to "думаю…", await the host promise,
// then show the result. The host tick age is the freeze indicator —
// JS timers keep running (separate WebKit process) even when the
// Crystal loop is blocked, host events do not.

function $(id) { return document.getElementById(id); }

// Local clock — keeps ticking even while the host is frozen.
setInterval(function () {
  $('clock').textContent = new Date().toLocaleTimeString('ru-RU');
}, 100);

// Host heartbeat age. Updated both by the event and by a local
// interval, so the age grows visibly when ticks stop arriving.
var lastTick = null;
if (window.Positron) {
  Positron.on('demo.tick', function (payload) {
    lastTick = performance.now();
    $('tick').textContent = 'только что (' + payload.t + ')';
  });
}
setInterval(function () {
  if (lastTick === null) return;
  var age = Math.round(performance.now() - lastTick);
  if (age > 2000) {
    $('tick').textContent = '⚠ нет ' + (age / 1000).toFixed(1) + ' с — хост заблокирован';
  }
}, 250);

function run(btnId, outId, command) {
  var btn = $(btnId), out = $(outId);
  var label = btn.textContent;
  btn.disabled = true;
  btn.textContent = 'думаю…';
  out.textContent = 'запущено…';
  var t0 = performance.now();
  Positron.call(command, { seconds: 10 }).then(function (r) {
    var hostMs = r && r.ms;
    out.textContent = 'итераций: ' + (r ? r.value : '?') +
                      ', хост: ' + hostMs + ' мс, JS: ' +
                      Math.round(performance.now() - t0) + ' мс';
    btn.disabled = false;
    btn.textContent = label;
  }, function (err) {
    out.textContent = 'ошибка: ' + err;
    btn.disabled = false;
    btn.textContent = label;
  });
}

$('freeze').onclick = function () { run('freeze', 'freeze-out', 'demo.freeze'); };
$('busy').onclick = function () { run('busy', 'busy-out', 'demo.busy'); };
$('isolated').onclick = function () { run('isolated', 'isolated-out', 'demo.isolated'); };
