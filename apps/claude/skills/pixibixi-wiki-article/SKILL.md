---
name: pixibixi-wiki-article
description: Use when writing, adding, updating, cross-linking, or adding a diagram to an article on the PixiBixi wiki (repo pixibixi.github.io, served at wiki.jdelgado.fr, MkDocs Material, docs/ tree). Triggers - "écris/ajoute un article wiki", "documente X sur le wiki", "ajoute une page", "rajoute un schéma à la page", "link entre deux articles du wiki".
---

# Écrire un article sur le wiki PixiBixi

## Overview

Le wiki est un site **MkDocs Material** (`~/Documents/perso/git/pixibixi.github.io`), déployé sur `wiki.jdelgado.fr` via GitHub Actions (`gh-deploy`) à chaque push sur `master`. Un article = un `.md` sous `docs/<section>/`. La prose est en **français**, le code/commits/technique en **anglais**.

Ce skill capture la procédure complète *et les deux pièges qui cassent la CI ou laissent l'article invisible*.

## Quick reference

| Élément | Valeur |
|---|---|
| Repo | `~/Documents/perso/git/pixibixi.github.io` (branche `master`) |
| Articles | `docs/<section>/<nom>.md` (ex. `docs/ci-cd/github/go-ci.md`) |
| Build local | `./.venv/bin/mkdocs build` |
| Lint markdown (repro CI) | `npx -y markdownlint-cli2@0.23.0 --config .markdownlint.json <fichiers.md>` |
| Rendu SVG en PNG (contrôle visuel) | `rsvg-convert -b '#0d1117' fichier.svg -o out.png` |
| Nav | **auto-générée depuis l'arborescence** (pas de bloc `nav:` dans `mkdocs.yml`) |

## Workflow

1. **Explorer** la section cible et **lire un article voisin** pour caler le style (frontmatter, ton, structure).
2. **Rédiger** l'article. Ancrer sur du réel (code, mesures, repos existants), pas du tuto générique.
3. **Passer la voix au filtre** — invoquer le skill `humanizer` pour que ça sonne comme l'auteur, pas comme un bot.
4. **Cross-linker** les articles liés (dans les deux sens) via une admonition `!!! tip` ou un lien inline.
5. **Schéma** si un *flux* le mérite (voir "Schémas SVG"). Sinon un tableau suffit.
6. **⚠️ Wirer les DEUX index** (voir Gotcha 1) — l'étape le plus souvent oubliée.
7. **Build + vérifier** : `./.venv/bin/mkdocs build`, puis relint markdown (Gotcha 2). Contrôler que le SVG est copié et la balise `<img>` résolue.
8. **Committer par scope** (Conventional Commits, un commit par portée), rebase sur `origin/master`, push.
9. **Watcher la CI** : `gh run watch <id> --repo PixiBixi/pixibixi.github.io --exit-status`. Ne pas considérer le travail fini avant que `lint` **et** `deploy` soient verts.

## Conventions MkDocs Material

- **Frontmatter** obligatoire : `description:` (une phrase riche en mots-clés) + `tags:` (liste).
- **Admonitions** : `!!! note`, `!!! warning`, `!!! tip "Titre"` (contenu indenté de 4 espaces).
- **Blocs de code titrés** : ` ```yaml title=".github/workflows/ci.yml" `.
- **Liens internes** : chemins relatifs vers le `.md` (`goreleaser.md`, `github/go-ci.md`) — MkDocs les résout.
- **Images/SVG** : `![Alt](nom.svg)` avec le fichier dans le même dossier que l'article.

## Schémas SVG (style maison)

SVG écrits à la main, palette GitHub dark, `viewBox` ~640 de large, police Segoe UI. Boîtes = `rect` bordure `#30363d` + barre d'accent 4px colorée à gauche ; pills = `rect rx=12` bordure colorée.

| Rôle | Couleur |
|---|---|
| Texte principal | `#e6edf3` |
| Texte secondaire / flèches / bordure | `#8b949e` / `#30363d` |
| Succès / gate | `#3fb950` (vert) |
| Release / accent chaud | `#f78166` (orange) |
| Sécurité / info | `#58a6ff` (bleu) |
| Fond (pour le rendu PNG) | `#0d1117` |

Marqueur flèche réutilisable :

```xml
<marker id="arr" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
  <polygon points="0 0, 8 3, 0 6" fill="#8b949e"/>
</marker>
```

Toujours contrôler le rendu (`rsvg-convert` → PNG → Read) avant de committer : chevauchements de pills et largeurs de colonnes ne se voient pas dans le XML.

## Gotcha 1 — la nav auto NE référence PAS l'article dans les index

La nav latérale est auto-générée depuis l'arborescence, **mais il y a deux index maintenus à la main** qu'il faut éditer, sinon l'article est "orphelin" :

- `docs/index.md` — page d'accueil, section `## CI/CD` (ou la section concernée).
- `docs/<section>/index.md` — index de la section (ex. `docs/ci-cd/index.md`).

Après avoir créé l'article, **grep les deux** pour un article voisin et ajouter la ligne au même endroit :

```bash
rg -n 'goreleaser|cocogitto' docs/index.md docs/ci-cd/index.md
```

## Gotcha 2 — markdownlint ne lint QUE les fichiers changés

La CI `lint` passe les fichiers **modifiés dans le push** à `markdownlint-cli2`. Conséquence :

- Toucher un vieil article peut réveiller une règle récente sur ses tableaux et casser la CI sans rapport avec ton changement.
- **Politique du wiki** : tableaux compacts (`|---|`, sans alignement). `MD013` (longueur) et `MD060` (`table-column-style`) sont **désactivés** dans `.markdownlint.json` — ne pas les réactiver.

Toujours relinter en local **avant de pousser**, avec la version exacte de la CI :

```bash
npx -y markdownlint-cli2@0.23.0 --config .markdownlint.json docs/**/tes-fichiers.md
```

## Gotcha 3 — `mkdocs build --strict` échoue en local (faux positif)

Le plugin `social` génère les cartes sociales via `cairosvg`, qui a besoin de `libcairo` (absente en local). En local, `--strict` **abort** sur des warnings `cairo` **sans rapport** avec le contenu. La CI (`deploy`) fait tourner `--strict` avec les bonnes deps → c'est elle qui fait foi.

En local : build **sans** `--strict`, et filtrer le bruit pour ne garder que les vrais warnings :

```bash
./.venv/bin/mkdocs build 2>&1 | grep -viE 'cairo|dlopen|no such file|no library|find_library|ctypes|ProperDocs'
```

## Common mistakes

- Créer l'article et oublier de wirer `docs/index.md` **et** `docs/<section>/index.md` (Gotcha 1).
- Aligner/reformater des tableaux pour plaire à `MD060` — la règle est désactivée exprès (Gotcha 2).
- Croire que l'échec `--strict` local vient de l'article (Gotcha 3).
- Committer un gros commit fourre-tout au lieu d'un commit par scope.
- Déclarer terminé sans avoir vu la CI verte (`lint` + `deploy`).
