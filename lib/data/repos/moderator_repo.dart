// lib/data/repos/moderator_repo.dart
//
// The owner's console, server side.
//
// Every call here is plain PostgREST: RLS already lets a moderator write to
// events, tournaments and cosmetics, so none of this needs an RPC.
//
// Nothing here deletes. Rows in `event_progress` and `user_cosmetics` point at
// these records, so removing one would erase progress a learner earned and
// items they paid XP for — retiring is `is_active = false`, which hides the
// row from `active_events` and `shop_catalogue` while leaving every reference
// intact.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/i18n/l10n.dart';
import '../models/dict_entry.dart';
import '../supa.dart';

/// Levels a piece of content can be aimed at, weakest first.
///
/// Deliberately its own list rather than `kCefrCodes`: these six are what the
/// `cefr_min` / `cefr_max` columns and `active_events` compare against, and
/// the console must keep matching the database even if the learner-facing
/// level list is ever reworded.
const List<String> kModCefr = ['A0', 'A1', 'A2', 'B1', 'B2', 'C1'];

/// Mirrors `events_kind_check`.
const List<String> kModEventKinds = [
  'challenge', 'topic_pack', 'tournament', 'season', 'quest',
];

/// Mirrors `cosmetics_kind_check` — one per equip slot on `profiles`.
const List<String> kModCosmeticKinds = [
  'frame', 'title', 'avatar', 'banner', 'badge', 'aura',
];

/// Mirrors `cosmetics_rarity_check`.
const List<String> kModRarities = ['common', 'rare', 'epic', 'legend'];

/// Position of a level in [kModCefr]; unknown codes read as the lowest, so a
/// stray value can never make a range look inverted.
int modCefrIndex(String code) {
  final i = kModCefr.indexOf(code);
  return i < 0 ? 0 : i;
}

/// Where a dated row sits relative to now — the one thing the hub has to show
/// at a glance, so it is computed once here instead of in every row widget.
enum ModPhase { running, upcoming, ended, retired }

/// The render payload key each cosmetic kind is read through.
///
/// `worn_cosmetics` reads `data->>'color'` for frames, banners and auras and
/// `data->>'emoji'` for badges and avatars; a title carries no payload at all
/// because its `name_kk` / `name_ru` *is* the text people see. An item saved
/// with the wrong key renders as nothing, so the editor asks for exactly one
/// of these.
String? modDataKeyFor(String kind) => switch (kind) {
  'frame' || 'banner' || 'aura' => 'color',
  'avatar' || 'badge' => 'emoji',
  _ => null,
};

// ═══════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════

class ModEvent {
  final int? id;
  final String slug;
  final String title, titleRu, subtitle, subtitleRu, emoji, kind;
  final String? topic;
  final String cefrMin, cefrMax;
  final String rulesKk, rulesRu, whoKk, whoRu;
  final int xpReward, target, prizeTopN;
  final String? prizeItem;
  final DateTime startsAt, endsAt;
  final bool isActive;

  /// Everything in `payload` the console does not edit, carried through a
  /// save so writing from the editor never drops a key another feature put
  /// there.
  final Map<String, dynamic> extra;

  const ModEvent({
    this.id,
    this.slug = '',
    required this.title,
    this.titleRu = '',
    this.subtitle = '',
    this.subtitleRu = '',
    this.emoji = '🎉',
    this.kind = 'challenge',
    this.topic,
    this.cefrMin = 'A0',
    this.cefrMax = 'C1',
    this.rulesKk = '',
    this.rulesRu = '',
    this.whoKk = '',
    this.whoRu = '',
    this.xpReward = 200,
    this.target = 10,
    this.prizeTopN = 0,
    this.prizeItem,
    required this.startsAt,
    required this.endsAt,
    this.isActive = true,
    this.extra = const {},
  });

  /// A week-long challenge open to everybody — the shape most events take, so
  /// the editor opens on something already savable.
  factory ModEvent.blank() {
    final now = DateTime.now();
    return ModEvent(
      title: '',
      startsAt: now,
      endsAt: now.add(const Duration(days: 7)),
    );
  }

  factory ModEvent.fromMap(Map<String, dynamic> m) {
    final payload =
        Map<String, dynamic>.from((m['payload'] as Map?) ?? const {});
    final target = int.tryParse('${payload.remove('target') ?? 10}') ?? 10;
    return ModEvent(
      id: (m['id'] as num?)?.toInt(),
      slug: (m['slug'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      titleRu: (m['title_ru'] ?? '').toString(),
      subtitle: (m['subtitle'] ?? '').toString(),
      subtitleRu: (m['subtitle_ru'] ?? '').toString(),
      emoji: (m['emoji'] ?? '🎉').toString(),
      kind: (m['kind'] ?? 'challenge').toString(),
      topic: (m['topic'] as String?)?.trim().isEmpty ?? true
          ? null
          : m['topic'] as String,
      cefrMin: (m['cefr_min'] ?? 'A0').toString(),
      cefrMax: (m['cefr_max'] ?? 'C1').toString(),
      rulesKk: (m['rules_kk'] ?? '').toString(),
      rulesRu: (m['rules_ru'] ?? '').toString(),
      whoKk: (m['who_kk'] ?? '').toString(),
      whoRu: (m['who_ru'] ?? '').toString(),
      xpReward: (m['xp_reward'] as num?)?.toInt() ?? 200,
      target: target,
      prizeTopN: (m['prize_top_n'] as num?)?.toInt() ?? 0,
      prizeItem: (m['prize_item'] as String?)?.trim().isEmpty ?? true
          ? null
          : m['prize_item'] as String,
      startsAt: DateTime.tryParse('${m['starts_at']}')?.toLocal() ??
          DateTime.now(),
      endsAt: DateTime.tryParse('${m['ends_at']}')?.toLocal() ??
          DateTime.now().add(const Duration(days: 7)),
      isActive: m['is_active'] != false,
      extra: payload,
    );
  }

  /// The row as PostgREST wants it. `slug`, `id` and `created_by` are left to
  /// the repository, which is the only place that knows whether this is an
  /// insert or an update.
  Map<String, dynamic> toRow() => {
    'title': title.trim(),
    'title_ru': titleRu.trim(),
    'subtitle': subtitle.trim(),
    'subtitle_ru': subtitleRu.trim(),
    'emoji': emoji.trim().isEmpty ? '🎉' : emoji.trim(),
    'kind': kind,
    'topic': topic,
    'cefr_min': cefrMin,
    'cefr_max': cefrMax,
    'rules_kk': rulesKk.trim(),
    'rules_ru': rulesRu.trim(),
    'who_kk': whoKk.trim(),
    'who_ru': whoRu.trim(),
    'xp_reward': xpReward,
    'prize_item': prizeItem,
    'prize_top_n': prizeTopN,
    'payload': {...extra, 'target': target},
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
    'is_active': isActive,
  };

  ModPhase get phase {
    if (!isActive) return ModPhase.retired;
    final now = DateTime.now();
    if (now.isBefore(startsAt)) return ModPhase.upcoming;
    if (now.isAfter(endsAt)) return ModPhase.ended;
    return ModPhase.running;
  }
}

class ModTournament {
  final int? id;
  final String title, emoji, cefrMin, cefrMax;
  final int xpReward;
  final DateTime startsAt, endsAt;

  const ModTournament({
    this.id,
    required this.title,
    this.emoji = '🏆',
    this.cefrMin = 'A0',
    this.cefrMax = 'C1',
    this.xpReward = 300,
    required this.startsAt,
    required this.endsAt,
  });

  /// A tournament runs for a day: `ensureTournament` builds daily ones, and a
  /// hand-made one that outlives its board would look broken next to them.
  factory ModTournament.blank() {
    final now = DateTime.now();
    return ModTournament(
      title: '',
      startsAt: now,
      endsAt: now.add(const Duration(days: 1)),
    );
  }

  factory ModTournament.fromMap(Map<String, dynamic> m) => ModTournament(
    id: (m['id'] as num?)?.toInt(),
    title: (m['title'] ?? '').toString(),
    emoji: (m['emoji'] ?? '🏆').toString(),
    cefrMin: (m['cefr_min'] ?? 'A0').toString(),
    cefrMax: (m['cefr_max'] ?? 'C1').toString(),
    xpReward: (m['xp_reward'] as num?)?.toInt() ?? 300,
    startsAt:
        DateTime.tryParse('${m['starts_at']}')?.toLocal() ?? DateTime.now(),
    endsAt: DateTime.tryParse('${m['ends_at']}')?.toLocal() ??
        DateTime.now().add(const Duration(days: 1)),
  );

  Map<String, dynamic> toRow() => {
    'title': title.trim(),
    'emoji': emoji.trim().isEmpty ? '🏆' : emoji.trim(),
    'cefr_min': cefrMin,
    'cefr_max': cefrMax,
    'xp_reward': xpReward,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
  };

  /// `tournaments` has no `is_active`, so a tournament is never retired — it
  /// only ever runs, waits or is over.
  ModPhase get phase {
    final now = DateTime.now();
    if (now.isBefore(startsAt)) return ModPhase.upcoming;
    if (now.isAfter(endsAt)) return ModPhase.ended;
    return ModPhase.running;
  }
}

class ModCosmetic {
  final String id, kind, nameKk, nameRu, rarity;
  final int price, sort;
  final String? requires;
  final Map<String, dynamic> data;
  final bool isActive;

  const ModCosmetic({
    required this.id,
    this.kind = 'frame',
    this.nameKk = '',
    this.nameRu = '',
    this.rarity = 'common',
    this.price = 0,
    this.sort = 0,
    this.requires,
    this.data = const {},
    this.isActive = true,
  });

  factory ModCosmetic.blank() => const ModCosmetic(id: '');

  factory ModCosmetic.fromMap(Map<String, dynamic> m) => ModCosmetic(
    id: (m['id'] ?? '').toString(),
    kind: (m['kind'] ?? 'frame').toString(),
    nameKk: (m['name_kk'] ?? '').toString(),
    nameRu: (m['name_ru'] ?? '').toString(),
    rarity: (m['rarity'] ?? 'common').toString(),
    price: (m['price'] as num?)?.toInt() ?? 0,
    sort: (m['sort'] as num?)?.toInt() ?? 0,
    requires: (m['requires'] as String?)?.trim().isEmpty ?? true
        ? null
        : m['requires'] as String,
    data: m['data'] is Map
        ? Map<String, dynamic>.from(m['data'] as Map)
        : const {},
    isActive: m['is_active'] != false,
  );

  /// `id` is left out: it is the primary key, so it goes in on an insert and
  /// is never part of an update.
  Map<String, dynamic> toRow() => {
    'kind': kind,
    'name_kk': nameKk.trim(),
    'name_ru': nameRu.trim(),
    'rarity': rarity,
    'price': price,
    'sort': sort,
    'requires': requires,
    'data': data,
    'is_active': isActive,
  };

  /// The one payload value this kind renders through, or null for a title.
  String? get payload {
    final key = modDataKeyFor(kind);
    if (key == null) return null;
    return data[key]?.toString();
  }
}

// ═══════════════════════════════════════════════════════════
// Repository
// ═══════════════════════════════════════════════════════════

class ModeratorRepo {
  /// Whether the signed-in account may run the console.
  ///
  /// A failed lookup answers "no": the console is the one place where guessing
  /// generously would be the wrong way to be wrong.
  Future<bool> amModerator() async {
    final uid = currentUid;
    if (uid == null) return false;
    try {
      final row =
          await supa.from('profiles').select('role').eq('id', uid).maybeSingle();
      final role = (row?['role'] ?? 'user').toString();
      return role == 'moderator' || role == 'admin';
    } catch (_) {
      return false;
    }
  }

  // ── Events ───────────────────────────────────────────────
  Future<List<ModEvent>> events() async {
    final rows = await supa
        .from('events')
        .select()
        .order('is_active', ascending: false)
        .order('starts_at', ascending: false);
    return [
      for (final r in rows as List)
        ModEvent.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<ModEvent> saveEvent(ModEvent e) async {
    final row = e.toRow();
    if (e.id == null) {
      row['slug'] = await _freeSlug(slugify(e.title));
      row['created_by'] = currentUid;
      final out = await supa.from('events').insert(row).select().single();
      return ModEvent.fromMap(out);
    }
    final out = await supa
        .from('events')
        .update(row)
        .eq('id', e.id!)
        .select()
        .single();
    return ModEvent.fromMap(out);
  }

  /// Takes an event out of circulation without touching anybody's progress.
  Future<void> setEventActive(int id, bool active) async {
    await supa.from('events').update({'is_active': active}).eq('id', id);
  }

  /// A url-safe key for a new event.
  ///
  /// Slugs are generated, never typed: `events.slug` is unique and nothing in
  /// the app ever shows it, so asking the owner to invent one would only add a
  /// field that can fail.
  static String slugify(String title) {
    final buf = StringBuffer();
    for (final ch in title.toLowerCase().split('')) {
      final mapped = _translit[ch];
      if (mapped != null) {
        buf.write(mapped);
      } else if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
        buf.write(ch);
      } else {
        buf.write('-');
      }
    }
    var slug = buf
        .toString()
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.length > 40) slug = slug.substring(0, 40);
    slug = slug.replaceAll(RegExp(r'-+$'), '');
    return slug.isEmpty ? 'event' : slug;
  }

  /// The first free variant of [base]. A repeated title is normal — "Апта
  /// сайынғы сын" every week — and must not fail on the unique index.
  Future<String> _freeSlug(String base) async {
    final rows =
        await supa.from('events').select('slug').like('slug', '$base%');
    final taken = {
      for (final r in rows as List) ((r as Map)['slug'] ?? '').toString(),
    };
    if (!taken.contains(base)) return base;
    for (var i = 2; i < 500; i++) {
      if (!taken.contains('$base-$i')) return '$base-$i';
    }
    return '$base-${DateTime.now().millisecondsSinceEpoch}';
  }

  // ── Tournaments ──────────────────────────────────────────
  Future<List<ModTournament>> tournaments() async {
    final rows = await supa
        .from('tournaments')
        .select()
        .order('starts_at', ascending: false);
    return [
      for (final r in rows as List)
        ModTournament.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<ModTournament> saveTournament(ModTournament t) async {
    final row = t.toRow();
    if (t.id == null) {
      final out = await supa.from('tournaments').insert(row).select().single();
      return ModTournament.fromMap(out);
    }
    final out = await supa
        .from('tournaments')
        .update(row)
        .eq('id', t.id!)
        .select()
        .single();
    return ModTournament.fromMap(out);
  }

  // ── Shop ─────────────────────────────────────────────────
  Future<List<ModCosmetic>> cosmetics() async {
    final rows = await supa
        .from('cosmetics')
        .select()
        .order('is_active', ascending: false)
        .order('kind')
        .order('sort');
    return [
      for (final r in rows as List)
        ModCosmetic.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Checked before an insert so a clash is an error next to the id field
  /// rather than a raw unique-violation from Postgres.
  Future<bool> cosmeticExists(String id) async {
    final row =
        await supa.from('cosmetics').select('id').eq('id', id).maybeSingle();
    return row != null;
  }

  Future<ModCosmetic> saveCosmetic(ModCosmetic c, {required bool isNew}) async {
    final row = c.toRow();
    if (isNew) {
      row['id'] = c.id.trim();
      row['created_by'] = currentUid;
      final out = await supa.from('cosmetics').insert(row).select().single();
      return ModCosmetic.fromMap(out);
    }
    final out = await supa
        .from('cosmetics')
        .update(row)
        .eq('id', c.id)
        .select()
        .single();
    return ModCosmetic.fromMap(out);
  }

  /// Pulls an item from the shop. Anybody already wearing it keeps it —
  /// `user_cosmetics` is untouched.
  Future<void> setCosmeticActive(String id, bool active) async {
    await supa.from('cosmetics').update({'is_active': active}).eq('id', id);
  }
}

/// Kazakh and Russian Cyrillic to latin, for [ModeratorRepo.slugify].
const Map<String, String> _translit = {
  'а': 'a', 'ә': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'ғ': 'g', 'д': 'd',
  'е': 'e', 'ё': 'yo', 'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'i', 'к': 'k',
  'қ': 'q', 'л': 'l', 'м': 'm', 'н': 'n', 'ң': 'ng', 'о': 'o', 'ө': 'o',
  'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ұ': 'u', 'ү': 'u',
  'ф': 'f', 'х': 'h', 'һ': 'h', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'sch',
  'ъ': '', 'ы': 'y', 'і': 'i', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
};

// ═══════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════
//
// The console keeps its providers next to its repository instead of in
// providers.dart: it is one self-contained feature, and providers.dart
// re-exports these names so screens still need only the one import.

final moderatorRepoProvider = Provider((_) => ModeratorRepo());

// ── The dictionary (EN-33 / EN-38 / EN-50 / KK-7) ──────────
//
// Until 5.0 this repo managed events, tournaments and shop items and never
// touched the dictionary, and dictionary_repo.dart is read-only. So the only
// writer was dict_upsert from the AI edge function, and no human could correct
// a wrong translation, add a word at a level, or remove a bad entry — every
// mistake the model made was permanent.

/// One page of dictionary rows for the console, unverified first.
Future<List<DictEntry>> _dictRows(dynamic res) => Future.value([
  for (final r in (res as List? ?? const []))
    DictEntry.fromMap(Map<String, dynamic>.from(r as Map)),
]);

extension ModeratorDictionary on ModeratorRepo {
  Future<List<DictEntry>> dictionary({
    String query = '',
    String? cefr,
    String? topic,
    bool? verified,
    String? source,
    int limit = 20,
    int offset = 0,
  }) async => _dictRows(await supa.rpc('dict_admin_list', params: {
        'p_query': query.trim(),
        'p_cefr': cefr,
        'p_topic': topic,
        'p_verified': verified,
        'p_source': source,
        'p_limit': limit,
        'p_offset': offset,
      }));

  /// An honest total for the header. DictionaryRepo.totalWords() selected a
  /// thousand ids and returned their length, so it both moved a thousand rows
  /// to produce one number and silently reported 1000 for ever once the
  /// dictionary passed that size.
  Future<int> dictionaryCount({
    String query = '',
    String? cefr,
    String? topic,
    bool? verified,
    String? source,
  }) async => ((await supa.rpc('dict_count', params: {
        'p_query': query.trim(),
        'p_cefr': cefr,
        'p_topic': topic,
        'p_verified': verified,
        'p_source': source,
      }) ?? 0) as num).toInt();

  Future<DictEntry> saveWord({
    int? id,
    required String en,
    required String kk,
    String? ru,
    String? pos,
    String? definitionEn,
    String? exampleEn,
    String? ipa,
    String? emoji,
    String cefr = 'A2',
    String topic = 'general',
    List<String> synonyms = const [],
    List<String> antonyms = const [],
    bool verified = true,
  }) async {
    final row = await supa.rpc('dict_admin_upsert', params: {
      'p_id': id,
      'p_en': en.trim(),
      'p_kk': kk.trim(),
      'p_ru': (ru ?? '').trim().isEmpty ? null : ru!.trim(),
      'p_pos': pos,
      'p_definition_en': definitionEn,
      'p_example_en': exampleEn,
      'p_ipa': ipa,
      'p_emoji': emoji,
      'p_cefr': cefr,
      'p_topic': topic,
      'p_synonyms': synonyms,
      'p_antonyms': antonyms,
      'p_verified': verified,
    });
    return DictEntry.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Deleting detaches every learner's copy first. The words themselves
  /// survive — somebody has been studying them, and a bad shared entry is not
  /// a reason to empty their bank.
  Future<void> deleteWord(int id) =>
      supa.rpc('dict_admin_delete', params: {'p_id': id});

  Future<int> setLevel(List<int> ids, String cefr) async =>
      ((await supa.rpc('dict_admin_set_cefr',
          params: {'p_ids': ids, 'p_cefr': cefr}) ?? 0) as num).toInt();

  Future<int> setVerified(List<int> ids, bool verified) async =>
      ((await supa.rpc('dict_admin_set_verified',
          params: {'p_ids': ids, 'p_verified': verified}) ?? 0) as num).toInt();

  // ── The translation review queue (EN-49 / EN-50) ────────
  /// What the translation gate refused. Refusing a bad translation is only
  /// half an answer if nobody can then supply a good one.
  Future<List<TranslationReport>> translationQueue({
    String status = 'open',
    int limit = 40,
    int offset = 0,
  }) async {
    final rows = await supa.rpc('translation_queue', params: {
      'p_status': status, 'p_limit': limit, 'p_offset': offset,
    });
    return [
      for (final r in (rows as List? ?? const []))
        TranslationReport.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Writes the correction and closes every open report for that word at once
  /// — a term that failed nine times should not need closing nine times.
  Future<void> fixTranslation(int id, {
    required String en,
    required String kk,
    String? ru,
  }) => supa.rpc('translation_fix', params: {
        'p_id': '$id',
        'p_en': en.trim(),
        'p_kk': kk.trim(),
        'p_ru': (ru ?? '').trim().isEmpty ? null : ru!.trim(),
      });

  Future<void> dismissTranslation(int id) =>
      supa.rpc('translation_dismiss', params: {'p_id': '$id'});
}

/// One refusal from the translation gate.
class TranslationReport {
  final int id, failCount;
  final String term, candidate, failedCheck, provider, status;
  final String? sourceLang, targetLang, currentEn, currentKk, currentRu;

  const TranslationReport({
    required this.id,
    required this.term,
    this.candidate = '',
    this.failedCheck = '',
    this.provider = '',
    this.status = 'open',
    this.failCount = 1,
    this.sourceLang,
    this.targetLang,
    this.currentEn,
    this.currentKk,
    this.currentRu,
  });

  factory TranslationReport.fromMap(Map<String, dynamic> m) =>
      TranslationReport(
        id:          ((m['id'] ?? 0) as num).toInt(),
        term:        (m['term'] ?? '').toString(),
        candidate:   (m['candidate'] ?? '').toString(),
        failedCheck: (m['failed_check'] ?? '').toString(),
        provider:    (m['provider'] ?? '').toString(),
        status:      (m['status'] ?? 'open').toString(),
        failCount:   ((m['fail_count'] ?? 1) as num).toInt(),
        sourceLang:  m['source_lang']?.toString(),
        targetLang:  m['target_lang']?.toString(),
        currentEn:   m['current_en']?.toString(),
        currentKk:   m['current_kk']?.toString(),
        currentRu:   m['current_ru']?.toString(),
      );

  /// Why the gate said no, in the app language.
  String get reason => switch (failedCheck) {
    'translit'   => tr('Транслитерация — аударма емес'),
    'script'     => tr('Жазуы дұрыс емес'),
    'identity'   => tr('Жауап сұрақтың өзі'),
    'length'     => tr('Ұзындығы келмейді'),
    'disagree'   => tr('Екі модель келіспеді'),
    'confidence' => tr('Сенімділік төмен'),
    _            => failedCheck,
  };
}

/// Its own subscription to the auth stream rather than a reach back into
/// providers.dart — a guest who signs in as the owner has to see the console
/// entrance appear without restarting the app.
final _modAuthProvider =
    StreamProvider<AuthState>((_) => supa.auth.onAuthStateChange);

/// Whether the current account may open the console. Both the entrance and
/// the console itself read this, so there is one place to be wrong about it.
final amModeratorProvider = FutureProvider<bool>((ref) {
  ref.watch(_modAuthProvider);
  return ref.watch(moderatorRepoProvider).amModerator();
});

/// The three catalogues, newest and still-live first. `autoDispose` because
/// nobody but the console reads them: leaving it drops the data, and coming
/// back re-reads a list the owner may have changed from the dashboard.
final modEventsProvider = FutureProvider.autoDispose<List<ModEvent>>(
    (ref) => ref.watch(moderatorRepoProvider).events());

final modTournamentsProvider = FutureProvider.autoDispose<List<ModTournament>>(
    (ref) => ref.watch(moderatorRepoProvider).tournaments());

final modCosmeticsProvider = FutureProvider.autoDispose<List<ModCosmetic>>(
    (ref) => ref.watch(moderatorRepoProvider).cosmetics());
