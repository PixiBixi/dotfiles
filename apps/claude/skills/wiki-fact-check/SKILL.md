---
name: wiki-fact-check
description: Use before committing a new or rewritten article on the PixiBixi wiki (repo pixibixi.github.io, docs/ tree), or when asked to verify, fact-check or audit the accuracy of an existing article. Triggers - "vérifie l'article", "fact-check", "revue d'exactitude", "est-ce que c'est juste", "relis avant commit", or once the build and the markdown lint pass in the pixibixi-wiki-article workflow.
---

# Vérifier l'exactitude d'un article du wiki

## Overview

Le build et markdownlint prouvent que l'article **s'affiche**. Rien ne prouve qu'il **dit vrai**. Ce skill couvre ce trou.

Mesuré sur 9 articles écrits par IA : 49 affirmations fausses, dont 17 sur des valeurs par défaut et des chiffres empruntés à l'upstream. La syntaxe et les noms de flags étaient presque toujours corrects. Ce qui casse, c'est ce qui se devine plausiblement.

**REQUIRED BACKGROUND :** ce skill vérifie la prose. Les blocs `yaml` et `json` sont déjà couverts par le hook `check-code-blocks` du repo, ne pas les revérifier à la main.

## Ce que produit une passe de vérification

Un rapport, jamais une modification du fichier. La correction vient après, une fois l'auteur d'accord.

Chaque constat porte **4 champs obligatoires** :

| Champ | Contenu |
|---|---|
| `Gravité` | ERREUR, OBSOLÈTE ou IMPRÉCIS (voir le barème) |
| `Ligne` | `docs/<section>/<article>.md:<n>` |
| `Article` | citation courte de ce que dit l'article |
| `Réel` | le fait correct, suivi de sa source |

Le champ `Réel` porte une **citation verbatim** de la source et son URL, ou un `fichier:ligne` du dépôt upstream. Une reformulation présentée entre guillemets est une citation inventée : recopier les mots exacts ou ne pas mettre de guillemets.

Terminer par un décompte : affirmations contrôlées, ERREUR, OBSOLÈTE, IMPRÉCIS.

## Le barème de gravité

C'est le point où une vérification se dégrade en tampon. Le test est **ce que fait le lecteur**, pas la distance à la vérité :

- **ERREUR** : un lecteur qui applique la phrase fait le mauvais geste, ou en tire une garantie qui n'existe pas.
- **OBSOLÈTE** : vrai dans une version antérieure, faux dans la version courante.
- **IMPRÉCIS** : le geste reste correct, seule la formulation est approximative.

Une affirmation vraie « seulement si » une condition non écrite est une **ERREUR**, pas une imprécision. « `maxSkew: 1` garantit un pod par node » est faux dès que les replicas dépassent les nodes : le lecteur en tire une garantie de drain qu'il n'a pas.

## Extraire avant de vérifier

Vérifier au fil de la lecture laisse passer ce qui n'accroche pas l'œil. Lister d'abord, contrôler ensuite.

Balayer l'article et sortir **toutes** les affirmations de ces 6 familles, chacune devenant une ligne à contrôler :

1. **Valeurs par défaut** d'un flag, d'un champ d'API, d'une option de config
2. **Chiffres** : seuils, ratios, gains de perf, pourcentages, tailles
3. **Noms** de flags, de métriques, de champs YAML, de commandes, et le composant qui les porte
4. **Comportements** : ce que fait un mécanisme, dans quel ordre, avec quel effet de bord
5. **Versions** : depuis quand, jusqu'à quand, GA ou beta, déprécié ou supprimé
6. **Codes de retour** et messages d'erreur cités

Les familles 1 et 2 sont les plus rentables : à elles deux, un tiers des erreurs observées.

## Le code prime sur la doc

La doc upstream est en retard ou fausse plus souvent qu'on ne le croit, et c'est précisément sur les points subtils.

Deux cas rencontrés le même jour :

- `query-frontend.md` de Thanos affirme encore que seules les range queries traversent le frontend. `roundtrip.go` définit un `newInstantQueryTripperware` depuis la 0.35.
- Un agent a rendu `thanos_bucket_store_series_gate_duration_seconds`. Le vrai nom est `..._gate_queries_duration_seconds`, lisible uniquement dans `pkg/gate/gate.go`.

Donc, pour toute affirmation des familles 1, 3 et 4 : **aller lire le source**, pas seulement la page de doc. Une valeur par défaut se lit dans la déclaration du flag, un nom de métrique dans sa définition, un comportement dans la fonction qui l'implémente.

Quand la doc et le code se contredisent, le code gagne et le rapport signale la contradiction.

## Chercher à casser, pas à valider

Un agent à qui on demande « vérifie cet article » confirme l'article. La posture qui trouve quelque chose est l'inverse : pour chaque affirmation, chercher activement le contre-exemple, la condition manquante, la version où c'est devenu faux.

Une affirmation qu'on n'a pas réussi à sourcer n'est pas validée. Elle sort en IMPRÉCIS avec la mention que la source manque, à charge de l'auteur de trancher.

## Quick reference

| Question | Où trouver la réponse |
|---|---|
| Valeur par défaut d'un flag | La déclaration du flag dans `cmd/` ou l'aide générée, pas un article de blog |
| Nom exact d'une métrique | Sa définition (`promauto.New...`), en incluant les préfixes ajoutés par un `WrapRegistererWithPrefix` |
| Un champ d'API k8s et son défaut | `kubernetes/api`, `core/v1/types.go`, commentaire du champ |
| GA ou beta | `pkg/features/kube_features.go` pour k8s, le CHANGELOG sinon |
| Un chiffre de perf emprunté | La PR ou le benchmark d'origine. Un nombre rond non sourcé est presque toujours faux |
| Un comportement de CLI | Le code de la sous-commande, la doc en second |

## Common mistakes

- **Vérifier au fil de la lecture** au lieu d'extraire d'abord : ce qui n'accroche pas l'œil n'est jamais contrôlé.
- **Classer en « nuance » ce qui change le geste du lecteur.** Le barème tranche, pas l'impression.
- **Citer de mémoire.** Une paraphrase entre guillemets fait passer une invention pour une source.
- **S'arrêter à la doc** sur une valeur par défaut ou un nom de métrique.
- **Revérifier les blocs YAML et JSON**, déjà couverts par le hook du repo.
- **Corriger dans la foulée.** Le rapport passe par l'auteur d'abord : sur un chiffre issu d'une mesure maison, seul lui sait lequel est le bon.

## Coût

Une passe tourne autour de 90k à 120k tokens par article.

Prendre **Sonnet** : contrôler qu'un flag existe et lire son défaut est du travail de motif. Réserver **Opus** aux articles dont la démonstration est un raisonnement chiffré, où l'enjeu est de voir qu'un calcul ne tient pas.
