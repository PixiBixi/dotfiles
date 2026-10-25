# AGENTS.md

Guidance for coding agents working in this repository.

## Common Commands

```bash
# Regenerate package lists + sync skills from upstream (see Makefile)
make update              # all: brew, krew indexes, npm, gems, skills, Claude skills, Claude plugins
make update-brew         # dump installed Homebrew packages → packages/Brewfile
make update-krew-indexes # custom krew indexes → packages/krew-indexes.txt
make update-npm          # global npm packages → packages/npm.txt
make update-gems         # installed gems → packages/gems.txt
make update-skills       # fetch latest SKILL.md from upstream, delegated to the claude-skills clone
make update-claude-skills # skillfish update + re-bundle packages/skillfish.json
make update-claude-plugins # refresh marketplaces + update every marketplace-backed plugin
make check               # dry-run of update-skills in the claude-skills clone
make drift               # check drift between config/ and deployed $HOME files
make help                # list targets

# Deploy / provision (idempotent)
./scripts/init_mac.sh

# Check for drift between config/ and deployed $HOME files
./scripts/check-drift.sh

# Audit Homebrew packages by binary atime (catches aliases, hooks, LSPs, agents)
./scripts/brew-usage-audit.sh [--stale-days N] [--leaves-only] [--all] [--history FILE] [--json FILE]

# Run a Terragrunt command per impacted unit, with readable output
tg-run [<command>] [<unit dir>...]

# Close Chrome tabs of merged/closed GitLab MRs, passed CI jobs/pipelines and done Jira tickets (-n: dry run)
close-done-tabs [-n]

# Pre-commit
pre-commit install                 # after cloning
pre-commit run --all-files         # run all hooks
pre-commit run shellcheck          # run one hook
pre-commit autoupdate              # bump hook versions
```

## Repository Structure

macOS dotfiles repo organized into four purpose-driven directories:

- `config/`: dotfiles deployed to `$HOME` (zsh, git, nvim, ssh, kube, tmux, vim, wezterm). Mirrors the target `$HOME` path structure. `config/.local/bin/` holds user commands deployed onto `$PATH` (`tg-run`), as opposed to `scripts/`, which are repo-maintenance scripts run from the clone.
- `packages/` holds the package lists: `Brewfile`, `krew-indexes.txt`, `npm.txt`, `gems.txt`, `skillfish.json`. **krew plugins live inside the `Brewfile`** as `krew "..."` entries (no separate `krew.txt`). Custom krew *indexes* do need their own file: `brew bundle` only shells out to `kubectl krew install <name>`, it never adds an index, so any `krew "<index>/<plugin>"` entry (`netshoot/`, `pixibixi/`) would fail on a fresh machine. `krew-indexes.txt` lists them as `<name> <git url>` and the `krew-indexes` step in `init_mac.sh` registers them **before** `brew-packages` runs. Refresh it with `make update-krew-indexes`.
- `apps/` holds the non-dotfile app configs:
  - `claude/`: `CLAUDE.md` + `settings.json` (versioned source for `~/.claude/`), `hooks/` (`session-allow.sh`, `wiki-sync.sh`, `wordlist-guard.sh`, `cold-resume-guard.sh`), `config/` (per-hook JSON config, symlinked flat into `~/.claude/`)
  - `raycast/`, `vscode/`
- `scripts/`: `init_mac.sh` (main setup), `check-drift.sh`, `brew-usage-audit.sh`

Repo-level tooling files stay at root: `Makefile`, `.pre-commit-config.yaml`, `.yamllint.yaml`, `.prettierignore`. Note: `.markdownlint.json` lives in `config/` (deployed to `$HOME`) and is referenced via `--config config/.markdownlint.json` in the pre-commit hook.

## Deployment model

`config/` files are deployed to `$HOME` either as **symlinks** or **copies**. `scripts/check-drift.sh` classifies each managed path:

- `symlink`: should point back to the repo; drift = wrong/missing link
- `copy`: must match the repo by md5; drift = re-run `init_mac.sh` or `cp` the file
- `machine`: machine-specific, diffs are expected and informational only

Symlinked files are live after an edit. The `copy_files` list in `init_mac.sh` needs `init_mac.sh --only dotfiles` (or a `cp`) to resync the deployed copy.

`check-drift.sh` also covers `~/.claude`: `CLAUDE.md`, `settings.json`, every `apps/claude/hooks/*.sh`, every `apps/claude/config/*.json` and every skill of the `claude-skills` clone. All three are enumerated from the same globs `setup_claude()` deploys, so adding one needs no edit here. Extra verdicts apply there:

- `ORPHAN`: a file in `~/.claude/hooks/` with no repo counterpart. It may still be wired into `settings.json` while nothing versions it.
- `NOT CLONED` is an **error**: the `claude-skills` clone is missing next to this repo, so no skill is checked. Fix with `scripts/init_mac.sh --only claude`.
- a skill deployed as a **real directory** instead of a symlink means an external installer owns it, see `Externally-managed skills` below.

It also checks the krew indexes from `packages/krew-indexes.txt` against `kubectl-krew index list`. This is the safety net for running `brew bundle install` directly instead of `init_mac.sh`, which bypasses the `krew-indexes` step:

- `NOT REGISTERED` is an **error**: every `krew "<index>/<plugin>"` entry of the Brewfile fails without it, and the fix command is printed inline.
- `WRONG URL` warns that the index name points somewhere else than the repo says.
- `ORPHAN`: an index registered locally but absent from `krew-indexes.txt`, so it is lost on the next machine. Version it with `make update-krew-indexes`.

It checks the Claude Code plugins against `apps/claude/settings.json`, the safety net for the `claude-plugins` step:

- `NOT ADDED` / `NOT INSTALLED` is an **error**: a marketplace of `extraKnownMarketplaces` or an `enabledPlugins` entry missing locally. Fix with `scripts/init_mac.sh --only claude-plugins`.
- `ORPHAN`: a marketplace added locally but not declared (`claude-plugins-official` is built in and skipped), or an **enabled** plugin absent from `enabledPlugins`. `equativ-plugins` is expected here: its private URL stays out of this public repo.

## init_mac.sh

`scripts/init_mac.sh` is the single entrypoint for provisioning a new Mac. It uses two path variables:

- `SCRIPT_DIR`: the `scripts/` directory
- `REPO_DIR`: the repo root (`SCRIPT_DIR/..`)

All file references use `${REPO_DIR}/config/...`, `${REPO_DIR}/packages/...`, etc. The script is idempotent: each function checks for existing installations before acting. `setup_claude()` deploys `apps/claude/CLAUDE.md` + `settings.json` + `keybindings.json` to `~/.claude/`; `install_claude_plugins()` (step `claude-plugins`) adds every marketplace of `extraKnownMarketplaces` and installs every `enabledPlugins` entry set to `true`, so `settings.json` is the single plugin list (a marketplace missing from it, like the private `equativ-plugins`, must be added by hand first); `setup_rtk()` runs `rtk init --global`, which generates `~/.claude/RTK.md` (unversioned on purpose, it tracks the installed rtk version) and wires the PreToolUse hook in `settings.json`. Since rtk 0.44 that hook is the built-in `rtk hook claude`; older versions generated a `~/.claude/hooks/rtk-rewrite.sh` wrapper that no longer exists, so re-run `rtk init --global` after a major rtk upgrade and commit the resulting `settings.json` delta.

## apps/claude/hooks

Each hook resolves its own config, first readable file wins: `$CLAUDE_<NAME>_CONFIG`, then `./.claude/<name>.json` (per repo), then `~/.claude/<name>.json`. `apps/claude/config/*.json` is the versioned source of that last stop, symlinked **flat** into `~/.claude/` by `setup_claude()`, so a hook needs no path knowledge and a new config file needs no edit to `init_mac.sh` or `check-drift.sh`.

Every hook exits 0 on a missing or malformed config and falls back to its built-in defaults: a broken config can never break a session. The flip side is that the only symptom of a config that failed to deploy is a rule quietly not enforced, which is why `check-drift.sh` checks them.

| Hook | Event | Does |
|------|-------|------|
| `session-allow.sh` | PermissionRequest | Per-session prefix allowlist behind an osascript dialog (Session / Once / Deny / Claude), TTL 12h |
| `wiki-sync.sh` | SessionEnd | Runs `/openwiki:wiki update` detached, commits and pushes `openwiki/` on the default branch only |
| `wordlist-guard.sh` | PostToolUse `Write\|Edit` | Flags banned characters and words that just landed in a file, via `additionalContext` |
| `home-dir-nudge.sh` | SessionStart `startup` | When a session starts from `$HOME` (no project CLAUDE.md), shows a message pointing to the ops workspace read from `~/.config/claude/ops-dir` (first line, versioned in the private repo that owns it); silent elsewhere |
| `cold-resume-guard.sh` | UserPromptSubmit | Blocks once the first prompt to a session idle over 1h with over 150k tokens of context (expired cache), showing the re-write cost; re-sending passes. Thresholds: `COLD_RESUME_IDLE_SECONDS`, `COLD_RESUME_CTX_TOKENS` |

`wordlist-guard.sh` is the floor under the writing rules in `apps/claude/CLAUDE.md`: a standing rule gets diluted with no error raised, and chat replies cannot be hooked, so this covers where written text persists. Config in `apps/claude/config/wordlist-guard.json`:

- `bannedChars`: `U+2014` / `U+2013` (the em dash rule) and `U+2022` (the bullet rule). Entries are `U+XXXX` or a literal character.
- `bannedWords`: the non-inclusive terms named in `CLAUDE.md`. Prefix an entry with `re:` for a raw regex, otherwise it matches the word with an optional trailing `s`.
- `allowPaths`: vendored and generated trees. The upstream-managed skills are allowed by the per-repo `.claude/wordlist-guard.json` of `claude-skills`. An entry containing `/` is a substring or glob match on the full path, otherwise it globs the basename.

Adding a word is a one-line edit to that JSON, no script change. Widen `bannedWords` only for rules that are actually written down in `CLAUDE.md`: a hook enforcing a rule that exists nowhere else is how false positives get normalised.

## Skills

Locally-authored and upstream-mirrored skills live in [PixiBixi/claude-skills](https://github.com/PixiBixi/claude-skills), not here. `setup_claude()` clones it next to this repo if missing, then symlinks **every** directory of its `skills/` into `~/.claude/skills/`, so a new skill needs no change to `init_mac.sh`. Symlinks rather than a plugin install keep the short names (`/mr-open`, not `/pixibixi:mr-open`) and live edits. Never install the `pixibixi` plugin on top: each skill would load twice.

Edit, commit and push skills in that clone. `make update-skills` and `make check` here only delegate to its Makefile.

### Externally-managed skills

Skills owned by their own installer are **never** vendored here, only the provenance needed to reinstall them. `install_claude_skills()` (step `claude-skills`) handles two cases:

| Skill | Installer |
|-------|-----------|
| `archify`, `gcx`, `create-dashboard`, `investigate-alert`, `setup-gcx`, `humanizer`, `python3-development`, `retro`, `security-audit` | `npx skillfish install --global` from `packages/skillfish.json` |
| `tickler` | `tickler skill install` (cask `pixibixi/tap/tickler`, installs the skill matching the CLI version) |

**skillfish is the default channel: add a new external skill there, not through a third installer.** It installs any skill straight from a GitHub repo, `owner/repo` plus an optional path (`--path archify`, `--path skills/hallmark`), and stamps a `.skillfish.json` in the deployed directory. `packages/skillfish.json` is generated by `npx skillfish bundle --global`, which captures exactly the skills carrying that stamp, so an `npx skillfish add ... --global` followed by `make update-claude-skills` versions the skill with **no edit to `init_mac.sh` and no new make target**. `tickler` stays out only because its installer does more than drop a skill directory: it pins the skill to the CLI version.

Migrating a plugin to skillfish: only when it ships nothing but skills (no hook, command, MCP server or `${CLAUDE_PLUGIN_ROOT}` runtime; a thin wrapper agent like `gcx` grafana-debugger is an acceptable loss). Uninstall the plugin but keep its marketplace in `extraKnownMarketplaces`: the `retro` skill reads marketplace catalogues, not `~/.claude/skills`, to find a skill's upstream repo.

That is why `npx skills add <repo> -g` (the `vercel-labs/skills` CLI) must not be used here: it installs to `~/.agents/skills/` and symlinks into `~/.claude/skills/`, a store nothing in this repo versions or checks, so the skill silently vanishes on the next machine. `skillfish add` takes the same GitHub arguments. Verified equivalent: for `archify` both channels deploy an identical 166-file payload.

Rule of thumb: `~/.claude/skills/<name>` being a **symlink** means the `claude-skills` clone owns it; a **real directory** means an external installer owns it. `skillfish list` shows exactly the second group, but only for real directories - it does not follow symlinks, so a skill linked in from elsewhere is invisible to both `list` and `bundle`.

## CI

`.github/workflows/pre-commit.yml` runs `pre-commit run --all-files` on every push to `master` and on every PR, so the local hooks are enforced even when a commit skipped them. Hook environments are cached on the hash of `.pre-commit-config.yaml`.

`.github/workflows/weekly-software-check.yml` runs every Monday (`0 8 * * 1` UTC) to validate that `packages/Brewfile` entries still exist. Two jobs:

- `check-brew`: validates formulas (`brew info`) and casks (via `formulae.brew.sh` API, since casks aren't installable on the Linux runner); tap formulas (`owner/tap/name`) are skipped. Emits the pruned Brewfile as an artifact.
- `create-pr`: applies the removals and opens a PR if anything changed.

Homebrew is cached between runs; `concurrency: weekly-software-check` prevents overlapping runs.

## Pre-commit Hooks

Hooks enforced on every commit:

- **gitleaks**: secret scanning (hardcoded credentials, tokens, keys)
- **shellcheck**: shell script linting, severity `warning`. Excludes zsh files matching `(^|/)\.zsh`.
- **shfmt**: shell formatting, 4-space indent, `-ci -bn -sr`.
- **markdownlint**: `--fix`, config `config/.markdownlint.json`, pinned to `markdownlint-cli` v0.43.0. Requires H1 as first line, single H1 per file, and language on all fenced code blocks (use `text` for file trees). Note: the pinned version predates the `MD060` table-column-style rule, so misaligned table pipes are not currently flagged even though `config/.markdownlint.json` sets `MD055` (pipe style).
- **yamllint**: config in `.yamllint.yaml`
- **prettier**: JSON formatting, 4-space indent. Excludes `apps/claude/settings.json` and `packages/skillfish.json` (both machine-generated).
- **conventional-pre-commit**: enforces Conventional Commits on commit messages (`feat:`, `fix:`, `chore:`, `docs:`, `perf:`, `refactor:`)
- **pre-commit-hooks** (upstream standard set): `trailing-whitespace`, `end-of-file-fixer`, `check-yaml`, `check-json`, `check-added-large-files`, `check-merge-conflict`, `check-case-conflict`, `check-executables-have-shebangs`, `check-shebang-scripts-are-executable`, `detect-private-key`, `mixed-line-ending`

`apps/claude/CLAUDE.md` is globally excluded from all hooks (`exclude:` at top of config).
