---
name: gitlab-job-triage
description: >
  Use when the user pastes a GitLab job, pipeline or MR-pipeline URL (.../-/jobs/<id>,
  .../-/pipelines/<id>), often with nothing else or with "pourquoi ça a fail ?", "c'est quoi
  cette erreur ?", "wtf ce plan", "lis le plan il est chelou", "check moi le plan", "le job
  est rouge". Covers resolving the URL, pulling the log to a file, finding the first real
  error, and reading a Terraform/Terragrunt plan critically (destroys, replacements,
  unexpected units). Read-only. Not for checking a rollout after a merge or for reviewing
  the MR diff itself.
---

# GitLab job triage

The answer is the first real error line with its cause, or for a plan the list of what it will destroy or replace. Never the last 20 lines of the log, never a retry.

## 1. Resolve the URL

| URL shape | Project path | Id |
|---|---|---|
| `<host>/<path>/-/jobs/<id>` | everything before `/-/` | job id |
| `<host>/<path>/-/pipelines/<id>` | same | pipeline id, list its jobs first |
| `<host>/<path>/-/merge_requests/<iid>` | same | MR head pipeline: `glab ci get -R <path> --merge-request=<iid> --status=failed --with-job-details` |

`glab api` wants the path `%2F`-encoded, `-R` wants it plain. Logs and JSON go to files, never through `echo` (zsh mangles `\n` inside JSON).

```bash
S=$(mktemp -d)                      # or the session scratchpad
P="group%2Fsubgroup%2Fproject"      # project path, %2F-encoded
JOB=123456789
glab api "projects/$P/jobs/$JOB" > "$S/job.json"
jq -r '[.name, .stage, .status, .failure_reason, .ref, .pipeline.id, .commit.short_id, .web_url] | @tsv' "$S/job.json"
glab api "projects/$P/jobs/$JOB/trace" > "$S/job.log"
```

Pipeline URL: `glab api "projects/$P/pipelines/<id>/jobs?per_page=100&include_retried=false"`, then triage each `failed` job, earliest stage first (a later failure is often the consequence).

## 2. Find the first real error

```bash
command rg -n -m 20 -i 'error|fatal|denied|forbidden|not found|timed out|no space|OOMKilled|exit code [1-9]' "$S/job.log"
```

| Pattern in the log | Usually means |
|---|---|
| `failure_reason` is `runner_system_failure`, `stuck_or_timeout_failure`, `scheduler_failure` | Runner side, not the change. Say so; a retry is the user's call |
| `Error acquiring the state lock` | Another apply or plan holds the lock: give the lock ID and who, never `force-unlock` |
| `403` / `Permission denied` / `iam.serviceAccounts.getAccessToken` | Workload identity or service account grant missing for that project |
| `Error: Unsupported argument` / `Missing required argument` after a module bump | The module's major version changed its inputs: diff the module tags |
| `Invalid reference` / `ref ... not found` in `terraform init` | Tag not pushed, or wrong `?ref=` in the module source |
| `context deadline exceeded` on a cloud API | Transient or quota: check whether other units hit it too |
| `exit code 137` | Job container OOMKilled: the runner size is too small for the job |

Quote the error line with its unit prefix (Terragrunt `run-all` prefixes every line with the unit) and the file/line it names, then read that file in the local clone at the job's commit: `git show <short_id>:<path>`.

## 3. Read a plan critically (plan jobs)

```bash
command rg -n 'Plan: [0-9]+ to add|No changes\.|must be replaced|will be destroyed|forces replacement' "$S/job.log"
```

Report per unit:

| Unit | add | change | destroy | replaced resources |
|---|---|---|---|---|

Then flag, in this order:

1. Any destroy or replacement the MR description does not announce. A replaced cluster, node pool, database instance, bucket or DNS zone is a stop: name it first.
2. Units in the plan that the MR did not touch (dependency fan-out, or drift: the default-branch plan shows the same change).
3. In-place changes on fields the diff does not explain (provider upgrade, default changed upstream).

Drift check: the same unit planned on the default branch, `glab ci trace <plan-job> -R <path> -b <default-branch>` (or the latest scheduled pipeline). The same diff there means drift, not the MR.

## 4. Answer

Two or three lines: job, first error with its unit, cause, what to change (file:line). For a plan: the table, then the flags. Fix only when asked.

## Common mistakes

| Mistake | Instead |
|---|---|
| Reading the tail of the log | First error, earliest failed stage |
| `glab ci retry` "to see" | Read-only; a retry is the user's decision |
| Unencoded path in `glab api` (404) | `%2F` |
| "Plan looks fine" from the summary line | Per-unit table, every destroy/replace named |
| Blaming the MR for drift | Compare with the default-branch plan |
| `force-unlock` on a lock error | Report the lock holder |
