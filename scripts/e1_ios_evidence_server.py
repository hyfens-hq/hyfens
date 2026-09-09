#!/usr/bin/env python3
"""Bounded local transport for the physical iOS E1 evidence run."""

import argparse
import json
import threading
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_RECEIPT_BYTES = 64 * 1024


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--serve-dir", required=True, type=Path)
    parser.add_argument("--receipts", required=True, type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--token", required=True)
    args = parser.parse_args()
    if len(args.token) != 64 or any(
        character not in "0123456789abcdef" for character in args.token
    ):
        raise SystemExit("invalid evidence bearer token")
    serve_dir = args.serve_dir.resolve(strict=True)
    artifact_files = [
        *serve_dir.glob("*.e1.signed.json"),
        *serve_dir.glob("*.v1.patch"),
    ]
    artifacts = {
        f"/{args.token}/{artifact.name}": artifact
        for artifact in artifact_files
    }
    required_names = (
        ("multi-1.v1.patch", "multi-invalid.v1.patch")
        if any(artifact.name.endswith(".v1.patch") for artifact in artifact_files)
        else ("patch.e1.signed.json", "invalid-signature.e1.signed.json")
    )
    for required in required_names:
        if f"/{args.token}/{required}" not in artifacts:
            raise SystemExit(f"missing evidence artifact: {serve_dir / required}")
    for artifact in artifacts.values():
        if not artifact.is_file():
            raise SystemExit(f"missing evidence artifact: {artifact}")
    args.receipts.parent.mkdir(parents=True, exist_ok=True)
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        server_version = "HyfensE1Evidence/1"

        def do_GET(self):  # noqa: N802
            if self.path == f"/{args.token}/health":
                self.send_response(HTTPStatus.NO_CONTENT)
                self.end_headers()
                return
            artifact = artifacts.get(self.path)
            if artifact is None:
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            body = artifact.read_bytes()
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):  # noqa: N802
            if self.path != f"/{args.token}/evidence":
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            try:
                length = int(self.headers.get("Content-Length", "-1"))
            except ValueError:
                length = -1
            if length < 2 or length > MAX_RECEIPT_BYTES:
                self.send_error(HTTPStatus.REQUEST_ENTITY_TOO_LARGE)
                return
            try:
                receipt = json.loads(self.rfile.read(length))
            except (UnicodeDecodeError, json.JSONDecodeError):
                self.send_error(HTTPStatus.BAD_REQUEST)
                return
            if (
                not isinstance(receipt, dict)
                or receipt.get("runId") != args.run_id
                or not isinstance(receipt.get("stage"), str)
                or not isinstance(receipt.get("processId"), int)
            ):
                self.send_error(HTTPStatus.BAD_REQUEST)
                return
            receipt["receivedAtUtc"] = datetime.now(timezone.utc).isoformat()
            line = json.dumps(receipt, sort_keys=True, separators=(",", ":"))
            with lock, args.receipts.open("a", encoding="utf-8") as output:
                output.write(f"{line}\n")
                output.flush()
            self.send_response(HTTPStatus.NO_CONTENT)
            self.end_headers()

        def log_message(self, format, *values):
            print(f"{self.address_string()} {format % values}", flush=True)

    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"listening=http://{args.bind}:{args.port} runId={args.run_id}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
