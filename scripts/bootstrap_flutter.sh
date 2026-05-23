#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../apps/noir_flutter"
flutter create . --platforms=ios,android,web
flutter pub get
dart run sodium:update_web --sumo

