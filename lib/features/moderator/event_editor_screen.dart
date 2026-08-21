// lib/features/moderator/event_editor_screen.dart
//
// One event, start to finish.
//
// The word level range is the field that actually decides what an event is:
// `active_events` only shows a row to learners whose level sits between
// `cefr_min` and `cefr_max`, so getting it wrong means nobody ever sees the
// event. It gets its own section rather than being buried among the text.
//
// Validation is per field. A form this long cannot report "something is
// wrong" at the bottom and expect the owner to find which line it meant.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/moderator_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import 'moderator_screen.dart';

class EventEditorScreen extends ConsumerStatefulWidget {
  /// Null creates a new event.
  final ModEvent? editing;

  const EventEditorScreen({super.key, this.editing});

  @override
  ConsumerState<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<EventEditorScreen> {
  late final ModEvent _base = widget.editing ?? ModEvent.blank();

  late final _emoji      = TextEditingController(text: _base.emoji);
  late final _title      = TextEditingController(text: _base.title);
  late final _titleRu    = TextEditingController(text: _base.titleRu);
  late final _subtitle   = TextEditingController(text: _base.subtitle);
  late final _subtitleRu = TextEditingController(text: _base.subtitleRu);
  late final _rulesKk    = TextEditingController(text: _base.rulesKk);
  late final _rulesRu    = TextEditingController(text: _base.rulesRu);
  late final _whoKk      = TextEditingController(text: _base.whoKk);
  late final _whoRu      = TextEditingController(text: _base.whoRu);
  late final _xp         = TextEditingController(text: '${_base.xpReward}');
  late final _target     = TextEditingController(text: '${_base.target}');
  late final _topN       = TextEditingController(text: '${_base.prizeTopN}');

  late String _kind      = _base.kind;
  late String? _topic    = _base.topic;
  late String _cefrMin   = _base.cefrMin;
  late String _cefrMax   = _base.cefrMax;
  late String? _prize    = _base.prizeItem;
  late DateTime _startsAt = _base.startsAt;
  late DateTime _endsAt   = _base.endsAt;
  late bool _active      = _base.isActive;

  String? _errTitle, _errLevels, _errEnds;
  bool _saving = false;

  bool get _isEdit => widget.editing?.id != null;

  @override
  void dispose() {
    for (final c in [
      _emoji, _title, _titleRu, _subtitle, _subtitleRu,
      _rulesKk, _rulesRu, _whoKk, _whoRu, _xp, _target, _topN,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int _num(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

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
      await ref.read(moderatorRepoProvider).saveEvent(ModEvent(
        id: _base.id,
        slug: _base.slug,
        title: title,
        titleRu: _titleRu.text,
        subtitle: _subtitle.text,
        subtitleRu: _subtitleRu.text,
        emoji: _emoji.text,
        kind: _kind,
        topic: _topic,
        cefrMin: _cefrMin,
        cefrMax: _cefrMax,
        rulesKk: _rulesKk.text,
        rulesRu: _rulesRu.text,
        whoKk: _whoKk.text,
        whoRu: _whoRu.text,
        xpReward: _num(_xp, 200),
        target: _num(_target, 10).clamp(1, 100000),
        prizeTopN: _num(_topN, 0),
        prizeItem: _prize,
        startsAt: _startsAt,
        endsAt: _endsAt,
        isActive: _active,
        extra: _base.extra,
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

  /// The prize is a row in `cosmetics`, so it is picked from the shop rather
  /// than typed — a mistyped id would save fine and hand out nothing.
  Future<void> _pickPrize() async {
    final items = ref.read(modCosmeticsProvider).value ?? const <ModCosmetic>[];
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(
            children: [
              const SqSheetGrip(),
              Text(tr('Сыйлық заты'),
                style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800,
                  color: AppColors.text(isDark(ctx)))),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  children: [
                    SqGroup(children: [
                      SqTile(
                        title: tr('Сыйлықсыз'),
                        onTap: () => Navigator.of(ctx).pop('')),
                      for (final c in items.where((c) => c.isActive))
                        SqTile(
                          title: (AppLang.isRu ? c.nameRu : c.nameKk).isEmpty
                              ? c.id
                              : (AppLang.isRu ? c.nameRu : c.nameKk),
                          subtitle:
                              '${modCosmeticKindLabel(c.kind)} · ${c.id}',
                          onTap: () => Navigator.of(ctx).pop(c.id)),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _prize = picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    // Watched, not read: the prize sheet needs the catalogue loaded, and this
    // screen can be reached without the shop tab ever having been opened.
    final catalogue = ref.watch(modCosmeticsProvider).value ??
        const <ModCosmetic>[];

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: _isEdit ? tr('Оқиғаны өңдеу') : tr('Жаңа оқиға'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        ModCard(title: tr('Атауы'), children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                child: ModField(
                  label: tr('Эмодзи'), controller: _emoji, hint: '🎉'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ModField(
                  label: tr('Қазақша атауы'),
                  controller: _title,
                  error: _errTitle,
                  onChanged: (_) {
                    if (_errTitle != null) setState(() => _errTitle = null);
                  }),
              ),
            ],
          ),
          ModField(label: tr('Орысша атауы'), controller: _titleRu),
          ModField(label: tr('Қазақша сипаттама'), controller: _subtitle),
          ModField(label: tr('Орысша сипаттама'), controller: _subtitleRu),
        ]),

        ModCard(title: tr('Түрі'), children: [
          ModPicker(
            label: tr('Оқиға түрі'),
            values: kModEventKinds,
            selected: _kind,
            labelOf: modEventKindLabel,
            onPick: (v) => setState(() => _kind = v)),
          ModPicker(
            label: tr('Тақырып'),
            values: ['', for (final t in kTopics) t.key],
            selected: _topic ?? '',
            labelOf: (k) => k.isEmpty
                ? tr('Тақырыпсыз')
                : '${topicOf(k).emoji} ${tr(topicOf(k).label)}',
            onPick: (v) => setState(() => _topic = v.isEmpty ? null : v)),
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

        ModCard(title: tr('Ережелер'), children: [
          ModField(
            label: tr('Қазақша ереже'), controller: _rulesKk, lines: 4),
          ModField(
            label: tr('Орысша ереже'), controller: _rulesRu, lines: 4),
        ]),

        ModCard(title: tr('Кім қатысады'), children: [
          ModField(label: tr('Қазақша'), controller: _whoKk, lines: 3),
          ModField(label: tr('Орысша'), controller: _whoRu, lines: 3),
        ]),

        ModCard(title: tr('Сыйлық'), children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ModField(
                  label: tr('XP сыйлығы'),
                  controller: _xp,
                  numeric: true)),
              const SizedBox(width: 12),
              Expanded(
                child: ModField(
                  label: tr('Мақсат саны'),
                  controller: _target,
                  numeric: true)),
            ],
          ),
          _PickRow(
            label: tr('Сыйлық заты'),
            value: _prizeLabel(catalogue),
            icon: PhosphorIconsFill.gift,
            onTap: _pickPrize),
          ModField(
            label: tr('Алғашқы неше адамға'),
            controller: _topN,
            numeric: true),
        ]),

        ModCard(title: tr('Мерзімі'), children: [
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
          ModSwitch(
            title: tr('Белсенді'),
            // Deleting would take the progress with it, so the console never
            // offers it: this switch is the only way to end an event.
            subtitle: tr('Өшірсең, оқиға тізімнен жоғалады'),
            value: _active,
            onChanged: (v) => setState(() => _active = v)),
        ]),

        SqAction(tr('Сақтау'),
          icon: PhosphorIconsBold.check,
          busy: _saving,
          onTap: _saving ? null : _save),
      ],
    );
  }

  String _prizeLabel(List<ModCosmetic> catalogue) {
    final id = _prize;
    if (id == null) return tr('Сыйлықсыз');
    for (final c in catalogue) {
      if (c.id != id) continue;
      final name = AppLang.isRu ? c.nameRu : c.nameKk;
      return name.isEmpty ? id : name;
    }
    return id;
  }
}

/// A row that opens a picker sheet — shaped like [ModDateField] so the form
/// reads as one kind of control throughout.
class _PickRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final VoidCallback onTap;

  const _PickRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SqEyebrow(label),
        const SizedBox(height: 6),
        SqPanel(
          radius: 17,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          onTap: onTap,
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 11),
              Expanded(
                child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800,
                    color: AppColors.text(d))),
              ),
              Icon(PhosphorIconsBold.caretRight,
                size: 15, color: AppColors.text4(d)),
            ],
          ),
        ),
      ],
    );
  }
}
