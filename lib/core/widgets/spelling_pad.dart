// lib/core/widgets/spelling_pad.dart
//
// The letter keypad for QKind.spelling. Solo rounds and battles share it, so
// a spelling question is always playable wherever it turns up.
//
// The empty slots are the point: they show how many letters are still missing
// before you have typed anything, which turns "assemble this word" from a
// guess into a puzzle with a visible shape.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/question.dart';
import '../theme/app_colors.dart';
import 'sq.dart';
import '../../core/i18n/l10n.dart';

class SpellingPad extends StatelessWidget {
  final Question question;
  final List<int> chosen;
  final bool revealed;
  final ValueChanged<int> onPick;
  final VoidCallback onUndo;
  final VoidCallback onSubmit;

  /// Battles are tighter on space than solo rounds.
  final bool dense;

  /// True when the pad sits on the dark battle field.
  final bool onInk;

  const SpellingPad({
    super.key,
    required this.question,
    required this.chosen,
    required this.revealed,
    required this.onPick,
    required this.onUndo,
    required this.onSubmit,
    this.dense = false,
    this.onInk = false,
  });

  String get _built => chosen
      .where((i) => i >= 0 && i < question.letters.length)
      .map((i) => question.letters[i])
      .join();

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final target = question.spellTarget;
    final built = _built;
    final ok = built.toLowerCase() == target.toLowerCase();
    final full = built.length >= target.length;

    final tint = revealed
        ? (ok ? AppColors.green : AppColors.red)
        : AppColors.primary;
    final surface = onInk
        ? Colors.white.withValues(alpha: 0.06)
        : AppColors.card(d);
    final edge = onInk
        ? Colors.white.withValues(alpha: 0.10)
        : AppColors.border(d);
    final ink3 = onInk ? AppColors.onInk2 : AppColors.text3(d);

    return Column(
      children: [
        // ── answer slots ──────────────────────────────────
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: 14, vertical: dense ? 12 : 16),
          decoration: BoxDecoration(
            color: revealed && !onInk ? AppColors.soft(tint, d) : surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: revealed ? tint : edge,
              width: revealed ? 1.8 : 1),
          ),
          child: Wrap(
            spacing: 6, runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < target.length; i++)
                _Slot(
                  letter: i < built.length ? built[i] : null,
                  tint: tint,
                  revealed: revealed,
                  dense: dense,
                  onInk: onInk,
                ),
            ],
          ),
        ),

        if (built.isEmpty && !revealed) ...[
          const SizedBox(height: 8),
          Text(tr('Әріптерді басып сөзді жина'),
            style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: ink3)),
        ],

        if (revealed && !ok) ...[
          const SizedBox(height: 8),
          Text(trp('Дұрысы: {p1}', {'p1': question.answer}),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.green, fontSize: 15,
              fontWeight: FontWeight.w800)),
        ],

        SizedBox(height: dense ? 14 : 18),

        // ── letter tiles ──────────────────────────────────
        Wrap(
          spacing: 8, runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < question.letters.length; i++)
              _LetterTile(
                letter: question.letters[i],
                used: chosen.contains(i),
                enabled: !revealed && !full,
                dense: dense,
                onInk: onInk,
                onTap: () => onPick(i),
              ),
          ],
        ),

        SizedBox(height: dense ? 14 : 18),

        // ── controls ──────────────────────────────────────
        Row(
          children: [
            SqLip(
              fill: onInk ? Colors.white.withValues(alpha: 0.08) : AppColors.card(d),
              border: onInk ? null : edge,
              borderWidth: 1.5,
              lip: onInk ? null : (d ? AppColors.borderD : const Color(0xFFEDEAF6)),
              depth: 3,
              radius: 16,
              onTap: revealed || chosen.isEmpty ? null : onUndo,
              child: SizedBox(
                width: 54, height: dense ? 50 : 54,
                child: Icon(Icons.backspace_rounded,
                  size: 19,
                  color: revealed || chosen.isEmpty
                      ? (onInk ? AppColors.onInk3 : AppColors.text4(d))
                      : (onInk ? Colors.white : AppColors.text2(d))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SqAction(tr('Тексеру'),
                icon: Icons.check_rounded,
                height: dense ? 50 : 54,
                onTap: revealed || chosen.isEmpty ? null : onSubmit),
            ),
          ],
        ),
      ],
    );
  }
}

/// One slot of the word being built — empty slots stay visible so the learner
/// always sees how many letters are still missing.
class _Slot extends StatelessWidget {
  final String? letter;
  final Color tint;
  final bool revealed, dense, onInk;

  const _Slot({
    required this.letter, required this.tint,
    required this.revealed, required this.dense, required this.onInk});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final filled = letter != null;
    final idle = onInk
        ? Colors.white.withValues(alpha: 0.22)
        : AppColors.border(d);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: dense ? 26 : 30,
      height: dense ? 36 : 42,
      decoration: BoxDecoration(
        color: filled
            ? tint.withValues(alpha: d || onInk ? 0.22 : 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border(
          bottom: BorderSide(
            color: filled ? tint : idle,
            width: filled ? 2.4 : 2),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        (letter ?? '').toUpperCase(),
        style: TextStyle(
          fontSize: dense ? 17 : 20,
          fontWeight: FontWeight.w800,
          color: revealed
              ? tint
              : (onInk ? Colors.white : AppColors.text(d))),
      ),
    );
  }
}

class _LetterTile extends StatelessWidget {
  final String letter;
  final bool used, enabled, dense, onInk;
  final VoidCallback onTap;

  const _LetterTile({
    required this.letter, required this.used, required this.enabled,
    required this.dense, required this.onInk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final live = !used && enabled;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: used ? 0.25 : 1,
      child: SqLip(
        fill: onInk ? Colors.white : AppColors.card(d),
        border: onInk ? null : AppColors.border(d),
        borderWidth: 1.5,
        lip: onInk
            ? Colors.black.withValues(alpha: 0.35)
            : (d ? AppColors.borderD : const Color(0xFFEDEAF6)),
        depth: 4,
        radius: 14,
        onTap: live
            ? () { HapticFeedback.selectionClick(); onTap(); }
            : null,
        child: SizedBox(
          width: dense ? 42 : 46,
          height: dense ? 46 : 50,
          child: Center(
            child: Text(letter.toUpperCase(),
              style: TextStyle(
                fontSize: dense ? 19 : 21,
                fontWeight: FontWeight.w800,
                color: onInk ? AppColors.ink : AppColors.text(d))),
          ),
        ),
      ),
    );
  }
}
