// lib/features/moderator/tournament_editor_screen.dart
//
// One tournament: a title, a level band, a prize and a window.
//
// `tournaments` has no `is_active` column, so a tournament cannot be retired —
// it only ever waits, runs or is over. Shortening `ends_at` is how you stop
// one early, which is why the dates stay editable after it has started.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/moderator_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import 'moderator_screen.dart';

class TournamentEditorScreen extends ConsumerStatefulWidget {
  /// Null creates a new tournament.
  final ModTournament? editing;

  const TournamentEditorScreen({super.key, this.editing});

  @override
  ConsumerState<TournamentEditorScreen> createState() =>
      _TournamentEditorScreenState();
}

class _TournamentEditorScreenState
    extends ConsumerState<TournamentEditorScreen> {
  late final ModTournament _base = widget.editing ?? ModTournament.blank();

  late final _emoji = TextEditingController(text: _base.emoji);
  late final _title = TextEditingController(text: _base.title);
  late final _xp    = TextEditingController(text: '${_base.xpReward}');

  late String _cefrMin = _base.cefrMin;
  late String _cefrMax = _base.cefrMax;
  late DateTime _startsAt = _base.startsAt;
  late DateTime _endsAt = _base.endsAt;

  String? _errTitle, _errLevels, _errEnds;
  bool _saving = false;

  bool get _isEdit => widget.editing?.id != null;

  @override
  void dispose() {
    _emoji.dispose();
    _title.dispose();
    _xp.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    setState(() {
      _errTitle = title.isEmpty ? tr('Атауын жаз') : null;
      _errLevels = modCefrIndex(_cefrMin) > modCefrIndex(_cefrMax)
          ? tr('Төменгі деңгей жоғарғысынан аспауы керек')
          : null;
      _errEnds = _endsAt.isAfter(_startsAt)
          ? null
          : tr('Аяқталуы басталуынан кейін болсын');
    });
    if (_errTitle != null || _errLevels != null || _errEnds != null) return;

    setState(() => _saving = true);
    try {
      await ref.read(moderatorRepoProvider).saveTournament(ModTournament(
        id: _base.id,
        title: title,
        emoji: _emoji.text,
        cefrMin: _cefrMin,
        cefrMax: _cefrMax,
        xpReward: int.tryParse(_xp.text.trim()) ?? 300,
        startsAt: _startsAt,
        endsAt: _endsAt,
      ));
      if (!mounted) return;
      sqSnack(context, tr('Сақталды'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        sqSnack(context, humanError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: _isEdit ? tr('Турнирді өңдеу') : tr('Жаңа турнир'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        ModCard(title: tr('Атауы'), children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                child: ModField(
                  label: tr('Эмодзи'), controller: _emoji, hint: '🏆'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ModField(
                  label: tr('Атауы'),
                  controller: _title,
                  error: _errTitle,
                  onChanged: (_) {
                    if (_errTitle != null) setState(() => _errTitle = null);
                  }),
              ),
            ],
          ),
        ]),

        ModCard(title: tr('Сөз деңгейі'), children: [
          ModPicker(
            label: tr('Ең төменгі деңгей'),
            values: kModCefr,
            selected: _cefrMin,
            labelOf: (v) => v,
            tint: AppColors.sky,
            onPick: (v) => setState(() {
              _cefrMin = v;
              _errLevels = null;
            })),
          ModPicker(
            label: tr('Ең жоғарғы деңгей'),
            values: kModCefr,
            selected: _cefrMax,
            labelOf: (v) => v,
            tint: AppColors.sky,
            error: _errLevels,
            onPick: (v) => setState(() {
              _cefrMax = v;
              _errLevels = null;
            })),
        ]),

        ModCard(title: tr('Мерзімі'), children: [
          ModField(label: tr('XP сыйлығы'), controller: _xp, numeric: true),
          ModDateField(
            label: tr('Басталуы'),
            value: _startsAt,
            onPick: (v) => setState(() {
              _startsAt = v;
              _errEnds = null;
            })),
          ModDateField(
            label: tr('Аяқталуы'),
            value: _endsAt,
            error: _errEnds,
            onPick: (v) => setState(() {
              _endsAt = v;
              _errEnds = null;
            })),
        ]),

        SqAction(tr('Сақтау'),
          icon: PhosphorIconsBold.check,
          busy: _saving,
          onTap: _saving ? null : _save),
      ],
    );
  }
}
