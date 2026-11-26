import 'package:sembast/sembast.dart';

import 'local_pos_database_native.dart'
    if (dart.library.js_interop) 'local_pos_database_web.dart'
    as platform;

/// Selects the device database or browser IndexedDB without changing callers.
Future<Database> openLocalPosDatabase() => platform.openLocalPosDatabase();
