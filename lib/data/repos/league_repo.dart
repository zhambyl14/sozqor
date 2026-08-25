// lib/data/repos/league_repo.dart
//
// The league as a rating threshold.
//
// Nobody is promoted for placing in a top ten: a band is a range of rating,
// you are in it because your rating is inside it, and you leave it the moment
// your rating crosses the number the next band starts at. That rule lives in
// the database — league_bands() draws the rungs, league_progress() says which
// one you are standing on — because a ladder whose thresholds disagree between
// the app and the server is worse than no ladder at all.
//
// So nothing in here compiles a band list, a colour or a threshold of its own.
// The one thing the app decides is which language to read the band's name in.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/i18n/l10n.dart';
import '../models/battle.dart';
import '../supa.dart';

/// int4's ceiling, which is what the server sends as the top band's upper
/// bound: the summit has no threshold above it, not a very high one.
const int _openEnded = 2147483647;

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

/// One rung of the ladder, as `league_bands()` defines it.
class LeagueBand {
  final int tier, min, max;
  final String kk, ru, colour;

  const LeagueBand({
    required this.tier,
    required this.min,
    required this.max,
    required this.kk,
    required this.ru,
    required this.colour,
  });

  factory LeagueBand.fromMap(Map<String, dynamic> m) => LeagueBand(
    tier:   _int(m['tier']),
    min:    _int(m['min']),
    max:    _int(m['max']),
    kk:     (m['kk'] ?? '').toString(),
    ru:     (m['ru'] ?? '').toString(),
    colour: (m['colour'] ?? '').toString(),
  );

  String get name => AppLang.isRu ? ru : kk;

  bool get isTop => max >= _openEnded;
}

/// Where one learner stands on the ladder, straight out of `league_progress()`.
class LeagueProgress {
  final int elo, tier;
  final String nameKk, nameRu, colour;

  /// The band this learner is inside, and the rating the next one opens at.
  final int bandMin, bandMax, nextAt, toNext;
  final String nextNameKk, nextNameRu, nextColour;

  /// The rating at which this learner would fall back into the band below.
  final int dropAt, toDrop;
  final String prevNameKk, prevNameRu;

  final bool isTop;
  final List<LeagueBand> bands;

  const LeagueProgress({
    required this.elo,
    required this.tier,
    required this.nameKk,
    required this.nameRu,
    required this.colour,
    required this.bandMin,
    required this.bandMax,
    this.nextAt = 0,
    this.toNext = 0,
    this.nextNameKk = '',
    this.nextNameRu = '',
    this.nextColour = '',
    this.dropAt = 0,
    this.toDrop = 0,
    this.prevNameKk = '',
    this.prevNameRu = '',
    this.isTop = false,
    this.bands = const [],
  });

  factory LeagueProgress.fromMap(Map<String, dynamic> m) => LeagueProgress(
    elo:        _int(m['elo']),
    tier:       _int(m['tier']),
    nameKk:     (m['name_kk'] ?? '').toString(),
    nameRu:     (m['name_ru'] ?? '').toString(),
    colour:     (m['colour'] ?? '').toString(),
    bandMin:    _int(m['band_min']),
    bandMax:    _int(m['band_max']),
    nextAt:     _int(m['next_at']),
    toNext:     _int(m['to_next']),
    nextNameKk: (m['next_name_kk'] ?? '').toString(),
    nextNameRu: (m['next_name_ru'] ?? '').toString(),
    nextColour: (m['next_colour'] ?? '').toString(),
    dropAt:     _int(m['drop_at']),
    toDrop:     _int(m['to_drop']),
    prevNameKk: (m['prev_name_kk'] ?? '').toString(),
    prevNameRu: (m['prev_name_ru'] ?? '').toString(),
    isTop:      (m['is_top'] ?? false) as bool,
    bands: [
      for (final b in (m['bands'] as List? ?? const []))
        LeagueBand.fromMap(Map<String, dynamic>.from(b as Map)),
    ],
  );

  /// A stand-in built from a `my_league()` row, used for the moment before
  /// league_progress() has answered — the standings usually arrive first, and
  /// a header that appears late reads as a header that failed.
  ///
  /// The row knows its own band but nothing about the one above it, so the
  /// next band goes unnamed and the screen says "the next league" instead.
  factory LeagueProgress.fromRow(LeagueRow r) => LeagueProgress(
    elo:     r.elo,
    tier:    r.tier,
    nameKk:  r.tierKk,
    nameRu:  r.tierRu,
    colour:  r.tierColour,
    bandMin: r.tierMin,
    bandMax: r.tierMax,
    nextAt:  r.isTopRank ? r.tierMax : r.tierMax + 1,
    toNext:  r.isTopRank ? 0 : (r.tierMax + 1 - r.elo).clamp(0, _openEnded),
    isTop:   r.isTopRank,
  );

  String get name     => AppLang.isRu ? nameRu : nameKk;
  String get nextName => AppLang.isRu ? nextNameRu : nextNameKk;
  String get prevName => AppLang.isRu ? prevNameRu : prevNameKk;

  /// How far across the current band the learner stands, 0..1.
  ///
  /// Measured from the band's own floor to the next band's threshold, because
  /// that is the only span promotion is decided on — a bar drawn against a
  /// placing in the room would be measuring something nobody is judged by.
  double get intoBand {
    if (isTop) return 1;
    final span = nextAt - bandMin;
    if (span <= 0) return 1;
    return ((elo - bandMin) / span).clamp(0.0, 1.0);
  }
}

class LeagueRepo {
  /// This learner's band, rating, and the threshold the next band opens at.
  ///
  /// Null when the server has not been migrated yet: an old database should
  /// cost the screen its header, not the whole screen.
  Future<LeagueProgress?> progress() async {
    try {
      final res = await supa.rpc('league_progress');
      if (res is! Map) return null;
      return LeagueProgress.fromMap(Map<String, dynamic>.from(res));
    } on PostgrestException catch (e) {
      if (_missing(e)) return null;
      rethrow;
    }
  }

  /// Everybody in this learner's band, ordered by rating.
  Future<List<LeagueRow>> standings() async {
    final res = await supa.rpc('my_league');
    return (res as List? ?? const [])
        .map((r) => LeagueRow.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// PGRST202 is PostgREST's "no such function in the schema cache" — the one
  /// failure that means "not deployed yet" rather than "something went wrong".
  bool _missing(PostgrestException e) =>
      e.code == 'PGRST202' || e.message.contains('does not exist');
}
