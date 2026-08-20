// lib/data/repos/profile_repo.dart
import 'dart:ui' show Color;

import '../models/battle.dart';
import '../models/profile.dart';
import '../supa.dart';
import '../../core/i18n/l10n.dart';

/// One day of the weekly report.
class DayStat {
  final DateTime day;
  final int xp, reviewed, correct;
  const DayStat(this.day, this.xp, this.reviewed, this.correct);

  /// Two-letter Kazakh weekday label, Monday first.
  String get label =>
      tr(const ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сб', 'Жк'][day.weekday - 1]);

  bool get isToday {
    final n = DateTime.now();
    return day.year == n.year && day.month == n.month && day.day == n.day;
  }
}

/// What one learner is wearing, as `worn_cosmetics` reports it: the frame id
/// plus the colour the catalogue stores for it, and the equipped title in both
/// interface languages. Everything is optional — most people wear nothing.
class WornCosmetic {
  final String frame, titleKk, titleRu;

  /// The frame's `data->>'color'` straight from the catalogue, so all 44 shop
  /// items render correctly without the client knowing any of their ids.
  final Color? color;

  const WornCosmetic({
    this.frame = '',
    this.titleKk = '',
    this.titleRu = '',
    this.color,
  });

  factory WornCosmetic.fromMap(Map<String, dynamic> m) => WornCosmetic(
    frame:   (m['frame'] ?? '').toString(),
    titleKk: (m['title_kk'] ?? '').toString(),
    titleRu: (m['title_ru'] ?? '').toString(),
    color:   hexColor(m['frame_color']?.toString()),
  );

  /// The title in the interface language, empty when none is equipped.
  String get title => byLang(kk: titleKk, ru: titleRu.isEmpty ? titleKk : titleRu);

  bool get hasTitle => title.trim().isNotEmpty;
  bool get isEmpty  => color == null && !hasTitle;
}

/// '#RRGGBB' / 'RRGGBB' / '#AARRGGBB' → [Color]. Anything unparseable is null,
/// which every caller reads as "no frame", never as black.
Color? hexColor(String? raw) {
  if (raw == null) return null;
  var h = raw.trim().replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

class ProfileRepo {
  Future<Profile?> me() async {
    final uid = currentUid;
    if (uid == null) return null;
    final row = await supa.from('profiles').select().eq('id', uid).maybeSingle();
    if (row == null) return null;
    return Profile.fromMap(row);
  }

  Future<Profile?> byId(String id) async {
    final row = await supa.from('profiles').select().eq('id', id).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  /// What a whole list of people are wearing, in ONE round trip — a
  /// leaderboard page or a friends list is a single call, never one per row.
  /// Ids are de-duplicated; an empty list skips the network entirely.
  /// Anyone wearing nothing is simply absent from the returned map.
  Future<Map<String, WornCosmetic>> wornCosmetics(List<String> userIds) async {
    final ids = userIds.where((s) => s.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await supa.rpc('worn_cosmetics', params: {'p_user_ids': ids});
    final out = <String, WornCosmetic>{};
    for (final r in (rows as List? ?? const [])) {
      final m = Map<String, dynamic>.from(r as Map);
      final uid = (m['user_id'] ?? '').toString();
      if (uid.isEmpty) continue;
      final worn = WornCosmetic.fromMap(m);
      if (!worn.isEmpty) out[uid] = worn;
    }
    return out;
  }

  /// One person's cosmetics. Null when they are wearing nothing.
  Future<WornCosmetic?> worn(String userId) async =>
      (await wornCosmetics([userId]))[userId];

  Stream<Profile?> watch() {
    final uid = currentUid;
    if (uid == null) return Stream.value(null);
    return supa
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', uid)
        .map((rows) => rows.isEmpty ? null : Profile.fromMap(rows.first));
  }

  Future<void> update(Map<String, dynamic> patch) async {
    final uid = currentUid;
    if (uid == null) return;
    await supa.from('profiles').update(patch).eq('id', uid);
  }

  Future<void> setLevel(String cefr)      => update({'cefr_level': cefr});
  Future<void> setAvatar(String emoji)    => update({'avatar_emoji': emoji});
  Future<void> setDisplayName(String v)   => update({'display_name': v.trim()});
  Future<void> setDarkMode(bool v)        => update({'dark_mode': v});
  Future<void> setNotifs(bool v)          => update({'notif_enabled': v});
  Future<void> setDailyGoal(int v)        => update({'daily_goal': v});
  Future<void> setUiLang(String v)        => update({'ui_lang': v});
  Future<void> setNativeLang(String v)    => update({'native_lang': v});
  Future<void> finishOnboarding()         => update({'onboarded': true});

  /// Username must be unique; surfaces a friendly error when taken.
  Future<void> setUsername(String v) async {
    final clean = v.trim().toLowerCase();
    if (clean.length < 3) throw Exception(tr('Логин кемінде 3 таңба болсын'));
    final taken = await supa
        .from('profiles').select('id').eq('username', clean).maybeSingle();
    if (taken != null && taken['id'] != currentUid) {
      throw Exception(tr('Бұл логин бос емес'));
    }
    await update({'username': clean});
  }

  Future<int> addXp(int amount, String source) async {
    final res = await supa.rpc('add_xp',
        params: {'p_amount': amount, 'p_source': source});
    return (res as num?)?.toInt() ?? 0;
  }

  /// Bumps the daily streak. Returns (streak, best, isNewDay).
  Future<(int, int, bool)> touchStreak() async {
    final res = await supa.rpc('touch_streak');
    if (res is List && res.isNotEmpty) {
      final m = Map<String, dynamic>.from(res.first as Map);
      return ((m['streak'] ?? 0) as int,
              (m['best_streak'] ?? 0) as int,
              (m['is_new_day'] ?? false) as bool);
    }
    return (0, 0, false);
  }

  Future<DailyProgress> today() async {
    final uid = currentUid;
    if (uid == null) return const DailyProgress();
    final day = DateTime.now().toIso8601String().substring(0, 10);
    final row = await supa
        .from('daily_progress')
        .select()
        .eq('user_id', uid)
        .eq('day', day)
        .maybeSingle();
    return row == null ? const DailyProgress() : DailyProgress.fromMap(row);
  }

  /// The last seven days of activity, oldest first and with missing days
  /// filled in as zeroes — the weekly report needs a bar for every weekday,
  /// including the ones nobody played.
  Future<List<DayStat>> lastWeek() async {
    final uid = currentUid;
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 6 - i));
      return d;
    });
    if (uid == null) {
      return [for (final d in days) DayStat(d, 0, 0, 0)];
    }

    final from = days.first.toIso8601String().substring(0, 10);
    final rows = await supa
        .from('daily_progress')
        .select('day, xp_earned, words_reviewed, correct_count')
        .eq('user_id', uid)
        .gte('day', from);

    final byDay = <String, Map<String, dynamic>>{
      for (final r in (rows as List))
        (r as Map)['day'].toString().substring(0, 10):
            Map<String, dynamic>.from(r),
    };

    return [
      for (final d in days)
        () {
          final key = d.toIso8601String().substring(0, 10);
          final m = byDay[key];
          return DayStat(
            d,
            (m?['xp_earned'] ?? 0) as int,
            (m?['words_reviewed'] ?? 0) as int,
            (m?['correct_count'] ?? 0) as int,
          );
        }(),
    ];
  }

  Future<void> bumpWordsAdded() async {
    final uid = currentUid;
    if (uid == null) return;
    final day = DateTime.now().toIso8601String().substring(0, 10);
    final row = await supa.from('daily_progress')
        .select('words_added').eq('user_id', uid).eq('day', day).maybeSingle();
    final n = ((row?['words_added'] ?? 0) as int) + 1;
    await supa.from('daily_progress').upsert(
      {'user_id': uid, 'day': day, 'words_added': n},
      onConflict: 'user_id,day');
  }

  Future<void> markQuestClaimed(String questId) async {
    final uid = currentUid;
    if (uid == null) return;
    final day = DateTime.now().toIso8601String().substring(0, 10);
    final row = await supa.from('daily_progress')
        .select('claimed').eq('user_id', uid).eq('day', day).maybeSingle();
    final claimed = <String>{
      ...((row?['claimed'] as List? ?? const []).map((e) => e.toString())),
      questId,
    }.toList();
    await supa.from('daily_progress').upsert(
      {'user_id': uid, 'day': day, 'claimed': claimed},
      onConflict: 'user_id,day');
  }

  // ── Achievements ───────────────────────────────────────
  Future<Set<String>> unlockedAchievements() async {
    final uid = currentUid;
    if (uid == null) return {};
    final rows = await supa.from('user_achievements')
        .select('code').eq('user_id', uid).not('unlocked_at', 'is', null);
    return (rows as List)
        .map((r) => (r as Map)['code'].toString()).toSet();
  }

  Future<void> unlockAchievement(String code) async {
    final uid = currentUid;
    if (uid == null) return;
    await supa.from('user_achievements').upsert({
      'user_id': uid,
      'code': code,
      'progress': 1,
      'unlocked_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,code');
  }
}
