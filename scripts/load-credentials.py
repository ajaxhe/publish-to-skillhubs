#!/usr/bin/env python3
"""publish-to-skillhubs 统一凭证管理。

所有平台的发布凭证集中在一份 JSON 里，便于统一管理/轮换；
各平台自己的原生配置文件只在统一文件缺字段时作为兜底读取。

统一文件路径（可用环境变量 PUBLISH_CREDENTIALS 覆盖）：
    ~/.config/publish-to-skillhubs/credentials.json

用法：
    load-credentials.py show                          # 掩码打印已配置平台
    load-credentials.py get skillhub token            # 取单个字段（未配置则输出空）
    load-credentials.py get clawhub registry
    load-credentials.py export-env                    # 输出 export 语句，供 shell eval
    load-credentials.py sync                          # 从各平台原生位置汇总写入统一文件
    load-credentials.py set skillhub token skh_xxx    # 写入/更新单个字段
"""

from __future__ import annotations

import json
import os
import stat
import sys
from pathlib import Path

DEFAULT_PATH = Path.home() / ".config" / "publish-to-skillhubs" / "credentials.json"

# 统一文件里的平台 -> 字段 -> 原生兜底位置
NATIVE_FALLBACKS = {
    "clawhub": {
        "token": [
            Path.home() / "Library/Application Support/clawhub/config.json",
            Path.home() / ".config/clawhub/config.json",
        ],
        "registry": [
            Path.home() / "Library/Application Support/clawhub/config.json",
            Path.home() / ".config/clawhub/config.json",
        ],
    },
    "agentskillhub": {
        "token": [Path.home() / ".skhub/auth.json"],
    },
    "skillshubai": {
        "apiKey": [Path.home() / ".skills-hub/config.json"],
        "apiUrl": [Path.home() / ".skills-hub/config.json"],
    },
    "skillhub": {
        "token": [Path.home() / ".skillhub/credentials.json"],
        "host": [Path.home() / ".skillhub/credentials.json"],
    },
}

DEFAULTS = {
    "clawhub": {"registry": "https://clawhub.ai"},
    "agentskillhub": {"apiUrl": "https://agentskillhub.dev"},
    "skillshubai": {"apiUrl": "https://api.skills-hub.ai"},
    "skillhub": {"host": "https://api.skillhub.cn"},
}


def cred_path() -> Path:
    raw = os.environ.get("PUBLISH_CREDENTIALS", "").strip()
    return Path(raw).expanduser() if raw else DEFAULT_PATH


def load_raw() -> dict:
    path = cred_path()
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"凭证文件不是合法 JSON: {path} ({exc})")


def save_raw(data: dict) -> Path:
    path = cred_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)  # 600
    return path


def _dig_native(platform: str, field: str) -> str:
    """从平台原生配置里挖字段；读不到返回空串。"""
    for candidate in NATIVE_FALLBACKS.get(platform, {}).get(field, []):
        if not candidate.exists():
            continue
        try:
            data = json.loads(candidate.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        if platform == "clawhub":
            value = data.get(field, "")
        elif platform == "agentskillhub":
            creds = data.get("credentials", {})
            value = next((item.get("token") for item in creds.values() if item.get("token")), "")
        elif platform == "skillshubai":
            value = data.get("apiKey" if field == "apiKey" else "apiUrl", "")
        elif platform == "skillhub":
            user = data.get("user") or {}
            value = user.get("token" if field == "token" else "host", "")
        else:
            value = ""
        if value:
            return str(value)
    return ""


def get(platform: str, field: str) -> str:
    data = load_raw()
    node = data.get(platform)
    value = (node.get(field) if isinstance(node, dict) else "") or ""
    if value:
        return str(value)
    value = _dig_native(platform, field)
    if value:
        return value
    return (DEFAULTS.get(platform) or {}).get(field, "")


def cmd_get(argv: list[str]) -> int:
    if len(argv) != 2:
        raise SystemExit("用法: load-credentials.py get <platform> <field>")
    value = get(argv[0], argv[1])
    if value:
        print(value)
    return 0


def cmd_set(argv: list[str]) -> int:
    if len(argv) != 3:
        raise SystemExit("用法: load-credentials.py set <platform> <field> <value>")
    platform, field, value = argv
    data = load_raw()
    node = data.setdefault(platform, {})
    node[field] = value
    path = save_raw(data)
    print(f"已写入 {platform}.{field} → {path}", file=sys.stderr)
    return 0


def cmd_show(argv: list[str]) -> int:
    data = load_raw()
    path = cred_path()
    print(f"凭证文件: {path} {'(存在)' if path.exists() else '(不存在)'}")
    platforms = sorted(NATIVE_FALLBACKS)
    for platform in platforms:
        node = data.get(platform)
        fields = sorted(set(NATIVE_FALLBACKS.get(platform, {})) | (set(node) if isinstance(node, dict) else set()))
        marks = []
        for field in fields:
            value = get(platform, field)
            if not value:
                marks.append(f"{field}=✗")
            elif field in ("token", "apiKey"):
                marks.append(f"{field}={value[:8]}…{value[-4:]}")
            else:
                marks.append(f"{field}={value}")
        print(f"  {platform:14s} " + "  ".join(marks))
    return 0


def cmd_export_env(argv: list[str]) -> int:
    """供 shell `eval "$(... export-env)"` 使用；空值不导出。"""
    pairs = [
        ("CLAWHUB_TOKEN", ("clawhub", "token")),
        ("CLAWHUB_REGISTRY", ("clawhub", "registry")),
        ("AGENTSKILLHUB_TOKEN", ("agentskillhub", "token")),
        ("SKILLSHUBAI_TOKEN", ("skillshubai", "apiKey")),
        ("SKILLSHUBAI_API_URL", ("skillshubai", "apiUrl")),
        ("SKILLHUB_TOKEN", ("skillhub", "token")),
        ("SKILLHUB_HOST", ("skillhub", "host")),
    ]
    for env_name, (platform, field) in pairs:
        value = get(platform, field)
        if value:
            print(f"export {env_name}={json.dumps(value)}")
    return 0


def cmd_sync(argv: list[str]) -> int:
    data = load_raw()
    data.setdefault("version", 1)
    data.setdefault("note", "publish-to-skillhubs 统一凭证；chmod 600，勿提交到任何仓库")
    found: list[str] = []
    for platform, fields in NATIVE_FALLBACKS.items():
        node = data.setdefault(platform, {})
        for field in fields:
            if node.get(field):
                continue
            value = _dig_native(platform, field)
            if value:
                node[field] = value
                found.append(f"{platform}.{field}")
    path = save_raw(data)
    print(f"统一凭证: {path}")
    if found:
        print("已从原生位置补入: " + ", ".join(found))
    else:
        print("没有新的字段可补（统一文件已是最全）")
    return 0


def main() -> int:
    commands = {"show": cmd_show, "get": cmd_get, "set": cmd_set, "export-env": cmd_export_env, "sync": cmd_sync}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        print(__doc__)
        return 1
    return commands[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    raise SystemExit(main())
