// lib/services/ads.dart
//
// Rewarded video ads: the learner chooses to watch one, and gets something
// back for it.
//
// ── The rule that must not be undone ──────────────────────────────────────
//
// A REWARDED AD MUST NEVER PAY XP.
//
// Leagues, the leaderboard, the daily challenge board and tournament
// standings are all ranked on XP or on a submitted score. XP handed out for
// watching a video would mean rank is bought with time and mobile data
// instead of earned by answering, and every ranking in the app would stop
// meaning "who learned the most". So an ad may only ever hand back things
// nobody is ranked on: one more life inside a run, a streak freeze, a
// practice re-run, extra cosmetic loot from a chest.
//
// The test to apply before adding a reward: could two learners who answered
// exactly the same questions exactly as well end up in a different order
// because one of them watched an ad? If yes, the reward does not belong here.
// That also covers the indirect route — a run continued by an ad must not
// overwrite a ranked best score, so the caller skips the board submit for
// that run (see [AdReward.extraLife]).
//
// ── Why this is three files ───────────────────────────────────────────────
//
// google_mobile_ads is Android/iOS only, and its Dart code imports dart:io,
// so it cannot even be compiled into the web bundle this app also ships
// through Cloudflare — a `kIsWeb` check at runtime would come far too late.
// The split therefore happens at import time: the browser gets
// `ads_backend_stub.dart`, which answers "no ad available" to everything.
// Every call site below works on every platform and never throws.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/i18n/l10n.dart';
import '../core/widgets/sq.dart';

import 'ads_backend_stub.dart'
    if (dart.library.io) 'ads_backend_mobile.dart' as backend;

// ═══════════════════════════════════════════════════════════
// Ad units
// ═══════════════════════════════════════════════════════════

/// The one place an ad unit id is written down.
///
/// Everything shipped today is a Google TEST unit: they always fill, they are
/// safe to run in debug, and they are the only ids that may ever be typed by
/// hand. A made-up id that merely looks real would serve ads against somebody
/// else's account — the live ids come from the AdMob console and arrive
/// through --dart-define, so a test build and a store build differ by a flag
/// rather than by an edit to this file.
class AdUnits {
  AdUnits._();

  // ⚠️ TEST — Google's official sample rewarded units.
  // https://developers.google.com/admob/android/test-ads
  static const String testAndroidRewarded =
      'ca-app-pub-3940256099942544/5224354917';
  static const String testIosRewarded =
      'ca-app-pub-3940256099942544/1712485313';

  // ⚠️ TEST — Google's official sample application ids, for the manifest /
  // Info.plist. Kept here so the real ones are swapped in one sitting.
  static const String testAndroidAppId =
      'ca-app-pub-3940256099942544~3347511713';
  static const String testIosAppId = 'ca-app-pub-3940256099942544~1458002511';

  /// Live units. Empty until the AdMob account has them:
  ///   flutter build apk --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-…/…
  static const String liveAndroidRewarded =
      String.fromEnvironment('ADMOB_REWARDED_ANDROID');
  static const String liveIosRewarded =
      String.fromEnvironment('ADMOB_REWARDED_IOS');

  /// True while the app is still serving Google's test inventory. Worth
  /// showing somewhere in a debug build so a test unit never ships unnoticed.
  static bool get usingTestUnits => rewarded == testAndroidRewarded ||
      rewarded == testIosRewarded;

  /// The rewarded unit for the platform the app is running on.
  static String get rewarded => switch (defaultTargetPlatform) {
        TargetPlatform.android =>
          liveAndroidRewarded.isNotEmpty ? liveAndroidRewarded : testAndroidRewarded,
        TargetPlatform.iOS =>
          liveIosRewarded.isNotEmpty ? liveIosRewarded : testIosRewarded,
        // No other platform has an AdMob implementation at all.
        _ => '',
      };
}

// ═══════════════════════════════════════════════════════════
// Outcomes and rewards
// ═══════════════════════════════════════════════════════════

/// How an ad attempt ended. Only [earned] may grant anything: the other three
/// all mean the learner did not watch a full ad, and telling them apart
/// matters because each deserves a different sentence on screen.
enum AdOutcome {
  /// Watched far enough that Google reported a reward. Grant it.
  earned,

  /// Closed early. Nothing is granted, and nothing is wrong either.
  dismissed,

  /// The ad broke while showing. Nothing is granted.
  failed,

  /// No ad to show — web, an unsupported platform, no fill, no connection.
  unavailable,
}

extension AdOutcomeMeta on AdOutcome {
  bool get grantsReward => this == AdOutcome.earned;

  /// What to tell the learner when nothing was granted. Kazakh original —
  /// wrap in `tr()` at the call site.
  String? get message => switch (this) {
        AdOutcome.earned => null,
        AdOutcome.dismissed => 'Жарнама толық көрілмеді — сыйлық берілмеді',
        AdOutcome.failed => 'Жарнама толық көрілмеді — сыйлық берілмеді',
        AdOutcome.unavailable => 'Қазір жарнама жоқ. Кейінірек көр.',
      };
}

/// What a watched ad may buy. Every entry is deliberately something no board
/// ranks on — see the file header before adding a fifth.
enum AdReward {
  /// Revive a marathon run that just ran out of lives. The run continues for
  /// the learning; the arcade record does not, so the caller must skip
  /// `submitGameScore` for a revived run.
  extraLife,

  /// One streak freeze into the shop stock. Streaks are personal, not ranked.
  streakFreeze,

  /// Replay a round as practice. Nothing is submitted a second time, so a
  /// board score can never be improved by watching an ad.
  secondChance,

  /// Twice the cosmetic contents of a daily chest. Cosmetics carry no rank.
  doubleChest,
}

/// Titles and one-line pitches, as Kazakh originals — the same convention as
/// [PlayModeMeta] in game_meta.dart, so the call site wraps them in `tr()`.
extension AdRewardMeta on AdReward {
  String get title => switch (this) {
        AdReward.extraLife => 'Тағы бір жан',
        AdReward.streakFreeze => 'Серия мұздатқыш',
        AdReward.secondChance => 'Тағы бір мүмкіндік',
        AdReward.doubleChest => 'Сандықты екі есе қыл',
      };

  String get pitch => switch (this) {
        AdReward.extraLife =>
          'Қысқа жарнама көр де, ойынды +1 жанмен жалғастыр',
        AdReward.streakFreeze =>
          'Жарнама көр де, серияңды бір күнге сақтап қал',
        AdReward.secondChance =>
          'Жарнама көр де, бұл раундты қайта ойна. Нәтиже кестеге жазылмайды.',
        AdReward.doubleChest =>
          'Жарнама көр де, сандықтан екі есе зат ал',
      };
}

// ═══════════════════════════════════════════════════════════
// The service
// ═══════════════════════════════════════════════════════════

/// Loads and shows rewarded ads. Every method is safe to call on every
/// platform: on web, on desktop and on a device with no connection it simply
/// reports that no ad is available.
class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  /// Only Android and iOS have an AdMob implementation. Web is excluded twice
  /// over — by [kIsWeb] here and by the conditional import above.
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      AdUnits.rewarded.isNotEmpty;

  /// True when an ad is loaded right now and [showRewarded] would open
  /// immediately. False is not a failure — [showRewarded] still tries to load
  /// one on the spot.
  bool get isReady => supported && backend.adsIsReady();

  /// Starts the AdMob SDK. Optional — [preload] and [showRewarded] both do it
  /// themselves — but calling it once at launch means the first offer of the
  /// session does not pay for the SDK handshake on top of the ad load.
  Future<void> init() async {
    if (!supported) return;
    await backend.adsEnsureInit();
  }

  /// Warms one up. Cheap to call more than once; a load already in flight is
  /// not started again. Call it a screen *before* the offer appears so the ad
  /// opens instantly rather than after a spinner.
  Future<void> preload() async {
    if (!supported) return;
    await backend.adsPreload(AdUnits.rewarded);
  }

  /// Shows a rewarded ad and reports how it ended.
  ///
  /// The caller must branch on this: only [AdOutcome.earned] means the learner
  /// actually watched, and only then may anything be granted.
  Future<AdOutcome> showRewardedOutcome() async {
    if (!supported) return AdOutcome.unavailable;
    // The seam between this file and the two platform backends carries a
    // plain code rather than [AdOutcome]: the backends are reached through a
    // conditional import, and keeping the shared enum on this side of it
    // avoids an import cycle just to name four constants.
    return switch (await backend.adsShowRewarded(AdUnits.rewarded)) {
      'earned' => AdOutcome.earned,
      'dismissed' => AdOutcome.dismissed,
      'failed' => AdOutcome.failed,
      _ => AdOutcome.unavailable,
    };
  }

  /// True only when the reward was genuinely earned. "No ad", "dismissed" and
  /// "failed" all return false, and none of them may grant anything.
  Future<bool> showRewarded() async =>
      (await showRewardedOutcome()).grantsReward;

  /// The whole offer in one call: ask first, show the ad, report the result.
  ///
  /// Asking first is not politeness — a rewarded ad that opens without consent
  /// is a policy violation, and the learner has to know what they are being
  /// offered before spending thirty seconds on it.
  ///
  /// Returns true only when the reward was earned, so the call site reads:
  ///
  ///   if (await AdsService.instance.offerRewarded(context, AdReward.extraLife)) {
  ///     // grant the life
  ///   }
  Future<bool> offerRewarded(BuildContext context, AdReward reward) async {
    if (!supported) {
      sqSnack(context, tr('Қазір жарнама жоқ. Кейінірек көр.'));
      return false;
    }

    final agreed = await sqConfirm(
      context,
      title: tr(reward.title),
      message: '${tr(reward.pitch)}\n\n${tr('XP берілмейді — рейтинг таза қалады')}',
      confirm: tr('Жарнама көру'),
      cancel: tr('Кейін'),
      danger: false,
    );
    if (!agreed || !context.mounted) return false;

    // Nothing is loaded yet, so the learner is about to wait — say so, then
    // let showRewardedOutcome do the loading itself.
    if (!isReady) sqSnack(context, tr('Жарнама жүктелуде…'));

    final outcome = await showRewardedOutcome();
    if (!context.mounted) return outcome.grantsReward;

    final problem = outcome.message;
    if (problem != null) sqSnack(context, tr(problem), error: true);
    return outcome.grantsReward;
  }
}
