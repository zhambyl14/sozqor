#!/usr/bin/env bash
# Builds the web app inside Cloudflare's build container.
#
# Cloudflare's image has git and node but no Flutter, so the SDK is fetched
# here. `--depth 1 -b stable` keeps that to a few seconds rather than cloning
# the full history.
#
# Point the Cloudflare build settings at this file:
#   Build command:            bash tool/cf_build.sh
#   Deploy command:           npx wrangler deploy
#   Build output directory:   build/web
set -euo pipefail

FLUTTER_DIR="${HOME}/flutter"

if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  echo "→ fetching Flutter (stable)"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"

# The container runs as a different user than the one that cloned the SDK on a
# cached build; without this git refuses to touch the repo and flutter fails.
git config --global --add safe.directory "${FLUTTER_DIR}" || true

flutter --version
flutter pub get

# --pwa-strategy=none is not optional. Flutter's service worker caches the
# whole app on the device and keeps serving it after a deploy, which is how a
# shipped fix ends up invisible on a phone that has opened the site before.
# Web push is unaffected — it runs through firebase-messaging-sw.js.
#
# FCM_VAPID_KEY is optional: without it web push simply stays off and the rest
# of the app is unchanged. Set it in Cloudflare → Settings → Variables.
flutter build web --release \
  --pwa-strategy=none \
  --dart-define=FCM_VAPID_KEY="${FCM_VAPID_KEY:-}"

# web/_redirects holds `/* /index.html 200`, which is how Netlify is told to
# serve a single-page app. Cloudflare reads the same file but rejects that
# rule outright — /index.html matches /* , so it scores it an infinite loop
# and fails the deploy (error 100324). Here the same job is done by
# `not_found_handling: single-page-application` in wrangler.jsonc, so the
# file is only in the way. Dropped from the output rather than the repo,
# because Netlify still needs it.
rm -f build/web/_redirects

echo "→ built build/web"
