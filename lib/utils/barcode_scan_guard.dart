/// Latches a barcode until the camera has stopped reporting it for a quiet period.
/// Unlike a fixed debounce, a continuously visible label stays blocked.
class BarcodeScanGuard {
  String? heldCode;

  bool accept(String code) {
    if (code.isEmpty || code == heldCode) return false;
    heldCode = code;
    return true;
  }

  void release() => heldCode = null;
}
