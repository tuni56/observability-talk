"""
Lambda ingestion handler
Receives HTTP POST /ingest, validates payload, sends to SQS.
Instrumented with ADOT Lambda Layer when ENABLE_OBSERVABILITY=true.
"""

import json
import os
import time
import uuid

import boto3
from shared.logger import StructuredLogger

logger = StructuredLogger("ingestion")
sqs    = boto3.client("sqs", region_name=os.environ.get("AWS_REGION", "us-east-2"))

SQS_QUEUE_URL = os.environ["SQS_QUEUE_URL"]

REQUIRED_FIELDS = {"source", "event_type", "payload"}


def _validate(body: dict) -> list[str]:
    """Return a list of missing required fields."""
    return [f for f in REQUIRED_FIELDS if f not in body]


def lambda_handler(event: dict, context) -> dict:
    start = time.monotonic()
    request_id = event.get("requestContext", {}).get("requestId", str(uuid.uuid4()))

    # ── Health check ──────────────────────────────────────────────────────────
    if event.get("routeKey") == "GET /health":
        return {"statusCode": 200, "body": json.dumps({"status": "ok"})}

    # ── Parse body ────────────────────────────────────────────────────────────
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError as exc:
        logger.error("Invalid JSON body", request_id=request_id, error_type=type(exc).__name__, error_message=str(exc))
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Invalid JSON", "detail": str(exc)}),
        }

    # ── Validate ──────────────────────────────────────────────────────────────
    missing = _validate(body)
    if missing:
        logger.warning("Validation failed", request_id=request_id, missing_fields=missing)
        return {
            "statusCode": 422,
            "body": json.dumps({"error": "Missing required fields", "fields": missing}),
        }

    # ── Enqueue ───────────────────────────────────────────────────────────────
    record_id = str(uuid.uuid4())
    message   = {
        "record_id":  record_id,
        "request_id": request_id,
        "source":     body["source"],
        "event_type": body["event_type"],
        "payload":    body["payload"],
        "ingested_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

    try:
        sqs.send_message(
            QueueUrl    = SQS_QUEUE_URL,
            MessageBody = json.dumps(message),
            MessageAttributes={
                "record_id": {"StringValue": record_id, "DataType": "String"},
            },
        )
    except Exception as exc:
        logger.error(
            "Failed to enqueue message",
            request_id=request_id,
            record_id=record_id,
            error_type=type(exc).__name__,
            error_message=str(exc),
        )
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Internal server error"}),
        }

    duration_ms = round((time.monotonic() - start) * 1000, 2)
    logger.info(
        "Record enqueued",
        request_id=request_id,
        record_id=record_id,
        event_type=body["event_type"],
        duration_ms=duration_ms,
    )

    return {
        "statusCode": 202,
        "headers":    {"Content-Type": "application/json"},
        "body":       json.dumps({"record_id": record_id, "status": "queued"}),
    }
