/* رسم QR على canvas + ماسح كاميرا — QR rendering + camera scanner.
   يستخدم BarcodeDetector الأصلي إن توفّر، وإلا jsQR. مع مسار لصق بديل. */
(function (global) {
  "use strict";
  const qrcode = global.qrcode; // vendor/qrcode.js
  const jsQR = global.jsQR;     // vendor/jsQR.js

  function renderQR(canvas, text, dark) {
    const qr = qrcode(0, "M");        // 0 = أصغر نسخة تتسع للبيانات
    qr.addData(text);
    qr.make();
    const count = qr.getModuleCount();
    const size = canvas.width;
    const cell = Math.floor(size / (count + 4));
    const off = Math.floor((size - cell * count) / 2);
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, size, size);
    ctx.fillStyle = dark || "#0d1b2a";
    for (let r = 0; r < count; r++)
      for (let c = 0; c < count; c++)
        if (qr.isDark(r, c)) ctx.fillRect(off + c * cell, off + r * cell, cell, cell);
  }

  class Scanner {
    constructor(video, canvas) {
      this.video = video;
      this.canvas = canvas;
      this.stream = null;
      this.raf = null;
      this.detector = null;
      if ("BarcodeDetector" in global) {
        try { this.detector = new global.BarcodeDetector({ formats: ["qr_code"] }); } catch (e) {}
      }
    }
    async start(onResult, onError) {
      try {
        this.stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "environment" }, audio: false,
        });
        this.video.setAttribute("playsinline", "true");
        this.video.srcObject = this.stream;
        await this.video.play();
        this._tick(onResult);
      } catch (e) {
        if (onError) onError(e);
      }
    }
    async _tick(onResult) {
      if (!this.stream) return;
      let result = null;
      if (this.video.readyState >= 2 && this.video.videoWidth) {
        try {
          if (this.detector) {
            const codes = await this.detector.detect(this.video);
            if (codes && codes.length) result = codes[0].rawValue;
          } else if (jsQR) {
            const w = this.video.videoWidth, h = this.video.videoHeight;
            this.canvas.width = w; this.canvas.height = h;
            const ctx = this.canvas.getContext("2d");
            ctx.drawImage(this.video, 0, 0, w, h);
            const img = ctx.getImageData(0, 0, w, h);
            const code = jsQR(img.data, w, h, { inversionAttempts: "dontInvert" });
            if (code) result = code.data;
          }
        } catch (e) { /* تجاهل إطاراً واصل المسح */ }
      }
      if (result) { onResult(result); return; }
      this.raf = requestAnimationFrame(() => this._tick(onResult));
    }
    stop() {
      if (this.raf) cancelAnimationFrame(this.raf);
      this.raf = null;
      if (this.stream) { this.stream.getTracks().forEach((t) => t.stop()); this.stream = null; }
      try { this.video.srcObject = null; } catch (e) {}
    }
  }

  global.WaslaQR = { renderQR, Scanner };
})(typeof globalThis !== "undefined" ? globalThis : this);
