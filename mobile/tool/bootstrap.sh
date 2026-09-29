#!/usr/bin/env bash
# Generates the Android platform folder for the installed Flutter version
# (only files that are missing), patches in what the plugins need, fetches
# packages and generates the Drift code.
#
#   cd mobile && ./tool/bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ]; then
  flutter create --project-name neuro_sathi --org org.neurosathi --platforms android .
fi
python3 tool/patch_android.py
flutter pub get
dart run build_runner build --delete-conflicting-outputs
