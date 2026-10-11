#!/usr/bin/env python3
"""Fetch latest SKILL.md from upstream sources, re-injecting the local source: field."""

import argparse
import difflib
import os
import re
import subprocess
import sys
import urllib.request

SKILLS_DIR = os.path.dirname(os.path.abspath(__file__))


UP_TO_DATE, CHANGED, FAILED = "up-to-date", "changed", "failed"

# Frontmatter is a `---` line at the very top and the next `---` line, nothing looser:
# a `---` rule in the body or inside a value must never be taken as a delimiter.
FRONTMATTER = re.compile(r"\A---[ \t]*\r?\n(.*?)^---[ \t]*\r?$(.*)", re.DOTALL | re.MULTILINE)


def split_frontmatter(text: str) -> tuple[str, str] | None:
    """Return (frontmatter, body after the closing line), or None when there is none."""
    m = FRONTMATTER.match(text.lstrip("﻿"))
    return (m.group(1), m.group(2)) if m else None


def commit_skill(name: str, skill_file: str) -> bool:
    """Stage and commit a single updated SKILL.md, one commit per skill."""
    rel = os.path.relpath(skill_file, SKILLS_DIR)
    try:
        subprocess.run(["git", "-C", SKILLS_DIR, "add", "--", skill_file], check=True)
        subprocess.run(
            ["git", "-C", SKILLS_DIR, "commit", "-m", f"chore(claude): sync {name} skill from upstream", "--", skill_file],
            check=True,
        )
        print(f"  [{name}] committed")
        return True
    except subprocess.CalledProcessError as e:
        print(f"  [{name}] ERROR committing {rel}: {e}", file=sys.stderr)
        return False


def update_skill(name: str, skill_file: str, dry_run: bool, commit: bool) -> str:
    with open(skill_file) as f:
        current = f.read()

    m = re.search(r"^source:\s*(\S+)", current, re.MULTILINE)
    if not m:
        print(f"  [{name}] no source: field, skipping")
        return UP_TO_DATE

    url = m.group(1)
    print(f"  [{name}] fetching from upstream...")

    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            upstream = r.read().decode()
    except (OSError, ValueError, UnicodeDecodeError) as e:
        print(f"  [{name}] ERROR: {e}", file=sys.stderr)
        return FAILED

    parsed = split_frontmatter(upstream)
    if parsed is None:
        print(f"  [{name}] ERROR: upstream has no frontmatter, not overwriting", file=sys.stderr)
        return FAILED
    frontmatter, body = parsed
    # Drop any upstream `source:` so the local one is the only one.
    frontmatter = re.sub(r"^source:.*\n?", "", frontmatter, flags=re.MULTILINE)

    updated = "---\n" + frontmatter.rstrip() + "\nsource: " + url + "\n---" + body

    if updated == current:
        print(f"  [{name}] up to date")
        return UP_TO_DATE

    if dry_run:
        diff = "".join(
            difflib.unified_diff(
                current.splitlines(True),
                updated.splitlines(True),
                fromfile=f"a/{name}/SKILL.md",
                tofile=f"b/{name}/SKILL.md",
                n=2,
            )
        )
        print(diff if diff else f"  [{name}] changes detected (diff empty)")
    else:
        with open(skill_file, "w") as f:
            f.write(updated)
        print(f"  [{name}] updated")
        if commit and not commit_skill(name, skill_file):
            return FAILED

    return CHANGED


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, epilog="Exit code is 1 when any skill could not be fetched, parsed or committed.")
    parser.add_argument("--check", action="store_true", help="dry-run: show diffs without modifying files")
    parser.add_argument("--commit", action="store_true", help="commit each updated SKILL.md separately (one commit per skill)")
    args = parser.parse_args()

    results: dict[str, list[str]] = {UP_TO_DATE: [], CHANGED: [], FAILED: []}
    for name in sorted(os.listdir(SKILLS_DIR)):
        skill_file = os.path.join(SKILLS_DIR, name, "SKILL.md")
        if not os.path.isfile(skill_file):
            continue
        status = update_skill(name, skill_file, dry_run=args.check, commit=args.commit and not args.check)
        results[status].append(name)

    changed, failed = results[CHANGED], results[FAILED]
    if not args.check:
        suffix = "s" if len(changed) != 1 else ""
        print(f"\n{len(changed)} skill{suffix} updated." if changed else "\nNo skill updated.")
    if failed:
        # Never "All skills up to date" over a failed fetch: offline looked exactly like that.
        print(f"FAILED: {', '.join(failed)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
