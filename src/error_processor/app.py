"""Error processor: receives ERROR log events from a CloudWatch Logs subscription filter.

CloudWatch Logs delivers matching events as base64-encoded, gzip-compressed JSON:
  {"awslogs": {"data": "<base64 gzip>"}}
which decodes to:
  {"logGroup": "...", "logStream": "...", "subscriptionFilters": [...],
   "logEvents": [{"id": "...", "timestamp": 1700000000000, "message": "{...json...}"}]}

This function decodes the payload, groups the errors by type and logs a summary. In a real
system this is where you would open a ticket, page someone, or forward to another tool.
"""
import base64
import gzip
import json
from collections import Counter


def decode(event):
    """Return the decoded CloudWatch Logs payload."""
    compressed = base64.b64decode(event["awslogs"]["data"])
    return json.loads(gzip.decompress(compressed))


def summarize(payload):
    errors = []
    for log_event in payload.get("logEvents", []):
        try:
            errors.append(json.loads(log_event["message"]))
        except (json.JSONDecodeError, TypeError):
            errors.append({"error_type": "Unparsed", "message": log_event.get("message")})
    by_type = Counter(e.get("error_type", "Unknown") for e in errors)
    return {
        "log_group": payload.get("logGroup"),
        "log_stream": payload.get("logStream"),
        "error_count": len(errors),
        "by_type": dict(by_type),
        "sample_request_ids": [e.get("request_id") for e in errors[:3]],
    }


def lambda_handler(event, context):
    payload = decode(event)
    if payload.get("messageType") == "CONTROL_MESSAGE":   # sent once when the filter is created
        return {"error_count": 0}
    summary = summarize(payload)
    print(json.dumps({"level": "INFO", "event": "errors_received", **summary}))
    return summary
