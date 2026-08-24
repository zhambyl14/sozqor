// lib/data/repos/phone_auth_repo.dart
//
// Phone + password sign-in. The number is proved by sharing it with the
// SozQor Telegram bot, which is free and needs no SMS provider.
//
// Supabase stores the account as <digits>@sozqor.kz; that address is an
// implementation detail the learner never sees.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supa.dart';
import '../../core/i18n/l10n.dart';

enum VerifyStatus { pending, verified, consumed, expired, unknown }

class VerifyRequest {
  final String code;
  final String? deepLink, botUsername;
  const VerifyRequest({required this.code, this.deepLink, this.botUsername});
}

class PhoneAuthRepo {
  static const _fn = 'phone-auth';
  static const emailDomain = 'sozqor.kz';

  /// Digits only, so "+7 (700) 123-45-67" and "87001234567" agree.
  static String normalize(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  static String emailFor(String phone) => '${normalize(phone)}@$emailDomain';

  /// Human-friendly formatting for an 11-digit KZ number.
  static String pretty(String phone) {
    final d = normalize(phone);
    if (d.length == 11) {
      return '+${d[0]} ${d.substring(1, 4)} ${d.substring(4, 7)} '
             '${d.substring(7, 9)} ${d.substring(9)}';
    }
    return d.isEmpty ? '' : '+$d';
  }

  static bool looksValid(String phone) {
    final d = normalize(phone);
    return d.length >= 10 && d.length <= 15;
  }

  Future<Map<String, dynamic>> _call(
    Map<String, dynamic> body, {
    bool withSession = false,
  }) async {
    try {
      final res = await supa.functions.invoke(
        _fn,
        body: body,
        headers: withSession
            ? {
                'Authorization':
                    'Bearer ${supa.auth.currentSession?.accessToken ?? ''}',
              }
            : null,
      );
      final data = res.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        if (map['error'] != null) throw Exception(map['error'].toString());
        return map;
      }
      throw Exception(tr('Сервер жауап бермеді'));
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(tr('Қызмет қолжетімсіз'));
    }
  }

  /// Opens a verification request and returns the Telegram deep link.
  ///
  /// The app language rides along (EN-4 / KK-9). The bot is a separate process
  /// with no session and no profile to read — all it ever receives is the
  /// verification code in a /start payload — so unless the language is stored
  /// on that row, every learner is answered in Kazakh, including one who set
  /// the app to Russian before they ever reached Telegram.
  Future<VerifyRequest> startVerification({String purpose = 'signup'}) async {
    final data = await _call({
      'action': 'start',
      'purpose': purpose,
      'lang': AppLang.current,
    });
    return VerifyRequest(
      code: (data['code'] ?? '').toString(),
      deepLink: data['deep_link']?.toString(),
      botUsername: data['bot_username']?.toString(),
    );
  }

  /// Polled while the user is over in Telegram.
  Future<(VerifyStatus, String?)> checkStatus(String code) async {
    final data = await _call({'action': 'status', 'code': code});
    final status = switch ((data['status'] ?? '').toString()) {
      'verified' => VerifyStatus.verified,
      'consumed' => VerifyStatus.consumed,
      'expired'  => VerifyStatus.expired,
      'pending'  => VerifyStatus.pending,
      _          => VerifyStatus.unknown,
    };
    return (status, data['phone']?.toString());
  }

  Future<bool> phoneExists(String phone) async {
    final data = await _call({'action': 'exists', 'phone': normalize(phone)});
    return (data['exists'] ?? false) as bool;
  }

  /// Creates the account, then signs in so the caller gets a live session.
  Future<void> register({
    required String code,
    required String password,
    required String displayName,
  }) async {
    final data = await _call({
      'action': 'register',
      'code': code,
      'password': password,
      'display_name': displayName,
    });
    await supa.auth.signInWithPassword(
      email: (data['email'] ?? '').toString(), password: password);
  }

  Future<void> resetPassword({
    required String code,
    required String password,
  }) async {
    final data = await _call({
      'action': 'reset', 'code': code, 'password': password,
    });
    await supa.auth.signInWithPassword(
      email: (data['email'] ?? '').toString(), password: password);
  }

  /// Turns the current guest session into a phone account, same user id.
  Future<void> claimGuest({
    required String code,
    required String password,
    required String displayName,
  }) async {
    await _call({
      'action': 'claim',
      'code': code,
      'password': password,
      'display_name': displayName,
    }, withSession: true);
  }

  Future<void> signIn({
    required String phone,
    required String password,
  }) async {
    await supa.auth.signInWithPassword(
      email: emailFor(phone), password: password);
  }
}
