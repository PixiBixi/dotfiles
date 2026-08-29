---
name: pixibixi-wiki-article
description: Use when writing, adding, updating, cross-linking, or adding a diagram to an article on the PixiBixi wiki (repo pixibixi.github.io, served at wiki.jdelgado.fr, MkDocs Material, docs/ tree). Triggers - "écris/ajoute un article wiki", "documente X sur le wiki", "ajoute une page", "rajoute un schéma à la page", "link entre deux articles du wiki".
---

# Écrire un article sur le wiki PixiBixi

## Overview

Le wiki est un site **MkDocs Material** (`~/Documents/perso/git/pixibixi.github.io`), déployé sur `wiki.jdelgado.fr` via GitHub Actions (`gh-deploy`) à chaque push sur `master`. Un article = un `.md` sous `docs/<section>/`. La prose est en **français**, le code/commits/technique en **anglais**.

Ce skill capture la procédure complète *et les pièges qui cassent la CI ou laissent l'article invisible*.

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
3. **Passer la voix au filtre** - invoquer le skill `humanizer` pour que ça sonne comme l'auteur, pas comme un bot.
4. **Cross-linker** les articles liés (dans les deux sens) via une admonition `!!! tip` ou un lien inline.
5. **Schéma** si un *flux* le mérite (voir "Schémas SVG"). Sinon un tableau suffit.
6. **⚠️ Wirer les DEUX index** (voir Gotcha 1) - l'étape le plus souvent oubliée.
7. **Build + vérifier** : `mkdocs build --strict` préfixé du `DYLD_FALLBACK_LIBRARY_PATH` (Gotcha 4), puis relint markdown (Gotchas 2 et 3). Contrôler que le SVG est copié et la balise `<img>` résolue.
8. **Committer par scope** (Conventional Commits, un commit par portée), rebase sur `origin/master`, push.
9. **Watcher la CI** : `gh run watch <id> --repo PixiBixi/pixibixi.github.io --exit-status`. Ne pas considérer le travail fini avant que `lint` **et** `deploy` soient verts.

## Conventions MkDocs Material

- **Frontmatter** obligatoire : `description:` (une phrase riche en mots-clés) + `tags:` (liste).
- **Admonitions** : `!!! note`, `!!! warning`, `!!! tip "Titre"` (contenu indenté de 4 espaces).
- **Blocs de code titrés** : ` ```yaml title=".github/workflows/ci.yml" `.
- **Liens internes** : chemins relatifs vers le `.md` (`goreleaser.md`, `github/go-ci.md`) - MkDocs les résout.
- **Images/SVG** : `![Alt](nom.svg)` avec le fichier dans le même dossier que l'article.

## Typographie et chiffres

Le `CLAUDE.md` du projet porte le style de fond (ton, structure, tournures). Ce qui suit
complète sur des points qu'aucun lint n'attrape.

- **Jamais d'em dash (`—`)**, nulle part : ni dans la prose, ni dans les titres, ni dans
  les descriptions de front matter, ni dans les commentaires d'un bloc de code. C'est la
  signature la plus visible d'un texte généré. À la place, un `-`, une virgule, un
  deux-points, ou on coupe la phrase en deux. Les incises appariées (`mot — aparté — suite`)
  passent en virgules ou en parenthèses, jamais en deux tirets : ça se lit mal et un `-`
  en début de ligne est parsé comme un item de liste par markdownlint.
- **Chiffres toujours en chiffres, jamais en lettres** : « 3 shards », « 12 fichiers »,
  « 100 caches », y compris en début de phrase. Seule exception, les approximations restent
  en lettres (« une vingtaine de clusters », « la centaine de pods ») - les écrire en
  chiffres inventerait une précision qui n'existe pas.
- **Un chiffre précis se justifie sur place, sinon il n'y est pas.** Écrire « garde 14 mois
  de métriques » en intro alors que le 14 vient d'un palier expliqué 100 lignes plus loin
  laisse le lecteur devant un nombre arbitraire. Soit on explique là, soit on reste
  générique (« aussi longtemps qu'on le lui demande ») et le chiffre arrive avec sa raison.
- **Unités de temps collées au chiffre** : `24h/24`, `12h`, `3h`, `6d`. Pas d'espace avant
  le symbole, c'est la convention de tout le wiki. La forme en mot (`12 heures`) reste
  valable en prose, mais on ne mélange pas `12 h` et `12h` dans le même article.
- **Guillemets français** `« … »` avec une espace intérieure, pas de `"…"` droits dans la
  prose. C'est la convention des articles récents.
- **Pas de virgule devant « et »**, ni devant « ou » et « ni ». C'est une faute, le
  réflexe vient de l'anglais où le comma before *and* est courant. On écrit « le cache et
  l'enveloppe mémoire », pas « le cache, et l'enveloppe mémoire ». Ça vaut aussi dans une
  énumération, où le français met la virgule entre les termes mais pas devant le dernier :
  « Ansible, Terraform et Makefile ». Attention au retour à la ligne, la faute se cache
  aussi à cheval sur 2 lignes, virgule en fin de ligne et `et` au début de la suivante,
  où un grep sur `, et` ne la voit pas.

    La seule exception est la virgule qui **ferme une incise** et se trouve juste avant le
    « et » : dans « le `main:` du build, qui vaut `""` tant qu'on ne l'a pas écrit, et ko
    passe cette chaîne vide », la virgule appartient à la relative, pas au « et ». La
    retirer casse la phrase. Avant un remplacement global, chercher le motif
    `, <qui|que|dont|où> …, et` et épargner ces cas.
- **Genre des acronymes et des composants** : il suit le nom-tête de l'expression
  développée, pas l'anglais. Une TSDB (*Database*), une API (*interface*), une VM
  (*machine*), une stack (*pile*), une store gateway (*passerelle*), une query (*requête*).
  Mais **un querier**, qui est le composant et pas la requête, un query frontend dont la
  tête est *frontend*, un compactor. Accorder aussi les pronoms et adjectifs.

    L'accord voyage plus loin que le déterminant collé au mot, et c'est là que la faute
    survit à la relecture. `attend tous les stacks`, `partagés par tous les stacks` et
    `les stacks annotés` sont faux au même titre que `un stack`, mais un grep sur
    `un stack` n'en voit aucun. Chercher aussi les quantifieurs (`tous`, `certains`,
    `plusieurs`), les participes détachés du nom et les textes alternatifs des schémas,
    que personne ne relit.
- **Le vocabulaire du domaine, pas son équivalent français.** La règle n'est pas une liste
  de mots, c'est un critère : si le terme est celui qu'on lit dans les flags, les métriques,
  la doc amont ou les dashboards, il reste tel quel. Traduire oblige le lecteur à refaire la
  correspondance dans sa tête au moment où il cherche justement à retrouver un flag.
  `timerange` et pas « plage de temps » ni « tranche de temps », `replicas` et pas
  « réplicas », `at scale` et pas « à l'échelle », `évicté` et pas « évincé » quand on parle
  de spot. Les noms K8s et infra restent en anglais, sans accent.

    Ça vaut **surtout dans les titres et les textes alternatifs**, qui sont écrits en
    dernier et relus le moins : c'est là que la traduction survit, alors que le corps du
    texte emploie déjà le bon terme deux paragraphes plus haut. Avant de committer, grep
    les traductions des termes que l'article utilise vraiment, pas seulement celles listées
    ici, et vérifier le sommaire de droite qui n'affiche que les titres.

    L'inverse est vrai aussi, le critère n'est pas « angliciser par défaut ». Quand la
    phrase parle de l'acte et pas du composant, le mot français gagne : on écrit « la
    requête met 26 secondes » et pas « la query », alors que `query frontend` reste le nom
    du composant et ne se traduit jamais. Même partage entre `un cache` et le fait de
    cacher, `un shard` et le fait de découper.
- **Attention aux remplacements globaux** : `réplica` → `replica` mange aussi
  `réplication`, qui est un mot français et garde son accent. Ancrer les motifs sur une
  frontière de mot et relire le diff.

## Titres

### Le H1

Forme : `<Sujet> : <les axes couverts>`. On nomme les **axes**, pas les composants.

- ✅ `Thanos at scale : archi, perf et FinOps`
- ✅ `HAProxy performance tuning : nbthread, maxconn, TLS, Kubernetes`

Ce qui échoue :

- **lister des composants** quand l'article couvre toute la chaîne :
  `Thanos at scale : Receive, spot, compactor en CronJob` ne dit pas qu'on parle aussi
  d'archi et de coût
- **se décrire soi-même** - `nos arbitrages`, `nos apprentissages`, `retour d'expérience`
  sonnent robot
- **une redondance** - `at scale` porte déjà l'échelle, donc pas de
  `… sur une vingtaine de clusters` derrière
- **un seul angle** quand l'article en couvre trois - `ce que ça coûte vraiment` sous-vend
  un article qui parle aussi d'archi et de perf

### Les H2

2 formes, pas d'autre :

1. **infinitif + objet** - `Compacter sans payer le disque 24 h/24`,
   `Mettre des limites en lecture et en ingestion`, `Contenir la RAM de Receive`
2. **groupe nominal court**, éventuellement `Sujet : qualifier` - `Un shard par tranche de
   temps`, `Un seul cache chaud pour toute la flotte`, `Nos tests et nos échecs`,
   `Réplication : le choix assumé`, `Receive : le composant le plus cher`

Un titre à l'infinitif promet une action, donc il n'est valable que si la section fournit
vraiment cette action. Quand elle ne fait que constater, c'est le groupe nominal qui va.

Un titre dit **ce que la section fait gagner**, pas le mécanisme qu'elle décrit :

| ✗ | ✅ | Pourquoi |
|---|---|---|
| `Le compactor en CronJob` | `Compacter sans payer le disque 24 h/24` | nomme le mécanisme, pas le gain |
| `Sharder la store gateway par plage de temps` | `Un shard par tranche de temps` | descriptif et trop long |
| `L'arithmétique Hyperdisk, ou comment on paye un choix d'instances` | `Payer de la capacité disque pour acheter du débit` | tournure `X, ou comment Y` et vocabulaire vendeur dans le titre |
| `Un cache chaud partagé plutôt que 100 caches froids` | `Un seul cache chaud pour toute la flotte` | bonne idée, trop bavarde |
| `Poser des limites avant que ça coûte` | `Mettre des limites en lecture et en ingestion` | `ça coûte` est vague |
| `Ce qu'on a essayé et retiré` | `Nos tests et nos échecs` | plat |
| `La query globale` | `L'architecture high-level` | titrait un composant alors que la section décrit l'archi |
| `Receive, dont la RAM suit la volumétrie` | `Receive : le composant le plus cher` | une relative avec virgule n'est pas un titre |
| `Contenir la RAM de Receive` | `Receive : le composant le plus cher` | promet une action qu'on ne peut pas faire : la RAM suit la volumétrie, on agit sur ce qui la fait grossir, on ne la plafonne pas |

Le nom d'un produit vendeur (`Hyperdisk`, `Ketama`) reste dans le corps, pas dans le titre :
il ferme le titre à ceux qui sont sur un autre cloud.

## Construire une phrase

L'erreur la plus fréquente, c'est de découper pour faire du rythme. Une phrase longue
construite en enchaînant des relatives passe très bien ; une suite de fragments courts
sonne faux.

**Ne pas** viser un plafond de mots par phrase. Cette voix accepte 40 mots quand ils
coulent :

> Une store gateway qui sert tout le bucket doit être dimensionnée pour la requête la plus
> violente qu'on lui posera jamais, par exemple un dashboard avec un timerange de 6 mois
> qui va charger énormément de donnée en RAM sur tous les replicas.

Ce qui sonne faux, à la place :

- **découper l'exemple en nouvelle phrase** avec une amorce du type « Concrètement : »,
  « Résultat : », « Le point à retenir ». Enchaîner avec `, par exemple …` dans la même
  phrase.
- **les fragments d'insistance** posés après un point (« Même ceux qui… », « Et pas
  qu'un peu. »)
- **un deux-points suivi d'une énumération de trois** - figure qui annonce au lieu de dire
- **le verbe imagé** là où le mécanisme suffit : « force à gonfler la RAM » → « va charger
  énormément de donnée en RAM »
- **le familier décoratif** (« on s'en fiche », « part en vrille », « à genoux »). Le blunt
  du `CLAUDE.md` est une réaction sincère, pas un ornement qu'on saupoudre.

## Schémas SVG (style maison)

Il n'existe pas de skill dédié au SVG, le style maison est ci-dessous. En revanche, dès que
le schéma **encode des quantités** (barres, frise proportionnelle, courbe), c'est un
graphique et pas un diagramme : invoquer le skill `dataviz` **avant** d'écrire le premier
`<rect>` et faire tourner son validateur de palette.

```bash
node scripts/validate_palette.js "#hex,#hex,#hex" --mode dark   # puis --mode light
```

Ce qu'il attrape et qu'on ne voit pas à l'œil : aplats trop saturés en gros blocs, absence
de gap de 2px entre fills adjacents, libellés portant la couleur de la série au lieu d'une
encre neutre et séparation insuffisante pour les daltonismes.

Un SVG du wiki doit passer le validateur **sur les 2 surfaces**, puisqu'il ne peut pas
livrer une palette par thème comme le suppose `dataviz`. Éviter `fill-opacity` pour la même
raison : le résultat dépend du fond, qu'on ne contrôle pas.

SVG écrits à la main, palette GitHub dark, `viewBox` ~640 de large, police Segoe UI. Boîtes = `rect` bordure `#30363d` + barre d'accent 4px colorée à gauche ; pills = `rect rx=12` bordure colorée.

Chaque teinte a **2 pas** : le vif pour les accents fins, l'atténué pour les aplats de
données. Un aplat large en couleur vive tombe dans l'anti-pattern « thick saturated
blocks », alors que la même couleur sur une barre d'accent de 4px est correcte.

| Rôle | Accent fin (barre 4px, stroke) | Aplat de données (barre, bande) |
|---|---|---|
| Succès / gate / spot | `#3fb950` | `#4e8f57` |
| Release / accent chaud | `#f78166` | `#c9714f` |
| Sécurité / info | `#58a6ff` | `#5b8fc9` |
| Neutre | `#8b949e` | `#8b949e` |

| Rôle | Couleur |
|---|---|
| Texte dans une boîte remplie | `#e6edf3` |
| Texte sur le fond de page | `#6e7781` + `font-weight="600"` |
| Texte secondaire / flèches / bordure | `#8b949e` / `#30363d` |
| Fond de boîte | `#161b22` |
| Fond (pour le rendu PNG uniquement) | `#0d1117` |

Marqueur flèche réutilisable :

```xml
<marker id="arr" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
  <polygon points="0 0, 8 3, 0 6" fill="#8b949e"/>
</marker>
```

Toujours contrôler le rendu (`rsvg-convert` → PNG → Read) avant de committer : chevauchements de pills et largeurs de colonnes ne se voient pas dans le XML.

### Lisibilité dans les 2 thèmes

Le site a un toggle clair/sombre et un SVG appelé en `<img>` ne peut pas le voir : Material
pose `data-md-color-scheme` sur `<html>`, hors de portée du SVG. Un
`@media (prefers-color-scheme)` suivrait l'OS et se désynchroniserait du toggle. Donc chaque
SVG doit être lisible sur les 2 fonds par construction.

- **texte dans une boîte** : donner un `fill` à la boîte (`#161b22`), jamais `fill="none"`
  et le texte peut rester clair (`#e6edf3`)
- **texte posé sur le fond de page** (titres, légendes, libellés de flèche) : mid-grey
  `#6e7781` avec `font-weight="600"`. Ni `#e6edf3` (invisible en clair) ni `#333`
  (invisible en sombre)
- **ne pas** poser un grand `rect` sombre derrière tout le schéma : ça fait un bloc noir au
  milieu de la page en thème clair

Contrôler les 2 :

```bash
rsvg-convert -b '#ffffff' -z 2 f.svg -o light.png
rsvg-convert -b '#0d1117' -z 2 f.svg -o dark.png
```

## Gotcha 1 - la nav auto NE référence PAS l'article dans les index

La nav latérale est auto-générée depuis l'arborescence, **mais il y a deux index maintenus à la main** qu'il faut éditer, sinon l'article est "orphelin" :

- `docs/index.md` - page d'accueil, section `## CI/CD` (ou la section concernée).
- `docs/<section>/index.md` - index de la section (ex. `docs/ci-cd/index.md`).

Après avoir créé l'article, **grep les deux** pour un article voisin et ajouter la ligne au même endroit :

```bash
rg -n 'goreleaser|cocogitto' docs/index.md docs/ci-cd/index.md
```

## Gotcha 2 - markdownlint ne lint QUE les fichiers changés

La CI `lint` passe les fichiers **modifiés dans le push** à `markdownlint-cli2`. Conséquence :

- Toucher un vieil article peut réveiller une règle récente sur ses tableaux et casser la CI sans rapport avec ton changement.
- **Politique du wiki** : tableaux compacts (`|---|`, sans alignement). `MD013` (longueur) et `MD060` (`table-column-style`) sont **désactivés** dans `.markdownlint.json` - ne pas les réactiver.

Toujours relinter en local **avant de pousser**, avec la version exacte de la CI :

```bash
npx -y markdownlint-cli2@0.23.0 --config .markdownlint.json docs/**/tes-fichiers.md
```

## Gotcha 3 - MD046 casse sur les admonitions

`markdownlint` ne connaît pas la syntaxe des admonitions MkDocs. Il lit le contenu indenté
de 4 espaces comme un bloc de code indenté et `MD046` (`code-block-style: consistent`)
casse. Deux cas :

- **un bloc de code fencé dans une admonition** → erreur systématique
- **une admonition à plusieurs paragraphes** → le 1er passe en continuation lâche, les
  suivants sont vus comme du code indenté

La bonne réponse est de **sortir le bloc de code de l'admonition** et de garder l'admonition
à un seul paragraphe. Pas d'ajout de `<!-- markdownlint-disable MD046 -->` : plusieurs vieux
articles en contiennent un jamais réactivé, ce qui désactive la règle sur toute la fin du
fichier et masque de vraies erreurs.

## Gotcha 4 - `mkdocs build --strict` a besoin de `DYLD_FALLBACK_LIBRARY_PATH`

Le plugin `social` génère les cartes via `cairosvg`, qui charge `libcairo` par `dlopen`. Le
Python de `uv` ne regarde pas dans Homebrew, d'où 244 warnings `cairo` (un par page) qui font
abort `--strict` sans aucun rapport avec le contenu.

`~/.zshrc` exporte déjà la variable qui corrige ça, mais zsh ne source `.zshrc` que dans un
shell **interactif** : un shell d'agent ne l'a jamais. Donc on préfixe la commande et on
garde `--strict`, qui est exactement ce que fait la CI :

```bash
DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/lib:$HOME/lib:/usr/local/lib:/usr/lib" \
  uv run mkdocs build --strict
```

Avec ça le build sort en 0. Le seul warning non bloquant qui reste est `WARNING:root:` du
plugin git-revision-date, y compris en `--strict`.

## Common mistakes

- Créer l'article et oublier de wirer `docs/index.md` **et** `docs/<section>/index.md` (Gotcha 1).
- Aligner/reformater des tableaux pour plaire à `MD060` - la règle est désactivée exprès (Gotcha 2).
- Mettre un bloc de code fencé dans une admonition, ou une admonition multi-paragraphes (Gotcha 3).
- Croire que l'échec `--strict` local vient de l'article, ou renoncer à `--strict` (Gotcha 4).
- Committer un gros commit fourre-tout au lieu d'un commit par scope.
- Écrire les chiffres en lettres (« trois shards ») au lieu de « 3 shards ».
- Titrer une section par son mécanisme (`Le compactor en CronJob`) au lieu de ce qu'elle fait gagner.
- Un H1 qui se décrit lui-même (`nos arbitrages`) ou qui ne couvre qu'un des axes de l'article.
- Découper un exemple en nouvelle phrase avec « Concrètement : » au lieu de `, par exemple …`.
- Viser un plafond de mots par phrase : ce n'est pas le critère, la construction l'est.
- Déclarer terminé sans avoir vu la CI verte (`lint` + `deploy`).
