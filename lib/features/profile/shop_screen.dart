// lib/features/profile/shop_screen.dart
//
// The XP shop.
//
// XP had exactly one use in 3.0 — a level number that went up. That is a
// scoreboard, not a reward. The shop gives the number somewhere to go: avatar
// frames, titles, avatars, plus the consumables that keep a streak alive.
//
// The catalogue comes from the server, not from a list compiled into the app,
// so it can grow without a release — which is also why an item renders from
// its own data (a hex colour, an emoji) instead of a switch over known ids.
//
// Buying spends against `xp_spent`, never against `xp` itself: leagues and
// leaderboards rank on total XP, so letting a cosmetic eat it would quietly
// cost the learner a place in a competition they did not know they were
// spending from.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/cosmetics_repo.dart';
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
  'xp'            => trp('{n} XP жинау', {'n': '${c.requiredAmount}'}),
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
    if (raw.contains('not enough xp')) {
      return tr('XP жетпей тұр — тағы бір раунд ойна');
    }
    if (raw.contains('locked')) return tr('Бұл әлі ашылмаған');
    if (raw.contains('not owned')) return tr('Алдымен сатып ал');
    return humanError(e);
  }

  Future<void> _buy(Cosmetic c) async {
    final ok = await sqConfirm(context,
      title: c.name,
      message: trp('{p1} XP жұмсап аласың ба?', {'p1': '${c.price}'}),
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

  void _onTap(Cosmetic c, int spendable) {
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
    if (spendable < c.price) {
      sqSnack(context,
        trp('{p1} XP жетпей тұр — тағы бір раунд ойна',
            {'p1': '${c.price - spendable}'}),
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
    final spendable = ref.watch(spendableXpProvider);
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

        _Balance(spendable: spendable, onEarn: () => goTab(ref, SqTab.play)),
        const SizedBox(height: 16),

        if (meta.freezes > 0 || meta.lives > 0) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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

        async.when(
          loading: () => const Column(
            children: [SqShimmer(), SqShimmer(), SqShimmer()]),
          error: (e, _) => SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            title: tr('Дүкен жүктелмеді'),
            subtitle: humanError(e),
            tint: AppColors.red),
          data: (items) {
            if (items.isEmpty) {
              return SqEmpty(
                icon: PhosphorIconsFill.storefront,
                title: tr('Дүкен әзірге бос'),
                subtitle: tr('Жақында жаңа заттар қосылады'));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final group in [
                  (CosmeticKind.frame,  tr('Аватар жиектері')),
                  (CosmeticKind.title,  tr('Атақтар')),
                  (CosmeticKind.avatar, tr('Аватарлар')),
                ]) ...[
                  ..._section(items, group.$1, group.$2, spendable),
                ],
              ],
            );
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
        Text(tr('Сатып алу лига XP-ін азайтпайды.'),
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
    int spendable,
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
            affordable: spendable >= c.price,
            busy: _busyId == c.id,
            onTap: () => _onTap(c, spendable),
          ),
      ]),
      const SizedBox(height: 18),
    ];
  }
}

class _Balance extends StatelessWidget {
  final int spendable;
  final VoidCallback onEarn;
  const _Balance({required this.spendable, required this.onEarn});

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
          child: const Icon(PhosphorIconsFill.star,
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
              SqCountUp(spendable,
                size: 24, color: Colors.white, suffix: ' XP'),
            ],
          ),
        ),
        SqLip(
          fill: Colors.white.withValues(alpha: 0.10),
          border: Colors.white.withValues(alpha: 0.16),
          radius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          onTap: onEarn,
          child: Text(tr('XP табу'),
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

  /// Every item previews the thing it actually is: a frame shows its ring in
  /// its real colour, an avatar shows its character, a title shows its text.
  Widget _preview(BuildContext context) {
    final d = isDark(context);
    switch (item.kind) {
      case CosmeticKind.frame:
        final color = sqHexColor(item.color) ?? AppColors.text4(d);
        return Container(
          width: 40, height: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: color, shape: BoxShape.circle),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card(d), shape: BoxShape.circle),
          ),
        );
      case CosmeticKind.avatar:
        return Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.muted(d),
            borderRadius: BorderRadius.circular(13)),
          alignment: Alignment.center,
          child: Text(item.emoji ?? '🙂',
            style: const TextStyle(fontSize: 21)),
        );
      case CosmeticKind.title:
        return SqTintBox(PhosphorIconsFill.sealCheck,
          tint: _rarity(item.rarity).tint, size: 40);
    }
  }

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
        opacity: item.isReward && !item.unlocked ? 0.4 : 1,
        child: _preview(context),
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
        SqNum('${item.price} XP',
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
