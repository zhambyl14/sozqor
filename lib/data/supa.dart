// lib/data/supa.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/i18n/l10n.dart';

/// Shorthand accessors for the Supabase singleton.
SupabaseClient get supa => Supabase.instance.client;

String? get currentUid => supa.auth.currentUser?.id;

/// Turns a PostgrestException / AuthException into a message a Kazakh-speaking
/// user can act on.
String humanError(Object e) {
  final raw = e.toString();

  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return tr('Email немесе құпия сөз дұрыс емес');
    if (m.contains('already registered') || m.contains('already been registered')) {
      return tr('Бұл email тіркелген. Кіріп көріңіз.');
    }
    if (m.contains('email not confirmed')) {
      return tr('Поштаңызды растаңыз — сілтеме жіберілді');
    }
    if (m.contains('password should be')) return tr('Құпия сөз кемінде 6 таңба болсын');
    if (m.contains('rate limit') || m.contains('too many') || m.contains('security purposes')) {
      return tr('Тым көп әрекет. Біраз күте тұрыңыз.');
    }
    if (m.contains('anonymous')) {
      return tr('Қонақ режимі әлі қосылмаған. Тіркеліп кіріңіз.');
    }
    if (m.contains('refresh token') || m.contains('jwt expired')) {
      return tr('Сессия аяқталды. Қайта кіріңіз.');
    }
    if (m.contains('user not found')) return tr('Пайдаланушы табылмады');
    return e.message;
  }

  if (e is PostgrestException) {
    if (e.code == '23505') return tr('Мұндай жазба бұрыннан бар');
    if (e.code == '42501') return tr('Рұқсат жоқ');
    if (e.code == '23503') return tr('Байланысты деректер табылмады');
    if (e.code == '23502') return tr('Міндетті өріс толтырылмаған');
    if (e.code == '57014') return tr('Сұраныс уақыты бітті. Қайта көріңіз.');
    if (e.message.contains('GUEST_LOCKED')) {
      return e.message.split('GUEST_LOCKED:').last.trim();
    }
    return e.message;
  }

  if (raw.contains('GUEST_LOCKED')) {
    return raw.split('GUEST_LOCKED:').last.replaceAll('"', '').trim();
  }

  if (raw.contains('SocketException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('ClientException')) {
    return tr('Интернет байланысын тексеріңіз');
  }

  return raw.replaceFirst('Exception: ', '');
}
