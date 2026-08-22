// lib/features/profile/account_screen.dart
//
// The account itself: the name others see, the number the app signs in with,
// and the password.
//
// The name is an ordinary setting and saves on the spot. The other two are
// the login, so neither moves on a tap alone — both go back through the same
// Telegram bot that proved the number when the account was made. And because
// the number IS the login, the screen says what changing it costs before it
// asks Telegram, not after.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/account_repo.dart';
import '../../data/repos/phone_auth_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../auth/guest_gate.dart';
import '../auth/telegram_verify_screen.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _repo = AccountRepo();
  bool _busy = false;

  /// One busy flag, one error surface, one profile refresh — so every row
  /// below shows its new value the moment the change lands.
  Future<void> _run(Future<void> Function() change, String done) async {
    setState(() => _busy = true);
    try {
      await change();
      ref.invalidate(myProfileProvider);
      if (mounted) sqSnack(context, done);
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(
      text: ref.read(myProfileProvider).valueOrNull?.displayName ?? '');
    // Built per call rather than held as a field, so it has to be released
    // per call too — otherwise every visit to the rename dialog leaks one.
    try {
      await _askName(ctrl);
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _askName(TextEditingController ctrl) async {
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
    if (value == null || value.length < 2 || !mounted) return;
    await _run(() => ref.read(profileRepoProvider).setDisplayName(value),
      tr('Есім жаңартылды'));
  }

  /// The new password is asked for before the verification, not after: a
  /// cancelled dialog then costs nothing, while a spent code costs another
  /// trip through Telegram.
  Future<void> _changePassword() async {
    final phone = ref.read(myProfileProvider).valueOrNull?.phone ?? '';
    if (phone.isEmpty) return;

    final pwd = await showDialog<String>(
      context: context, builder: (_) => const _NewPasswordDialog());
    if (pwd == null || !mounted) return;

    final verified = await verifyWithTelegram(context, purpose: 'reset');
    if (verified == null || !mounted) return;

    await _run(() => _repo.changePassword(
      code: verified.code,
      verifiedPhone: verified.phone,
      accountPhone: phone,
      password: pwd), tr('Құпия сөз жаңартылды'));
  }

  Future<void> _changePhone() async {
    final p = ref.read(myProfileProvider).valueOrNull;
    final current = p?.phone ?? '';

    final input = await showDialog<(String, String)>(
      context: context, builder: (_) => _NewPhoneDialog(current: current));
    if (input == null || !mounted) return;
    final (phone, password) = input;

    if (PhoneAuthRepo.normalize(phone) == PhoneAuthRepo.normalize(current)) {
      sqSnack(context, tr('Бұл нөмір қазірдің өзінде сенікі'), error: true);
      return;
    }

    // Both questions are cheap and both are fatal to the change, so they are
    // settled here rather than after a pointless walk through Telegram.
    setState(() => _busy = true);
    String? stop;
    try {
      if (await _repo.phoneTaken(phone)) {
        stop = tr('Бұл нөмір басқа аккаунтқа тіркелген');
      } else if (!await _repo.passwordMatches(password)) {
        stop = tr('Құпия сөз дұрыс емес');
      }
    } catch (e) {
      stop = humanError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (stop != null) {
      sqSnack(context, stop, error: true);
      return;
    }

    final ok = await sqConfirm(context,
      title: tr('Кіру нөмірін өзгерту'),
      message: trp(
        'Бұдан кейін аккаунтқа {phone} нөмірімен кіресің. Ескі нөмір жарамайды.',
        {'phone': PhoneAuthRepo.pretty(phone)}),
      confirm: tr('Өзгерту'),
      cancel: tr('Болдырмау'));
    if (!ok || !mounted) return;

    final verified = await verifyWithTelegram(context);
    if (verified == null || !mounted) return;

    await _run(() => _repo.changePhone(
      code: verified.code,
      verifiedPhone: verified.phone,
      intendedPhone: phone,
      password: password,
      displayName: p?.displayName ?? ''), tr('Кіру нөмірі жаңартылды'));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final p = ref.watch(myProfileProvider).valueOrNull;
    final phone = p?.phone ?? '';
    final hasPhone = phone.isNotEmpty;
    final name = (p?.displayName ?? '').trim();

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: tr('Аккаунт'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        // A guest has no login to edit — every field here would be dead — so
        // the whole screen becomes the one thing they can actually do.
        if (p?.isGuest ?? false) ...[
          SqPanel(
            radius: 20,
            padding: const EdgeInsets.all(18),
            fill: AppColors.soft(AppColors.amber, d),
            border: AppColors.line(AppColors.amber, d),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SqTintBox(PhosphorIconsFill.shieldCheck,
                  tint: AppColors.amber, size: 44, solid: true),
                const SizedBox(height: 13),
                Text(tr('Қонақ режимі'),
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: AppColors.text(d))),
                const SizedBox(height: 5),
                Text(tr('Нөмір мен құпия сөз тіркелген аккаунтта ғана болады.'),
                  style: TextStyle(
                    fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w600,
                    color: AppColors.onSoft(AppColors.amber, d))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SqAction(tr('Тіркелу'),
            icon: PhosphorIconsFill.paperPlaneTilt,
            onTap: _busy ? null : () async {
              final claimed =
                  await showClaimSheet(context, GuestFeature.saveWord);
              if (claimed == true) ref.invalidate(myProfileProvider);
            }),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => signInToExistingAccount(context, ref),
              child: Text(tr('Менде аккаунт бар — кіру'))),
          ),
        ] else ...[
          SqGroup(children: [
            SqTile(
              leading: const SqTintBox(PhosphorIconsFill.userCircle, size: 34),
              title: tr('Есім'),
              trailing: _Value(name.isEmpty ? '—' : name),
              chevron: true,
              onTap: _busy ? null : _editName),
          ]),
          const SizedBox(height: 18),

          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 9),
            child: SqEyebrow(tr('Кіру деректері'))),
          SqGroup(children: [
            SqTile(
              leading: const SqTintBox(PhosphorIconsFill.phone,
                tint: AppColors.green, size: 34),
              title: tr('Телефон'),
              subtitle: hasPhone ? null : tr('Нөмір тіркелмеген'),
              trailing: _Value(hasPhone ? PhoneAuthRepo.pretty(phone) : '—'),
              chevron: true,
              onTap: _busy ? null : _changePhone),
            SqTile(
              leading: const SqTintBox(PhosphorIconsFill.lock,
                tint: AppColors.sky, size: 34),
              title: tr('Құпия сөз'),
              // Without a number there is nothing for the bot to verify
              // against, so the row says what to do first instead of failing
              // halfway through.
              subtitle: hasPhone ? null : tr('Алдымен нөміріңді қос'),
              trailing: const _Value('••••••'),
              chevron: hasPhone,
              onTap: (_busy || !hasPhone) ? null : _changePassword),
          ]),
          const SizedBox(height: 11),
          Text(
            tr('Нөмір — кіру деректерің. Оны өзгертсең, келесі жолы жаңа '
               'нөміріңмен кіресің. Екеуін де Telegram растайды.'),
            style: TextStyle(
              fontSize: 11.5, height: 1.5, fontWeight: FontWeight.w600,
              color: AppColors.text3(d))),
        ],
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

class _NewPasswordDialog extends StatefulWidget {
  const _NewPasswordDialog();

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Жаңа құпия сөз')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          obscureText: _obscure,
          decoration: InputDecoration(
            hintText: tr('Құпия сөз'),
            errorText: _error,
            prefixIcon: const Icon(PhosphorIconsBold.lock, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? PhosphorIconsBold.eyeSlash
                  : PhosphorIconsBold.eye, size: 18),
              onPressed: () => setState(() => _obscure = !_obscure)),
          ),
        ),
        const SizedBox(height: 10),
        Text(tr('Растау үшін Telegram ашылады'),
          style: TextStyle(
            fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w600,
            color: AppColors.text3(isDark(context)))),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(tr('Болдырмау'))),
      TextButton(
        onPressed: () {
          if (_ctrl.text.length < 6) {
            setState(() => _error = tr('Кемінде 6 таңба'));
            return;
          }
          Navigator.of(context).pop(_ctrl.text);
        },
        child: Text(tr('Жалғастыру'))),
    ],
  );
}

/// Asks for the number to move to and for the password that already opens
/// this account.
///
/// The password is not decoration: the server call that re-keys the login
/// writes it back, so it has to be the real one — and asking for it is also
/// what stops a borrowed unlocked phone from walking off with the account.
class _NewPhoneDialog extends StatefulWidget {
  final String current;
  const _NewPhoneDialog({required this.current});

  @override
  State<_NewPhoneDialog> createState() => _NewPhoneDialogState();
}

class _NewPhoneDialogState extends State<_NewPhoneDialog> {
  final _form  = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _pwd   = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _phone.dispose(); _pwd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return AlertDialog(
      title: Text(widget.current.isEmpty
          ? tr('Нөмір қосу')
          : tr('Кіру нөмірін өзгерту')),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.current.isNotEmpty) ...[
              SqEyebrow(tr('Қазіргі нөмір')),
              const SizedBox(height: 3),
              SqNum(PhoneAuthRepo.pretty(widget.current),
                size: 13, color: AppColors.primary),
              const SizedBox(height: 14),
            ],
            PhoneField(controller: _phone),
            const SizedBox(height: 11),
            TextFormField(
              controller: _pwd,
              obscureText: _obscure,
              decoration: InputDecoration(
                hintText: tr('Қазіргі құпия сөз'),
                prefixIcon: const Icon(PhosphorIconsBold.lock, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? PhosphorIconsBold.eyeSlash
                      : PhosphorIconsBold.eye, size: 18),
                  onPressed: () => setState(() => _obscure = !_obscure)),
              ),
              validator: (v) =>
                  (v ?? '').length < 6 ? tr('Кемінде 6 таңба') : null,
            ),
            const SizedBox(height: 12),
            Text(
              tr('Жаңа нөмірді Telegram растайды — сол нөмір Telegram '
                 'аккаунтыңда болуы керек.'),
              style: TextStyle(
                fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w600,
                color: AppColors.text3(d))),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Болдырмау'))),
        TextButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.of(context).pop((_phone.text, _pwd.text));
          },
          child: Text(tr('Жалғастыру'))),
      ],
    );
  }
}
