# publish-to-skillhubs

> 将任意 Agent Skill 一键发布到 ClawHub、agentskillhub.dev、skills-hub.ai、skillhub.cn、agent-skills-hub 等多平台。
> 目标 skill 只需提供 `SKILL.md` + 可选 `publish.json`，即可推送到各 Agent Skill 市场。
> **内置发布前严格校验**：本地产物、私有配置、凭证命中即阻断，脏包上不了架。

- **Skill 名**：`publish-to-skillhubs`
- **版本**：`1.2.0`
- **作者**：ajaxhe
- **标签**：publish, clawhub, skillhub, skillhub.cn, preflight, validation, automation, ci

---

## 1. 它能做什么

把本地已就绪（有公开 GitHub 仓库）的 Skill 分发到多个 Skill 市场，统一处理：

| 平台 | 标识 | 认证方式 |
|------|------|----------|
| [clawhub.ai](https://clawhub.ai) | `clawhub` | `clawhub login`（GitHub OAuth） |
| [agentskillhub.dev](https://agentskillhub.dev) | `agentskillhub` | `skhub login` 或 Web 导入 |
| [skills-hub.ai](https://skills-hub.ai) | `skillshubai` | API Key |
| [skillhub.cn](https://skillhub.cn)（腾讯，ClawHub 中文站） | `skillhub` | `skh_` API Token（需实名认证） |
| [agent-skills-hub](https://github.com/agent-skills-hub/agent-skills-hub) | `agentskillshub` | `gh auth login`（提 PR） |

**特性**

- 读取 `publish.json` 配置，缺省时从 `SKILL.md` frontmatter + `git remote` 自动推断
- ClawHub 发布前生成**干净副本**（剔除 `out/`、构建产物、私有配置、二进制），绝不修改原始 skill 目录
- 支持 `--dry-run` 预览、`--platform` 单平台、`--skip-git-push` 不自动推送
- 可选安装 GitHub Actions CI，实现推送即发布
- **发布前严格校验（阻断式）**：校验规则与打包过滤共用一份 `policy.py`，本地产物 / 私有配置 / 凭证 / 超限体积命中即中止发布

---

## 2. 快速开始

### 2.1 为目标 skill 添加 `publish.json`

```bash
cp scripts/../templates/publish.json.example /path/to/your-skill/publish.json
```

必填字段：`skill_name`、`display_name`、`github_repo`。其余可自动推断。

**凭证统一管理**：所有平台 token 集中在 `~/.config/publish-to-skillhubs/credentials.json`（600 权限），
用 `scripts/load-credentials.py` 读写，各平台原生配置仅作兜底：

```bash
CRED=scripts/load-credentials.py
python3 $CRED show                        # 掩码查看各平台配置
python3 $CRED sync                        # 从原生位置汇总补入
python3 $CRED set skillhub token skh_xxx  # 写入/轮换
```

**平台专属元数据**：面向中文用户的平台（skillhub.cn）用 `platform_overrides.<平台>` 覆盖
displayName/summary/description/tags，脚本会把它写进暂存副本再上传，不改动原 SKILL.md。

`publish.json` 字段说明：

```json
{
  "skill_name": "your-skill-name",
  "display_name": "Your Skill Display Name",
  "version": "1.0.0",
  "github_repo": "owner/your-skill-name",
  "category": "productivity",
  "tags": ["cursor", "agent", "automation"],
  "changelog": "首次发布",
  "clawscan_note": "Brief note for ClawHub security scan (optional).",
  "pr_description": "Optional markdown body for agent-skills-hub PR.",
  "platforms": {
    "clawhub":       { "enabled": true },
    "agentskillhub": { "enabled": true },
    "skillshubai":   { "enabled": true },
    "skillhub":      { "enabled": true },
    "agentskillshub":{ "enabled": false }
  }
}
```

### 2.2 确保 skill 有公开 GitHub 仓库

```bash
cd /path/to/your-skill
git remote -v   # 应指向 github.com/<owner>/<repo>
git push origin main
```

> agentskillhub 等平台要求仓库为 **public**。

### 2.3 发布前校验（脚本会自动跑，也可单独跑）

```bash
python3 scripts/preflight.py /path/to/your-skill          # 人读
python3 scripts/preflight.py /path/to/your-skill --json   # 机读，exit 0/1
```

`publish-to-skillhubs.sh` 在**向任何平台发送内容之前**会先执行这一步，**退出码非 0 直接中止发布**。

| 判定 | 触发条件 |
|------|----------|
| ❌ 阻断 | 缺 `SKILL.md` / `name` / `description` |
| ❌ 阻断 | `frontmatter` 值的 plain scalar 里有半角冒号+空格 `: `（平台报 `mapping values are not allowed in this context`） |
| ❌ 阻断 | 私有配置（`config.json`/`.env`）**含真实凭证** |
| ❌ 阻断 | 待上传文本命中 `skh_`、`ghp_`、`AKIA`、`AKID`、私钥、`Bearer` 等特征 |
| ❌ 阻断 | 整包 > 8 MB 或单文件 > 1 MB |
| ⚠️ 提示 | 目录里有私有配置（不进包，提醒别提交仓库） |
| ⚠️ 提示 | 文本含 `/Users/xxx`、`/home/xxx` 本地绝对路径 |
| ⚠️ 提示 | `SKILL.md` 引用了一个不会进包的文件（装完跑不起来） |

跳过校验：`--skip-preflight`（不推荐）。提示项升级为阻断：`--preflight-strict`。

**永远不进包**：`.git` `.github` `.workbuddy` `__pycache__` `node_modules` `.venv` `dist` `build`
`articles` `output` `out` `projects` `logs` `tmp` 等产物目录；`config.json` `credentials.json`
`auth.json` `token.json` `.env*` `id_rsa` 等私有文件；`publish.json` `.gitignore` `.DS_Store`；
二进制与非文本类型；无扩展名文件（`LICENSE` 除外，平台会拒收）。

### 2.4 一键发布

```bash
# 正式发布（交互确认）
bash scripts/publish-to-skillhubs.sh --skill-dir /path/to/your-skill

# 预览（不真正发布）
bash scripts/publish-to-skillhubs.sh --skill-dir /path/to/your-skill --dry-run

# 仅发 ClawHub
bash scripts/publish-to-skillhubs.sh --skill-dir /path/to/your-skill --platform clawhub

# 仅发 skillhub.cn（先 skillhub login --key skh_xxx）
bash scripts/publish-to-skillhubs.sh --skill-dir /path/to/your-skill --platform skillhub

# 非交互环境
bash scripts/publish-to-skillhubs.sh --skill-dir /path/to/your-skill --platform all --yes
```

### 2.5 （可选）安装 GitHub Actions 自动发布

```bash
bash scripts/install-workflow.sh --skill-dir /path/to/your-skill
bash scripts/setup-tokens.sh --repo owner/repo
```

---

## 3. 脚本一览

| 脚本 | 用途 |
|------|------|
| `scripts/publish-to-skillhubs.sh` | 主发布脚本（Step 1 强制校验 → 编排各平台发布） |
| `scripts/preflight.py` | 发布前严格校验（阻断式，exit 0/1） |
| `scripts/policy.py` | **策略单一事实来源**：打包过滤与校验共用 |
| `scripts/setup-tokens.sh` | 一次性：提取各平台 token → GitHub Secrets |
| `scripts/prepare-clawhub-staging.sh` | 创建 ClawHub 干净副本（按 `policy` 过滤） |
| `scripts/install-workflow.sh` | 复制 CI workflow 到目标 skill 仓库 |
| `scripts/load-config.py` | 读取 `publish.json` + 自动推断字段 |
| `scripts/load-credentials.py` | 统一凭证（读写 / 汇总 / 掩码查看 / export-env） |
| `scripts/apply-platform-meta.py` | 生成暂存副本：改写平台专属元数据 + 按 `policy` 过滤文件 |

---

## 4. Agent 执行流程（供调用方参考）

1. **定位 skill 目录**：解析用户给出的路径；若是软链则 `readlink -f` 到真实目录。
2. **发布前校验（必跑，脚本自动执行）**：`python3 scripts/preflight.py <skill>`，退出码非 0 就停下来修，禁止 `--skip-preflight` 硬发；同时人工确认 `SKILL.md` frontmatter 含 `name`/`description`、建议含 `version`/`tags`/`category`、发 skillhub.cn 还需 `slug`/`displayName`（`tags` 用行内列表）、GitHub 仓库为 public、本地变更已 push。
3. **ClawHub 特殊处理**：若 skill 含图片/PDF/`config.json`，先用 `prepare-clawhub-staging.sh` 生成干净副本，再从副本发布，绝不改动原始目录。
4. **执行发布**：`bash publish-to-skillhubs.sh --skill-dir <绝对路径> --platform all`（非交互加 `--yes`）。
5. **汇报结果**：列出各平台链接 `https://<平台>/skills/<skill_name>`。

---

## 5. 安装位置与软链

本 skill 的真实目录位于 `~/.workbuddy/skills/publish-to-skillhubs`（统一管理）。
为兼容依赖 `~/.agents/skills/` 路径的 Agent/服务，原位置保留软链：

```bash
ln -s ~/.workbuddy/skills/publish-to-skillhubs ~/.agents/skills/publish-to-skillhubs
```

经软链路径（`~/.agents/skills/publish-to-skillhubs/scripts/...`）调用与真实路径等效。
项目内也可按需软链到 CodeBuddy 等环境，发布时 `--skill-dir` 指向软链或真实路径均可，脚本会自动 resolve。

---

## 6. 安全说明

- 本仓库**不包含任何真实密钥 / 凭证**：`setup-tokens.sh` 仅负责把本地已有 token 写入目标仓库的 GitHub Secrets，自身不硬编码任何 secret。
- 统一凭证放在 `~/.config/publish-to-skillhubs/credentials.json`（600 权限，仓库之外），不要把该文件复制进任何 skill 目录或提交。
- **发布前严格校验**：`policy.py` 是唯一策略来源，打包过滤与校验共用同一份规则，杜绝「校验放行、打包却带上 `.env`」。
- ClawHub 发布走干净副本，默认排除 `out/`、构建产物与私有配置，避免隐私外泄。
- 目标 skill 发布前请确认 `.gitignore` 已排除 `config.json`、`auth.json`、token 文件等。

---

## 7. 目录结构

```text
publish-to-skillhubs/
├── SKILL.md                 # Skill 定义与执行流程
├── README.md                # 本文件
├── scripts/
│   ├── publish-to-skillhubs.sh
│   ├── preflight.py             # 发布前严格校验
│   ├── policy.py                # 策略单一事实来源
│   ├── apply-platform-meta.py
│   ├── prepare-clawhub-staging.sh
│   ├── setup-tokens.sh
│   ├── install-workflow.sh
│   ├── load-config.py
│   └── load-credentials.py
├── references/
│   └── platforms.md         # 各平台细节与 API
└── templates/
    ├── publish.json.example
    └── publish-to-skillhubs.yml
```

## 8. 参考

- 平台细节与 API：`references/platforms.md`
- 配置模板：`templates/publish.json.example`
- CI 模板：`templates/publish-to-skillhubs.yml`
