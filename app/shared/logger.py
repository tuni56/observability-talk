"""
Shared structured logger — ADR-003
All services import this module to emit structured JSON logs.
Mandatory fields are enforced here, not per-developer discretion.
"""

import json
import logging
import os
import time
from typing import Any

# OTel trace context — populated automatically when ADOT is active
try:
    from opentelemetry import trace

    def _get_trace_context() -> dict:
        span = trace.get_current_span()
        ctx = span.get_span_context()
        if ctx.is_valid:
            trace_id = format(ctx.trace_id, "032x")
            span_id  = format(ctx.span_id, "016x")
            # X-Ray format: 1-{first 8 hex of trace_id}-{remaining 24}
            xray_trace_id = f"1-{trace_id[:8]}-{trace_id[8:]}"
            return {"trace_id": xray_trace_id, "span_id": span_id}
        return {}

except ImportError:
    def _get_trace_context() -> dict:
        return {}


class StructuredLogger:
    """
    Emits JSON logs with the mandatory schema defined in ADR-003.
    Usage:
        logger = StructuredLogger("ingestion")
        logger.info("Record received", record_id="abc123", duration_ms=42)
    """

    LEVELS = {
        "DEBUG":    logging.DEBUG,
        "INFO":     logging.INFO,
        "WARNING":  logging.WARNING,
        "ERROR":    logging.ERROR,
        "CRITICAL": logging.CRITICAL,
    }

    def __init__(self, service: str):
        self.service     = service
        self.environment = os.environ.get("ENVIRONMENT", "demo")
        level_name       = os.environ.get("LOG_LEVEL", "INFO").upper()
        self._level      = self.LEVELS.get(level_name, logging.INFO)

        # Use the root handler but emit pre-formatted JSON
        self._logger = logging.getLogger(service)
        self._logger.setLevel(self._level)

        if not self._logger.handlers:
            handler = logging.StreamHandler()
            handler.setFormatter(logging.Formatter("%(message)s"))
            self._logger.addHandler(handler)
            self._logger.propagate = False

    def _emit(self, level: str, message: str, **extra: Any) -> None:
        if self.LEVELS[level] < self._level:
            return

        record: dict[str, Any] = {
            "timestamp":   time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
            "level":       level,
            "service":     self.service,
            "environment": self.environment,
            "message":     message,
        }

        record.update(_get_trace_context())
        record.update(extra)

        self._logger.log(self.LEVELS[level], json.dumps(record, default=str))

    def debug(self, message: str, **extra: Any) -> None:
        self._emit("DEBUG", message, **extra)

    def info(self, message: str, **extra: Any) -> None:
        self._emit("INFO", message, **extra)

    def warning(self, message: str, **extra: Any) -> None:
        self._emit("WARNING", message, **extra)

    def error(self, message: str, **extra: Any) -> None:
        self._emit("ERROR", message, **extra)

    def critical(self, message: str, **extra: Any) -> None:
        self._emit("CRITICAL", message, **extra)
