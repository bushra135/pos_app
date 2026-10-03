import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'firebase_options.dart';
import 'screens/auth/auth_wrapper.dart';

/// Initialize Firebase before building screens that depend on its services.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (kIsWeb) {
    // Mobile platforms persist sessions automatically; this setting is web-only.
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  runApp(const MyApp());
}

/// Connect the shared theme to authentication and role-based navigation.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AuthWrapper(),
    );
  }
}
