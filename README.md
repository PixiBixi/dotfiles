# dotfiles

Configuration complète pour macOS avec installation automatisée.

## Quick Start

```bash
git clone https://github.com/PixiBixi/dotfiles.git ~/dotfiles
cd ~/dotfiles
./scripts/init_mac.sh
```

Le script est **idempotent** : vous pouvez le relancer sans risque.

## Prérequis

- macOS (Ventura ou plus récent recommandé)
- Connexion internet
- Droits administrateur (pour Xcode Command Line Tools)

Le script installe automatiquement :

- Xcode Command Line Tools
- Homebrew
- oh-my-zsh + plugins
- Tous les packages listés dans `packages/` (formulas, casks, krew plugins, npm, gems via Brewfile)

## Structure du Repository

```text
dotfiles/
├── config/                      # Dotfiles, miroir de $HOME
│   ├── .zshrc
│   ├── .zsh_alias
│   ├── .zsh_functions
│   ├── .zsh_linux
│   ├── .zsh_mac
│   ├── .gitconfig
│   ├── .gitconfig_perso
│   ├── .gitconfig_work
│   ├── .tmux.conf
│   ├── .vimrc
│   ├── .wezterm.lua
│   ├── .markdownlint.json
│   ├── .ssh/
│   │   └── config
│   ├── .kube/
│   │   └── switch-config.yaml
│   └── .config/
│       ├── git/                 # allowed_signers, ignore
│       └── nvim/
├── packages/                    # Listes de paquets à installer
│   ├── Brewfile                 # Formulas, casks, krew plugins, npm, gems
│   ├── krew-indexes.txt         # Index krew custom, ajoutés avant le Brewfile
│   ├── npm.txt
│   ├── gems.txt
│   └── skillfish.json           # Manifeste des skills Claude externes
├── apps/                        # Configs d'applications non-dotfiles
│   ├── claude/
│   │   ├── CLAUDE.md
│   │   ├── settings.json
│   │   ├── hooks/               # session-allow.sh, wiki-sync.sh, wordlist-guard.sh
│   │   ├── config/              # Config JSON par hook, symlinkée dans ~/.claude/
│   │   └── skills/              # SKILL.md upstream + skills locales
│   ├── raycast/
│   │   └── Raycast.rayconfig
│   └── vscode/
│       ├── settings.json
│       └── extensions.txt
│   └── .local/
│       └── bin/
│           └── tg-run           # Runner Terragrunt à sortie lisible, déployé sur le $PATH
├── scripts/
│   ├── init_mac.sh              # Script d'installation principal
│   ├── check-drift.sh           # Diff entre config/ et les fichiers déployés
│   ├── brew-usage-audit.sh      # Audit packages Homebrew via l'atime des binaires
│   └── init.sh                  # Legacy, ne pas utiliser
├── Makefile
├── .pre-commit-config.yaml
└── .yamllint.yaml
```

## Post-Installation

### 1. Configuration Git

Éditer vos identités Git :

```bash
# Personnel
vim ~/.gitconfig_perso

# Professionnel
vim ~/.gitconfig_work
```

Dans votre `.gitconfig` principal, incluez conditionnellement :

```ini
[includeIf "gitdir:~/Documents/perso/"]
    path = ~/.gitconfig_perso

[includeIf "gitdir:~/Documents/work/"]
    path = ~/.gitconfig_work
```

Deux fichiers sous `config/.config/git/` sont symlinkés vers `~/.config/git/` :

- `allowed_signers` : référencé par `gpg.ssh.allowedSignersFile`. Adresse courante en premier, domaines historiques après, séparés par des virgules sur la même ligne
- `ignore` : gitignore global, lu par défaut à cet emplacement

### 2. Kubeconfig

Split votre kubeconfig en plusieurs fichiers :

```bash
kubectl konfig split -o ~/.kube/configs
```

### 3. Google Cloud (GKE)

Configurer les Application Default Credentials pour que kubeswitch découvre les clusters GKE sans prompt d'authentification répété :

```bash
gcloud auth application-default login
```

À relancer si kubeswitch redemande l'auth Google (token expiré, renouvellement de session SSO).

### 4. Shell

```bash
source ~/.zshrc
```

### 5. Pre-commit

```bash
pre-commit install
```

## Maintenance

### Cibles make

```bash
make help          # lister les targets
```

| Target | Effet |
| -------- | ------- |
| `update` | Tout : brew, krew indexes, npm, gems, skills, skills Claude |
| `update-brew` | Dump les packages Homebrew installés vers `packages/Brewfile` |
| `update-krew-indexes` | Dump les index krew custom vers `packages/krew-indexes.txt` |
| `update-npm` | Dump les packages npm globaux vers `packages/npm.txt` |
| `update-gems` | Dump les gems installées vers `packages/gems.txt` |
| `update-skills` | Récupère les derniers SKILL.md upstream (un commit par skill) |
| `update-claude-skills` | Met à jour les skills skillfish et re-bundle `packages/skillfish.json` |
| `check` | Dry-run : affiche les diffs de skills sans écrire |

### Vérifier la dérive

`scripts/check-drift.sh` compare les fichiers de `config/` et de `apps/claude/` avec ce qui est déployé dans `$HOME`, et vérifie que les index krew de `packages/krew-indexes.txt` sont enregistrés.

```bash
./scripts/check-drift.sh
```

### Auditer l'usage du Brewfile

`scripts/brew-usage-audit.sh` liste les packages Homebrew jamais utilisés, en lisant l'atime des binaires du Cellar.

| Flag | Effet |
| ------ | ------- |
| `--stale-days N` | Signaler les packages inutilisés depuis plus de N jours (défaut : 90) |
| `--leaves-only` | N'auditer que les leaves (ignore les dépendances) |
| `--all` | Lister tous les packages audités, pas seulement ceux signalés |
| `--history FILE` | Historique shell utilisé comme preuve d'appoint (défaut : `$HISTFILE`) |
| `--json FILE` | Écrire aussi le résultat complet en JSON |
| `-h`, `--help` | Aide |

```bash
./scripts/brew-usage-audit.sh
./scripts/brew-usage-audit.sh --stale-days 180 --leaves-only
./scripts/brew-usage-audit.sh --all --json /tmp/audit.json
```

Avant de supprimer un package suggéré :

```bash
brew uses --installed <package>   # vérifier s'il est requis par un autre
brew uninstall <package>
```

### Lancer un plan Terragrunt lisible

`tg-run` (déployé depuis `config/.local/bin/`) lance une commande Terragrunt sur chaque unité impactée, une invocation par unité. Le format `pretty` de Terragrunt réencapsule la sortie Terraform en `<time> <level> [<unit>] terraform: <ligne>`, soit ~77 colonnes perdues sur chaque ligne d'un plan : le script exporte `TG_TF_FORWARD_STDOUT` pour laisser passer la sortie Terraform brute, et regroupe chaque unité dans une section repliable sous GitLab CI (un simple titre en local).

| Invocation | Effet |
| ------ | ------- |
| `tg-run` | Plan de l'unité courante si le répertoire contient un `terragrunt.hcl` ; sinon de toutes les unités sous le répertoire courant ; sinon des unités impactées vs `origin/main`. La racine du repo est exclue du deuxième cas, un appel nu y planerait tout le monorepo |
| `tg-run plan live/a live/b` | Plan des unités données |
| `tg-run validate` | N'importe quelle commande Terragrunt |
| `BASE_REF=origin/master tg-run` | Change la branche de référence pour la détection |
| `-h`, `--help` | Aide |

Ce n'est pas un remplacement de `tg plan` : chaque unité passe par `run --all --queue-include-dir`, ce qui embarque aussi ses dépendances. `--non-interactive` n'est ajouté que si `$CI` est défini, pour qu'un `apply` local garde sa confirmation.

## Pre-commit

Hooks appliqués à chaque commit : `gitleaks`, `shellcheck`, `shfmt`, `markdownlint`, `yamllint`, `prettier`, `conventional-pre-commit`.

```bash
pre-commit run --all-files      # tous les hooks
pre-commit run shellcheck       # un seul hook
pre-commit autoupdate           # bumper les versions
```

## CI

`.github/workflows/weekly-software-check.yml` tourne chaque lundi, valide que les formulas et les casks de `packages/Brewfile` existent toujours, et ouvre une PR pour supprimer les entrées obsolètes.

## Composants Installés

### Shell & Terminal

- **zsh** avec oh-my-zsh
- Plugins : `zsh-autosuggestions`, `zsh-syntax-highlighting`
- **Wezterm** comme émulateur de terminal

### Outils CLI Modernes

Voir `packages/Brewfile` pour la liste complète. Généralement :

- `rg` (ripgrep), `fd`, `bat`, `eza`
- `fzf` pour fuzzy finding
- `jq`, `yq` pour manipulation JSON/YAML

### Kubernetes Tools

- `kubectl` + krew (installés via Homebrew)
- `kubectx`, `kubens`
- `kubeswitch` pour la gestion multi-cluster
- Plugins krew : entrées `krew "..."` dans `packages/Brewfile`
- Index krew custom : `packages/krew-indexes.txt`, enregistrés par le step `krew-indexes` de `init_mac.sh` avant l'installation des packages

### Claude Code / AI Tooling

- **Claude Code** : installé par l'installeur natif (step `claude-code`). Config globale (`apps/claude/CLAUDE.md`, `settings.json`), hooks et skills déployés par `setup_claude()`
- **Skills externes** : réinstallées par `install_claude_skills()` depuis `packages/skillfish.json` (skillfish), `uipro`, ou leur dépôt upstream
- **RTK** : proxy CLI token-efficient (`rtk init --global` configure le hook et génère `~/.claude/RTK.md`)

### Development Tools

- Git avec configuration avancée
- Node.js (via Homebrew)
- Ruby (système macOS)
- Packages NPM/Gem selon listes

## Troubleshooting

### Le script échoue sur Xcode

Si l'installation Xcode Command Line Tools nécessite une interaction :

1. Le script s'arrête proprement
2. Terminez l'installation dans la fenêtre popup
3. Relancez `./scripts/init_mac.sh`

### Homebrew pas dans le PATH

Pour Apple Silicon, ajoutez à votre shell :

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Pour Intel :

```bash
eval "$(/usr/local/bin/brew shellenv)"
```

### kubeswitch demande l'auth Google à chaque fois

Le token ADC est expiré (fréquent sur les comptes Google Workspace avec SSO) :

```bash
gcloud auth application-default login
```

Pour réduire la fréquence des appels API, ajouter `refreshIndexAfter` dans `~/.kube/switch-config.yaml` sur le store GKE :

```yaml
- kind: gke
  refreshIndexAfter: 8h
  config:
    authentication:
      authenticationType: gcloud
  cache:
    kind: filesystem
    config:
      path: ~/.kube/cache
```

### Un plugin krew préfixé échoue à l'installation

L'index custom n'est pas enregistré. `./scripts/check-drift.sh` le signale et affiche la commande de correction.

## Configuration Avancée

### SSH ControlMaster

Pour activer la réutilisation de connexions SSH (déjà configuré dans `.zshrc`) :

```bash
mkdir -p ~/.ssh/private
```

### Wezterm

```bash
vim ~/.wezterm.lua
```

### Markdownlint

```bash
vim ~/.markdownlint.json
```

## Contribution

Pour ajouter un outil :

1. L'installer manuellement pour tester
2. L'ajouter au fichier approprié (`packages/Brewfile`, `packages/npm.txt`, etc.)
3. Regénérer le fichier avec `make update`
4. Commit + push

## Licence

Configuration personnelle - Utilisez à vos risques et périls.
