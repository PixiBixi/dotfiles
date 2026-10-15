# Ideas

Backlog of changes worth doing later. Not commitments.

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
