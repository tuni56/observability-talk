# ADR-002: Sampling Strategy for Distributed Traces

**Date:** 2024-10  
**Status:** Accepted  
**Deciders:** Platform Engineering Team

---

## Context

Capturing 100% of traces in a high-throughput pipeline is expensive and creates
storage/cost bottlenecks that contradict the goal of "governance without new bottlenecks."
We need a sampling strategy that preserves signal fidelity while controlling cost.

Key constraints:
- Budget: trace storage cost must not exceed 5% of total observability budget
- Signal: P99 latency outliers and all errors must always be captured
- Throughput: system processes ~500 req/s at peak

---

## Decision

**We use X-Ray's reservoir + rate-based sampling with tail-based error capture.**

Configuration:
- **Reservoir:** 5 req/s always sampled (guaranteed baseline)
- **Rate:** 5% of requests beyond the reservoir
- **Override rule:** 100% sampling for requests where `http.status_code >= 400` or `error = true`

This is configured via ADOT Collector sampling rules — not in application code.

---

## Options Considered

### Option A: 100% sampling
- ✅ Complete visibility
- ❌ At 500 req/s, trace storage cost is ~$270/month (X-Ray pricing)
- ❌ Trace processing overhead adds ~2-5ms per request
- ❌ Creates the exact bottleneck we're trying to avoid

### Option B: Fixed 1% sampling
- ✅ Minimal cost
- ❌ At low traffic periods, may capture 0 traces for minutes at a time
- ❌ Errors may be missed entirely if they occur in unsampled requests
- ❌ Statistically unreliable for p99 calculations

### Option C: Reservoir + rate + tail-based error capture (chosen)
- ✅ Guaranteed baseline coverage regardless of traffic level
- ✅ Errors and slow requests always captured (tail-based)
- ✅ Cost predictable and bounded
- ✅ Configured in collector YAML — no code changes to adjust
- ❌ Slightly more complex initial configuration
- ❌ "Tail-based" sampling requires buffering spans briefly before sampling decision

---

## Sampling Math

At 500 req/s:
- Reservoir: 5 traces/s = 432,000 traces/day
- Rate (5% of remaining 495 req/s): ~24.75 traces/s = 2,138,400 traces/day
- Estimated cost: ~$18/month vs ~$270/month at 100%
- Error traces: 100% captured regardless

---

## Consequences

- Sampling rules live in `observability/sampling-rules.yaml` — version controlled
- Changes to sampling require a collector config update + ECS task redeploy (not a code deploy)
- We accept that ~95% of successful requests are not individually traceable
- Aggregate metrics (CloudWatch EMF) cover the gap — every request emits metrics even if not traced

---

## References

- [X-Ray Sampling Rules](https://docs.aws.amazon.com/xray/latest/devguide/xray-console-sampling.html)
- [ADOT Tail Sampling Processor](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/tailsamplingprocessor)
