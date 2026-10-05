#!/usr/bin/env bash
# Mac / Linux: Android iskeletini kurar, bağımlılıkları indirir, kodu üretir.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ]; then
  tmp="$(mktemp -d)"
  flutter create --org com.kocum --project-name kocum --platforms android "$tmp/kocum"
  cp -r "$tmp/kocum/android" ./android
fi

flutter pub get
dart tool/patch_android.dart
dart run build_runner build --delete-conflicting-outputs

echo
echo "Hazır. Telefonu USB ile bağla ve çalıştır:  flutter run --release"
