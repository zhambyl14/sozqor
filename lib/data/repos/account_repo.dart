// lib/data/repos/account_repo.dart
//
// The parts of an account a signed-in learner can change themselves: the
// number they sign in with and their password.
//
// The number is not an ordinary profile column. PhoneAuthRepo turns its
// digits into the address Supabase authenticates against, so changing the
// number changes the login itself — which is why both operations here only
// ever run against a code the Telegram bot has already verified, and why
// this repo refuses a code that proves a number the account does not own.
// Without that check a verified stranger's number would happily rewrite a
// stranger's password, since the server resolves the account from the phone.
//
// The display name deliberately stays in ProfileRepo.setDisplayName: it is a
// plain column behind RLS and needs none of this.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/i18n/l10n.dart';
import '../supa.dart';
import 'phone_auth_repo.dart';

class AccountRepo {
  final _phoneAuth = PhoneAuthRepo();

  /// The address Supabase actually holds for this session.
  ///
  /// Read back rather than derived from the profile's phone: the two agree
  /// for every account made through the bot, but only this one is the thing
  /// a password is checked against.
  String? get _email => supa.auth.currentUser?.email;

  /// True when [password] really is this account's password.
  ///
  /// Asked before the number change starts, never after: the server action
  /// that moves the login also *sets* the password to whatever it is handed,
  /// so an unchecked typo would lock the learner out of the very number they
  /// had just moved to. A network failure throws instead of answering false —
  /// "we could not ask" is not "you typed it wrong".
  Future<bool> passwordMatches(String password) async {
    final email = _email;
    if (email == null || password.isEmpty) return false;
    try {
      await supa.auth.signInWithPassword(email: email, password: password);
      return true;
    } on AuthException {
      return false;
    }
  }

  /// Whether any account already signs in with [phone].
  Future<bool> phoneTaken(String phone) => _phoneAuth.phoneExists(phone);

  /// Sets a new password once the bot has confirmed the account's own number.
  ///
  /// [verifiedPhone] is what Telegram reported, [accountPhone] what the
  /// profile holds; they must be the same number or the reset would land on
  /// somebody else's account.
  Future<void> changePassword({
    required String code,
    required String verifiedPhone,
    required String accountPhone,
    required String password,
  }) async {
    _mustMatch(verifiedPhone, accountPhone,
      tr('Telegram-де өз нөміріңді бөліс'));
    await _phoneAuth.resetPassword(code: code, password: password);
  }

  /// Moves the login to [intendedPhone], which the bot has just verified.
  ///
  /// Rotating the auth email needs the service-role key, so this goes through
  /// the phone-auth function. Its `claim` action is the only privileged path
  /// that does it: written for a guest taking a number, but what it performs
  /// is exactly this — bind the verified number to the calling session and
  /// re-key the email from it. It refuses a number that belongs to another
  /// account, so a signed-in learner cannot take over anyone's login here.
  ///
  /// [password] must already have passed [passwordMatches]: the server writes
  /// it back, so it has to be the password the learner already has.
  Future<void> changePhone({
    required String code,
    required String verifiedPhone,
    required String intendedPhone,
    required String password,
    required String displayName,
  }) async {
    _mustMatch(verifiedPhone, intendedPhone,
      tr('Telegram-де жаңа нөміріңді бөліс'));
    await _phoneAuth.claimGuest(
      code: code, password: password, displayName: displayName);
    // The email moved with the number, so the copy of the user cached on this
    // device still names the old one — and that stale address is what the
    // next password check would be made against. The change itself is already
    // committed, so a failure to refresh must not be reported as a failure to
    // change: the session catches up on its own at the next token refresh.
    try {
      await supa.auth.refreshSession();
    } catch (_) {/* already changed server-side */}
  }

  static void _mustMatch(String a, String b, String message) {
    if (PhoneAuthRepo.normalize(a) != PhoneAuthRepo.normalize(b)) {
      throw Exception(message);
    }
  }
}
