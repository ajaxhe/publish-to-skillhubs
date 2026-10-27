#!/usr/bin/env bash
# install-workflow.sh — 将 CI workflow 安装到目标 skill 仓库
#
# Usage:
#   bash install-workflow.sh --skill-dir /path/to/skill

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLHUBS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$SKILLHUBS_DIR/templates/publish-to-skillhubs.yml"

SKILL_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill-dir) SKILL_DIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [ -z "$SKILL_DIR" ]; then
  echo "Usage: $0 --skill-dir /path/to/skill"
  exit 1
fi

SKILL_DIR="$(cd "$SKILL_DIR" && pwd -P)"
TARGET="$SKILL_DIR/.github/workflows/publish-to-skillhubs.yml"

if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
  echo "❌ SKILL.md not found in $SKILL_DIR"
  exit 1
fi

mkdir -p "$(dirname "$TARGET")"
cp "$TEMPLATE" "$TARGET"

# 连同校验脚本一起装进 .github/skill-preflight/：CI 的 preflight job 直接跑它，
# 保证线上发布和本地发布用的是同一份策略（.github/ 不会进 skill 包）。
PREFLIGHT_DIR="$SKILL_DIR/.github/skill-preflight"
mkdir -p "$PREFLIGHT_DIR"
cp "$SCRIPT_DIR/policy.py" "$SCRIPT_DIR/preflight.py" "$PREFLIGHT_DIR/"

echo "✅ Installed: $TARGET"
echo "✅ Installed: $PREFLIGHT_DIR/{policy.py,preflight.py}"
echo ""
echo "Next steps:"
echo "  1. Ensure publish.json exists in skill root"
echo "  2. bash $SCRIPT_DIR/setup-tokens.sh --repo \$(python3 $SCRIPT_DIR/load-config.py '$SKILL_DIR' | python3 -c \"import sys,json; print(json.load(sys.stdin)['github_repo'])\"))"
echo "  3. git add .github publish.json && git commit && git push"
