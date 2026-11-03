// Camera demo frontend — plain web APIs on top of the host's
// permission grant: enumerateDevices for the picker, getUserMedia for
// capture, applyConstraints for the torch. The host side (the
// permission-request handler) reports every grant as
// `permission.requested`, logged at the bottom.

(function () {
  "use strict";

  var els = {
    device: document.getElementById("device"),
    toggle: document.getElementById("toggleBtn"),
    torch: document.getElementById("torchBtn"),
    status: document.getElementById("status"),
    video: document.getElementById("video"),
    stage: document.querySelector(".stage"),
    placeholder: document.getElementById("placeholder"),
    placeholderHint: document.getElementById("placeholderHint"),
    eventsLog: document.getElementById("eventsLog")
  };

  var stream = null;
  var torchOn = false;

  function setStatus(text, isError) {
    els.status.textContent = text;
    els.status.className = isError ? "status error" : "status";
  }

  function logEvent(text) {
    var line = document.createElement("div");
    line.textContent = "[" + new Date().toLocaleTimeString() + "] " + text;
    els.eventsLog.appendChild(line);
    els.eventsLog.scrollTop = els.eventsLog.scrollHeight;
  }

  // getUserMedia requires a secure context — the app:// scheme is one,
  // load_html pages are not. Show the honest reason instead of a
  // broken picker when mediaDevices is missing.
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    els.placeholderHint.textContent =
      "navigator.mediaDevices is unavailable (insecure context or " +
      "unsupported platform). Serve the frontend from a custom URI " +
      "scheme or localhost.";
    els.toggle.disabled = true;
    els.device.disabled = true;
    setStatus("mediaDevices unavailable", true);
  } else {
    refreshDevices();
  }

  // Labels arrive only after the first capture grant — refresh the
  // picker once a stream has opened.
  function refreshDevices() {
    navigator.mediaDevices.enumerateDevices().then(function (devices) {
      var cameras = devices.filter(function (d) { return d.kind === "videoinput"; });
      var selected = els.device.value;
      els.device.innerHTML = "";
      cameras.forEach(function (cam, i) {
        var opt = document.createElement("option");
        opt.value = cam.deviceId;
        opt.textContent = cam.label || ("Camera " + (i + 1));
        els.device.appendChild(opt);
      });
      if (selected && cameras.some(function (c) { return c.deviceId === selected; })) {
        els.device.value = selected;
      }
      if (!cameras.length) setStatus("No camera devices found", true);
    }).catch(function (e) {
      setStatus("enumerateDevices: " + e.name, true);
    });
  }

  function stop() {
    if (stream) stream.getTracks().forEach(function (t) { t.stop(); });
    stream = null;
    els.video.srcObject = null;
    els.stage.classList.remove("live");
    els.toggle.textContent = "Start";
    els.torch.hidden = true;
    torchOn = false;
    setStatus("Stopped.");
  }

  function start() {
    var constraints = { video: { width: { ideal: 1280 }, height: { ideal: 720 } } };
    var id = els.device.value;
    if (id) constraints.video.deviceId = { exact: id };

    navigator.mediaDevices.getUserMedia(constraints).then(function (s) {
      stream = s;
      els.video.srcObject = s;
      els.stage.classList.add("live");
      els.toggle.textContent = "Stop";

      var track = s.getVideoTracks()[0];
      var settings = track.getSettings();
      setStatus((track.label || "camera") + " · " +
        (settings.width || "?") + "x" + (settings.height || "?") +
        " @ " + (settings.frameRate || "?") + " fps");

      // Torch: only where the platform + device expose it.
      var caps = track.getCapabilities ? track.getCapabilities() : {};
      els.torch.hidden = !caps.torch;

      track.addEventListener("ended", function () {
        if (stream === s) { stop(); setStatus("Camera disconnected", true); }
      });

      refreshDevices();
    }).catch(function (e) {
      setStatus(e.name + ": " + e.message, true);
    });
  }

  els.toggle.addEventListener("click", function () {
    stream ? stop() : start();
  });

  els.device.addEventListener("change", function () {
    if (stream) start(); // live device switch
  });

  els.torch.addEventListener("click", function () {
    if (!stream) return;
    var track = stream.getVideoTracks()[0];
    torchOn = !torchOn;
    track.applyConstraints({ advanced: [{ torch: torchOn }] })
      .then(function () { els.torch.textContent = torchOn ? "Torch off" : "Torch"; })
      .catch(function (e) { setStatus("torch: " + e.name, true); });
  });

  // Every permission grant the host made on this page's behalf.
  if (window.Positron && Positron.on) {
    Positron.on("permission.requested", function (payload) {
      logEvent("granted: " + payload.type);
    });
  }
})();
