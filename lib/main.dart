import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'firebase_options.dart';
import 'screens/auth/auth_wrapper.dart';
import 'services/local_pos_store.dart';
import 'services/sale_gateway.dart';
import 'services/sale_sync_service.dart';

/// Initialize Firebase before building screens that depend on its services.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  if (kIsWeb) {
    // Mobile platforms persist sessions automatically; this setting is web-only.
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  final sync = SaleSyncService(
    store: await LocalPosStore.open(),
    gateway: FirestoreSaleGateway(),
    currentUserId: () => FirebaseAuth.instance.currentUser?.uid,
  );
  SaleSyncService.maybeInstance = sync;
  sync.start();
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user == null) sync.clearSession();
  });

  runApp(const ShopPadApp());
}

/// Connect the shared theme to authentication and role-based navigation.
class ShopPadApp extends StatelessWidget {
  const ShopPadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AuthWrapper(),
    );
  }
}
