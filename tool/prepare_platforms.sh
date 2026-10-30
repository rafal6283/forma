#!/usr/bin/env bash
# Generuje katalogi android/ i ios/ (flutter create) i nakłada na nie poprawki Formy.
set -euo pipefail
cd "$(dirname "$0")/.."

# test/ jest nasz — flutter create nie nadpisuje istniejących plików, ale dokłada widget_test.dart
had_widget_test=0
[ -f test/widget_test.dart ] && had_widget_test=1
flutter create --org pl.rafal --project-name forma --platforms "${PLATFORMS:-android,ios}" . >/dev/null
[ "$had_widget_test" = 0 ] && rm -f test/widget_test.dart

python3 tool/patch_platforms.py
