#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p .build/module-cache docs/screenshots
sources=()
for source in Sources/*.swift; do
  [[ "$source" == Sources/Main.swift ]] || sources+=("$source")
done
/usr/bin/clang -O2 -target "${XIAOKE_ARCH:-$(uname -m)}-apple-macosx13.0" -c Sources/Sensors.c -o .build/ScreenshotSensors.o
/usr/bin/swiftc -swift-version 5 -target "${XIAOKE_ARCH:-$(uname -m)}-apple-macosx13.0" -module-cache-path .build/module-cache \
  -import-objc-header Sources/Sensors.h -framework AppKit -framework SwiftUI -framework Combine -framework PDFKit -framework IOKit \
  "${sources[@]}" Tests/ScreenshotFixtures.swift .build/ScreenshotSensors.o -o .build/screenshots
.build/screenshots
