// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'data/supa.dart';
import 'features/arena/battle_invite_overlay.dart';
import 'features/auth/login_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/root_shell.dart';
import 'features/shell/splash_screen.dart';
import 'providers.dart';

class SozQorApp extends ConsumerWidget {
  const SozQorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeProvider);
    // Watching the language here keeps the whole tree — including the built-in
    // Material copy inside pickers and text menus — in step with the switch.
    final lang = ref.watch(langProvider);
    return MaterialApp(
      title: 'SozQor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      locale: Locale(lang),
      supportedLocales: const [Locale('kk'), Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 4.0 drops the drifting aurora: the page is a single quiet off-white so
      // the one dark focus block on each screen is the loudest thing on it.
      // Text never scales past 1.2× — the answer tiles and the nav bar are
      // laid out tightly enough that anything larger would clip.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        // The invitation banner lives HERE, above the navigator, rather than
        // inside the tab shell. Wrapped around the tabs it could not appear
        // over a pushed route — so a friend calling while you were in the
        // word bank, the shop or a story chapter reached nothing at all, and
        // the requirement is that it reaches you whatever screen you are on.
        child: BattleInviteOverlay(child: child ?? const SizedBox.shrink()),
      ),
      home: const AuthGate(),
    );
  }
}

/// Decides what the user sees. Nobody is asked to sign in first: a fresh
/// visitor gets a guest session automatically and lands in onboarding, where
/// they pick a name, an avatar and a level. Registering is offered later, and
/// skipping it simply keeps them a guest.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  /// The signup trigger writes the profile row a moment after the session
  /// appears. Retry a bounded number of times instead of spinning forever.
  static const _maxRetries = 6;
  int _retries = 0;

  bool _startingGuest = false;
  String? _guestError;

  /// Set once a session that used to exist has gone away and could not be
  /// refreshed back. Nothing may silently mint a replacement guest while this
  /// is true — see [_openSession].
  bool _sessionLost = false;

  void _retryProfile() {
    if (_retries >= _maxRetries) return;
    _retries++;
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) ref.invalidate(myProfileProvider);
    });
  }

  /// Decides what a missing session means, and acts on it.
  ///
  /// Supabase revokes a session outright when a refresh-token rotation races
  /// with itself, so a learner who never signed out can land here mid-use.
  /// Blindly opening a guest session at that point is the worst possible
  /// answer: it hands them a brand-new empty account and orphans every word,
  /// XP point and streak the old one still holds server-side. So a device
  /// that has held a session before gets a refresh attempt first, and if that
  /// truly fails it gets the sign-in screen — never a silent reset. Only a
  /// genuinely first-time device goes straight to a guest session.
  Future<void> _openSession() async {
    if (_startingGuest) return;
    _startingGuest = true;
    if (_guestError != null && mounted) setState(() => _guestError = null);
    try {
      final auth = ref.read(authRepoProvider);
      final lastUid = await auth.lastKnownUid();

      if (lastUid != null) {
        if (await auth.tryRecoverSession()) return;
        if (mounted) setState(() => _sessionLost = true);
        return;
      }

      await auth.signInAsGuest();
    } catch (e) {
      if (mounted) setState(() => _guestError = humanError(e));
    } finally {
      _startingGuest = false;
    }
  }

  /// Deliberately starts over as a guest after an unrecoverable session, with
  /// the learner having seen what it costs.
  Future<void> _startFreshGuest() async {
    final auth = ref.read(authRepoProvider);
    await auth.forgetSession();
    if (mounted) setState(() => _sessionLost = false);
    await _openSession();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    // "Тіркелмей-ақ ойнау" on LoginScreen only flips showLoginProvider back
    // to false — it has no way to reach _startGuest directly. Without this,
    // a set _guestError kept the OR below true forever, so that button
    // became a permanent no-op after the first guest-sign-in failure. This
    // is the only place showLoginProvider is ever set back to false after a
    // guest error, so retrying here on that exact transition is what makes
    // the button work again.
    ref.listen<bool>(showLoginProvider, (prev, next) {
      if (!next && _guestError != null) _openSession();
    });
    if (session == null) {
      _retries = 0;

      // A session that existed and could not be refreshed back. The account
      // itself is still on the server with all its progress, so the way back
      // in is signing in — not a fresh guest that would strand it.
      if (_sessionLost) {
        return LoginScreen(
          notice: tr('Сессияң аяқталды. Прогресің сақтаулы — қайта кір.'),
          onContinueAsGuest: _startFreshGuest,
        );
      }

      // Signing in is a choice, not a toll gate — the only reasons to show
      // the login screen are an explicit request and a guest session that
      // could not be opened at all.
      if (ref.watch(showLoginProvider) || _guestError != null) {
        return LoginScreen(notice: _guestError);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => _openSession());
      return const SplashScreen();
    }

    // Remember the live session so a later disappearance is recognisable as
    // a loss rather than a first run.
    final uid = session.user.id;
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(authRepoProvider).rememberSession(uid));

    final profile = ref.watch(myProfileProvider);

    return profile.when(
      loading: () => const SplashScreen(),
      error: (e, _) => SplashScreen(
        error: humanError(e),
        onRetry: () {
          _retries = 0;
          ref.invalidate(myProfileProvider);
        },
      ),
      data: (p) {
        if (p == null) {
          if (_retries >= _maxRetries) {
            return SplashScreen(
              error: tr('Профиль жүктелмеді. Қайта кіріп көріңіз.'),
              onRetry: () {
                _retries = 0;
                ref.invalidate(myProfileProvider);
              },
            );
          }
          _retryProfile();
          return const SplashScreen();
        }
        _retries = 0;

        // Keep the theme and the interface language in step with the stored
        // preferences. A language chosen on this device always wins over the
        // one on the profile row, so switching never bounces back.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final want = p.darkMode ? ThemeMode.dark : ThemeMode.light;
          if (ref.read(themeProvider) != want) {
            ref.read(themeProvider.notifier).set(p.darkMode);
          }
          ref.read(langProvider.notifier).adoptFromProfile(p.uiLang);
        });

        return p.onboarded ? const RootShell() : const OnboardingScreen();
      },
    );
  }
}
