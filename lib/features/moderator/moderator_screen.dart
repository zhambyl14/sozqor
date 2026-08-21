// lib/features/moderator/moderator_screen.dart
//
// The console: events, tournaments and the shop, run from inside the app.
//
// Before this screen the only way to start an event was to type a row into the
// Supabase dashboard, which meant the owner could not launch anything from a
// phone and every field was a chance to break a check constraint. Here the
// three catalogues are one segmented list, each row says at a glance whether
// it is live, and the three editors do the validating.
//
// This file also holds the form kit the editors share. It lives with the hub
// rather than in a file of its own because the hub is the one screen every
// editor already comes back to.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/moderator_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import 'event_editor_screen.dart';
import 'shop_item_editor_screen.dart';
import 'tournament_editor_screen.dart';

class ModeratorScreen extends ConsumerStatefulWidget {
  const ModeratorScreen({super.key});

  @override
  ConsumerState<ModeratorScreen> createState() => _ModeratorScreenState();
}

class _ModeratorScreenState extends ConsumerState<ModeratorScreen> {
  int _tab = 0;

  Future<void> _refresh() async {
    ref.invalidate(modEventsProvider);
    ref.invalidate(modTournamentsProvider);
    ref.invalidate(modCosmeticsProvider);
  }

  /// Saving here changes what learners see, so the learner-facing caches are
  /// dropped in the same breath — otherwise a new event is invisible on the
  /// home tab until the app restarts.
  Future<void> _openEvent(ModEvent? e) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EventEditorScreen(editing: e)));
    if (saved != true) return;
    ref.invalidate(modEventsProvider);
    ref.invalidate(activeEventsProvider);
  }

  Future<void> _openTournament(ModTournament? t) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TournamentEditorScreen(editing: t)));
    if (saved != true) return;
    ref.invalidate(modTournamentsProvider);
    ref.invalidate(tournamentProvider);
  }

  Future<void> _openItem(ModCosmetic? c) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ShopItemEditorScreen(editing: c)));
    if (saved != true) return;
    ref.invalidate(modCosmeticsProvider);
    ref.invalidate(shopCatalogueProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final gate = ref.watch(amModeratorProvider);

    if (gate.isLoading) {
      return SqPage(children: [
        _header(context),
        const SizedBox(height: 60),
        const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      ]);
    }

    if (gate.value != true) {
      return SqPage(children: [
        _header(context),
        const SizedBox(height: 30),
        SqEmpty(
          icon: PhosphorIconsFill.lockKey,
          tint: AppColors.red,
          title: tr('Рұқсат жоқ'),
          subtitle: tr('Бұл бөлім тек модераторға арналған')),
      ]);
    }

    return SqPage(
      onRefresh: _refresh,
      children: [
        _header(context),
        const SizedBox(height: 16),
        SqSegmented(
          items: [tr('Оқиғалар'), tr('Турнирлер'), tr('Дүкен')],
          index: _tab,
          onChanged: (i) => setState(() => _tab = i)),
        const SizedBox(height: 16),
        ...switch (_tab) {
          0 => _eventsSection(),
          1 => _tournamentsSection(),
          _ => _shopSection(),
        },
      ],
    );
  }

  Widget _header(BuildContext context) => SqHeader(
    title: tr('Басқару'),
    eyebrow: tr('Модератор'),
    onBack: () => Navigator.of(context).pop());

  // ── Events ───────────────────────────────────────────────
  List<Widget> _eventsSection() => [
    SqAction(tr('Жаңа оқиға'),
      icon: PhosphorIconsBold.plus,
      onTap: () => _openEvent(null)),
    const SizedBox(height: 14),
    ..._list<ModEvent>(
      ref.watch(modEventsProvider),
      empty: tr('Әзірге оқиға жоқ'),
      row: (e) => SqTile(
        leading: _Glyph(text: e.emoji),
        title: e.title.isEmpty ? tr('Атаусыз') : e.title,
        subtitle: '${_range(e.cefrMin, e.cefrMax)} · '
                  '${modDate(e.startsAt)} – ${modDate(e.endsAt)}',
        trailing: _PhaseTag(e.phase),
        chevron: true,
        onTap: () => _openEvent(e)),
    ),
  ];

  // ── Tournaments ──────────────────────────────────────────
  List<Widget> _tournamentsSection() => [
    SqAction(tr('Жаңа турнир'),
      icon: PhosphorIconsBold.plus,
      onTap: () => _openTournament(null)),
    const SizedBox(height: 14),
    ..._list<ModTournament>(
      ref.watch(modTournamentsProvider),
      empty: tr('Әзірге турнир жоқ'),
      row: (t) => SqTile(
        leading: _Glyph(text: t.emoji),
        title: t.title.isEmpty ? tr('Атаусыз') : t.title,
        subtitle: '${_range(t.cefrMin, t.cefrMax)} · '
                  '${modDate(t.startsAt)} – ${modDate(t.endsAt)}',
        trailing: _PhaseTag(t.phase),
        chevron: true,
        onTap: () => _openTournament(t)),
    ),
  ];

  // ── Shop ─────────────────────────────────────────────────
  List<Widget> _shopSection() => [
    SqAction(tr('Жаңа зат'),
      icon: PhosphorIconsBold.plus,
      onTap: () => _openItem(null)),
    const SizedBox(height: 14),
    ..._list<ModCosmetic>(
      ref.watch(modCosmeticsProvider),
      empty: tr('Әзірге зат жоқ'),
      row: (c) => SqTile(
        leading: _Glyph(text: c.payload, color: sqHexColor(c.payload)),
        title: (AppLang.isRu ? c.nameRu : c.nameKk).isEmpty
            ? c.id
            : (AppLang.isRu ? c.nameRu : c.nameKk),
        subtitle: '${modCosmeticKindLabel(c.kind)} · ${c.price} XP · '
                  '${modRarityLabel(c.rarity)}',
        trailing: c.isActive
            ? null
            : SqBadge(tr('Тоқтатылған'), tint: AppColors.red),
        chevron: true,
        onTap: () => _openItem(c)),
    ),
  ];

  /// One list-shaped section: placeholder, error or a group of rows.
  List<Widget> _list<T>(
    AsyncValue<List<T>> async, {
    required String empty,
    required Widget Function(T) row,
  }) => async.when(
    loading: () => const [SqShimmer(), SqShimmer(), SqShimmer()],
    error: (e, _) => [
      SqEmpty(
        icon: PhosphorIconsFill.warningCircle,
        tint: AppColors.red,
        title: tr('Жүктелмеді'),
        subtitle: humanError(e)),
    ],
    data: (items) => items.isEmpty
        ? [SqEmpty(icon: PhosphorIconsFill.stack, title: empty)]
        : [SqGroup(children: [for (final i in items) row(i)])],
  );

  String _range(String min, String max) =>
      min == kModCefr.first && max == kModCefr.last
          ? tr('Барлық деңгей')
          : '$min–$max';
}

// ═══════════════════════════════════════════════════════════
// Row pieces
// ═══════════════════════════════════════════════════════════

/// The square that leads a row: an emoji, a colour swatch, or neither.
class _Glyph extends StatelessWidget {
  final String? text;
  final Color? color;
  const _Glyph({this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final tint = color ?? AppColors.primary;
    return Container(
      width: 38, height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? AppColors.soft(AppColors.primary, d),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.line(tint, d)),
      ),
      // A colour swatch says everything on its own; only an emoji needs ink.
      child: color != null
          ? null
          : Text(text ?? '•', style: const TextStyle(fontSize: 17)),
    );
  }
}

class _PhaseTag extends StatelessWidget {
  final ModPhase phase;
  const _PhaseTag(this.phase);

  @override
  Widget build(BuildContext context) {
    final (label, tint) = modPhaseTag(phase);
    return SqBadge(label, tint: tint, solid: phase == ModPhase.running);
  }
}

// ═══════════════════════════════════════════════════════════
// Labels
// ═══════════════════════════════════════════════════════════

(String, Color) modPhaseTag(ModPhase p) => switch (p) {
  ModPhase.running  => (tr('Жүріп жатыр'), AppColors.green),
  ModPhase.upcoming => (tr('Басталмаған'), AppColors.amber),
  ModPhase.ended    => (tr('Аяқталды'), AppColors.sky),
  ModPhase.retired  => (tr('Тоқтатылған'), AppColors.red),
};

String modEventKindLabel(String kind) => switch (kind) {
  'topic_pack' => tr('Тақырып жинағы'),
  'tournament' => tr('Турнир'),
  'season'     => tr('Маусым'),
  'quest'      => tr('Тапсырма'),
  _            => tr('Сын-қатер'),
};

String modCosmeticKindLabel(String kind) => switch (kind) {
  'title'  => tr('Атақ'),
  'avatar' => tr('Аватар'),
  'banner' => tr('Баннер'),
  'badge'  => tr('Белгіше'),
  'aura'   => tr('Аура'),
  _        => tr('Жиек'),
};

String modRarityLabel(String rarity) => switch (rarity) {
  'rare'   => tr('Сирек'),
  'epic'   => tr('Эпик'),
  'legend' => tr('Аңыз'),
  _        => tr('Қарапайым'),
};

/// `dd.MM.yy`. Written by hand rather than through intl because the console
/// only ever shows one date shape and it must read the same in both languages.
String modDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${two(d.year % 100)}';
}

// ═══════════════════════════════════════════════════════════
// Form kit
// ═══════════════════════════════════════════════════════════

/// A labelled text field whose error sits directly under it.
///
/// The editors are long forms; an error collected at the bottom would leave
/// the owner hunting for the field it belongs to.
class ModField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint, error;
  final int lines;
  final bool numeric, enabled;
  final ValueChanged<String>? onChanged;

  const ModField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.error,
    this.lines = 1,
    this.numeric = false,
    this.enabled = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SqEyebrow(label),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        enabled: enabled,
        maxLines: numeric ? 1 : lines,
        keyboardType:
            numeric ? TextInputType.number : TextInputType.multiline,
        inputFormatters:
            numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700,
          color: AppColors.text(isDark(context))),
        decoration: InputDecoration(
          hintText: hint, errorText: error, isDense: true),
      ),
    ],
  );
}

/// One value out of a short list, as chips. Every column the console writes
/// into is guarded by a check constraint, so nothing here is ever free text.
class ModPicker extends StatelessWidget {
  final String label;
  final List<String> values;
  final String? selected;
  final String Function(String) labelOf;
  final ValueChanged<String> onPick;
  final String? error;
  final Color tint;

  const ModPicker({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onPick,
    this.error,
    this.tint = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SqEyebrow(label),
      const SizedBox(height: 8),
      Wrap(
        spacing: 7, runSpacing: 7,
        children: [
          for (final v in values)
            SqChip(labelOf(v),
              tint: tint,
              selected: v == selected,
              outlined: v != selected,
              onTap: () => onPick(v)),
        ],
      ),
      if (error != null) ...[
        const SizedBox(height: 7),
        ModError(error!),
      ],
    ],
  );
}

/// A date and time picked from the calendar. Timestamps are never typed —
/// that is the whole reason the owner stopped using the dashboard.
class ModDateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onPick;
  final String? error;

  const ModDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onPick,
    this.error,
  });

  Future<void> _pick(BuildContext context) async {
    final day = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (day == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context, initialTime: TimeOfDay.fromDateTime(value));
    // Cancelling the clock keeps the hour the field already had, so picking a
    // day never silently moves an event to midnight.
    final t = time ?? TimeOfDay.fromDateTime(value);
    onPick(DateTime(day.year, day.month, day.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    String two(int v) => v.toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SqEyebrow(label),
        const SizedBox(height: 6),
        SqPanel(
          radius: 17,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          border: error == null ? null : AppColors.red,
          onTap: () => _pick(context),
          child: Row(
            children: [
              const Icon(PhosphorIconsFill.calendarBlank,
                size: 18, color: AppColors.primary),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  '${modDate(value)} · ${two(value.hour)}:${two(value.minute)}',
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800,
                    color: AppColors.text(d))),
              ),
              Icon(PhosphorIconsBold.caretRight,
                size: 15, color: AppColors.text4(d)),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 7),
          ModError(error!),
        ],
      ],
    );
  }
}

/// An on/off row, used for `is_active`.
class ModSwitch extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const ModSwitch({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SqTile(
    // No horizontal padding: the row already sits inside a padded card.
    padding: const EdgeInsets.symmetric(vertical: 2),
    title: title,
    subtitle: subtitle,
    trailing: Switch(value: value, onChanged: onChanged),
    onTap: () => onChanged(!value),
  );
}

/// The red line under a field that failed validation.
class ModError extends StatelessWidget {
  final String text;
  const ModError(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(PhosphorIconsFill.warningCircle,
          size: 14, color: AppColors.red),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
            style: const TextStyle(
              fontSize: 11.5, height: 1.35,
              fontWeight: FontWeight.w700, color: AppColors.red)),
        ),
      ],
    ),
  );
}

/// The white block every group of fields sits in.
class ModCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const ModCard({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SqSection(title),
        SqPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                children[i],
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
