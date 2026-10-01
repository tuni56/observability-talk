# ADR-001: OpenTelemetry (ADOT) vs AWS-Native Observability Only

**Date:** 2024-10  
**Status:** Accepted  
**Deciders:** Platform Engineering Team

---

## Context

We need to instrument a mixed workload (Lambda + ECS Fargate) with distributed tracing
and metrics. Two main options exist: use AWS-native tooling exclusively (X-Ray SDK, 
CloudWatch agent) or adopt the OpenTelemetry standard via AWS Distro for OpenTelemetry (ADOT).

The key tension: AWS-native is simpler to set up but increases vendor lock-in.
OpenTelemetry is the industry standard but adds operational complexity.

---

## Decision

**We adopt ADOT (AWS Distro for OpenTelemetry) as our instrumentation layer.**

X-Ray remains the backend for traces. CloudWatch remains the backend for metrics.
ADOT acts as the collection and export layer — we instrument once, route anywhere.

---

## Options Considered

### Option A: AWS X-Ray SDK + CloudWatch Agent (native only)
- ✅ Simpler setup, less moving parts
- ✅ Native console integration
- ❌ Vendor lock-in: migrating traces backend requires re-instrumentation
- ❌ X-Ray SDK is not OTel-compatible by default
- ❌ No standard for metrics/logs correlation

### Option B: ADOT (OpenTelemetry standard, AWS-managed distro)
- ✅ OTel is the CNCF standard — portable across backends (X-Ray, Jaeger, Datadog)
- ✅ AWS manages the distro — security patches, Lambda layers, ECS sidecar
- ✅ Correlates traces + metrics + logs via trace context propagation
- ✅ Sampling configuration is declarative (YAML), not code
- ❌ Additional component to manage (ADOT Collector sidecar in ECS)
- ❌ Slightly higher cold start on Lambda (~50ms) due to layer overhead

### Option C: Third-party APM (Datadog, New Relic, Dynatrace)
- ✅ Rich UI, anomaly detection out of the box
- ❌ Cost at scale is significant
- ❌ Data leaves AWS boundary (compliance concern)
- ❌ Out of scope for this architecture

---

## Consequences

- Lambda functions use the **ADOT Lambda Layer** — no agent to manage
- ECS tasks run the **ADOT Collector as a sidecar container** — exports to X-Ray + CloudWatch
- Instrumentation code uses `opentelemetry-sdk` (Python) — not the X-Ray SDK directly
- If we ever migrate from X-Ray to another backend, only the collector config changes
- Trade-off accepted: +50ms Lambda cold start is acceptable for our p50/p99 SLOs

---

## References

- [AWS Distro for OpenTelemetry](https://aws-otel.github.io/)
- [ADOT Lambda Layer](https://aws-otel.github.io/docs/getting-started/lambda)
- [ADOT ECS Setup](https://aws-otel.github.io/docs/setup/ecs)
