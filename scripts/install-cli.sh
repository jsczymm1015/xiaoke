#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
command -v python3 >/dev/null || { print '请先安装 Python 3（https://www.python.org/downloads/macos/）'; exit 1; }
mkdir -p "$HOME/.local/bin"
cp "$project_dir/cli/xiaoke" "$HOME/.local/bin/xiaoke"
chmod 755 "$HOME/.local/bin/xiaoke"
print '已安装 ~/.local/bin/xiaoke'
print '若找不到命令，请在 ~/.zshrc 加入：export PATH="$HOME/.local/bin:$PATH"'
