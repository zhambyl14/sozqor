// lib/features/profile/shop_screen.dart
//
// The shop.
//
// XP had exactly one use in 3.0 — a level number that went up. That is a
// scoreboard, not a reward. The shop gives progress somewhere to go: avatar
// frames, titles, avatars, plus the consumables that keep a streak alive.
//
// The catalogue comes from the server, not from a list compiled into the app,
// so it can grow without a release — which is also why an item renders from
// its own data (a hex colour, an emoji) instead of a switch over known ids.
//
// All six kinds are shelved here. Three of them — banners, badges and auras —
// used to fall through the client's three-value enum and land in the avatar
// section drawn as a blank 🙂, which is a third of the shop mislabelled and
// unrecognisable. With sixty-odd items the shelf also needs a way in, so the
// kinds are a filter across the top and what is currently worn sits above
// them: the two questions anybody opening a shop actually has.
//
// 5.0 buys with coins rather than XP (EN-42 / KK-6). Leagues and leaderboards
// rank on total XP, so spending it meant a cosmetic quietly cost a place in a
// competition the learner did not know they were spending from. `xp_spent`
// was already a currency in XP's clothes; `coins` is the same idea said out
// loud, and it has been accruing on every award since before this release.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/cosmetics_repo.dart';
import 'cosmetic_preview.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../home/missions_screen.dart';

/// Rarity is the shop's whole visual language: four tiers a learner can tell
/// apart at a glance, so a legend never reads like a common.
({Color tint, String Function() label}) _rarity(Rarity r) => switch (r) {
  Rarity.common => (tint: AppColors.sky,     label: () => tr('Қарапайым')),
  Rarity.rare   => (tint: AppColors.green,   label: () => tr('Сирек')),
  Rarity.epic   => (tint: AppColors.primary, label: () => tr('Эпик')),
  Rarity.legend => (tint: AppColors.amber,   label: () => tr('Аңыз')),
};

/// What an unlock condition asks for, in words. The server stores it as
/// `metric:threshold`; only the metric needs translating.
String _requirement(Cosmetic c) => switch (c.requiredMetric) {
  'streak'        => trp('{n} күндік серия', {'n': '${c.requiredAmount}'}),
  'battles_won'   => trp('{n} баттл жеңу', {'n': '${c.requiredAmount}'}),
  'words_total'   => trp('{n} сөз жинау', {'n': '${c.requiredAmount}'}),
  'words_learned' => trp('{n} сөзді меңгеру', {'n': '${c.requiredAmount}'}),
  'xp'            => trp('{n} тәжірибе жинау', {'n': '${c.requiredAmount}'}),
  'elo'           => trp('{n} Elo рейтинг', {'n': '${c.requiredAmount}'}),
  _               => tr('Ойнап аш'),
};

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  /// The item currently being bought or equipped, so its own row can show the
  /// wait instead of freezing the whole page.
  String? _busyId;

  /// Which shelf is open, or null for the whole catalogue.
  CosmeticKind? _kind;

  Future<void> _run(String itemId, Future<void> Function() action) async {
    if (_busyId != null) return;
    setState(() => _busyId = itemId);
    try {
      await action();
      ref.invalidate(shopCatalogueProvider);
      ref.invalidate(myProfileProvider);
    } catch (e) {
      if (mounted) sqSnack(context, _reason(e), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// The buy RPC raises with a short machine reason; everything else goes
  /// through the app's usual translator.
  String _reason(Object e) {
    final raw = e.toString();
    // The RPC raised 'not enough xp' before coins existed; the new one says
    // so in Kazakh through GUEST_LOCKED, which humanError already unwraps.
    if (raw.contains('not enough xp') || raw.contains('Тиын жетпей')) {
      return tr('Тиын жетпей тұр — тағы бір раунд ойна');
    }
    if (raw.contains('locked')) return tr('Бұл әлі ашылмаған');
    if (raw.contains('not owned')) return tr('Алдымен сатып ал');
    return humanError(e);
  }

  Future<void> _buy(Cosmetic c) async {
    final ok = await sqConfirm(context,
      title: c.name,
      message: trp('{p1} тиын жұмсап аласың ба?', {'p1': '${c.price}'}),
      confirm: tr('Сатып алу'),
      cancel: tr('Кейін'),
      danger: false);
    if (!ok) return;
    await _run(c.id, () async {
      await ref.read(cosmeticsRepoProvider).buy(c.id);
      // Buying is the moment worth wearing it — one tap instead of two.
      await ref.read(cosmeticsRepoProvider).equip(c.id);
      if (mounted) sqSnack(context, trp('«{p1}» алынды', {'p1': c.name}));
    });
  }

  Future<void> _equip(Cosmetic c) => _run(c.id, () async {
    await ref.read(cosmeticsRepoProvider).equip(c.id);
    if (mounted) sqSnack(context, trp('«{p1}» киілді', {'p1': c.name}));
  });

  void _onTap(Cosmetic c, int coins) {
    if (c.equipped) return;
    if (c.owned || c.isDefault) {
      _equip(c);
      return;
    }
    if (c.isReward) {
      sqSnack(context, c.unlocked
          ? tr('Ашылды — киюге болады')
          : trp('Ашу үшін: {p1}', {'p1': _requirement(c)}),
        error: !c.unlocked);
      if (c.unlocked) _equip(c);
      return;
    }
    if (coins < c.price) {
      sqSnack(context,
        trp('{p1} тиын жетпей тұр — тағы бір раунд ойна',
            {'p1': '${c.price - coins}'}),
        error: true);
      return;
    }
    _buy(c);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final meta = ref.watch(metaProvider);
    final coins = ref.watch(coinsProvider);
    final async = ref.watch(shopCatalogueProvider);

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: () async {
        ref.invalidate(shopCatalogueProvider);
        ref.invalidate(myProfileProvider);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        SqHeader(
          title: tr('Дүкен'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        _Balance(coins: coins, onEarn: () => goTab(ref, SqTab.play)),
        const SizedBox(height: 16),

        if (meta.freezes > 0 || meta.lives > 0) ...[
          SqEqualRow(
            children: [
              Expanded(child: SqStat(
                icon: PhosphorIconsFill.snowflake, tint: AppColors.sky,
                value: '${meta.freezes}', label: tr('мұздатқыш'))),
              const SizedBox(width: 9),
              Expanded(child: SqStat(
                icon: PhosphorIconsFill.heart, tint: AppColors.red,
                value: '${meta.lives}', label: tr('қосымша жан'))),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Spread, not nested. Every section is a child of the page's own
        // ListView, so the sliver can skip the ones that are off screen.
        // Wrapped in a Column they were a single render object: all eighty-odd
        // items laid out and painted on every frame, a couple of dozen of them
        // carrying blurred shadows, which is why opening the shop stopped the
        // app dead rather than merely stuttering.
        ...async.when(
          loading: () => const <Widget>[
            SqShimmer(), SqShimmer(), SqShimmer()],
          error: (e, _) => <Widget>[SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            title: tr('Дүкен жүктелмеді'),
            subtitle: humanError(e),
            tint: AppColors.red)],
          data: (items) {
            if (items.isEmpty) {
              return <Widget>[SqEmpty(
                icon: PhosphorIconsFill.storefront,
                title: tr('Дүкен әзірге бос'),
                subtitle: tr('Жақында жаңа заттар қосылады'))];
            }
            // Only kinds the server actually stocks get a shelf, so retiring
            // every banner leaves no empty "Баннерлер" heading behind.
            final kinds = [
              for (final k in CosmeticKind.values)
                if (items.any((c) => c.kind == k)) k,
            ];
            final open = _kind != null && kinds.contains(_kind)
                ? [_kind!] : kinds;

            return <Widget>[
              _Wearing(items: items),
              _KindFilter(
                kinds: kinds,
                selected: kinds.contains(_kind) ? _kind : null,
                ownedOf: (k) => items
                    .where((c) => c.kind == k && (c.owned || c.isDefault))
                    .length,
                totalOf: (k) => items.where((c) => c.kind == k).length,
                onPick: (k) => setState(() => _kind = k)),
              const SizedBox(height: 18),
              for (final k in open)
                ..._section(items, k, cosmeticKindLabel(k), coins),
            ];
          },
        ),

        const SizedBox(height: 4),
        SqPanel(
          radius: 20,
          padding: const EdgeInsets.all(16),
          fill: AppColors.soft(AppColors.primary, d),
          border: AppColors.line(AppColors.primary, d),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MissionsScreen())),
          child: Row(
            children: [
              const SqTintBox(PhosphorIconsFill.medal,
                size: 40, solid: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Миссия жолы'),
                      style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: AppColors.text(d))),
                    Text(tr('Скиндерді тегін ашудың жолы'),
                      style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: AppColors.onSoft(AppColors.primary, d))),
                  ],
                ),
              ),
              Icon(PhosphorIconsBold.caretRight,
                size: 16, color: AppColors.onSoft(AppColors.primary, d)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(tr('Тиын әр ойыннан жиналады. Тәжірибең азаймайды.'),
          style: TextStyle(
            fontSize: 11, height: 1.5, fontWeight: FontWeight.w600,
            color: AppColors.text4(d))),
      ],
    );
  }

  List<Widget> _section(
    List<Cosmetic> all,
    CosmeticKind kind,
    String title,
    int coins,
  ) {
    // The free default of each kind is the "take it off again" option, which
    // belongs with the rest of its group rather than looking like a product.
    final items = all.where((c) => c.kind == kind).toList();
    if (items.isEmpty) return const [];
    final owned = items.where((c) => c.owned || c.isDefault).length;

    return [
      SqSection(title,
        trailingWidget: SqNum('$owned / ${items.length}',
          size: 11, color: AppColors.text3(isDark(context)))),
      SqGroup(children: [
        for (final c in items)
          _CosmeticRow(
            item: c,
            affordable: coins >= c.price,
            busy: _busyId == c.id,
            onTap: () => _onTap(c, coins),
          ),
      ]),
      const SizedBox(height: 18),
    ];
  }
}

class _Balance extends StatelessWidget {
  final int coins;
  final VoidCallback onEarn;
  const _Balance({required this.coins, required this.onEarn});

  @override
  Widget build(BuildContext context) => SqInkCard(
    padding: const EdgeInsets.all(17),
    glow: AppColors.amber,
    child: Row(
      children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: AppColors.amber,
            borderRadius: BorderRadius.circular(16)),
          child: const Icon(PhosphorIconsFill.coin,
            size: 23, color: AppColors.ink),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SqEyebrow(tr('Жұмсауға болады'), color: AppColors.onInk2),
              const SizedBox(height: 2),
              SqCountUp(coins, size: 24, color: Colors.white),
            ],
          ),
        ),
        SqLip(
          fill: Colors.white.withValues(alpha: 0.10),
          border: Colors.white.withValues(alpha: 0.16),
          radius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          onTap: onEarn,
          child: Text(tr('Тиын табу'),
            style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w800,
              color: Colors.white)),
        ),
      ],
    ),
  );
}

class _CosmeticRow extends StatelessWidget {
  final Cosmetic item;
  final bool affordable, busy;
  final VoidCallback onTap;

  const _CosmeticRow({
    required this.item,
    required this.affordable,
    required this.busy,
    required this.onTap});

  /// Every item previews the thing it actually is, from its own payload: a
  /// frame shows its ring, a banner its stripe, an aura its glow, a badge and
  /// an avatar their character. Nothing here switches over known ids, so an
  /// item the moderator adds tonight draws itself correctly tomorrow.
  Widget _preview(BuildContext context) =>
      cosmeticPreview(context, item, size: 48);

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final rarity = _rarity(item.rarity);

    final String subtitle;
    if (item.isDefault) {
      subtitle = tr('Әдепкі');
    } else if (item.isReward) {
      subtitle = item.unlocked
          ? tr('Ашылды')
          : trp('Ашу үшін: {p1}', {'p1': _requirement(item)});
    } else {
      subtitle = rarity.label();
    }

    return SqTile(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      leading: Opacity(
        // A locked reward is dimmed rather than hidden: seeing what is behind
        // the streak is the reason to keep the streak.
        opacity: item.isReward && !item.unlocked ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // The rarity as light around the item, so an epic reads as epic
            // across the room instead of only in the word underneath it.
            boxShadow: item.isDefault
                ? null
                : [BoxShadow(
                    color: rarity.tint.withValues(alpha: 0.30),
                    blurRadius: 14, spreadRadius: 1)],
          ),
          child: _preview(context),
        ),
      ),
      title: item.name,
      subtitle: subtitle,
      trailing: busy
          ? const SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2))
          : _action(d),
      onTap: busy ? null : onTap,
    );
  }

  Widget _action(bool d) {
    if (item.equipped) {
      return SqBadge(tr('Киілген'),
        tint: AppColors.green, size: 11);
    }
    if (item.owned || item.isDefault) {
      return SqBadge(tr('Кию'),
        tint: AppColors.primary, solid: true, size: 11);
    }
    if (item.isReward) {
      return Icon(
        item.unlocked ? PhosphorIconsFill.lockOpen : PhosphorIconsFill.lock,
        size: 18,
        color: item.unlocked ? AppColors.green : AppColors.text4(d));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        SqNum(trp('{n} тиын', {'n': '${item.price}'}),
          size: 12,
          color: affordable ? AppColors.amberInk : AppColors.text4(d)),
        const SizedBox(height: 5),
        SqBadge(tr('Сатып алу'),
          tint: affordable ? AppColors.ink : AppColors.text4(d),
          solid: affordable,
          size: 11),
      ],
    );
  }
}

/// The swatch a cosmetic is recognised by. Shared with the "wearing now"
/// strip so an item never looks like two different things.
/// What an item looks like, drawn from its own payload.
///
/// This used to be a flat disc of one colour for a frame, a plain stripe for
/// a banner and a ring for an aura — which is precisely why the shop looked
/// like nothing worth buying: the animated renderer already existed in
/// cosmetic_preview.dart and the shop was not using it. A frame now previews
/// with its real gradient and its real motion, so what you pay for is what
/// you saw.
///
/// Nothing here switches over known ids, so an item a moderator adds tonight
/// draws itself correctly tomorrow.
/// Everything below is wrapped in a [RepaintBoundary] by [cosmeticPreview]:
/// a shelf is dozens of gradients and a fair few blurs, and without a boundary
/// each one is redrawn on every pixel of scroll.
Widget _preview(BuildContext context, Cosmetic item, double size) {
  final d = isDark(context);
  final color = sqHexColor(item.color);
  final second = frameSecondOf(item.data) ?? color;
  final tint = _rarity(item.rarity).tint;

  switch (item.kind) {
    case CosmeticKind.frame:
      // The real thing: gradient, sweep, shimmer or pulse, exactly as it will
      // look on the profile and above the opponent's head in a battle.
      return CosmeticAvatar(
        name: item.name,
        emoji: '🙂',
        size: size,
        frame: color ?? AppColors.muted(d),
        frameSecond: second,
        fx: frameFxOf(item.data),
        // Caught mid-turn rather than turning: see the note on `still`.
        still: true,
      );

    case CosmeticKind.avatar:
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.soft(tint, d),
              AppColors.line(tint, d),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(size * 0.33)),
        alignment: Alignment.center,
        child: Text(item.emoji ?? '🙂',
          style: TextStyle(fontSize: size * 0.52)),
      );

    case CosmeticKind.badge:
      // A badge rides next to a name at a fraction of this size, so it is
      // previewed on a disc of its own with the rarity's light behind it.
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [AppColors.soft(tint, d), AppColors.line(tint, d)]),
          boxShadow: [
            BoxShadow(
              color: tint.withValues(alpha: 0.35),
              blurRadius: size * 0.28, spreadRadius: size * 0.02),
          ],
        ),
        alignment: Alignment.center,
        child: Text(item.emoji ?? '•',
          style: TextStyle(fontSize: size * 0.45)),
      );

    case CosmeticKind.banner:
      // A banner is a wide strip behind a name, so the preview is that strip
      // — with the diagonal sheen it actually carries, not a flat bar.
      final base = color ?? tint;
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: AppColors.muted(d),
          borderRadius: BorderRadius.circular(size * 0.28)),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    base,
                    Color.lerp(base, Colors.black, 0.35) ?? base,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              ),
            ),
            // The highlight that makes a flat rectangle read as a surface.
            Transform.rotate(
              angle: -0.6,
              child: FractionallySizedBox(
                widthFactor: 0.42,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.00),
                        Colors.white.withValues(alpha: 0.28),
                        Colors.white.withValues(alpha: 0.00),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

    case CosmeticKind.aura:
      // An aura is light around an avatar; the preview is that light, at the
      // strength it will actually have.
      final glow = color ?? tint;
      return SizedBox(
        width: size, height: size,
        child: Center(
          child: Container(
            width: size * 0.60, height: size * 0.60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.card(d),
                glow.withValues(alpha: 0.35),
              ]),
              border: Border.all(color: glow, width: 2),
              boxShadow: [
                BoxShadow(
                  color: glow.withValues(alpha: 0.60),
                  blurRadius: size * 0.34, spreadRadius: size * 0.08),
              ],
            ),
          ),
        ),
      );

    case CosmeticKind.title:
      // A title is words in the frame's colour, so the preview is the word
      // itself rather than a generic seal that told you nothing.
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: LinearGradient(
            colors: [AppColors.soft(tint, d), AppColors.line(tint, d)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        ),
        alignment: Alignment.center,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: size * 0.08),
          child: FittedBox(
            child: Text(
              item.name.isEmpty ? 'A' : item.name.characters.first.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.onSoft(tint, d)),
            ),
          ),
        ),
      );
  }
}

Widget cosmeticPreview(BuildContext context, Cosmetic item,
        {double size = 44}) =>
    RepaintBoundary(child: _preview(context, item, size));

/// What the learner is wearing right now, read straight out of the catalogue
/// rather than from a second request.
///
/// Without this the shop could say what a thing costs but never what you
/// already chose — and for a banner, a badge or an aura there was no screen
/// in the app that showed it at all.
class _Wearing extends StatelessWidget {
  final List<Cosmetic> items;
  const _Wearing({required this.items});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final worn = [for (final c in items) if (c.equipped && !c.isDefault) c];
    if (worn.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SqPanel(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SqEyebrow(tr('Қазір киіп жүргенің')),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14, runSpacing: 12,
              children: [
                for (final c in worn)
                  SizedBox(
                    width: 64,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        cosmeticPreview(context, c, size: 36),
                        const SizedBox(height: 5),
                        Text(c.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10, height: 1.25,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text3(d))),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The way into a sixty-item catalogue: one chip per kind, each carrying how
/// much of that shelf is already yours.
class _KindFilter extends StatelessWidget {
  final List<CosmeticKind> kinds;
  final CosmeticKind? selected;
  final int Function(CosmeticKind) ownedOf, totalOf;
  final ValueChanged<CosmeticKind?> onPick;

  const _KindFilter({
    required this.kinds,
    required this.selected,
    required this.ownedOf,
    required this.totalOf,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    // 38, not 36: the chip is 9-pt padded around a 12-pt label, and the app
    // clamps text scaling at 1.2 rather than at 1.0.
    height: 38,
    child: ListView(
      scrollDirection: Axis.horizontal,
      // The page already has 18-pt gutters; the strip scrolls inside them
      // rather than bleeding to the screen edge.
      padding: EdgeInsets.zero,
      children: [
        SqChip(tr('Бәрі'),
          selected: selected == null,
          outlined: selected != null,
          radius: 999,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          onTap: () => onPick(null)),
        for (final k in kinds) ...[
          const SizedBox(width: 8),
          SqChip('${cosmeticKindShort(k)} ${ownedOf(k)}/${totalOf(k)}',
            selected: selected == k,
            outlined: selected != k,
            radius: 999,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            onTap: () => onPick(k)),
        ],
      ],
    ),
  );
}
