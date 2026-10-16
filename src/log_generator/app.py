"""Log generator: pretends to be a small online-shop "orders" service.

Every invocation simulates a batch of requests and writes one structured JSON log line per
request to CloudWatch Logs, so the lab has realistic data for metric filters, alarms and
Logs Insights queries.

Each log line looks like:
  {"level": "INFO", "service": "orders-api", "event": "order_placed", "path": "/orders",
   "method": "POST", "status": 201, "latency_ms": 87, "order_value": 54.99,
   "customer_email": "ama@example.com", "request_id": "...", "message": "Order placed"}

Invoke it with {"mode": "errors"} to force an error spike (used to test the alarm).
"""
import json
import os
import random
import time
import uuid

SERVICE = os.environ.get("SERVICE_NAME", "orders-api")
ERROR_RATE = float(os.environ.get("ERROR_RATE", "0.05"))
REQUESTS_PER_RUN = int(os.environ.get("REQUESTS_PER_RUN", "20"))

ROUTES = [
    # (method, path, event, success status, typical latency ms)
    ("GET", "/products", "products_listed", 200, 40),
    ("GET", "/products/{id}", "product_viewed", 200, 25),
    ("POST", "/cart", "cart_updated", 200, 60),
    ("POST", "/orders", "order_placed", 201, 120),
    ("GET", "/orders/{id}", "order_viewed", 200, 35),
]
ERRORS = [
    (500, "PaymentGatewayTimeout", "Payment provider did not respond within 3000 ms"),
    (500, "DatabaseConnectionError", "Could not connect to orders database"),
    (503, "InventoryServiceUnavailable", "Inventory service returned 503"),
]
WARNINGS = [
    (429, "RateLimited", "Client exceeded 100 requests per minute"),
    (400, "ValidationError", "Field 'quantity' must be greater than 0"),
]
CUSTOMERS = ["ama.mensah", "kofi.boateng", "sarah.johnson", "michael.chen", "fatima.okafor",
             "james.smith", "priya.patel", "lucas.silva", "emma.brown", "yaw.asante"]


def make_record(rng, force_error=False):
    """Build one simulated request log record."""
    method, path, event, status, base_latency = rng.choice(ROUTES)
    record = {
        "level": "INFO",
        "service": SERVICE,
        "event": event,
        "method": method,
        "path": path,
        "status": status,
        "latency_ms": max(1, int(rng.gauss(base_latency, base_latency * 0.3))),
        "customer_email": f"{rng.choice(CUSTOMERS)}@example.com",
        "request_id": str(uuid.UUID(int=rng.getrandbits(128))),
        "message": event.replace("_", " ").capitalize(),
    }
    roll = rng.random()
    if force_error or roll < ERROR_RATE:
        code, error_type, message = rng.choice(ERRORS)
        record.update(level="ERROR", status=code, error_type=error_type, message=message,
                      latency_ms=rng.randint(2500, 3500))
    elif roll < ERROR_RATE + 0.08:
        code, error_type, message = rng.choice(WARNINGS)
        record.update(level="WARN", status=code, error_type=error_type, message=message)
    elif event == "order_placed":
        record["order_value"] = round(rng.uniform(10, 300), 2)
    return record


def lambda_handler(event, context, rng=None):
    rng = rng or random.Random()
    force_errors = (event or {}).get("mode") == "errors"
    count = int((event or {}).get("count", REQUESTS_PER_RUN))
    summary = {"INFO": 0, "WARN": 0, "ERROR": 0}
    for _ in range(count):
        record = make_record(rng, force_error=force_errors)
        record["timestamp"] = int(time.time() * 1000)
        summary[record["level"]] += 1
        print(json.dumps(record))      # stdout → CloudWatch Logs
    print(json.dumps({"level": "INFO", "service": SERVICE, "event": "batch_complete",
                      "message": f"Generated {count} requests", **{k.lower(): v for k, v in summary.items()}}))
    return summary
