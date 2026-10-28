# 小可 0.3.0 · 通用 Agent 桌面伴侣

从“小柯”更名为“小可”，保留原存档兼容。

- Codex 自动监听、Claude Code Hooks、任意 CLI 包装、自定义 v1 事件协议。
- Agent 工作写字、空闲低头打盹，保留喂养、小窝、衣橱、小游戏、待办和专注功能。
- 修复首次打开面板、切换小窝/衣橱时重复解码动画造成的卡顿；共享素材缓存、暂停隐藏预览刷新。
- 点击互动复用正常人物帧，避免触摸时变大。
- 中文安装、接入、升级、卸载、排错文档与真实界面渲染截图。

## 安装

下载 `xiaoke-0.3.0-macos-arm64.zip`，解压后把 `小可桌宠.app` 放进「应用程序」。Apple Silicon / macOS 13+。升级前退出旧版；存档目录保持不变。

此包使用 ad-hoc 本地签名，尚未经 Apple 公证。请阅读仓库 `docs/INSTALL.md`，并使用 `SHA256SUMS.txt` 检查文件。无需关闭系统安全保护。

其他 Agent 的 CLI 桥接需要 Python 3.9+；脚本已随 app 提供。Codex 自动监听不需要 Python。

## 验证边界

业务、协议、CLI、137 项原生画布断言、14 项喂养菜单断言通过；本机通用事件与 Codex 并行显示/完成提醒已验收。Claude Code Hooks 仅通过模拟输入和配置合并测试，真实 Claude Code 会话尚未端到端验证。详见 `docs/VALIDATION.md`。
