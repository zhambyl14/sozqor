// lib/features/onboarding/onboarding_screen.dart
//
// First run, in three steps: who you are and which language you translate to,
// what level you are at, and how much you want to do per day.
//
// 3.0 asked four questions including a topic picker whose only job was to pick
// the starter words. 4.0 drops it — the level alone seeds a sensible pack, and
// one fewer screen between "install" and "first round" is worth more than a
// slightly better starter list. A progress rail and a running summary of what
// you have chosen sit on every step, so nothing feels like a trap.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/dict_entry.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/local_dictionary.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();

  int _step = 0;
  // Preselects to whichever language the app is already showing, so the
  // words a beginner sees during onboarding are never in a language they
  // never chose. Still just a default — the step below lets them pick either.
  String _lang = AppLang.current;
  String _level = 'A1';
  int _goal = 10;
  bool _busy = false;
  bool _levelFromTest = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(myProfileProvider).value;
    if (p != null) {
      _name.text = p.displayName.trim().isEmpty ? '' : p.displayName;
      _lang = p.nativeLang;
      _level = p.cefrLevel;
      _goal = p.dailyGoal;
    }
  }

  @override
  void dispose() { _name.dispose(); super.dispose(); }

  void _to(int step) => setState(() => _step = step.clamp(0, 2));

  Future<void> _haveAccount() async {
    final ok = await sqConfirm(context,
      title: tr('Аккаунтқа кіру'),
      message: tr('Бар аккаунтыңның нөмірі мен құпия сөзін енгізесің.'),
      confirm: tr('Кіру'),
      cancel: tr('Болдырмау'),
      danger: false);
    if (!ok) return;
    ref.read(showLoginProvider.notifier).state = true;
    await ref.read(authRepoProvider).signOut();
  }

  Future<void> _openTest() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PlacementTestScreen()));
    if (result != null && mounted) {
      setState(() { _level = result; _levelFromTest = true; });
      _to(2);
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      final profiles = ref.read(profileRepoProvider);
      await profiles.update({
        'display_name': _name.text.trim(),
        'cefr_level': _level,
        'native_lang': _lang,
        'daily_goal': _goal,
      });
      await _seedStarterWords();
      await profiles.finishOnboarding();
      refreshAll(ref);
      ref.invalidate(myProfileProvider);
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Drops ten level-appropriate words into the bank so every screen has
  /// something to show from the very first second.
  Future<void> _seedStarterWords() async {
    try {
      await LocalDictionary.instance.load();
      final pool = <DictEntry>[
        ...LocalDictionary.instance.byLevels([_level]),
        ...LocalDictionary.instance.byLevels(visibleCefrFor(_level)),
      ];
      final seen = <String>{};
      final picks = <DictEntry>[];
      pool.shuffle(Random());
      for (final e in pool) {
        if (seen.add(e.en.toLowerCase())) picks.add(e);
        if (picks.length >= 10) break;
      }
      if (picks.isNotEmpty) {
        await ref.read(wordsRepoProvider).addManyFromDict(picks);
      }
    } catch (_) {
      // a failed starter pack must never block onboarding
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);

    return Scaffold(
      backgroundColor: AppColors.bg(d),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            children: [
              Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        height: 6,
                        decoration: BoxDecoration(
                          color: i <= _step
                              ? AppColors.primary
                              : (d ? AppColors.borderD
                                   : const Color(0xFFE7E4F3)),
                          borderRadius: BorderRadius.circular(999)),
                      ),
                    ),
                    const SizedBox(width: 9),
                  ],
                  SqNum('${_step + 1} / 3',
                    size: 11, color: AppColors.text3(d)),
                ],
              ),
              const SizedBox(height: 18),

              Expanded(
                child: switch (_step) {
                  0 => _StepName(
                    name: _name,
                    lang: _lang,
                    onLang: (l) => setState(() => _lang = l),
                    onHaveAccount: _haveAccount),
                  1 => _StepLevel(
                    selected: _level,
                    fromTest: _levelFromTest,
                    onPick: (l) => setState(() {
                      _level = l;
                      _levelFromTest = false;
                    }),
                    onTest: _openTest),
                  _ => _StepGoal(
                    goal: _goal,
                    lang: _lang,
                    level: _level,
                    onPick: (g) => setState(() => _goal = g)),
                },
              ),

              const SizedBox(height: 12),
              Row(
                children: [
                  if (_step > 0) ...[
                    SqSquareButton(PhosphorIconsBold.arrowLeft,
                      size: 56,
                      lip: d ? AppColors.borderD : const Color(0xFFEDEAF6),
                      onTap: () => _to(_step - 1)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: SqAction(
                      _step == 2 ? tr('Бастайық') : tr('Жалғастыру'),
                      trailingIcon: _step == 2
                          ? PhosphorIconsBold.rocketLaunch
                          : PhosphorIconsBold.arrowRight,
                      height: 56,
                      busy: _busy,
                      onTap: () {
                        if (_step == 0 && _name.text.trim().length < 2) {
                          sqSnack(context, tr('Атыңды жаз'), error: true);
                          return;
                        }
                        if (_step == 2) { _finish(); return; }
                        _to(_step + 1);
                      }),
                  ),
                ],
              ),
              if (_step == 2) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _busy ? null : _finish,
                  child: Text(tr('Кейін өзгертемін'))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Step 1: name + study language ──────────────────────────

class _StepName extends StatefulWidget {
  final TextEditingController name;
  final String lang;
  final ValueChanged<String> onLang;
  final VoidCallback onHaveAccount;

  const _StepName({
    required this.name, required this.lang,
    required this.onLang, required this.onHaveAccount});

  @override
  State<_StepName> createState() => _StepNameState();
}

class _StepNameState extends State<_StepName> {
  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return ListView(
      children: [
        SqEyebrow(tr('SozQor-ға қош келдің')),
        const SizedBox(height: 7),
        Text(tr('Танысып алайық'),
          style: TextStyle(
            fontSize: 28, height: 1.2, fontWeight: FontWeight.w800,
            letterSpacing: -0.9, color: AppColors.text(d))),
        const SizedBox(height: 8),
        Text(tr('Тіркелудің керегі жоқ — бірден бастай бер.'),
          style: TextStyle(
            fontSize: 13, height: 1.5, fontWeight: FontWeight.w600,
            color: AppColors.text3(d))),
        const SizedBox(height: 22),

        SqPanel(
          padding: const EdgeInsets.fromLTRB(17, 15, 17, 17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SqEyebrow(tr('Атың')),
              const SizedBox(height: 8),
              TextField(
                controller: widget.name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.text(d)),
                decoration: InputDecoration(
                  hintText: tr('Мысалы, Ерасыл'),
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppColors.text4(d)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 9),
          child: SqEyebrow(tr('Ана тілім'))),
        for (final l in [('kk', 'Қазақша'), ('ru', 'Орысша')]) ...[
          _Choice(
            title: tr(l.$2),
            subtitle: l.$1 == 'kk'
                ? tr('Ағылшын сөздері қазақшаға аударылады')
                : tr('Ағылшын сөздері орысшаға аударылады'),
            icon: PhosphorIconsFill.translate,
            selected: widget.lang == l.$1,
            onTap: () => widget.onLang(l.$1)),
          const SizedBox(height: 10),
        ],

        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: widget.onHaveAccount,
            child: Text(tr('Менде аккаунт бар — кіру'))),
        ),
      ],
    );
  }
}

// ── Step 2: level ──────────────────────────────────────────

class _StepLevel extends StatelessWidget {
  final String selected;
  final bool fromTest;
  final ValueChanged<String> onPick;
  final VoidCallback onTest;

  const _StepLevel({
    required this.selected, required this.fromTest,
    required this.onPick, required this.onTest});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return ListView(
      children: [
        SqEyebrow(tr('2-қадам')),
        const SizedBox(height: 7),
        Text(tr('Ағылшын деңгейің қандай?'),
          style: TextStyle(
            fontSize: 26, height: 1.2, fontWeight: FontWeight.w800,
            letterSpacing: -0.8, color: AppColors.text(d))),
        const SizedBox(height: 8),
        Text(tr('Дұрыс деңгей — дұрыс сөздер.'),
          style: TextStyle(
            fontSize: 13, height: 1.5, fontWeight: FontWeight.w600,
            color: AppColors.text3(d))),
        const SizedBox(height: 18),

        SqInkCard(
          padding: const EdgeInsets.all(17),
          onTap: onTest,
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(15)),
                child: const Icon(PhosphorIconsFill.target,
                  size: 22, color: Colors.white),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Тест тапсырып анықтау'),
                      style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800,
                        color: Colors.white)),
                    Text(tr('8 сұрақ · 1 минут'),
                      style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: AppColors.onInk2)),
                  ],
                ),
              ),
              const Icon(PhosphorIconsBold.arrowRight,
                size: 16, color: Colors.white),
            ],
          ),
        ),
        if (fromTest) ...[
          const SizedBox(height: 10),
          SqPanel(
            radius: 18,
            padding: const EdgeInsets.all(14),
            fill: AppColors.soft(AppColors.green, d),
            border: AppColors.line(AppColors.green, d),
            child: Row(
              children: [
                const Icon(PhosphorIconsFill.checkCircle,
                  size: 19, color: AppColors.greenDeep),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    trp('Тест бойынша деңгейің: {level} · {title}',
                      {'level': selected, 'title': tr(cefrOf(selected).title)}),
                    style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800,
                      color: AppColors.greenInk)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),

        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 9),
          child: SqEyebrow(tr('Немесе өзің таңда'))),
        for (final l in kCefrLevels) ...[
          _Choice(
            title: '${tr(l.title)} · ${l.code}',
            subtitle: tr(l.subtitle),
            icon: PhosphorIconsFill.chartBar,
            tint: AppColors.tiers[cefrIndex(l.code).clamp(0, 4)],
            selected: l.code == selected,
            onTap: () => onPick(l.code)),
          const SizedBox(height: 9),
        ],
      ],
    );
  }
}

// ── Step 3: daily goal ─────────────────────────────────────

class _StepGoal extends StatelessWidget {
  final int goal;
  final String lang, level;
  final ValueChanged<int> onPick;

  const _StepGoal({
    required this.goal, required this.lang,
    required this.level, required this.onPick});

  static const _options = [
    (10, 'Жеңіл', '10 сөз / күн', '≈ 3 мин'),
    (30, 'Тұрақты', '30 сөз / күн', '≈ 8 мин'),
    (60, 'Күшті', '60 сөз / күн', '≈ 15 мин'),
  ];

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return ListView(
      children: [
        SqEyebrow(tr('Соңғы қадам')),
        const SizedBox(height: 7),
        Text(tr('Күндік мақсатыңды таңда'),
          style: TextStyle(
            fontSize: 26, height: 1.2, fontWeight: FontWeight.w800,
            letterSpacing: -0.8, color: AppColors.text(d))),
        const SizedBox(height: 8),
        Text(tr('Кішкене мақсат — үлкен серия.'),
          style: TextStyle(
            fontSize: 13, height: 1.5, fontWeight: FontWeight.w600,
            color: AppColors.text3(d))),
        const SizedBox(height: 20),

        for (final o in _options) ...[
          _Choice(
            title: tr(o.$2),
            subtitle: tr(o.$3),
            icon: o.$1 <= 10
                ? PhosphorIconsFill.plant
                : o.$1 <= 30 ? PhosphorIconsFill.fire
                             : PhosphorIconsFill.crownSimple,
            tint: o.$1 <= 10
                ? AppColors.green
                : o.$1 <= 30 ? AppColors.amber : AppColors.primary,
            trailing: tr(o.$4),
            selected: goal == o.$1,
            onTap: () => onPick(o.$1)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),

        SqPanel(
          radius: 20,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SqEyebrow(tr('Таңдауың')),
              const SizedBox(height: 11),
              _SummaryRow(tr('Ана тілім'),
                lang == 'ru' ? tr('Орысша') : tr('Қазақша')),
              const SizedBox(height: 8),
              _SummaryRow(tr('Деңгейім'),
                '$level · ${tr(cefrOf(level).title)}'),
              const SizedBox(height: 8),
              _SummaryRow(tr('Мақсатым'),
                trp('{n} сөз / күн', {'n': '$goal'})),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label, value;
  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Row(
      children: [
        const Icon(PhosphorIconsFill.checkCircle,
          size: 17, color: AppColors.green),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
            style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700,
              color: AppColors.text2(d))),
        ),
        Text(value,
          style: TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w800,
            color: AppColors.text(d))),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color? tint;
  final String? trailing;
  final bool selected;
  final VoidCallback onTap;

  const _Choice({
    required this.title, required this.subtitle, required this.icon,
    required this.selected, required this.onTap, this.tint, this.trailing});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final c = tint ?? AppColors.primary;
    return SqPanel(
      radius: 20,
      padding: const EdgeInsets.all(16),
      fill: selected ? AppColors.soft(AppColors.primary, d) : null,
      border: selected ? AppColors.primary : null,
      onTap: onTap,
      child: Row(
        children: [
          SqTintBox(icon, tint: c, size: 40, solid: selected),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: selected
                        ? AppColors.primaryDeep : AppColors.text(d))),
                const SizedBox(height: 1),
                Text(subtitle,
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppColors.text3(d))),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            SqNum(trailing!, size: 11.5, color: AppColors.text3(d)),
          ],
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(PhosphorIconsFill.checkCircle,
              size: 22, color: AppColors.primary),
          ],
        ],
      ),
    );
  }
}

// ── Placement test ─────────────────────────────────────────

class PlacementTestScreen extends StatefulWidget {
  const PlacementTestScreen({super.key});

  @override
  State<PlacementTestScreen> createState() => _PlacementTestScreenState();
}

class _PlacementTestScreenState extends State<PlacementTestScreen> {
  static const _bands = ['A0', 'A1', 'A2', 'A2', 'B1', 'B1', 'B2', 'C1'];

  final _rng = Random();
  late final List<_PlacementQ> _questions = _buildQuestions();

  int _index = 0;
  int _score = 0;
  int _answered = 0;
  String? _picked;
  bool _revealed = false;

  List<_PlacementQ> _buildQuestions() {
    final dict = LocalDictionary.instance;
    final out = <_PlacementQ>[];
    final used = <String>{};

    for (final band in _bands) {
      final pool =
          dict.byLevels([band]).where((e) => !used.contains(e.en)).toList();
      if (pool.isEmpty) continue;
      final target = pool[_rng.nextInt(pool.length)];
      used.add(target.en);

      final decoys = dict.entries
          .where((e) => e.kk != target.kk && e.en != target.en)
          .toList()..shuffle(_rng);
      if (decoys.length < 3) continue;

      final options = [target.kk, ...decoys.take(3).map((e) => e.kk)]
        ..shuffle(_rng);

      out.add(_PlacementQ(
        word: target.en, answer: target.kk, options: options));
    }
    return out;
  }

  void _answer(String choice) {
    if (_revealed) return;
    final q = _questions[_index];
    setState(() {
      _picked = choice;
      _revealed = true;
      _answered++;
      if (choice == q.answer) _score++;
    });

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (_index + 1 >= _questions.length) {
        Navigator.of(context).pop(_levelFromScore());
      } else {
        setState(() { _index++; _picked = null; _revealed = false; });
      }
    });
  }

  String _levelFromScore() {
    // Use the number of questions actually answered, not the full set —
    // an early submit via "Өткізу" must not count unanswered questions as
    // wrong and drag the placement level down.
    final total = _answered;
    if (total == 0) return 'A1';
    final ratio = _score / total;
    if (ratio >= 0.95) return 'C1';
    if (ratio >= 0.85) return 'B2';
    if (ratio >= 0.70) return 'B1';
    if (ratio >= 0.50) return 'A2';
    if (ratio >= 0.25) return 'A1';
    return 'A0';
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);

    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.bg(d),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: SqHeader(title: tr('Деңгей тесті'),
                  onBack: () => Navigator.of(context).pop())),
              const Spacer(),
              SqEmpty(
                icon: PhosphorIconsFill.warningCircle,
                title: tr('Тест жүктелмеді'),
                subtitle: tr('Деңгейді қолмен таңдай бер'),
                tint: AppColors.red,
                action: SizedBox(
                  width: 220,
                  child: SqAction(tr('Артқа'),
                    tone: SqTone.ghost,
                    onTap: () => Navigator.of(context).pop())),
              ),
              const Spacer(),
            ],
          ),
        ),
      );
    }

    final q = _questions[_index];

    return Scaffold(
      backgroundColor: AppColors.bg(d),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SqSquareButton(PhosphorIconsBold.x,
                    onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 11),
                  Expanded(
                    child: SqBeads(
                      total: _questions.length,
                      done: _index,
                      current: _index,
                      height: 7),
                  ),
                  const SizedBox(width: 11),
                  SqNum('${_index + 1}/${_questions.length}',
                    size: 11.5, color: AppColors.text3(d)),
                ],
              ),
              const SizedBox(height: 20),

              SqInkCard(
                radius: 26,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 26),
                glowAt: Alignment.topLeft,
                child: Column(
                  children: [
                    Text(tr('Бұл сөз қазақша қалай?'),
                      style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700,
                        color: AppColors.onInk2)),
                    const SizedBox(height: 12),
                    Text(q.word,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 34, height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1, color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < q.options.length; i++) ...[
                      SqAnswer(
                        text: q.options[i],
                        badge: String.fromCharCode(65 + i),
                        revealed: _revealed,
                        isCorrect: q.options[i] == q.answer,
                        isPicked: q.options[i] == _picked,
                        onTap: () => _answer(q.options[i])),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),

              TextButton(
                onPressed: () => Navigator.of(context).pop(_levelFromScore()),
                child: Text(tr('Өткізу'))),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlacementQ {
  final String word, answer;
  final List<String> options;
  const _PlacementQ({
    required this.word, required this.answer, required this.options});
}
