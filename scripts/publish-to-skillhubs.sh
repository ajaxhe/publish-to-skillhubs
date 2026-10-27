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
PREPARE_CLAWHUB="$SCRIPT_DIR/prepare-clawhub-staging.sh"

SKILL_DIR=""
DRY_RUN=false
TARGET_PLATFORM="all"
ASSUME_YES=false
SKIP_GIT_PUSH=false
FAILED_PLATFORMS=()

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
CLAWHUB_OWNER="$(read_cfg clawhub_owner)"
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
elif [ "$SKIP_GIT_PUSH" = false ] && [ ! -d "$SKILL_DIR/.git" ]; then
  log_warn "Skill 目录不是 Git 工作区，无法校验本地内容是否已推送；将使用 ${GITHUB_REPO_URL:-配置中的远端仓库}"
fi

publish_agentskillhub() {
  log_section "Platform: agentskillhub.dev"
  if [ "$(platform_enabled agentskillhub)" != "True" ]; then
    log_warn "publish.json 中已禁用 agentskillhub"; return
  fi
  if [ -z "$GITHUB_REPO" ]; then log_warn "缺少 github_repo，跳过"; return; fi

  SKHUB_AUTH="$HOME/.skhub/auth.json"

  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] POST analyze url=${GITHUB_REPO_URL}，再按检测到的 path 调用 import"
    return
  fi

  # Always analyze first. AgentSkillHub represents a root-level SKILL.md as
  # path "", not "."; guessing the path makes otherwise valid repositories fail.
  python3 - "$GITHUB_REPO" "$GITHUB_REPO_URL" "$SKILL_NAME" "$SKHUB_AUTH" <<'PY'
import json, sys, urllib.error, urllib.request

repo, repo_url, skill_name, auth_path = sys.argv[1:5]
token = ""
try:
    credentials = json.load(open(auth_path)).get("credentials", {}).values()
    token = next((item.get("token") for item in credentials if item.get("token")), "")
except (FileNotFoundError, json.JSONDecodeError):
    pass
headers = {
    "Content-Type": "application/json",
    # Cloudflare 前置拦截非浏览器 UA（返回 403 "error code: 1010"），必须伪装 UA
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
    "Accept": "application/json",
}
if token:
    headers["Authorization"] = f"Bearer {token}"

def post(path, payload):
    request = urllib.request.Request(
        f"https://agentskillhub.dev/api/v1/repos/{path}",
        data=json.dumps(payload).encode(),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request) as response:
            return response.status, json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            body = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            body = {"error": raw.decode(errors="replace")[:500]}
        return error.code, body

code, analysis = post("analyze", {"url": repo_url})
if code != 200:
    print(f"❌ analyze HTTP {code}: {analysis}")
    raise SystemExit(1)

skills = analysis.get("skills") or []
skill = next(
    (item for item in skills if item.get("slug") == skill_name or item.get("name") == skill_name),
    skills[0] if len(skills) == 1 else None,
)
if not skill:
    print(f"❌ 仓库未检测到目标 Skill：{skill_name}；检测结果={skills}")
    raise SystemExit(1)

selected_path = skill.get("path", "")
code, result = post(
    "import",
    {"repoFullName": analysis.get("repoFullName") or repo, "selectedPaths": [selected_path]},
)
failed = result.get("failed") or []
if code not in (200, 201) or failed:
    print(f"❌ import HTTP {code}: {result}")
    raise SystemExit(1)

counts = {key: len(result.get(key) or []) for key in ("imported", "updated", "reused")}
print(f"✅ agentskillhub.dev 导入成功（path={selected_path!r}, {counts}）")
PY
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

  if ! python3 - "$SKILL_DIR" "$GITHUB_REPO_URL" "$SKILLSHUB_CONFIG" <<'PY'
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
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            body = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            body = {"error": raw.decode(errors="replace")[:500]}
        return e.code, body

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
elif code == 409 and "already exists" in json.dumps(data).lower():
    print(f"✅ skills-hub.ai 版本 {payload['version']} 已存在，无需重复发布")
else:
    print(f"❌ skills-hub HTTP {code}: {data}")
    sys.exit(1)
PY
  then
    return 1
  fi
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

  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] clawhub --workdir $(dirname "${SKILL_DIR}") publish ${SKILL_NAME} --version ${SKILL_VERSION}"
    return
  fi

  if CLAWHUB_USER=$(clawhub whoami 2>&1); then
    CLAWHUB_USER=$(printf '%s\n' "$CLAWHUB_USER" | tr '\n' ' ')
    log_info "已登录 clawhub.ai（${CLAWHUB_USER}）"
  else
    log_warn "未登录 clawhub.ai — 需要 GitHub OAuth"
    if [ "$ASSUME_YES" = true ]; then
      log_error "非交互模式不会自动打开 OAuth；请先手动运行 clawhub login"
      return 1
    fi
    if ! confirm "运行 clawhub login？"; then return; fi
    clawhub login
    if ! clawhub whoami >/dev/null 2>&1; then
      log_error "clawhub 登录校验失败"
      return 1
    fi
  fi

  STAGING_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/publish-to-skillhubs.XXXXXX")
  PUBLISH_DIR="${STAGING_ROOT}/${SKILL_NAME}"
  if ! bash "$PREPARE_CLAWHUB" --skill-dir "$SKILL_DIR" --staging-dir "$PUBLISH_DIR"; then
    rm -rf "$STAGING_ROOT"
    return 1
  fi
  SKILLS_PARENT="$STAGING_ROOT"
  TAGS_CLAW="${TAGS},latest"
  CLAWSCAN_FLAG=""
  if [ -n "$CLAWSCAN_NOTE" ]; then
    CLAWSCAN_FLAG="--clawscan-note '${CLAWSCAN_NOTE}'"
  fi

  if [ "$DRY_RUN" = false ]; then
    if ! run_or_dry "clawhub --workdir '${SKILLS_PARENT}' publish '${SKILL_NAME}' \
      --slug '${SKILL_NAME}' \
      --name '${DISPLAY_NAME}' \
      --version '${SKILL_VERSION}' \
      --changelog 'See README.md' \
      --tags '${TAGS_CLAW}' \
      ${CLAWSCAN_FLAG}"; then
      rm -rf "$STAGING_ROOT"
      return 1
    fi
    rm -rf "$STAGING_ROOT"
    log_info "clawhub.ai → https://clawhub.ai/${CLAWHUB_OWNER}/skills/${SKILL_NAME}"
  else
    echo "[DRY RUN] clawhub --workdir ${SKILLS_PARENT} publish ${SKILL_NAME} --version ${SKILL_VERSION}"
  fi
}

run_platform() {
  local platform="$1"
  shift
  if ! "$@"; then
    FAILED_PLATFORMS+=("$platform")
    log_error "${platform} 发布失败，继续执行其他平台"
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
    run_platform agentskillhub.dev publish_agentskillhub
    run_platform skills-hub.ai publish_skillshubai
    run_platform clawhub.ai publish_clawhub
    run_platform agent-skills-hub publish_agentskillshub_pr
    ;;
  agentskillhub)   run_platform agentskillhub.dev publish_agentskillhub ;;
  skillshubai)     run_platform skills-hub.ai publish_skillshubai ;;
  clawhub)         run_platform clawhub.ai publish_clawhub ;;
  agentskillshub)  run_platform agent-skills-hub publish_agentskillshub_pr ;;
  *)
    log_error "未知平台: $TARGET_PLATFORM"
    echo "支持: all | agentskillhub | skillshubai | clawhub | agentskillshub"
    exit 1
    ;;
esac

if [ "${#FAILED_PLATFORMS[@]}" -gt 0 ]; then
  log_section "部分平台失败"
  log_error "失败平台: ${FAILED_PLATFORMS[*]}"
else
  log_section "完成 🎉"
fi
echo ""
echo "📍 平台链接："
echo "  clawhub.ai        → https://clawhub.ai/${CLAWHUB_OWNER}/skills/${SKILL_NAME}"
echo "  agentskillhub.dev → https://agentskillhub.dev/u/${GITHUB_REPO%%/*}/sk/${SKILL_NAME}"
echo "  skills-hub.ai     → https://skills-hub.ai/skills/${SKILL_NAME}"
echo "  agent-skills-hub  → https://github.com/agent-skills-hub/agent-skills-hub/pulls"

[ "${#FAILED_PLATFORMS[@]}" -eq 0 ]
