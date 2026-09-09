#!/usr/bin/env python3
"""Run a bounded, non-mutating hosted-like control-plane load sample.

The script intentionally measures only authenticated update lookup and artifact
fetch. It does not create tenants, promote releases, or emit runtime
telemetry. The delivery token is read from HYFENS_LOAD_TOKEN and is never
printed.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import time
import urllib.error
import urllib.request
from typing import Any


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--application-id", required=True)
    parser.add_argument("--environment-id", required=True)
    parser.add_argument("--runtime-application-id", required=True)
    parser.add_argument("--runtime-release-id", required=True)
    parser.add_argument("--artifact-id", required=True)
    parser.add_argument("--requests", type=int, default=40)
    parser.add_argument("--concurrency", type=int, default=8)
    args = parser.parse_args()
    token = os.environ.get("HYFENS_LOAD_TOKEN", "")
    if not token or any(char in token for char in "\r\n"):
        parser.error("HYFENS_LOAD_TOKEN must contain the delivery credential")
    if args.requests <= 0 or args.requests > 1000:
        parser.error("--requests must be between 1 and 1000")
    if args.concurrency <= 0 or args.concurrency > args.requests:
        parser.error("--concurrency must be between 1 and --requests")
    endpoint = args.endpoint.rstrip("/")

    operations = {
        "update-check": lambda: _update_check(endpoint, token, args),
        "artifact-fetch": lambda: _artifact_fetch(endpoint, token, args),
    }
    samples: dict[str, list[float]] = {name: [] for name in operations}
    errors: dict[str, list[str]] = {name: [] for name in operations}
    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(
        max_workers=args.concurrency
    ) as executor:
        futures = []
        for index in range(args.requests):
            name, operation = list(operations.items())[index % len(operations)]
            futures.append((name, executor.submit(operation)))
        for name, future in futures:
            try:
                duration_ms, status = future.result()
                samples[name].append(duration_ms)
                if status < 200 or status >= 300:
                    errors[name].append(f"HTTP {status}")
            except Exception as error:  # noqa: BLE001 - report bounded sample faults
                errors[name].append(type(error).__name__)

    result: dict[str, Any] = {
        "label": "LOAD_TEST",
        "requests": args.requests,
        "concurrency": args.concurrency,
        "elapsedMs": round((time.perf_counter() - started) * 1000, 3),
        "operations": {},
    }
    for name in operations:
        durations = samples[name]
        result["operations"][name] = {
            "samples": len(durations),
            "errors": len(errors[name]),
            "p50Ms": _percentile(durations, 50),
            "p95Ms": _percentile(durations, 95),
            "p99Ms": _percentile(durations, 99),
            "errorKinds": sorted(set(errors[name])),
        }
    print(json.dumps(result, sort_keys=True))
    return 0 if all(not faults for faults in errors.values()) else 1


def _update_check(endpoint: str, token: str, args: argparse.Namespace) -> tuple[float, int]:
    body = {
        "application_id": args.application_id,
        "environment_id": args.environment_id,
        "runtime_application_id": args.runtime_application_id,
        "runtime_release_id": args.runtime_release_id,
        "runtime_compatibility_version": 1,
        "patch_format_version": 1,
        "high_water_sequence": 0,
    }
    return _request(
        urllib.request.Request(
            f"{endpoint}/v1/runtime/update-check",
            data=json.dumps(body).encode("utf-8"),
            method="POST",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
                "X-Request-Id": "p2-load-update",
            },
        )
    )


def _artifact_fetch(endpoint: str, token: str, args: argparse.Namespace) -> tuple[float, int]:
    url = (
        f"{endpoint}/v1/runtime/artifacts/{args.artifact_id}"
        f"?application_id={args.application_id}"
        f"&environment_id={args.environment_id}"
    )
    return _request(
        urllib.request.Request(
            url,
            method="GET",
            headers={
                "Authorization": f"Bearer {token}",
                "X-Request-Id": "p2-load-artifact",
            },
        )
    )


def _request(request: urllib.request.Request) -> tuple[float, int]:
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            response.read()
            return (time.perf_counter() - started) * 1000, response.status
    except urllib.error.HTTPError as error:
        error.read()
        return (time.perf_counter() - started) * 1000, error.code


def _percentile(values: list[float], percentile: int) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    rank = (len(ordered) - 1) * percentile / 100
    lower = int(rank)
    upper = min(lower + 1, len(ordered) - 1)
    if lower == upper:
        return round(ordered[lower], 3)
    fraction = rank - lower
    return round(ordered[lower] + (ordered[upper] - ordered[lower]) * fraction, 3)


if __name__ == "__main__":
    raise SystemExit(main())
