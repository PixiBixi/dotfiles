---
name: wiki-fact-check
description: Use before committing a new or rewritten article on the PixiBixi wiki (repo pixibixi.github.io, docs/ tree), or when asked to verify, fact-check or audit the accuracy of an existing article. Triggers - "vérifie l'article", "fact-check", "revue d'exactitude", "est-ce que c'est juste", "relis avant commit", or once the build and the markdown lint pass in the pixibixi-wiki-article workflow.
---

# Fact-checking a wiki article

## Overview

The build and markdownlint prove an article **renders**. Nothing proves it is **true**. This skill covers that gap.

Measured across 9 AI-written articles: 49 false claims, 17 of them default values or numbers borrowed from upstream. Syntax and flag names were almost always right. What breaks is whatever can be guessed plausibly.

**REQUIRED BACKGROUND:** this skill checks prose. The `yaml` and `json` fences are already covered by the repo's `check-code-blocks` pre-commit hook, so do not re-verify them by hand.

## What a verification pass produces

A report, never an edit to the article. The fix comes afterwards, once the author agrees.

Every finding carries **4 required fields**:

| Field | Content |
|---|---|
| `Severity` | ERROR, OUTDATED or IMPRECISE (see the rubric) |
| `Line` | `docs/<section>/<article>.md:<n>` |
| `Article` | short quote of what the article says |
| `Actual` | the correct fact, followed by its source |

The `Actual` field carries a **verbatim quote** of the source plus its URL, or a `file:line` in the upstream repository. A paraphrase presented inside quotation marks is a fabricated citation: copy the exact words, or drop the quotation marks.

Close with a tally: claims checked, ERROR, OUTDATED, IMPRECISE.

## The severity rubric

This is where a verification degrades into a rubber stamp. The test is **what the reader does**, not how far the sentence is from the truth:

- **ERROR**: a reader who acts on the sentence does the wrong thing, or takes away a guarantee that does not exist.
- **OUTDATED**: true in an earlier version, false in the current one.
- **IMPRECISE**: the reader still does the right thing, only the wording is loose.

A claim that holds only under an unstated condition is an **ERROR**, not an imprecision. "`maxSkew: 1` guarantees one pod per node" is false as soon as replicas outnumber nodes: the reader takes away a drain guarantee they do not have.

## Extract before verifying

Verifying while reading misses whatever does not catch the eye. List first, check second.

Sweep the article and pull out **every** claim in these 6 families, each becoming one line to check:

1. **Default values** of a flag, an API field, a config option
2. **Numbers**: thresholds, ratios, performance gains, percentages, sizes
3. **Names** of flags, metrics, YAML fields, commands, and which component owns them
4. **Behaviours**: what a mechanism does, in what order, with what side effect
5. **Versions**: since when, until when, GA or beta, deprecated or removed
6. **Return codes** and quoted error messages

Families 1 and 2 pay best: together they accounted for a third of the observed errors.

## Source beats documentation

Upstream docs lag or lie more often than expected, and precisely on the subtle points.

Two cases hit on the same day:

- Thanos `query-frontend.md` still claims only range queries go through the frontend. `roundtrip.go` has defined a `newInstantQueryTripperware` since 0.35.
- An agent reported `thanos_bucket_store_series_gate_duration_seconds`. The real name is `..._gate_queries_duration_seconds`, readable only in `pkg/gate/gate.go`.

So for any claim in families 1, 3 and 4: **go read the source**, not just the doc page. A default value lives in the flag declaration, a metric name in its definition, a behaviour in the function implementing it.

When docs and code disagree, code wins and the report flags the contradiction.

## Try to break it, not to confirm it

An agent asked to "verify this article" confirms the article. The posture that finds anything is the opposite: for each claim, actively hunt the counter-example, the missing condition, the version where it stopped being true.

A claim that could not be sourced is not validated. It goes out as IMPRECISE, noting the source is missing, and the author decides.

## Quick reference

| Question | Where the answer lives |
|---|---|
| Default value of a flag | The flag declaration under `cmd/`, or generated help. Never a blog post |
| Exact name of a metric | Its definition (`promauto.New...`), including any prefix added by a `WrapRegistererWithPrefix` |
| A Kubernetes API field and its default | `kubernetes/api`, `core/v1/types.go`, the field comment |
| GA or beta | `pkg/features/kube_features.go` for Kubernetes, the CHANGELOG otherwise |
| A borrowed performance number | The originating PR or benchmark. An unsourced round number is almost always wrong |
| A CLI behaviour | The subcommand's code first, the docs second |

## Common mistakes

- **Verifying while reading** instead of extracting first: whatever does not catch the eye never gets checked.
- **Filing something as a nuance when it changes what the reader does.** The rubric decides, not the impression.
- **Quoting from memory.** A paraphrase inside quotation marks passes an invention off as a source.
- **Stopping at the docs** for a default value or a metric name.
- **Re-checking YAML and JSON fences**, already covered by the repo hook.
- **Fixing on the spot.** The report goes to the author first: when a number comes from their own measurement, only they know which one is right.

## Cost

A pass runs about 90k to 120k tokens per article.

Use **Sonnet**: checking that a flag exists and reading its default is pattern work. Reserve **Opus** for articles whose argument is a numeric chain, where the point is to notice that a calculation does not hold.
