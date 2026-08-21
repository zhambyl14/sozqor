// lib/data/models/app_event.dart

import '../../core/i18n/l10n.dart';

/// A live event pushed from the server — new seasonal challenges, topic packs
/// and quests can appear without shipping a new build.
///
/// Text is stored bilingually in the row rather than going through tr(), for
/// the same reason the shop catalogue is: a moderator writes these from inside
/// the app at runtime, so there is no key in ru.dart for them to translate
/// against. Everything the moderator can fill in has a Kazakh and a Russian
/// column, and the getters pick by interface language — the learner's reading
/// language, not their study language.
class AppEvent {
  final int id;
  final String slug, emoji, kind;
  final String titleKk, subtitleKk;
  final String? titleRu, subtitleRu;

  /// Free text the moderator writes: how the event is scored, and who is
  /// allowed to enter. Null when they left the field empty, so the UI can drop
  /// the whole section rather than render an empty heading.
  final String? rulesKk, rulesRu, whoKk, whoRu;

  final String? topic;

  /// Which words the event draws on. The server already filters by these, but
  /// the learner is shown them too — an event they cannot enter should say so
  /// rather than simply not appear.
  final String cefrMin, cefrMax;

  final int xpReward, target;

  /// A cosmetics.id awarded to the top [prizeTopN] finishers, on top of XP.
  final String? prizeItem;
  final int prizeTopN;

  final DateTime startsAt, endsAt;

  const AppEvent({
    required this.id,
    required this.slug,
    required this.titleKk,
    required this.subtitleKk,
    required this.emoji,
    required this.kind,
    required this.xpReward,
    required this.target,
    required this.startsAt,
    required this.endsAt,
    required this.cefrMin,
    required this.cefrMax,
    this.titleRu,
    this.subtitleRu,
    this.rulesKk,
    this.rulesRu,
    this.whoKk,
    this.whoRu,
    this.topic,
    this.prizeItem,
    this.prizeTopN = 0,
  });

  factory AppEvent.fromMap(Map<String, dynamic> m) {
    final payload = Map<String, dynamic>.from(
        (m['payload'] as Map?) ?? const {});
    String? opt(String key) {
      final v = m[key]?.toString().trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    return AppEvent(
      id:         (m['id'] ?? 0) as int,
      slug:       (m['slug'] ?? '').toString(),
      titleKk:    (m['title'] ?? '').toString(),
      titleRu:    opt('title_ru'),
      subtitleKk: (m['subtitle'] ?? '').toString(),
      subtitleRu: opt('subtitle_ru'),
      emoji:      (m['emoji'] ?? '🎉').toString(),
      kind:       (m['kind'] ?? 'challenge').toString(),
      topic:      opt('topic'),
      rulesKk:    opt('rules_kk'),
      rulesRu:    opt('rules_ru'),
      whoKk:      opt('who_kk'),
      whoRu:      opt('who_ru'),
      cefrMin:    (m['cefr_min'] ?? 'A0').toString(),
      cefrMax:    (m['cefr_max'] ?? 'C1').toString(),
      xpReward:   (m['xp_reward'] ?? 200) as int,
      prizeItem:  opt('prize_item'),
      prizeTopN:  (m['prize_top_n'] ?? 0) as int,
      target:     int.tryParse('${payload['target'] ?? 10}') ?? 10,
      startsAt:   DateTime.tryParse('${m['starts_at']}') ?? DateTime.now(),
      endsAt:     DateTime.tryParse('${m['ends_at']}') ??
                  DateTime.now().add(const Duration(days: 30)),
    );
  }

  /// Falls back to the Kazakh column when the Russian one was left empty, so a
  /// half-filled row still reads as an event rather than a blank card.
  static String? _pick(String? kk, String? ru) {
    final chosen = AppLang.isRu ? (ru ?? kk) : kk;
    return (chosen == null || chosen.isEmpty) ? null : chosen;
  }

  String get title => _pick(titleKk, titleRu) ?? '';
  String get subtitle => _pick(subtitleKk, subtitleRu) ?? '';
  String? get rules => _pick(rulesKk, rulesRu);
  String? get who => _pick(whoKk, whoRu);

  bool get hasPrizeItem => prizeItem != null && prizeTopN > 0;

  /// A0-only and C1-only events are common, and "A0 — A0" reads worse than
  /// just "A0".
  String get levelLabel =>
      cefrMin == cefrMax ? cefrMin : '$cefrMin — $cefrMax';

  bool get notStarted => DateTime.now().isBefore(startsAt);

  Duration get remaining {
    final d = endsAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  String get remainingLabel {
    final r = remaining;
    if (r.inDays > 0) return trp('{p1} күн қалды', {'p1': '${r.inDays}'});
    if (r.inHours > 0) return trp('{p1} сағат қалды', {'p1': '${r.inHours}'});
    return trp('{p1} минут қалды', {'p1': '${r.inMinutes}'});
  }
}

class EventProgress {
  final int eventId, progress, target;
  final bool completed;
  const EventProgress({
    required this.eventId,
    required this.progress,
    required this.target,
    required this.completed,
  });

  factory EventProgress.fromMap(Map<String, dynamic> m) => EventProgress(
    eventId:   (m['event_id'] ?? 0) as int,
    progress:  (m['progress'] ?? 0) as int,
    target:    (m['target'] ?? 1) as int,
    completed: (m['completed'] ?? false) as bool,
  );

  double get ratio => target == 0 ? 0 : (progress / target).clamp(0.0, 1.0);
}
