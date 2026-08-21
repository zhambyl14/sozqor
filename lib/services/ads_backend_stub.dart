// lib/services/ads_backend_stub.dart
//
// The no-ads backend. Chosen by the conditional import in ads.dart for every
// target without dart:io — which today means the web build that ships through
// Cloudflare, where google_mobile_ads has no implementation and cannot even
// be compiled in.
//
// It exists so the browser never has to be a special case at the call sites:
// the offer simply never has an ad to give, which the caller already handles
// as "no reward". See ads.dart for the contract these functions implement.

Future<void> adsEnsureInit() async {}

bool adsIsReady() => false;

Future<bool> adsPreload(String unitId) async => false;

/// Always 'unavailable' — see [AdOutcome] in ads.dart for the codes.
Future<String> adsShowRewarded(String unitId) async => 'unavailable';
