// lib/services/push_service.dart
//
// Notifications come from two places and the app needs both:
//
//   • Firebase Cloud Messaging — league, battle and friend pushes sent from a
//     server. Works on Android, iOS and, once a VAPID key is configured, in
//     the browser.
//   • A local daily reminder — scheduled on the device itself, so a learner
//     still gets nudged when nothing is running server-side. This is the one
//     that actually fires for most people.
//
// Nothing here is allowed to throw into the app: notifications are a nicety,
// and a device that refuses permission must still get a working app.

import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/config/app_config.dart';
import '../core/i18n/l10n.dart';
import '../data/supa.dart';

/// Wakes the isolate for a background message. The tray alert itself is drawn
/// by the system from the `notification` block, so there is nothing to draw
/// here — but the handler must exist and must stay top-level.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _local = FlutterLocalNotificationsPlugin();

  bool _started = false;
  bool _localReady = false;
  String? _token;

  /// Set by the shell so a notification tap can move the learner somewhere.
  void Function(Map<String, dynamic> data)? onOpen;

  /// A tap that arrived before anything was listening — replayed once the
  /// shell registers.
  Map<String, dynamic>? _pendingOpen;

  static const _reminderId = 1001;
  static const _testId = 1002;
  static const _prefsOn = 'sq_reminder_on';
  static const _prefsHour = 'sq_reminder_hour';
  static const _prefsMin = 'sq_reminder_minute';

  /// Early evening — when most learners actually open the app.
  static const defaultHour = 20;
  static const defaultMinute = 0;

  static final _channel = AndroidNotificationChannel(
    'sozqor_default',
    'SozQor',
    description: tr('Күнделікті еске салу, лига және баттл хабарламалары'),
    importance: Importance.high,
  );

  /// Local scheduling has no web implementation, so the browser leans on FCM
  /// web push instead.
  bool get supportsLocal => !kIsWeb;

  /// Web push is off until a VAPID key is compiled in; native always has it.
  bool get pushConfigured => kIsWeb ? AppConfig.webPushReady : true;

  // ── startup ──────────────────────────────────────────────
  /// Safe to call on every launch; failures never block the app.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await _initLocal();
      await _initFirebase();
      // Put back the reminder the learner had set before the last restart.
      await restoreReminder();
    } catch (_) {
      // Notifications are optional — the app works fine without them.
    }
  }

  Future<void> _initLocal() async {
    if (!supportsLocal || _localReady) return;
    try {
      tzdata.initializeTimeZones();

      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            // Permission is asked for later, on the learner's own terms.
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => _handleOpen(_decode(r.payload)),
      );

      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // A tap that launched the app from cold.
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _handleOpen(_decode(launch?.notificationResponse?.payload));
      }
      _localReady = true;
    } catch (_) {/* local notifications simply stay off */}
  }

  Future<void> _initFirebase() async {
    if (Firebase.apps.isEmpty || !pushConfigured) return;

    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    }

    final messaging = FirebaseMessaging.instance;

    // iOS shows nothing in the foreground unless told to; on Android the
    // alert is drawn by the local plugin below.
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _handleOpen(Map<String, dynamic>.from(m.data)));

    final initial = await messaging.getInitialMessage();
    if (initial != null) _handleOpen(Map<String, dynamic>.from(initial.data));

    // Only sync a token if notifications are already allowed. Asking on the
    // very first launch is what makes people say no forever.
    if (await permissionGranted()) await syncToken();

    messaging.onTokenRefresh.listen((t) {
      _token = t;
      _storeToken(t);
    });
  }

  // ── permission ───────────────────────────────────────────
  Future<bool> permissionGranted() async {
    try {
      if (Firebase.apps.isEmpty || !pushConfigured) return false;
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      return s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  /// Asks the OS. Returns whether notifications may now be shown.
  Future<bool> requestPermission() async {
    var granted = false;
    try {
      if (Firebase.apps.isNotEmpty && pushConfigured) {
        final s = await FirebaseMessaging.instance
            .requestPermission(alert: true, badge: true, sound: true);
        granted = s.authorizationStatus == AuthorizationStatus.authorized ||
            s.authorizationStatus == AuthorizationStatus.provisional;
      }
    } catch (_) {/* fall through to the local plugin */}

    // Android 13+ and iOS gate the locally scheduled reminder separately.
    if (supportsLocal) {
      await _initLocal();
      try {
        if (defaultTargetPlatform == TargetPlatform.android) {
          final ok = await _local
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission();
          granted = granted || (ok ?? false);
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          final ok = await _local
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true);
          granted = granted || (ok ?? false);
        }
      } catch (_) {/* ignore */}
    }

    if (granted) await syncToken();
    return granted;
  }

  // ── token ────────────────────────────────────────────────
  /// Stores this device's token against the signed-in user.
  Future<void> syncToken() async {
    if (Firebase.apps.isEmpty || !pushConfigured) return;
    try {
      final messaging = FirebaseMessaging.instance;

      // iOS hands out an FCM token only once APNS has registered the device.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        var apns = await messaging.getAPNSToken();
        for (var i = 0; i < 6 && apns == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          apns = await messaging.getAPNSToken();
        }
        if (apns == null) return;
      }

      final token = kIsWeb
          ? await messaging.getToken(vapidKey: AppConfig.fcmVapidKey)
          : await messaging.getToken();
      if (token == null) return;
      _token = token;
      await _storeToken(token);
    } catch (_) {/* ignore */}
  }

  /// Call this after the interface language changes (Settings). The stored
  /// `device_tokens.lang` column is only ever written from `_storeToken`, so
  /// without a fresh sync it stays stuck on whatever language was active
  /// when the token was first registered.
  Future<void> onLanguageChanged() => syncToken();

  Future<void> _storeToken(String token) async {
    final uid = currentUid;
    if (uid == null) return;
    try {
      await supa.from('device_tokens').upsert({
        'token': token,
        'user_id': uid,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'lang': AppLang.current,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } catch (_) {/* never break the app over a token row */}
  }

  Future<void> clearToken() async {
    try {
      final token = _token ??
          (Firebase.apps.isEmpty || !pushConfigured
              ? null
              : await FirebaseMessaging.instance.getToken());
      if (token != null) {
        await supa.from('device_tokens').delete().eq('token', token);
      }
      _token = null;
    } catch (_) {/* ignore */}
  }

  // ── incoming ─────────────────────────────────────────────
  Future<void> _showForeground(RemoteMessage m) async {
    final n = m.notification;
    if (n == null || !supportsLocal || !_localReady) return;
    try {
      await _local.show(
        n.hashCode,
        n.title,
        n.body,
        _details(),
        payload: jsonEncode(m.data),
      );
    } catch (_) {/* ignore */}
  }

  NotificationDetails _details() => NotificationDetails(
    android: AndroidNotificationDetails(
      _channel.id, _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: const DarwinNotificationDetails(),
  );

  Map<String, dynamic> _decode(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    try {
      final v = jsonDecode(payload);
      return v is Map ? Map<String, dynamic>.from(v) : const {};
    } catch (_) {
      return const {};
    }
  }

  void _handleOpen(Map<String, dynamic> data) {
    final sink = onOpen;
    if (sink == null) {
      _pendingOpen = data;
      return;
    }
    sink(data);
  }

  /// Called by the shell once it can navigate; replays a tap that arrived
  /// while the app was still starting.
  void drainPendingOpen() {
    final pending = _pendingOpen;
    if (pending == null) return;
    _pendingOpen = null;
    onOpen?.call(pending);
  }

  // ── daily reminder ───────────────────────────────────────
  Future<bool> reminderOn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsOn) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<({int hour, int minute})> reminderTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (
        hour: prefs.getInt(_prefsHour) ?? defaultHour,
        minute: prefs.getInt(_prefsMin) ?? defaultMinute,
      );
    } catch (_) {
      return (hour: defaultHour, minute: defaultMinute);
    }
  }

  /// Schedules — or reschedules — the once-a-day nudge. The text is resolved
  /// here, so re-arming after a language switch changes what it says.
  Future<bool> scheduleDailyReminder({int? hour, int? minute}) async {
    if (!supportsLocal) return false;
    await _initLocal();
    if (!_localReady) return false;

    final saved = await reminderTime();
    final h = hour ?? saved.hour;
    final m = minute ?? saved.minute;

    try {
      await _local.cancel(_reminderId);
      await _local.zonedSchedule(
        _reminderId,
        tr('Бүгінгі сөздер күтіп тұр'),
        tr('5 минут жаттық — серияң үзілмесін.'),
        _nextInstance(h, m),
        _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: '{"tab":"play"}',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsOn, true);
      await prefs.setInt(_prefsHour, h);
      await prefs.setInt(_prefsMin, m);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelDailyReminder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsOn, false);
    } catch (_) {/* ignore */}
    if (!supportsLocal) return;
    try {
      await _local.cancel(_reminderId);
    } catch (_) {/* ignore */}
  }

  /// Re-arms the reminder on launch if it is still wanted.
  Future<void> restoreReminder() async {
    if (!supportsLocal) return;
    try {
      if (!await reminderOn()) return;
      await scheduleDailyReminder();
    } catch (_) {/* ignore */}
  }

  /// The next time today or tomorrow that the clock reads h:m.
  ///
  /// Scheduling is done against UTC on purpose: the device's IANA zone name
  /// is not available without another plugin, and an absolute instant that
  /// repeats every 24 hours lands on the same wall clock in any zone that
  /// does not shift for daylight saving — which includes Kazakhstan.
  tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
    return tz.TZDateTime.from(target.toUtc(), tz.UTC);
  }

  /// Fires one notification straight away, so the learner can see for
  /// themselves that notifications work on this device.
  Future<bool> sendTestNotification() async {
    if (!supportsLocal) return false;
    await _initLocal();
    if (!_localReady) return false;
    try {
      await _local.show(
        _testId,
        tr('Хабарлама қосулы'),
        tr('Осылай көрінеді. Жаттығуды ұмытпа!'),
        _details(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
