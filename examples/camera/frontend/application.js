// Camera demo frontend — two capture modes picked at runtime:
//   - "web": plain web APIs on top of the host's permission grant
//     (enumerateDevices, getUserMedia, applyConstraints for the torch).
//   - "native": the host camera plugin (real on iOS, where WKWebView's
//     getUserMedia runs in XPC processes no injection can reach) —
//     start/stop through Positron.camera.*, frames pulled from the
//     app:// scheme (/native-frame: 12-byte header + RGBA) and drawn
//     onto a canvas.

(function () {
  "use strict";

  var els = {
    device: document.getElementById("device"),
    toggle: document.getElementById("toggleBtn"),
    torch: document.getElementById("torchBtn"),
    status: document.getElementById("status"),
    video: document.getElementById("video"),
    native: document.getElementById("nativeVideo"),
    stage: document.querySelector(".stage"),
    placeholder: document.getElementById("placeholder"),
    placeholderHint: document.getElementById("placeholderHint"),
    eventsLog: document.getElementById("eventsLog")
  };

  var stream = null;
  var torchOn = false;

  // "web" until the host plugin answers supported() — set once at boot.
  var mode = "web";

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

  function init() {
    if (window.Positron && Positron.camera && Positron.camera.supported) {
      Positron.camera.supported().then(function (ok) {
        mode = ok ? "native" : "web";
        refreshDevices();
      }).catch(function () {
        mode = "web";
        webCheckAndRefresh();
      });
    } else {
      webCheckAndRefresh();
    }
  }

  // getUserMedia requires a secure context — the app:// scheme is one,
  // load_html pages are not. Show the honest reason instead of a
  // broken picker when mediaDevices is missing.
  function webCheckAndRefresh() {
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
  }

  function refreshDevices() {
    if (mode === "native") {
      Positron.camera.devices().then(function (devices) {
        fillDevicePicker(devices, function (i) { return "Camera " + (i + 1); });
        if (!devices.length) setStatus("No camera devices found", true);
      }).catch(function (e) {
        setStatus("camera.devices: " + e.message, true);
      });
      return;
    }
    // Labels arrive only after the first capture grant in web mode.
    navigator.mediaDevices.enumerateDevices().then(function (devices) {
      var cameras = devices.filter(function (d) { return d.kind === "videoinput"; });
      fillDevicePicker(
        cameras.map(function (c) { return { id: c.deviceId, label: c.label }; }),
        function (i) { return "Camera " + (i + 1); });
      if (!cameras.length) setStatus("No camera devices found", true);
    }).catch(function (e) {
      setStatus("enumerateDevices: " + e.name, true);
    });
  }

  function fillDevicePicker(entries, fallbackLabel) {
    var selected = els.device.value;
    els.device.innerHTML = "";
    entries.forEach(function (entry, i) {
      var opt = document.createElement("option");
      opt.value = entry.id;
      opt.textContent = entry.label || fallbackLabel(i);
      els.device.appendChild(opt);
    });
    if (selected && entries.some(function (e) { return e.id === selected; })) {
      els.device.value = selected;
    }
  }

  // --- web mode ---

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

  // --- native mode ---

  var nativeRunning = false;
  var nativeFetching = false;
  var nativeSeq = 0;
  var nativeFrames = 0;

  function nativeStop() {
    nativeRunning = false;
    Positron.camera.stop().catch(function () {});
    els.native.hidden = true;
    els.video.hidden = false;
    els.stage.classList.remove("live");
    els.toggle.textContent = "Start";
    setStatus("Stopped.");
  }

  function nativeStart() {
    var id = els.device.value;
    Positron.camera.start({ deviceId: id || null, width: 1280, height: 720 })
      .then(function (res) {
        if (!res || !res.ok) {
          setStatus("native: " + (res && res.error || "start failed"), true);
          return;
        }
        nativeRunning = true;
        nativeFrames = 0;
        els.video.hidden = true;
        els.native.hidden = false;
        els.stage.classList.add("live");
        els.toggle.textContent = "Stop";
        setStatus("native camera · waiting for frames…");
        pump();
      })
      .catch(function (e) {
        setStatus("camera.start: " + e.message, true);
      });
  }

  // Pull the latest host-side frame; one fetch in flight at a time.
  function pump() {
    if (!nativeRunning || nativeFetching) return;
    nativeFetching = true;
    nativeSeq++;
    fetch("app://camera/native-frame?n=" + nativeSeq)
      .then(function (r) { return r.arrayBuffer(); })
      .then(function (buf) {
        nativeFetching = false;
        if (buf.byteLength > 12 && nativeRunning) {
          var dv = new DataView(buf);
          var w = dv.getUint32(4, true);
          var h = dv.getUint32(8, true);
          if (w > 0 && h > 0 && buf.byteLength >= 12 + w * h * 4) {
            var cv = els.native;
            if (cv.width !== w || cv.height !== h) { cv.width = w; cv.height = h; }
            cv.getContext("2d").putImageData(
              new ImageData(new Uint8ClampedArray(buf, 12, w * h * 4), w, h), 0, 0);
            nativeFrames++;
            if (nativeFrames === 1) setStatus("native camera · " + w + "×" + h);
          }
        }
        if (nativeRunning) setTimeout(pump, 33);
      })
      .catch(function () {
        nativeFetching = false;
        if (nativeRunning) setTimeout(pump, 100);
      });
  }

  // --- wiring ---

  els.toggle.addEventListener("click", function () {
    if (mode === "native") {
      nativeRunning ? nativeStop() : nativeStart();
    } else {
      stream ? stop() : start();
    }
  });

  els.device.addEventListener("change", function () {
    if (mode === "native") {
      if (nativeRunning) nativeStart(); // live device switch
    } else if (stream) {
      start();
    }
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

  init();
})();
