// lib/features/auth/guest_gate.dart
//
// Guests get the full solo experience. Anything competitive or social —
// saving words, the league, ranked battles, tournaments, the global daily
// challenge, friends, leaderboards — asks them to claim their account first.
//
// Claiming keeps the same user id, so every word, XP point and streak the
// guest earned carries straight over. The sheet says so with their real
// numbers in it, because "you will not lose anything" is only believable when
// it names what you have.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/phone_auth_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import 'telegram_verify_screen.dart';

/// What a guest just tried to do, used to word the prompt.
enum GuestFeature { saveWord, league, ranked, tournament, daily, friends, board }

extension GuestFeatureCopy on GuestFeature {
  String get title => switch (this) {
    GuestFeature.saveWord   => tr('Сөзді сақтау үшін тіркел'),
    GuestFeature.league     => tr('Лигаға қосылу үшін тіркел'),
    GuestFeature.ranked     => tr('Рейтингті баттл үшін тіркел'),
    GuestFeature.tournament => tr('Турнирге қатысу үшін тіркел'),
    GuestFeature.daily      => tr('Глобал сынақ үшін тіркел'),
    GuestFeature.friends    => tr('Дос қосу үшін тіркел'),
    GuestFeature.board      => tr('Тізімде көріну үшін тіркел'),
  };

  String get subtitle => switch (this) {
    GuestFeature.saveWord => tr('Тіркелсең — өз сөздігің сақталады.'),
    GuestFeature.league => tr('Апта сайын 30 адаммен жарысасың.'),
    GuestFeature.ranked =>
        tr('Нағыз қарсыласпен ойнап, Elo рейтинг жинайсың.'),
    GuestFeature.tournament => tr('24 сағаттық турнирге қосыласың.'),
    GuestFeature.daily => tr('Бүкіл әлеммен бір жиынтық ойнайсың.'),
    GuestFeature.friends => tr('Достарыңды баттлға шақырасың.'),
    GuestFeature.board =>
        tr('Үздіктер тізімінде атың көрінеді.'),
  };

  IconData get icon => switch (this) {
    GuestFeature.saveWord   => PhosphorIconsFill.books,
    GuestFeature.league     => PhosphorIconsFill.shieldStar,
    GuestFeature.ranked     => PhosphorIconsFill.sword,
    GuestFeature.tournament => PhosphorIconsFill.trophy,
    GuestFeature.daily      => PhosphorIconsFill.globeHemisphereEast,
    GuestFeature.friends    => PhosphorIconsFill.usersThree,
    GuestFeature.board      => PhosphorIconsFill.ranking,
  };
}

/// True while the signed-in session is an anonymous guest.
final isGuestProvider = Provider<bool>((ref) =>
    ref.watch(myProfileProvider).value?.isGuest ?? false);

/// Guard for a gated action. Returns true when the caller may proceed;
/// otherwise it shows the claim sheet and returns whatever the user did.
Future<bool> requireAccount(
  BuildContext context,
  WidgetRef ref,
  GuestFeature feature,
) async {
  if (!ref.read(isGuestProvider)) return true;
  final claimed = await showClaimSheet(context, feature);
  return claimed == true;
}

Future<bool?> showClaimSheet(BuildContext context, GuestFeature feature) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ClaimSheet(feature: feature),
    );

/// Ends the guest session and opens the sign-in screen. A guest is never
/// asked to confirm signing "out", because they never signed in — this is
/// framed entirely as what it does for them: switching to an account that
/// already exists. Returns whether they actually went through with it.
Future<bool> signInToExistingAccount(BuildContext context, WidgetRef ref) async {
  final ok = await sqConfirm(context,
    title: tr('Аккаунтқа кіру'),
    message: tr('Бар аккаунтыңа кірсең, қазіргі қонақ режиміндегі прогрес '
                'жоғалады. Оны сақтап қалу үшін алдымен тіркел.'),
    confirm: tr('Кіру'),
    cancel: tr('Болдырмау'),
    danger: false);
  if (!ok) return false;
  ref.read(showLoginProvider.notifier).state = true;
  await ref.read(authRepoProvider).signOut();
  return true;
}

class _ClaimSheet extends ConsumerStatefulWidget {
  final GuestFeature feature;
  const _ClaimSheet({required this.feature});

  @override
  ConsumerState<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends ConsumerState<_ClaimSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _pwd = TextEditingController();
  final _repo = PhoneAuthRepo();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = ref.read(myProfileProvider).value;
    // Compare against the raw stored default, not a UI-language translation
    // of it — the stored value is always the literal Kazakh word regardless
    // of which interface language is currently active.
    if (p != null && p.displayName != 'Қонақ') _name.text = p.displayName;
  }

  @override
  void dispose() {
    _name.dispose(); _pwd.dispose();
    super.dispose();
  }

  /// A guest who already has an account was, until now, stuck here on a
  /// registration-only form with no way out but "Later" — the only sign-in
  /// entry point lived in Settings, several taps away from wherever this
  /// sheet actually opened. This closes the gap right where it appears.
  Future<void> _signInInstead() async {
    final switched = await signInToExistingAccount(context, ref);
    if (switched && mounted) Navigator.of(context).pop(false);
  }

  Future<void> _claim() async {
    if (!_form.currentState!.validate()) return;

    final verified = await verifyWithTelegram(context);
    if (verified == null || !mounted) return;

    setState(() { _busy = true; _error = null; });
    try {
      await _repo.claimGuest(
        code: verified.code,
        password: _pwd.text,
        displayName: _name.text.trim(),
      );
      ref.invalidate(myProfileProvider);
      refreshAll(ref);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      sqSnack(context, tr('Аккаунт жасалды — барлық прогресің сақталды'));
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final p = ref.watch(myProfileProvider).value;

    return Padding(
      padding: EdgeInsets.only(
        left: 22, right: 22, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SqSheetGrip(),
              Center(child: SqTintBox(widget.feature.icon, size: 56)),
              const SizedBox(height: 13),
              Text(widget.feature.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800,
                  letterSpacing: -0.4, color: AppColors.text(d))),
              const SizedBox(height: 7),
              Text(widget.feature.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13, height: 1.5, fontWeight: FontWeight.w600,
                  color: AppColors.text3(d))),
              const SizedBox(height: 18),

              // Reassure the guest that nothing is lost — with real numbers.
              SqPanel(
                radius: 18,
                padding: const EdgeInsets.all(14),
                fill: AppColors.soft(AppColors.green, d),
                border: AppColors.line(AppColors.green, d),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsFill.shieldCheck,
                      size: 20, color: AppColors.greenDeep),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        trp('Бәрі сақталады: {xp} XP · {words} сөз · {days} күн', {
                          'xp': '${p?.xp ?? 0}',
                          'words': '${p?.wordsTotal ?? 0}',
                          'days': '${p?.streak ?? 0}',
                        }),
                        style: const TextStyle(
                          fontSize: 12.5, height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: AppColors.greenInk)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

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
              TextFormField(
                controller: _pwd,
                obscureText: _obscure,
                decoration: InputDecoration(
                  hintText: tr('Құпия сөз'),
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

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.red, fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
              ],

              const SizedBox(height: 13),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.soft(AppColors.sky, d),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsFill.paperPlaneTilt,
                      size: 17, color: AppColors.sky),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr('Telegram растайды — SMS қажет емес.'),
                        style: TextStyle(
                          fontSize: 11.5, height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSoft(AppColors.sky, d))),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              SqAction(tr('Telegram арқылы тіркелу'),
                icon: PhosphorIconsFill.paperPlaneTilt,
                busy: _busy,
                onTap: _claim),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _signInInstead,
                  child: Text(tr('Аккаунтың бар ма? Кіру'))),
              ),
              TextButton(
                onPressed: _busy
                    ? null : () => Navigator.of(context).pop(false),
                child: Text(tr('Кейінірек'))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small inline strip shown on hub screens while browsing as a guest.
class GuestBanner extends ConsumerWidget {
  final GuestFeature feature;
  const GuestBanner({super.key, this.feature = GuestFeature.board});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isGuestProvider)) return const SizedBox.shrink();
    final d = isDark(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SqPanel(
        radius: 20,
        padding: const EdgeInsets.all(15),
        fill: AppColors.soft(AppColors.amber, d),
        border: AppColors.line(AppColors.amber, d),
        onTap: () => showClaimSheet(context, feature),
        child: Row(
          children: [
            const SqTintBox(PhosphorIconsFill.userCircle,
              tint: AppColors.amber, size: 40, solid: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('Қонақ режиміндесің'),
                    style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800,
                      color: AppColors.text(d))),
                  Text(tr('Тіркел — прогресің сақталады, арена ашылады'),
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
    );
  }
}
