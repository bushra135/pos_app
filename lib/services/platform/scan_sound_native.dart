import 'package:audioplayers/audioplayers.dart';

// Keep short, preloaded players so rapid scans do not stop the previous beep.
Future<AudioPool>? _pool;
Future<void> playScanSound() async {
  try {
    final pool = await (_pool ??= AudioPool.createFromAsset(
      path: 'sounds/beep.mp3',
      maxPlayers: 4,
    ));
    await pool.start();
  } catch (_) {
    _pool = null;
    rethrow;
  }
}
