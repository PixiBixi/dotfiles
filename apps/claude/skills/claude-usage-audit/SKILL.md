---
name: claude-usage-audit
description: Use when asked to analyse Claude Code token usage or spend over a period ("analyse mon usage token", "combien j'ai consommé", "pourquoi je tape la limite", "audit tokens 30 jours"), or to re-measure after a cost change. Parses ~/.claude/projects transcripts locally, no API call.
---

# Claude usage audit

Three local scripts over `~/.claude/projects/**/*.jsonl` (main sessions and `subagents/`). Each API call is deduplicated on `(message.id, requestId)`; cost is the public API price per model, so on a subscription it reads as "API-equivalent", a proxy for plan quota.

## Run

```bash
SKILL_DIR=~/.claude/skills/claude-usage-audit/scripts
OUT=$CLAUDE_SCRATCHPAD   # or any temp dir
python3 -I "$SKILL_DIR/usage.py" "$OUT/usage.json"            # totals, daily, models, projects, sessions, cache rebuilds, tools, skills, agents
python3 -I "$SKILL_DIR/context_sources.py" "$OUT/usage2.json" # Bash command families by output size, full vs partial Read, sdk entrypoints, idle gaps
python3 -I "$SKILL_DIR/cost_split.py"                         # cost by token type, cache-read tax above 200k / 300k context
python3 -I "$SKILL_DIR/history.py" "$OUT/hist.json"            # weekly prompts, cost per prompt, slash commands, sessions, hour x weekday (default 90 days)
```

Window: `AUDIT_DAYS=90` in the environment (default 30, 90 for `history.py`). Transcripts only go back `cleanupPeriodDays` (set to 120 in settings; Claude Code defaults to 30), while `~/.claude/history.jsonl` keeps every prompt: beyond the retention, only prompt-level metrics are real. Mark weeks whose transcripts were partly deleted as partial, never as low-cost.

## Before quoting dollars

Prices live in the `PRICES` table of `usage.py` and `P` in `cost_split.py`. Check them against the `claude-api` skill first and fix the table when a model is missing (an unknown model counts as $0).

## What to look at, in order

| Signal | Field | Lever |
|---|---|---|
| Calls above 200k context | `ctx_cost`, `cost_split.py` tax | `autoCompactWindow` in settings, `/clear` per topic |
| Cold resumes (cache rebuilt after >1h idle) | `cache_miss` | `cold-resume-guard.sh` hook |
| Non-CLI entrypoints (`sdk-py`, `sdk-cli`) | `entry`, `sdk` in usage2 | a plugin or hook spawning Claude: pin its model (`SG_AGENTIC_MODEL` for security-guidance) |
| Biggest tool outputs | `tool_result_kchars`, `bash_fam`, `read` | targeted Read, capped command output |
| 1h vs 5m cache TTL | `w1h` vs the 5-60 min gap count in `gaps` | keep 1h while 5-60 min gaps x context x 1.25 exceeds the 0.75x premium on 1h writes |
| Subagent share and model | `main_sub`, `agents` | Sonnet for pattern work |

Session prompts in `top_sessions` are the user's own text: keep them out of anything shared.
