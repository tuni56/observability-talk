"""
ECS Fargate processor — the heart of the demo.

This service polls SQS, processes records, writes to DynamoDB and S3.

THE BOTTLENECK (INTRODUCE_LATENCY_BUG=true):
  A synchronous HTTP call to a mock "validation API" is made inside the
  processing loop, BEFORE writing the record. This simulates a real-world
  anti-pattern: a synchronous dependency on an external service in a hot path.

  Without observability: p99 goes from ~400ms to ~8s. Silent. No alert fires.
  With X-Ray: the trace map shows a thick red segment on the "validate" span.
  One glance at the waterfall = root cause identified.

THE FIX (live demo moment):
  Set INTRODUCE_LATENCY_BUG=false, redeploy — p99 drops immediately.
"""

import json
import os
import time
import uuid
import contextlib
from typing import Any

import boto3
import urllib.request
import urllib.error

from shared.logger import StructuredLogger

# ── OTel tracing setup (active when ENABLE_OBSERVABILITY=true) ─────────────
ENABLE_OBSERVABILITY = os.environ.get("ENABLE_OBSERVABILITY", "true").lower() == "true"

if ENABLE_OBSERVABILITY:
    from opentelemetry import trace
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

    provider = TracerProvider()
    otlp_exporter = OTLPSpanExporter(
        endpoint=os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317"),
        insecure=True,
    )
    provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
    trace.set_tracer_provider(provider)
    tracer = trace.get_tracer("processor")
else:
    # No-op tracer — zero overhead when observability is disabled
    class _NoopSpan:
        def set_attribute(self, *a, **kw): pass
        def record_exception(self, *a, **kw): pass
        def set_status(self, *a, **kw): pass
        def __enter__(self): return self
        def __exit__(self, *a): pass

    class _NoopTracer:
        @contextlib.contextmanager
        def start_as_current_span(self, name, **kw):
            yield _NoopSpan()

    tracer = _NoopTracer()

# ── AWS clients ───────────────────────────────────────────────────────────────
REGION         = os.environ.get("AWS_REGION", "us-east-2")
SQS_QUEUE_URL  = os.environ["SQS_QUEUE_URL"]
DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]
S3_BUCKET      = os.environ["S3_BUCKET"]

sqs      = boto3.client("sqs",      region_name=REGION)
dynamodb = boto3.client("dynamodb", region_name=REGION)
s3       = boto3.client("s3",       region_name=REGION)

INTRODUCE_LATENCY_BUG = os.environ.get("INTRODUCE_LATENCY_BUG", "false").lower() == "true"
MOCK_VALIDATION_URL   = os.environ.get("MOCK_VALIDATION_URL", "http://httpbin.org/delay/2")

logger = StructuredLogger("processor")


def _external_validation(record_id: str) -> bool:
    """
    DEMO BOTTLENECK: synchronous external call that adds ~2s per record.
    X-Ray shows this as the fat span in the waterfall.
    """
    with tracer.start_as_current_span("external_validation") as span:
        span.set_attribute("record.id", record_id)
        span.set_attribute("validation.url", MOCK_VALIDATION_URL)
        start = time.monotonic()
        try:
            req = urllib.request.Request(MOCK_VALIDATION_URL, method="GET")
            with urllib.request.urlopen(req, timeout=10) as resp:
                duration_ms = round((time.monotonic() - start) * 1000, 2)
                span.set_attribute("validation.duration_ms", duration_ms)
                return True
        except urllib.error.URLError as exc:
            duration_ms = round((time.monotonic() - start) * 1000, 2)
            span.record_exception(exc)
            logger.warning("External validation failed", record_id=record_id,
                           duration_ms=duration_ms, error_message=str(exc))
            return False


def _write_to_dynamodb(record: dict[str, Any]) -> None:
    with tracer.start_as_current_span("dynamodb_write") as span:
        span.set_attribute("db.system", "dynamodb")
        span.set_attribute("db.table", DYNAMODB_TABLE)
        dynamodb.put_item(
            TableName=DYNAMODB_TABLE,
            Item={
                "record_id":    {"S": record["record_id"]},
                "request_id":   {"S": record.get("request_id", "")},
                "source":       {"S": record.get("source", "")},
                "event_type":   {"S": record.get("event_type", "")},
                "processed_at": {"S": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())},
                "expires_at":   {"N": str(int(time.time()) + 86400 * 7)},
            },
            ConditionExpression="attribute_not_exists(record_id)",
        )


def _write_to_s3(record: dict[str, Any]) -> None:
    with tracer.start_as_current_span("s3_write") as span:
        key = f"raw/{record.get('event_type','unknown')}/{record['record_id']}.json"
        span.set_attribute("s3.bucket", S3_BUCKET)
        span.set_attribute("s3.key", key)
        s3.put_object(
            Bucket=S3_BUCKET, Key=key,
            Body=json.dumps(record, default=str).encode(),
            ContentType="application/json",
        )


def process_record(message_body: str) -> None:
    with tracer.start_as_current_span("process_record") as span:
        start = time.monotonic()
        record = json.loads(message_body)
        record_id = record.get("record_id", str(uuid.uuid4()))

        span.set_attribute("record.id", record_id)
        span.set_attribute("record.event_type", record.get("event_type", "unknown"))
        span.set_attribute("latency_bug.enabled", INTRODUCE_LATENCY_BUG)

        logger.info("Processing record", record_id=record_id,
                    event_type=record.get("event_type"))

        if INTRODUCE_LATENCY_BUG:
            _external_validation(record_id)

        _write_to_dynamodb(record)
        _write_to_s3(record)

        duration_ms = round((time.monotonic() - start) * 1000, 2)
        span.set_attribute("process.duration_ms", duration_ms)
        logger.info("Record processed", record_id=record_id,
                    event_type=record.get("event_type"), duration_ms=duration_ms)


def poll_forever() -> None:
    logger.info("Processor starting", queue_url=SQS_QUEUE_URL,
                observability_enabled=ENABLE_OBSERVABILITY,
                latency_bug_enabled=INTRODUCE_LATENCY_BUG)

    while True:
        with tracer.start_as_current_span("sqs_poll"):
            response = sqs.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=20,
            )

        for message in response.get("Messages", []):
            try:
                process_record(message["Body"])
                sqs.delete_message(QueueUrl=SQS_QUEUE_URL,
                                   ReceiptHandle=message["ReceiptHandle"])
            except Exception as exc:
                logger.error("Failed to process record — will retry",
                             error_type=type(exc).__name__,
                             error_message=str(exc),
                             message_id=message.get("MessageId"))


if __name__ == "__main__":
    poll_forever()
