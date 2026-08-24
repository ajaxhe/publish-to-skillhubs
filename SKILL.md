---
name: publish-to-skillhubs
description: 将任意 Agent Skill 一键发布到 ClawHub、agentskillhub.dev、skills-hub.ai、
  agent-skills-hub 等平台。支持 publish.json 配置、ClawHub 干净副本、GitHub Actions CI。
  当用户提到「发布 skill」「提交到 ClawHub/SkillHub」「扩大 skill 影响力」 「publish to skill
  platforms」时使用。
version: 1.0.0
author: ajaxhe
tags: publish, clawhub, skillhub, automation, ci
---

# publish-to-skillhubs

通用 Skill 多平台发布工具。目标 skill 只需提供 `SKILL.md` + 可选 `publish.json`，即可推送到各 Agent Skill 市场。

## 支持平台

| 平台 | 标识 | 认证 |
|------|------|------|
| [clawhub.ai](https://clawhub.ai) | `clawhub` | `clawhub login` |
| [agentskillhub.dev](https://agentskillhub.dev) | `agentskillhub` | `skhub login` 或 Web 导入 |
| [skills-hub.ai](https://skills-hub.ai) | `skillshubai` | API Key |
| [agent-skills-hub](https://github.com/agent-skills-hub/agent-skills-hub) | `agentskillshub` | `gh auth login`（PR） |

## 快速开始

### 1. 为目标 skill 添加 `publish.json`

在 skill 根目录复制模板并填写：

```bash
cp ~/.agents/skills/publish-to-skillhubs/templates/publish.json.example \
   /path/to/your-skill/publish.json
```

必填字段：`skill_name`、`display_name`、`github_repo`。其余可自动推断。

### 2. 确保 skill 有公开 GitHub 仓库

```bash
cd /path/to/your-skill
git remote -v   # 应指向 github.com/<owner>/<repo>
git push origin main
```

### 3. 一键发布

```bash
bash ~/.agents/skills/publish-to-skillhubs/scripts/publish-to-skillhubs.sh \
  --skill-dir /path/to/your-skill

# 预览
bash ~/.agents/skills/publish-to-skillhubs/scripts/publish-to-skillhubs.sh \
  --skill-dir /path/to/your-skill --dry-run

# 仅 ClawHub
bash ~/.agents/skills/publish-to-skillhubs/scripts/publish-to-skillhubs.sh \
  --skill-dir /path/to/your-skill --platform clawhub
```

### 4. （可选）安装 GitHub Actions 自动发布

```bash
bash ~/.agents/skills/publish-to-skillhubs/scripts/install-workflow.sh \
  --skill-dir /path/to/your-skill

bash ~/.agents/skills/publish-to-skillhubs/scripts/setup-tokens.sh \
  --repo owner/repo
```

## Agent 执行流程

当用户要求「把某 skill 发布到各平台」时，按序执行：

### Step 0：定位 skill 目录

- 解析用户给出的路径；若是软链则 `readlink -f` 到真实目录
- 确认存在 `SKILL.md`
- 若无 `publish.json`，从 `SKILL.md` frontmatter + `git remote` 自动生成并让用户确认

### Step 1：发布前检查

- [ ] `SKILL.md` frontmatter 含 `name`、`description`（≤200 字兼容 Claude.ai）
- [ ] 建议含 `version`、`tags`、`category`（skills-hub.ai 需要 category）
- [ ] 无 `config.json` 等私有文件被提交（应在 `.gitignore`）
- [ ] GitHub 仓库为 **public**（agentskillhub 需公开仓库）
- [ ] 本地变更已 commit & push

### Step 2：ClawHub 特殊处理

ClawHub 不接受二进制/私有配置。若 skill 含图片、PDF、`config.json`：

```bash
bash ~/.agents/skills/publish-to-skillhubs/scripts/prepare-clawhub-staging.sh \
  --skill-dir /path/to/skill \
  --staging-dir /path/to/project/.codebuddy/skills/<name>-clawhub
```

主发布脚本会自动创建临时 staging、从 staging 发布并在结束后清理；**绝不修改原始
skill 目录**。非交互模式如未登录会立即失败，不会自动打开 OAuth 并无限等待。

### Step 3：执行发布

```bash
PUBLISH_SKILLHUBS="$HOME/.agents/skills/publish-to-skillhubs/scripts/publish-to-skillhubs.sh"
bash "$PUBLISH_SKILLHUBS" --skill-dir "<绝对路径>" --platform all
```

非交互环境加 `--yes`；首次认证失败时引导用户运行 `setup-tokens.sh`。

发布脚本必须支持幂等重跑：已存在的同版本视为成功；单个平台失败时继续执行其余平台，
最终汇总失败平台并返回非零退出码。agentskillhub.dev 必须先调用仓库 analyze API，
使用平台返回的真实路径（根目录 Skill 的路径是空字符串，不是 `.`）。

### Step 4：汇报结果

只列出真实结果；不得在失败后仍打印“完成”。各平台链接：

- `https://clawhub.ai/<clawhub_owner>/skills/<skill_name>`
- `https://agentskillhub.dev/u/<username>/sk/<skill_name>`
- `https://skills-hub.ai/skills/<skill_name>`

## 项目内软链模式（贾维斯等）

用户可在项目里软链 skill，便于 CodeBuddy 识别 + 统一发布：

```bash
ln -sf ~/.workbuddy/skills/sync-obsidian-to-lexiang \
  /Users/ajaxhe/CodeBuddy/贾维斯/.codebuddy/skills/sync-obsidian-to-lexiang
```

发布时 `--skill-dir` 指向软链或真实路径均可；脚本会自动 resolve。

## 脚本一览

| 脚本 | 用途 |
|------|------|
| `scripts/publish-to-skillhubs.sh` | 主发布脚本 |
| `scripts/setup-tokens.sh` | 一次性：提取各平台 token → GitHub Secrets |
| `scripts/prepare-clawhub-staging.sh` | 创建 ClawHub 干净副本 |
| `scripts/install-workflow.sh` | 复制 CI workflow 到目标 skill 仓库 |
| `scripts/load-config.py` | 读取 publish.json + 自动推断 |

## 参考

- 平台细节与 API：`references/platforms.md`
- 配置模板：`templates/publish.json.example`
- CI 模板：`templates/publish-to-skillhubs.yml`
