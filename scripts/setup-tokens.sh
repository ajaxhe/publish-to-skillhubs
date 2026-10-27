#!/usr/bin/env bash
# setup-tokens.sh — 一次性：提取各平台 token 写入 GitHub Secrets
#
# Usage:
#   bash setup-tokens.sh --repo owner/skill-repo

set -euo pipefail

REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [ -z "$REPO" ]; then
  echo "Usage: $0 --repo owner/skill-repo"
  exit 1
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}✅${NC} $*"; }
log_warn()    { echo -e "${YELLOW}⚠️ ${NC} $*"; }
log_section() { echo -e "\n${BOLD}── $* ──────────────────────────────${NC}"; }

log_section "前置检查"
if ! command -v gh &>/dev/null; then
  log_warn "需要 GitHub CLI: brew install gh && gh auth login"
  exit 1
fi
if ! gh auth status &>/dev/null 2>&1; then
  gh auth login
fi
log_info "GitHub CLI 已登录（$(gh api user --jq .login)）→ repo: $REPO"

log_section "Token 1: clawhub.ai"
CLAWHUB_CONFIG="$HOME/Library/Application Support/clawhub/config.json"
[ ! -f "$CLAWHUB_CONFIG" ] && CLAWHUB_CONFIG="$HOME/.config/clawhub/config.json"
if [ -f "$CLAWHUB_CONFIG" ]; then
  CLAWHUB_TOKEN=$(python3 -c "import json; d=json.load(open('$CLAWHUB_CONFIG')); print(d.get('token',''))" 2>/dev/null)
  if [ -n "$CLAWHUB_TOKEN" ]; then
    echo "$CLAWHUB_TOKEN" | gh secret set CLAWHUB_TOKEN --repo "$REPO"
    log_info "CLAWHUB_TOKEN 已写入"
  else
    log_warn "token 为空，运行: npm i -g @clawhub/cli && clawhub login"
  fi
else
  log_warn "未找到 clawhub 配置，运行: clawhub login"
fi

log_section "Token 2: agentskillhub.dev"
SKHUB_AUTH="$HOME/.skhub/auth.json"
if [ ! -f "$SKHUB_AUTH" ]; then
  echo "运行 skhub login..."
  skhub login 2>/dev/null || log_warn "skhub CLI 未安装: npm i -g skhub"
fi
if [ -f "$SKHUB_AUTH" ]; then
  AGENTSKILLHUB_TOKEN=$(python3 -c "
import json
data=json.load(open('$SKHUB_AUTH'))
for cred in data.get('credentials',{}).values():
    if cred.get('token'):
        print(cred['token']); break
" 2>/dev/null)
  if [ -n "$AGENTSKILLHUB_TOKEN" ]; then
    echo "$AGENTSKILLHUB_TOKEN" | gh secret set AGENTSKILLHUB_TOKEN --repo "$REPO"
    log_info "AGENTSKILLHUB_TOKEN 已写入"
  fi
fi

log_section "Token 3: skills-hub.ai"
SKILLSHUB_CONFIG="$HOME/.skills-hub/config.json"
if [ -f "$SKILLSHUB_CONFIG" ]; then
  SKILLSHUBAI_TOKEN=$(python3 -c "import json; d=json.load(open('$SKILLSHUB_CONFIG')); print(d.get('apiKey') or d.get('accessToken',''))" 2>/dev/null)
  if [ -n "$SKILLSHUBAI_TOKEN" ]; then
    echo "$SKILLSHUBAI_TOKEN" | gh secret set SKILLSHUBAI_TOKEN --repo "$REPO"
    log_info "SKILLSHUBAI_TOKEN 已写入"
  fi
else
  echo "访问 https://skills-hub.ai/settings/api-keys 创建 API Key"
  read -r -p "粘贴 API Key（留空跳过）: " SKILLSHUBAI_INPUT
  if [ -n "$SKILLSHUBAI_INPUT" ]; then
    mkdir -p "$HOME/.skills-hub"
    echo "{\"apiUrl\": \"https://api.skills-hub.ai\", \"apiKey\": \"$SKILLSHUBAI_INPUT\"}" > "$SKILLSHUB_CONFIG"
    echo "$SKILLSHUBAI_INPUT" | gh secret set SKILLSHUBAI_TOKEN --repo "$REPO"
    log_info "SKILLSHUBAI_TOKEN 已写入"
  fi
fi

log_section "Token 4: skillhub.cn"
SKILLHUB_CRED="$HOME/.skillhub/credentials.json"
SKILLHUB_TOKEN=""
if [ -f "$SKILLHUB_CRED" ]; then
  SKILLHUB_TOKEN=$(python3 -c "
import json
print((json.load(open('$SKILLHUB_CRED')).get('user') or {}).get('token',''))
" 2>/dev/null)
fi
if [ -z "$SKILLHUB_TOKEN" ] && [ -n "${SKILLHUB_TOKEN_ENV:-}" ]; then
  SKILLHUB_TOKEN="$SKILLHUB_TOKEN_ENV"
fi
if [ -z "$SKILLHUB_TOKEN" ]; then
  echo "访问 https://skillhub.cn/dashboard/keys 创建 API Token（skh_ 开头，需先实名认证）"
  read -r -p "粘贴 skh_ Token（留空跳过）: " SKILLHUB_INPUT
  SKILLHUB_TOKEN="$SKILLHUB_INPUT"
fi
if [ -n "$SKILLHUB_TOKEN" ]; then
  echo "$SKILLHUB_TOKEN" | gh secret set SKILLHUB_TOKEN --repo "$REPO"
  log_info "SKILLHUB_TOKEN 已写入"
else
  log_warn "跳过 skillhub.cn（未提供 skh_ Token）"
fi

log_section "已配置的 Secrets"
gh secret list --repo "$REPO" 2>/dev/null | grep -E "CLAWHUB|AGENTSKILLHUB|SKILLSHUBAI|SKILLHUB" || true
log_info "完成！推送 main 后 GitHub Actions 将自动发布。"
