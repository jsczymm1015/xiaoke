# 安装、升级与排错

## 1. 检查系统

- Apple Silicon（M1/M2/M3/M4 等）Mac。
- macOS 13 或更新版本。
- 运行桌宠不需要 Xcode、Python 或任何 Agent 账号。
- 运行 `xiaoke` 桥接命令需要 Python 3.9+；从源码构建还需要 Xcode Command Line Tools。

## 2. 下载和校验

从 [官方项目 Releases](https://github.com/jsczymm1015/xiaoke/releases/latest) 下载 ZIP 和 `SHA256SUMS.txt`，放在同一个目录。在终端进入该目录：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

应显示 ZIP 文件 `OK`。校验失败时重新下载，不要运行损坏包。解压后将 `小可桌宠.app` 拖入「应用程序」。

本版本是 ad-hoc 本地签名，不是 Apple 公证发行版。macOS 可能提示无法验证开发者。确认来源后，可按「系统设置 → 隐私与安全性」提供的“仍要打开”流程处理；不同 macOS 版本按钮略有差异。不需要关闭 SIP、全局关闭 Gatekeeper 或以管理员身份长期运行。

## 3. 第一次打开

- 桌面出现角色；双击打开面板。
- 右键角色：小食堂、小窝、衣橱、小游戏、硬件等。
- 菜单栏「可」→ 找回角色，可恢复窗口位置。
- 关闭面板不会退出；通过「设置 → 退出桌宠」彻底退出。
- 设置可调整大小、跟随鼠标、鼠标穿透、免打扰、Agent 任务提醒与任务气泡。
- 系统通知为可选项，不授权也能使用角色气泡。

![工作状态](screenshots/working.png)

## 4. 安装 CLI（接入其他 Agent 时）

检查 `python3 --version`，要求 3.9 或更新。桥接脚本不安装第三方包。

```sh
mkdir -p "$HOME/.local/bin"
cp '/Applications/小可桌宠.app/Contents/Resources/cli/xiaoke' "$HOME/.local/bin/xiaoke"
chmod 755 "$HOME/.local/bin/xiaoke"
export PATH="$HOME/.local/bin:$PATH"
xiaoke doctor
```

将 `export PATH="$HOME/.local/bin:$PATH"` 写入 `~/.zshrc` 并重新打开终端。已有相同 PATH 配置无需重复添加。源码用户可以执行 `/bin/zsh scripts/install-cli.sh`。

测试连通性：

```sh
xiaoke run --provider demo --title '小可连接测试' -- python3 -c 'import time; time.sleep(8)'
```

小可应在约 2 秒内进入工作状态，进程结束后显示完成提醒。若当前处于免打扰，工作动作仍可能发生，但气泡或提醒会隐藏。

继续阅读 [Agent 接入](AGENTS.md)。

## 5. 升级与备份

1. 在旧版「设置」中导出备份。
2. 选择「退出桌宠」。
3. 用新包替换应用；从“小柯”升级时，把旧的 `小柯桌宠.app` 移到废纸篓，保留新的 `小可桌宠.app`。
4. 重新打开；存档目录和 bundle ID 保持兼容，不必导入备份。
5. 重新运行安装 CLI 的复制命令更新脚本。如果 CLI 路径和 Python 路径未变，已有 Hooks 不需要重装。

存档目录：`~/Library/Application Support/XiaoKeCompanion/`。不要把此目录提交到 GitHub。导出的备份可能包含个人待办、便签和快捷入口。

## 6. 常见问题

| 问题 | 检查方法 |
|---|---|
| 找不到角色 | 菜单栏「可」→ 显示并找回；检查是否隐藏或穿透 |
| `command not found: xiaoke` | 检查 `~/.local/bin` 是否加入 PATH，或使用完整路径运行 |
| 没有 Python | 安装 Python 3.9+；仅 Codex 自动监听无需 Python |
| Agent 执行了但没动 | 确认应用正在运行、Agent 提醒已开启、CLI 与应用使用同一用户/数据目录 |
| 没有气泡 | 开启任务气泡、自动提醒，检查免打扰；不是所有任务都有计划步骤 |
| Codex 没被观察到 | 需有本机 `~/.codex/sessions` 记录；新文件发现最多约 10 秒；未来日志格式可能不兼容 |
| Claude Code Hooks 未生效 | 重启 Claude Code，检查配置位置及版本支持；执行 `xiaoke doctor`；不要同时包装同一会话 |
| 任务结束后还忙碌 | CLI 包装器等待进程退出；常驻交互进程需用 Hooks；异常终止在 TTL 后清理 |
| 硬件字段空白 | 仅显示本机成功读取的传感器，不同机型支持不同 |
| 两只角色或打开了旧版本 | 退出旧 app；Codex 内置 Pets 与小可是不同程序 |

## 7. 卸载

先退出应用，把 `小可桌宠.app` 和 `~/.local/bin/xiaoke` 移到废纸篓。手动移除 Claude 配置中命令结尾为 `xiaoke hook claude-code` 的条目，保留其他 Hooks；也可在确认没有后续配置修改时恢复安装器生成的备份。

存档默认保留，便于重装恢复。如需彻底删除，请先导出备份，再自行处理上述 Application Support 目录。
