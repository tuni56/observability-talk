# ADR-004: Alerting Strategy — Avoiding Alert Fatigue

**Date:** 2024-10  
**Status:** Accepted  
**Deciders:** Platform Engineering Team

---

## Context

Alert fatigue is a direct consequence of poor governance: too many alarms, too sensitive
thresholds, or alerting on symptoms instead of causes. The result is that engineers
start ignoring alerts — which defeats the entire purpose of observability.

We need an alerting strategy that:
1. Pages on user-impacting events only
2. Has a clear owner and response playbook per alert
3. Does not fire during normal traffic variance

---

## Decision

**We alert on SLO burn rate, not on raw metric thresholds.**

Two alert tiers:

| Tier | Condition | Channel | Response SLA |
|------|-----------|---------|--------------|
| P1 — Page | Error rate burns >5% of monthly error budget in 1h | SNS → PagerDuty | 15 min |
| P2 — Ticket | P99 latency > 2x SLO baseline for 10 min sustained | SNS → Slack | Next business day |

SLO definitions:
- **Availability SLO:** 99.5% of requests succeed (error rate < 0.5%)
- **Latency SLO:** P99 < 1000ms

---

## Options Considered

### Option A: Alert on every CloudWatch metric anomaly
- ✅ Maximum coverage
- ❌ High false positive rate — traffic spikes trigger alerts during normal operation
- ❌ Engineers learn to ignore alerts within weeks
- ❌ Every alert requires investigation time — creates toil, not governance

### Option B: Static thresholds (e.g., "alert if error rate > 1%")
- ✅ Simple to configure
- ❌ Does not account for traffic patterns (1% at 10 req/s = 1 error, 1% at 10k req/s = 100 errors)
- ❌ Threshold calibration is manual and gets stale

### Option C: SLO burn rate alerting (chosen)
- ✅ Alerts correlate directly to user impact — not implementation details
- ✅ Burn rate accounts for traffic volume automatically
- ✅ Monthly error budget gives engineering teams a clear contract
- ✅ Reduces alert volume by 70-80% vs threshold-based (industry data)
- ❌ Requires defining SLOs first — upfront work
- ❌ More complex CloudWatch math expressions
- ❌ Team needs to understand error budget concept

---

## Alert Definitions (CloudWatch)

```hcl
# P99 Latency Burn Rate — implemented in terraform/modules/observability/alarms.tf
# Uses CloudWatch Metric Math to calculate burn rate against SLO baseline
```

**What we do NOT alert on:**
- CPU/Memory utilization (unless directly tied to an SLO breach)
- Queue depth in isolation (it's a leading indicator, not a user impact)
- Individual Lambda errors below error budget threshold

**What we DO alert on:**
- SLO burn rate (as above)
- Dead Letter Queue messages > 0 (these are guaranteed failures, not samples)
- ECS task crash loops (availability impact)

---

## Consequences

- All alarms have a `runbook_url` tag pointing to the response playbook
- SNS topics are segmented by tier (P1, P2) — different subscribers
- Alert history is reviewed monthly in the platform team sync
- Adding a new alarm requires: metric, threshold justification, owner, and runbook

---

## References

- [Google SRE Book — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
- [CloudWatch Metric Math](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/using-metric-math.html)
