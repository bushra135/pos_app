// mobile_scanner 6 calls attachStreamToVideo directly, bypassing ZXing's
// prepareVideoElement. Set iPhone playback flags before attaching the stream.
(() => {
  const prototype = window.ZXing?.BrowserCodeReader?.prototype;
  if (!prototype) return;
  const attach = prototype.attachStreamToVideo;
  prototype.attachStreamToVideo = function (stream, video) {
    video.muted = true;
    video.defaultMuted = true;
    video.playsInline = true;
    video.setAttribute('muted', '');
    video.setAttribute('playsinline', '');
    video.setAttribute('webkit-playsinline', '');
    return attach.call(this, stream, video);
  };
})();
