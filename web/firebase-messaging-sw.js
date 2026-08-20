// web/firebase-messaging-sw.js
//
// Background handler for web push. The browser runs this file on its own, so
// the Firebase config has to be repeated here — it is the same public config
// as lib/firebase_options.dart (web).
//
// Push on the web needs three things to line up:
//   1. this file served from the site root
//   2. a VAPID key passed to getToken() — see AppConfig.fcmVapidKey
//   3. on iOS, the site installed to the home screen (iOS 16.4+)

importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCbEyzaBYjIVoWzYft6ax6xNpdVBfcaIbs',
  appId: '1:774025972537:web:2f2f207efafa295a9bb6e8',
  messagingSenderId: '774025972537',
  projectId: 'sozqor',
  authDomain: 'sozqor.firebaseapp.com',
  storageBucket: 'sozqor.firebasestorage.app',
  measurementId: 'G-WYQGRKZX9K',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
  const n = payload.notification || {};
  const d = payload.data || {};
  self.registration.showNotification(n.title || 'SozQor', {
    body: n.body || '',
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    tag: d.tag || 'sozqor',
    data: d,
  });
});

// Tapping the notification focuses an open tab instead of opening a second one.
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  const route = (event.notification.data && event.notification.data.route) || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
      for (const client of list) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow(route);
    })
  );
});
