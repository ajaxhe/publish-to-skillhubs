#!/usr/bin/env bash
# publish-to-skillhubs.sh — 通用 Agent Skill 多平台发布
#
# Usage:
#   bash publish-to-skillhubs.sh --skill-dir /path/to/skill [options]
#
# Options:
#   --platform all|clawhub|agentskillhub|skillshubai|agentskillshub
#   --dry-run
#   --yes              跳过交互确认
#   --skip-git-push    不自动 commit/push

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOAD_CONFIG="$SCRIPT_DIR/load-config.py"

SKILL_DIR=""
DRY_RUN=false
TARGET_PLATFORM="all"
ASSUME_YES=false
SKIP_GIT_PUSH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill-dir) SKILL_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --platform) TARGET_PLATFORM="$2"; shift 2 ;;
    --yes) ASSUME_YES=true; shift ;;
    --skip-git-push) SKIP_GIT_PUSH=true; shift ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      if [ -z "$SKILL_DIR" ] && [ -d "$1" ]; then
        SKILL_DIR="$1"
        shift
      else
        echo "Unknown arg: $1"; exit 1
      fi
      ;;
  esac
done

if [ -z "$SKILL_DIR" ]; then
  echo "❌ 请指定 --skill-dir /path/to/skill"
  exit 1
fi

SKILL_DIR="$(cd "$SKILL_DIR" && pwd -P)"

if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
  echo "❌ SKILL.md 不存在: $SKILL_DIR"
  exit 1
fi

CFG_JSON="$(python3 "$LOAD_CONFIG" "$SKILL_DIR")"
read_cfg() {
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$1',''))" <<< "$CFG_JSON"
}
read_cfg_list() {
  python3 -c "import json,sys; d=json.load(sys.stdin); v=d.get('$1',[]); print(','.join(v) if isinstance(v,list) else v)" <<< "$CFG_JSON"
}
platform_enabled() {
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('platforms',{}).get('$1',{}).get('enabled', True))" <<< "$CFG_JSON"
}

SKILL_NAME="$(read_cfg skill_name)"
DISPLAY_NAME="$(read_cfg display_name)"
SKILL_VERSION="$(read_cfg version)"
GITHUB_REPO="$(read_cfg github_repo)"
GITHUB_REPO_URL="$(read_cfg github_repo_url)"
TAGS="$(read_cfg_list tags)"
CLAWSCAN_NOTE="$(read_cfg clawscan_note)"
PR_DESCRIPTION="$(read_cfg pr_description)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
log_info()    { echo -e "${GREEN}✅${NC} $*"; }
log_warn()    { echo -e "${YELLOW}⚠️ ${NC} $*"; }
log_error()   { echo -e "${RED}❌${NC} $*"; }
log_section() { echo -e "\n${BOLD}── $* ──────────────────────────${NC}"; }

run_or_dry() {
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN]${NC} $*"
  else
    eval "$@"
  fi
}

confirm() {
  if [ "$ASSUME_YES" = true ]; then return 0; fi
  read -r -p "$1 (y/N) " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

log_section "前置检查"
echo "Skill 目录:   $SKILL_DIR"
echo "Skill 名称:   $SKILL_NAME"
echo "GitHub 仓库:  ${GITHUB_REPO_URL:-（未检测到 remote）}"
echo "版本:         $SKILL_VERSION"
echo "平台:         $TARGET_PLATFORM"
echo "Dry Run:      $DRY_RUN"

if [ -z "$GITHUB_REPO" ] && [ "$TARGET_PLATFORM" != "clawhub" ]; then
  log_warn "未检测到 github_repo，agentskillhub/skillshubai 可能失败"
  log_warn "请在 skill 目录添加 publish.json 或配置 git remote origin"
fi

# ── Step 0: Git sync ─────────────────────────────────────────────────────
if [ "$SKIP_GIT_PUSH" = false ] && [ -d "$SKILL_DIR/.git" ]; then
  log_section "Step 0: 同步到 GitHub"
  cd "$SKILL_DIR"
  GIT_STATUS=$(git status --porcelain)
  if [ -n "$GIT_STATUS" ]; then
    log_warn "有未提交变更:"
    git status --short
    if confirm "自动 commit & push？"; then
      run_or_dry 'git add -A && git commit -m "chore: prepare for SkillHub publishing" && git push'
    fi
  else
    AHEAD=$(git rev-list origin/main..HEAD --count 2>/dev/null || echo "0")
    if [ "$AHEAD" -gt 0 ]; then
      run_or_dry 'git push'
      log_info "已推送 ${AHEAD} 个提交"
    else
      log_info "已与 GitHub 同步"
    fi
  fi
fi

publish_agentskillhub() {
  log_section "Platform: agentskillhub.dev"
  if [ "$(platform_enabled agentskillhub)" != "True" ]; then
    log_warn "publish.json 中已禁用 agentskillhub"; return
  fi
  if [ -z "$GITHUB_REPO" ]; then log_warn "缺少 github_repo，跳过"; return; fi

  SKHUB_AUTH="$HOME/.skhub/auth.json"
  AUTH_HEADER=""
  if [ -f "$SKHUB_AUTH" ]; then
    SKHUB_TOKEN=$(python3 -c "
import json
for cred in json.load(open('$SKHUB_AUTH')).get('credentials',{}).values():
    if cred.get('token'): print(cred['token']); break
" 2>/dev/null || echo "")
    [ -n "$SKHUB_TOKEN" ] && AUTH_HEADER="Authorization: Bearer ${SKHUB_TOKEN}"
  fi

  CURL_AUTH=()
  [ -n "$AUTH_HEADER" ] && CURL_AUTH=(-H "$AUTH_HEADER")

  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] POST import repoFullName=${GITHUB_REPO} selectedPaths=[${SKILL_NAME}]"
    return
  fi

  IMPORT_BODY="{\"repoFullName\":\"${GITHUB_REPO}\",\"selectedPaths\":[\"${SKILL_NAME}\"]}"
  # Root-level skill (SKILL.md at repo root): use repo name as path
  if [ ! -d "${SKILL_DIR}/${SKILL_NAME}" ] && [ -f "${SKILL_DIR}/SKILL.md" ]; then
    IMPORT_BODY="{\"repoFullName\":\"${GITHUB_REPO}\",\"selectedPaths\":[\".\"]}"
  fi

  RESPONSE=$(curl -s -o /tmp/ash_import.json -w "%{http_code}" -X POST \
    "https://agentskillhub.dev/api/v1/repos/import" \
    -H "Content-Type: application/json" \
    "${CURL_AUTH[@]}" \
    -d "$IMPORT_BODY" || echo "000")
  BODY=$(cat /tmp/ash_import.json 2>/dev/null || echo "{}")
  echo "HTTP $RESPONSE: $(echo "$BODY" | head -c 300)"

  if [ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "201" ]; then
    log_info "agentskillhub.dev 导入成功"
  else
    log_warn "agentskillhub.dev 导入失败（平台侧 GitHub 集成可能异常）"
    echo "  → 手动导入: https://agentskillhub.dev"
    echo "  → Add Skills → ${GITHUB_REPO_URL}"
    echo "  → 或运行: skhub add ${GITHUB_REPO_URL}"
  fi
}

publish_skillshubai() {
  log_section "Platform: skills-hub.ai"
  if [ "$(platform_enabled skillshubai)" != "True" ]; then
    log_warn "publish.json 中已禁用 skillshubai"; return
  fi

  SKILLSHUB_CONFIG="$HOME/.skills-hub/config.json"
  if [ ! -f "$SKILLSHUB_CONFIG" ]; then
    log_warn "未找到 ~/.skills-hub/config.json"
    echo "  → https://skills-hub.ai/settings/api-keys 创建 API Key"
    return
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] POST https://api.skills-hub.ai/api/v1/skills (REST API)"
    return
  fi

  python3 - "$SKILL_DIR" "$GITHUB_REPO_URL" "$SKILLSHUB_CONFIG" <<'PY'
import json, re, sys, urllib.request, urllib.error
skill_dir, repo_url, cfg_path = sys.argv[1:4]
token = json.load(open(cfg_path)).get("apiKey") or ""
if not token:
    print("❌ skills-hub API key 为空"); sys.exit(1)

content = open(f"{skill_dir}/SKILL.md").read()
fm_match = re.match(r'^---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
fm, body = fm_match.group(1), content[fm_match.end():]

def get_field(name, text):
    m = re.search(rf'^{name}:\s*(.+)$', text, re.MULTILINE)
    if not m:
        return ""
    val = m.group(1).strip().strip('"')
    # YAML 块标量标记（>-, >, |, |- 等）不是真实值，回退给调用方
    if val[:1] in (">", "|"):
        return ""
    return val

tags_m = re.search(r'^tags:\s*(.+)$', fm, re.MULTILINE)
tags = [t.strip() for t in (tags_m.group(1).split(",") if tags_m else [])]
slug = get_field("name", fm)

payload = {
    "name": slug,
    "description": get_field("description", fm)[:500] or slug,
    "version": get_field("version", fm) or "1.0.0",
    "categorySlug": get_field("category", fm) or "productivity",
    "platforms": ["CLAUDE_CODE", "CURSOR", "GEMINI_CLI"],
    "instructions": body.strip()[:8000],
    "visibility": "PUBLIC",
    "tags": tags[:10],
    "githubRepoUrl": repo_url,
}

def api(method, path, data=None):
    req = urllib.request.Request(
        f"https://api.skills-hub.ai/api/v1/skills{path}",
        data=json.dumps(data).encode() if data is not None else None,
        headers={"Content-Type": "application/json", "Authorization": f"ApiKey {token}", "User-Agent": "Mozilla/5.0"},
        method=method,
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())

code, data = api("GET", f"/{slug}")
if code == 404:
    code, data = api("POST", "", payload)
    if code in (200, 201):
        pub_code, pub_data = api("POST", f"/{slug}/publish", {})
        if pub_code not in (200, 201):
            print(f"⚠️ publish HTTP {pub_code}: {pub_data}")
elif code == 200:
    if data.get("status") == "DRAFT":
        pub_code, pub_data = api("POST", f"/{slug}/publish", {})
    code, data = api("POST", f"/{slug}/versions", payload)
    if code in (200, 201) and data.get("status") == "DRAFT":
        api("POST", f"/{slug}/publish", {})

if code in (200, 201):
    print(f"✅ skills-hub.ai → https://skills-hub.ai/skills/{slug}")
else:
    print(f"❌ skills-hub HTTP {code}: {data}")
    sys.exit(1)
PY
  log_info "skills-hub.ai 发布完成"
}

publish_clawhub() {
  log_section "Platform: clawhub.ai"
  if [ "$(platform_enabled clawhub)" != "True" ]; then
    log_warn "publish.json 中已禁用 clawhub"; return
  fi

  if ! command -v clawhub &>/dev/null; then
    run_or_dry "npm install -g @clawhub/cli"
  fi

  CLAWHUB_USER=$(clawhub whoami 2>/dev/null | grep -v '^-' | tr -d '[:space:]' || echo "")
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] clawhub --workdir $(dirname "${SKILL_DIR}") publish ${SKILL_NAME} --version ${SKILL_VERSION}"
    return
  fi

  if [ -n "$CLAWHUB_USER" ]; then
    log_info "已登录 clawhub.ai（${CLAWHUB_USER}）"
  else
    log_warn "未登录 clawhub.ai — 需要 GitHub OAuth"
    if ! confirm "运行 clawhub login？"; then return; fi
    clawhub login
    if ! confirm "登录完成了吗？"; then return; fi
  fi

  SKILLS_PARENT="$(dirname "${SKILL_DIR}")"
  TAGS_CLAW="${TAGS},latest"
  CLAWSCAN_FLAG=""
  if [ -n "$CLAWSCAN_NOTE" ]; then
    CLAWSCAN_FLAG="--clawscan-note '${CLAWSCAN_NOTE}'"
  fi

  if [ "$DRY_RUN" = false ]; then
    run_or_dry "clawhub --workdir '${SKILLS_PARENT}' publish '${SKILL_NAME}' \
      --slug '${SKILL_NAME}' \
      --name '${DISPLAY_NAME}' \
      --version '${SKILL_VERSION}' \
      --changelog 'See README.md' \
      --tags '${TAGS_CLAW}' \
      ${CLAWSCAN_FLAG}"
    log_info "clawhub.ai → https://clawhub.ai/skills/${SKILL_NAME}"
  else
    echo "[DRY RUN] clawhub --workdir ${SKILLS_PARENT} publish ${SKILL_NAME} --version ${SKILL_VERSION}"
  fi
}

publish_agentskillshub_pr() {
  log_section "Platform: agent-skills-hub (GitHub PR)"
  if [ "$(platform_enabled agentskillshub)" != "True" ]; then
    log_warn "publish.json 中已禁用 agentskillshub PR"; return
  fi
  if ! command -v gh &>/dev/null; then
    log_warn "需要 gh CLI: brew install gh && gh auth login"; return
  fi
  if ! gh auth status &>/dev/null 2>&1; then
    log_warn "gh 未登录"; return
  fi

  FORK_DIR="/tmp/agent-skills-hub-fork-$$"
  TARGET_SKILL_DIR="${FORK_DIR}/skills/${SKILL_NAME}"

  run_or_dry "gh repo fork agent-skills-hub/agent-skills-hub --clone --fork-name agent-skills-hub-fork --remote=true || true"
  run_or_dry "git clone https://github.com/\$(gh api user --jq .login)/agent-skills-hub ${FORK_DIR} 2>/dev/null || git clone https://github.com/agent-skills-hub/agent-skills-hub ${FORK_DIR}"

  if [ "$DRY_RUN" = false ]; then
    mkdir -p "$TARGET_SKILL_DIR"
    for item in SKILL.md README.md config.json.example scripts references .gitignore LICENSE; do
      [ -e "${SKILL_DIR}/${item}" ] && cp -r "${SKILL_DIR}/${item}" "$TARGET_SKILL_DIR/"
    done
    rm -f "$TARGET_SKILL_DIR/scripts/publish-to-skillhubs.sh" "$TARGET_SKILL_DIR/scripts/setup-tokens.sh" 2>/dev/null || true

    cd "$FORK_DIR"
    git config user.email "$(git config --global user.email || echo 'agent@github.com')"
    git config user.name "$(git config --global user.name || echo 'GitHub Actions')"
    BRANCH="add-${SKILL_NAME}-$(date +%Y%m%d)"
    git checkout -b "$BRANCH"
    git add "skills/${SKILL_NAME}/"
    git commit -m "feat: add ${SKILL_NAME}

${PR_DESCRIPTION}

Source: ${GITHUB_REPO_URL}"
    git push origin "$BRANCH"
    gh pr create \
      --repo "agent-skills-hub/agent-skills-hub" \
      --title "feat: add ${SKILL_NAME}" \
      --body "${PR_DESCRIPTION}

Source: ${GITHUB_REPO_URL}"
    log_info "PR → https://github.com/agent-skills-hub/agent-skills-hub/pulls"
    cd "$SKILL_DIR"
    rm -rf "$FORK_DIR"
  fi
}

log_section "开始发布 → ${TARGET_PLATFORM}"
[ "$DRY_RUN" = true ] && echo -e "${YELLOW}🔍 DRY RUN 模式${NC}\n"

case "$TARGET_PLATFORM" in
  all)
    publish_agentskillhub
    publish_skillshubai
    publish_clawhub
    publish_agentskillshub_pr
    ;;
  agentskillhub)   publish_agentskillhub ;;
  skillshubai)     publish_skillshubai ;;
  clawhub)         publish_clawhub ;;
  agentskillshub)  publish_agentskillshub_pr ;;
  *)
    log_error "未知平台: $TARGET_PLATFORM"
    echo "支持: all | agentskillhub | skillshubai | clawhub | agentskillshub"
    exit 1
    ;;
esac

log_section "完成 🎉"
echo ""
echo "📍 平台链接："
echo "  clawhub.ai        → https://clawhub.ai/skills/${SKILL_NAME}"
echo "  agentskillhub.dev → https://agentskillhub.dev/skills/${SKILL_NAME}"
echo "  skills-hub.ai     → https://skills-hub.ai/skills/${SKILL_NAME}"
echo "  agent-skills-hub  → https://github.com/agent-skills-hub/agent-skills-hub/pulls"
