// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/i18n/l10n.dart';
import 'firebase_options.dart';
import 'services/local_dictionary.dart';
import 'services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  // The interface language is restored before the first frame so the splash
  // screen already reads in the right language.
  await AppLang.restore();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  // The offline half of the dictionary — loaded before the first frame so
  // translation works even with no connection.
  await LocalDictionary.instance.load();

  // Firebase is used only for push; the app must still run if it fails.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    unawaitedStart();
  } catch (_) {/* push simply stays off */}

  runApp(const ProviderScope(child: SozQorApp()));
}

void unawaitedStart() {
  PushService.instance.start();
}
