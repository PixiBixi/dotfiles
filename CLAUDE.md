# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

```bash
# Run all pre-commit hooks manually
pre-commit run --all-files

# Run a specific hook
pre-commit run shellcheck
pre-commit run markdownlint

# Install hooks after cloning
pre-commit install

# Run the macOS setup script
./scripts/init_mac.sh
```

## Repository Structure

This is a macOS dotfiles repo organized into four purpose-driven directories:

- `config/` — dotfiles deployed to `$HOME` (zsh, git, nvim, ssh, kube, tmux, vim, wezterm). Mirrors the target `$HOME` path structure.
- `packages/` — package lists: `Brewfile`, `npm.txt`, `gems.txt`, `krew.txt`
- `apps/` — non-dotfile app configs: `claude/CLAUDE.md`, `raycast/`, `vscode/`
- `scripts/` — `init_mac.sh` (main setup), `init.sh` (legacy)

Repo-level tooling files stay at root: `.pre-commit-config.yaml`, `.yamllint.yaml`. Note: `.markdownlint.json` lives in `config/` (deployed to `$HOME`) and is referenced via `--config config/.markdownlint.json` in the pre-commit hook.

## init_mac.sh

`scripts/init_mac.sh` is the single entrypoint for provisioning a new Mac. It uses two path variables:

- `SCRIPT_DIR` — the `scripts/` directory
- `REPO_DIR` — the repo root (`SCRIPT_DIR/..`)

All file references use `${REPO_DIR}/config/...`, `${REPO_DIR}/packages/...`, etc. The script is idempotent — each function checks for existing installations before acting.

## CI

`.github/workflows/weekly-software-check.yml` runs every Monday to validate that Homebrew formulae and krew plugins still exist. It auto-creates a PR removing stale entries from `packages/Brewfile` and `packages/krew.txt`.

## Pre-commit Hooks

Hooks enforced on every commit:

- **shellcheck** — shell script linting, severity `warning`. Excludes zsh files matching `(^|/)\.zsh`.
- **shfmt** — shell formatting: 4-space indent, `-ci -bn -sr`.
- **markdownlint** — requires H1 as first line, single H1 per file, language on all fenced code blocks. Use `text` for file trees.
- **yamllint** — config in `.yamllint.yaml`
- **prettier** — JSON formatting, 4-space indent
- **conventional-pre-commit** — enforces Conventional Commits on commit messages (`feat:`, `fix:`, `chore:`, `docs:`, `perf:`, `refactor:`)
