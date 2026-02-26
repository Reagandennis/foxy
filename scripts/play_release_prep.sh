#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DART_DEFINE_FILE="${1:-supabase.local.json}"
KEY_PROPS_FILE="android/key.properties"
LOCAL_PROPS_FILE="android/local.properties"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

fail() {
  echo -e "${RED}ERROR:${NC} $1"
  exit 1
}

warn() {
  echo -e "${YELLOW}WARN:${NC} $1"
}

ok() {
  echo -e "${GREEN}OK:${NC} $1"
}

echo "== Foxy Android Play Release Prep =="

test -f "$DART_DEFINE_FILE" || fail "Missing $DART_DEFINE_FILE"
ok "Found $DART_DEFINE_FILE"

test -f "$KEY_PROPS_FILE" || fail "Missing $KEY_PROPS_FILE. Copy android/key.properties.example and fill real values."

store_file="$(grep -E '^storeFile=' "$KEY_PROPS_FILE" | cut -d'=' -f2- | xargs || true)"
store_password="$(grep -E '^storePassword=' "$KEY_PROPS_FILE" | cut -d'=' -f2- | xargs || true)"
key_alias="$(grep -E '^keyAlias=' "$KEY_PROPS_FILE" | cut -d'=' -f2- | xargs || true)"
key_password="$(grep -E '^keyPassword=' "$KEY_PROPS_FILE" | cut -d'=' -f2- | xargs || true)"

[[ -n "$store_file" && -n "$store_password" && -n "$key_alias" && -n "$key_password" ]] || fail "android/key.properties is incomplete."

if [[ "$store_password" == replace_with_store_password || "$key_password" == replace_with_key_password ]]; then
  fail "android/key.properties still has placeholder passwords."
fi

if [[ "$store_file" = /* ]]; then
  resolved_keystore="$store_file"
else
  # Match Gradle module-relative resolution used in android/app/build.gradle.kts
  resolved_keystore="$ROOT_DIR/android/app/$store_file"
fi
[[ -f "$resolved_keystore" ]] || fail "Keystore file not found at $resolved_keystore"
ok "Release key config looks valid"

if [[ -f "$LOCAL_PROPS_FILE" ]]; then
  app_id="$(grep -E '^FOXY_APP_ID=' "$LOCAL_PROPS_FILE" | cut -d'=' -f2- | xargs || true)"
  version_code="$(grep -E '^FOXY_VERSION_CODE=' "$LOCAL_PROPS_FILE" | cut -d'=' -f2- | xargs || true)"
  version_name="$(grep -E '^FOXY_VERSION_NAME=' "$LOCAL_PROPS_FILE" | cut -d'=' -f2- | xargs || true)"

  if [[ -z "$app_id" ]]; then
    warn "FOXY_APP_ID not set in android/local.properties. Default com.foxy.app will be used."
  else
    ok "FOXY_APP_ID=$app_id"
  fi

  if [[ -z "$version_code" || -z "$version_name" ]]; then
    warn "FOXY_VERSION_CODE or FOXY_VERSION_NAME missing in android/local.properties. pubspec version will be used."
  else
    ok "Version override: $version_name ($version_code)"
  fi
fi

echo

echo "Running quality checks..."
flutter analyze
flutter test

echo

echo "Building Play bundle (.aab)..."
flutter build appbundle --release --dart-define-from-file="$DART_DEFINE_FILE"

AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
[[ -f "$AAB_PATH" ]] || fail "Build finished without expected bundle at $AAB_PATH"
ok "Bundle ready: $AAB_PATH"

echo
ok "Release prep complete. Next: upload .aab to Play Console internal testing track."
