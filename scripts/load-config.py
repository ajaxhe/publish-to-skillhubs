#!/usr/bin/env python3
"""Load publish config for a skill directory."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


def read_frontmatter(skill_md: Path) -> dict[str, str]:
    text = skill_md.read_text(encoding="utf-8")
    match = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if not match:
        return {}

    fm: dict[str, str] = {}
    for line in match.group(1).splitlines():
        if ":" not in line or line.strip().startswith("#"):
            continue
        key, _, value = line.partition(":")
        value = value.strip().strip('"').strip("'")
        if value.startswith(">"):
            continue
        fm[key.strip()] = value
    return fm


def git_remote_repo(skill_dir: Path) -> str:
    try:
        url = subprocess.check_output(
            ["git", "-C", str(skill_dir), "remote", "get-url", "origin"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except subprocess.CalledProcessError:
        return ""

    url = url.removesuffix(".git")
    if url.startswith("git@"):
        # git@github.com:owner/repo
        return url.split(":", 1)[-1]
    if "github.com/" in url:
        return url.split("github.com/", 1)[-1]
    return ""


def load_config(skill_dir: Path) -> dict:
    skill_dir = skill_dir.resolve()
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        raise SystemExit(f"SKILL.md not found in {skill_dir}")

    fm = read_frontmatter(skill_md)
    publish_json = skill_dir / "publish.json"
    cfg: dict = {}
    if publish_json.exists():
        cfg = json.loads(publish_json.read_text(encoding="utf-8"))

    skill_name = cfg.get("skill_name") or fm.get("name") or skill_dir.name
    github_repo = cfg.get("github_repo") or git_remote_repo(skill_dir)
    display_name = cfg.get("display_name") or skill_name.replace("-", " ").title()
    version = cfg.get("version") or fm.get("version") or "1.0.0"
    category = cfg.get("category") or fm.get("category") or "productivity"
    tags = cfg.get("tags") or []
    if isinstance(tags, str):
        tags = [t.strip() for t in tags.split(",") if t.strip()]
    if not tags and fm.get("tags"):
        tags = [t.strip() for t in fm["tags"].split(",") if t.strip()]

    clawscan_note = cfg.get("clawscan_note", "")
    pr_description = cfg.get("pr_description", f"Add {skill_name} skill.\n\nSource: https://github.com/{github_repo}")
    platforms = cfg.get(
        "platforms",
        {
            "clawhub": {"enabled": True},
            "agentskillhub": {"enabled": True},
            "skillshubai": {"enabled": True},
            "agentskillshub": {"enabled": False},
        },
    )

    return {
        "skill_dir": str(skill_dir),
        "skill_name": skill_name,
        "display_name": display_name,
        "version": version,
        "category": category,
        "tags": tags,
        "github_repo": github_repo,
        "github_repo_url": f"https://github.com/{github_repo}" if github_repo else "",
        "clawscan_note": clawscan_note,
        "pr_description": pr_description,
        "platforms": platforms,
        "description": fm.get("description", ""),
    }


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} <skill-dir>")
    print(json.dumps(load_config(Path(sys.argv[1])), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
