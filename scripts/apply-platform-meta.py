#!/usr/bin/env python3
"""按发布策略生成 skill 的暂存副本，并按需改写平台专属元数据。

动机：
- skill 工作目录里有大量**本地生成的产物**（抓取结果、导出目录、构建缓存）和**私有配置**，
  绝不能进发布包（实测某 skill 工作目录 555MB）；
- skillhub.cn 只从 SKILL.md frontmatter 读元数据，且面向中文用户需要重写名称/简介/描述，
  而原 SKILL.md 的 description 是给本地 Agent 做触发匹配的，两者目标不同。

文件筛选规则来自 `policy.py`（与发布前校验共用同一份策略）。

用法：
    apply-platform-meta.py --skill-dir <原目录> --out-dir <暂存目录> \
        [--meta '{"displayName":"...","summary":"...","tags":["a","b"]}']

约定：
- 只改 frontmatter 里出现的键，其余行原样保留；新键追加到 frontmatter 末尾
- 值一律压成单行（skillhub CLI 的 frontmatter 解析器只认 `key: value` 单行）
- list 值写成行内列表 `[a, b]`（skillhub CLI 只认这种写法）
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import policy  # noqa: E402


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


def build_staging(src: Path, dst: Path) -> dict[str, list[str]]:
    """按 policy 过滤拷到 dst，返回 {跳过原因: [相对路径]}。"""
    files, skipped = policy.collect_publish_files(src)
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True, exist_ok=True)
    for path in files:
        target = dst / path.relative_to(src)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    return skipped


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skill-dir", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--meta", default="{}", help="JSON 字符串或 .json 文件路径（为空则只做过滤拷贝）")
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

    skipped = build_staging(src, dst)
    applied = rewrite_frontmatter(dst / "SKILL.md", meta) if meta else []
    kept = [p for p in dst.rglob("*") if p.is_file()]
    total = sum(p.stat().st_size for p in kept)
    print(f"暂存副本: {dst}")
    if applied:
        print("已覆盖 frontmatter 字段: " + ", ".join(applied))
    print(f"包内容: {len(kept)} 个文件 / {total / 1024 / 1024:.2f} MB")
    if skipped:
        parts = [f"{reason} ×{len(paths)}" for reason, paths in sorted(skipped.items())]
        print("已跳过（非 skill 本体）: " + "；".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
