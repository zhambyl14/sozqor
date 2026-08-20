// lib/data/repos/auth_repo.dart
//
// Session lifecycle. Phone + password sign-in lives in PhoneAuthRepo; this
// class owns the session stream, guest sessions and the optional Google flow.

import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../supa.dart';
import '../../core/i18n/l10n.dart';

class AuthRepo {
  Stream<AuthState> get changes => supa.auth.onAuthStateChange;
  User? get user => supa.auth.currentUser;
  bool get signedIn => supa.auth.currentUser != null;
  bool get isAnonymous => supa.auth.currentUser?.isAnonymous ?? false;

  /// The last user id this device held a session for. Its only job is to tell
  /// "this app has never been opened here" apart from "a session existed and
  /// then went away" — the two look identical to [sessionProvider], and they
  /// call for opposite responses.
  static const _lastUidKey = 'sq_last_uid';

  Future<void> rememberSession(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastUidKey, uid);
    } catch (_) {/* a lost marker only costs us the nicer recovery path */}
  }

  Future<String?> lastKnownUid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastUidKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> forgetSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastUidKey);
    } catch (_) {/* ignore */}
  }

  /// Attempts to bring a dropped session back.
  ///
  /// Supabase rotates refresh tokens, and a rotation that races with itself
  /// (two tabs, or a retry after a flaky network) revokes the session
  /// outright — the server then answers `session_not_found` for a learner who
  /// never signed out. Asking for a refresh recovers the common transient
  /// case; only when that genuinely fails is the session really gone.
  Future<bool> tryRecoverSession() async {
    try {
      final res = await supa.auth.refreshSession();
      return res.session != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    await forgetSession();
    await supa.auth.signOut();
  }

  /// Starts a guest session. Progress is real and stored server-side, so it
  /// all survives when the guest later claims the account with a phone number.
  Future<void> signInAsGuest() async {
    await supa.auth.signInAnonymously();
  }

  /// Google sign-in via a native id token. Hidden until the OAuth client ids
  /// are supplied through --dart-define.
  Future<void> signInWithGoogle() async {
    if (!AppConfig.googleSignInReady) {
      throw Exception(tr('Google кіру әлі бапталмаған'));
    }
    final google = GoogleSignIn(
      clientId: AppConfig.googleIosClientId.isEmpty
          ? null : AppConfig.googleIosClientId,
      serverClientId: AppConfig.googleWebClientId,
    );

    final account = await google.signIn();
    if (account == null) throw Exception(tr('Google кіру тоқтатылды'));

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) throw Exception(tr('Google токені алынбады'));

    await supa.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );
  }
}
