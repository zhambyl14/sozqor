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
# The commit is baked in so the running app can name the build it came
# from. Without it "is my change in this app?" has no answer from a phone:
# a stale service worker and an old bookmark look identical to a deploy
# that never happened. Cloudflare sets CF_PAGES_COMMIT_SHA; the git
# fallback covers running this script by hand.
BUILD_STAMP="${CF_PAGES_COMMIT_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}"
BUILD_STAMP="${BUILD_STAMP:0:7}"
APP_VERSION="$(grep '^version:' pubspec.yaml | cut -d' ' -f2 | cut -d'+' -f1)"
echo "-> building ${APP_VERSION} - ${BUILD_STAMP}"

flutter build web --release \
  --pwa-strategy=none \
  --dart-define=APP_VERSION="${APP_VERSION}" \
  --dart-define=BUILD_STAMP="${BUILD_STAMP}" \
  --dart-define=FCM_VAPID_KEY="${FCM_VAPID_KEY:-}"

echo "→ built build/web"
