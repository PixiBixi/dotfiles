# Ideas

Backlog of changes worth doing later. Not commitments.

## From a comparison with 13 public dotfiles repos (2026-10)

Compared against ahmetb, jessfraz, mitchellh/nixos-config, caarlos0, jonhoo/configs, nicknisi, holman, mathiasbynens, twpayne, geerlingguy, alrra, paulirish and tjdevries/config_manager.

Where this repo is already ahead: infra tooling (only ahmetb comes close: krew indexes, kube switch, terragrunt helpers), drift detection (`make drift`, nobody else has it), measured shell startup (only nicknisi caches compinit, only ahmetb defers plugins), pre-commit coverage (gitleaks, shellcheck, shfmt, yamllint), Renovate plus the weekly Brewfile prune, and the Claude Code config as a first-class component (ahmetb and nicknisi do the same).

Ranked by gain over effort:

| Idea | Seen in | Effort |
|---|---|---|
| Run the existing pre-commit hooks in CI on every push (today only local) | alrra (shellcheck + markdownlint + link check on macos-latest) | low |
| Clean dead weight: `scripts/init.sh` (Vundle, old Homebrew installer), `config/.vimrc`, empty `package.json`/`package-lock.json`, EOL formulas (`python@3.9`, `python@3.10`, `ffmpeg@4`) | - | low |
| Generalize the untracked local override (`~/.zsh_work`) into `~/.zshrc.local` and `~/.gitconfig.local`, created empty on first bootstrap, never overwritten | alrra `create_local_config_files.sh`, holman, paulirish | low |
| GCP helpers: `gcurl` / `runcurl` aliases (curl with an access or identity token) | ahmetb `zsh_aliases.inc` | low |
| `kubecolor` aliased to `kubectl` only when installed | ahmetb `.zshrc` (`has'kubecolor'`) | low |
| A `kdebug` alias running a toolbox pod | caarlos0 `fish/config.fish` | low |
| `--dry-run` for `init_mac.sh`: every side effect goes through one `run()` wrapper | nicknisi `install.sh` | medium |
| Symlink everything, drop the `copy` mode of `deploy_file`, and refuse to overwrite a real file instead of `ln -sf` over it | caarlos0 `setup` `link()`, alrra `create_symbolic_links.sh` | medium |
| Secrets as `op://` references resolved at runtime instead of `~/.zsh_work_secrets` | mitchellh `home-manager.nix`, twpayne `onepasswordRead` | medium |
| Smoke-test the bootstrap in CI (`init_mac.sh --dry-run` on a macOS runner) | nicknisi devcontainer smoke test, jessfraz `nix flake check` matrix | medium, needs `--dry-run` first |
| Pin infra CLI versions (terraform, kubectl, helm) with mise instead of unpinned Homebrew formulas | nicknisi `mise.toml` | medium |
| Per-machine profiles (work vs personal Brewfile, identity) chosen by hostname | caarlos0 `Brewfile.<host>`, twpayne chezmoi tags | medium, only if a second Mac appears |

Not worth it here: Nix (jessfraz, mitchellh, jonhoo), heavy and VM-centric; chezmoi (twpayne), a full migration whose main gain is multi-machine templating.

## Drop oh-my-zsh entirely

`config/.zshrc` no longer sources `oh-my-zsh.sh`: a minimal loader sources 12 of its `lib/` files, 6 plugins and the `robbyrussell` theme straight from `~/.oh-my-zsh`. Interactive startup is ~95 ms, so removing the rest is about owning the config, not speed. `omz update` is not needed.

| Still used from oh-my-zsh | Replacement |
|---|---|
| `lib/` (history, key bindings, completion zstyles, directories, misc) | ~30 lines of `setopt`, `bindkey` and `zstyle` in the dotfiles |
| `zsh-defer` (in `custom/plugins`) | standalone clone of romkatv/zsh-defer |
| `kube-ps1` | `brew install kube-ps1` |
| `kubectl`, `helm`, `terraform`, `aws` plugins | vendor the alias files; completions already come from Homebrew |
| `ssh-agent` plugin | `AddKeysToAgent yes` + `UseKeychain yes` in `~/.ssh/config` |
| `robbyrussell` + async git prompt (`lib/async_prompt.zsh`, `lib/git.zsh`) | keep the prompt async: vendor both files, or starship. Plain `vcs_info` is synchronous and blocks the prompt |

How to check: snapshot `alias`, `setopt`, `zstyle -L`, `bindkey -L` and `${(ok)functions}` before and after, then diff. Do it on a branch.

Watch out: the `ssh-agent` plugin names its cache file after `$SHORT_HOST`; if it is unset, every shell starts a new agent.
