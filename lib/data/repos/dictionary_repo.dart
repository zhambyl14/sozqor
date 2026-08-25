// lib/data/repos/dictionary_repo.dart
import 'package:supabase_flutter/supabase_flutter.dart'
    show CountOption, PostgrestException;

import '../models/dict_entry.dart';
import '../supa.dart';

class DictionaryRepo {
  /// Exact-then-fuzzy lookup in the shared brain, both directions.
  Future<List<DictEntry>> lookup(String term) async {
    if (term.trim().isEmpty) return const [];
    final rows = await supa.rpc('dict_lookup', params: {'p_term': term.trim()});
    return (rows as List? ?? const [])
        .map((r) => DictEntry.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Catalog browsing, filtered by the level band the learner should see.
  Future<List<DictEntry>> search({
    String query = '',
    List<String>? cefr,
    String? topic,
    int limit = 40,
    int offset = 0,
  }) async {
    final rows = await supa.rpc('dict_search', params: {
      'p_query': query,
      'p_cefr': cefr,
      'p_topic': topic,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (rows as List? ?? const [])
        .map((r) => DictEntry.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Words at [cefr] the CALLER does not already own — the discovery feed.
  ///
  /// The subtraction happens inside the database because that is the only
  /// place the learner's whole `words` table is visible. The client knows
  /// only the rows currently on screen, which is why the old client-side
  /// filter kept being handed back words that were already saved, hid every
  /// one of them, and left the screen saying "жаңа сөз табылмады" over a
  /// dictionary of hundreds of rows.
  ///
  /// [exclude] is for what is already on screen, on top of the owned words the
  /// server drops on its own.
  Future<List<DictEntry>> discover({
    required String cefr,
    String? topic,
    List<String> exclude = const [],
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await supa.rpc('dict_discover', params: {
        'p_cefr': cefr,
        'p_topic': topic,
        'p_exclude': exclude,
        'p_limit': limit,
        'p_offset': offset,
      });
      return (rows as List? ?? const [])
          .map((r) => DictEntry.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      // v5_discovery.sql is applied by hand, and the grant is to
      // `authenticated`. Neither a missing function nor a missing grant is a
      // reason to show an empty catalogue: plain search still lists the
      // level, it just cannot subtract what the learner owns.
      if (e.code == 'PGRST202' || e.code == '42883' || e.code == '42501') {
        return search(cefr: [cefr], topic: topic, limit: limit, offset: offset);
      }
      rethrow;
    }
  }

  /// How many words are left to find at this level — the one number that can
  /// tell "you have taken them all" apart from "the request failed".
  ///
  /// Null means the server could not say. Unknown is never the same as zero,
  /// and the caller must not print it as such.
  Future<int?> discoverCount({required String cefr, String? topic}) async {
    try {
      final n = await supa.rpc('dict_discover_count',
          params: {'p_cefr': cefr, 'p_topic': topic});
      return n is num ? n.toInt() : int.tryParse('$n');
    } catch (_) {
      return null;
    }
  }

  /// Random entries used to fill quiz option slots.
  Future<List<DictEntry>> distractors({
    required List<String> exclude,
    String cefr = 'A2',
    int limit = 3,
  }) async {
    final rows = await supa.rpc('dict_distractors', params: {
      'p_exclude': exclude,
      'p_cefr': cefr,
      'p_limit': limit,
    });
    return (rows as List? ?? const [])
        .map((r) => DictEntry.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Pool of entries a round can be built from, at the learner's level band.
  Future<List<DictEntry>> pool({
    required List<String> cefr,
    String? topic,
    int limit = 120,
  }) => search(cefr: cefr, topic: topic, limit: limit);

  /// A HEAD count. The old version selected 1000 ids and returned their
  /// length, which both moved a thousand rows to produce one number and
  /// silently reported 1000 forever once the shared dictionary passed that
  /// size — the one number whose whole point is that it keeps growing.
  Future<int> totalWords() =>
      supa.from('dictionary').count(CountOption.exact);
}
