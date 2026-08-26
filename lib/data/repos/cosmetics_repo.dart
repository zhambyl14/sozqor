// lib/data/repos/cosmetics_repo.dart
//
// The shop, server-side.
//
// Cosmetics used to live in SharedPreferences: a five-item hardcoded list,
// purchases stored on the device, and a frame nobody else could ever see. All
// three of those were the same mistake. The catalogue now lives in Postgres,
// so it grows without shipping an app build; ownership lives with the account,
// so a reinstall does not wipe it; and what someone is wearing is readable by
// everyone, which is the only reason a cosmetic is worth having.
//
// Buying and equipping are both server-authoritative — price, affordability
// and unlock conditions are re-checked in the RPC, so a tampered client cannot
// award itself anything.

import '../../core/i18n/l10n.dart';
import '../supa.dart';

/// One per equip slot on `profiles`, and one per value `cosmetics_kind_check`
/// allows. The enum used to stop at three, and `_kindOf` folded everything it
/// did not recognise into `avatar` — so every banner, badge and aura in the
/// catalogue arrived on the shop shelf labelled "Аватар" and drew itself with
/// the fallback 🙂, because a banner carries a colour and no emoji at all.
enum CosmeticKind { frame, title, avatar, banner, badge, aura }

CosmeticKind _kindOf(String raw) => switch (raw) {
  'frame'  => CosmeticKind.frame,
  'title'  => CosmeticKind.title,
  'banner' => CosmeticKind.banner,
  'badge'  => CosmeticKind.badge,
  'aura'   => CosmeticKind.aura,
  _        => CosmeticKind.avatar,
};

/// The section a kind is sold under, in the interface language.
String cosmeticKindLabel(CosmeticKind k) => switch (k) {
  CosmeticKind.frame  => tr('Аватар жиектері'),
  CosmeticKind.title  => tr('Атақтар'),
  CosmeticKind.avatar => tr('Аватарлар'),
  CosmeticKind.banner => tr('Баннерлер'),
  CosmeticKind.badge  => tr('Белгішелер'),
  CosmeticKind.aura   => tr('Ауралар'),
};

/// The same thing in one word, for a catalogue filter chip.
String cosmeticKindShort(CosmeticKind k) => switch (k) {
  CosmeticKind.frame  => tr('Жиек'),
  CosmeticKind.title  => tr('Атақ'),
  CosmeticKind.avatar => tr('Аватар'),
  CosmeticKind.banner => tr('Баннер'),
  CosmeticKind.badge  => tr('Белгіше'),
  CosmeticKind.aura   => tr('Аура'),
};

/// How hard something was to get. Drives nothing but presentation — the
/// server does not price by rarity, it just labels.
enum Rarity { common, rare, epic, legend }

Rarity _rarityOf(String raw) => switch (raw) {
  'rare'   => Rarity.rare,
  'epic'   => Rarity.epic,
  'legend' => Rarity.legend,
  _        => Rarity.common,
};

class Cosmetic {
  final String id;
  final CosmeticKind kind;
  final String nameKk, nameRu;
  final int price;
  final Rarity rarity;

  /// `metric:threshold` (e.g. `streak:30`) for the items that are earned
  /// rather than sold. Null for everything in the shop proper.
  final String? requires;

  /// Render payload the client reads generically: `color` for a frame,
  /// `emoji` for an avatar. A new item needs no client change.
  final Map<String, dynamic> data;

  final bool owned, unlocked, equipped;

  const Cosmetic({
    required this.id,
    required this.kind,
    required this.nameKk,
    required this.nameRu,
    required this.price,
    required this.rarity,
    required this.requires,
    required this.data,
    required this.owned,
    required this.unlocked,
    required this.equipped,
  });

  factory Cosmetic.fromMap(Map<String, dynamic> m) => Cosmetic(
    id:       (m['id'] ?? '').toString(),
    kind:     _kindOf((m['kind'] ?? '').toString()),
    nameKk:   (m['name_kk'] ?? '').toString(),
    nameRu:   (m['name_ru'] ?? '').toString(),
    price:    (m['price'] ?? 0) as int,
    rarity:   _rarityOf((m['rarity'] ?? '').toString()),
    requires: (m['requires'] as String?)?.trim().isEmpty ?? true
        ? null : m['requires'] as String,
    data:     m['data'] is Map
        ? Map<String, dynamic>.from(m['data'] as Map) : const {},
    owned:    m['owned'] == true,
    unlocked: m['unlocked'] == true,
    // The RPC's join can miss and answer null rather than false.
    equipped: m['equipped'] == true,
  );

  /// The catalogue is stored bilingually in the database rather than going
  /// through tr(), precisely so new items can be added server-side without an
  /// app release — there would be no key in ru.dart to translate them with.
  String get name => AppLang.isRu ? nameRu : nameKk;

  /// Earned by playing, never sold.
  bool get isReward => price == 0 && requires != null;

  /// The free default of its kind — always wearable, never bought.
  bool get isDefault => price == 0 && requires == null;

  /// Hex colour for a frame, as `#RRGGBB`. Null for other kinds.
  String? get color => data['color'] as String?;

  /// The character an avatar puts in the circle.
  String? get emoji => data['emoji'] as String?;

  /// The metric half of [requires], e.g. `streak`.
  String? get requiredMetric => requires?.split(':').first;

  /// The threshold half of [requires], e.g. 30.
  int get requiredAmount =>
      int.tryParse(requires?.split(':').last ?? '') ?? 0;
}

/// What one person is wearing, for rendering somebody *else* on a board.
///
/// `worn_cosmetics` has always returned all five renderable payloads; this
/// class only read the first two, which is why a badge or an aura somebody
/// paid thousands of XP for showed up nowhere.
class WornCosmetics {
  final String? frameId;
  final String? frameColor;

  /// The frame's second colour and its motion. Without these, everybody but
  /// the owner saw a flat ring: the effect was rendered from the shop
  /// catalogue, which only the owner's own profile reads. An item bought to
  /// be seen was invisible to exactly the people it was bought for.
  final String? frameColor2;
  final String? frameFx;
  final String? titleKk, titleRu;
  final String? bannerColor;
  final String? badgeEmoji;
  final String? auraColor;

  const WornCosmetics({
    this.frameId,
    this.frameColor,
    this.frameColor2,
    this.frameFx,
    this.titleKk,
    this.titleRu,
    this.bannerColor,
    this.badgeEmoji,
    this.auraColor,
  });

  String? get title {
    final t = AppLang.isRu ? titleRu : titleKk;
    return (t == null || t.isEmpty) ? null : t;
  }

  String? get badge => (badgeEmoji ?? '').isEmpty ? null : badgeEmoji;

  bool get isEmpty =>
      frameColor == null && title == null && badge == null &&
      bannerColor == null && auraColor == null;
}

class CosmeticsRepo {
  /// Every item plus this learner's ownership and equipped state, in one call.
  Future<List<Cosmetic>> catalogue() async {
    final res = await supa.rpc('shop_catalogue');
    return (res as List? ?? const [])
        .map((r) => Cosmetic.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Spends from `xp - xp_spent`. Never reduces `xp` itself — leagues rank on
  /// it, so a cosmetic must not quietly cost a place in a competition.
  /// Throws with the server's own reason: `not enough xp`, `locked`.
  Future<void> buy(String itemId) async {
    await supa.rpc('buy_cosmetic', params: {'p_item': itemId});
  }

  Future<void> equip(String itemId) async {
    await supa.rpc('equip_cosmetic', params: {'p_item': itemId});
  }

  /// What a list of people are wearing, keyed by user id. One call per list,
  /// never one per row.
  Future<Map<String, WornCosmetics>> worn(List<String> userIds) async {
    if (userIds.isEmpty) return const {};
    final res = await supa.rpc('worn_cosmetics',
        params: {'p_user_ids': userIds});
    final out = <String, WornCosmetics>{};
    for (final r in (res as List? ?? const [])) {
      final m = Map<String, dynamic>.from(r as Map);
      final id = (m['user_id'] ?? '').toString();
      if (id.isEmpty) continue;
      out[id] = WornCosmetics(
        frameId:     m['frame'] as String?,
        frameColor:  m['frame_color'] as String?,
        frameColor2: m['frame_color2'] as String?,
        frameFx:     m['frame_fx'] as String?,
        titleKk:     m['title_kk'] as String?,
        titleRu:     m['title_ru'] as String?,
        bannerColor: m['banner_color'] as String?,
        badgeEmoji:  m['badge_emoji'] as String?,
        auraColor:   m['aura_color'] as String?,
      );
    }
    return out;
  }
}
