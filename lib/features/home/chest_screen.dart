// lib/features/home/chest_screen.dart
//
// The daily chest.
//
// One chest a day, three face-down cards, one pick. The choice is the point:
// a reward you selected reads as luck, a reward handed to you reads as a
// number going up. The prize grows with the chest streak and every seventh
// day is a guaranteed big one, so the run itself becomes the reason to come
// back.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/supa.dart';
import '../../providers.dart';

class ChestScreen extends ConsumerStatefulWidget {
  const ChestScreen({super.key});

  @override
  ConsumerState<ChestScreen> createState() => _ChestScreenState();
}

class _ChestScreenState extends ConsumerState<ChestScreen> {
  int? _picked;
  bool _busy = false;
  bool _opened = false;
  int _reward = 0;

  // Labels stay Kazakh here — they are the translation key, and the card is
  // drawn with tr() further down.
  static const _cards = [
    (label: 'XP сыйлығы', icon: PhosphorIconsFill.star, tint: AppColors.amber),
    (label: 'Мұздатқыш', icon: PhosphorIconsFill.snowflake, tint: AppColors.sky),
    (label: 'Құпия', icon: PhosphorIconsFill.question, tint: AppColors.primary),
  ];

  Future<void> _open() async {
    final index = _picked;
    if (index == null || _busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final xp = await ref.read(metaProvider.notifier)
          .openChest(cardIndex: index);
      if (xp > 0) {
        // The chest pays in real XP so it feeds the league like anything else.
        await ref.read(profileRepoProvider)
            .addXp(xp, 'daily_chest')
            .catchError((_) => 0);
        ref.invalidate(myProfileProvider);
      }
      if (!mounted) return;
      setState(() { _opened = true; _reward = xp; });
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final meta = ref.watch(metaProvider);
    final ready = meta.chestReady;
    final day = ready ? meta.nextChestStreak : meta.chestStreak;
    final toGolden = (7 - (day % 7)) % 7;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: SqFill(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
              Row(
                children: [
                  SqSquareButton(PhosphorIconsBold.x,
                    size: 36, onInk: true,
                    onTap: () => Navigator.of(context).pop()),
                  Expanded(
                    child: Center(
                      child: SqEyebrow(
                        trp('{n}-күнгі сыйлық', {'n': '$day'}),
                        color: AppColors.onInk2, size: 10.5)),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
              const Spacer(flex: 2),

              _ChestArt(open: _opened || !ready),
              const SizedBox(height: 22),

              if (_opened) ...[
                SqRise(
                  child: Column(
                    children: [
                      Text(tr('Сандық ашылды!'),
                        style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800,
                          letterSpacing: -0.5, color: Colors.white)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.amber.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_cards[_picked ?? 0].icon,
                              size: 22, color: AppColors.amber),
                            const SizedBox(width: 10),
                            SqCountUp(_reward,
                              size: 24, color: Colors.white, suffix: ' XP'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _picked == 1
                            ? tr('Серия мұздатқышы да қосылды')
                            : _picked == 2
                                ? tr('Қосымша жан да қосылды')
                                : tr('Серияңды жалғастыр — ертең тағы келеді'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600,
                          color: AppColors.onInk2)),
                    ],
                  ),
                ),
              ] else if (!ready) ...[
                Text(tr('Бүгінгі сандық ашылған'),
                  style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800,
                    letterSpacing: -0.5, color: Colors.white)),
                const SizedBox(height: 8),
                Text(tr('Ертең жаңа сандық күтіп тұрады'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600,
                    color: AppColors.onInk2)),
              ] else ...[
                Text(tr('Бір картаны таңда'),
                  style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800,
                    letterSpacing: -0.5, color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  tr('Серияң ұзарған сайын сыйлық та жақсарады'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600,
                    color: AppColors.onInk2)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    for (var i = 0; i < _cards.length; i++) ...[
                      Expanded(
                        child: _PickCard(
                          label: tr(_cards[i].label),
                          icon: _cards[i].icon,
                          tint: _cards[i].tint,
                          selected: _picked == i,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _picked = i);
                          },
                        ),
                      ),
                      if (i != _cards.length - 1) const SizedBox(width: 11),
                    ],
                  ],
                ),
              ],

              const Spacer(flex: 3),

              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsFill.fire,
                      size: 20, color: AppColors.amber),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        toGolden == 0
                            ? tr('Бүгін алтын сандық — ең үлкен сыйлық осында.')
                            : trp(
                                '{n} күннен кейін алтын сандық ашылады: '
                                '+200 XP бонус.',
                                {'n': '$toGolden'}),
                        style: const TextStyle(
                          fontSize: 12, height: 1.45, fontWeight: FontWeight.w600,
                          color: AppColors.onInkSoft)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (_opened || !ready)
                SqAction(tr('Басты бетке'),
                  tone: SqTone.amber,
                  height: 56,
                  icon: PhosphorIconsBold.house,
                  onTap: () => Navigator.of(context).pop())
              else
                SqAction(tr('Ашу'),
                  tone: SqTone.amber,
                  height: 56,
                  busy: _busy,
                  icon: PhosphorIconsFill.handTap,
                  onTap: _picked == null ? null : _open),
          ],
        ),
      ),
    );
  }
}

class _ChestArt extends StatelessWidget {
  final bool open;
  const _ChestArt({required this.open});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150, height: 150,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SqPulse(
          child: Container(
            width: 150, height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.amber.withValues(alpha: 0.18)),
          ),
        ),
        SqFloat(
          distance: 7,
          child: Container(
            width: 110, height: 110,
            decoration: BoxDecoration(
              color: open ? AppColors.green : AppColors.amber,
              borderRadius: BorderRadius.circular(36),
              boxShadow: [
                BoxShadow(
                  color: open ? AppColors.greenDeep : AppColors.amberDeep,
                  offset: const Offset(0, 6), blurRadius: 0),
                BoxShadow(
                  color: (open ? AppColors.green : AppColors.amber)
                      .withValues(alpha: 0.55),
                  blurRadius: 40, offset: const Offset(0, 20)),
              ],
            ),
            child: Icon(
              open ? PhosphorIconsFill.checkCircle : PhosphorIconsFill.gift,
              size: 56, color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

class _PickCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  const _PickCard({
    required this.label, required this.icon, required this.tint,
    required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: selected ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? tint
              : Colors.white.withValues(alpha: 0.12),
          width: selected ? 2 : 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, size: 24, color: tint),
          ),
          const SizedBox(height: 11),
          Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white)),
        ],
      ),
    ),
  );
}
