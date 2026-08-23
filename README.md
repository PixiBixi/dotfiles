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

Le script installe automatiquement:

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
│   ├── .ssh/
│   │   └── config
│   ├── .kube/
│   │   └── switch-config.yaml
│   └── .config/
│       └── nvim/
├── packages/                    # Listes de paquets à installer
│   ├── Brewfile                 # Formulas, casks, krew plugins, npm, gems
│   ├── npm.txt
│   ├── gems.txt
│   └── skillfish.json           # Manifeste des skills Claude externes
├── apps/                        # Configs d'applications non-dotfiles
│   ├── claude/
│   │   ├── CLAUDE.md
│   │   ├── settings.json
│   │   ├── hooks/               # session-allow.sh
│   │   └── skills/              # SKILL.md upstream + skills locales
│   ├── raycast/
│   │   └── Raycast.rayconfig
│   └── vscode/
│       ├── settings.json
│       └── extensions.txt
├── scripts/
│   ├── init_mac.sh              # Script d'installation principal
│   ├── brew-usage-audit.sh      # Audit packages Homebrew via l'atime des binaires
│   └── init.sh
├── .markdownlint.json
├── .pre-commit-config.yaml
└── .yamllint.yaml
```

## Fonctionnalités du Script

### Gestion d'erreur robuste

- Arrêt immédiat en cas d'échec (`set -euo pipefail`)
- Messages d'erreur clairs avec couleurs
- Trap pour cleanup automatique

### Idempotence

Chaque composant vérifie s'il est déjà installé:

- ✓ Skip si déjà présent
- ⚠ Warning si fichier manquant (non bloquant)
- ✗ Erreur seulement pour composants critiques

### Détection automatique

- Support Intel (`/usr/local`) et Apple Silicon (`/opt/homebrew`)
- Vérification macOS avant exécution
- Détection des outils déjà installés

## Post-Installation

### 1. Configuration Git

Éditer vos identités Git:

```bash
# Personnel
vim ~/.gitconfig_perso

# Professionnel
vim ~/.gitconfig_work
```

Dans votre `.gitconfig` principal, incluez conditionnellement:

```ini
[includeIf "gitdir:~/Documents/perso/"]
    path = ~/.gitconfig_perso

[includeIf "gitdir:~/Documents/work/"]
    path = ~/.gitconfig_work
```

### 2. Kubeconfig

Split votre kubeconfig en plusieurs fichiers:

```bash
kubectl konfig split -o ~/.kube/configs
```

### 3. Google Cloud (GKE)

Configurer les Application Default Credentials pour que kubeswitch puisse découvrir les clusters GKE sans prompt d'authentification répété :

```bash
gcloud auth application-default login
```

À relancer si kubeswitch vous redemande l'auth Google (token expiré, renouvellement de session SSO, etc.).

### 4. Shell

Recharger votre configuration:

```bash
source ~/.zshrc
```

## CI

Le workflow `.github/workflows/weekly-software-check.yml` tourne chaque lundi et valide que les formulas Homebrew et les casks existent toujours. Il crée automatiquement une PR pour supprimer les entrées obsolètes.

Le workflow comporte deux jobs :

- `check-brew` : valide les formulas (`brew info`) et les casks (API `formulae.brew.sh`) dans `packages/Brewfile`
- `create-pr` : applique les suppressions et ouvre la PR si nécessaire

Homebrew est mis en cache entre les runs pour éviter une réinstallation complète à chaque exécution.

Les formulas de taps (`owner/tap/name`) sont ignorées, trop spécifiques à macOS pour être validées sur Linux.

## Maintenance

### Auditer l'usage du Brewfile

`scripts/brew-usage-audit.sh` identifie les packages jamais utilisés en lisant l'**atime des
binaires** dans le Cellar. APFS met l'atime à jour à chaque exécution, donc le signal capte
tous les chemins d'invocation : alias, fonctions shell, hooks pre-commit, serveurs LSP,
scripts, et commandes lancées par un agent de code.

L'historique shell ne capte aucun de ces cas et sert seulement de preuve d'appoint. Un audit
basé sur l'historique déclare `bat` inutilisé alors qu'il tourne à chaque `cat`.

```bash
# Signaler tout ce qui n'a pas servi depuis 90 jours (défaut)
./scripts/brew-usage-audit.sh

# Seuil à 180 jours, leaves uniquement (pas les dépendances)
./scripts/brew-usage-audit.sh --stale-days 180 --leaves-only

# Tout lister, y compris les packages actifs, + export JSON
./scripts/brew-usage-audit.sh --all --json /tmp/audit.json

# Aide complète
./scripts/brew-usage-audit.sh --help
```

La colonne `EVIDENCE` nomme le chemin d'invocation que l'atime ne montre pas : l'alias de
`config/.zsh_alias`, la sous-commande `kubectl <plugin>`, ou le fichier de config qui
consomme l'outil (`.pre-commit-config.yaml`, `lsp.lua`, `init_mac.sh`). Un package avec une
evidence est utilisé même à 0 hit d'historique : ne pas le supprimer sur le seul compte de jours.

La mention `never run since install` avec une date d'install récente n'est **pas** un verdict :
`brew upgrade` réécrit le keg et remet l'atime à la date d'install. Laisser passer quelques
semaines avant de s'y fier.

Deux limites connues : les packages sans binaire dans `$(brew --prefix)/bin` ne sont pas
audités (`switch` livre un `switch.sh` à sourcer), et le script cible macOS (il épingle
`/usr/bin/stat` et `/bin/date` car les coreutils GNU masquent les deux avec des flags
incompatibles).

Avant de supprimer un package suggéré :

```bash
brew uses --installed <package>   # vérifier s'il est requis par un autre
brew uninstall <package>
```

### Mettre à jour Brewfile

Exporter vos packages actuels:

```bash
brew bundle dump --force --file=./packages/Brewfile
```

### Mettre à jour npm.txt

Lister vos packages NPM globaux:

```bash
npm list --global --parseable --depth=0 | \
  sed '1d' | \
  awk '{gsub(/\/.*\//,"",$1); print}' > ./packages/npm.txt
```

### Mettre à jour gems.txt

Lister vos gems installées:

```bash
gem list | tail -n+1 | \
  sed 's/(/--version /' | \
  sed 's/)//' > ./packages/gems.txt
```

## Composants Installés

### Shell & Terminal

- **zsh** avec oh-my-zsh
- Plugins: `zsh-autosuggestions`, `zsh-syntax-highlighting`
- **Wezterm** comme émulateur de terminal

### Outils CLI Modernes

Voir `packages/Brewfile` pour la liste complète. Généralement:

- `rg` (ripgrep), `fd`, `bat`, `exa`
- `fzf` pour fuzzy finding
- `jq`, `yq` pour manipulation JSON/YAML

### Kubernetes Tools

- `kubectl` + krew (installés via Homebrew)
- `kubectx`, `kubens`
- `kubeswitch` pour gestion multi-cluster
- Plugins krew gérés directement dans `packages/Brewfile` (entrées `krew "..."`))

### Claude Code / AI Tooling

- **Claude Code** : configuration globale (`apps/claude/CLAUDE.md`, `settings.json`), hooks et skills (`apps/claude/skills/`, symlinkées vers `~/.claude/skills/` par `setup_claude()`)
- **Skills externes** : celles gérées par leur propre installeur ne sont pas versionnées. `install_claude_skills()` les réinstalle depuis `packages/skillfish.json` (skillfish), `uipro`, ou leur dépôt upstream. Rafraîchir le manifeste avec `make update-claude-skills`
- **RTK** : proxy CLI token-efficient pour Claude Code (`rtk init --global` configure le hook automatique et génère `~/.claude/RTK.md`)

### Development Tools

- Git avec configuration avancée
- Node.js (via Homebrew)
- Ruby (système macOS)
- Packages NPM/Gem selon listes

## Troubleshooting

### Le script échoue sur Xcode

Si l'installation Xcode Command Line Tools nécessite une interaction:

1. Le script s'arrête proprement
2. Terminez l'installation dans la fenêtre popup
3. Relancez `./scripts/init_mac.sh`

### Homebrew pas dans le PATH

Pour Apple Silicon, ajoutez à votre shell:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Pour Intel:

```bash
eval "$(/usr/local/bin/brew shellenv)"
```

### kubeswitch demande l'auth Google à chaque fois

Le store GKE appelle les APIs Google Cloud à chaque lancement pour découvrir les clusters. Si le token ADC est expiré (fréquent sur les comptes Google Workspace avec SSO), kubeswitch déclenche `gcloud auth application-default login`.

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

## Configuration Avancée

### SSH ControlMaster

Pour activer la réutilisation de connexions SSH (déjà configuré dans `.zshrc`):

```bash
mkdir -p ~/.ssh/private
```

### Wezterm

La configuration Wezterm est copiée automatiquement. Pour la personnaliser:

```bash
vim ~/.wezterm.lua
```

### Markdownlint

Configuration pour linting Markdown (VSCode, nvim):

```bash
vim ~/.markdownlint.json
```

## Contribution

Pour ajouter un outil:

1. L'installer manuellement pour tester
2. L'ajouter au fichier approprié (`packages/Brewfile`, `packages/npm.txt`, etc.)
3. Regénérer le fichier avec les commandes de maintenance
4. Commit + push

## Licence

Configuration personnelle - Utilisez à vos risques et périls.
