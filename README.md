# publish-to-skillhubs

> 将任意 Agent Skill 一键发布到 ClawHub、agentskillhub.dev、skills-hub.ai、agent-skills-hub 等多平台。
> 目标 skill 只需提供 `SKILL.md` + 可选 `publish.json`，即可推送到各 Agent Skill 市场。

- **Skill 名**：`publish-to-skillhubs`
- **版本**：`1.0.0`
- **作者**：ajaxhe
- **标签**：publish, clawhub, skillhub, automation, ci

---

## 1. 它能做什么

把本地已就绪（有公开 GitHub 仓库）的 Skill 分发到多个 Skill 市场，统一处理：

| 平台 | 标识 | 认证方式 |
|------|------|----------|
| [clawhub.ai](https://clawhub.ai) | `clawhub` | `clawhub login`（GitHub OAuth） |
| [agentskillhub.dev](https://agentskillhub.dev) | `agentskillhub` | `skhub login` 或 Web 导入 |
| [skills-hub.ai](https://skills-hub.ai) | `skillshubai` | API Key |
| [agent-skills-hub](https://github.com/agent-skills-hub/agent-skills-hub) | `agentskillshub` | `gh auth login`（提 PR） |

**特性**

- 读取 `publish.json` 配置，缺省时从 `SKILL.md` frontmatter + `git remote` 自动推断
- ClawHub 发布前生成**干净副本**（剔除 `out/`、构建产物、私有配置、二进制），绝不修改原始 skill 目录
- 支持 `--dry-run` 预览、`--platform` 单平台、`--skip-git-push` 不自动推送
- 可选安装 GitHub Actions CI，实现推送即发布
- 发布前自动做安全自检提示（不应提交 `config.json` 等私有文件）

---

## 2. 快速开始

### 2.1 为目标 skill 添加 `publish.json`

```bash
cp scripts/../templates/publish.json.example /path/to/your-skill/publish.json
```

必填字段：`skill_name`、`display_name`、`github_repo`。其余可自动推断。

`publish.json` 字段说明：

```json
{
  "skill_name": "your-skill-name",
  "display_name": "Your Skill Display Name",
  "version": "1.0.0",
  "github_repo": "owner/your-skill-name",
  "category": "productivity",
  "tags": ["cursor", "agent", "automation"],
  "clawscan_note": "Brief note for ClawHub security scan (optional).",
  "pr_description": "Optional markdown body for agent-skills-hub PR.",
  "platforms": {
    "clawhub":       { "enabled": true },
    "agentskillhub": { "enabled": true },
    "skillshubai":   { "enabled": true },
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

### 2.3 一键发布

```bash
# 正式发布（交互确认）
bash scripts/publish-to-skillhubs.sh --skill-dir /path/to/your-skill

# 预览（不真正发布）
bash scripts/publish-to-skillhubs.sh --skill-dir /path/to/your-skill --dry-run

# 仅发 ClawHub
bash scripts/publish-to-skillhubs.sh --skill-dir /path/to/your-skill --platform clawhub

# 非交互环境
bash scripts/publish-to-skillhubs.sh --skill-dir /path/to/your-skill --platform all --yes
```

### 2.4 （可选）安装 GitHub Actions 自动发布

```bash
bash scripts/install-workflow.sh --skill-dir /path/to/your-skill
bash scripts/setup-tokens.sh --repo owner/repo
```

---

## 3. 脚本一览

| 脚本 | 用途 |
|------|------|
| `scripts/publish-to-skillhubs.sh` | 主发布脚本（编排各平台发布） |
| `scripts/setup-tokens.sh` | 一次性：提取各平台 token → GitHub Secrets |
| `scripts/prepare-clawhub-staging.sh` | 创建 ClawHub 干净副本（剔除 `out/`、缓存、私有配置） |
| `scripts/install-workflow.sh` | 复制 CI workflow 到目标 skill 仓库 |
| `scripts/load-config.py` | 读取 `publish.json` + 自动推断字段 |

---

## 4. Agent 执行流程（供调用方参考）

1. **定位 skill 目录**：解析用户给出的路径；若是软链则 `readlink -f` 到真实目录。
2. **发布前检查**：`SKILL.md` frontmatter 含 `name`/`description`；建议含 `version`/`tags`/`category`；无私有文件被提交；GitHub 仓库为 public；本地变更已 push。
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
│   ├── setup-tokens.sh
│   ├── prepare-clawhub-staging.sh
│   ├── install-workflow.sh
│   └── load-config.py
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
