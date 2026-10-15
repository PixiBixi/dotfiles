<!-- markdownlint-disable MD033 MD041 -->
<div align="center">

# dotfiles

**Mon poste macOS d'SRE, reproductible en une commande.**

zsh, WezTerm, Kubernetes, Terragrunt et Claude Code, provisionnés par un script idempotent.

[![macOS](https://img.shields.io/badge/macOS-Ventura%2B-000000?logo=apple&logoColor=white)](#prérequis)
[![Shell](https://img.shields.io/badge/shell-zsh-89e051?logo=gnubash&logoColor=white)](config/.zshrc)
[![Homebrew](https://img.shields.io/badge/Homebrew-Brewfile-FBB040?logo=homebrew&logoColor=black)](packages/Brewfile)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-FAB040?logo=pre-commit&logoColor=black)](.pre-commit-config.yaml)
[![Weekly check](https://github.com/PixiBixi/dotfiles/actions/workflows/weekly-software-check.yml/badge.svg)](.github/workflows/weekly-software-check.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

[Installation](#installation) · [Contenu](#ce-qui-est-installé) · [Commandes](#commandes-maison) · [Terminal](#terminal) · [Claude Code](#claude-code) · [Maintenance](#maintenance) · [Troubleshooting](#troubleshooting)

</div>

---

## Installation

```bash
git clone https://github.com/PixiBixi/dotfiles.git ~/dotfiles
cd ~/dotfiles
./scripts/init_mac.sh
```

> [!TIP]
> Le script est **idempotent** : il peut être relancé sans risque. `--only <step>` ne joue qu'une étape (`dotfiles`, `launchagents`, `claude-plugins`, ...).

### Prérequis

- macOS Ventura ou plus récent
- Une connexion internet
- Les droits administrateur (Xcode Command Line Tools)

Le script installe le reste : Xcode CLT, Homebrew, oh-my-zsh et ses plugins, puis tout ce que liste `packages/` (formulas, casks, plugins krew, npm, gems).

### Post-installation

<details>
<summary><b>1. Identités Git</b></summary>

```bash
vim ~/.gitconfig_perso   # personnel
vim ~/.gitconfig_work    # professionnel
```

Inclusion conditionnelle dans le `.gitconfig` principal :

```ini
[includeIf "gitdir:~/Documents/perso/"]
    path = ~/.gitconfig_perso

[includeIf "gitdir:~/Documents/work/"]
    path = ~/.gitconfig_work
```

`.gitconfig_work` fait passer les remotes gitlab.com en HTTPS (`insteadOf` sur `git@gitlab.com:`), authentifiés par le token de `glab` : un seul secret à renouveler (`glab auth login`), aucun reclone. À faire une fois :

```bash
glab config set git_protocol https --host gitlab.com
```

Symlinkés vers `~/.config/git/` :

- `allowed_signers` : référencé par `gpg.ssh.allowedSignersFile`, adresse courante en premier, domaines historiques ensuite, séparés par des virgules sur la même ligne
- `ignore` : gitignore global

</details>

<details>
<summary><b>2. Kubeconfig et GKE</b></summary>

```bash
kubectl konfig split -o ~/.kube/configs
gcloud auth application-default login   # ADC pour que kubeswitch découvre les clusters GKE
```

</details>

<details>
<summary><b>3. Shell et pre-commit</b></summary>

```bash
source ~/.zshrc
pre-commit install
```

</details>

---

## Ce qui est installé

| Domaine | Outils |
|---|---|
| **Shell** | zsh + oh-my-zsh, `zsh-autosuggestions`, `zsh-syntax-highlighting` |
| **Terminal** | [WezTerm](#wezterm) nightly, config [Ghostty](config/.config/ghostty/config) portée |
| **CLI** | `rg`, `fd`, `bat`, `lsd`, `fzf`, `jq`, `yq`, `neovim` |
| **Kubernetes** | `kubectl` + krew, `kubectx`/`kubens`, `kubeswitch`, plugins krew dans le `Brewfile` |
| **IaC** | Terraform, Terragrunt, [`tg-run`](#tg-run) |
| **AI** | [Claude Code](#claude-code), skills, hooks, statusline, RTK |
| **Dev** | Git, Node.js, Ruby système, paquets npm et gems |

La liste complète est dans [`packages/Brewfile`](packages/Brewfile).

<details>
<summary><b>Structure du repo</b></summary>

```text
dotfiles/
├── config/                       # Dotfiles, miroir de $HOME
│   ├── .zshrc, .zsh_alias, .zsh_functions, .zsh_mac, .zsh_linux
│   ├── .gitconfig, .gitconfig_perso, .gitconfig_work
│   ├── .tmux.conf, .vimrc, .wezterm.lua, .markdownlint.json
│   ├── .ssh/config
│   ├── .kube/switch-config.yaml
│   ├── .config/
│   │   ├── flameshot/            # flameshot.ini (copie)
│   │   ├── ghostty/
│   │   ├── git/                  # allowed_signers, ignore
│   │   └── nvim/
│   ├── .local/bin/               # Commandes déployées sur le $PATH
│   └── Library/LaunchAgents/     # Agents launchd, rendus depuis __HOME__
├── packages/
│   ├── Brewfile                  # Formulas, casks, krew plugins, npm, gems
│   ├── krew-indexes.txt          # Index krew custom, ajoutés avant le Brewfile
│   ├── npm.txt
│   ├── gems.txt
│   └── skillfish.json            # Manifeste des skills Claude externes
├── apps/
│   ├── claude/                   # CLAUDE.md, settings.json, bin/, hooks/, config/, skills/
│   ├── raycast/Raycast.rayconfig
│   └── vscode/                   # settings.json, extensions.txt
├── scripts/
│   ├── init_mac.sh               # Installation principale
│   ├── check-drift.sh            # Diff entre le repo et $HOME
│   └── brew-usage-audit.sh       # Packages Homebrew inutilisés
└── Makefile
```

</details>

---

## Commandes maison

Déployées sur le `$PATH` depuis [`config/.local/bin/`](config/.local/bin/).

| Commande | Rôle |
|---|---|
| [`tg-run`](#tg-run) | Runner Terragrunt à sortie lisible |
| [`helm-charts-update`](#helm-charts-update) | Passe les charts Helm locaux à la dernière version |
| [`close-done-tabs`](#close-done-tabs) | Ferme les onglets Chrome des MR, jobs CI et tickets Jira terminés |
| [`wezterm-pane-picker`](#wezterm) | Sélecteur fzf des panes WezTerm (`Cmd+P`) |
| [`wezterm-restore`](#wezterm) | Restaure onglets et sessions Claude |
| [`slack-restart.sh`](#agents-launchd) | Redémarrage planifié de Slack |

### `tg-run`

Lance une commande Terragrunt sur chaque unité impactée, une invocation par unité. Exporte `TG_TF_FORWARD_STDOUT` pour garder la sortie Terraform brute (le format `pretty` mange ~77 colonnes par ligne) et regroupe chaque unité dans une section repliable sous GitLab CI.

| Invocation | Effet |
|---|---|
| `tg-run` | Unité courante si `terragrunt.hcl` présent, sinon toutes les unités sous le répertoire, sinon les unités impactées vs `origin/main` (jamais tout le monorepo depuis la racine) |
| `tg-run plan live/a live/b` | Plan des unités données |
| `tg-run validate` | N'importe quelle commande Terragrunt |
| `BASE_REF=origin/master tg-run` | Autre branche de référence |

> [!NOTE]
> Pas un remplacement de `tg plan` : chaque unité passe par `run --all --queue-include-dir`, qui embarque aussi ses dépendances. `--non-interactive` n'est ajouté que si `$CI` est défini, un `apply` local garde sa confirmation.

### `helm-charts-update`

Remplace chaque chart de `~/Documents/work/src/helm` par la dernière version publiée (`helm pull --untar`), sans jamais downgrader. L'index `~/Documents/work/src/helm/.helm-sources` contient une ligne `<dossier> <repo> <chart>` ou `<dossier> <oci://ref>` par chart ; un dossier absent de l'index est signalé `UNTRACKED`.

| Invocation | Effet |
|---|---|
| `helm-charts-update` | Met à jour les charts en retard |
| `helm-charts-update --dry-run` | Affiche versions locale et distante |
| `helm-charts-update --add argo-cd https://argoproj.github.io/argo-helm` | Ajoute à l'index puis pull |
| `helm-charts-update --add redis oci://registry-1.docker.io/bitnamicharts/redis` | Idem en OCI |
| `JOBS=16` / `RETRIES=5` / `HELM_DIR=<dir>` | Parallélisme (défaut 10), tentatives (défaut 3), autre dossier |

### `close-done-tabs`

Lit les onglets Chrome (déchargés compris) et ferme ceux dont l'objet est terminé. États lus via `glab api` et `jira issue view --raw`, 5 appels en parallèle. Au premier lancement, macOS demande d'autoriser le terminal à piloter Chrome.

| Onglet reconnu | Fermé si | Exemple |
|---|---|---|
| MR GitLab (sous-pages comprises) | `merged` ou `closed` | `gitlab.com/<group>/<project>/-/merge_requests/42/diffs` |
| Job ou pipeline GitLab CI | `passed` | `gitlab.com/<group>/<project>/-/jobs/123` |
| Ticket Jira, ou board avec `selectedIssue` | catégorie `done` | `<site>.atlassian.net/browse/PE-123` |

```bash
close-done-tabs -n   # dry run : liste par état, ne ferme rien
close-done-tabs      # ferme
```

---

## Terminal

### WezTerm

Version nightly (`wezterm@nightly`) : le plein écran derrière l'encoche n'existe pas dans la stable de 2024.

| Raccourci | Effet |
|---|---|
| `Ctrl+Cmd+F` | Plein écran derrière l'encoche |
| `Cmd+N` | Nouvelle fenêtre dans le même état que la courante |
| `Cmd+P` | Sélecteur fzf de toutes les panes, avec aperçu |
| `Ctrl+F` *(sélecteur)* | Bascule recherche par titre / dans le contenu |
| `Ctrl+K` *(sélecteur)* | Efface après le curseur |

Un onglet inactif passe en jaune avec un `●` quand une de ses panes travaille (session Claude ou progression OSC 9;4).

La disposition (onglets, splits, dossiers, ID de session Claude) est sauvegardée dans `~/.local/state/wezterm/layout.json` à chaque changement, 10 versions dans `history/`. Au démarrage, WezTerm propose de restaurer.

| Commande | Effet |
|---|---|
| `wezterm-restore` | Restaure la session précédente dans la fenêtre courante |
| `wezterm-restore ~/.local/state/wezterm/history/layout-<date>.json` | Restaure une sauvegarde plus ancienne |
| `wezterm-restore --dry-run` | Affiche les commandes sans rien ouvrir |
| `wezterm-restore --no-claude` | Recrée les onglets sans relancer Claude |

### Flameshot

| Raccourci | Outil |
|---|---|
| `Cmd+Shift+4` | Flameshot, capture de zone |
| `Cmd+Shift+5` | Natif macOS, capture de fenêtre |

`flameshot.ini` est déployé en **copie** (QSettings remplace un symlink). L'étape `screenshot-hotkeys` libère `Cmd+Shift+4` côté macOS ; le raccourci est déclaré `Ctrl+Shift+'` car sous Qt macOS `Ctrl` vaut `Cmd` et sur AZERTY `4` produit `'`.

```bash
./scripts/init_mac.sh --only dotfiles screenshot-hotkeys   # Réglages Système fermés
```

---

## Claude Code

| Élément | Source | Déploiement |
|---|---|---|
| Binaire | installeur natif | step `claude-code` |
| `CLAUDE.md`, `settings.json`, `keybindings.json` | `apps/claude/` | symlinks dans `~/.claude/` (`setup_claude()`) |
| Hooks et leur config | `apps/claude/hooks/`, `apps/claude/config/` | symlinks dans `~/.claude/` |
| Skills locales et upstream | `apps/claude/skills/` | symlinks dans `~/.claude/skills/` |
| Skills externes | `packages/skillfish.json`, `tickler` | `install_claude_skills()` |
| Plugins | `enabledPlugins` de `settings.json` | step `claude-plugins` |
| RTK | `rtk init --global` | hook PreToolUse + `~/.claude/RTK.md` |

**Statusline** : `apps/claude/bin/claude-statusline` affiche session, branche, modèle et effort, contexte, quotas 5h/semaine et coût. Police Nerd Font requise.

| Variable | Effet |
|---|---|
| `CLAUDE_STATUSLINE_BG_RGB` | Fond du terminal (défaut `26;27;37`) |
| `CLAUDE_STATUSLINE_TICKET_URL` | Préfixe d'URL : une session nommée `PE-2166` devient un lien cliquable |

---

## Agents launchd

`config/Library/LaunchAgents/*.plist` est rendu vers `~/Library/LaunchAgents/` (substitution de `__HOME__`, launchd n'interprète aucune variable) puis chargé par l'étape `launchagents`.

| Agent | Déclenchement | Fait |
|---|---|---|
| `fr.jdelgado.slack-restart` | 04h30, 12h30, 19h30 | Quitte Slack via AppleScript et le relance masqué |

`slack-restart.sh` ne fait rien si Slack ne tourne pas, a démarré il y a moins de 6h (`MIN_UPTIME`), ou si le clavier a servi dans les 10 dernières minutes (`IDLE_THRESHOLD`). Trois créneaux car un créneau manqué pendant le sommeil part au réveil, où le garde-fou d'inactivité l'annule. Quit laissé 30 s avant `pkill`. Logs : `~/Library/Logs/slack-restart.{log,err}`.

> [!IMPORTANT]
> Le script est déployé en **copie** : un agent launchd n'a pas de droits TCC sur `~/Documents`, un symlink vers le repo échoue en exit 126. Après modification : `./scripts/init_mac.sh --only dotfiles`.

```bash
IDLE_THRESHOLD=0 MIN_UPTIME=0 ~/.local/bin/slack-restart.sh      # tester sans attendre
./scripts/init_mac.sh --only launchagents                         # (re)déployer et charger
launchctl list | grep fr.jdelgado                                 # état
launchctl kickstart -k gui/$(id -u)/fr.jdelgado.slack-restart     # forcer un run
launchctl bootout gui/$(id -u)/fr.jdelgado.slack-restart          # décharger
```

Le premier run demande l'autorisation d'automatiser Slack (Réglages, Confidentialité, Automatisation).

---

## Maintenance

### Cibles `make`

| Target | Effet |
|---|---|
| `make update` | Tout : brew, krew indexes, npm, gems, skills, skills Claude, plugins Claude |
| `make update-brew` | Dump Homebrew vers `packages/Brewfile` |
| `make update-krew-indexes` | Dump des index krew custom vers `packages/krew-indexes.txt` |
| `make update-npm` / `update-gems` | Dump npm globaux / gems |
| `make update-skills` | Derniers SKILL.md upstream, un commit par skill |
| `make update-claude-skills` | Met à jour skillfish et re-bundle `packages/skillfish.json` |
| `make update-claude-plugins` | Rafraîchit marketplaces et plugins (redémarrage requis) |
| `make check` | Dry-run des diffs de skills |
| `make drift` | Dérive entre le repo et `$HOME` (`scripts/check-drift.sh`) |

`make drift` compare `config/` et `apps/claude/` avec `$HOME`, et vérifie les index krew et les plugins Claude déclarés.

### Auditer le Brewfile

`scripts/brew-usage-audit.sh` repère les packages jamais utilisés via l'atime des binaires du Cellar.

| Flag | Effet |
|---|---|
| `--stale-days N` | Inutilisés depuis plus de N jours (défaut 90) |
| `--leaves-only` | Ignore les dépendances |
| `--all` | Liste tout, pas seulement les signalés |
| `--history FILE` | Historique shell comme preuve d'appoint (défaut `$HISTFILE`) |
| `--json FILE` | Résultat complet en JSON |

```bash
./scripts/brew-usage-audit.sh --stale-days 180 --leaves-only
brew uses --installed <package>   # requis par un autre ? à vérifier avant uninstall
```

### Qualité

Hooks pre-commit : `gitleaks`, `shellcheck`, `shfmt`, `markdownlint`, `yamllint`, `prettier`, `conventional-pre-commit`.

```bash
pre-commit run --all-files
pre-commit autoupdate
```

Chaque lundi, [`weekly-software-check`](.github/workflows/weekly-software-check.yml) vérifie que les formulas et casks du `Brewfile` existent toujours et ouvre une PR pour retirer les entrées mortes.

### Ajouter un outil

1. L'installer à la main pour tester
2. `make update` pour regénérer les listes
3. Commit + push

---

## Troubleshooting

<details>
<summary><b>Le script s'arrête sur Xcode</b></summary>

Terminer l'installation dans la popup, puis relancer `./scripts/init_mac.sh`.

</details>

<details>
<summary><b>Homebrew absent du PATH</b></summary>

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"   # Apple Silicon
eval "$(/usr/local/bin/brew shellenv)"      # Intel
```

</details>

<details>
<summary><b>kubeswitch redemande l'auth Google</b></summary>

Token ADC expiré (fréquent avec le SSO Google Workspace) :

```bash
gcloud auth application-default login
```

Pour espacer les appels API, ajouter `refreshIndexAfter` au store GKE de `~/.kube/switch-config.yaml` :

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

</details>

<details>
<summary><b>Un plugin krew préfixé échoue à l'installation</b></summary>

Son index custom n'est pas enregistré : `make drift` le signale et affiche la commande de correction.

</details>

<details>
<summary><b>SSH ControlMaster</b></summary>

La réutilisation de connexions est configurée, le dossier de sockets doit exister :

```bash
mkdir -p ~/.ssh/private
```

</details>

---

<div align="center">

Configuration personnelle, partagée sous licence [Apache 2.0](LICENSE). Utilisez à vos risques et périls.

</div>
