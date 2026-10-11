---
name: tf-module-release
description: >
  Use right after a Terraform module MR is merged and the new version must be tagged and
  rolled into its callers: "fais le tag & bump module.hcl", "tag une nouvelle version",
  "bump le module dans <repo>", "release le module", "<n> est merge, tag", "bump <module>
  to X". Covers the semver choice, the signed annotated tag, finding every caller on the
  default branch of the live repos, and the bump MRs. Not for writing the module change,
  app repos versioned by a release tool, or Helm chart releases.
---

# Terraform module release

A module version is a signed annotated tag on the default-branch merge commit; callers pin it with `?ref=<version>` in their `.hcl` or `.tf` source. No CI job tags for you.

## 1. Tag

In the module's local clone (fetch, never check out the user's branch):

```bash
M=~/path/to/module-clone
git -C "$M" fetch origin --tags
git -C "$M" tag --sort=-v:refname | head -3      # the existing scheme: bare X.Y.Z or vX.Y.Z
git -C "$M" log --oneline -5 origin/main
```

| Change since the last tag | Bump |
|---|---|
| Removed or renamed input, new required input, resource replaced for existing callers | major |
| New optional input or output, new feature, behavior unchanged when unset | minor |
| Fix, docs, CI only | patch |

Follow the existing tag scheme exactly. Message: subject = the change in one line with the ticket key; body = what callers see, and whether bumping plans no change. Signed through `tag.gpgsign`:

```bash
git -C "$M" tag -a 16.3.0 origin/main -F "$MSG"
git -C "$M" tag -v 16.3.0
git -C "$M" push origin 16.3.0
```

Confirm `origin/main` is the merge commit of the MR before tagging. Show the tag name and message and wait for a yes: a pushed tag is consumed immediately and is never re-pointed.

## 2. Find every caller

On the fetched default branch of each live repo, not the working tree (a stale checkout shows old refs):

```bash
git -C <live-repo> fetch origin
git -C <live-repo> grep -n '<module-name>.git' origin/main -- '*.hcl' '*.tf'
```

List callers in a table: repo, file, current ref. A caller more than one major behind gets its own decision, never a silent multi-major jump.

## 3. Bump MR per caller repo

- Commit `chore(<scope>): bump <module> to <version>` with the ticket key, body saying whether the plan is expected to be empty. Bump alone: an input change is its own `feat()` commit. One MR per repo (`mr-open`).
- The MR plan (`gitlab-job-triage` to read it) must match the tag message: "no change" means zero add/change/destroy on every caller unit.
- In repos that apply on merge, merging is the user's call.

## Common mistakes

| Mistake | Instead |
|---|---|
| Tagging the feature branch head or local `main` | `origin/main` after fetch, the merge commit |
| Changing the tag scheme (`v` prefix or not) | Copy the existing tags |
| Lightweight or unsigned tag | `git tag -a`, verify with `git tag -v` |
| Minor bump for a removed input | Major |
| Grepping the working tree of a live repo | `git grep` on `origin/main` |
| Bumping and changing inputs in one commit | Two commits |
