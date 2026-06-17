#!/usr/bin/env python3
"""Fetch latest SKILL.md from upstream sources, re-injecting the local source: field."""

import argparse
import difflib
import os
import re
import sys
import urllib.request

SKILLS_DIR = os.path.dirname(os.path.abspath(__file__))


def update_skill(name: str, skill_file: str, dry_run: bool) -> bool:
    with open(skill_file) as f:
        current = f.read()

    m = re.search(r"^source:\s*(\S+)", current, re.MULTILINE)
    if not m:
        print(f"  [{name}] no source: field, skipping")
        return False

    url = m.group(1)
    print(f"  [{name}] fetching from upstream...")

    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            upstream = r.read().decode()
    except Exception as e:
        print(f"  [{name}] ERROR: {e}", file=sys.stderr)
        return False

    parts = upstream.split("---", 2)
    if len(parts) < 3:
        print(f"  [{name}] ERROR: cannot parse frontmatter", file=sys.stderr)
        return False

    fm = parts[1].rstrip() + "\nsource: " + url + "\n"
    updated = "---" + fm + "---" + parts[2]

    if updated == current:
        print(f"  [{name}] up to date")
        return False

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

    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="dry-run: show diffs without modifying files")
    args = parser.parse_args()

    changed = 0
    for name in sorted(os.listdir(SKILLS_DIR)):
        skill_file = os.path.join(SKILLS_DIR, name, "SKILL.md")
        if not os.path.isfile(skill_file):
            continue
        if update_skill(name, skill_file, dry_run=args.check):
            changed += 1

    if not args.check:
        suffix = "s" if changed != 1 else ""
        print(f"\n{changed} skill{suffix} updated." if changed else "\nAll skills up to date.")


if __name__ == "__main__":
    main()
