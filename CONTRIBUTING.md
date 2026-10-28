# 参与开发

代码结构：

- `Sources/AgentTaskMonitor.swift`：统一监视器与 Codex 只读适配器。
- `Sources/AgentEventBridge.swift`：通用 v1 文件事件读取、校验、过期和去重。
- `cli/xiaoke`：Python 标准库桥接、命令包装、Claude Code Hooks 安装。
- `Sources/SpriteCanvas.swift`：原生透明桌宠、动画与互动。
- `Sources/CompanionCore.swift`：存档、养成、专注等业务状态。
- `Sources/CompanionPanel.swift` / `PetLifeViews.swift`：SwiftUI 面板。

## 测试

```sh
/bin/zsh scripts/test.sh                    # 纯逻辑、适配器与 CLI 测试
/bin/zsh scripts/test.sh --native-only      # 需要 macOS 图形会话的画布测试
/bin/zsh scripts/test.sh --feeding-native-only
/bin/zsh scripts/build.sh                  # 测试 + 构建 + plist/签名验证
python3 Tests/test_cli.py                   # 只运行 CLI 测试
```

硬件真实采集另行执行 `./qa/hardware-tests --hardware-test --require-smc`，不等同于格式测试。

`qa/`、`.build/`、`dist/`、个人存档、Hooks 配置和日志不提交。测试使用临时目录；应用开发可通过 `XIAOKE_DATA_DIR` 隔离数据。截图重建脚本 `scripts/screenshots.sh` 只使用演示状态，不读取真实存档。

首次公开版保留旧 bundle ID、存档目录与部分 Codable 字段名（例如 codexTaskReminders），避免破坏旧用户数据；UI 品牌与统一事件类型已改为小可 / Agent。这些内部兼容字段不限制适配器来源。

提交新适配器请包含真实边界说明；模拟测试通过不能写成真实厂商端到端验证。建议先开 Issue 描述协议映射，再发 PR。
