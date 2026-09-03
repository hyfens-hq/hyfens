import http.client
import json
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from dashboard.serve import DashboardServer, _loopback_bind, _origin


class _UpstreamHandler(BaseHTTPRequestHandler):
    calls = []

    def do_GET(self):
        self.__class__.calls.append(
            (self.command, self.path, self.headers.get("Authorization"), b"")
        )
        if self.path == "/.well-known/hyfens":
            self._json(200, {"product": "hyfens", "apiVersion": "v1"})
            return
        parsed_path = urllib.parse.urlparse(self.path).path
        if parsed_path in {"/v1/platform/metrics", "/v1/platform/commercial"}:
            self._json(200, {"readOnly": True, "scope": "platform"})
            return
        if parsed_path.startswith(
            "/v1/platform/organizations"
        ) or parsed_path == "/v1/platform/audit" or parsed_path.startswith(
            "/v1/platform/support/cases"
        ):
            self._json(200, {"readOnly": True, "scope": "platform"})
            return
        if self.path.startswith("/v1/organizations/"):
            self._json(200, {"readOnly": True, "source": "upstream"})
            return
        if urllib.parse.urlparse(self.path).path == "/auth/authorize":
            self._json(200, {"status": "authorization_required", "authorization_request_id": "areq_demo"})
            return
        self._json(404, {"error": {"code": "NOT_FOUND"}})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        self.__class__.calls.append(
            (self.command, self.path, self.headers.get("Authorization"), body)
        )
        if self.path in {"/auth/login", "/auth/refresh", "/auth/logout"}:
            self._json(200, {"status": "accepted"})
            return
        if self.path == "/auth/authorize":
            self._json(200, {"code": "hfc_demo", "state": "state_demo", "redirect_uri": "http://127.0.0.1:43127/callback"})
            return
        parsed_path = urllib.parse.urlparse(self.path).path
        if self.path in {"/v1/public/register", "/v1/public/waitlist", "/v1/public/newsletter"}:
            self._json(200, {"status": "accepted", "request_id": "request_demo"})
            return
        if parsed_path.startswith("/v1/organizations/") and (
            "/support/cases" in parsed_path or parsed_path.endswith("/invitations")
        ):
            self._json(200, {"readOnly": False, "scope": "customer"})
            return
        if parsed_path.startswith("/v1/platform/support/cases/"):
            self._json(200, {"readOnly": False, "scope": "platform"})
            return
        if self.path in {"/auth/token", "/auth/device/code", "/auth/device/token", "/auth/device/approve"}:
            self._json(200, {"status": "accepted"})
            return
        self._json(404, {"error": {"code": "NOT_FOUND"}})

    def do_PATCH(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        self.__class__.calls.append(
            (self.command, self.path, self.headers.get("Authorization"), body)
        )
        if urllib.parse.urlparse(self.path).path.startswith("/v1/platform/support/cases/"):
            self._json(200, {"readOnly": False, "scope": "platform"})
            return
        self._json(404, {"error": {"code": "NOT_FOUND"}})

    def _json(self, status, value):
        body = json.dumps(value).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


class ServeValidationTest(unittest.TestCase):
    def test_origin_accepts_loopback_ip_literal(self):
        self.assertEqual(_origin("http://127.0.0.1:18081/"), "http://127.0.0.1:18081")
        self.assertEqual(_origin("https://[::1]:18443"), "https://[::1]:18443")

    def test_origin_rejects_non_loopback_or_ambiguous_hosts(self):
        for value in (
            "http://0.0.0.0:18081",
            "http://198.51.100.10:18081",
            "http://localhost:18081",
            "http://user:password@127.0.0.1:18081",
            "http://127.0.0.1:18081/api",
        ):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    _origin(value)

    def test_bind_accepts_only_loopback_ip_literals(self):
        self.assertEqual(_loopback_bind("127.0.0.1"), "127.0.0.1")
        self.assertEqual(_loopback_bind("::1"), "::1")
        for value in ("0.0.0.0", "198.51.100.10", "localhost"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    _loopback_bind(value)

    def test_server_rejects_non_loopback_bind_and_api_origin(self):
        with self.assertRaises(ValueError):
            DashboardServer(
                ("0.0.0.0", 0),
                "http://127.0.0.1:18081",
                Path("."),
            )
        with self.assertRaises(ValueError):
            DashboardServer(
                ("127.0.0.1", 0),
                "http://198.51.100.10:18081",
                Path("."),
            )


class ProxyRouteTest(unittest.TestCase):
    def setUp(self):
        _UpstreamHandler.calls = []
        self.upstream = ThreadingHTTPServer(("127.0.0.1", 0), _UpstreamHandler)
        self.upstream_thread = threading.Thread(
            target=self.upstream.serve_forever,
            daemon=True,
        )
        self.upstream_thread.start()
        self.dashboard = DashboardServer(
            ("127.0.0.1", 0),
            f"http://127.0.0.1:{self.upstream.server_port}",
            Path(__file__).resolve().parent,
        )
        self.dashboard_thread = threading.Thread(
            target=self.dashboard.serve_forever,
            daemon=True,
        )
        self.dashboard_thread.start()

    def tearDown(self):
        self.dashboard.shutdown()
        self.dashboard.server_close()
        self.dashboard_thread.join(timeout=2)
        self.upstream.shutdown()
        self.upstream.server_close()
        self.upstream_thread.join(timeout=2)

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.dashboard.server_port)
        encoded = None if body is None else json.dumps(body).encode("utf-8")
        request_headers = {"Accept": "application/json", **(headers or {})}
        if encoded is not None:
            request_headers["Content-Type"] = "application/json"
            request_headers["Content-Length"] = str(len(encoded))
        connection.request(method, path, body=encoded, headers=request_headers)
        response = connection.getresponse()
        payload = response.read()
        connection.close()
        return response.status, payload

    def test_proxy_forwards_known_auth_discovery_and_overview_routes(self):
        status, body = self.request("GET", "/.well-known/hyfens")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["product"], "hyfens")

        status, _ = self.request(
            "POST",
            "/auth/login",
            {"email": "operator@example.com", "password": "not-in-url"},
        )
        self.assertEqual(status, 200)

        status, _ = self.request(
            "GET",
            "/auth/me",
            headers={"Authorization": "Bearer memory-access"},
        )
        self.assertEqual(status, 404)

        status, body = self.request(
            "GET",
            "/v1/organizations/org_demo/overview",
            headers={"Authorization": "Bearer memory-access"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["readOnly"], True)

        self.assertEqual(
            [(method, path) for method, path, _, _ in _UpstreamHandler.calls],
            [
                ("GET", "/.well-known/hyfens"),
                ("POST", "/auth/login"),
                ("GET", "/auth/me"),
                ("GET", "/v1/organizations/org_demo/overview"),
            ],
        )
        self.assertEqual(_UpstreamHandler.calls[2][2], "Bearer memory-access")
        self.assertNotIn(b"not-in-url", body)

    def test_platform_metrics_proxy_requires_auth_and_allows_only_profile_query(self):
        status, _ = self.request("GET", "/v1/platform/metrics")
        self.assertEqual(status, 401)
        self.assertEqual(_UpstreamHandler.calls, [])

        status, body = self.request(
            "GET",
            "/v1/platform/metrics",
            headers={"Authorization": "Bearer memory-access"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["scope"], "platform")

        status, _ = self.request(
            "GET",
            "/v1/platform/metrics?profile=super-admin",
            headers={"Authorization": "Bearer memory-access"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(
            _UpstreamHandler.calls[-1][0:3],
            ("GET", "/v1/platform/metrics?profile=super-admin", "Bearer memory-access"),
        )

        status, _ = self.request(
            "GET",
            "/v1/platform/metrics?organization_id=secret",
            headers={"Authorization": "Bearer memory-access"},
        )
        self.assertEqual(status, 400)
        self.assertEqual(len(_UpstreamHandler.calls), 2)

    def test_platform_projection_proxy_forwards_bounded_queries(self):
        headers = {"Authorization": "Bearer memory-access"}
        requests = (
            "/v1/platform/organizations?profile=super-admin&q=acme",
            "/v1/platform/organizations/org_demo?profile=super-admin",
            "/v1/platform/audit?profile=super-admin&organization_id=org_demo",
        )
        for path in requests:
            with self.subTest(path=path):
                status, body = self.request("GET", path, headers=headers)
                self.assertEqual(status, 200)
                self.assertEqual(json.loads(body)["scope"], "platform")

        self.assertEqual(
            [call[1] for call in _UpstreamHandler.calls],
            list(requests),
        )
        status, _ = self.request(
            "GET",
            "/v1/platform/organizations?profile=super-admin&token=secret",
            headers=headers,
        )
        self.assertEqual(status, 400)
        self.assertEqual(len(_UpstreamHandler.calls), len(requests))

    def test_proxy_forwards_browser_and_device_auth_routes_without_query_secrets(self):
        query = urllib.parse.urlencode(
            {
                "client_id": "hyfens-cli",
                "redirect_uri": "http://127.0.0.1:43127/callback",
                "response_type": "code",
                "code_challenge": "challenge",
                "code_challenge_method": "S256",
                "state": "state_demo",
            }
        )
        status, _ = self.request("GET", f"/auth/authorize?{query}")
        self.assertEqual(status, 200)
        status, _ = self.request(
            "POST",
            "/auth/authorize",
            {"request_id": "areq_demo"},
            headers={"Authorization": "Bearer memory-access"},
        )
        self.assertEqual(status, 200)
        status, _ = self.request(
            "POST",
            "/auth/device/approve",
            {"user_code": "ABCD-EFGH"},
            headers={"Authorization": "Bearer memory-access"},
        )
        self.assertEqual(status, 200)
        self.assertIn(
            ("GET", f"/auth/authorize?{query}"),
            [(method, path) for method, path, _, _ in _UpstreamHandler.calls],
        )
        self.assertEqual(_UpstreamHandler.calls[-1][2], "Bearer memory-access")

    def test_proxy_forwards_fixed_public_onboarding_routes_without_auth(self):
        routes = (
            ("/v1/public/register", {"email": "new@example.com", "password": "not-in-url"}),
            ("/v1/public/waitlist", {"email": "visitor@example.com", "name": "Visitor", "source": "referral"}),
            ("/v1/public/newsletter", {"email": "reader@example.com"}),
        )
        for path, body in routes:
            with self.subTest(path=path):
                status, response_body = self.request("POST", path, body)
                self.assertEqual(status, 200)
                self.assertEqual(json.loads(response_body)["status"], "accepted")

        self.assertEqual(
            [(method, path) for method, path, _, _ in _UpstreamHandler.calls],
            [("POST", path) for path, _ in routes],
        )
        self.assertEqual(
            [body for _, _, _, body in _UpstreamHandler.calls],
            [json.dumps(body).encode("utf-8") for _, body in routes],
        )
        self.assertEqual([authorization for _, _, authorization, _ in _UpstreamHandler.calls], [None, None, None])

    def test_public_onboarding_routes_reject_query_data_and_unknown_paths(self):
        status, _ = self.request("POST", "/v1/public/waitlist?email=secret@example.com", {"email": "visitor@example.com"})
        self.assertEqual(status, 400)
        self.assertEqual(_UpstreamHandler.calls, [])

        status, _ = self.request("POST", "/v1/public/unknown", {"email": "visitor@example.com"})
        self.assertEqual(status, 405)
        self.assertEqual(_UpstreamHandler.calls, [])

    def test_auth_pages_are_served_as_static_same_origin_routes(self):
        for path in ("/cli/authorize/", "/device/"):
            status, body = self.request("GET", path)
            self.assertEqual(status, 200)
            self.assertIn(b"HyfensAuthFlow", body)

    def test_proxy_forwards_support_and_commercial_routes_with_bounded_queries(self):
        headers = {"Authorization": "Bearer memory-access"}
        requests = (
            ("GET", "/v1/platform/commercial?profile=super-admin"),
            ("GET", "/v1/platform/support/cases?profile=super-admin&status=OPEN"),
            ("GET", "/v1/organizations/org_demo/support/cases"),
            ("GET", "/v1/organizations/org_demo/invitations"),
            ("POST", "/v1/organizations/org_demo/invitations"),
            ("POST", "/v1/organizations/org_demo/support/cases"),
            ("PATCH", "/v1/platform/support/cases/case_demo?profile=super-admin"),
            ("POST", "/v1/platform/support/cases/case_demo/messages?profile=super-admin"),
        )
        for method, path in requests:
            with self.subTest(method=method, path=path):
                if method == "PATCH":
                    body = {"status": "IN_PROGRESS"}
                elif method == "POST" and "/organizations/" in path:
                    body = {"subject": "Help", "description": "A question"}
                elif method == "POST":
                    body = {"body": "Reply"}
                else:
                    body = None
                status, _ = self.request(method, path, body, headers=headers)
                self.assertEqual(status, 200)
        self.assertEqual(
            [(call[0], call[1]) for call in _UpstreamHandler.calls],
            list(requests),
        )

        status, _ = self.request(
            "PATCH",
            "/v1/platform/support/cases/case_demo?profile=super-admin&token=secret",
            {"status": "OPEN"},
            headers=headers,
        )
        self.assertEqual(status, 400)
        self.assertEqual(len(_UpstreamHandler.calls), len(requests))

    def test_auth_pages_load_runtime_config_before_auth_flow(self):
        pages = (
            (
                "/cli/authorize/",
                b'<script src="../../runtime-config.js"></script>',
                b'<script src="../../auth-flow.js"></script>',
            ),
            (
                "/device/",
                b'<script src="../runtime-config.js"></script>',
                b'<script src="../auth-flow.js"></script>',
            ),
        )
        for path, runtime_config, auth_flow in pages:
            with self.subTest(path=path):
                status, body = self.request("GET", path)
                self.assertEqual(status, 200)
                runtime_index = body.find(runtime_config)
                auth_index = body.find(auth_flow)
                self.assertGreaterEqual(runtime_index, 0)
                self.assertGreaterEqual(auth_index, 0)
                self.assertLess(runtime_index, auth_index)

    def test_clean_dashboard_view_paths_serve_the_index(self):
        for path in (
            "/",
            "/overview",
            "/applications",
            "/platform",
            "/platform/organizations",
            "/platform/organizations/org_demo",
            "/platform/audit",
            "/platform/operations",
            "/platform/commercial",
            "/platform/support",
            "/platform/settings",
            "/support",
            "/settings",
        ):
            with self.subTest(path=path):
                status, body = self.request("GET", path)
                self.assertEqual(status, 200)
                self.assertIn(b"Hyfens | Developer control plane", body)
        self.assertEqual(_UpstreamHandler.calls, [])

    def test_platform_host_routes_serve_the_platform_shell_index(self):
        for path in (
            "/",
            "/organizations",
            "/organizations/org_demo",
            "/audit",
            "/commercial",
            "/support",
        ):
            with self.subTest(path=path):
                status, body = self.request(
                    "GET",
                    path,
                    headers={"Host": "admin.hyfens.com"},
                )
                self.assertEqual(status, 200)
                self.assertIn(b"Platform Console", body)
        self.assertEqual(_UpstreamHandler.calls, [])

    def test_protected_routes_require_bearer_and_query_data_is_rejected(self):
        status, _ = self.request("GET", "/v1/organizations/org_demo/overview")
        self.assertEqual(status, 401)
        self.assertEqual(_UpstreamHandler.calls, [])

        status, body = self.request(
            "GET",
            "/.well-known/hyfens?access_token=secret-value",
        )
        self.assertEqual(status, 400)
        self.assertNotIn(b"secret-value", body)
        self.assertEqual(_UpstreamHandler.calls, [])

    def test_unsupported_mutation_routes_are_not_forwarded(self):
        status, _ = self.request(
            "POST",
            "/v1/organizations/org_demo/overview",
            {},
        )
        self.assertEqual(status, 405)
        self.assertEqual(_UpstreamHandler.calls, [])


class DashboardContractTest(unittest.TestCase):
    def test_auth_forms_use_a_stable_interruptible_transition_stage(self):
        root = Path(__file__).resolve().parent
        markup = (root / "index.html").read_text(encoding="utf-8")
        styles = (root / "styles.css").read_text(encoding="utf-8")
        app_source = (root / "app.js").read_text(encoding="utf-8")

        self.assertIn('class="auth-form-stage"', markup)
        self.assertIn('data-auth-form-mode="login"', markup)
        self.assertIn('data-auth-form-mode="register"', markup)
        self.assertIn('aria-hidden="false"', markup)
        self.assertIn('aria-hidden="true"', markup)
        self.assertIn("inert", markup)
        self.assertIn(".auth-form-stage {", styles)
        stage_rule = styles.split(".auth-form-stage {", 1)[1].split("}", 1)[0]
        self.assertIn("display: grid;", stage_rule)
        self.assertIn(".auth-form-stage > .auth-form {", styles)
        transition_rule = styles.split(
            ".auth-form-stage > .auth-form {", 1
        )[1].split("}", 1)[0]
        self.assertIn("transition: opacity", transition_rule)
        self.assertIn("transform", transition_rule)
        self.assertIn("visibility", transition_rule)
        self.assertIn(".auth-form-stage > .auth-form[aria-hidden=\"true\"]", styles)
        self.assertIn("opacity: 0;", styles)
        self.assertIn("transform: translateY(8px);", styles)
        self.assertIn("prefers-reduced-motion: reduce", styles)
        self.assertIn("setAttribute('aria-hidden'", app_source)
        self.assertIn("form.inert", app_source)

    def test_auth_shell_uses_one_document_scroll_context_and_keeps_onboarding_out(self):
        root = Path(__file__).resolve().parent
        markup = (root / "index.html").read_text(encoding="utf-8")
        styles = (root / "styles.css").read_text(encoding="utf-8")
        app_source = (root / "app.js").read_text(encoding="utf-8")
        auth_layout_rule = styles.split(".auth-layout {", 1)[1].split("}", 1)[0]
        auth_panel_rule = styles.split(".auth-panel {", 1)[1].split("}", 1)[0]
        auth_rail_rule = styles.split(".auth-rail {", 1)[1].split("}", 1)[0]
        auth_focus_marker = ".auth-form input:focus,\n.auth-form input:focus-visible {"

        self.assertIn('href="styles.css?v=236"', markup)
        self.assertIn('src="app.js?v=231"', markup)
        self.assertIn("min-height: 100dvh;", auth_layout_rule)
        self.assertIn("overflow: visible;", auth_layout_rule)
        self.assertNotIn("\n  height: 100dvh;", auth_layout_rule)
        self.assertIn("width: 100%;", auth_panel_rule)
        self.assertIn("height: auto;", auth_panel_rule)
        self.assertIn("min-height: 100dvh;", auth_panel_rule)
        self.assertIn("overflow: clip;", auth_panel_rule)
        self.assertNotIn("overflow-y: auto;", auth_panel_rule)
        self.assertIn("height: auto;", auth_rail_rule)
        self.assertIn("min-height: 100dvh;", auth_rail_rule)
        self.assertIn("overflow: clip;", auth_rail_rule)
        self.assertNotIn("overflow-y: auto;", auth_rail_rule)
        self.assertIn(auth_focus_marker, styles)
        auth_focus_rule = styles.split(auth_focus_marker, 1)[1].split("}", 1)[0]
        self.assertNotIn("onboarding-intake", markup)
        self.assertNotIn("data-intake-kind", markup)
        self.assertNotIn("Join the waitlist", markup)
        self.assertNotIn("Get product updates", markup)
        self.assertNotIn("app.hyfens.com", markup)
        self.assertIn("nodes.intakeForm?.addEventListener", app_source)
        self.assertIn("if (nodes.intakeForm) showIntakeMode", app_source)
        self.assertNotIn("box-shadow", auth_focus_rule)
        self.assertIn("outline: none;", auth_focus_rule)
        self.assertIn("outline-offset: 0;", auth_focus_rule)

    def test_dashboard_assigns_ui_and_display_font_roles(self):
        root = Path(__file__).resolve().parent
        tokens = (root / "tokens.css").read_text(encoding="utf-8")
        styles = (root / "styles.css").read_text(encoding="utf-8")
        markup = (root / "index.html").read_text(encoding="utf-8")
        nav_rule = styles.split(".nav-group a {", 1)[1].split("}", 1)[0]
        button_rule = styles.split(".button {", 1)[1].split("}", 1)[0]

        self.assertIn("IBM+Plex+Sans", tokens)
        self.assertIn('--hyfens-font-ui: "IBM Plex Sans"', tokens)
        self.assertIn('--hyfens-font-display: "Bricolage Grotesque"', tokens)
        self.assertIn(
            "--hyfens-font-primary: var(--hyfens-font-ui);",
            tokens,
        )
        self.assertIn('href="tokens.css?v=222"', markup)
        self.assertIn('href="styles.css?v=236"', markup)
        self.assertIn('src="app.js?v=231"', markup)
        self.assertGreaterEqual(
            styles.count("font-family: var(--hyfens-font-display);"),
            2,
        )
        self.assertIn("font-weight: 500;", nav_rule)
        self.assertIn("font-weight: 600;", button_rule)
        self.assertNotIn("font-weight: 650;", styles)
        self.assertIn("strong,\nb {", styles)

    def test_collection_controls_use_hairline_states_and_wide_content(self):
        root = Path(__file__).resolve().parent
        styles = (root / "styles.css").read_text(encoding="utf-8")
        content_rule = styles.split(".content {", 1)[1].split("}", 1)[0]
        collection_field_rule = styles.split(
            ".collection-toolbar input,\n.collection-toolbar select {", 1
        )[1].split("}", 1)[0]
        collection_focus_rule = styles.split(
            ".collection-toolbar input:focus,\n.collection-toolbar input:focus-visible {",
            1,
        )[1].split("}", 1)[0]

        self.assertIn("width: min(100%, 1760px);", content_rule)
        self.assertIn("border: 0;", collection_field_rule)
        self.assertNotIn("box-shadow", collection_field_rule)
        self.assertIn("outline: none;", collection_focus_rule)
        self.assertNotIn("box-shadow", collection_focus_rule)

    def test_select_controls_are_borderless_with_keyboard_focus(self):
        root = Path(__file__).resolve().parent
        styles = (root / "styles.css").read_text(encoding="utf-8")
        field_rule = styles.split(
            ".auth-form input,\n.intake-form input,\n.context-controls select {",
            1,
        )[1].split("}", 1)[0]
        context_rule = styles.split(
            ".context-controls select {\n  min-height: 42px;", 1
        )[1].split("}", 1)[0]
        workspace_rule = styles.split(
            "#organization-context,\n.workspace-context-select select {", 1
        )[1].split("}", 1)[0]
        context_focus_marker = (
            ".context-controls select:focus,\n"
            ".context-controls select:focus-visible {"
        )
        workspace_focus_marker = (
            "#organization-context:focus,\n"
            ".workspace-context-select select:focus {"
        )
        collection_focus_marker = (
            ".collection-toolbar select:focus,\n"
            ".collection-toolbar select:focus-visible {"
        )

        self.assertNotIn("border:", field_rule)
        self.assertIn("border: 0;", context_rule)
        self.assertIn("border: 0;", workspace_rule)
        self.assertNotIn("border-color:", workspace_rule)
        for marker in (
            context_focus_marker,
            workspace_focus_marker,
            collection_focus_marker,
        ):
            with self.subTest(marker=marker):
                state_rule = styles.split(marker, 1)[1].split("}", 1)[0]
                self.assertNotIn("border:", state_rule)
                self.assertNotIn("border-color:", state_rule)
                self.assertNotIn("box-shadow", state_rule)

        self.assertIn("select:focus-visible,", styles)
        self.assertIn("outline: 2px solid var(--accent);", styles)

    def test_dashboard_shell_removes_redundant_details_and_uses_opaque_popover(self):
        root = Path(__file__).resolve().parent
        markup = (root / "index.html").read_text(encoding="utf-8")
        app_source = (root / "app.js").read_text(encoding="utf-8")
        styles = (root / "styles.css").read_text(encoding="utf-8")
        popover_rule = styles.split(".account-popover {", 1)[1].split("}", 1)[0]
        desktop_header_rule = styles.split("@media (min-width: 901px)", 1)[1] if "@media (min-width: 901px)" in styles else ""

        self.assertNotIn('class="user-profile-icon"', markup)
        self.assertNotIn('id="workspace-id"', markup)
        self.assertNotIn("workspaceId:", app_source)
        self.assertNotIn("nodes.workspaceId", app_source)
        self.assertIn("background: var(--bg);", popover_rule)
        self.assertIn(".sidebar-header", desktop_header_rule)
        self.assertIn("justify-content: center;", desktop_header_rule)

    def test_sidebar_context_surfaces_are_quiet_until_active(self):
        root = Path(__file__).resolve().parent
        styles = (root / "styles.css").read_text(encoding="utf-8")
        workspace_rule = styles.split(".workspace-context {", 1)[1].split("}", 1)[0]
        account_rule = styles.split(".sidebar-user-menu {", 1)[1].split("}", 1)[0]
        account_open_marker = ".account-menu[open] > .sidebar-user-menu {"
        account_focus_marker = ".account-menu > .sidebar-user-menu:focus-visible {"
        account_open_rule = styles.split(account_open_marker, 1)[1].split("}", 1)[0]
        account_focus_rule = styles.split(account_focus_marker, 1)[1].split("}", 1)[0]

        self.assertIn("border: 0;", workspace_rule)
        self.assertIn("background: transparent;", workspace_rule)
        self.assertNotIn(".workspace-context:has(.workspace-context-select)", styles)
        self.assertIn("border: 0;", account_rule)
        self.assertIn("background: transparent;", account_rule)
        self.assertIn("border: 0.5px solid var(--accent-line);", account_open_rule)
        self.assertIn("background: var(--accent-soft);", account_open_rule)
        self.assertIn("border: 0.5px solid var(--accent);", account_focus_rule)
        self.assertIn("background: var(--accent-soft);", account_focus_rule)
        self.assertIn("box-shadow: none;", account_focus_rule)

    def test_dashboard_navigation_uses_clean_history_routes(self):
        root = Path(__file__).resolve().parent
        markup = (root / "index.html").read_text(encoding="utf-8")
        app_source = (root / "app.js").read_text(encoding="utf-8")

        self.assertNotIn('href="#', markup)
        self.assertIn('href="/applications"', markup)
        self.assertIn('href="/settings"', markup)
        self.assertNotIn('data-intake-link', markup)
        self.assertIn("history.pushState", app_source)
        self.assertIn("history.replaceState", app_source)
        self.assertIn("addEventListener('popstate'", app_source)
        self.assertNotIn("window.location.hash =", app_source)
        self.assertIn("renderCurrentPage({ transition: true });", app_source)
        self.assertIn("data-page-transition", app_source)
        self.assertIn("requestAnimationFrame", app_source)

    def test_dashboard_has_explicit_customer_and_platform_shell_contracts(self):
        root = Path(__file__).resolve().parent
        markup = (root / "index.html").read_text(encoding="utf-8")
        app_source = (root / "app.js").read_text(encoding="utf-8")

        self.assertIn('id="app-view" class="app-view" data-shell="customer"', markup)
        self.assertIn('id="platform-sidebar"', markup)
        self.assertIn('id="customer-context-bar"', markup)
        self.assertIn('id="platform-context-bar"', markup)
        self.assertIn('href="/applications"', markup)
        self.assertIn('href="/platform/organizations"', markup)
        self.assertIn('displayApiBase', (root / "auth-flow.js").read_text(encoding="utf-8"))
        self.assertIn("const PLATFORM_HOSTNAMES = new Set", app_source)
        self.assertIn("const PLATFORM_AUTHORIZATION_AUDIENCE = 'platform'", app_source)
        self.assertIn("function requestedLoginAudience", app_source)
        self.assertIn("authorizationAudience", app_source)
        self.assertIn("function applyShellMode()", app_source)
        self.assertIn("function customerProfileList()", app_source)
        self.assertIn("function platformCapabilityForView", app_source)
        self.assertIn("function renderPlatformOrganizationsPage", app_source)
        self.assertIn("function renderSettingsPage", app_source)

    def test_dashboard_navigation_motion_is_fast_transform_only_and_reduced_safe(self):
        root = Path(__file__).resolve().parent
        styles = (root / "styles.css").read_text(encoding="utf-8")
        transition_rule = styles.split(".page-region > * {", 1)[1].split("}", 1)[0]
        entry_rule = styles.split(
            ".page-region[data-page-transition] > * {", 1
        )[1].split("}", 1)[0]
        reduced_rules = styles.split(
            "@media (prefers-reduced-motion: reduce) {", 1
        )[1]

        self.assertIn("transition: opacity 220ms var(--ease-out),", transition_rule)
        self.assertIn("transform 220ms var(--ease-out);", transition_rule)
        self.assertIn("opacity: 0;", entry_rule)
        self.assertIn("transform: translateY(8px);", entry_rule)
        self.assertNotIn("height:", transition_rule)
        self.assertNotIn("width:", transition_rule)
        self.assertIn("opacity: 1;", reduced_rules)
        self.assertIn("transform: none;", reduced_rules)

    def test_sidebar_brand_lockup_is_centered_in_header(self):
        root = Path(__file__).resolve().parent
        styles = (root / "styles.css").read_text(encoding="utf-8")
        selector = ".sidebar-header .brand-lockup {"

        self.assertIn(selector, styles)
        rule = styles.split(selector, 1)[1].split("}", 1)[0]
        self.assertIn("align-self: center;", rule)

    def test_dashboard_image_ships_local_icons_and_keeps_desktop_header_inline(self):
        root = Path(__file__).resolve().parent
        dockerfile = (root / "Dockerfile").read_text(encoding="utf-8")
        styles = (root / "styles.css").read_text(encoding="utf-8")

        self.assertIn("COPY dashboard/icons ./icons", dockerfile)
        self.assertIn("COPY dashboard/runtime-config.js .", dockerfile)
        self.assertIn("COPY LICENSE /opt/hyfens/LICENSE", dockerfile)
        self.assertIn(
            "COPY THIRD_PARTY_NOTICES.md /opt/hyfens/THIRD_PARTY_NOTICES.md",
            dockerfile,
        )
        self.assertIn(
            'ENTRYPOINT ["/usr/local/bin/hyfens-dashboard-entrypoint"]',
            dockerfile,
        )
        self.assertNotIn("ARG HYFENS_API_BASE", dockerfile)
        self.assertIn('src="runtime-config.js"', (root / "index.html").read_text(encoding="utf-8"))
        self.assertIn("__HYFENS_RUNTIME_CONFIG__", (root / "app.js").read_text(encoding="utf-8"))
        self.assertIn(".topbar-actions {\n  flex-wrap: nowrap;", styles)
        self.assertTrue((root / "icons" / "search_normal_outline.svg").is_file())
        self.assertTrue((root / "icons" / "sun_outline.svg").is_file())

    def test_dashboard_boot_gate_org_switcher_and_record_drawer_contract(self):
        root = Path(__file__).resolve().parent
        markup = (root / "index.html").read_text(encoding="utf-8")
        app_source = (root / "app.js").read_text(encoding="utf-8")
        styles = (root / "styles.css").read_text(encoding="utf-8")
        record_overlay_rule = styles.split(".record-sheet {", 1)[1].split("}", 1)[0]
        sheet_rule = styles.split(".record-sheet-dialog {", 1)[1].split("}", 1)[0]
        mobile_rules = styles.split("@media (max-width: 700px) {", 1)[1].split(
            "@media (prefers-reduced-motion: reduce)", 1
        )[0]
        sheet_open_rule = styles.split(
            "body.record-sheet-open .record-sheet-dialog,", 1
        )[1].split("}", 1)[0]
        surface_rule = styles.split(".surface-panel {", 1)[1].split("}", 1)[0]
        input_rules = (
            styles.split(
                ".auth-form input:focus,\n.auth-form input:focus-visible {", 1
            )[1].split("}", 1)[0],
            styles.split(
                "#organization-context:focus,\n.workspace-context-select select:focus {",
                1,
            )[1].split("}", 1)[0],
            styles.split("#global-search {", 1)[1].split("}", 1)[0],
            styles.split(
                "#global-search:focus,\n#global-search:focus-visible {", 1
            )[1].split("}", 1)[0],
            styles.split(
                ".collection-toolbar input,\n.collection-toolbar select {", 1
            )[1].split("}", 1)[0],
            styles.split(
                ".collection-toolbar input:hover,\n.collection-toolbar select:hover {",
                1,
            )[1].split("}", 1)[0],
            styles.split(
                ".collection-toolbar input:focus,\n.collection-toolbar input:focus-visible {",
                1,
            )[1].split("}", 1)[0],
            styles.split(
                ".context-controls select:focus,\n.context-controls select:focus-visible {",
                1,
            )[1].split("}", 1)[0],
        )

        self.assertIn('<body class="session-pending">', markup)
        self.assertIn('id="session-boot"', markup)
        self.assertIn('id="organization-context"', markup)
        self.assertIn('id="record-sheet"', markup)
        self.assertIn('role="dialog"', markup)
        self.assertIn('data-record-sheet-close', markup)
        self.assertIn("exact-record-trigger", app_source)
        self.assertIn("openRecordSheet", app_source)
        self.assertIn("organization-context", app_source)
        self.assertIn("session-pending", app_source)
        self.assertIn("body.session-pending", styles)
        self.assertIn(".session-boot", styles)
        self.assertIn(".record-sheet", styles)
        self.assertIn("align-items: stretch;", record_overlay_rule)
        self.assertIn("justify-items: end;", record_overlay_rule)
        self.assertIn("width: min(100%, 640px);", sheet_rule)
        self.assertIn("height: 100%;", sheet_rule)
        self.assertIn("max-height: none;", sheet_rule)
        self.assertIn(
            "background: rgba(var(--hyfens-void-black-rgb), 0.9);",
            sheet_rule,
        )
        self.assertIn('html[data-theme="light"] .record-sheet-dialog {', styles)
        self.assertIn("transform: translateX(100%);", sheet_rule)
        self.assertIn("transform: translateX(0);", sheet_open_rule)
        self.assertIn(".record-sheet {", mobile_rules)
        self.assertIn("align-items: end;", mobile_rules)
        self.assertIn("justify-items: stretch;", mobile_rules)
        self.assertIn("transform: translateY(14px);", mobile_rules)
        self.assertIn("transform: translateY(0);", mobile_rules)
        self.assertIn("border: 0;", surface_rule)
        for input_rule in input_rules:
            self.assertNotIn("box-shadow", input_rule)

    def test_default_collection_toolbar_omits_repeated_count(self):
        root = Path(__file__).resolve().parent
        app_source = (root / "app.js").read_text(encoding="utf-8")

        self.assertIn("if (statusText) {", app_source)
        self.assertIn(
            "if (!hasActiveFilter && !result.truncated) return null;",
            app_source,
        )

    def test_global_search_no_match_is_compact_and_neutral(self):
        root = Path(__file__).resolve().parent
        styles = (root / "styles.css").read_text(encoding="utf-8")
        app_source = (root / "app.js").read_text(encoding="utf-8")
        search_render = app_source.split(
            "function renderGlobalSearchPage()", 1
        )[1].split("function globalSearchRecordCard", 1)[0]
        state_rule = styles.split(
            '.empty-state.global-search-empty-state[data-state="no-match"] {',
            1,
        )[1].split("}", 1)[0]

        self.assertIn("noMatch.classList.add('global-search-empty-state');", search_render)
        self.assertNotIn("collection-toolbar-status", search_render)
        self.assertNotIn("Showing ${matchCount} matching records", search_render)
        self.assertIn("min-height: 0;", state_rule)
        self.assertIn("border: 0;", state_rule)
        self.assertIn("background: var(--surface-soft);", state_rule)

    def test_dashboard_keyboard_shortcuts_are_discoverable_and_guarded(self):
        root = Path(__file__).resolve().parent
        markup = (root / "index.html").read_text(encoding="utf-8")
        app_source = (root / "app.js").read_text(encoding="utf-8")
        styles = (root / "styles.css").read_text(encoding="utf-8")

        self.assertIn('id="shortcuts-button"', markup)
        self.assertIn('aria-keyshortcuts="?"', markup)
        self.assertIn('id="shortcuts-dialog"', markup)
        self.assertIn('role="dialog"', markup)
        self.assertIn("Focus record search", markup)
        self.assertIn("Refresh records", markup)
        self.assertIn("Toggle light or dark theme", markup)
        self.assertIn("function openShortcutsDialog", app_source)
        self.assertIn("function handleShortcutsDialogKeydown", app_source)
        self.assertIn("function isEditableKeyboardTarget", app_source)
        self.assertIn("input, textarea, select, [contenteditable=\"true\"]", app_source)
        self.assertIn("event.key === '?'", app_source)
        self.assertIn("event.key === '/'", app_source)
        self.assertIn("event.key.toLowerCase() === 'r'", app_source)
        self.assertIn("event.key.toLowerCase() === 't'", app_source)
        self.assertIn("document.addEventListener('keydown', handleShortcutsDialogKeydown, true)", app_source)
        self.assertIn("body.shortcuts-dialog-open", styles)
        self.assertIn(".shortcuts-dialog-panel", styles)
        self.assertIn("transform: translateY(8px) scale(0.985);", styles)
        self.assertIn(".shortcuts-dialog-panel {\n    transform: none;", styles)

    def test_dashboard_shared_spacing_and_heading_alignment_contract(self):
        root = Path(__file__).resolve().parent
        styles = (root / "styles.css").read_text(encoding="utf-8")
        heading_rule = styles.split(".heading-meta {", 1)[1].split("}", 1)[0]
        toolbar_rule = styles.split(".collection-toolbar {", 1)[1].split("}", 1)[0]
        context_rule = styles.split(".context-bar {", 1)[1].split("}", 1)[0]

        self.assertIn("align-items: baseline;", heading_rule)
        self.assertIn("margin-bottom: 0;", heading_rule)
        self.assertIn("gap: 12px;", toolbar_rule)
        self.assertNotIn("padding:", toolbar_rule)
        self.assertNotIn("border:", toolbar_rule)
        self.assertNotIn("background:", toolbar_rule)
        self.assertNotIn("border:", context_rule)

    def test_dashboard_does_not_persist_or_collect_legacy_control_credentials(self):
        root = Path(__file__).resolve().parent
        source = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (
                root / "index.html",
                root / "app.js",
                root / "styles.css",
                root / "auth-flow.js",
                root / "cli" / "authorize" / "index.html",
                root / "device" / "index.html",
            )
        )
        self.assertNotIn("localStorage", source)
        self.assertIn("sessionStorage", source)
        self.assertIn("hyfens-dashboard-session", source)
        self.assertNotIn("control-token", source)
        self.assertNotIn(
            "requiredString(root, 'access_token', 'accessToken', 'token')",
            source,
        )
        self.assertNotIn(
            "requiredString(payload, 'access_token', 'accessToken', 'token')",
            source,
        )
        self.assertNotIn("host.startsWith('127.')", source)
        self.assertIn("octets.length === 4", source)
        self.assertIn("auth/login", source)
        self.assertIn("auth/logout", source)
        self.assertIn("auth/me", source)
        self.assertIn(".well-known/hyfens", source)
        self.assertIn("readOnly", source)
        self.assertIn("code_challenge", source)
        self.assertIn("device/approve", source)
        self.assertIn('data-view-link="artifacts"', source)
        self.assertIn("artifacts: renderArtifactsPage", source)
        self.assertIn("primaryCell(pick(revision, 'revision')", source)
        self.assertNotIn("primaryCell(pick(item, 'currentRevision')", source)
        self.assertIn("#theme-toggle-label", source)
        self.assertNotIn("access_token=", source)
        self.assertNotIn("device_code=", source)
        self.assertIn('href="https://hyfens.com/"', source)
        self.assertIn('id="theme-toggle"', source)
        self.assertIn('id="account-popover"', source)
        self.assertIn('data-account-action="my-account"', source)
        self.assertIn('data-account-action="sign-out"', source)
        self.assertIn('data-placement="top"', source)
        self.assertNotIn('class="user-profile-icon"', source)
        self.assertIn('data-theme="light"', source)
        self.assertIn("nodes.contextOrganization.textContent", source)
        self.assertIn("document.addEventListener('keydown'", source)
        self.assertIn('id="cancel"', source)


if __name__ == "__main__":
    unittest.main()
