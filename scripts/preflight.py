#!/usr/bin/env python3
"""发布前严格校验：确保 skill 包里没有本地生成的产物、私有配置与凭证。

判定依据是 policy.py 的同一份策略 —— 校验的就是"真正会被上传的那些文件"，
所以不会出现"校验放行、打包却带上 .env"的错位。

用法：
    preflight.py <skill-dir> [--json] [--skip-content] [--max-mb 8]

退出码：0 = 通过（可能有提示）；1 = 存在阻断项，禁止发布。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import policy  # noqa: E402

BLOCK = "block"
WARN = "warn"
INFO = "info"


def human_size(num: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if num < 1024 or unit == "GB":
            return f"{num:.0f} {unit}" if unit == "B" else f"{num:.2f} {unit}"
        num /= 1024
    return f"{num:.2f} GB"


def dir_size(path: Path) -> int:
    total = 0
    for item in path.rglob("*"):
        if item.is_file() and not item.is_symlink():
            try:
                total += item.stat().st_size
            except OSError:
                pass
    return total


def read_frontmatter(skill_md: Path) -> dict[str, str]:
    text = skill_md.read_text(encoding="utf-8", errors="replace")
    match = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if not match:
        return {}
    fm: dict[str, str] = {}
    for line in match.group(1).splitlines():
        # 只认顶层键（顶格），否则会被 requires.skills[].version 这类嵌套键覆盖
        if not line or line[0].isspace() or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        fm[key.strip()] = value.strip().strip('"').strip("'")
    return fm


def read_frontmatter_text(skill_md: Path) -> str:
    """取 frontmatter 原文（两个 `---` 之间的全部行），给 YAML 合规检查用。"""
    text = skill_md.read_text(encoding="utf-8", errors="replace")
    match = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    return match.group(1) if match else ""


def check(root: Path, max_mb: float, skip_content: bool) -> dict:
    findings: list[dict] = []
    root = root.resolve()

    skill_md = root / "SKILL.md"
    fm: dict[str, str] = {}
    if not skill_md.is_file():
        findings.append({"level": BLOCK, "code": "no-skill-md", "message": "缺少 SKILL.md"})
    else:
        fm = read_frontmatter(skill_md)
        for field in ("name", "description"):
            if not fm.get(field):
                findings.append({
                    "level": BLOCK, "code": f"missing-{field}",
                    "message": f"SKILL.md frontmatter 缺少 {field}",
                })
        # 平台解析器会因为 YAML 写法直接拒收（典型：值里有半角冒号+空格）
        for item in policy.scan_frontmatter(read_frontmatter_text(skill_md)):
            item["level"] = BLOCK if item["level"] == "block" else WARN
            findings.append(item)

    files, skipped = policy.collect_publish_files(root)
    total = sum(f.stat().st_size for f in files)

    # 1. 私有配置 / 凭证文件出现在仓库里（即使不进包，也要提醒）
    present_private = sorted(
        str(p.relative_to(root)) for p in root.rglob("*")
        if p.is_file() and not p.is_symlink()
        and policy.is_private_name(p.name)
        and ".git" not in p.relative_to(root).parts
        and not any(part in policy.ARTIFACT_DIRS for part in p.relative_to(root).parts[:-1])
    )
    for rel in present_private:
        leaked: list[str] = []
        if not skip_content:
            try:
                leaked = policy.scan_text((root / rel).read_text(encoding="utf-8", errors="ignore"))
            except OSError:
                pass
        if leaked:
            # 虽然它不会进包，但里面躺着真凭证且已在工作目录 / 仓库里 —— 必须处理掉
            findings.append({
                "level": BLOCK, "code": "private-secret",
                "message": f"私有配置 {rel} 含真实凭证（{', '.join(leaked)}），先移除再发布",
            })
        else:
            findings.append({
                "level": WARN, "code": "private-file-present",
                "message": f"工作目录存在私有配置 {rel}（不会进包，但注意别提交到仓库）",
            })

    # 2. 体积
    if total > max_mb * 1024 * 1024:
        findings.append({
            "level": BLOCK, "code": "total-size",
            "message": f"发布包过大 {human_size(total)}，超过 {max_mb} MB 上限",
        })
    for path in files:
        try:
            size = path.stat().st_size
        except OSError:
            continue
        if size > policy.MAX_FILE_BYTES:
            findings.append({
                "level": BLOCK, "code": "file-size",
                "message": f"单文件过大 {path.relative_to(root)}（{human_size(size)}）",
            })

    # 3. 内容扫描：凭证 / 本地绝对路径
    if not skip_content:
        for path in files:
            try:
                text = path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                findings.append({
                    "level": WARN, "code": "non-utf8",
                    "message": f"非 UTF-8 文本 {path.relative_to(root)}（确认是否该进包）",
                })
                continue
            secrets = policy.scan_text(text)
            if secrets:
                findings.append({
                    "level": BLOCK, "code": "secret",
                    "message": f"{path.relative_to(root)} 疑似包含凭证：{', '.join(secrets)}",
                })
            local_paths = policy.scan_local_paths(text)
            if local_paths:
                findings.append({
                    "level": WARN, "code": "local-path",
                    "message": f"{path.relative_to(root)} 含本地绝对路径：{', '.join(local_paths)}",
                })

    # 4. SKILL.md 引用了存在但被排除的文件（会导致装完跑不起来）
    if skill_md.is_file():
        referenced = set(re.findall(
            r"`((?:scripts|references|bin|assets|tests)/[A-Za-z0-9._\-/]+)`",
            skill_md.read_text(encoding="utf-8", errors="replace"),
        ))
        published = {str(f.relative_to(root)) for f in files}
        for rel in sorted(referenced):
            target = root / rel
            if target.exists() and rel not in published:
                findings.append({
                    "level": WARN, "code": "referenced-but-excluded",
                    "message": f"SKILL.md 引用了 {rel}，但它不会进包（平台类型限制）",
                })

    # 5. 被跳过的本地产物（信息项，不是错误）
    artifacts = []
    for name in sorted(policy.ARTIFACT_DIRS):
        candidate = root / name
        if candidate.is_dir() and name not in (".git", ".github"):
            artifacts.append({"name": name, "size": human_size(dir_size(candidate))})

    return {
        "skill_dir": str(root),
        "skill_name": fm.get("name", ""),
        "version": fm.get("version", ""),
        "publish_files": len(files),
        "publish_size": human_size(total),
        "skipped": {k: len(v) for k, v in sorted(skipped.items())},
        "skipped_detail": {k: v[:8] for k, v in sorted(skipped.items())},
        "local_artifacts": artifacts,
        "findings": findings,
        "blocked": any(f["level"] == BLOCK for f in findings),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("skill_dir")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--skip-content", action="store_true", help="跳过内容里的凭证扫描")
    parser.add_argument("--max-mb", type=float, default=policy.MAX_TOTAL_BYTES / 1024 / 1024)
    args = parser.parse_args()

    root = Path(args.skill_dir).expanduser()
    if not root.is_dir():
        raise SystemExit(f"目录不存在: {root}")

    report = check(root, args.max_mb, args.skip_content)

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 1 if report["blocked"] else 0

    print(f"校验目标: {report['publish_files']} 个文件 / {report['publish_size']}"
          f"{'（' + report['skill_name'] + '@' + report['version'] + '）' if report['skill_name'] else ''}")
    if report["local_artifacts"]:
        shown = ", ".join(f"{a['name']}/ {a['size']}" for a in report["local_artifacts"])
        print(f"本地产物目录（已排除，不上传）: {shown}")
    if report["skipped"]:
        detail = []
        for reason, count in report["skipped"].items():
            sample = report["skipped_detail"][reason]
            detail.append(f"{reason} ×{count}（如 {', '.join(sample[:3])}）")
        print("已排除: " + "； ".join(detail))

    blocks = [f for f in report["findings"] if f["level"] == BLOCK]
    warns = [f for f in report["findings"] if f["level"] == WARN]
    for item in blocks:
        print(f"❌ {item['message']}")
    for item in warns:
        print(f"⚠️  {item['message']}")

    if blocks:
        print(f"\n❌ 校验未通过：{len(blocks)} 个阻断项，禁止发布")
        return 1
    print(f"\n✅ 校验通过{'（' + str(len(warns)) + ' 个提示）' if warns else ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
