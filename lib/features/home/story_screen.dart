// lib/features/home/story_screen.dart
//
// The word path — a zig-zag ladder of levels through one themed zone.
//
// A flat "play again" button gives no sense of travel. A path does: you can
// see what you cleared, exactly where you are, the boss at the end of the
// stretch and the chest waiting behind it. Only the node you are standing on
// is playable, so there is never a decision to make — just a next step.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../providers.dart';
import '../play/play_session_screen.dart';

/// The zones a learner walks through, in order. Each is eight levels long.
List<({String title, String topic, IconData icon, Color tint})> get _zones => [
  (title: tr('Тамақ аймағы'), topic: 'food',
   icon: PhosphorIconsFill.bowlFood, tint: AppColors.green),
  (title: tr('Саяхат аймағы'), topic: 'travel',
   icon: PhosphorIconsFill.airplaneTilt, tint: AppColors.sky),
  (title: tr('Жұмыс аймағы'), topic: 'work',
   icon: PhosphorIconsFill.briefcase, tint: AppColors.primary),
  (title: tr('Технология аймағы'), topic: 'tech',
   icon: PhosphorIconsFill.cpu, tint: AppColors.amber),
  (title: tr('Сезім аймағы'), topic: 'emotions',
   icon: PhosphorIconsFill.heart, tint: AppColors.red),
];

enum _NodeKind { done, now, locked, boss, chest }

class StoryScreen extends ConsumerWidget {
  const StoryScreen({super.key});

  static const _perZone = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final node = ref.watch(metaProvider).storyNode;
    final zoneIndex = (node ~/ _perZone) % _zones.length;
    final zone = _zones[zoneIndex];
    final inZone = node % _perZone;
    final totalLevels = _zones.length * _perZone;

    Future<void> play(int index) async {
      final outcome = await Navigator.of(context).push<PlayOutcome>(
        MaterialPageRoute(builder: (_) => PlaySessionScreen(
          mode: PlayMode.classic, topic: zone.topic)));
      if (outcome != null && outcome.passed) {
        await ref.read(metaProvider.notifier).clearStoryTo(node + 1);
        if (context.mounted) {
          sqSnack(context, trp('{n}-деңгей алынды!',
            {'n': '${index + 1}'}));
        }
      }
      if (context.mounted) refreshAll(ref);
    }

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: tr('Сөз жолы'),
          eyebrow: trp('{n}-аймақ', {'n': '${zoneIndex + 1}'}),
          onBack: () => Navigator.of(context).pop(),
          actions: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.soft(AppColors.amber, d),
                borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhosphorIconsFill.star,
                    size: 14, color: AppColors.amber),
                  const SizedBox(width: 5),
                  SqNum('$node/$totalLevels',
                    size: 11.5, color: AppColors.amberInk),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        SqPanel(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
          child: Row(
            children: [
              SqTintBox(zone.icon, tint: zone.tint, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr(zone.title),
                      style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800,
                        color: AppColors.text(d))),
                    const SizedBox(height: 6),
                    SqTrack(inZone / _perZone, color: zone.tint),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SqNum('$inZone/$_perZone', size: 11.5, color: zone.tint),
            ],
          ),
        ),
        const SizedBox(height: 18),

        for (var i = 0; i < _perZone; i++) ...[
          _PathNode(
            index: i,
            kind: _kindFor(i, inZone),
            left: i.isEven,
            onPlay: () => play(inZone),
          ),
          if (i != _perZone - 1)
            _Connector(done: i < inZone, left: i.isEven),
        ],

        const SizedBox(height: 20),
        SqPanel(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              const SqTintBox(PhosphorIconsFill.info,
                tint: AppColors.sky, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr('10 сұрақ · 60% дұрыс болса, келесі деңгей ашылады.'),
                  style: TextStyle(
                    fontSize: 12, height: 1.5, fontWeight: FontWeight.w600,
                    color: AppColors.text3(d))),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static _NodeKind _kindFor(int i, int current) {
    if (i == current) return _NodeKind.now;
    if (i < current) return _NodeKind.done;
    if (i == 7) return _NodeKind.chest;
    if (i == 3) return _NodeKind.boss;
    return _NodeKind.locked;
  }
}

class _PathNode extends StatelessWidget {
  final int index;
  final _NodeKind kind;
  final bool left;
  final VoidCallback onPlay;

  const _PathNode({
    required this.index, required this.kind,
    required this.left, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);

    late final Color bg, ink, lip;
    late final IconData icon;
    late final String label;

    switch (kind) {
      case _NodeKind.done:
        bg = AppColors.green; ink = Colors.white; lip = AppColors.greenDeep;
        icon = PhosphorIconsFill.check;
        label = trp('Деңгей {n}', {'n': '${index + 1}'});
      case _NodeKind.now:
        bg = AppColors.primary; ink = Colors.white; lip = AppColors.primaryDeep;
        icon = PhosphorIconsFill.play; label = tr('Осы жерде');
      case _NodeKind.boss:
        bg = AppColors.inkBlock(d); ink = AppColors.amber;
        lip = AppColors.inkBlockLip(d);
        icon = PhosphorIconsFill.crownSimple; label = tr('Босс');
      case _NodeKind.chest:
        bg = AppColors.amber; ink = Colors.white; lip = AppColors.amberDeep;
        icon = PhosphorIconsFill.gift; label = tr('Сыйлық');
      case _NodeKind.locked:
        bg = AppColors.card(d); ink = AppColors.text4(d);
        lip = AppColors.surfaceLip(d);
        icon = PhosphorIconsFill.lockSimple;
        label = trp('Деңгей {n}', {'n': '${index + 1}'});
    }

    final size = kind == _NodeKind.now ? 70.0 : 58.0;
    final live = kind == _NodeKind.now;

    final bubble = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SqLip(
          fill: bg,
          lip: lip,
          depth: live ? 5 : 4,
          radius: size / 2,
          border: kind == _NodeKind.locked ? AppColors.border(d) : null,
          onTap: live ? onPlay : null,
          child: SizedBox(
            width: size, height: size,
            child: Icon(icon, size: 24, color: ink),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
          style: TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w800,
            color: AppColors.text3(d))),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisAlignment:
            left ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (!left && live) ...[
            _StartPill(onTap: onPlay),
            const SizedBox(width: 12),
          ],
          bubble,
          if (left && live) ...[
            const SizedBox(width: 12),
            _StartPill(onTap: onPlay),
          ],
        ],
      ),
    );
  }
}

class _StartPill extends StatelessWidget {
  final VoidCallback onTap;
  const _StartPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SqLip(
      fill: AppColors.inkBlock(d),
      lip: AppColors.inkBlockLip(d),
      depth: 3,
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('Бастау'),
            style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(width: 8),
          const Icon(PhosphorIconsBold.arrowRight,
            size: 14, color: Colors.white),
        ],
      ),
    );
  }
}

/// The looping rail that joins two nodes.
class _Connector extends StatelessWidget {
  final bool done, left;
  const _Connector({required this.done, required this.left});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SizedBox(
      height: 34,
      child: CustomPaint(
        painter: _ConnectorPainter(
          color: done
              ? AppColors.green
              : AppColors.border(d),
          left: left,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ConnectorPainter extends CustomPainter {
  final Color color;
  final bool left;
  const _ConnectorPainter({required this.color, required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Both ends sit under a node; the rail dips between them so the path
    // reads as one continuous road rather than two separate stubs.
    final startX = left ? 43.0 : size.width - 43.0;
    final endX = left ? size.width - 43.0 : 43.0;
    final path = Path()
      ..moveTo(startX, -6)
      ..cubicTo(
        startX, size.height * 0.9,
        endX, size.height * 0.9,
        endX, size.height + 6);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter old) =>
      old.color != color || old.left != left;
}
