#!/usr/bin/env python3
"""Deterministic local HTTP fixture for the AlphaX Waypoint example."""

from __future__ import annotations

import argparse
import json
import logging
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlsplit


TRIPS = (
    {
        "id": "kyoto",
        "title": "Kyoto, slowly",
        "destination": "Kyoto, Japan",
        "dateRange": "12–19 Apr 2026",
        "durationLabel": "7 days · 6 nights",
        "coverLabel": "KYOTO",
        "imageAsset": "assets/images/waypoint/kyoto.svg",
        "accent": "#B7D9D0",
        "progress": 0.72,
        "itinerary": (
            {
                "time": "09:00",
                "title": "Fushimi Inari Taisha",
                "detail": "Early morning walk through the vermilion gates",
                "category": "Explore",
                "done": True,
            },
            {
                "time": "12:30",
                "title": "Lunch at Omen",
                "detail": "Handmade udon near Gion",
                "category": "Eat",
                "done": False,
            },
        ),
        "checklist": (
            {
                "title": "Reserve the tea ceremony",
                "detail": "Gion Hatanaka · 18 Apr",
                "done": True,
            },
            {
                "title": "Download rail pass",
                "detail": "Keep it available offline",
                "done": True,
            },
        ),
        "documents": (
            {
                "name": "Kyoto itinerary.pdf",
                "kind": "PDF",
                "sizeLabel": "248 KB",
                "icon": "description",
            },
        ),
    },
    {
        "id": "lisbon",
        "title": "A long weekend in Lisbon",
        "destination": "Lisbon, Portugal",
        "dateRange": "08–11 Jun 2026",
        "durationLabel": "4 days · 3 nights",
        "coverLabel": "LISBON",
        "imageAsset": "assets/images/waypoint/lisbon.svg",
        "accent": "#F3D4B2",
        "progress": 0.28,
        "itinerary": (
            {
                "time": "10:00",
                "title": "Alfama wander",
                "detail": "Tiles, viewpoints, and a slow coffee",
                "category": "Explore",
                "done": False,
            },
            {
                "time": "19:30",
                "title": "Dinner at Prado",
                "detail": "Seasonal plates and Portuguese wine",
                "category": "Eat",
                "done": False,
            },
        ),
        "checklist": (
            {
                "title": "Choose a hotel",
                "detail": "Three saved options",
                "done": True,
            },
            {
                "title": "Book the train",
                "detail": "Airport to city centre",
                "done": False,
            },
        ),
        "documents": (),
    },
)

PLACES = (
    {
        "id": "sora",
        "name": "Sora Coffee",
        "category": "Coffee · Quiet morning",
        "kind": "food",
        "location": "Higashiyama · 0.8 km",
        "country": "Kyoto, Japan",
        "description": "A tiny counter for thoughtful coffee and warm pastries.",
        "summary": "A tiny counter for thoughtful coffee and warm pastries.",
        "locationLabel": "Higashiyama · 0.8 km",
        "rating": 4.8,
        "durationLabel": "45 min",
        "distance": "8 min walk",
        "emoji": "☕",
        "accent": "#F1D6B8",
        "accentColor": "#F1D6B8",
        "imageAsset": "assets/images/waypoint/kyoto.svg",
        "tags": ("coffee", "quiet"),
        "saved": True,
    },
    {
        "id": "garden",
        "name": "Shosei-en Garden",
        "category": "Nature · Quiet route",
        "kind": "nature",
        "location": "Shimogyo · 1.4 km",
        "country": "Kyoto, Japan",
        "description": "A calm pond garden hiding behind the city streets.",
        "summary": "A calm pond garden hiding behind the city streets.",
        "locationLabel": "Shimogyo · 1.4 km",
        "rating": 4.7,
        "durationLabel": "1 hr",
        "distance": "17 min walk",
        "emoji": "🌿",
        "accent": "#C8DEC3",
        "accentColor": "#C8DEC3",
        "imageAsset": "assets/images/waypoint/kyoto.svg",
        "tags": ("nature", "quiet route"),
        "saved": False,
    },
    {
        "id": "higashiyama",
        "name": "Higashiyama walk",
        "category": "Culture · Golden hour",
        "kind": "culture",
        "location": "Gion · 2.1 km",
        "country": "Kyoto, Japan",
        "description": "A gentle route from Yasaka to the old lanes above the river.",
        "summary": "A gentle route from Yasaka to the old lanes above the river.",
        "locationLabel": "Gion · 2.1 km",
        "rating": 4.9,
        "durationLabel": "2 hr",
        "distance": "25 min walk",
        "emoji": "⛩️",
        "accent": "#D7C5E9",
        "accentColor": "#D7C5E9",
        "imageAsset": "assets/images/waypoint/kyoto.svg",
        "tags": ("culture", "golden hour"),
        "saved": True,
    },
)

ACTIVITIES = (
    {
        "id": "saved-garden",
        "title": "A new idea was saved",
        "detail": "Shosei-en Garden · Kyoto",
        "time": "Just now",
        "timeLabel": "Just now",
        "icon": "bookmark",
        "iconName": "bookmark",
        "accent": "#A7CDBE",
        "accentColor": "#A7CDBE",
    },
    {
        "id": "shared-kyoto",
        "title": "Itinerary shared with Maya",
        "detail": "Kyoto, slowly · 2 collaborators",
        "time": "8 min ago",
        "timeLabel": "8 min ago",
        "icon": "group",
        "iconName": "group",
        "accent": "#D7C5E9",
        "accentColor": "#D7C5E9",
    },
)

BANNER = {
    "id": "slow-season-edit",
    "kind": "time_limited",
    "title": "A little more time away",
    "message": "Save a flexible long-weekend plan before this edit ends.",
    "expiresAt": "2030-06-30T23:59:59Z",
    "dismissible": True,
    "action": "open_planner",
    "actionLabel": "Build a plan",
    "accentColor": "#B7D9D0",
}

ACTIONS = (
    {
        "id": "open_planner",
        "type": "bottom_sheet",
        "title": "Start a small plan",
        "subtitle": "Choose a place, a pace, and a few open days.",
        "submitLabel": "Show ideas",
    },
    {
        "id": "watch_route_preview",
        "type": "video",
        "title": "Preview the route",
        "subtitle": "See the pace before you plan.",
        "submitLabel": "Play preview",
        "asset": "assets/video/waypoint-route-preview.mp4",
    },
    {
        "id": "share_trip_note",
        "type": "form",
        "title": "Add a travel note",
        "subtitle": "Keep one small thought with the plan.",
        "submitLabel": "Save note",
    },
)

HOME = {
    "trips": TRIPS,
    "places": PLACES,
    "activities": ACTIVITIES,
    "banner": BANNER,
    "actions": ACTIONS,
}


def json_bytes(value: object) -> bytes:
    """Encode fixture responses consistently for repeatable local checks."""

    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


class WaypointRequestHandler(BaseHTTPRequestHandler):
    """Handle the small, read-only API consumed by the Waypoint app."""

    server_version = "WaypointFixture/1.0"

    def do_OPTIONS(self) -> None:  # noqa: N802 - stdlib handler API
        if urlsplit(self.path).path.startswith("/api/"):
            self.send_response(HTTPStatus.NO_CONTENT)
            self._write_common_headers()
            self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
            self.send_header(
                "Access-Control-Allow-Headers",
                "Content-Type, X-Waypoint-Client",
            )
            self.end_headers()
            return
        self._send_json(HTTPStatus.NOT_FOUND, {"error": "route not found"})

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        request_uri = urlsplit(self.path)
        route = request_uri.path

        if route == "/api/home":
            self._send_json(HTTPStatus.OK, HOME)
            return

        if route == "/api/search":
            query = parse_qs(request_uri.query, keep_blank_values=True).get(
                "q", [""]
            )[0]
            normalized_query = query.strip().casefold()
            places = [
                place
                for place in PLACES
                if not normalized_query
                or normalized_query
                in " ".join(
                    str(place[field])
                    for field in ("name", "category", "location", "country")
                ).casefold()
            ]
            self._send_json(HTTPStatus.OK, {"places": places})
            return

        if route == "/api/probe":
            self._send_json(HTTPStatus.OK, {"ok": True})
            return

        if route == "/api/activity":
            self._send_ndjson(ACTIVITIES)
            return

        trip_prefix = "/api/trips/"
        if route.startswith(trip_prefix):
            trip_id = unquote(route[len(trip_prefix) :])
            trip = next((item for item in TRIPS if item["id"] == trip_id), None)
            if trip is None or not trip_id or "/" in trip_id:
                self._send_json(
                    HTTPStatus.NOT_FOUND,
                    {"error": "trip not found", "id": trip_id},
                )
                return
            self._send_json(HTTPStatus.OK, trip)
            return

        self._send_json(HTTPStatus.NOT_FOUND, {"error": "route not found"})

    def _send_json(self, status: HTTPStatus, value: object) -> None:
        body = json_bytes(value)
        self.send_response(status)
        self._write_common_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_ndjson(self, values: tuple[object, ...]) -> None:
        body = b"".join(json_bytes(value) + b"\n" for value in values)
        self.send_response(HTTPStatus.OK)
        self._write_common_headers()
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _write_common_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")

    def log_message(self, format_string: str, *args: object) -> None:
        logging.info("%s - %s", self.address_string(), format_string % args)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8080, type=int)
    return parser.parse_args()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    arguments = parse_args()
    server = ThreadingHTTPServer(
        (arguments.host, arguments.port), WaypointRequestHandler
    )
    logging.info(
        "Waypoint fixture listening on http://%s:%d/",
        arguments.host,
        arguments.port,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logging.info("Stopping Waypoint fixture")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
