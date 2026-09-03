#!/usr/bin/env python3
"""Serve the local dashboard and proxy its bounded control-plane routes.

The proxy keeps the static page same-origin with a local control plane. It
    forwards only the shared discovery, human-session, public onboarding, and
    bounded customer/platform routes. It never logs request headers, follows
upstream redirects, or exposes the control-plane origin to arbitrary browser
requests.
"""

from __future__ import annotations

import argparse
import functools
import ipaddress
import json
import re
import urllib.error
import urllib.parse
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


MAX_RESPONSE_BYTES = 1024 * 1024
MAX_REQUEST_BYTES = 64 * 1024
DISCOVERY_PATH = "/.well-known/hyfens"
OVERVIEW_PATH = re.compile(r"^/v1/organizations/[a-z][a-z0-9_]{1,63}/overview$")
PLATFORM_ORGANIZATIONS_PATH = re.compile(
    r"^/v1/platform/organizations(?:/[^/]+)?$"
)
ORGANIZATION_METADATA_PATH = re.compile(
    r"^/v1/organizations/[^/]+/(?:members|credentials)$"
)
ORGANIZATION_CREDENTIAL_ISSUE_PATH = re.compile(
    r"^/v1/organizations/[^/]+/credentials$"
)
ORGANIZATION_CREDENTIAL_REVOKE_PATH = re.compile(
    r"^/v1/organizations/[^/]+/credentials/[^/]+/revoke$"
)
APPLICATION_CREATE_PATH = re.compile(
    r"^/v1/organizations/[^/]+/applications$"
)
ENVIRONMENT_CREATE_PATH = re.compile(
    r"^/v1/organizations/[^/]+/applications/[^/]+/environments$"
)
ENVIRONMENT_PROMOTE_PATH = re.compile(
    r"^/v1/organizations/[^/]+/environments/[^/]+/release-promotions$"
)
PLATFORM_VIEW_PATH = re.compile(r"^/platform/organizations/[^/]+$")
PLATFORM_HOST_ORGANIZATION_PATH = re.compile(r"^/organizations/[^/]+$")
PLATFORM_HOSTNAMES = {"admin.hyfens.com", "platform.hyfens.com"}
PLATFORM_HOST_VIEW_PATHS = {
    "/",
    "/organizations",
    "/audit",
    "/operations",
    "/users",
    "/entitlements",
    "/settings",
}
DASHBOARD_VIEW_PATHS = {
    "/",
    "/overview",
    "/applications",
    "/environments",
    "/releases",
    "/patches",
    "/artifacts",
    "/deployments",
    "/audit",
    "/settings",
    "/platform",
    "/platform/organizations",
    "/platform/audit",
    "/platform/operations",
    "/platform/users",
    "/platform/entitlements",
    "/platform/settings",
}


_PROXY_ROUTES = {
    ("GET", DISCOVERY_PATH): "discovery",
    ("GET", "/auth/authorize"): "auth-authorize-get",
    ("POST", "/auth/login"): "auth-login",
    ("POST", "/auth/refresh"): "auth-refresh",
    ("POST", "/auth/logout"): "auth-logout",
    ("POST", "/auth/authorize"): "auth-authorize-post",
    ("POST", "/auth/token"): "auth-token",
    ("POST", "/auth/device/code"): "auth-device-code",
    ("POST", "/auth/device/token"): "auth-device-token",
    ("POST", "/auth/device/approve"): "auth-device-approve",
    ("POST", "/v1/public/register"): "public-register",
    ("POST", "/v1/public/waitlist"): "public-waitlist",
    ("POST", "/v1/public/newsletter"): "public-newsletter",
    ("GET", "/auth/me"): "auth-me",
    ("GET", "/v1/platform/metrics"): "platform-metrics",
    ("GET", "/v1/platform/organizations"): "platform-organizations",
    ("GET", "/v1/platform/audit"): "platform-audit",
    ("GET", "/v1/platform/users"): "platform-users",
    ("GET", "/v1/platform/entitlements"): "platform-entitlements",
}

_AUTHORIZATION_QUERY_KEYS = {
    "client_id",
    "redirect_uri",
    "response_type",
    "code_challenge",
    "code_challenge_method",
    "state",
}


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, msg, headers, new_url):
        return None


def _origin(value: str) -> str:
    try:
        parsed = urllib.parse.urlparse(value)
        host = parsed.hostname
        parsed.port
    except ValueError as error:
        raise ValueError(
            "api-origin must be an HTTP(S) loopback origin without credentials or a path"
        ) from error
    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.netloc
        or host is None
        or not _is_loopback(host)
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or parsed.path not in {"", "/"}
    ):
        raise ValueError(
            "api-origin must be an HTTP(S) loopback origin without credentials or a path"
        )
    return f"{parsed.scheme}://{parsed.netloc}"


def _is_loopback(value: str) -> bool:
    try:
        return ipaddress.ip_address(value).is_loopback
    except ValueError:
        return False


def _loopback_bind(value: str) -> str:
    if not _is_loopback(value):
        raise ValueError("bind must be a loopback IP address")
    return value


class DashboardHandler(SimpleHTTPRequestHandler):
    server_version = "HyfensLocalDashboard/1"

    def do_GET(self) -> None:
        if self._proxy_route() is not None:
            self._proxy_request()
            return
        path = urllib.parse.urlparse(self.path).path
        if (
            path in DASHBOARD_VIEW_PATHS
            or PLATFORM_VIEW_PATH.fullmatch(path)
            or self._is_platform_host_view(path)
        ):
            self.path = "/"
        super().do_GET()

    def _is_platform_host_view(self, path: str) -> bool:
        try:
            hostname = urllib.parse.urlsplit(
                f"//{self.headers.get('Host', '')}"
            ).hostname
        except ValueError:
            return False
        if hostname is None or hostname.lower() not in PLATFORM_HOSTNAMES:
            return False
        return path in PLATFORM_HOST_VIEW_PATHS or bool(
            PLATFORM_HOST_ORGANIZATION_PATH.fullmatch(path)
        )

    def do_POST(self) -> None:
        if self._proxy_route() is not None:
            self._proxy_request()
            return
        self.send_error(405, "Only the bounded dashboard POST routes are supported")

    def do_PUT(self) -> None:
        self.send_error(405, "Only GET is supported")

    def do_DELETE(self) -> None:
        self.send_error(405, "Only GET is supported")

    def _proxy_route(self) -> str | None:
        parsed = urllib.parse.urlparse(self.path)
        direct = _PROXY_ROUTES.get((self.command, parsed.path))
        if direct is not None:
            return direct
        if self.command == "GET" and OVERVIEW_PATH.fullmatch(parsed.path):
            return "overview"
        if self.command == "GET" and PLATFORM_ORGANIZATIONS_PATH.fullmatch(parsed.path):
            return (
                "platform-organizations"
                if parsed.path.endswith("/organizations")
                else "platform-organization"
            )
        if self.command == "GET" and parsed.path == "/v1/platform/audit":
            return "platform-audit"
        if self.command == "GET" and ORGANIZATION_METADATA_PATH.fullmatch(parsed.path):
            return "organization-metadata"
        if self.command == "POST" and ORGANIZATION_CREDENTIAL_ISSUE_PATH.fullmatch(
            parsed.path
        ):
            return "credential-issue"
        if self.command == "POST" and APPLICATION_CREATE_PATH.fullmatch(parsed.path):
            return "application-create"
        if self.command == "POST" and ORGANIZATION_CREDENTIAL_REVOKE_PATH.fullmatch(
            parsed.path
        ):
            return "credential-revoke"
        if self.command == "POST" and ENVIRONMENT_CREATE_PATH.fullmatch(parsed.path):
            return "environment-create"
        if self.command == "POST" and ENVIRONMENT_PROMOTE_PATH.fullmatch(parsed.path):
            return "environment-promote"
        return None

    def _proxy_request(self) -> None:
        route = self._proxy_route()
        if route is None:
            self.send_error(404, "Route is not available")
            return

        parsed = urllib.parse.urlparse(self.path)
        if parsed.query and not (
            (
                route == "auth-authorize-get"
                and self._authorization_query_is_safe(parsed.query)
            )
            or route in {
                "platform-metrics",
                "platform-organizations",
                "platform-organization",
                "platform-audit",
                "platform-users",
                "platform-entitlements",
            }
            and self._platform_query_is_safe(route, parsed.query)
        ):
            self._json_error(400, "Query parameters are not supported on this route")
            return
        authorization = self.headers.get("Authorization")
        if route in {
            "auth-me",
            "overview",
            "platform-metrics",
            "platform-organizations",
            "platform-organization",
            "platform-audit",
            "organization-metadata",
            "application-create",
            "credential-issue",
            "credential-revoke",
            "environment-create",
            "environment-promote",
            "auth-authorize-post",
            "auth-device-approve",
        }:
            if not authorization or not authorization.startswith("Bearer "):
                self._json_error(401, "Bearer credential is required")
                return

        body = None
        if self.command == "POST":
            body = self._request_body()
            if body is None:
                return

        target = f"{self.server.api_origin}{parsed.path}"
        if parsed.query and route in {
            "auth-authorize-get",
            "platform-metrics",
            "platform-organizations",
            "platform-organization",
            "platform-audit",
            "platform-users",
            "platform-entitlements",
        }:
            target += f"?{parsed.query}"
        headers = {"Accept": "application/json"}
        if authorization and route in {
            "auth-me",
            "overview",
            "platform-metrics",
            "platform-organizations",
            "platform-organization",
            "platform-audit",
            "organization-metadata",
            "application-create",
            "platform-users",
            "platform-entitlements",
            "credential-issue",
            "credential-revoke",
            "environment-create",
            "environment-promote",
            "auth-authorize-post",
            "auth-device-approve",
        }:
            headers["Authorization"] = authorization
        if body is not None:
            headers["Content-Type"] = self.headers.get(
                "Content-Type", "application/json"
            )
        for header in ("Idempotency-Key", "If-Match"):
            value = self.headers.get(header)
            if value:
                headers[header] = value
        request = urllib.request.Request(
            target,
            headers=headers,
            data=body,
            method=self.command,
        )
        try:
            with self.server.api_opener.open(request, timeout=15) as response:
                response_body = response.read(MAX_RESPONSE_BYTES + 1)
                if len(response_body) > MAX_RESPONSE_BYTES:
                    self._json_error(
                        502, "Control-plane response exceeds the local proxy limit"
                    )
                    return
                self.send_response(response.status)
                self.send_header(
                    "Content-Type",
                    response.headers.get("Content-Type", "application/json"),
                )
                self.send_header("Content-Length", str(len(response_body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(response_body)
        except urllib.error.HTTPError as error:
            try:
                response_body = error.read(MAX_RESPONSE_BYTES + 1)
            finally:
                error.close()
            if len(response_body) > MAX_RESPONSE_BYTES:
                self._json_error(502, "Control-plane error exceeds the local proxy limit")
                return
            self.send_response(error.code)
            self.send_header(
                "Content-Type",
                error.headers.get("Content-Type", "application/json"),
            )
            self.send_header("Content-Length", str(len(response_body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(response_body)
        except (TimeoutError, urllib.error.URLError):
            self._json_error(502, "Local control plane is unavailable")

    @staticmethod
    def _authorization_query_is_safe(query: str) -> bool:
        try:
            values = urllib.parse.parse_qs(query, keep_blank_values=True)
        except ValueError:
            return False
        if set(values) != _AUTHORIZATION_QUERY_KEYS:
            return False
        return all(len(items) == 1 and items[0] for items in values.values())

    @staticmethod
    def _platform_query_is_safe(route: str, query: str) -> bool:
        try:
            values = urllib.parse.parse_qs(query, keep_blank_values=True)
        except ValueError:
            return False
        allowed = {
            "platform-metrics": {"profile"},
            "platform-organizations": {"profile", "q"},
            "platform-organization": {"profile"},
            "platform-audit": {"profile", "organization_id"},
            "platform-users": {"profile"},
            "platform-entitlements": {"profile"},
        }.get(route, set())
        if not set(values).issubset(allowed):
            return False
        return all(len(items) == 1 for items in values.values()) and all(
            bool(items[0]) for items in values.values()
        )

    def _request_body(self) -> bytes | None:
        raw_length = self.headers.get("Content-Length")
        if raw_length is None:
            self._json_error(411, "Content-Length is required")
            return None
        try:
            length = int(raw_length)
        except ValueError:
            self._json_error(400, "Content-Length is invalid")
            return None
        if length < 0 or length > MAX_REQUEST_BYTES:
            self._json_error(413, "Request body exceeds the local proxy limit")
            return None
        body = self.rfile.read(length)
        if len(body) != length:
            self._json_error(400, "Request body is incomplete")
            return None
        return body

    def _json_error(self, status: int, message: str) -> None:
        body = json.dumps({"error": message}).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        # Never log request headers: they may contain the control credential.
        message = format % args
        message = re.sub(r"(\s/[^\s?]*)\?[^\s]*", r"\1?[redacted]", message)
        super().log_message("%s", message)


class DashboardServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], api_origin: str, directory: Path):
        bind = _loopback_bind(address[0])
        origin = _origin(api_origin)
        handler = functools.partial(DashboardHandler, directory=str(directory))
        super().__init__((bind, address[1]), handler)
        self.api_origin = origin
        self.api_opener = urllib.request.build_opener(_NoRedirect())


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve the local Hyfens operator page")
    parser.add_argument("--api-origin", default="http://127.0.0.1:18081")
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    try:
        api_origin = _origin(args.api_origin)
        bind = _loopback_bind(args.bind)
    except ValueError as error:
        parser.error(str(error))
    directory = Path(__file__).resolve().parent
    server = DashboardServer((bind, args.port), api_origin, directory)
    print(f"Hyfens local dashboard listening on http://{bind}:{args.port}/")
    print(f"Proxying the read-only overview route to {api_origin}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
