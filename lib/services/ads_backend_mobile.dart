// lib/services/ads_backend_mobile.dart
//
// The real AdMob backend, reached by the conditional import in ads.dart on
// every target that has dart:io. Only Android and iOS actually carry the
// plugin: dart:io is also present on Windows, macOS and Linux, where the
// method channel has nobody on the other end, so the platform is checked
// again here and desktop quietly gets no ads instead of an exception.
//
// Nothing in this file is allowed to throw into the app. An ad is a bonus; a
// learner whose ad failed must still be looking at a working game.
//
// The reward policy — never XP — lives in ads.dart, where the rewards are
// defined. This file only knows how to load and show a video.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// A rewarded ad is single use: once shown it is disposed and the next one is
/// loaded behind it, so at most one is ever held.
RewardedAd? _ad;
bool _loading = false;
bool _initialized = false;

/// How long a load may take before the offer gives up. Long enough for a slow
/// connection, short enough that nobody is left staring at a spinner.
const Duration _loadTimeout = Duration(seconds: 12);

/// A watched ad that never reports back — the app was backgrounded mid-video,
/// say — must not leave the caller awaiting forever.
const Duration _showTimeout = Duration(minutes: 5);

bool get _onAdPlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

Future<void> adsEnsureInit() async {
  if (_initialized || !_onAdPlatform) return;
  // Set before awaiting: two screens preloading at once must not both run the
  // SDK's initialize.
  _initialized = true;
  try {
    await MobileAds.instance.initialize();
  } catch (_) {
    // An SDK that refused to start simply never fills an ad.
  }
}

bool adsIsReady() => _ad != null;

/// Loads one ad and reports whether it is now ready. A load already in flight
/// is not started a second time.
Future<bool> adsPreload(String unitId) async {
  if (!_onAdPlatform || unitId.isEmpty) return false;
  if (_ad != null) return true;
  if (_loading) return false;

  await adsEnsureInit();
  _loading = true;

  final loaded = Completer<bool>();
  try {
    await RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
          if (!loaded.isCompleted) loaded.complete(true);
        },
        onAdFailedToLoad: (_) {
          _ad = null;
          _loading = false;
          if (!loaded.isCompleted) loaded.complete(false);
        },
      ),
    );
  } catch (_) {
    _loading = false;
    return false;
  }

  return loaded.future.timeout(_loadTimeout, onTimeout: () {
    // The callback may still land later and fill _ad for the next offer; only
    // this attempt is abandoned.
    _loading = false;
    return false;
  });
}

/// Shows the loaded ad, loading one first if need be.
///
/// Returns one of 'earned', 'dismissed', 'failed' or 'unavailable' — the codes
/// ads.dart maps onto AdOutcome. 'earned' is reported only when Google's own
/// reward callback fired, never merely because the ad closed.
Future<String> adsShowRewarded(String unitId) async {
  if (!_onAdPlatform || unitId.isEmpty) return 'unavailable';

  if (_ad == null) await adsPreload(unitId);
  final ad = _ad;
  if (ad == null) return 'unavailable';
  _ad = null;

  var earned = false;
  final closed = Completer<String>();

  ad.fullScreenContentCallback = FullScreenContentCallback(
    onAdDismissedFullScreenContent: (a) {
      a.dispose();
      if (!closed.isCompleted) {
        closed.complete(earned ? 'earned' : 'dismissed');
      }
    },
    onAdFailedToShowFullScreenContent: (a, _) {
      a.dispose();
      if (!closed.isCompleted) closed.complete('failed');
    },
  );

  try {
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
  } catch (_) {
    ad.dispose();
    return 'failed';
  }

  final outcome = await closed.future
      .timeout(_showTimeout, onTimeout: () => earned ? 'earned' : 'failed');

  // Warm the next one so a second offer opens without a wait.
  unawaited(adsPreload(unitId));
  return outcome;
}
