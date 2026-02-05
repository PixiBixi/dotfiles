# dotfiles

Configuration complète pour macOS avec installation automatisée.

## Quick Start

```bash
git clone https://github.com/PixiBixi/dotfiles.git ~/dotfiles
cd ~/dotfiles
./init_mac.sh
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
- Tous les packages listés dans `Brewfile`, `npmfile`, `gemlist`
- kubectl krew + plugins

## Structure du Repository

```sh
dotfiles/
├── init_mac.sh              # Script d'installation principal
├── Brewfile                 # Packages Homebrew (formulae, casks, mas)
├── Plugins_Krew             # Plugins kubectl krew
├── npmfile                  # Packages NPM globaux
├── gemlist                  # Gems Ruby
├── .zshrc                   # Configuration zsh
├── .wezterm.lua             # Configuration Wezterm
├── .gitconfig_perso         # Git config pour projets perso
├── .gitconfig_work          # Git config pour projets work
├── .markdownlint.json       # Configuration markdownlint
└── .kube/
    └── switch-config.yaml   # Configuration kubeswitch
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

### 3. Shell

Recharger votre configuration:

```bash
source ~/.zshrc
```

## Maintenance

### Mettre à jour Brewfile

Exporter vos packages actuels:

```bash
brew bundle dump --force --file=./Brewfile
```

### Mettre à jour npmfile

Lister vos packages NPM globaux:

```bash
npm list --global --parseable --depth=0 | \
  sed '1d' | \
  awk '{gsub(/\/.*\//,"",$1); print}' > ./npmfile
```

### Mettre à jour gemlist

Lister vos gems installées:

```bash
gem list | tail -n+1 | \
  sed 's/(/--version /' | \
  sed 's/)//' > ./gemlist
```

### Mettre à jour Plugins_Krew

Lister vos plugins krew:

```bash
kubectl krew list > ./Plugins_Krew
```

## Composants Installés

### Shell & Terminal

- **zsh** avec oh-my-zsh
- Plugins: `zsh-autosuggestions`, `zsh-syntax-highlighting`
- **Wezterm** comme émulateur de terminal

### Outils CLI Modernes

Voir `Brewfile` pour la liste complète. Généralement:

- `rg` (ripgrep), `fd`, `bat`, `exa`
- `fzf` pour fuzzy finding
- `jq`, `yq` pour manipulation JSON/YAML

### Kubernetes Tools

- `kubectl` + krew
- `kubectx`, `kubens`
- `kubeswitch` pour gestion multi-cluster
- Plugins krew selon `Plugins_Krew`

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
3. Relancez `./init_mac.sh`

### Homebrew pas dans le PATH

Pour Apple Silicon, ajoutez à votre shell:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Pour Intel:

```bash
eval "$(/usr/local/bin/brew shellenv)"
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
2. L'ajouter au fichier approprié (`Brewfile`, `npmfile`, etc.)
3. Regénérer le fichier avec les commandes de maintenance
4. Commit + push

## Licence

Configuration personnelle - Utilisez à vos risques et périls.
