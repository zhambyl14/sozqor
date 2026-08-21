// lib/features/moderator/shop_item_editor_screen.dart
//
// One shop item.
//
// The shape here is dictated by what already renders items: `shop_catalogue`
// hands the client `kind`, `name_kk`/`name_ru`, `price`, `rarity`, `requires`
// and a `data` blob, and `worn_cosmetics` reads exactly one key out of that
// blob — `color` for a frame, banner or aura, `emoji` for an avatar or badge,
// nothing at all for a title, whose name *is* the text people see. So the
// editor asks for one payload value and picks the key itself; an item saved
// under the wrong key would look fine here and render as nothing everywhere
// else.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/moderator_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import 'moderator_screen.dart';

class ShopItemEditorScreen extends ConsumerStatefulWidget {
  /// Null creates a new item.
  final ModCosmetic? editing;

  const ShopItemEditorScreen({super.key, this.editing});

  @override
  ConsumerState<ShopItemEditorScreen> createState() =>
      _ShopItemEditorScreenState();
}

class _ShopItemEditorScreenState extends ConsumerState<ShopItemEditorScreen> {
  late final ModCosmetic _base = widget.editing ?? ModCosmetic.blank();

  late final _id       = TextEditingController(text: _base.id);
  late final _nameKk   = TextEditingController(text: _base.nameKk);
  late final _nameRu   = TextEditingController(text: _base.nameRu);
  late final _price    = TextEditingController(text: '${_base.price}');
  late final _sort     = TextEditingController(text: '${_base.sort}');
  late final _requires = TextEditingController(text: _base.requires ?? '');
  late final _payload  = TextEditingController(text: _base.payload ?? '');

  late String _kind   = _base.kind;
  late String _rarity = _base.rarity;
  late bool _active   = _base.isActive;

  String? _errId, _errName, _errPayload, _errRequires;
  bool _saving = false;

  bool get _isEdit => widget.editing != null;

  @override
  void dispose() {
    for (final c in [
      _id, _nameKk, _nameRu, _price, _sort, _requires, _payload,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final id = _id.text.trim();
    final nameKk = _nameKk.text.trim();
    final requires = _requires.text.trim();
    final payload = _payload.text.trim();
    final key = modDataKeyFor(_kind);

    setState(() {
      _errId = switch (id) {
        '' => tr('Идентификатор керек'),
        _ when !RegExp(r'^[a-z0-9_]+$').hasMatch(id) =>
            tr('Тек кіші латын әрпі, сан және _'),
        _ => null,
      };
      _errName = nameKk.isEmpty ? tr('Қазақша атауын жаз') : null;
      // A colour that does not parse renders as nothing at all, which looks
      // like a broken shop rather than a mistyped field.
      _errPayload = key == 'color' && payload.isNotEmpty &&
              sqHexColor(payload) == null
          ? tr('Түс #RRGGBB түрінде болсын')
          : null;
      _errRequires = requires.isNotEmpty && !_looksLikeRequires(requires)
          ? tr('Шарт «streak:30» түрінде болсын')
          : null;
    });
    if (_errId != null || _errName != null ||
        _errPayload != null || _errRequires != null) {
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(moderatorRepoProvider);
      if (!_isEdit && await repo.cosmeticExists(id)) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _errId = tr('Мұндай идентификатор бар');
        });
        return;
      }

      // Whatever else the blob carried is kept: only the one key this kind
      // renders through is the console's to rewrite.
      final data = Map<String, dynamic>.from(_base.data);
      for (final k in ['color', 'emoji']) {
        data.remove(k);
      }
      if (key != null && payload.isNotEmpty) data[key] = payload;

      await repo.saveCosmetic(
        ModCosmetic(
          id: id,
          kind: _kind,
          nameKk: nameKk,
          // A blank Russian name would leave a Russian-speaking learner
          // staring at an empty row, so it falls back to the Kazakh one.
          nameRu: _nameRu.text.trim().isEmpty ? nameKk : _nameRu.text.trim(),
          rarity: _rarity,
          price: int.tryParse(_price.text.trim()) ?? 0,
          sort: int.tryParse(_sort.text.trim()) ?? 0,
          requires: requires.isEmpty ? null : requires,
          data: data,
          isActive: _active,
        ),
        isNew: !_isEdit,
      );
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

  /// `metric:threshold`, the shape `cosmetic_unlocked` splits on.
  bool _looksLikeRequires(String v) {
    final parts = v.split(':');
    return parts.length == 2 &&
        parts.first.trim().isNotEmpty &&
        int.tryParse(parts.last.trim()) != null;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final key = modDataKeyFor(_kind);

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: _isEdit ? tr('Затты өңдеу') : tr('Жаңа зат'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        ModCard(title: tr('Не екені'), children: [
          ModPicker(
            label: tr('Түрі'),
            values: kModCosmeticKinds,
            selected: _kind,
            labelOf: modCosmeticKindLabel,
            onPick: (v) => setState(() {
              _kind = v;
              _errPayload = null;
            })),
          ModField(
            label: tr('Идентификатор'),
            controller: _id,
            hint: 'frame_gold',
            // The id is the primary key and `user_cosmetics` points at it, so
            // changing it on an existing item would orphan every purchase.
            enabled: !_isEdit,
            error: _errId,
            onChanged: (_) {
              if (_errId != null) setState(() => _errId = null);
            }),
        ]),

        ModCard(title: tr('Атауы'), children: [
          ModField(
            label: tr('Қазақша'),
            controller: _nameKk,
            error: _errName,
            onChanged: (_) {
              if (_errName != null) setState(() => _errName = null);
            }),
          ModField(label: tr('Орысша'), controller: _nameRu),
        ]),

        if (key != null)
          ModCard(title: tr('Көрінісі'), children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ModField(
                    label: key == 'color' ? tr('Түсі') : tr('Эмодзи'),
                    controller: _payload,
                    hint: key == 'color' ? '#7C5CFF' : '🦊',
                    error: _errPayload,
                    onChanged: (_) => setState(() => _errPayload = null)),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: _Preview(
                    isColor: key == 'color', value: _payload.text.trim()),
                ),
              ],
            ),
          ])
        else
          ModCard(title: tr('Көрінісі'), children: [
            Text(tr('Атақтың мәтіні — атауының өзі'),
              style: TextStyle(
                fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600,
                color: AppColors.text3(isDark(context)))),
          ]),

        ModCard(title: tr('Бағасы'), children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ModField(
                  label: tr('Бағасы (XP)'),
                  controller: _price,
                  numeric: true)),
              const SizedBox(width: 12),
              Expanded(
                child: ModField(
                  label: tr('Реті'), controller: _sort, numeric: true)),
            ],
          ),
          ModPicker(
            label: tr('Сиректігі'),
            values: kModRarities,
            selected: _rarity,
            labelOf: modRarityLabel,
            tint: AppColors.amber,
            onPick: (v) => setState(() => _rarity = v)),
          ModField(
            label: tr('Ашылу шарты'),
            controller: _requires,
            hint: 'streak:30',
            error: _errRequires,
            onChanged: (_) {
              if (_errRequires != null) setState(() => _errRequires = null);
            }),
          ModSwitch(
            title: tr('Дүкенде тұрсын'),
            // Never a delete: `user_cosmetics` rows point here, and dropping
            // one would take away something a learner paid XP for.
            subtitle: tr('Өшірсең, дүкеннен жоғалады'),
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
}

/// What the payload will look like once it is worn.
class _Preview extends StatelessWidget {
  final bool isColor;
  final String value;
  const _Preview({required this.isColor, required this.value});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final color = isColor ? sqHexColor(value) : null;
    return Container(
      width: 50, height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? AppColors.muted(d),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border(d), width: 2),
      ),
      child: isColor
          ? null
          : Text(value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 22)),
    );
  }
}
