// lib/features/profile/settings_screen.dart
//
// Settings, grouped by what a row actually changes: study, notifications,
// account. Every row is one decision with its current value on the right, so
// the screen can be read without opening anything.
//
// Interface language and study language are two settings, not one — but
// changing the interface also resets the study language to match, so the
// common case (both in the same language) never needs two taps. Picking a
// different study language right after is still one tap away, on the row
// below, and that later choice is what sticks.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/constants/build_info.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/phone_auth_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/meta_store.dart';
import '../../services/push_service.dart';
import '../auth/guest_gate.dart';
import '../../data/repos/moderator_repo.dart';
import '../moderator/moderator_screen.dart';
import 'account_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  /// Mirrors of what PushService has stored, so the rows can be drawn without
  /// awaiting anything on every frame.
  bool _reminderOn = false;
  int _reminderHour = PushService.defaultHour;
  int _reminderMinute = PushService.defaultMinute;

  @override
  void initState() {
    super.initState();
    _loadReminder();
  }

  Future<void> _loadReminder() async {
    final on = await PushService.instance.reminderOn();
    final at = await PushService.instance.reminderTime();
    if (!mounted) return;
    setState(() {
      _reminderOn = on;
      _reminderHour = at.hour;
      _reminderMinute = at.minute;
    });
  }

  static String _clock(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  /// Turning the reminder on asks for permission first — a switch that flips
  /// back on its own is worse than one that never moved.
  Future<void> _setReminder(bool want) async {
    if (!want) {
      await PushService.instance.cancelDailyReminder();
      if (mounted) setState(() => _reminderOn = false);
      return;
    }

    if (!PushService.instance.supportsLocal) {
      if (mounted) {
        sqSnack(context,
          tr('Браузерде күнделікті еске салу жоқ — қосымшаны телефонға орнат.'),
          error: true);
      }
      return;
    }

    setState(() => _busy = true);
    final granted = await PushService.instance.requestPermission();
    if (!granted) {
      if (mounted) {
        setState(() => _busy = false);
        sqSnack(context,
          tr('Хабарламаға рұқсат берілмеді. Телефон баптауынан қосасың.'),
          error: true);
      }
      return;
    }

    final ok = await PushService.instance.scheduleDailyReminder(
      hour: _reminderHour, minute: _reminderMinute);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _reminderOn = ok;
    });
    if (ok) {
      sqSnack(context, trp('Күн сайын {time} — еске саламыз',
        {'time': _clock(_reminderHour, _reminderMinute)}));
    }
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _reminderHour = picked.hour;
      _reminderMinute = picked.minute;
    });
    final ok = await PushService.instance.scheduleDailyReminder(
      hour: picked.hour, minute: picked.minute);
    if (!mounted) return;
    if (ok) {
      sqSnack(context, trp('Күн сайын {time} — еске саламыз',
        {'time': _clock(picked.hour, picked.minute)}));
    }
  }

  Future<void> _testNotification() async {
    final granted = await PushService.instance.permissionGranted()
        ? true
        : await PushService.instance.requestPermission();
    if (!granted) {
      if (mounted) {
        sqSnack(context,
          tr('Хабарламаға рұқсат берілмеді. Телефон баптауынан қосасың.'),
          error: true);
      }
      return;
    }
    final ok = await PushService.instance.sendTestNotification();
    if (!mounted) return;
    sqSnack(context,
      ok ? tr('Жіберілді — экранның жоғарысын қара')
         : tr('Хабарлама жіберілмеді'),
      error: !ok);
  }

  Future<void> _patch(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(myProfileProvider);
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<T?> _sheet<T>(String title, List<Widget> children) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SqSheetGrip(),
                Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800,
                    color: AppColors.text(isDark(context)))),
                const SizedBox(height: 18),
                ...children,
              ],
            ),
          ),
        ),
      );

  Future<void> _editName() async {
    final profile = ref.read(myProfileProvider).value;
    final ctrl = TextEditingController(text: profile?.displayName ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Атыңды өзгерту')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: tr('Атың'))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('Болдырмау'))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(tr('Сақтау'))),
        ],
      ),
    );
    if (value != null && value.length >= 2) {
      await _patch(() => ref.read(profileRepoProvider).setDisplayName(value));
    }
  }

  Future<void> _editUsername() async {
    final profile = ref.read(myProfileProvider).value;
    final ctrl = TextEditingController(text: profile?.username ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Логинді өзгерту')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('Логин'))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('Болдырмау'))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(tr('Сақтау'))),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) {
      await _patch(() => ref.read(profileRepoProvider).setUsername(value));
    }
  }

  Future<void> _pickFrame() async {
    final meta = ref.read(metaProvider);
    final owned = [
      '',
      ...kShopItems.where((i) => i.id.startsWith('frame_') && meta.owns(i.id))
          .map((i) => i.id),
    ];
    final chosen = await _sheet<String>(tr('Аватар жиегі'), [
      for (final id in owned)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: SqPanel(
            radius: 18,
            padding: const EdgeInsets.all(14),
            border: meta.frame == id ? AppColors.primaryEdge : null,
            onTap: () => Navigator.of(context).pop(id),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: ProfileScreen.frameColor(id),
                    shape: BoxShape.circle),
                  child: Container(
                    width: 32, height: 32,
                    decoration: const BoxDecoration(
                      color: AppColors.primary, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(child: Text(tr(ProfileScreen.frameName(id)),
                  style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800))),
                if (meta.frame == id)
                  const Icon(PhosphorIconsFill.checkCircle,
                    size: 20, color: AppColors.primary),
              ],
            ),
          ),
        ),
      if (owned.length == 1)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            tr('Жаңа жиектерді дүкеннен немесе миссия жолынан ашасың.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12, height: 1.5, fontWeight: FontWeight.w600,
              color: AppColors.text3(isDark(context)))),
        ),
    ]);
    if (chosen != null) {
      await ref.read(metaProvider.notifier).wearFrame(chosen);
    }
  }

  Future<void> _pickLevel() async {
    final current = ref.read(myProfileProvider).value?.cefrLevel ?? 'A1';
    final chosen = await _sheet<String>(tr('Деңгейді өзгерту'), [
      for (final l in kCefrLevels)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: SqPanel(
            radius: 18,
            padding: const EdgeInsets.all(15),
            border: l.code == current ? AppColors.primaryEdge : null,
            onTap: () => Navigator.of(context).pop(l.code),
            child: Row(
              children: [
                SqBadge(l.code,
                  tint: AppColors.tiers[cefrIndex(l.code).clamp(0, 4)],
                  size: 12),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr(l.title),
                        style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                      Text(tr(l.subtitle),
                        style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600,
                          color: AppColors.text3(isDark(context)))),
                    ],
                  ),
                ),
                if (l.code == current)
                  const Icon(PhosphorIconsFill.checkCircle,
                    size: 20, color: AppColors.primary),
              ],
            ),
          ),
        ),
    ]);
    if (chosen != null) {
      await _patch(() => ref.read(profileRepoProvider).setLevel(chosen));
      ref.invalidate(levelPoolProvider);
    }
  }

  Future<void> _pickGoal() async {
    final current = ref.read(myProfileProvider).value?.dailyGoal ?? 10;
    final chosen = await _sheet<int>(tr('Күнделікті мақсат'), [
      for (final g in [5, 10, 20, 30, 50])
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: SqPanel(
            radius: 18,
            padding: const EdgeInsets.all(15),
            border: g == current ? AppColors.primaryEdge : null,
            onTap: () => Navigator.of(context).pop(g),
            child: Row(
              children: [
                SqTintBox(
                  g <= 10
                      ? PhosphorIconsFill.plant
                      : g <= 30 ? PhosphorIconsFill.fire
                                : PhosphorIconsFill.crownSimple,
                  tint: g <= 10
                      ? AppColors.green
                      : g <= 30 ? AppColors.amber : AppColors.primary,
                  size: 36),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(trp('{n} сөз / күн', {'n': '$g'}),
                        style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                      Text(trp('≈ {m} минут', {'m': '${(g * 0.65).ceil()}'}),
                        style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600,
                          color: AppColors.text3(isDark(context)))),
                    ],
                  ),
                ),
                if (g == current)
                  const Icon(PhosphorIconsFill.checkCircle,
                    size: 20, color: AppColors.primary),
              ],
            ),
          ),
        ),
    ]);
    if (chosen != null) {
      await _patch(() => ref.read(profileRepoProvider).setDailyGoal(chosen));
    }
  }

  /// Interface language. The switch lands before the sheet closes, so the
  /// screen behind it is already in the new language.
  Future<void> _pickUiLang() async {
    final current = ref.read(langProvider);
    final chosen = await _sheet<String>(tr('Қосымша тілі'), [
      for (final code in AppLang.supported)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: SqPanel(
            radius: 18,
            padding: const EdgeInsets.all(15),
            border: code == current ? AppColors.primaryEdge : null,
            onTap: () => Navigator.of(context).pop(code),
            child: Row(
              children: [
                const SqTintBox(PhosphorIconsFill.globeHemisphereEast,
                  tint: AppColors.primary, size: 36),
                const SizedBox(width: 13),
                Expanded(child: Text(AppLang.names[code] ?? code,
                  style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800))),
                if (code == current)
                  const Icon(PhosphorIconsFill.checkCircle,
                    size: 20, color: AppColors.primary),
              ],
            ),
          ),
        ),
    ]);
    if (chosen == null || chosen == current) return;
    // Local first — the interface must never wait on the network to switch.
    await ref.read(langProvider.notifier).set(chosen);
    if (mounted) setState(() {});
    // Keeps the server-side push-token language in step, so a server job
    // sending a reminder picks the language the learner actually reads now.
    unawaited(PushService.instance.onLanguageChanged());
    try {
      await ref.read(profileRepoProvider).setUiLang(chosen);
      // The study language follows the interface by default — reading the
      // app in Russian while every new word is still translated to Kazakh is
      // what actually looked like "wrong-language content" to learners. A
      // deliberate change on the "Оқу тілі" row right below still wins, since
      // it always runs after this and simply overwrites it.
      await ref.read(profileRepoProvider).setNativeLang(chosen);
      ref.invalidate(myProfileProvider);
    } catch (_) {/* the choice is already saved on this device */}
  }

  Future<void> _pickLang() async {
    final current = ref.read(nativeLangProvider);
    final chosen = await _sheet<String>(tr('Оқу тілі'), [
      Text(tr('Ағылшын сөздері қай тілге аударылып көрсетіледі'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w600,
          color: AppColors.text3(isDark(context)))),
      const SizedBox(height: 16),
      for (final l in [('kk', tr('Қазақша')), ('ru', tr('Орысша'))])
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: SqPanel(
            radius: 18,
            padding: const EdgeInsets.all(15),
            border: l.$1 == current ? AppColors.primaryEdge : null,
            onTap: () => Navigator.of(context).pop(l.$1),
            child: Row(
              children: [
                const SqTintBox(PhosphorIconsFill.translate, size: 36),
                const SizedBox(width: 13),
                Expanded(child: Text(tr(l.$2),
                  style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800))),
                if (l.$1 == current)
                  const Icon(PhosphorIconsFill.checkCircle,
                    size: 20, color: AppColors.primary),
              ],
            ),
          ),
        ),
    ]);
    if (chosen != null) {
      await _patch(() => ref.read(profileRepoProvider).setNativeLang(chosen));
    }
  }

  /// Only ever shown to a signed-in account — a guest has nothing to "log
  /// out" of, so that path is [signInToExistingAccount] instead, worded for
  /// what it actually does.
  Future<void> _logout() async {
    final ok = await sqConfirm(context,
      title: tr('Шығу'),
      message: tr('Аккаунттан шығасың ба?'),
      confirm: tr('Шығу'));
    if (!ok) return;
    await PushService.instance.clearToken();
    // Signing out is a deliberate exit, so land on the sign-in screen rather
    // than silently opening a brand new guest session.
    ref.read(showLoginProvider.notifier).state = true;
    await ref.read(authRepoProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final lang = ref.watch(langProvider);
    final p = ref.watch(myProfileProvider).value;
    final meta = ref.watch(metaProvider);

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: tr('Баптаулар'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        if (p?.isGuest ?? false) ...[
          SqPanel(
            radius: 20,
            padding: const EdgeInsets.all(16),
            fill: AppColors.soft(AppColors.amber, d),
            border: AppColors.line(AppColors.amber, d),
            onTap: () async {
              final claimed =
                  await showClaimSheet(context, GuestFeature.saveWord);
              if (claimed == true) ref.invalidate(myProfileProvider);
            },
            child: Row(
              children: [
                const SqTintBox(PhosphorIconsFill.shieldCheck,
                  tint: AppColors.amber, size: 40, solid: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr('Аккаунтыңды сақтап қал'),
                        style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800,
                          color: AppColors.text(d))),
                      Text(tr('Тіркел — прогресің жоғалмайды'),
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
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => signInToExistingAccount(context, ref),
              child: Text(tr('Менде аккаунт бар — кіру'))),
          ),
          const SizedBox(height: 10),
        ],

        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 9),
          child: SqEyebrow(tr('Тіл'))),
        SqGroup(children: [
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.globeHemisphereEast,
              tint: AppColors.primary, size: 34),
            title: tr('Қосымша тілі'),
            trailing: _Value(AppLang.names[lang] ?? lang),
            chevron: true,
            onTap: _pickUiLang),
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.translate,
              tint: AppColors.green, size: 34),
            title: tr('Оқу тілі'),
            trailing: _Value(
              (p?.nativeLang ?? 'kk') == 'ru' ? tr('Орысша') : tr('Қазақша')),
            chevron: true,
            onTap: _busy ? null : _pickLang),
        ]),
        const SizedBox(height: 18),

        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 9),
          child: SqEyebrow(tr('Оқу'))),
        SqGroup(children: [
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.target,
              tint: AppColors.primary, size: 34),
            title: tr('Күнделікті мақсат'),
            trailing: _Value(trp('{n} сөз', {'n': '${p?.dailyGoal ?? 10}'})),
            chevron: true,
            onTap: _busy ? null : _pickGoal),
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.chartBar,
              tint: AppColors.sky, size: 34),
            title: tr('Деңгей'),
            trailing: _Value(
              '${p?.cefrLevel ?? 'A1'} · ${tr(cefrOf(p?.cefrLevel ?? 'A1').title)}'),
            chevron: true,
            onTap: _busy ? null : _pickLevel),
        ]),
        const SizedBox(height: 18),

        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 9),
          child: SqEyebrow(tr('Хабарлама'))),
        SqGroup(children: [
          _Toggle(
            icon: PhosphorIconsFill.bell,
            title: tr('Күнделікті еске салу'),
            value: _reminderOn,
            onChanged: _busy ? null : _setReminder),
          if (_reminderOn && PushService.instance.supportsLocal)
            SqTile(
              leading: const SqTintBox(PhosphorIconsFill.clock,
                tint: AppColors.sky, size: 34),
              title: tr('Еске салу уақыты'),
              trailing: _Value(_clock(_reminderHour, _reminderMinute)),
              chevron: true,
              onTap: _busy ? null : _pickReminderTime),
          _Toggle(
            icon: PhosphorIconsFill.megaphone,
            title: tr('Лига мен баттл хабарламалары'),
            value: p?.notifEnabled ?? true,
            onChanged: _busy ? null : (v) {
              _patch(() async {
                await ref.read(profileRepoProvider).setNotifs(v);
                if (v) {
                  await PushService.instance.requestPermission();
                } else {
                  await PushService.instance.clearToken();
                }
              });
            }),
          _Toggle(
            icon: PhosphorIconsFill.moonStars,
            title: tr('Түнгі тақырып'),
            value: p?.darkMode ?? false,
            onChanged: _busy ? null : (v) {
              ref.read(themeProvider.notifier).set(v);
              _patch(() => ref.read(profileRepoProvider).setDarkMode(v));
            }),
        ]),
        if (PushService.instance.supportsLocal) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _testNotification,
              child: Text(tr('Хабарламаны тексеріп көру'))),
          ),
        ],
        const SizedBox(height: 18),

        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 9),
          child: SqEyebrow(tr('Аккаунт'))),
        SqGroup(children: [
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.userCircle,
              tint: AppColors.primary, size: 34),
            title: tr('Есім'),
            trailing: _Value(p?.displayName.isNotEmpty == true
                ? p!.displayName : '—'),
            chevron: true,
            onTap: _busy ? null : _editName),
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.circleHalf,
              tint: AppColors.amber, size: 34),
            title: tr('Аватар жиегі'),
            trailing: _Value(tr(ProfileScreen.frameName(meta.frame))),
            chevron: true,
            onTap: _busy ? null : _pickFrame),
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.identificationCard,
              tint: AppColors.sky, size: 34),
            title: tr('Логин'),
            trailing: _Value('@${p?.username ?? ''}'),
            chevron: true,
            onTap: _busy ? null : _editUsername),
          // The phone used to be printed here and nothing more, which left no
          // way at all to change a number, a password or a name from inside
          // the app. AccountScreen handles the guest and no-number cases
          // itself, so this row is always offered.
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.lock,
              tint: AppColors.green, size: 34),
            title: tr('Кіру деректері'),
            subtitle: tr('Нөмір мен құпия сөз'),
            trailing: _Value((p?.phone ?? '').isEmpty
                ? '—' : PhoneAuthRepo.pretty(p!.phone!)),
            chevron: true,
            onTap: _busy ? null : () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountScreen()))),
        ]),

        // Only a moderator ever sees this. amModeratorProvider reads the role
        // off the server rather than trusting anything on the device, and the
        // RLS policies behind every write check it again — this entrance is a
        // convenience, not the security boundary.
        Consumer(
          builder: (_, ref, __) {
            final isMod = ref.watch(amModeratorProvider).value ?? false;
            if (!isMod) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 9),
                    child: SqEyebrow(tr('Модератор'))),
                  SqGroup(children: [
                    SqTile(
                      leading: const SqTintBox(PhosphorIconsFill.shieldCheck,
                        tint: AppColors.primary, size: 34),
                      title: tr('Басқару панелі'),
                      subtitle: tr('Ивент, турнир, дүкен'),
                      chevron: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ModeratorScreen()))),
                  ]),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 22),

        // A guest never logged into anything, so "Шығу" (log out) has
        // nothing true to say to them — their one way back to the sign-in
        // screen is "Менде аккаунт бар — кіру" at the top of this page,
        // worded for what it actually does.
        if (!(p?.isGuest ?? false)) ...[
          SqAction(tr('Шығу'),
            icon: PhosphorIconsBold.signOut,
            tone: SqTone.ghost,
            height: 50,
            onTap: _busy ? null : _logout),
          const SizedBox(height: 18),
        ],
        // The build stamp, not a hardcoded label. "Is my change in this app?"
        // has no answer from a phone otherwise: a stale service worker, a
        // second tab keeping the old worker alive, and an old bookmark all
        // look the same from the outside — the app opens and the new screens
        // are missing. Reading the commit here settles it in one glance.
        Center(
          child: SqNum('SozQor $buildLabel',
            size: 11.5, color: AppColors.text4(d))),
      ],
    );
  }
}

class _Value extends StatelessWidget {
  final String text;
  const _Value(this.text);

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 150),
    child: Text(text,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 12.5, fontWeight: FontWeight.w700,
        color: AppColors.text3(isDark(context)))),
  );
}

class _Toggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _Toggle({
    required this.icon, required this.title,
    required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) => SqTile(
    padding: const EdgeInsets.fromLTRB(15, 7, 12, 7),
    leading: SqTintBox(icon,
      tint: value ? AppColors.primary : AppColors.text4(isDark(context)),
      size: 34),
    title: title,
    trailing: Switch(value: value, onChanged: onChanged),
  );
}
