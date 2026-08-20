// lib/core/config/app_config.dart
//
// Supabase connection details.
// The publishable key is designed to ship inside the client — every table is
// protected by row level security, and LLM keys live only in the
// `sozqor-ai` edge function.

class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xwscugxrkbjiwcbmswrg.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_g_UwLLvwfR7hcz0GQ5si4A_P2L1GlbK',
  );

  /// Web / iOS OAuth client id used by google_sign_in to mint an id token.
  /// Leave empty to hide the Google button until it is configured.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  static bool get googleSignInReady => googleWebClientId.isNotEmpty;

  /// Web push needs the Web Push certificate key pair from
  /// Firebase console → Project settings → Cloud Messaging → Web configuration.
  /// Leave it empty and web push simply stays off; Android and iOS are
  /// unaffected either way.
  static const String fcmVapidKey = String.fromEnvironment(
    'FCM_VAPID_KEY',
    defaultValue: '',
  );

  static bool get webPushReady => fcmVapidKey.isNotEmpty;

  static const String aiFunction = 'sozqor-ai';
}
