#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
app_dir="$project_dir/dist/小可桌宠.app"
mkdir -p "$build_dir/module-cache" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
if [[ "${1:-}" != "--skip-tests" ]]; then
  /bin/zsh "$project_dir/scripts/test.sh"
fi
/usr/bin/clang -O2 -target "${XIAOKE_ARCH:-$(uname -m)}-apple-macosx13.0" -c "$project_dir/Sources/Sensors.c" -o "$build_dir/Sensors.o"
/usr/bin/swiftc -swift-version 5 -O -target "${XIAOKE_ARCH:-$(uname -m)}-apple-macosx13.0" \
  -module-cache-path "$build_dir/module-cache" \
  -import-objc-header "$project_dir/Sources/Sensors.h" \
  -framework AppKit -framework SwiftUI -framework Combine -framework PDFKit -framework UserNotifications -framework IOKit \
  "$project_dir"/Sources/*.swift "$build_dir/Sensors.o" -o "$app_dir/Contents/MacOS/XiaoKeCompanion"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/spritesheet.png" "$app_dir/Contents/Resources/spritesheet.png"
cp "$project_dir/Resources/l3d-spritesheet.png" "$app_dir/Contents/Resources/l3d-spritesheet.png"
for activity in "$project_dir/Resources/"*-activities.png(N) "$project_dir/Resources/"*-life.png(N) "$project_dir/Resources/"*-foods.png(N) "$project_dir/Resources/"*-blanket.png(N) "$project_dir/Resources/"l3d-accessory-*.png(N) "$project_dir/Resources/"home-*.png(N); do
  cp "$activity" "$app_dir/Contents/Resources/"
done
mkdir -p "$app_dir/Contents/Resources/cli"
cp "$project_dir/cli/xiaoke" "$app_dir/Contents/Resources/cli/xiaoke"
if [[ -f "$project_dir/Resources/AppIcon.icns" ]]; then
  cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
fi
/usr/bin/plutil -lint "$app_dir/Contents/Info.plist"
/usr/bin/codesign --force --sign - --timestamp=none "$app_dir"
/usr/bin/codesign --verify --deep --strict "$app_dir"
print "已构建：$app_dir"
