#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
mkdir -p "$project_dir/.build/module-cache" "$project_dir/qa"
if [[ "${1:-}" == "--feeding-native-only" ]]; then
  /usr/bin/swiftc -swift-version 5 -target "${XIAOKE_ARCH:-$(uname -m)}-apple-macosx13.0" -module-cache-path "$project_dir/.build/module-cache" \
    -framework AppKit -framework Combine "$project_dir/Sources/CompanionCore.swift" \
    "$project_dir/Sources/FeedingMenu.swift" "$project_dir/Tests/FeedingMenuTests.swift" -o "$project_dir/.build/feeding-menu-tests"
  "$project_dir/.build/feeding-menu-tests"
  exit 0
fi
if [[ "${1:-}" == "--native-only" ]]; then
  /usr/bin/swiftc -swift-version 5 -target "${XIAOKE_ARCH:-$(uname -m)}-apple-macosx13.0" -module-cache-path "$project_dir/.build/module-cache" \
    -framework AppKit "$project_dir/Sources/AgentTaskMonitor.swift" "$project_dir/Sources/AgentEventBridge.swift" "$project_dir/Sources/CodexTaskBubble.swift" \
    "$project_dir/Sources/SpriteCanvas.swift" "$project_dir/Tests/CanvasTests.swift" -o "$project_dir/.build/canvas-tests"
  "$project_dir/.build/canvas-tests" --resources "$project_dir/Resources" --output-dir "$project_dir/qa/canvas-previews"
  exit 0
fi
/usr/bin/swiftc -swift-version 5 -module-cache-path "$project_dir/.build/module-cache" \
  "$project_dir/Sources/CompanionCore.swift" "$project_dir/Tests/CoreTests.swift" \
  -o "$project_dir/qa/core-tests"
"$project_dir/qa/core-tests"
/usr/bin/swiftc -swift-version 5 -module-cache-path "$project_dir/.build/module-cache" \
  "$project_dir/Sources/CompanionCore.swift" "$project_dir/Tests/LifeCoreTests.swift" \
  -o "$project_dir/qa/life-core-tests"
"$project_dir/qa/life-core-tests"
/usr/bin/swiftc -swift-version 5 -module-cache-path "$project_dir/.build/module-cache" \
  -framework Combine "$project_dir/Sources/CompanionCore.swift" "$project_dir/Sources/PetGameEngine.swift" \
  "$project_dir/Sources/PetPlayroomController.swift" "$project_dir/Tests/PlayroomTests.swift" \
  -o "$project_dir/.build/playroom-tests"
"$project_dir/.build/playroom-tests"
/usr/bin/swiftc -swift-version 5 -module-cache-path "$project_dir/.build/module-cache" \
  -framework AppKit -framework PDFKit -framework Combine \
  "$project_dir/Sources/FileAssistant.swift" "$project_dir/Tests/BridgeTests.swift" \
  -o "$project_dir/qa/bridge-tests"
"$project_dir/qa/bridge-tests"
/usr/bin/clang -O2 -target "${XIAOKE_ARCH:-$(uname -m)}-apple-macosx13.0" -c "$project_dir/Sources/Sensors.c" -o "$project_dir/.build/Sensors.o"
/usr/bin/swiftc -swift-version 5 -module-cache-path "$project_dir/.build/module-cache" \
  -import-objc-header "$project_dir/Sources/Sensors.h" -framework AppKit -framework Combine -framework IOKit \
  "$project_dir/Sources/HardwareMonitor.swift" "$project_dir/Tests/HardwareTests.swift" "$project_dir/.build/Sensors.o" \
  -o "$project_dir/qa/hardware-tests"
"$project_dir/qa/hardware-tests"
/usr/bin/swiftc -swift-version 5 -module-cache-path "$project_dir/.build/module-cache" \
  "$project_dir/Sources/PetWindowPlacement.swift" "$project_dir/Tests/WindowPlacementTests.swift" -o "$project_dir/qa/window-tests"
"$project_dir/qa/window-tests"
/usr/bin/swiftc -swift-version 5 -module-cache-path "$project_dir/.build/module-cache" \
  "$project_dir/Sources/RuntimeDiagnostics.swift" "$project_dir/Tests/RuntimeTests.swift" -o "$project_dir/qa/runtime-tests"
"$project_dir/qa/runtime-tests"
/usr/bin/swiftc -swift-version 5 -module-cache-path "$project_dir/.build/module-cache" \
  -framework Combine "$project_dir/Sources/AgentTaskMonitor.swift" "$project_dir/Sources/AgentEventBridge.swift" "$project_dir/Tests/CodexMonitorTests.swift" \
  -o "$project_dir/qa/codex-monitor-tests"
"$project_dir/qa/codex-monitor-tests"
/usr/bin/swiftc -swift-version 5 -module-cache-path "$project_dir/.build/module-cache" \
  -framework Combine "$project_dir/Sources/AgentTaskMonitor.swift" "$project_dir/Sources/AgentEventBridge.swift" "$project_dir/Sources/CodexTaskBubble.swift" \
  "$project_dir/Tests/TaskBubbleTests.swift" -o "$project_dir/qa/task-bubble-tests"
"$project_dir/qa/task-bubble-tests"

/usr/bin/swiftc -swift-version 5 -module-cache-path "$project_dir/.build/module-cache" \
  -framework Combine "$project_dir/Sources/AgentTaskMonitor.swift" "$project_dir/Sources/AgentEventBridge.swift" \
  "$project_dir/Tests/AgentBridgeTests.swift" -o "$project_dir/.build/agent-bridge-tests"
"$project_dir/.build/agent-bridge-tests"
python3 "$project_dir/Tests/test_cli.py"
