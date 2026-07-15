# Agent Skill 发布平台参考

## clawhub.ai

- **CLI**: `npm install -g @clawhub/cli`
- **登录**: `clawhub login`（GitHub OAuth）
- **发布**: `clawhub --workdir <skills-parent> publish <skill-name> --slug ... --version ...`
- **约束**: 仅文本文件；需过滤图片、PDF、`config.json`
- **链接**: https://clawhub.ai/skills/{skill_name}

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
| `platforms.*.enabled` | 可选 | 按平台开关 |
