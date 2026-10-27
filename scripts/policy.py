#!/usr/bin/env python3
"""publish-to-skillhubs 的发布策略（单一事实来源）。

两个用途：
1. `collect_publish_files()` —— 决定"哪些文件真正会被上传"（打包过滤）；
2. `SECRET_PATTERNS` / `PRIVATE_NAMES` —— 给 `preflight.py` 做发布前严格校验。

**校验和打包必须共用这份规则**，否则会出现"校验说没问题、实际把 .env 传上去"这种事故。

策略要点：
- skill 包只该含"能读懂 + 能跑"的文本：文档、脚本、配置样例；
- 本地生成的产物（抓取结果、导出目录、构建产物、缓存）一律不进包；
- 私有配置（`config.json`、`.env`、凭证文件）一律不进包，并且它们出现在仓库里本身要告警。
"""

from __future__ import annotations

import re
from pathlib import Path

# ── 不进包的目录（运行时产物 / 缓存 / 依赖） ──────────────────────────────
ARTIFACT_DIRS = {
    ".git", ".github", ".idea", ".vscode", ".workbuddy",
    "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".cache",
    "node_modules", ".venv", "venv", "env", "dist", "build", "coverage", "htmlcov",
    # 本地生成的内容产物（抓取、导出、试跑输出）
    "articles", "output", "out", "projects", "logs", "tmp", ".tmp",
}

# ── 不进包的文件名（私有配置 / 系统垃圾） ─────────────────────────────────
PRIVATE_NAMES = {
    "config.json", "credentials.json", "credential.json", "secrets.json", "secret.json",
    "auth.json", "token.json", "tokens.json", ".env", ".env.local", ".env.production",
    "id_rsa", "id_ed25519", ".netrc", ".npmrc", ".pypirc",
}
JUNK_NAMES = {"Thumbs.db", ".DS_Store", "publish.json", ".gitignore"}
JUNK_SUFFIXES = (".pyc", ".pyo", ".log", ".tmp", ".bak", ".swp", "~", ".orig", ".rej")

# 允许写进包的文本类型（其余按二进制/未知处理，不进包）
ALLOWED_SUFFIXES = (
    ".md", ".markdown", ".txt", ".rst",
    ".py", ".sh", ".bash", ".zsh", ".fish", ".ps1",
    ".json", ".yml", ".yaml", ".toml", ".ini", ".cfg", ".conf",
    ".html", ".htm", ".css", ".js", ".mjs", ".cjs", ".ts", ".jsx", ".tsx",
    ".csv", ".tsv", ".srt", ".xml", ".sql", ".graphql",
    ".example", ".template", ".tmpl", ".in",
)
# 无扩展名但必须保留的
KEEP_EXTENSIONLESS = {"SKILL.md", "README", "README.md", "README.zh.md", "Makefile", "Dockerfile"}

# ── 内容层面的凭证特征（发布前必须为空，否则 BLOCK） ──────────────────────
SECRET_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("SkillHub token", re.compile(r"skh_[A-Za-z0-9]{20,}")),
    ("ClawHub token", re.compile(r"clh_[A-Za-z0-9]{16,}")),
    ("AgentSkillHub token", re.compile(r"skhub_pa[A-Za-z0-9]{16,}")),
    ("skills-hub key", re.compile(r"\bsh_[A-Za-z0-9]{20,}")),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}")),
    ("Slack token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}")),
    ("AWS access key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("腾讯云 SecretId", re.compile(r"\bAKID[0-9A-Za-z]{13,}\b")),
    ("私钥", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----")),
    ("Bearer token", re.compile(r"Bearer\s+[A-Za-z0-9._\-]{30,}")),
]
# 文档里出现的占位符不算泄露（如 `skh_xxx`、`<your-token>`）
PLACEHOLDER_RE = re.compile(r"(x{3,}|\*{3,}|<[^>]*>|YOUR_|your[-_]|example|placeholder|\.\.\.|redacted)", re.IGNORECASE)

# 本地绝对路径（隐私提示，不阻断）
LOCAL_PATH_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("macOS 用户目录", re.compile(r"/Users/[A-Za-z0-9._-]+")),
    ("Linux 用户目录", re.compile(r"/home/[A-Za-z0-9._-]+")),
]

MAX_FILE_BYTES = 1 * 1024 * 1024      # 单文件 1MB
MAX_TOTAL_BYTES = 8 * 1024 * 1024     # 整包 8MB


def _suffix_of(name: str) -> str:
    return Path(name).suffix.lower()


def is_private_name(name: str) -> bool:
    """是否是私有配置 / 凭证文件名（含 .env 家族）。"""
    return name in PRIVATE_NAMES or name.startswith(".env") or name.endswith(".env")


def classify(path: Path, root: Path) -> tuple[bool, str]:
    """判断单个文件是否进包。返回 (是否打包, 原因或空串)。"""
    rel = path.relative_to(root)
    parts = rel.parts
    if any(part in ARTIFACT_DIRS for part in parts[:-1]):
        return False, f"产物/缓存目录 {parts[0]}/"
    name = path.name
    if is_private_name(name):
        return False, "私有配置"
    if name in JUNK_NAMES:
        return False, "无需发布"
    if name.endswith(JUNK_SUFFIXES):
        return False, "系统垃圾/临时文件"
    if name in KEEP_EXTENSIONLESS:
        return True, ""
    if "." not in name.lstrip("."):
        return False, "无扩展名（平台不接受且难判定类型）"
    if _suffix_of(name) not in ALLOWED_SUFFIXES:
        return False, f"非文本类型 {_suffix_of(name) or '(无后缀)'}"
    return True, ""


def collect_publish_files(root: Path) -> tuple[list[Path], dict[str, list[str]]]:
    """返回 (将发布的文件列表, {跳过原因: [相对路径...]})。

    历史 git 仓库里的文件也按同一策略过滤——**不因为"被 git 跟踪"就放行**，
    否则样例大目录、私有配置会顺着仓库进入平台包。
    """
    root = root.resolve()
    keep: list[Path] = []
    skipped: dict[str, list[str]] = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink() or not path.is_file():
            continue
        if any(part in ARTIFACT_DIRS for part in path.relative_to(root).parts[:-1]):
            continue  # 整目录跳过，不逐个记账
        ok, reason = classify(path, root)
        rel = str(path.relative_to(root))
        if ok:
            keep.append(path)
        else:
            skipped.setdefault(reason, []).append(rel)
    return keep, skipped


def scan_text(text: str) -> list[str]:
    """返回命中的凭证类型（已过滤占位符）。"""
    hits: list[str] = []
    for label, pattern in SECRET_PATTERNS:
        for match in pattern.finditer(text):
            snippet = match.group(0)
            tail = text[match.end(): match.end() + 8]
            if PLACEHOLDER_RE.search(snippet) or PLACEHOLDER_RE.search(tail):
                continue
            hits.append(label)
            break
    return hits


def scan_local_paths(text: str) -> list[str]:
    """返回命中的本地路径类型。文档里刻意写的占位路径（/Users/xxx）不算。"""
    hits: list[str] = []
    for label, pattern in LOCAL_PATH_PATTERNS:
        for match in pattern.finditer(text):
            seg = match.group(0)
            # 只取用户名那一段判断占位符：/Users/xxx、/Users/<name>、/Users/your-name
            username = seg.rsplit("/", 1)[-1]
            if PLACEHOLDER_RE.search(username):
                continue
            hits.append(label)
            break
    return hits


# ── frontmatter YAML 合规（平台解析器会直接报错的那一类问题） ────────────────
# 值的首个字符是这些时属于合法写法，不需要按 plain scalar 检查
_BLOCK_OR_QUOTED = ('"', "'", "[", "{", "|", ">")


def scan_frontmatter(frontmatter: str) -> list[dict]:
    """检查 frontmatter 里会让 YAML 解析器报错的写法（纯文本规则，不依赖 PyYAML）。

    最常见的一条：plain scalar（不加引号的值）内部出现 **ASCII 冒号 + 空格**，
    解析器会把它当成「新的 mapping 开始」，报
    `mapping values are not allowed in this context`。
    中文全角冒号「：」不触发，所以只查半角。

    行号按**平台视角**给：`name` 记作第 1 行（平台拿到时已去掉首个 `---`），
    方便和平台报错里的行号直接对照。
    """
    findings: list[dict] = []
    seen_keys: dict[str, int] = {}
    in_block = False
    block_indent = 0

    for idx, line in enumerate(frontmatter.splitlines(), start=1):
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        # 块标量（`|` / `>`）的正文行：缩进即内容，不参与键值检查
        if in_block:
            if line.lstrip().startswith("#") or indent > block_indent:
                continue
            in_block = False
        if line.lstrip().startswith("#") or indent > 0:
            continue

        key, sep, value = line.partition(":")
        if not sep:
            findings.append({
                "level": "block", "code": "frontmatter-no-colon",
                "message": f"frontmatter 第 {idx} 行不是 `key: value` 结构：{line[:60]}",
            })
            continue

        key = key.strip()
        value = value.strip()
        if key in seen_keys:
            findings.append({
                "level": "warn", "code": "frontmatter-dup-key",
                "message": f"frontmatter 重复键 `{key}`（第 {seen_keys[key]} 行与第 {idx} 行，后者覆盖前者）",
            })
        seen_keys.setdefault(key, idx)

        if not value:
            continue
        if value[0] in _BLOCK_OR_QUOTED:
            if value[0] in "|>":
                in_block = True
                block_indent = indent
            continue

        # plain scalar：查半角冒号+空格（含行尾冒号）
        for match in re.finditer(r":\s", value):
            snippet = value[max(0, match.start() - 20): match.start() + 16]
            findings.append({
                "level": "block", "code": "frontmatter-colon",
                "message": (f"frontmatter 第 {idx} 行 `{key}` 的值里有半角冒号+空格 `: `，"
                            f"YAML 会报 mapping values are not allowed in this context"
                            f"（…{snippet}…）；改成全角「：」、改标点，或给整行值加引号"),
            })
            break
        else:
            if value.endswith(":"):
                findings.append({
                    "level": "block", "code": "frontmatter-colon",
                    "message": f"frontmatter 第 {idx} 行 `{key}` 的值以冒号结尾，YAML 会解析失败",
                })
        # 空格+# 会被当成注释，值被静默截断
        if re.search(r"\s#", value):
            findings.append({
                "level": "warn", "code": "frontmatter-comment",
                "message": f"frontmatter 第 {idx} 行 `{key}` 的值里有 ` #`，YAML 会当作注释截断后面的内容",
            })

    return findings
