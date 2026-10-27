---
name: publish-to-skillhubs
slug: publish-to-skillhubs
displayName: Publish to Skill Hubs
summary: 把本地 Agent Skill 一键分发到 ClawHub、agentskillhub.dev、skills-hub.ai、skillhub.cn、agent-skills-hub，内置发布前严格校验（剔除本地产物/私有配置/凭证），支持 publish.json 配置、干净副本与 GitHub Actions CI
description: 将任意 Agent Skill 一键发布到 ClawHub、agentskillhub.dev、skills-hub.ai、skillhub.cn、agent-skills-hub 等平台。发布前自动做严格校验：剔除本地生成的产物、私有配置与凭证，命中即阻断，避免脏包上架。支持 publish.json 配置、干净副本、GitHub Actions CI。当用户提到「发布 skill」「提交到 ClawHub/SkillHub/skillhub.cn」「扩大 skill 影响力」「publish to skill platforms」「发布前检查 skill 包」时使用。
version: 1.2.0
author: ajaxhe
category: productivity
tags: [publish, clawhub, skillhub, automation, ci]
license: MIT
homepage: https://github.com/ajaxhe/publish-to-skillhubs
---

# publish-to-skillhubs

通用 Skill 多平台发布工具。目标 skill 只需提供 `SKILL.md` + 可选 `publish.json`，即可推送到各 Agent Skill 市场。

## 支持平台

| 平台 | 标识 | 认证 |
|------|------|------|
| [clawhub.ai](https://clawhub.ai) | `clawhub` | `clawhub login` |
| [agentskillhub.dev](https://agentskillhub.dev) | `agentskillhub` | `skhub login` 或 Web 导入 |
| [skills-hub.ai](https://skills-hub.ai) | `skillshubai` | API Key |
| [skillhub.cn](https://skillhub.cn)（腾讯，ClawHub 中文站） | `skillhub` | `skh_` API Token，需实名认证 |
| [agent-skills-hub](https://github.com/agent-skills-hub/agent-skills-hub) | `agentskillshub` | `gh auth login`（PR） |

## 统一凭证（所有平台一份文件）

发布凭证集中存放在 **`~/.config/publish-to-skillhubs/credentials.json`**（600 权限，
`PUBLISH_CREDENTIALS` 可改路径），脚本优先读它，各平台原生配置（`clawhub/config.json`、
`~/.skhub/auth.json`、`~/.skills-hub/config.json`、`~/.skillhub/credentials.json`）只作兜底。

```bash
CRED=~/.agents/skills/publish-to-skillhubs/scripts/load-credentials.py
python3 $CRED show                          # 掩码查看各平台配置状态
python3 $CRED sync                          # 从各平台原生位置汇总补入统一文件
python3 $CRED set skillhub token skh_xxx    # 写入/轮换单个字段
```

字段命名：`clawhub.token/registry`、`agentskillhub.token`、`skillshubai.apiKey/apiUrl`、
`skillhub.token/host`。**该文件不要提交到任何仓库。**

## 发布前严格校验（自动执行，阻断式）

`publish-to-skillhubs.sh` 在**向任何平台发送内容之前**会先跑 `scripts/preflight.py`，
校验规则与打包过滤共用 `scripts/policy.py` —— **校验的那些文件，就是要上传的那些文件**，
不存在「校验放行、打包却带上 `.env`」的错位。

```bash
python3 scripts/preflight.py /path/to/skill          # 人读报告
python3 scripts/preflight.py /path/to/skill --json   # 机读，退出码 0/1
```

阻断项（`exit 1`，发布直接中止）：

| 检查 | 说明 |
|------|------|
| `no-skill-md` / `missing-name` / `missing-description` | frontmatter 必备字段缺失 |
| `frontmatter-colon` | **值的 plain scalar 里有半角冒号+空格 `: `** → 平台报 `mapping values are not allowed in this context` |
| `frontmatter-no-colon` | frontmatter 某行不是 `key: value` 结构 |
| `private-secret` | 工作目录里的私有配置（`config.json`/`.env`…）**含真实凭证** |
| `secret` | 待上传的文本里命中 `skh_`/`ghp_`/`AKIA`/私钥/Bearer 等特征 |
| `total-size` / `file-size` | 整包 > 8 MB 或单文件 > 1 MB |

提示项（不阻断，加 `--preflight-strict` 可升级为阻断）：

- `private-file-present`：目录里有私有配置（不进包，但提醒别提交仓库）
- `local-path`：文本含 `/Users/xxx`、`/home/xxx` 等本地绝对路径
- `referenced-but-excluded`：`SKILL.md` 引用了不会进包的文件（装完跑不起来）
- `non-utf8`：非 UTF-8 文本待确认
- `frontmatter-dup-key` / `frontmatter-comment`：重复键；值里的 ` #` 会被 YAML 当注释截断

### frontmatter YAML 这条坑值得单独说

`description` 这类长值如果不加引号（plain scalar），**值内部不能出现半角冒号+空格**：

```yaml
# ❌ 平台报：yaml: line 5: mapping values are not allowed in this context
description: ...product demo video。Also: product demo video editor for agents.
# ❌ 同样炸：值以冒号结尾
summary: 能力包括:
# ✅ 换成中文全角冒号 / 改标点 / 整体加引号
description: ...product demo video。Also, product demo video editor for agents.
description: "...product demo video。Also: product demo video editor for agents."
description: >-
  多行长描述用块标量，内部随便写冒号
```

行号提示：平台报的行号是**去掉首个 `---` 之后**的位置（`name` 记作第 1 行），
所以在本地文件里要 **+1** 才对应得上。`preflight.py` 输出的就是平台行号。

**永远不进包**（`policy.ARTIFACT_DIRS` / `PRIVATE_NAMES`）：
`.git` `.github` `.workbuddy` `__pycache__` `node_modules` `.venv` `dist` `build`
`articles` `output` `out` `projects` `logs` `tmp` 等产物目录；
`config.json` `credentials.json` `auth.json` `token.json` `.env*` `id_rsa` 等私有文件；
`publish.json` `.gitignore` `.DS_Store` 等无需发布项；二进制与非文本类型。

## 快速开始

### 1. 为目标 skill 添加 `publish.json`

在 skill 根目录复制模板并填写：

```bash
cp ~/.agents/skills/publish-to-skillhubs/templates/publish.json.example \
   /path/to/your-skill/publish.json
```

必填字段：`skill_name`、`display_name`、`github_repo`。其余可自动推断。
`changelog` 会作为各平台本次发布的变更说明（默认 `See README.md`）。

面向中文用户的平台（目前是 skillhub.cn）通过 `platform_overrides.<平台>` 单独给一套元数据，
脚本会生成暂存副本、把这份元数据写进副本的 frontmatter 再上传，**不改动原 SKILL.md**
（原 description 是给本地 Agent 做触发匹配的，取值目标不同）：

```json
"platform_overrides": {
  "skillhub": {
    "displayName": "产品演示视频剪辑",
    "summary": "一句话中文简介（会展示在商店列表）",
    "description": "面向检索重写的描述：能力 + 适用场景 + 关键词",
    "tags": ["视频剪辑", "演示视频", "录屏"]
  }
}
```

### 2. 配好凭证

```bash
CRED=~/.agents/skills/publish-to-skillhubs/scripts/load-credentials.py
python3 $CRED show     # 缺哪个平台就补哪个；先从原生位置自动汇总
python3 $CRED sync
```

### 3. 确保 skill 有公开 GitHub 仓库

```bash
cd /path/to/your-skill
git remote -v   # 应指向 github.com/<owner>/<repo>
git push origin main
```

### 4. 一键发布

```bash
bash ~/.agents/skills/publish-to-skillhubs/scripts/publish-to-skillhubs.sh \
  --skill-dir /path/to/your-skill

# 预览
bash ~/.agents/skills/publish-to-skillhubs/scripts/publish-to-skillhubs.sh \
  --skill-dir /path/to/your-skill --dry-run

# 仅 ClawHub
bash ~/.agents/skills/publish-to-skillhubs/scripts/publish-to-skillhubs.sh \
  --skill-dir /path/to/your-skill --platform clawhub

# 仅 skillhub.cn（先 skillhub login --key skh_xxx）
bash ~/.agents/skills/publish-to-skillhubs/scripts/publish-to-skillhubs.sh \
  --skill-dir /path/to/your-skill --platform skillhub
```

### 5. （可选）安装 GitHub Actions 自动发布

```bash
bash ~/.agents/skills/publish-to-skillhubs/scripts/install-workflow.sh \
  --skill-dir /path/to/your-skill

bash ~/.agents/skills/publish-to-skillhubs/scripts/setup-tokens.sh \
  --repo owner/repo
```

`install-workflow.sh` 会同时把 `policy.py` + `preflight.py` 装到
`<skill>/.github/skill-preflight/`，CI 里有一个独立的 `preflight` job 跑同一份校验，
所有 publish job 都 `needs: [load-config, preflight]` —— 本地与线上同一道闸门。
`.github/` 本身在排除名单里，不会进 skill 包。

## Agent 执行流程

当用户要求「把某 skill 发布到各平台」时，按序执行：

### Step 0：定位 skill 目录

- 解析用户给出的路径；若是软链则 `readlink -f` 到真实目录
- 确认存在 `SKILL.md`
- 若无 `publish.json`，从 `SKILL.md` frontmatter + `git remote` 自动生成并让用户确认

### Step 1：发布前校验（必跑）

```bash
python3 ~/.workbuddy/skills/publish-to-skillhubs/scripts/preflight.py /path/to/skill
```

退出码非 0 就**停下来修**，不要 `--skip-preflight` 硬发。同时人工确认 checklist：

- [ ] `SKILL.md` frontmatter 含 `name`、`description`（≤200 字兼容 Claude.ai）
- [ ] 建议含 `version`、`tags`、`category`（skills-hub.ai 需要 category）
- [ ] 要发 skillhub.cn 的，frontmatter 必须另有 `slug`（kebab-case，全网唯一）、`displayName`、`version`（SemVer），
      并建议补 `summary`、`license`、`homepage`；`tags` 写成行内列表 `tags: [a, b]`（否则平台收不到标签数组）
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

skillhub.cn 走官方 CLI（`skillhub publish <dir>`），没有 OAuth 兜底：
未装 CLI / 未登录 / 缺 frontmatter 时脚本只报原因和下一步命令，不尝试交互登录。

### Step 4：汇报结果

只列出真实结果；不得在失败后仍打印“完成”。各平台链接：

- `https://clawhub.ai/<clawhub_owner>/skills/<skill_name>`
- `https://agentskillhub.dev/u/<username>/sk/<skill_name>`
- `https://skills-hub.ai/skills/<skill_name>`
- `https://skillhub.cn/skills/<slug>`

注意各平台的「审核」不等于失败：ClawHub 的 `pending.publication`、skills-hub.ai 的
`PENDING_REVIEW`、skillhub.cn 的 `status=pending_review` 都是已提交待审，汇报时要写清楚。

## 项目内软链模式（贾维斯等）

用户可在项目里软链 skill，便于 CodeBuddy 识别 + 统一发布：

```bash
ln -sf ~/.workbuddy/skills/sync-obsidian-to-lexiang \
  ~/CodeBuddy/贾维斯/.codebuddy/skills/sync-obsidian-to-lexiang
```

发布时 `--skill-dir` 指向软链或真实路径均可；脚本会自动 resolve。

## 脚本一览

| 脚本 | 用途 |
|------|------|
| `scripts/publish-to-skillhubs.sh` | 主发布脚本（含 Step 1 强制校验） |
| `scripts/preflight.py` | 发布前严格校验，阻断式，退出码 0/1 |
| `scripts/policy.py` | **策略单一事实来源**：打包过滤 + 校验规则共用 |
| `scripts/setup-tokens.sh` | 一次性：提取各平台 token → GitHub Secrets |
| `scripts/prepare-clawhub-staging.sh` | 创建 ClawHub 干净副本（走 policy 过滤） |
| `scripts/install-workflow.sh` | 复制 CI workflow + 校验脚本到目标 skill 仓库 |
| `scripts/load-config.py` | 读取 publish.json + 自动推断 |
| `scripts/load-credentials.py` | 统一凭证的读写/汇总/掩码查看 |
| `scripts/apply-platform-meta.py` | 生成暂存副本：改写 frontmatter 元数据 + 按 policy 过滤文件 |

## 参考

- 平台细节与 API：`references/platforms.md`
- 配置模板：`templates/publish.json.example`
- CI 模板：`templates/publish-to-skillhubs.yml`
