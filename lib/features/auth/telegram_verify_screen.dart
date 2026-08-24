// lib/features/auth/telegram_verify_screen.dart
//
// Phone verification without SMS: the learner taps through to the SozQor
// Telegram bot, shares their number, and comes back. The screen polls until
// the bot reports the number as verified.
//
// This is the whole reason registration is free to run — no SMS provider, no
// per-message cost, and nobody has to type their own number.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/phone_auth_repo.dart';
import '../../data/supa.dart';
import '../../core/i18n/l10n.dart';

/// Result handed back to whoever asked for verification.
class VerifiedPhone {
  final String code, phone;
  const VerifiedPhone({required this.code, required this.phone});
}

/// Opens the flow and resolves once the bot has confirmed a number.
Future<VerifiedPhone?> verifyWithTelegram(
  BuildContext context, {
  String purpose = 'signup',
}) =>
    Navigator.of(context).push<VerifiedPhone>(MaterialPageRoute(
      builder: (_) => TelegramVerifyScreen(purpose: purpose),
      fullscreenDialog: true,
    ));

class TelegramVerifyScreen extends ConsumerStatefulWidget {
  final String purpose;
  const TelegramVerifyScreen({super.key, this.purpose = 'signup'});

  @override
  ConsumerState<TelegramVerifyScreen> createState() =>
      _TelegramVerifyScreenState();
}

class _TelegramVerifyScreenState extends ConsumerState<TelegramVerifyScreen> {
  final _repo = PhoneAuthRepo();

  Timer? _poll;
  Timer? _clock;
  VerifyRequest? _request;
  int _secondsLeft = 900;
  bool _starting = true;
  bool _opened = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() { _starting = true; _error = null; });
    try {
      final req = await _repo.startVerification(purpose: widget.purpose);
      if (!mounted) return;
      setState(() { _request = req; _starting = false; });
      _beginPolling();
      _beginClock();
    } catch (e) {
      if (mounted) {
        setState(() { _starting = false; _error = humanError(e); });
      }
    }
  }

  void _beginClock() {
    _clock?.cancel();
    _secondsLeft = 900;
    _clock = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _poll?.cancel();
        setState(() => _error = tr('Уақыт бітті. Қайта баста.'));
      }
    });
  }

  void _beginPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (t) async {
      final code = _request?.code;
      if (!mounted || code == null) { t.cancel(); return; }
      try {
        final (status, phone) = await _repo.checkStatus(code);
        if (!mounted) return;
        if (status == VerifyStatus.verified && (phone ?? '').isNotEmpty) {
          t.cancel();
          _clock?.cancel();
          HapticFeedback.heavyImpact();
          Navigator.of(context)
              .pop(VerifiedPhone(code: code, phone: phone!));
        } else if (status == VerifyStatus.expired) {
          t.cancel();
          _clock?.cancel();
          setState(() => _error = tr('Мерзімі өтті. Қайта баста.'));
        }
      } catch (_) {
        // transient network hiccup — keep polling
      }
    });
  }

  Future<void> _openTelegram() async {
    final link = _request?.deepLink;
    if (link == null) {
      setState(() => _error =
          tr('Telegram боты әлі бапталмаған. Кейінірек көр.'));
      return;
    }
    final uri = Uri.parse(link);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (ok) {
      setState(() => _opened = true);
    } else {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        sqSnack(context,
          tr('Telegram ашылмады — сілтеме көшірілді'), error: true);
      }
    }
  }

  String get _timeLabel {
    final m = (_secondsLeft ~/ 60).clamp(0, 99);
    final s = (_secondsLeft % 60).clamp(0, 59);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);

    return Scaffold(
      backgroundColor: AppColors.bg(d),
      body: SafeArea(
        child: _starting
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                children: [
                  SqHeader(
                    title: tr('Нөмірді растау'),
                    eyebrow: tr('SMS қажет емес'),
                    backIcon: PhosphorIconsBold.x,
                    onBack: () => Navigator.of(context).pop()),
                  const SizedBox(height: 22),

                  SqRise(
                    child: Center(
                      child: SqFloat(
                        child: Container(
                          width: 88, height: 88,
                          decoration: BoxDecoration(
                            color: AppColors.sky,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              const BoxShadow(
                                color: AppColors.skyDeep,
                                offset: Offset(0, 6), blurRadius: 0),
                              BoxShadow(
                                color: AppColors.sky.withValues(alpha: 0.42),
                                blurRadius: 30, offset: const Offset(0, 16)),
                            ],
                          ),
                          child: const Icon(PhosphorIconsFill.paperPlaneTilt,
                            color: Colors.white, size: 40),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(tr('Telegram арқылы растау'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w800,
                      letterSpacing: -0.5, color: AppColors.text(d))),
                  const SizedBox(height: 8),
                  Text(tr('Ботқа нөміріңді бөліссең болғаны.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13, height: 1.5, fontWeight: FontWeight.w600,
                      color: AppColors.text3(d))),
                  const SizedBox(height: 22),

                  SqPanel(
                    child: Column(children: [
                      _Step(n: 1, text: tr('Түймені бас — Telegram ашылады')),
                      // EN-5 / KK-9: name the button, not the outcome. The
                      // bot opens Telegram's contact keyboard with exactly
                      // this label on it, so the learner is looking for a
                      // phrase they can actually see rather than working out
                      // what "share your number" is supposed to mean.
                      _Step(n: 2,
                        text: byLang(
                          kk: 'Ботта «Start» → төмендегі «📱 Нөмірмен бөлісу» '
                              'түймесін бас',
                          ru: 'В боте «Start» → нажми внизу кнопку '
                              '«📱 Поделиться контактом»')),
                      _Step(n: 3,
                        text: tr('Осы бетке орал'), last: true),
                    ]),
                  ),
                  if ((_request?.botUsername ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      trp('Түйме ашылмаса, Telegram-нан @{bot} деп тап',
                        {'bot': _request!.botUsername!}),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: AppColors.text3(d))),
                  ],
                  const SizedBox(height: 18),

                  if (_error != null) ...[
                    SqPanel(
                      radius: 18,
                      padding: const EdgeInsets.all(14),
                      fill: AppColors.soft(AppColors.red, d),
                      border: AppColors.line(AppColors.red, d),
                      child: Row(
                        children: [
                          const Icon(PhosphorIconsFill.warningCircle,
                            size: 19, color: AppColors.red),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(_error!,
                              style: TextStyle(
                                fontSize: 12.5, height: 1.4,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSoft(AppColors.red, d))),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SqAction(tr('Қайта бастау'),
                      icon: PhosphorIconsBold.arrowClockwise,
                      onTap: _start),
                  ] else ...[
                    SqAction(
                      _opened
                          ? tr('Telegram-ды қайта ашу')
                          : tr('Telegram-де растау'),
                      icon: PhosphorIconsBold.arrowSquareOut,
                      tone: SqTone.sky,
                      onTap: _openTelegram),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 15, height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Text(tr('Растауды күтудеміз · '),
                          style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700,
                            color: AppColors.text3(d))),
                        SqNum(_timeLabel,
                          size: 12.5, color: AppColors.text2(d)),
                      ],
                    ),
                  ],

                  const SizedBox(height: 22),
                  Text(tr('Нөмір басқа қолданушыларға көрсетілмейді.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11, height: 1.45, fontWeight: FontWeight.w600,
                      color: AppColors.text4(d))),
                ],
              ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  final bool last;
  const _Step({required this.n, required this.text, this.last = false});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: AppColors.sky,
              borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: SqNum('$n', size: 11.5, color: Colors.white),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(text,
              style: TextStyle(
                fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w600,
                color: AppColors.text2(d))),
          ),
        ],
      ),
    );
  }
}

/// Shared phone field so every screen formats numbers the same way.
class PhoneField extends StatefulWidget {
  final TextEditingController controller;
  final String? hint;
  final bool enabled;
  const PhoneField({
    super.key, required this.controller, this.hint, this.enabled = true});

  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<PhoneField> {
  /// Every account here is a Kazakh number, so the country code is a constant
  /// the learner should never have to type.
  ///
  /// It sits in the field's TEXT rather than in the decoration on purpose:
  /// PhoneAuthRepo.normalize reads the digits straight off the controller, so
  /// a decorative prefix would be invisible to it and every number would be
  /// registered one digit short — a different account than the one typed.
  static const _prefix = '+7 ';

  @override
  void initState() {
    super.initState();
    if (PhoneAuthRepo.normalize(widget.controller.text).isEmpty) {
      widget.controller.value = const TextEditingValue(
        text: _prefix,
        selection: TextSelection.collapsed(offset: _prefix.length),
      );
    }
    widget.controller.addListener(_keepPrefix);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_keepPrefix);
    super.dispose();
  }

  /// Backspacing through the country code leaves a number that still looks
  /// complete but resolves to a different account, so the prefix goes back.
  void _keepPrefix() {
    if (widget.controller.text.startsWith(_prefix)) return;
    var digits = PhoneAuthRepo.normalize(widget.controller.text);
    // A pasted or dictated number usually carries its own 7 or 8 in front.
    // Only strip it when there are more digits than a local number has,
    // otherwise a real subscriber number starting with 7 loses its first one.
    if (digits.length > 10 &&
        (digits.startsWith('7') || digits.startsWith('8'))) {
      digits = digits.substring(1);
    }
    final text = _prefix + digits;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    enabled: widget.enabled,
    keyboardType: TextInputType.phone,
    autofillHints: const [AutofillHints.telephoneNumber],
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s()-]')),
      LengthLimitingTextInputFormatter(20),
    ],
    decoration: InputDecoration(
      hintText: widget.hint ?? '+7 700 123 45 67',
      prefixIcon: const Icon(PhosphorIconsBold.phone, size: 18)),
    validator: (v) {
      final t = (v ?? '').trim();
      // The field is seeded with the country code, so "nothing entered" is a
      // lone "+7" rather than a zero-length string.
      if (t.isEmpty || PhoneAuthRepo.normalize(t).length <= 1) {
        return tr('Бұл өріс міндетті');
      }
      if (!PhoneAuthRepo.looksValid(t)) return tr('Нөмір толық емес');
      return null;
    },
  );
}
