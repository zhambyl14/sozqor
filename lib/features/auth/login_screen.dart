// lib/features/auth/login_screen.dart
//
// Sign in with phone + password. Registration never asks the learner to type
// their number: it comes back verified from the Telegram bot, which is free
// and needs no SMS provider.
//
// The screen only appears when someone asks for it — the app's default state
// is a guest session — so "Тіркелмей-ақ ойнау" is always the way back out.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/phone_auth_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import 'telegram_verify_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  /// Shown above the form when the gate had something to say — for example
  /// that a guest session could not be opened.
  final String? notice;

  /// Overrides what "Тіркелмей-ақ ойнау" does. The gate supplies this after a
  /// session it could not recover, where continuing as a guest means starting
  /// a brand-new empty account rather than returning to the existing one —
  /// something only the gate knows, and only it can do safely.
  final Future<void> Function()? onContinueAsGuest;

  const LoginScreen({super.key, this.notice, this.onContinueAsGuest});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form  = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _pwd   = TextEditingController();
  final _name  = TextEditingController();
  final _repo  = PhoneAuthRepo();

  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _phone.dispose(); _pwd.dispose(); _name.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _repo.signIn(phone: _phone.text, password: _pwd.text);
    } catch (e) {
      if (mounted) {
        final msg = humanError(e);
        if (msg.contains(tr('дұрыс емес'))) {
          setState(() => _error = tr('Нөмір немесе құпия сөз дұрыс емес'));
          // A wrong-credentials error is ambiguous — the phone may simply
          // never have been registered. Check only now, after the sign-in
          // attempt already failed, so a normal sign-in never pays for it.
          try {
            final exists = await _repo.phoneExists(_phone.text);
            if (mounted && !exists) {
              setState(() => _error = tr(
                  'Бұл нөмір тіркелмеген. «Тіркелу» бөліміне өт.'));
            }
          } catch (_) {
            // lookup itself failed — keep the generic message
          }
        } else {
          setState(() => _error = msg);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Telegram proves the number, so registration never needs an SMS provider.
  Future<void> _startRegister() async {
    if (!_form.currentState!.validate()) return;

    final verified = await verifyWithTelegram(context);
    if (verified == null || !mounted) return;

    setState(() { _busy = true; _error = null; });
    try {
      await _repo.register(
        code: verified.code,
        password: _pwd.text,
        displayName: _name.text.trim(),
      );
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final verified = await verifyWithTelegram(context, purpose: 'reset');
    if (verified == null || !mounted) return;

    final newPwd = await showDialog<String>(
      context: context,
      builder: (ctx) => _NewPasswordDialog(
        phone: PhoneAuthRepo.pretty(verified.phone)),
    );
    if (newPwd == null || !mounted) return;

    setState(() { _busy = true; _error = null; });
    try {
      await _repo.resetPassword(code: verified.code, password: newPwd);
      if (mounted) sqSnack(context, tr('Құпия сөз жаңартылды'));
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The app's default state is "guest", so this normally just hands control
  /// back to the gate, which opens the session. After an unrecoverable
  /// session the gate passes its own handler instead, because continuing
  /// there means abandoning an account that still exists — so it confirms
  /// first rather than letting one tap quietly strand it.
  Future<void> _guest() async {
    final startFresh = widget.onContinueAsGuest;
    if (startFresh == null) {
      ref.read(showLoginProvider.notifier).state = false;
      return;
    }
    final ok = await sqConfirm(context,
      title: tr('Жаңа қонақ ретінде бастау'),
      message: tr('Ескі аккаунтыңдағы сөздер мен XP сақтаулы тұр, бірақ оған '
                  'тек қайта кіргенде ғана қайта қосыласың. Жаңадан бастасаң, '
                  'бос аккаунт ашылады.'),
      confirm: tr('Жаңадан бастау'),
      cancel: tr('Болдырмау'));
    if (!ok) return;
    await startFresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);

    return Scaffold(
      backgroundColor: AppColors.bg(d),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 74, height: 74,
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            const BoxShadow(
                              color: AppColors.inkLip,
                              offset: Offset(0, 5), blurRadius: 0),
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.32),
                              blurRadius: 26, offset: const Offset(0, 14)),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const SqNum('SQ',
                          size: 26, color: Colors.white, letterSpacing: -0.8),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(_register ? S.joinUs : S.welcomeBack,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800,
                        letterSpacing: -0.7, color: AppColors.text(d))),
                    const SizedBox(height: 6),
                    Text(S.slogan,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppColors.text3(d))),
                    const SizedBox(height: 24),

                    if (widget.notice != null) ...[
                      _Notice(widget.notice!, AppColors.amber,
                        PhosphorIconsFill.info),
                      const SizedBox(height: 16),
                    ],

                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: tr('Атың'),
                          prefixIcon: const Icon(PhosphorIconsBold.user, size: 18)),
                        validator: (v) => (v == null || v.trim().length < 2)
                            ? tr('Атыңды жаз') : null,
                      ),
                      const SizedBox(height: 11),
                    ] else ...[
                      PhoneField(controller: _phone),
                      const SizedBox(height: 11),
                    ],

                    TextFormField(
                      controller: _pwd,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        hintText: tr('Құпия сөз'),
                        prefixIcon:
                            const Icon(PhosphorIconsBold.lock, size: 18),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? PhosphorIconsBold.eyeSlash
                              : PhosphorIconsBold.eye, size: 18),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v ?? '').length < 6 ? tr('Кемінде 6 таңба') : null,
                    ),

                    if (!_register)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _forgot,
                          child: Text(tr('Құпия сөзді ұмыттың ба?')),
                        ),
                      ),

                    if (_register) ...[
                      const SizedBox(height: 12),
                      _Notice(
                        tr('Telegram растайды — SMS те, нөмір теру де қажет емес.'),
                        AppColors.sky, PhosphorIconsFill.paperPlaneTilt),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _Notice(_error!, AppColors.red,
                        PhosphorIconsFill.warningCircle),
                    ],

                    const SizedBox(height: 16),
                    SqAction(
                      _register ? tr('Telegram арқылы тіркелу') : tr('Кіру'),
                      icon: _register
                          ? PhosphorIconsFill.paperPlaneTilt
                          : PhosphorIconsBold.signIn,
                      busy: _busy,
                      onTap: _register ? _startRegister : _signIn),

                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_register ? tr('Аккаунт бар ма?') : tr('Аккаунт жоқ па?'),
                          style: TextStyle(
                            color: AppColors.text3(d), fontSize: 13,
                            fontWeight: FontWeight.w600)),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _register = !_register;
                                  _error = null;
                                }),
                          child: Text(_register ? tr('Кіру') : tr('Тіркелу')),
                        ),
                      ],
                    ),

                    const SizedBox(height: 2),
                    SqAction(tr('Тіркелмей-ақ ойнау'),
                      icon: PhosphorIconsFill.gameController,
                      tone: SqTone.ghost,
                      height: 50,
                      onTap: _busy ? null : _guest),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final Color tint;
  final IconData icon;
  const _Notice(this.text, this.tint, this.icon);

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.soft(tint, d),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line(tint, d)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
              style: TextStyle(
                fontSize: 12, height: 1.45, fontWeight: FontWeight.w600,
                color: AppColors.onSoft(tint, d))),
          ),
        ],
      ),
    );
  }
}

class _NewPasswordDialog extends StatefulWidget {
  final String phone;
  const _NewPasswordDialog({required this.phone});

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
        SqNum(widget.phone, size: 13, color: AppColors.primary),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          autofocus: true,
          obscureText: _obscure,
          decoration: InputDecoration(
            hintText: tr('Құпия сөз'),
            errorText: _error,
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? PhosphorIconsBold.eyeSlash
                  : PhosphorIconsBold.eye, size: 18),
              onPressed: () => setState(() => _obscure = !_obscure)),
          ),
        ),
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
        child: Text(tr('Сақтау'))),
    ],
  );
}
