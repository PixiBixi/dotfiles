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
make update-claude-skills # skillfish update + re-bundle packages/skillfish.json
make check               # dry-run: show skill diffs without writing
make help                # list targets

# Deploy / provision (idempotent)
./scripts/init_mac.sh

# Check for drift between config/ and deployed $HOME files
./scripts/check-drift.sh

# Audit Homebrew packages by binary atime (catches aliases, hooks, LSPs, agents)
./scripts/brew-usage-audit.sh [--stale-days N] [--leaves-only] [--all] [--json FILE]

# Pre-commit
pre-commit install                 # after cloning
pre-commit run --all-files         # run all hooks
pre-commit run shellcheck          # run one hook
pre-commit autoupdate              # bump hook versions
```

## Repository Structure

macOS dotfiles repo organized into four purpose-driven directories:

- `config/`: dotfiles deployed to `$HOME` (zsh, git, nvim, ssh, kube, tmux, vim, wezterm). Mirrors the target `$HOME` path structure.
- `packages/` holds the package lists: `Brewfile`, `krew-indexes.txt`, `npm.txt`, `gems.txt`, `skillfish.json`. **krew plugins live inside the `Brewfile`** as `krew "..."` entries (no separate `krew.txt`). Custom krew *indexes* do need their own file: `brew bundle` only shells out to `kubectl krew install <name>`, it never adds an index, so any `krew "<index>/<plugin>"` entry (`netshoot/`, `pixibixi/`) would fail on a fresh machine. `krew-indexes.txt` lists them as `<name> <git url>` and the `krew-indexes` step in `init_mac.sh` registers them **before** `brew-packages` runs. Refresh it with `make update-krew-indexes`.
- `apps/` holds the non-dotfile app configs:
  - `claude/`: `CLAUDE.md` + `settings.json` (versioned source for `~/.claude/`), `skills/` (managed SKILL.md files + `.update-skills.py`), `hooks/` (`session-allow.sh`, `wiki-sync.sh`, `wordlist-guard.sh`), `config/` (per-hook JSON config, symlinked flat into `~/.claude/`)
  - `raycast/`, `vscode/`
- `scripts/`: `init_mac.sh` (main setup), `check-drift.sh`, `brew-usage-audit.sh`, `init.sh` (legacy, do not use)

Repo-level tooling files stay at root: `Makefile`, `.pre-commit-config.yaml`, `.yamllint.yaml`, `.prettierignore`. Note: `.markdownlint.json` lives in `config/` (deployed to `$HOME`) and is referenced via `--config config/.markdownlint.json` in the pre-commit hook.

## Deployment model

`config/` files are deployed to `$HOME` either as **symlinks** or **copies**. `scripts/check-drift.sh` classifies each managed path:

- `symlink`: should point back to the repo; drift = wrong/missing link
- `copy`: must match the repo by md5; drift = re-run `init_mac.sh` or `cp` the file
- `machine`: machine-specific, diffs are expected and informational only

After editing a `config/` file, deploy it (`cp config/.zshrc ~/.zshrc`, etc.) or run `init_mac.sh` so the deployed copy stays in sync.

`check-drift.sh` also covers `~/.claude`: `CLAUDE.md`, `settings.json`, every `apps/claude/hooks/*.sh`, every `apps/claude/config/*.json` and every `apps/claude/skills/*/`. All three are enumerated from the same globs `setup_claude()` deploys, so adding one needs no edit here. Two extra verdicts apply there:

- `ORPHAN`: a file in `~/.claude/hooks/` with no repo counterpart. It may still be wired into `settings.json` while nothing versions it.
- a skill deployed as a **real directory** instead of a symlink means an external installer owns it, see `Externally-managed skills` below.

It also checks the krew indexes from `packages/krew-indexes.txt` against `kubectl-krew index list`. This is the safety net for running `brew bundle install` directly instead of `init_mac.sh`, which bypasses the `krew-indexes` step:

- `NOT REGISTERED` is an **error**: every `krew "<index>/<plugin>"` entry of the Brewfile fails without it, and the fix command is printed inline.
- `WRONG URL` warns that the index name points somewhere else than the repo says.
- `ORPHAN`: an index registered locally but absent from `krew-indexes.txt`, so it is lost on the next machine. Version it with `make update-krew-indexes`.

## init_mac.sh

`scripts/init_mac.sh` is the single entrypoint for provisioning a new Mac. It uses two path variables:

- `SCRIPT_DIR`: the `scripts/` directory
- `REPO_DIR`: the repo root (`SCRIPT_DIR/..`)

All file references use `${REPO_DIR}/config/...`, `${REPO_DIR}/packages/...`, etc. The script is idempotent: each function checks for existing installations before acting. `setup_claude()` deploys `apps/claude/CLAUDE.md` + `settings.json` to `~/.claude/`; `setup_rtk()` runs `rtk init --global`, which generates `~/.claude/RTK.md` (unversioned on purpose, it tracks the installed rtk version) and wires the PreToolUse hook in `settings.json`. Since rtk 0.44 that hook is the built-in `rtk hook claude`; older versions generated a `~/.claude/hooks/rtk-rewrite.sh` wrapper that no longer exists, so re-run `rtk init --global` after a major rtk upgrade and commit the resulting `settings.json` delta.

## apps/claude/hooks

Each hook resolves its own config, first readable file wins: `$CLAUDE_<NAME>_CONFIG`, then
`./.claude/<name>.json` (per repo), then `~/.claude/<name>.json`. `apps/claude/config/*.json` is the
versioned source of that last stop, symlinked **flat** into `~/.claude/` by `setup_claude()`, so a
hook needs no path knowledge and a new config file needs no edit to `init_mac.sh` or
`check-drift.sh`.

Every hook exits 0 on a missing or malformed config and falls back to its built-in defaults: a
broken config can never break a session. The flip side is that the only symptom of a config that
failed to deploy is a rule quietly not enforced, which is why `check-drift.sh` checks them.

| Hook | Event | Does |
|------|-------|------|
| `session-allow.sh` | PermissionRequest | Per-session prefix allowlist behind an osascript dialog (Session / Once / Deny / Claude), TTL 12h |
| `wiki-sync.sh` | SessionEnd | Runs `/openwiki:wiki update` detached, commits and pushes `openwiki/` on the default branch only |
| `wordlist-guard.sh` | PostToolUse `Write\|Edit` | Flags banned characters and words that just landed in a file, via `additionalContext` |

`wordlist-guard.sh` is the floor under the writing rules in `apps/claude/CLAUDE.md`: a standing rule
gets diluted with no error raised, and chat replies cannot be hooked, so this covers where written
text persists. Config in `apps/claude/config/wordlist-guard.json`:

- `bannedChars`: `U+2014` / `U+2013` (the em dash rule). Entries are `U+XXXX` or a literal character.
- `bannedWords`: the non-inclusive terms named in `CLAUDE.md`. Prefix an entry with `re:` for a raw
  regex, otherwise it matches the word with an optional trailing `s`.
- `allowPaths`: `apps/claude/skills/` (upstream-managed, same exclusion markdownlint uses), plus
  vendored and generated trees. An entry containing `/` is a substring or glob match on the full
  path, otherwise it globs the basename.

Adding a word is a one-line edit to that JSON, no script change. Widen `bannedWords` only for rules
that are actually written down in `CLAUDE.md`: a hook enforcing a rule that exists nowhere else is
how false positives get normalised.

## apps/claude/skills

`apps/claude/skills/` holds SKILL.md files that mirror upstream skills. `.update-skills.py` (run via `make update-skills` / `make check`) fetches the latest SKILL.md from each upstream URL and re-injects the local `source:` frontmatter field. Use `make check` for a dry-run diff before committing updates.

Locally-authored skills live here too (e.g. `incident-response/`): a SKILL.md with no `source:` field is skipped by the updater, so it is never clobbered. `setup_claude()` symlinks **every** directory in `apps/claude/skills/` into `~/.claude/skills/`, so a new skill needs no change to `init_mac.sh`.

### Externally-managed skills

Skills owned by their own installer are **never** vendored here, only the provenance needed to reinstall them. `install_claude_skills()` (step `claude-skills`) handles all four cases:

| Skill | Installer |
|-------|-----------|
| `linkedin-best-practices-2026`, `python3-development`, `terragrunt-generator` | `npx skillfish install --global` from `packages/skillfish.json` |
| `ui-ux-pro-max` | `uipro init --ai claude --global` (npm `ui-ux-pro-max-cli`) |
| `humanizer` | `git clone github.com/blader/humanizer` |
| `seo` | `Bhanunamikaze/Agentic-SEO-Skill` `install.sh --target claude` (also deploys the `seo-*` agents to `~/.claude/agents/`) |

`packages/skillfish.json` is generated by `npx skillfish bundle --global`, which only captures skills carrying a `.skillfish.json` manifest, hence the three explicit cases above. Refresh it with `make update-claude-skills`.

Rule of thumb: `~/.claude/skills/<name>` being a **symlink** means the repo owns it; a **real directory** means an external installer owns it. `skillfish list` shows exactly the second group.

`make update-skills` passes `--commit`, so each updated skill is committed on its own (`chore(claude): sync <name> skill from upstream`), one commit per scope, no manual staging. Run the script without `--commit` to update files without committing; `--check` never commits.

## CI

`.github/workflows/weekly-software-check.yml` runs every Monday (`0 8 * * 1` UTC) to validate that `packages/Brewfile` entries still exist. Two jobs:

- `check-brew`: validates formulas (`brew info`) and casks (via `formulae.brew.sh` API, since casks aren't installable on the Linux runner); tap formulas (`owner/tap/name`) are skipped. Emits the pruned Brewfile as an artifact.
- `create-pr`: applies the removals and opens a PR if anything changed.

Homebrew is cached between runs; `concurrency: weekly-software-check` prevents overlapping runs.

## Pre-commit Hooks

Hooks enforced on every commit:

- **gitleaks**: secret scanning (hardcoded credentials, tokens, keys)
- **shellcheck**: shell script linting, severity `warning`. Excludes zsh files matching `(^|/)\.zsh`.
- **shfmt**: shell formatting, 4-space indent, `-ci -bn -sr`.
- **markdownlint**: `--fix`, requires H1 as first line, single H1 per file, language on all fenced code blocks (use `text` for file trees). Excludes `apps/claude/skills/` (upstream-managed).
- **yamllint**: config in `.yamllint.yaml`
- **prettier**: JSON formatting, 4-space indent. Excludes `apps/claude/settings.json`.
- **conventional-pre-commit**: enforces Conventional Commits on commit messages (`feat:`, `fix:`, `chore:`, `docs:`, `perf:`, `refactor:`)

`apps/claude/CLAUDE.md` is globally excluded from all hooks (`exclude:` at top of config).
