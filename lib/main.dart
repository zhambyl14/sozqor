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

  // A widget that throws while building is replaced by Flutter's own error
  // widget, and in a release build that is an unlabelled grey rectangle. A
  // whole tab rendering as a grey rectangle is indistinguishable from the app
  // being broken, and it says nothing anybody can act on — not to the learner
  // looking at it and not to whoever is being told about it. This says what
  // happened and offers the one move that usually works.
  ErrorWidget.builder = (details) {
    // Also say it out loud. A release build strips the assertion text from
    // the screen, so without this a dead section is undiagnosable from the
    // one place it is ever seen — somebody's phone, over a remote console.
    debugPrint('SOZQOR RENDER FAILURE: ${details.exceptionAsString()}');
    return _BrokenSection(details: details);
  };

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

/// What a section that failed to build looks like.
///
/// Deliberately plain Material rather than the app's own kit: this has to
/// render when something in that kit is what threw, so it must not depend on
/// anything the app built. It keeps the failure contained to the block that
/// broke — the rest of the screen, and the navigation bar, still work.
class _BrokenSection extends StatelessWidget {
  final FlutterErrorDetails details;
  const _BrokenSection({required this.details});

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.maybeOf(context)?.platformBrightness ==
        Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      color: dark ? const Color(0xFF0E0D1A) : const Color(0xFFF7F6FB),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
            size: 34, color: dark ? const Color(0xFFFF5B5B) : const Color(0xFFC0392B)),
          const SizedBox(height: 12),
          Text(
            tr('Бұл бөлім ашылмады'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800,
              color: dark ? const Color(0xFFF3F1FF) : const Color(0xFF15132A)),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Қосымшаны қайта ашып көр. Басқа бөлімдер істеп тұр.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w600,
              color: dark ? const Color(0xFFA8A3C8) : const Color(0xFF565272)),
          ),
        ],
      ),
    );
  }
}
