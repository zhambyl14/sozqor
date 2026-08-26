// lib/features/arena/invite_wait_sheet.dart
//
// One screen for the fifteen seconds between "I tapped a friend's name" and
// "we are both playing".
//
// It lives on its own because two screens can ring a friend — the arena and
// the friends list — and when the friends list had its own copy of this flow
// it did not have one at all: it called createFriendBattle, which makes an
// ACTIVE battle, and started playing. The friend was told about a match that
// was already under way, and by the time they looked at it the sender had
// finished and was "waiting" for somebody who had never agreed to play.
//
// So the invite handshake is not a screen behaviour, it is the only way to
// start a friend battle, and this is where the waiting is drawn.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/battle.dart';
import '../../data/models/question.dart';
import '../../data/supa.dart';
import '../../providers.dart';

/// What the SENDER looks at while a friend decides.
///
/// It polls the row rather than assuming: the battle becomes `active` only
/// when the other side accepts, so this sheet is the only thing standing
/// between "I tapped a name" and "we are both playing". It closes with the
/// battle on yes, and with nothing at all on no.
class InviteWaitSheet extends ConsumerStatefulWidget {
  final Battle battle;
  const InviteWaitSheet({super.key, required this.battle});

  @override
  ConsumerState<InviteWaitSheet> createState() => InviteWaitSheetState();
}

class InviteWaitSheetState extends ConsumerState<InviteWaitSheet> {
  Timer? _poll;
  int _left = 15;
  String? _outcome;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(milliseconds: 900), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() => _left = widget.battle.inviteSecondsLeft);
    try {
      final live = await ref.read(battleRepoProvider).byId(widget.battle.id);
      if (!mounted || live == null) return;
      if (live.status == 'active') {
        _poll?.cancel();
        Navigator.of(context).pop(live);
        return;
      }
      if (live.isDeclined) {
        _poll?.cancel();
        setState(() => _outcome = tr('Досың бас тартты'));
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {/* a dropped poll is not worth an error message */}

    if (_left <= 0 && _outcome == null && mounted) {
      _poll?.cancel();
      setState(() => _outcome = tr('Досың жауап бермеді'));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        const SqSheetGrip(),
        Text(tr('Шақыру жіберілді'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 19, fontWeight: FontWeight.w800,
            letterSpacing: -0.4, color: AppColors.text(d))),
        const SizedBox(height: 6),
        if (_outcome == null) ...[
          const Center(child: SizedBox(
            width: 34, height: 34,
            child: CircularProgressIndicator(strokeWidth: 3))),
          const SizedBox(height: 16),
          Text(tr('Досың жауабын күтіп тұрмыз. Ол қабылдаса, баттл екеуіңде '
                  'бір уақытта басталады.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13, height: 1.45, fontWeight: FontWeight.w600,
              color: AppColors.text3(d))),
          const SizedBox(height: 14),
          Center(
            child: Text(trp('{n} секунд', {'n': '${_left.clamp(0, 15)}'}),
              style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: AppColors.text(d))),
          ),
        ] else
          Text(_outcome!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15, height: 1.4, fontWeight: FontWeight.w800,
              color: AppColors.text(d))),
        const SizedBox(height: 18),
        SqLip(
          fill: AppColors.card(d),
          lip: AppColors.line(AppColors.ink, d),
          depth: 3,
          radius: 14,
          padding: const EdgeInsets.symmetric(vertical: 13),
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: Text(tr('Жабу'),
              style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w800,
                color: AppColors.text(d))),
          ),
        ),
        const SizedBox(height: 6),
        ],
      ),
    );
  }
}


/// Rings [targetUserId] and waits for an answer.
///
/// Returns the live battle when they accept, and null every other way —
/// refused, ignored, busy, blocked, or not enough words to build a round.
/// Every screen that offers to challenge a friend goes through this, so none
/// of them can accidentally start a match on one person's say-so.
Future<Battle?> ringFriend(
  BuildContext context,
  WidgetRef ref, {
  required String targetUserId,
  required List<Question> questions,
  required String cefr,
}) async {
  final repo = ref.read(battleRepoProvider);
  try {
    // Asked first so "they are in a match" is said in half a second rather
    // than after fifteen of silence.
    if (await repo.isBusy(targetUserId)) {
      if (context.mounted) {
        sqSnack(context, tr('Досың қазір бос емес — басқа ойында'), error: true);
      }
      return null;
    }
    final invited = await repo.inviteFriend(
      targetUserId: targetUserId, questions: questions, cefr: cefr);
    if (!context.mounted) return null;
    return showModalBottomSheet<Battle>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (_) => InviteWaitSheet(battle: invited),
    );
  } catch (e) {
    if (context.mounted) sqSnack(context, humanError(e), error: true);
    return null;
  }
}
