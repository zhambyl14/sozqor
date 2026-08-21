// lib/features/play/play_hub_screen.dart
//
// Every solo way to train, ordered by how likely it is to be the right one.
//
// 3.0 showed five equally loud gradient cards and made the learner choose.
// 4.0 makes the choice for them: the recommended round is a dark block with a
// button, and the rest are one-line entries in a plain list. Filters for what
// to drill sit *above* the modes, because "what am I practising" is a decision
// you make before "how".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/word.dart';
import '../../providers.dart';
import 'ai_chat_screen.dart';
import 'packs_screen.dart';
import 'play_session_screen.dart';
import 'pronounce_screen.dart';

class PlayHubScreen extends ConsumerStatefulWidget {
  const PlayHubScreen({super.key});

  @override
  ConsumerState<PlayHubScreen> createState() => _PlayHubScreenState();
}

class _PlayHubScreenState extends ConsumerState<PlayHubScreen> {
  final Set<QKind> _kinds = {};
  bool _showKinds = false;

  Future<void> _start(PlayMode mode) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaySessionScreen(
        mode: mode,
        kinds: _kinds.isEmpty ? null : _kinds.toList(),
      ),
    ));
    if (mounted) refreshAll(ref);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) refreshAll(ref);
  }

  static IconData _kindIcon(QKind k) => switch (k) {
    QKind.kkEn       => PhosphorIconsFill.translate,
    QKind.enKk       => PhosphorIconsFill.arrowsLeftRight,
    QKind.definition => PhosphorIconsFill.bookOpenText,
    QKind.synonym    => PhosphorIconsFill.link,
    QKind.antonym    => PhosphorIconsFill.arrowsLeftRight,
    QKind.listening  => PhosphorIconsFill.headphones,
    QKind.spelling   => PhosphorIconsFill.keyboard,
    QKind.sentence   => PhosphorIconsFill.textAlignLeft,
  };

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final profile = ref.watch(myProfileProvider).value;
    final cefr = profile?.cefrLevel ?? 'A1';
    final available = kindsFor(cefr);
    final locked = QKind.values.where((k) => !available.contains(k)).toList();
    final words = ref.watch(myWordsProvider).value ?? const <Word>[];
    final due = ref.watch(dueCountProvider).value ?? 0;
    final playedDaily = ref.watch(playedDailyProvider).value ?? false;

    return SqPage(
      onRefresh: () async {
        refreshAll(ref);
        ref.invalidate(playedDailyProvider);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SqEyebrow(tr('Жаттығу')),
                  const SizedBox(height: 1),
                  Text(tr('Ойнау'),
                    style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800,
                      letterSpacing: -0.6)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.card(d),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.border(d)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhosphorIconsFill.chartBar,
                    size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  SqNum(cefr, size: 12.5, color: AppColors.text(d)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // The question-kind filter is a wall of chips that almost nobody
        // changes, so it starts folded into one line and only unfolds when
        // asked. Nothing is removed — it is just not shouting on first paint.
        SqPanel(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
          onTap: () => setState(() => _showKinds = !_showKinds),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(PhosphorIconsBold.slidersHorizontal,
                    size: 16, color: AppColors.text2(d)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _kinds.isEmpty
                          ? tr('Сұрақ түрі: барлығы')
                          : trp('Сұрақ түрі: {n} таңдалды',
                              {'n': '${_kinds.length}'}),
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800,
                        color: AppColors.text(d))),
                  ),
                  Icon(_showKinds
                      ? PhosphorIconsBold.caretUp
                      : PhosphorIconsBold.caretDown,
                    size: 14, color: AppColors.text4(d)),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: !_showKinds
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 13),
                          Wrap(
                            spacing: 7, runSpacing: 7,
                            children: [
                              for (final k in available)
                                SqChip(tr(k.short),
                                  icon: _kindIcon(k),
                                  selected: _kinds.contains(k),
                                  outlined: true,
                                  onTap: () => setState(() {
                                    if (!_kinds.remove(k)) _kinds.add(k);
                                  })),
                              for (final k in locked)
                                Opacity(
                                  opacity: 0.5,
                                  child: SqChip(
                                    '${tr(k.short)} · '
                                    '${kCefrCodes[k.minLevel.clamp(0, kCefrCodes.length - 1)]}',
                                    icon: PhosphorIconsFill.lockSimple,
                                    outlined: true),
                                ),
                            ],
                          ),
                          if (_kinds.isNotEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () => setState(_kinds.clear),
                                child: Text(tr('Тазалау'))),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        SqInkCard(
          padding: const EdgeInsets.all(19),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(15)),
                    child: const Icon(PhosphorIconsFill.target,
                      size: 22, color: Colors.white),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(tr('Классикалық тест'),
                                style: const TextStyle(
                                  fontSize: 16.5, fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3, color: Colors.white)),
                            ),
                            const SizedBox(width: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.amber,
                                borderRadius: BorderRadius.circular(5)),
                              child: SqNum(tr('ҰСЫНЫЛАДЫ'),
                                size: 9, color: AppColors.ink),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          trp('10 сұрақ · {src} · 4 минут', {
                            'src': words.isEmpty
                                ? tr('базадан')
                                : tr('өз сөздерің')
                          }),
                          style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: AppColors.onInk2)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              SqAction(tr('Бастау'),
                icon: PhosphorIconsFill.play,
                height: 52,
                onTap: () => _start(PlayMode.classic)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        SqGroup(children: [
          _ModeTile(
            mode: PlayMode.review,
            icon: PhosphorIconsFill.arrowsClockwise,
            tint: AppColors.green,
            subtitle: due > 0
                ? trp('Ұмытуға жақын {n} сөз', {'n': '$due'})
                : tr('Қазір қайталайтын сөз жоқ'),
            badge: due > 0 ? trp('{n} дайын', {'n': '$due'}) : tr('бос'),
            dimmed: due == 0,
            onTap: () {
              if (due == 0) {
                sqSnack(context, tr('Қайталайтын сөз жоқ — кейінірек кел'));
                return;
              }
              _start(PlayMode.review);
            }),
          _ModeTile(
            mode: PlayMode.marathon,
            icon: PhosphorIconsFill.heartbeat,
            tint: AppColors.red,
            subtitle: tr('3 жан · шексіз сұрақ'),
            badge: tr('рекорд қой'),
            onTap: () => _start(PlayMode.marathon)),
          _ModeTile(
            mode: PlayMode.timeAttack,
            icon: PhosphorIconsFill.timer,
            tint: AppColors.amber,
            subtitle: tr('60 секунд · жылдамдық'),
            badge: tr('жылдам'),
            onTap: () => _start(PlayMode.timeAttack)),
          _ModeTile(
            mode: PlayMode.classic,
            icon: PhosphorIconsFill.keyboard,
            tint: AppColors.sky,
            title: tr('Емле жаттығуы'),
            subtitle: tr('Әріптен сөз жинау'),
            badge: tr('жаңа'),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlaySessionScreen(
                  mode: PlayMode.classic,
                  kinds: const [QKind.spelling],
                  title: tr('Емле жаттығуы'))));
              if (mounted) refreshAll(ref);
            }),
          _ModeTile(
            mode: PlayMode.daily,
            icon: PhosphorIconsFill.globeHemisphereEast,
            tint: AppColors.primary,
            subtitle: tr('Әлем бір жиынтық ойнайды'),
            badge: playedDaily ? tr('ойналды') : tr('ойналмады'),
            dimmed: playedDaily,
            onTap: () {
              if (playedDaily) {
                sqSnack(context,
                  tr('Бүгінгі сынақты ойнап қойдың. Ертең жаңасы келеді!'));
                return;
              }
              _start(PlayMode.daily);
            }),
        ]),
        const SizedBox(height: 20),

        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: SqEyebrow(tr('Жаңа тәсілдер'))),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _NewWayCard(
                icon: PhosphorIconsFill.chatsCircle,
                tint: AppColors.primary,
                title: tr('AI әңгіме'),
                subtitle: tr('Сөйлесіп жаттық'),
                onTap: () => _open(const AiChatScreen())),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: _NewWayCard(
                icon: PhosphorIconsFill.microphone,
                tint: AppColors.sky,
                title: tr('Айтылым'),
                subtitle: tr('Буынға бөліп жаттық'),
                onTap: () => _open(const PronounceScreen())),
            ),
          ],
        ),
        const SizedBox(height: 14),

        SqPanel(
          radius: 20,
          padding: const EdgeInsets.all(15),
          fill: AppColors.soft(AppColors.amber, d),
          border: AppColors.line(AppColors.amber, d),
          onTap: () => _open(const PacksScreen()),
          child: Row(
            children: [
              const SqTintBox(PhosphorIconsFill.stack,
                tint: AppColors.amber, size: 40, solid: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Сөз топтамалары'),
                      style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: AppColors.text(d))),
                    Text(tr('Фильм · ән · IELTS · мамандық'),
                      style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: AppColors.onSoft(AppColors.amber, d))),
                  ],
                ),
              ),
              Icon(PhosphorIconsBold.caretRight,
                size: 16, color: AppColors.onSoft(AppColors.amber, d)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  final PlayMode mode;
  final IconData icon;
  final Color tint;
  final String subtitle, badge;
  final String? title;
  final bool dimmed;
  final VoidCallback onTap;

  const _ModeTile({
    required this.mode,
    required this.icon,
    required this.tint,
    required this.subtitle,
    required this.badge,
    required this.onTap,
    this.title,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: dimmed ? 0.6 : 1,
    child: SqTile(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      leading: SqTintBox(icon, tint: tint, size: 40),
      title: title ?? tr(mode.title),
      subtitle: subtitle,
      trailing: SqBadge(badge, tint: tint),
      chevron: true,
      onTap: onTap,
    ),
  );
}

class _NewWayCard extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title, subtitle;
  final VoidCallback onTap;

  const _NewWayCard({
    required this.icon, required this.tint,
    required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SqLip(
      fill: AppColors.card(d),
      border: AppColors.border(d),
      lip: d ? AppColors.borderD : const Color(0xFFF0EEF7),
      depth: 3,
      radius: 20,
      padding: const EdgeInsets.all(15),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SqTintBox(icon, tint: tint, size: 38),
          const SizedBox(height: 10),
          Text(title,
            style: TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w800,
              color: AppColors.text(d))),
          Text(subtitle,
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: AppColors.text3(d))),
        ],
      ),
    );
  }
}
