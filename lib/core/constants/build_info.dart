// lib/core/constants/build_info.dart
//
// Which build is actually running, visible from inside the app.
//
// Without this there is no way to answer "did my change ship?" from a phone.
// A stale service worker, a second browser tab holding the old worker alive,
// or an old bookmark pointing at a retired host all look identical from the
// outside: the app opens, and nothing you added is there. Reading a stamp off
// the Settings screen settles it in one glance instead of an argument.
//
// Both values are compile-time constants, so no package and no plugin channel
// is involved and this works the same on web and on Android.

/// The marketing version, kept in step with pubspec.yaml by the build scripts.
const String kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '4.0.1');

/// The short commit the build came from. `tool/cf_build.sh` passes it on every
/// Cloudflare deploy; a local `flutter build` without the define says "local",
/// which is itself the useful answer.
const String kBuildStamp =
    String.fromEnvironment('BUILD_STAMP', defaultValue: 'local');

/// What to print in Settings: "4.0.1 · a1b2c3d".
String get buildLabel => '$kAppVersion · $kBuildStamp';
