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
    // PGRST303 — "JWT issued at future". PostgREST compares the token's `iat`
    // against the database clock with no tolerance at all, so a device whose
    // own clock runs even slightly ahead gets locked out of every request
    // with a raw JSON blob on the splash screen. It is not a login problem
    // and it is not something retrying differently will fix, so the message
    // names the one thing that will.
    if (e.code == 'PGRST303' || e.message.contains('issued at future')) {
      return tr('Құрылғының уақыты дұрыс емес. Телефон баптауларынан '
                'уақытты автоматты етіп қойып, қайта кір.');
    }
    if (e.code == '23505') return tr('Мұндай жазба бұрыннан бар');
    if (e.code == '42501') return tr('Рұқсат жоқ');
    if (e.code == '23503') return tr('Байланысты деректер табылмады');
    if (e.code == '23502') return tr('Міндетті өріс толтырылмаған');
    if (e.code == '57014') return tr('Сұраныс уақыты бітті. Қайта көріңіз.');
    if (e.message.contains('GUEST_LOCKED')) {
      // Through tr(), not straight to the screen. The server writes these in
      // Kazakh because it has no idea which language the reader chose — and
      // in this app the Kazakh sentence IS the translation key, so one call
      // turns every one of them into a Russian one for a Russian learner.
      // Before this, "Бөлме толы" reached a Russian speaker in Kazakh.
      return tr(e.message.split('GUEST_LOCKED:').last.trim());
    }
    final coded = _codedFailure(e.message);
    if (coded != null) return coded;
    return e.message;
  }

  // The same thing arriving as a plain string rather than a typed exception,
  // which is how it reaches the splash screen through the guest sign-in.
  if (raw.contains('PGRST303') || raw.contains('issued at future')) {
    return tr('Құрылғының уақыты дұрыс емес. Телефон баптауларынан '
              'уақытты автоматты етіп қойып, қайта кір.');
  }

  if (raw.contains('GUEST_LOCKED')) {
    return tr(raw.split('GUEST_LOCKED:').last.replaceAll('"', '').trim());
  }

  final coded = _codedFailure(raw);
  if (coded != null) return coded;

  if (raw.contains('SocketException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('ClientException')) {
    return tr('Интернет байланысын тексеріңіз');
  }

  return raw.replaceFirst('Exception: ', '');
}

// ── Server refusals that arrive as a code ────────────────────
//
// v5_teams.sql, v5_match_consent.sql and the rematch functions raise every
// user-facing refusal as `PREFIX:code` — 'TEAM_ERR:already_in_team',
// 'INVITE_ERR:blocked:90'. They do it that way on purpose: the server has no
// idea which of the two interface languages the person reading it chose, and a
// Kazakh sentence hard-coded in plpgsql cannot be translated. The sentence is
// therefore a UI decision, and this is where it is made.
//
// Until it was made, the code itself reached the screen. Somebody trying to
// join a team they were already in read "TEAM_ERR:already_in_team", which to a
// learner is indistinguishable from the app breaking.

/// Turns `PREFIX:code` into a sentence, or null when [s] carries no such code
/// (or carries one nobody has worded yet) so the caller falls through to
/// whatever it was going to show.
String? _codedFailure(String s) {
  final m = RegExp(r'(TEAM_ERR|INVITE_ERR|REMATCH_ERR):([a-z_]+)(?::(\d+))?')
      .firstMatch(s);
  if (m == null) return null;
  final code = m.group(2)!;
  return switch (m.group(1)) {
    'TEAM_ERR'   => _teamFailure(code),
    'INVITE_ERR' => _inviteFailure(code, m.group(3)),
    _            => _rematchFailure(code),
  };
}

/// Teams, the weekly challenge and the war (v5_teams.sql).
String? _teamFailure(String code) => switch (code) {
  'guest'             => tr('Команда жүйесі тіркелгендерге ғана ашық'),
  'already_in_team'   => tr('Сен бір командадасың. Алдымен одан шық.'),
  'bad_name'          => tr('Команда атауы 2–24 таңба болсын'),
  'bad_tag'           => tr('Тег 2–6 таңба: тек бас латын әрпі мен сан'),
  'tag_taken'         => tr('Мұндай тег біреуде бар — басқасын таңда'),
  'not_found'         => tr('Команда табылмады'),
  'closed'            => tr('Бұл команда жаңа мүше қабылдамайды'),
  'full'              => tr('Команда толы'),
  'no_team'           => tr('Сен әлі командада емессің'),
  'forbidden'         => tr('Бұған рұқсатың жоқ'),
  'self'              => tr('Мұны өзіңе қолдана алмайсың'),
  'target_in_team'    => tr('Бұл ойыншы басқа командада'),
  'invite_gone'       => tr('Бұл шақыру ескірген'),
  'cannot_kick'       => tr('Бұл мүшені командадан шығара алмайсың'),
  'not_member'        => tr('Бұл ойыншы сенің командаңда емес'),
  'not_ready'         => tr('Апталық мақсат әлі орындалмаған'),
  'already_claimed'   => tr('Апталық сыйлық бұрын алынған'),
  'need_contributors' => tr('Сыйлық үшін тағы мүшелердің үлесі керек'),
  'too_small'         => tr('Шайқасқа шығуға командада мүше жетпейді'),
  'no_war'            => tr('Шайқас табылмады'),
  'war_over'          => tr('Бұл шайқас аяқталған'),
  'match_limit'       => tr('Бүгінгі соққыларың бітті — ертең қайта кел'),
  _                   => null,
};

/// Battle invitations (v5_match_consent.sql). `blocked` carries the seconds
/// left on the silence the other player asked for, so the sentence says when
/// to try again rather than just refusing.
String? _inviteFailure(String code, String? seconds) => switch (code) {
  'self'       => tr('Өзіңді шақыра алмайсың'),
  'not_friend' => tr('Тек досыңды баттлға шақыруға болады'),
  'busy'       => tr('Бұл ойыншы қазір басқа ойында'),
  'blocked'    => seconds == null
      ? tr('Бұл досқа әзірге қайта шақыру жіберуге болмайды')
      : trp('Бұл досқа {n} секундтан кейін қайта шақыру жіберуге болады',
            {'n': seconds}),
  'gone'       => tr('Бұл шақыру жойылған'),
  'not_yours'  => tr('Бұл шақыру саған арналмаған'),
  _            => null,
};

/// The best-of-three rematch series (v5_match_consent.sql).
String? _rematchFailure(String code) => switch (code) {
  'gone'        => tr('Бұл баттл табылмады'),
  'unfinished'  => tr('Баттл әлі аяқталмаған'),
  'no_opponent' => tr('Бұл баттлда қарсылас болмаған'),
  'not_yours'   => tr('Бұл баттл сенікі емес'),
  'series_over' => tr('Реванш сериясы аяқталды'),
  _             => null,
};
