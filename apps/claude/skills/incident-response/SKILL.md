---
name: incident-response
description: Use when a production issue is happening or suspected (an alert fired, a service is down or degraded, error rate or latency spiked, users report breakage, a deploy or config change looks like the trigger), or when writing the postmortem or runbook that follows. Triggers - "on a un incident", "c'est down en prod", "alerte", "ça déconne en prod", "postmortem", "runbook".
---

# Incident Response

## Overview

Condensed FIRE loop for production issues: stop the bleeding first, find the root cause second.

## When to Use

- An alert fired, a service is down or degraded, error rate or latency spiked
- Someone reports breakage and production is a plausible cause
- Writing the postmortem or runbook after the fact

Not for: local bugs with no production impact (use `systematic-debugging`), or planned changes (normal review flow).

## The Loop

1. **First response**: state the symptom, the impact (who and what is affected, severity), and any recent change that could be the trigger.
2. **Investigate**: one hypothesis at a time, backed by evidence. For deep diagnosis, use the `systematic-debugging` skill.
3. **Remediate**: propose options and wait for approval. Mitigation beats root cause at this stage: stop the bleeding, fix properly after.
4. **Evaluate**: once stable, write a short postmortem whose last section is prevention items.

## Response Style

- Lead with impact assessment, not root cause
- Give exact commands, not guidance
- Timestamp every action taken, the timeline is the postmortem's backbone

## Runbook Format

Operational and troubleshooting docs follow:

`Symptoms → Prerequisites → Steps → Verification → Rollback → Escalation`

## Common Mistakes

| Mistake | Instead |
|---------|---------|
| Chasing root cause while users are down | Mitigate first, investigate once stable |
| Applying a fix without approval | Propose options, wait |
| Reconstructing the timeline afterwards | Timestamp each action as you take it |
| Postmortem with no prevention items | Every postmortem ends in action items |
