#!/usr/bin/env bash
# prepare-clawhub-staging.sh — 为 ClawHub 创建干净副本（过滤二进制与私有配置）
#
# Usage:
#   bash prepare-clawhub-staging.sh --skill-dir /path/to/skill [--staging-dir /path/to/staging]

set -euo pipefail

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

if [ -d "$STAGING_DIR" ]; then
  rm -rf "$STAGING_DIR"
fi

mkdir -p "$STAGING_DIR"

rsync -a \
  --exclude='.git/' \
  --exclude='.gitignore' \
  --exclude='out/' \
  --exclude='config.json' \
  --exclude='config.json.example' \
  --exclude='publish.json' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  --exclude='*.png' \
  --exclude='*.jpg' \
  --exclude='*.jpeg' \
  --exclude='*.gif' \
  --exclude='*.webp' \
  --exclude='*.pdf' \
  --exclude='*.zip' \
  --exclude='*.tar.gz' \
  --exclude='articles/' \
  --exclude='.workbuddy/' \
  --exclude='.github/workflows/publish-to-skillhubs.yml' \
  --exclude='scripts/publish-to-skillhubs.sh' \
  --exclude='scripts/setup-tokens.sh' \
  "$SKILL_DIR/" "$STAGING_DIR/"

echo "✅ ClawHub staging ready: $STAGING_DIR"
echo "   Publish with:"
echo "   bash ~/.agents/skills/publish-to-skillhubs/scripts/publish-to-skillhubs.sh \\"
echo "     --skill-dir '$STAGING_DIR' --platform clawhub"
