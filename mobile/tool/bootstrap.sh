#!/usr/bin/env bash
# Generates the Android platform folder for the installed Flutter version
# (only files that are missing), patches in what the plugins need, bundles the
# language packs, fetches packages and generates the Drift code.
#
#   cd mobile && ./tool/bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ]; then
  flutter create --project-name neuro_sathi --org org.neurosathi --platforms android .
fi
python3 tool/patch_android.py
python3 tool/sync_language_packs.py
flutter pub get
dart run build_runner build --delete-conflicting-outputs
