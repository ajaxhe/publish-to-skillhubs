# Agent Skill 发布平台参考

## clawhub.ai

- **CLI**: `npm install -g @clawhub/cli`
- **登录**: `clawhub login`（GitHub OAuth）
- **发布**: `clawhub --workdir <skills-parent> publish <skill-name> --slug ... --version ...`
- **约束**: 仅文本文件；需过滤图片、PDF、`config.json`
- **链接**: https://clawhub.ai/{clawhub_owner}/skills/{skill_name}

## agentskillhub.dev

- **导入**: POST `https://agentskillhub.dev/api/v1/repos/import`
- **Body**: `{"url": "https://github.com/owner/repo", "skills": ["skill-name"]}`
- **认证**: Bearer token（`skhub login` → `~/.skhub/auth.json`）
- **要求**: GitHub 仓库必须 **public**
- **链接**: https://agentskillhub.dev/skills/{skill_name}

## skills-hub.ai

- **CLI**: `npx @skills-hub-ai/cli publish . --github-repo URL`
- **API Key**: https://skills-hub.ai/settings/api-keys
- **SKILL.md 建议字段**: `version`, `category`, `tags`
- **category 示例**: productivity, research, development, writing
- **链接**: https://skills-hub.ai/skills/{skill_name}

## agent-skills-hub (GitHub)

- **仓库**: https://github.com/agent-skills-hub/agent-skills-hub
- **方式**: Fork → 复制到 `skills/{name}/` → PR
- **建议**: 仅手动触发，避免自动 spam PR

## GitHub Secrets（CI 用）

| Secret | 来源 |
|--------|------|
| `CLAWHUB_TOKEN` | `~/Library/Application Support/clawhub/config.json` → `.token` |
| `AGENTSKILLHUB_TOKEN` | `~/.skhub/auth.json` |
| `SKILLSHUBAI_TOKEN` | skills-hub.ai API Key |

运行 `scripts/setup-tokens.sh --repo owner/repo` 一次性写入。

## publish.json 字段

| 字段 | 必填 | 说明 |
|------|------|------|
| `skill_name` | 推荐 | 默认同目录名或 SKILL.md `name` |
| `display_name` | 推荐 | ClawHub 展示名 |
| `github_repo` | 推荐 | `owner/repo`，默认同 git remote |
| `version` | 可选 | 默认 SKILL.md 或 1.0.0 |
| `tags` | 可选 | 各平台标签 |
| `category` | 可选 | skills-hub.ai 分类 |
| `clawhub_owner` | 可选 | ClawHub 发布者 handle；默认取 `github_repo` owner |
| `platforms.*.enabled` | 可选 | 按平台开关 |
| `clawscan_note` | 可选 | 给 ClawHub ClawScan 的说明：脚本会跑 ffmpeg/OpenCV、开无头浏览器、写本地目录时务必写清楚，减少被判可疑 |

## 实测踩坑（2026-10-27）

**1. agentskillhub.dev 被 Cloudflare 拦 Python UA（HTTP 403 `error code: 1010`）**
`urllib` 默认 UA 直接被前置 WAF 拒，`analyze` 第一步就 403。脚本已改为带浏览器 UA + `Accept: application/json`；
curl 默认 UA 反而不拦，容易造成「curl 能通、脚本挂」的错觉，排查时先用脚本语言本身复现。

**2. skills-hub.ai 的 404 是空响应体，`json.loads` 直接崩**
`GET /skills/<slug>` 未发布时返回 404 且 body 为空，旧代码 `json.loads(e.read())` 抛 JSONDecodeError，
把「正常的新建流程第一步」伪装成一串 traceback。已改为空体返回 `{}`，并把非 JSON 错误体截断进 `{"error": ...}`。

**3. skills-hub.ai 会瞬时 503 `upstream connect error ... connection refused`**
不是配置问题，也不是 token 失效。用 curl 打 `https://api.skills-hub.ai/api/v1/categories` 复核：同时段
categories 200、`/skills` 503、几十秒后全部恢复。遇到 503 先分辨端点级 vs 全站级，别急着重配 token，原样重跑一次往往就过。

**4. 发布成功 ≠ 已公开，三个平台都有审核队列，汇报时必须区分**
- ClawHub：`clawhub inspect <slug>` 返回 `hidden by moderation (pending.publication)`，但 `Moderation: CLEAN`；
  此时页面 URL 仍是「couldn't find that page」，等审核通过才可访问。
- skills-hub.ai：`GET /api/v1/skills/<slug>` 的 `status` 为 `PENDING_REVIEW`，质量分 `qualityScore` 已有值。
- agentskillhub.dev：import 返回 `imported: 1` 即已公开，页面可正常渲染（根目录 skill 的 `path` 是空字符串）。
汇报用「已上传/待审核」而不是笼统的「已发布」。

