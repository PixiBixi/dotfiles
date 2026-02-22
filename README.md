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
- Tous les packages listés dans `packages/`
- kubectl krew + plugins

## Structure du Repository

```text
dotfiles/
├── config/                      # Dotfiles — miroir de $HOME
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
│   ├── Brewfile
│   ├── npm.txt
│   ├── gems.txt
│   └── krew.txt
├── apps/                        # Configs d'applications non-dotfiles
│   ├── claude/
│   │   └── CLAUDE.md
│   ├── raycast/
│   │   └── Raycast.rayconfig
│   └── vscode/
│       ├── settings.json
│       └── extensions.txt
├── scripts/
│   ├── init_mac.sh              # Script d'installation principal
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

Le workflow `.github/workflows/weekly-software-check.yml` tourne chaque lundi et valide que les formulas Homebrew, les casks et les plugins krew existent toujours. Il crée automatiquement une PR pour supprimer les entrées obsolètes.

Le workflow comporte trois jobs :

- `check-brew` — valide les formulas (`brew info`) et les casks (API `formulae.brew.sh`) dans `packages/Brewfile`
- `check-krew` — valide les plugins dans `packages/krew.txt`
- `create-pr` — agrège les résultats et ouvre la PR si des entrées ont été supprimées

Les jobs `check-brew` et `check-krew` tournent en parallèle. Homebrew est mis en cache entre les runs pour éviter une réinstallation complète à chaque exécution.

Les formulas de taps (`owner/tap/name`) et les plugins krew issus d'index custom (`index/plugin`) sont ignorés — trop spécifiques à macOS pour être validés sur Linux.

## Maintenance

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

### Mettre à jour krew.txt

Lister vos plugins krew:

```bash
kubectl krew list > ./packages/krew.txt
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

- `kubectl` + krew
- `kubectx`, `kubens`
- `kubeswitch` pour gestion multi-cluster
- Plugins krew selon `packages/krew.txt`

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

### Krew plugins échouent

Certains plugins peuvent ne plus être maintenus. Le script continue avec un warning.
Vérifiez manuellement:

```bash
kubectl krew search <plugin-name>
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
