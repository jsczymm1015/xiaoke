#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
# LaunchServices owns the app; no long-lived shell or Codex execution session owns it.
/usr/bin/open -a "$project_dir/dist/小可桌宠.app"
