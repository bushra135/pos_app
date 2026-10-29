// Browser-owned video avoids Flutter's embedded video rendering on iPhone.
window.ShopPadBrowserScanner = {
  close() { this._close?.(); },
  position(bounds) {
    this._bounds = JSON.parse(bounds);
    this._updateBounds?.();
  },
  open(onBarcode = null, initialSummary = '') {
    if (document.getElementById('shoppad-browser-scanner')) return Promise.resolve(null);
    document.activeElement?.blur?.();
    const continuous = typeof onBarcode === 'function';
    const inline = continuous && !!this._bounds;
    return new Promise(resolve => {
      let closed = false, stream, reader, starting = false, processing = false;
      let lastAddedCode;
      const lastSeen = new Map();
      const pending = [];
      const overlay = document.createElement('section');
      overlay.id = 'shoppad-browser-scanner';
      overlay.lang = 'en';
      overlay.dir = 'ltr';
      overlay.setAttribute('role', 'dialog');
      overlay.setAttribute('aria-label', continuous ? 'Scan and sell' : 'Scan product barcode');
      overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#102d4b;color:white;display:flex;flex-direction:column;padding:env(safe-area-inset-top) 16px env(safe-area-inset-bottom);font:16px system-ui;';
      const updateBounds = () => {
        if (!inline) return;
        const box = window.ShopPadBrowserScanner._bounds;
        if (!box) return;
        Object.assign(overlay.style, {
          inset:'auto', left:box.left+'px', top:box.top+'px',
          width:box.width+'px', height:box.height+'px', padding:'0',
          boxSizing:'border-box', overflow:'hidden', background:'#102d4b'
        });
      };
      window.ShopPadBrowserScanner._updateBounds = updateBounds;
      updateBounds();
      const header = document.createElement('div');
      header.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:16px 0;';
      const title = document.createElement('strong');
      title.textContent = continuous ? 'Scan & sell' : 'Scan product barcode';
      function button(label) {
        const result = document.createElement('button');
        result.textContent = label;
        result.style.cssText = 'padding:12px 16px;margin:4px 0;border:0;border-radius:12px;background:#e5f0fd;color:#102d4b;font:inherit;';
        return result;
      }
      const close = button('Close');
      const video = document.createElement('video');
      video.muted = true; video.defaultMuted = true; video.playsInline = true;
      for (const flag of ['muted','playsinline','webkit-playsinline']) video.setAttribute(flag, '');
      video.style.cssText = inline
        ? 'position:absolute;inset:0;width:100%;height:100%;object-fit:cover;background:black;'
        : 'width:100%;min-height:0;flex:1;object-fit:contain;background:black;';
      const message = document.createElement('p');
      message.textContent = 'Starting camera...';
      message.style.cssText = 'text-align:center;white-space:pre-wrap;margin:8px 0;';
      const summary = document.createElement('strong');
      summary.textContent = initialSummary;
      summary.style.cssText = 'text-align:center;padding:8px;';
      if (inline) message.style.cssText = 'position:absolute;bottom:0;left:0;right:0;margin:0;padding:8px;background:#102d4bd9;font-size:12px;white-space:pre-wrap;text-align:center;';
      const retry = button('Start / retry camera');
      if (inline) retry.style.cssText += 'position:absolute;top:12px;left:12px;right:12px;';
      const repeat = button('Add same item');
      repeat.disabled = true;
      const review = button('Review sale');
      const stop = () => {
        try { reader?.reset(); } catch (_) {}
        stream?.getTracks().forEach(track => track.stop());
        stream = undefined; video.srcObject = null;
      };
      const finish = value => {
        if (closed) return;
        closed = true; pending.length = 0;
        stop(); overlay.remove();
        window.ShopPadBrowserScanner._bounds = null;
        window.ShopPadBrowserScanner._updateBounds = null;
        if (window.ShopPadBrowserScanner._close === dismiss) window.ShopPadBrowserScanner._close = null;
        resolve(value);
      };
      const dismiss = () => finish(null);
      window.ShopPadBrowserScanner._close = dismiss;
      async function processQueue() {
        if (processing || closed) return;
        processing = true; review.disabled = true; repeat.disabled = true;
        try {
          while (pending.length && !closed) {
            const code = pending.shift();
            message.textContent = 'Adding item...';
            try {
              const response = JSON.parse(await onBarcode(code));
              if (closed) break;
              message.textContent = response.message;
              summary.textContent = response.summary;
              lastAddedCode = response.ok ? code : null;
            } catch (_) {
              if (!closed) message.textContent = 'Could not add item. Close the camera and check the sale.';
              lastAddedCode = null;
            }
          }
        } finally {
          processing = false;
          if (!closed) { review.disabled = false; repeat.disabled = !lastAddedCode; }
        }
      }
      function detect(result) {
        if (!result || closed) return;
        const code = result.getText();
        if (!continuous) { finish(code); return; }
        const now = Date.now();
        const duplicate = lastSeen.has(code) && now - lastSeen.get(code) < 1600;
        lastSeen.set(code, now);
        if (lastSeen.size > 128) lastSeen.delete(lastSeen.keys().next().value);
        if (duplicate || pending.length >= 12) return;
        pending.push(code); processQueue();
      }
      async function start() {
        if (closed || starting) return;
        starting = true; retry.disabled = true;
        if (inline) retry.style.display = 'none';
        stop(); message.textContent = 'Starting camera...';
        try {
          if (!navigator.mediaDevices?.getUserMedia) throw new Error('Open this HTTPS link in Safari to use the camera.');
          if (!window.ZXing) throw new Error('Barcode reader failed to load. Reload the page.');
          const acquired = await navigator.mediaDevices.getUserMedia({audio:false,video:{facingMode:{ideal:'environment'}}});
          if (closed) { acquired.getTracks().forEach(track => track.stop()); return; }
          stream = acquired;
          reader = new window.ZXing.BrowserMultiFormatReader();
          await reader.decodeFromStream(stream, video, detect);
          if (!closed && inline) retry.style.display = 'none';
          if (!closed) message.textContent = inline
            ? 'Point at a barcode. Use + in the cart for identical items.'
            : continuous ? 'Scan items continuously. Use Add same item for identical products.'
            : 'Hold the barcode steady in front of the back camera.';
        } catch (error) {
          stop();
          if (!closed && inline) retry.style.display = '';
          if (!closed) message.textContent = 'Camera could not start: ' + (error.name || '') + ' ' + error.message + '\nAllow camera access, close other camera tabs, then tap retry.';
        } finally { starting = false; if (!closed) retry.disabled = false; }
      }
      close.onclick = dismiss; retry.onclick = start;
      repeat.onclick = () => {
        if (!processing && lastAddedCode) { pending.push(lastAddedCode); processQueue(); }
      };
      review.onclick = () => { if (!processing) finish('review'); };
      header.append(title, close);
      if (!inline) overlay.append(header);
      overlay.append(video, message);
      if (continuous && !inline) overlay.append(summary, repeat, review);
      overlay.append(retry);
      document.body.append(overlay);
      start();
    });
  }
};
