#!/usr/bin/env python3
"""把平台专属元数据（中文 displayName / summary / description / tags 等）写进一份暂存副本。

动机：skillhub.cn 只从 SKILL.md frontmatter 读取元数据，且它是面向中文用户的商店，
需要中文名称与重写过的检索型描述；而 skill 自身的 SKILL.md 描述是给本地 Agent
做触发匹配的，两者目标不同。直接改原文件会伤到本地触发词，所以这里产出干净副本。

用法：
    apply-platform-meta.py --skill-dir <原目录> --out-dir <暂存目录> \
        --meta '{"displayName":"...","summary":"...","tags":["a","b"]}'

约定：
- 只改 frontmatter 里出现的键，其余行原样保留；新键追加到 frontmatter 末尾
- 值一律压成单行（skillhub CLI 的 frontmatter 解析器只认 `key: value` 单行）
- list 值写成行内列表 `[a, b]`（skillhub CLI 只认这种写法）
- 暂存副本排除 .git / __pycache__ / *.pyc / .DS_Store / node_modules 等
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

EXCLUDE_DIRS = {".git", ".idea", ".vscode", "node_modules", "__pycache__", ".workbuddy"}
EXCLUDE_SUFFIXES = (".pyc", ".DS_Store")
EXCLUDE_FILES = {"Thumbs.db", ".DS_Store", "publish.json", ".gitignore"}
# skillhub.cn 服务端按文件类型校验，无扩展名文件（LICENSE 等）会被拒：
# "不允许的文件类型: LICENSE"。许可证已在 frontmatter 的 license 字段声明，副本里无需带。
KEEP_EXTENSIONLESS = {"SKILL.md", "README.md", "README.zh.md"}


def _skip_file(name: str) -> bool:
    if name in EXCLUDE_FILES or name.endswith(EXCLUDE_SUFFIXES):
        return True
    if name in KEEP_EXTENSIONLESS:
        return False
    # 无扩展名（含 . 开头的隐藏文件）一律跳过
    return "." not in name.lstrip(".")


def copy_tree(src: Path, dst: Path) -> list[str]:
    """拷贝目录，返回被跳过的相对路径（供日志展示）。"""
    skipped: list[str] = []

    def ignore(directory: str, names: list[str]) -> set[str]:
        dropped: set[str] = set()
        for name in names:
            path = Path(directory) / name
            if path.is_dir():
                if name in EXCLUDE_DIRS:
                    dropped.add(name)
                continue
            if _skip_file(name):
                dropped.add(name)
                skipped.append(str(path.relative_to(src)))
        return dropped

    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        if item.name in EXCLUDE_DIRS or item.name in EXCLUDE_FILES:
            continue
        if item.is_dir():
            shutil.copytree(item, dst / item.name, ignore=ignore, symlinks=False)
        elif not _skip_file(item.name):
            shutil.copy2(item, dst / item.name)
        else:
            skipped.append(item.name)
    return skipped


def format_value(value: object) -> str:
    if isinstance(value, list):
        return "[" + ", ".join(str(v).strip() for v in value if str(v).strip()) + "]"
    # frontmatter 单行约束：折叠换行与多余空白
    return " ".join(str(value).split()).replace("\n", " ")


def rewrite_frontmatter(skill_md: Path, meta: dict) -> list[str]:
    text = skill_md.read_text(encoding="utf-8")
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        raise SystemExit(f"SKILL.md 缺少 frontmatter: {skill_md}")

    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), -1)
    if end < 0:
        raise SystemExit(f"SKILL.md frontmatter 缺少结束标记: {skill_md}")

    head, body, tail = lines[1:end], lines[end + 1 :], lines[:1]
    applied: list[str] = []
    remaining = dict(meta)

    for idx, line in enumerate(head):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or ":" not in stripped:
            continue
        key = stripped.split(":", 1)[0].strip()
        if key in remaining:
            head[idx] = f"{key}: {format_value(remaining.pop(key))}"
            applied.append(key)

    for key, value in remaining.items():
        head.append(f"{key}: {format_value(value)}")
        applied.append(key)

    skill_md.write_text("\n".join(tail + head + ["---"] + body), encoding="utf-8")
    return applied


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skill-dir", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--meta", default="{}", help="JSON 字符串或 .json 文件路径（为空则只做文件过滤拷贝）")
    args = parser.parse_args()

    raw = args.meta.strip()
    if raw.startswith("@"):
        raw = Path(raw[1:]).read_text(encoding="utf-8")
    elif raw.startswith("{"):
        pass  # 直接是 JSON 字面量
    elif len(raw) < 512 and Path(raw).is_file():
        # 长串直接当路径会触发 OSError: File name too long
        raw = Path(raw).read_text(encoding="utf-8")
    meta = json.loads(raw)
    if not isinstance(meta, dict):
        raise SystemExit("--meta 必须是 JSON 对象")

    src = Path(args.skill_dir).expanduser().resolve()
    dst = Path(args.out_dir).expanduser().resolve()
    if not (src / "SKILL.md").is_file():
        raise SystemExit(f"源目录没有 SKILL.md: {src}")

    skipped = copy_tree(src, dst)
    applied = rewrite_frontmatter(dst / "SKILL.md", meta) if meta else []
    print(f"暂存副本: {dst}")
    if applied:
        print("已覆盖 frontmatter 字段: " + ", ".join(applied))
    if skipped:
        print("已跳过（平台不接受的文件类型）: " + ", ".join(sorted(set(skipped))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
