#!/usr/bin/env bash
# prepare-clawhub-staging.sh — 为 ClawHub 创建干净副本（过滤产物、私有配置、二进制）
#
# 实际过滤规则在 scripts/policy.py（与发布前校验 preflight.py 共用同一份策略），
# 这里只做参数校验与调用，避免两套规则各自漂移。
#
# Usage:
#   bash prepare-clawhub-staging.sh --skill-dir /path/to/skill [--staging-dir /path/to/staging]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY_META="$SCRIPT_DIR/apply-platform-meta.py"

SKILL_DIR=""
STAGING_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill-dir) SKILL_DIR="$2"; shift 2 ;;
    --staging-dir) STAGING_DIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [ -z "$SKILL_DIR" ]; then
  echo "Usage: $0 --skill-dir /path/to/skill [--staging-dir /path/to/staging]"
  exit 1
fi

SKILL_DIR="$(cd "$SKILL_DIR" && pwd -P)"
SKILL_NAME="$(basename "$SKILL_DIR")"

if [ -z "$STAGING_DIR" ]; then
  STAGING_DIR="$(dirname "$SKILL_DIR")/${SKILL_NAME}-clawhub"
fi

python3 "$APPLY_META" --skill-dir "$SKILL_DIR" --out-dir "$STAGING_DIR" --meta '{}'

echo "✅ ClawHub staging ready: $STAGING_DIR"
echo "   Publish with:"
echo "   bash $SCRIPT_DIR/publish-to-skillhubs.sh \\"
echo "     --skill-dir '$STAGING_DIR' --platform clawhub"
