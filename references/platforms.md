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

## skillhub.cn

- **定位**: 腾讯运营的国内 Skill 商店，ClawHub 中文站；个人/企业均可发布，有 SkillPay 按调用变现
- **CLI**: `curl -fsSL https://skillhub.cn/install/install.sh | bash -s -- --cli-only`
  （装到 `~/.local/bin/skillhub`；PATH 未生效时用绝对路径）
- **登录**: `skillhub login --key skh_xxx --host https://api.skillhub.cn`
  Token 在 [个人中心 → API keys](https://skillhub.cn/dashboard/keys) 创建，**必须先完成实名认证**（人脸核身）
- **发布**: `skillhub publish <skill-dir> [--version x.y.z] [--changelog "本次改动"] [--dry-run] [--json]`
- **必填 frontmatter**: `slug`（kebab-case，全网唯一）、`version`（SemVer）、`displayName`；
  建议 `summary`、`description`、`tags`（**行内列表** `[a, b]`）、`license`、`homepage`
- **打包**: 整个目录逐文件上传，自动排除 `.git/.idea/.vscode/node_modules/__pycache__`、`*.pyc/.DS_Store`，跳过软连接；
  **服务端还会按文件类型校验，无扩展名文件（`LICENSE`、`bin/xxx`）会报 `不允许的文件类型: LICENSE`**
  → 脚本一律先做暂存副本，跳过无扩展名文件再上传（`apply-platform-meta.py`）
- **中文元数据**: 面向中文用户，`displayName`/`summary`/`description` 应写中文且为检索重写
  → 用 `publish.json` 的 `platform_overrides.skillhub` 提供，脚本写进暂存副本的 frontmatter，
  不动原 SKILL.md（原 description 是给本地 Agent 做触发匹配的）
- **审核**: 发布返回 `status=pending_review`，经「内容合规 + 科恩实验室漏洞扫描 + 云鼎 AI 模型安全评估」三线审核后自动上架；
  审核期间 `tags` 立刻生效，而 `displayName`/`summary` 等仍显示上一个已上架版本的元数据
- **错误码**: 401 token 失效 / 403 未实名 / 409 slug 被占用 / 429 限频（约 1 分钟后重试）
- **链接**: https://skillhub.cn/skills/<slug>
- **凭证位置**: `~/.skillhub/credentials.json` 的 `user.token`；也认 `SKILLHUB_TOKEN` 环境变量与 `--token`

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
| `SKILLHUB_TOKEN` | `~/.skillhub/credentials.json` → `.user.token`（`skh_` 开头） |

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
| `changelog` | 可选 | 本次发布的变更说明（skillhub.cn / ClawHub 会用到），默认 `See README.md` |
| `platform_overrides.<平台>` | 可选 | 单平台元数据覆盖（如 `skillhub` 的中文 displayName/summary/description/tags），发布时写进暂存副本 |
| `platforms.*.enabled` | 可选 | 按平台开关 |

## 统一凭证

所有平台凭证集中在 `~/.config/publish-to-skillhubs/credentials.json`（600 权限，`PUBLISH_CREDENTIALS` 可覆盖路径），
脚本用 `scripts/load-credentials.py` 读取；字段缺失时才回落到各平台原生配置。

| 平台 | 字段 | 原生兜底位置 |
|------|------|--------------|
| clawhub | `token`、`registry` | `~/Library/Application Support/clawhub/config.json`（Linux：`~/.config/clawhub/config.json`） |
| agentskillhub | `token` | `~/.skhub/auth.json` |
| skillshubai | `apiKey`、`apiUrl` | `~/.skills-hub/config.json` |
| skillhub | `token`、`host` | `~/.skillhub/credentials.json` 的 `user` 节点 |

```bash
CRED=scripts/load-credentials.py
python3 $CRED show                        # 掩码查看
python3 $CRED sync                        # 原生位置 → 统一文件
python3 $CRED set skillhub token skh_xxx  # 写入/轮换
python3 $CRED export-env                  # 输出 export 语句，供 shell eval
```

ClawHub CLI 支持 `CLAWHUB_CONFIG_PATH`，脚本会用统一凭证生成临时配置指向它，不改动用户原生配置。
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

