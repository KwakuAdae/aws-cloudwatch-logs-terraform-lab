"""Unit tests for both Lambda functions (no AWS needed).

Run:  pip install pytest && pytest -v
"""
import base64
import gzip
import importlib.util
import json
import os
import random

ROOT = os.path.join(os.path.dirname(__file__), "..")


def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, "src", name, "app.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


generator = load("log_generator")
processor = load("error_processor")


def run_generator(capsys, event):
    summary = generator.lambda_handler(event, None, rng=random.Random(42))
    lines = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    return summary, lines


def test_generator_writes_one_json_line_per_request_plus_summary(capsys):
    summary, lines = run_generator(capsys, {"count": 50})
    assert len(lines) == 51
    assert sum(summary.values()) == 50
    assert lines[-1]["event"] == "batch_complete"


def test_generator_records_have_required_fields(capsys):
    _, lines = run_generator(capsys, {"count": 200})
    for rec in lines[:-1]:
        for field in ("level", "service", "event", "status", "latency_ms", "request_id", "customer_email", "timestamp"):
            assert field in rec
        assert rec["level"] in ("INFO", "WARN", "ERROR")
        assert rec["customer_email"].endswith("@example.com")


def test_generator_produces_a_mix_of_levels(capsys):
    summary, lines = run_generator(capsys, {"count": 500})
    assert summary["INFO"] > summary["WARN"] > 0
    assert summary["ERROR"] > 0
    assert any("order_value" in rec for rec in lines)
    assert all("error_type" in rec for rec in lines if rec["level"] == "ERROR")


def test_generator_error_mode_forces_errors(capsys):
    summary, lines = run_generator(capsys, {"mode": "errors", "count": 10})
    assert summary == {"INFO": 0, "WARN": 0, "ERROR": 10}
    assert all(rec["status"] >= 500 for rec in lines[:-1])


def encode(payload):
    return {"awslogs": {"data": base64.b64encode(gzip.compress(json.dumps(payload).encode())).decode()}}


def test_processor_summarizes_errors(capsys):
    errors = [{"level": "ERROR", "error_type": t, "request_id": f"r{i}"}
              for i, t in enumerate(["PaymentGatewayTimeout", "PaymentGatewayTimeout", "DatabaseConnectionError"])]
    payload = {"messageType": "DATA_MESSAGE", "logGroup": "/aws/lambda/x", "logStream": "s",
               "logEvents": [{"id": str(i), "timestamp": 0, "message": json.dumps(e)} for i, e in enumerate(errors)]}
    result = processor.lambda_handler(encode(payload), None)
    assert result["error_count"] == 3
    assert result["by_type"] == {"PaymentGatewayTimeout": 2, "DatabaseConnectionError": 1}
    assert result["sample_request_ids"] == ["r0", "r1", "r2"]
    assert json.loads(capsys.readouterr().out)["event"] == "errors_received"


def test_processor_handles_non_json_messages():
    payload = {"logEvents": [{"id": "1", "timestamp": 0, "message": "plain text error"}]}
    assert processor.lambda_handler(encode(payload), None)["by_type"] == {"Unparsed": 1}


def test_processor_ignores_control_message():
    assert processor.lambda_handler(encode({"messageType": "CONTROL_MESSAGE"}), None) == {"error_count": 0}
