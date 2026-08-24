// lib/data/repos/dictionary_repo.dart
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

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
