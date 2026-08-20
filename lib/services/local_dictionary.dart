// lib/services/local_dictionary.dart
//
// The offline half of SozQor's brain: a starter dictionary bundled with the
// app so the very first translation, and every repeat lookup, is instant and
// free — no network, no LLM quota.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../data/models/dict_entry.dart';

class LocalDictionary {
  LocalDictionary._();
  static final LocalDictionary instance = LocalDictionary._();

  final Map<String, DictEntry> _byEn = {};
  final Map<String, DictEntry> _byKk = {};
  final Map<String, DictEntry> _byRu = {};
  List<DictEntry> _all = const [];
  bool _loaded = false;

  static String norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/data/starter_dictionary.json');
      final list = jsonDecode(raw) as List;
      _all = list
          .map((e) => DictEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      for (final e in _all) {
        _byEn.putIfAbsent(norm(e.en), () => e);
        _byKk.putIfAbsent(norm(e.kk), () => e);
        final ru = e.ru;
        if (ru != null && ru.trim().isNotEmpty) {
          _byRu.putIfAbsent(norm(ru), () => e);
        }
      }
    } catch (_) {
      _all = const [];
    }
    _loaded = true;
  }

  bool get isLoaded => _loaded;
  int  get size     => _all.length;
  List<DictEntry> get entries => _all;

  /// Exact hit in any of the three languages. The learner can type Kazakh,
  /// Russian or English and never has to say which.
  DictEntry? lookup(String term) {
    final t = norm(term);
    if (t.isEmpty) return null;
    return _byEn[t] ??
        _byKk[t] ??
        _byRu[t] ??
        // tolerate a missing "to " on English verbs
        _byEn['to $t'] ??
        (t.startsWith('to ') ? _byEn[t.substring(3)] : null);
  }

  /// Prefix/contains matches for the search field, across all languages.
  List<DictEntry> search(String query, {int limit = 20}) {
    final q = norm(query);
    if (q.isEmpty) return const [];
    final out = <DictEntry>[];
    for (final e in _all) {
      if (norm(e.en).contains(q) ||
          norm(e.kk).contains(q) ||
          norm(e.ru ?? '').contains(q)) {
        out.add(e);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  List<DictEntry> byLevels(List<String> cefr, {String? topic}) => _all
      .where((e) => cefr.contains(e.cefr) && (topic == null || e.topic == topic))
      .toList();
}
