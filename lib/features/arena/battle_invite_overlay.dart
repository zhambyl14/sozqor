// lib/features/arena/battle_invite_overlay.dart
//
// A friend's battle invitation, wherever you happen to be standing
// (EN-12 / EN-14 / KK-2).
//
// Before this, an invitation existed only as a row the Arena tab would notice
// the next time it was opened and refreshed. Somebody on the Words tab was
// never told at all, so the sender sat waiting for a person who had no way of
// knowing they had been asked.
//
// Three rules the PRD is explicit about, and this file exists to keep:
//
//   • Nothing starts on its own. The card offers Accept and Decline; the
//     battle opens on Accept and on nothing else.
//   • It does not interrupt. While `busyProvider` is set — mid-battle,
//     mid-ranked-match, mid-timed-round — the card is withheld, because a
//     popup over the question you are answering costs you the round. It is
//     shown the moment that clears, provided the invitation is still fresh.
//   • It can be told to stop. Repeated invitations get a "mute for two
//     minutes" action, kept on the device: this is "stop poking me", not a
//     block, and it should not outlive the annoyance.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/battle.dart';
import '../../data/models/profile.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import 'battle_screen.dart';

/// An invitation older than this is not worth interrupting anybody for — the
/// sender has almost certainly given up and gone elsewhere.
const _freshFor = Duration(minutes: 2);

class BattleInviteOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const BattleInviteOverlay({super.key, required this.child});

  @override
  ConsumerState<BattleInviteOverlay> createState() =>
      _BattleInviteOverlayState();
}

class _BattleInviteOverlayState extends ConsumerState<BattleInviteOverlay> {
  /// Invitations answered or dismissed on this device. Without it a declined
  /// row would reappear for the instant between the tap and the write.
  final Set<String> _handled = {};

  /// Cached sender names, so the card can say who is asking without a lookup
  /// every time the stream ticks.
  final Map<String, String> _names = {};

  String? _opening;

  /// Redraws the countdown, and answers on the learner's behalf when it runs
  /// out. Fifteen seconds is the whole budget: the sender is looking at a
  /// spinner the entire time, so an invitation nobody answers has to become a
  /// refusal rather than silence.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Battle? _pick(List<Battle> invites) {
    final uid = currentUid ?? '';
    final now = DateTime.now();
    for (final b in invites) {
      if (_handled.contains(b.id)) continue;
      if (now.difference(b.createdAt) > _freshFor) continue;
      final from = b.oppId(uid);
      if (from == null) continue;
      if (ref.read(mutedInvitersProvider.notifier).isMuted(from)) continue;
      // Out of time. Sending the refusal rather than just hiding the card is
      // what starts the two-minute silence AND what tells the sender to stop
      // waiting — hiding it locally would leave them staring at a spinner
      // until their own clock ran out.
      if (b.inviteSecondsLeft <= 0) {
        _handled.add(b.id);
        WidgetsBinding.instance.addPostFrameCallback((_) => _decline(b));
        continue;
      }
      return b;
    }
    return null;
  }

  Future<void> _loadName(String userId) async {
    if (_names.containsKey(userId)) return;
    try {
      final Profile? p = await ref.read(profileRepoProvider).byId(userId);
      if (mounted && p != null) setState(() => _names[userId] = p.name);
    } catch (_) {/* the card falls back to a generic word */}
  }

  Future<void> _accept(Battle b) async {
    setState(() {
      _handled.add(b.id);
      _opening = b.id;
    });
    try {
      // Opening the screen is NOT accepting. The row has to become `active`,
      // and it becomes active here — which is also the moment the sender's
      // waiting sheet stops spinning and drops them into the same match.
      // Pushing the battle screen without this was the old bug wearing a new
      // hat: one player playing a match the other had never agreed to.
      final live = await ref.read(battleRepoProvider).respondToInvite(b.id, true);
      if (!mounted) return;
      if (live.status != 'active') {
        setState(() => _opening = null);
        sqSnack(context, tr('Шақыру ескірді'), error: true);
        return;
      }
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => BattleScreen(battle: live)));
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    }
    if (!mounted) return;
    setState(() => _opening = null);
    refreshAll(ref);
    ref.invalidate(pendingInvitesProvider);
  }

  Future<void> _decline(Battle b) async {
    setState(() => _handled.add(b.id));
    try {
      await ref.read(battleRepoProvider).declineInvite(b.id);
    } catch (_) {
      // The row stays active and the sender keeps waiting, which is no worse
      // than before; the card is gone from this device either way.
    }
    if (mounted) ref.invalidate(pendingInvitesProvider);
  }

  void _mute(Battle b) {
    final from = b.oppId(currentUid ?? '');
    if (from != null) ref.read(mutedInvitersProvider.notifier).mute(from);
    _decline(b);
  }

  @override
  Widget build(BuildContext context) {
    final invites =
        ref.watch(incomingInvitesProvider).valueOrNull ?? const <Battle>[];
    final busy = ref.watch(busyProvider);
    final invite = busy ? null : _pick(invites);

    if (invite != null) {
      final from = invite.oppId(currentUid ?? '');
      if (from != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _loadName(from));
      }
    }

    return Stack(
      children: [
        widget.child,
        if (invite != null)
          Positioned(
            left: 12, right: 12,
            top: MediaQuery.of(context).padding.top + 10,
            child: _InviteCard(
              name: _names[invite.oppId(currentUid ?? '') ?? ''] ??
                  tr('Досың'),
              secondsLeft: invite.inviteSecondsLeft,
              busy: _opening == invite.id,
              onAccept: () => _accept(invite),
              onDecline: () => _decline(invite),
              onMute: () => _mute(invite),
            ),
          ),
      ],
    );
  }
}

class _InviteCard extends StatelessWidget {
  final String name;

  /// Drawn as a number and as a bar. At a glance it says "hurry" without
  /// anybody having to read it, which matters on a card that appears over
  /// whatever the learner was already doing.
  final int secondsLeft;

  final bool busy;
  final VoidCallback onAccept, onDecline, onMute;

  const _InviteCard({
    required this.name,
    required this.secondsLeft,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    return SqRise(
      child: Material(
        color: Colors.transparent,
        child: SqInkCard(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          glow: AppColors.red,
          glowAt: Alignment.topRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(14)),
                    child: const Icon(PhosphorIconsFill.sword,
                      size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SqEyebrow(tr('Баттлға шақыру'),
                          color: AppColors.onInk2),
                        const SizedBox(height: 2),
                        Text(
                          trp('{name} сені баттлға шақырды',
                            {'name': name}),
                          style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800,
                            color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              // The clock the sender is also watching. Fifteen seconds, drawn
              // so it can be read without reading.
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (secondsLeft / 15).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        valueColor:
                            const AlwaysStoppedAnimation(Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(trp('{n} с', {'n': '$secondsLeft'}),
                    style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800,
                      color: Colors.white)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SqAction(tr('Қабылдау'),
                      icon: PhosphorIconsFill.play,
                      height: 46,
                      busy: busy,
                      onTap: busy ? null : onAccept),
                  ),
                  const SizedBox(width: 9),
                  SqLip(
                    fill: Colors.white.withValues(alpha: 0.10),
                    border: Colors.white.withValues(alpha: 0.16),
                    radius: 14,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                    onTap: busy ? null : onDecline,
                    child: Text(tr('Бас тарту'),
                      style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800,
                        color: Colors.white)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // EN-14: the way out of somebody sending this over and over.
              Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: busy ? null : onMute,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(tr('2 минутқа бұғаттау'),
                      style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700,
                        color: AppColors.onInk3)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
