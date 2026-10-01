# ADR-003: Structured Logging Schema

**Date:** 2024-10  
**Status:** Accepted  
**Deciders:** Platform Engineering Team

---

## Context

Unstructured logs are the most common observability anti-pattern. They are human-readable
but machine-unfriendly: impossible to query at scale, expensive to parse, and create
cognitive overhead during incidents.

We need a logging standard that:
1. Is queryable via CloudWatch Logs Insights without parsing magic
2. Correlates with traces (trace_id propagation)
3. Has mandatory fields enforced at the platform level, not per-developer discretion

---

## Decision

**All services emit structured JSON logs with a mandatory base schema.**

Mandatory fields enforced via a shared logging library (`app/shared/logger.py`):

```json
{
  "timestamp": "2024-10-01T19:00:00.000Z",
  "level": "INFO",
  "service": "processor",
  "environment": "demo",
  "trace_id": "1-abc123-...",
  "span_id": "abc456",
  "request_id": "uuid-v4",
  "message": "human readable message",
  "duration_ms": 42
}
```

Optional but standardized fields:
```json
{
  "error_type": "TimeoutError",
  "error_message": "...",
  "record_id": "...",
  "queue_message_id": "...",
  "http_status_code": 200
}
```

---

## Options Considered

### Option A: Unstructured logs (print/logging.info)
- ✅ Zero setup cost
- ❌ CloudWatch Insights requires regex parsing — slow and brittle
- ❌ No trace correlation — impossible to join logs + traces for a single request
- ❌ Inconsistent across services — each developer invents their own format

### Option B: Structured JSON with no schema enforcement
- ✅ Machine-readable
- ❌ Without enforcement, field names diverge (e.g., `traceId` vs `trace_id` vs `TraceID`)
- ❌ Mandatory fields get omitted under time pressure

### Option C: Structured JSON with mandatory schema (chosen)
- ✅ CloudWatch Insights queries work without parsing: `filter service="processor" | stats avg(duration_ms)`
- ✅ `trace_id` propagation enables log-to-trace correlation in the console
- ✅ Schema is code — enforced by the shared logger, not by documentation
- ❌ Requires a shared library that all services import
- ❌ Adding new mandatory fields requires updating all services

---

## Consequences

- `app/shared/logger.py` is the single source of truth for log schema
- Any field not in the schema can be added as `extra={}` kwargs — no blocking
- CloudWatch Logs Insights sample queries are pre-built in `observability/queries/`
- `trace_id` is extracted from the OTel context — not passed manually
- Log level `DEBUG` is disabled in production via `LOG_LEVEL` env var

---

## Sample CloudWatch Insights Queries

```sql
-- P99 latency by service
filter ispresent(duration_ms)
| stats pct(duration_ms, 99) as p99, avg(duration_ms) as avg by service
| sort p99 desc

-- All errors in the last hour
filter level = "ERROR"
| fields timestamp, service, error_type, error_message, trace_id
| sort timestamp desc

-- Trace correlation: find all logs for a specific request
filter trace_id = "1-abc123-..."
| fields timestamp, service, level, message
| sort timestamp asc
```
