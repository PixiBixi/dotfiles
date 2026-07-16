# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

```bash
# Regenerate package lists + sync skills from upstream (see Makefile)
make update              # all: brew, npm, gems, skills
make update-brew         # dump installed Homebrew packages → packages/Brewfile
make update-npm          # global npm packages → packages/npm.txt
make update-gems         # installed gems → packages/gems.txt
make update-skills       # fetch latest SKILL.md from upstream sources
make check               # dry-run: show skill diffs without writing
make help                # list targets

# Deploy / provision (idempotent)
./scripts/init_mac.sh

# Check for drift between config/ and deployed $HOME files
./scripts/check-drift.sh

# Audit Homebrew packages vs shell-history usage
./scripts/brew-usage-audit.sh [--days N] [--threshold N] [--leaves-only]

# Pre-commit
pre-commit install                 # after cloning
pre-commit run --all-files         # run all hooks
pre-commit run shellcheck          # run one hook
pre-commit autoupdate              # bump hook versions
```

## Repository Structure

macOS dotfiles repo organized into four purpose-driven directories:

- `config/` — dotfiles deployed to `$HOME` (zsh, git, nvim, ssh, kube, tmux, vim, wezterm). Mirrors the target `$HOME` path structure.
- `packages/` — package lists: `Brewfile`, `npm.txt`, `gems.txt`. **krew plugins live inside the `Brewfile`** as `krew "..."` entries (no separate `krew.txt`).
- `apps/` — non-dotfile app configs:
  - `claude/` — `CLAUDE.md` + `settings.json` (versioned source for `~/.claude/`), `skills/` (managed SKILL.md files + `.update-skills.py`), `hooks/` (`session-allow.sh`)
  - `raycast/`, `vscode/`
- `scripts/` — `init_mac.sh` (main setup), `check-drift.sh`, `brew-usage-audit.sh`, `init.sh` (legacy, do not use)

Repo-level tooling files stay at root: `Makefile`, `.pre-commit-config.yaml`, `.yamllint.yaml`, `.prettierignore`. Note: `.markdownlint.json` lives in `config/` (deployed to `$HOME`) and is referenced via `--config config/.markdownlint.json` in the pre-commit hook.

## Deployment model

`config/` files are deployed to `$HOME` either as **symlinks** or **copies**. `scripts/check-drift.sh` classifies each managed path:

- `symlink` — should point back to the repo; drift = wrong/missing link
- `copy` — must match the repo by md5; drift = re-run `init_mac.sh` or `cp` the file
- `machine` — machine-specific, diffs are expected and informational only

After editing a `config/` file, deploy it (`cp config/.zshrc ~/.zshrc`, etc.) or run `init_mac.sh` so the deployed copy stays in sync.

## init_mac.sh

`scripts/init_mac.sh` is the single entrypoint for provisioning a new Mac. It uses two path variables:

- `SCRIPT_DIR` — the `scripts/` directory
- `REPO_DIR` — the repo root (`SCRIPT_DIR/..`)

All file references use `${REPO_DIR}/config/...`, `${REPO_DIR}/packages/...`, etc. The script is idempotent — each function checks for existing installations before acting. `setup_claude()` deploys `apps/claude/CLAUDE.md` + `settings.json` to `~/.claude/`.

## apps/claude/skills

`apps/claude/skills/` holds SKILL.md files that mirror upstream skills. `.update-skills.py` (run via `make update-skills` / `make check`) fetches the latest SKILL.md from each upstream URL and re-injects the local `source:` frontmatter field. Use `make check` for a dry-run diff before committing updates.

## CI

`.github/workflows/weekly-software-check.yml` runs every Monday (`0 8 * * 1` UTC) to validate that `packages/Brewfile` entries still exist. Two jobs:

- `check-brew` — validates formulas (`brew info`) and casks (via `formulae.brew.sh` API, since casks aren't installable on the Linux runner); tap formulas (`owner/tap/name`) are skipped. Emits the pruned Brewfile as an artifact.
- `create-pr` — applies the removals and opens a PR if anything changed.

Homebrew is cached between runs; `concurrency: weekly-software-check` prevents overlapping runs.

## Pre-commit Hooks

Hooks enforced on every commit:

- **gitleaks** — secret scanning (hardcoded credentials, tokens, keys)
- **shellcheck** — shell script linting, severity `warning`. Excludes zsh files matching `(^|/)\.zsh`.
- **shfmt** — shell formatting: 4-space indent, `-ci -bn -sr`.
- **markdownlint** — `--fix`, requires H1 as first line, single H1 per file, language on all fenced code blocks (use `text` for file trees). Excludes `apps/claude/skills/` (upstream-managed).
- **yamllint** — config in `.yamllint.yaml`
- **prettier** — JSON formatting, 4-space indent. Excludes `apps/claude/settings.json`.
- **conventional-pre-commit** — enforces Conventional Commits on commit messages (`feat:`, `fix:`, `chore:`, `docs:`, `perf:`, `refactor:`)

`apps/claude/CLAUDE.md` is globally excluded from all hooks (`exclude:` at top of config).
